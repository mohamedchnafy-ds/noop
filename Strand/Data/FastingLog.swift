import Foundation
import StrandAnalytics
import WhoopStore

// Personal fork, chantier 15: the app's access to the intermittent fasts (`FastStore` in WhoopStore,
// migration v55-fasts) and THE ONE RESOLVER of a fast's state.
//
// The Nutrition card, the Jeûne page, the lock-screen banner, the end notification and the Coach's
// FASTING block all read `FastingLog.resolveFastingState` (or `fastingState(of:now:)` for a known row):
// no screen computes elapsed, remaining or the phase by itself, so two readouts cannot disagree
// (the Alarms lesson in AGENTS.md). The arithmetic itself is `FastingTimeline` (StrandAnalytics),
// shared byte for byte with Android.
//
// Nothing here touches the interface: callers hand in dates and minutes and get rows and figures back.

/// What a fast looks like right now, resolved once from its three stored values.
struct FastingState: Equatable {
    var fast: FastRow
    /// Minutes since the start, up to the end (ended) or `now` (running); never negative.
    var elapsedMinutes: Int
    /// Minutes left before the goal; 0 once met.
    var remainingMinutes: Int
    /// Progress toward the goal, 0…1000.
    var progressPermille: Int
    /// Index in `FastingTimeline.phaseIds` of the phase reached.
    var phaseIndex: Int
    /// Where each phase inside the goal starts on the ring.
    var markers: [FastingTimeline.Marker]
    /// The start plus the goal.
    var plannedEnd: Date
    var isRunning: Bool { fast.endedAt == nil }
    var goalReached: Bool { remainingMinutes == 0 }
    var startedAt: Date { Date(timeIntervalSince1970: TimeInterval(fast.startedAt)) }
    var endedAt: Date? { fast.endedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) } }
    var phaseId: String { FastingTimeline.phaseIds[phaseIndex] }
}

enum FastingLog {

    /// UserDefaults counter bumped on every write, so the screens that cache a state reload. Read by
    /// the Nutrition card and the Jeûne page (chantier 15 PR B).
    static let revisionKey = "fasting.revision"

    /// UserDefaults: the goal of the last fast started, minutes; the next "Start" offers it again.
    static let lastGoalKey = "fasting.lastGoalMinutes"

    @MainActor
    private static func bumpFastingRevision() {
        let defaults = UserDefaults.standard
        defaults.set(defaults.integer(forKey: revisionKey) &+ 1, forKey: revisionKey)
    }

    // MARK: Resolver

    /// The state of `fast` at `now`. PURE: tested on its own (`FastingLogTests`).
    static func fastingState(of fast: FastRow, now: Date) -> FastingState {
        let endSec = fast.endedAt ?? Int(now.timeIntervalSince1970)
        let elapsed = max(0, (endSec - fast.startedAt) / 60)
        let goal = fast.goalMinutes
        return FastingState(
            fast: fast,
            elapsedMinutes: elapsed,
            remainingMinutes: FastingTimeline.fastingRemainingMinutes(elapsedMinutes: elapsed, goalMinutes: goal),
            progressPermille: FastingTimeline.fastingProgressPermille(elapsedMinutes: elapsed, goalMinutes: goal),
            phaseIndex: FastingTimeline.fastingPhaseIndex(elapsedMinutes: elapsed),
            markers: FastingTimeline.fastingMarkers(goalMinutes: goal),
            plannedEnd: Date(timeIntervalSince1970: TimeInterval(fast.startedAt + goal * 60)))
    }

    /// The running fast resolved at `now`, or nil when nothing is running. The single entry point of
    /// every screen, banner, notification and Coach block.
    static func resolveFastingState(_ store: WhoopStore, now: Date = Date()) async -> FastingState? {
        guard let fast = try? await store.runningFast() else { return nil }
        return fastingState(of: fast, now: now)
    }

    // MARK: Writes

    /// Start a fast at `startedAt` (now, or earlier when the wearer forgot to press Start) aiming at
    /// `goalMinutes` (clamped to the bounds). A fast still running is closed at that start first, so
    /// one fast runs at a time. Remembers the goal for the next Start.
    @discardableResult
    static func startFast(_ store: WhoopStore, startedAt: Date, goalMinutes: Int, now: Date = Date()) async -> FastRow {
        let startSec = Int(startedAt.timeIntervalSince1970)
        let nowSec = Int(now.timeIntervalSince1970)
        let goal = FastingTimeline.clampGoalMinutes(goalMinutes)
        if var open = try? await store.runningFast() {
            open.endedAt = max(open.startedAt, startSec)
            open.updatedAt = nowSec
            try? await store.upsertFast(open)
        }
        let row = FastRow(id: UUID().uuidString, startedAt: startSec, endedAt: nil, goalMinutes: goal,
                          createdAt: nowSec, updatedAt: nowSec)
        try? await store.upsertFast(row)
        UserDefaults.standard.set(goal, forKey: lastGoalKey)
        await bumpFastingRevision()
        return row
    }

    /// End `fast` at `endedAt` (now, or earlier when the wearer ate before opening the app), never
    /// before its start.
    static func endFast(_ store: WhoopStore, _ fast: FastRow, endedAt: Date, now: Date = Date()) async {
        var row = fast
        row.endedAt = max(row.startedAt, Int(endedAt.timeIntervalSince1970))
        row.updatedAt = Int(now.timeIntervalSince1970)
        try? await store.upsertFast(row)
        await bumpFastingRevision()
    }

    /// Correct a fast after the fact: a new start, a new goal (clamped), or a new end for a fast that
    /// has one. `nil` keeps the stored value. The start never moves past the end.
    static func amendFast(_ store: WhoopStore, _ fast: FastRow, startedAt: Date? = nil, goalMinutes: Int? = nil,
                          endedAt: Date? = nil, now: Date = Date()) async {
        var row = fast
        if let startedAt { row.startedAt = Int(startedAt.timeIntervalSince1970) }
        if let goalMinutes { row.goalMinutes = FastingTimeline.clampGoalMinutes(goalMinutes) }
        if let endedAt, row.endedAt != nil { row.endedAt = Int(endedAt.timeIntervalSince1970) }
        if let end = row.endedAt, end < row.startedAt { row.startedAt = end }
        row.updatedAt = Int(now.timeIntervalSince1970)
        try? await store.upsertFast(row)
        await bumpFastingRevision()
    }

    /// Forget one fast.
    static func deleteFastRecord(_ store: WhoopStore, id: String) async {
        try? await store.deleteFast(id: id)
        await bumpFastingRevision()
    }

    // MARK: Reads

    /// The fasts that overlap `[from, to)`, oldest first.
    static func fasts(_ store: WhoopStore, from: Date, to: Date) async -> [FastRow] {
        (try? await store.fastsBetween(fromSec: Int(from.timeIntervalSince1970),
                                       toSec: Int(to.timeIntervalSince1970))) ?? []
    }

    /// The newest `limit` fasts, newest first.
    static func recentFastRows(_ store: WhoopStore, limit: Int) async -> [FastRow] {
        (try? await store.recentFasts(limit: limit)) ?? []
    }

    /// One duration per logical day over the last `days` days (oldest first, today last): the longest
    /// fast that ENDED that day (a running fast counts for today, up to `now`); 0 when none. PURE:
    /// `dayKey` is injected so the rule is tested without the day-cycle setting.
    static func dailyFastMinutes(_ fasts: [FastRow], days: Int, now: Date, calendar: Calendar = .current,
                                 dayKey: (Date) -> String = { Repository.logicalDayKey($0) }) -> [Int] {
        guard days > 0 else { return [] }
        var keys: [String] = []
        for back in stride(from: days - 1, through: 0, by: -1) {
            let day = calendar.date(byAdding: .day, value: -back, to: now) ?? now
            keys.append(dayKey(day))
        }
        var longest: [String: Int] = [:]
        let nowSec = Int(now.timeIntervalSince1970)
        for fast in fasts {
            let endSec = fast.endedAt ?? nowSec
            let key = dayKey(Date(timeIntervalSince1970: TimeInterval(endSec)))
            let minutes = max(0, (endSec - fast.startedAt) / 60)
            longest[key] = max(longest[key] ?? 0, minutes)
        }
        return keys.map { longest[$0] ?? 0 }
    }

    /// The history figures of the last `days` days (mean, kept, fasted, streak) against `goalMinutes`,
    /// from the fasts that ended in that window.
    static func fastingHistory(_ store: WhoopStore, days: Int, goalMinutes: Int,
                               now: Date = Date()) async -> (durations: [Int], summary: FastingTimeline.Summary) {
        let from = Calendar.current.date(byAdding: .day, value: -(days + 1), to: now) ?? now
        let rows = await fasts(store, from: from, to: now.addingTimeInterval(1))
        let durations = dailyFastMinutes(rows, days: days, now: now)
        return (durations, FastingTimeline.fastingSummary(durationsMinutes: durations, goalMinutes: goalMinutes))
    }
}
