import Foundation
import WhoopStore

// Personal fork, chantier 24: the app's access to the habits (`HabitStore` in WhoopStore, migration
// v56-habits) and THE ONE RESOLVER of a habit's figures.
//
// The Habits screen, a habit's page, the More sheet row, the Lock Screen banner, the Home Screen quick
// action and the Coach's habits tool all read through here: no screen sums durations or picks the day
// of a session by itself, so two readouts cannot disagree (the Alarms lesson in AGENTS.md).
//
// Rules (the owner's choices, 15 Nov 2026):
//   - one stopwatch at a time: starting a habit closes the one running at that instant;
//   - a session counts for the (logical) day it STARTED on, even when it runs past midnight;
//   - totals and bars count ENDED sessions only; the running one is shown by its own stopwatch;
//   - no goal, no streak, no reminder.
//
// Nothing here touches the interface: callers hand in dates and strings and get rows and figures back.

/// Why a session cannot be saved as entered (the editor greys « Add » and prints the reason).
enum HabitSessionProblem: Equatable {
    /// The end is not after the start.
    case endNotAfterStart
    /// Longer than `HabitLog.maxSessionSeconds`.
    case tooLong
    /// The end is in the future.
    case inFuture
    /// It overlaps another session of the same habit.
    case overlaps
}

/// One bar of a habit's chart: the seconds of the sessions that started in `[start, end)`.
struct HabitBar: Equatable {
    var start: Date
    var end: Date
    var seconds: Int
}

/// Which bars a habit's chart shows.
enum HabitChartPeriod: String, CaseIterable {
    /// The seven days of the current week, Monday to Sunday.
    case week
    /// The last 30 days, one bar per day.
    case month
    /// The last 12 weeks, one bar per week (Monday first).
    case quarter
}

/// A stretch of the day a session covered, in minutes since midnight (`0..<1440`), for the « When »
/// strip. A session that runs past midnight gives two stretches.
struct HabitDaySpan: Equatable {
    var startMinute: Int
    var endMinute: Int
}

/// Everything a habit's page shows, resolved once.
struct HabitFigures: Equatable {
    /// Ended sessions that started in the current week (Monday first).
    var weekSeconds: Int
    /// Ended sessions that started in the current month.
    var monthSeconds: Int
    /// Every ended session, ever.
    var allTime: HabitSessionSummary
    var weekBars: [HabitBar]
    var monthBars: [HabitBar]
    var quarterBars: [HabitBar]
    /// The time of day of the sessions of the last 30 days.
    var daySpans: [HabitDaySpan]

    func bars(_ period: HabitChartPeriod) -> [HabitBar] {
        switch period {
        case .week: weekBars
        case .month: monthBars
        case .quarter: quarterBars
        }
    }
}

enum HabitLog {

    /// UserDefaults counter bumped on every write, so the screens that cache figures reload.
    static let revisionKey = "habits.revision"

    /// UserDefaults: the id of the habit last started; the Home Screen quick action offers it.
    static let lastStartedKey = "habits.lastStartedId"

    /// The longest session the editor accepts, seconds (12 h). The stopwatch itself has no limit.
    static let maxSessionSeconds = 12 * 3_600

    /// How many sessions a habit's page lists.
    static let listedSessions = 200

    /// The palette keys a habit can take; the screens map each to a design token.
    static let colorKeys = ["cyan", "violet", "orange", "green", "blue", "pink", "yellow"]

    /// What follows a change to the habits, outside the screens (chantier 24 PR C): the Lock Screen
    /// banner and the Home Screen quick action. Registered by the iOS app root; nil elsewhere (macOS,
    /// tests), where a write only bumps the revision.
    @MainActor static var onHabitChange: (@MainActor (WhoopStore) async -> Void)?

    @MainActor
    private static func habitsDidChange(_ store: WhoopStore) async {
        let defaults = UserDefaults.standard
        defaults.set(defaults.integer(forKey: revisionKey) &+ 1, forKey: revisionKey)
        await onHabitChange?(store)
    }

    // MARK: Pure rules

    /// A note as stored: trimmed, nil when nothing is left.
    static func storedNote(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    /// A habit's name as stored: trimmed, nil when nothing is left (the editor then refuses).
    static func storedHabitName(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The seconds a session lasted: up to its end, or up to `nowSec` while it runs; never negative.
    static func habitSessionSeconds(_ session: HabitSessionRow, nowSec: Int) -> Int {
        max(0, (session.endedAt ?? nowSec) - session.startedAt)
    }

    /// Why `[startSec, endSec)` cannot be saved for a habit whose other sessions are `others`, or nil
    /// when it can. `editingId` is the session being edited (left out of the overlap check). A running
    /// session among `others` counts up to `nowSec`. PURE: tested on its own (`HabitLogTests`).
    static func habitSessionProblem(startSec: Int, endSec: Int, others: [HabitSessionRow], editingId: String?,
                                    nowSec: Int) -> HabitSessionProblem? {
        if endSec <= startSec { return .endNotAfterStart }
        if endSec > nowSec { return .inFuture }
        if endSec - startSec > maxSessionSeconds { return .tooLong }
        for other in others where other.id != editingId {
            let otherEnd = other.endedAt ?? nowSec
            if startSec < otherEnd && other.startedAt < endSec { return .overlaps }
        }
        return nil
    }

    /// The day a session counts for: the calendar midnight of the LOGICAL day of its start
    /// (`Repository.logicalDayRolloverHour` decides where a day ends).
    static func habitSessionDay(_ session: HabitSessionRow, calendar: Calendar,
                                rolloverHour: Int = Repository.logicalDayRolloverHour) -> Date {
        let start = Date(timeIntervalSince1970: TimeInterval(session.startedAt))
        return calendar.startOfDay(for: Repository.logicalDay(start, rolloverHour: rolloverHour))
    }

    /// The bars of `period` at `now`: ended sessions summed by the day (or week) they count for.
    /// PURE: tested on its own (`HabitLogTests`).
    static func habitBars(_ sessions: [HabitSessionRow], period: HabitChartPeriod, now: Date, calendar: Calendar,
                          rolloverHour: Int = Repository.logicalDayRolloverHour) -> [HabitBar] {
        let today = calendar.startOfDay(for: Repository.logicalDay(now, rolloverHour: rolloverHour))
        let thisMonday = TrainingCalendar.mondayOf(today, calendar: calendar)
        let starts: [Date]
        let step: Int
        switch period {
        case .week:
            starts = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: thisMonday) }
            step = 1
        case .month:
            starts = (0..<30).compactMap { calendar.date(byAdding: .day, value: $0 - 29, to: today) }
            step = 1
        case .quarter:
            starts = (0..<12).compactMap { calendar.date(byAdding: .day, value: 7 * ($0 - 11), to: thisMonday) }
            step = 7
        }
        var bars = starts.map { start in
            HabitBar(start: start, end: calendar.date(byAdding: .day, value: step, to: start) ?? start, seconds: 0)
        }
        for session in sessions {
            guard let end = session.endedAt else { continue }
            let day = habitSessionDay(session, calendar: calendar, rolloverHour: rolloverHour)
            if let index = bars.firstIndex(where: { $0.start <= day && day < $0.end }) {
                bars[index].seconds += max(0, end - session.startedAt)
            }
        }
        return bars
    }

    /// Where in the day `session` fell, in minutes since local midnight, split at midnight. A running
    /// session counts up to `nowSec`. PURE: tested on its own (`HabitLogTests`).
    static func habitDaySpans(_ session: HabitSessionRow, nowSec: Int, calendar: Calendar) -> [HabitDaySpan] {
        let start = Date(timeIntervalSince1970: TimeInterval(session.startedAt))
        let end = Date(timeIntervalSince1970: TimeInterval(max(session.startedAt, session.endedAt ?? nowSec)))
        var spans: [HabitDaySpan] = []
        var cursor = start
        // A session is at most a day or so; the bound keeps a corrupt row from looping.
        for _ in 0..<3 where cursor < end {
            let midnight = calendar.startOfDay(for: cursor)
            let next = calendar.date(byAdding: .day, value: 1, to: midnight) ?? end
            let stop = min(end, next)
            let from = Int(cursor.timeIntervalSince(midnight) / 60)
            let to = stop == next ? 1_440 : Int(stop.timeIntervalSince(midnight) / 60)
            if to > from { spans.append(HabitDaySpan(startMinute: from, endMinute: to)) }
            cursor = stop
        }
        return spans
    }

    /// The figures of a habit at `now` from its sessions of the last 12 weeks (at least) and its all-time
    /// summary. PURE: tested on its own (`HabitLogTests`).
    static func habitFigures(_ sessions: [HabitSessionRow], allTime: HabitSessionSummary, now: Date,
                             calendar: Calendar,
                             rolloverHour: Int = Repository.logicalDayRolloverHour) -> HabitFigures {
        let today = calendar.startOfDay(for: Repository.logicalDay(now, rolloverHour: rolloverHour))
        let monday = TrainingCalendar.mondayOf(today, calendar: calendar)
        let monthStart = TrainingCalendar.monthStart(today, calendar: calendar)
        var week = 0
        var month = 0
        for session in sessions {
            guard let end = session.endedAt else { continue }
            let day = habitSessionDay(session, calendar: calendar, rolloverHour: rolloverHour)
            let seconds = max(0, end - session.startedAt)
            if day >= monday && day <= today { week += seconds }
            if day >= monthStart && day <= today { month += seconds }
        }
        let nowSec = Int(now.timeIntervalSince1970)
        let spanFrom = calendar.date(byAdding: .day, value: -29, to: today) ?? today
        let spans = sessions
            .filter { habitSessionDay($0, calendar: calendar, rolloverHour: rolloverHour) >= spanFrom }
            .flatMap { habitDaySpans($0, nowSec: nowSec, calendar: calendar) }
        return HabitFigures(
            weekSeconds: week, monthSeconds: month, allTime: allTime,
            weekBars: habitBars(sessions, period: .week, now: now, calendar: calendar, rolloverHour: rolloverHour),
            monthBars: habitBars(sessions, period: .month, now: now, calendar: calendar, rolloverHour: rolloverHour),
            quarterBars: habitBars(sessions, period: .quarter, now: now, calendar: calendar,
                                   rolloverHour: rolloverHour),
            daySpans: spans)
    }

    /// The first instant whose sessions `habitFigures` needs: the earliest of the 12-week chart, the
    /// month and the 30-day strip, a day early so a logical day that starts before midnight is covered.
    static func habitFiguresWindowStart(now: Date, calendar: Calendar,
                                        rolloverHour: Int = Repository.logicalDayRolloverHour) -> Date {
        let today = calendar.startOfDay(for: Repository.logicalDay(now, rolloverHour: rolloverHour))
        let monday = TrainingCalendar.mondayOf(today, calendar: calendar)
        let candidates = [
            calendar.date(byAdding: .day, value: -77, to: monday) ?? monday,
            TrainingCalendar.monthStart(today, calendar: calendar),
            calendar.date(byAdding: .day, value: -29, to: today) ?? today,
        ]
        let earliest = candidates.min() ?? today
        return calendar.date(byAdding: .day, value: -1, to: earliest) ?? earliest
    }

    // MARK: Reads

    /// Every habit, in the order they were created.
    static func loadHabitList(_ store: WhoopStore) async -> [HabitRow] {
        (try? await store.allHabits()) ?? []
    }

    /// The stopwatch running, if any: the one entry point of every screen, banner and quick action.
    static func resolveRunningHabit(_ store: WhoopStore) async -> HabitSessionRow? {
        try? await store.runningHabitSession()
    }

    /// The newest sessions of a habit, newest first, for its page.
    static func loadHabitSessions(_ store: WhoopStore, habitId: String,
                                  limit: Int = listedSessions) async -> [HabitSessionRow] {
        (try? await store.recentHabitSessions(habitId: habitId, limit: limit)) ?? []
    }

    /// The sessions of every habit (or one) that started in `[from, to)`, oldest first: what the Coach's
    /// habits tool reads.
    static func loadHabitSessionsBetween(_ store: WhoopStore, from: Date, to: Date,
                                         habitId: String? = nil) async -> [HabitSessionRow] {
        (try? await store.habitSessionsStarted(fromSec: Int(from.timeIntervalSince1970),
                                               toSec: Int(to.timeIntervalSince1970), habitId: habitId)) ?? []
    }

    /// The figures of one habit at `now`, read against the store.
    static func resolveHabitFigures(_ store: WhoopStore, habitId: String, now: Date = Date(),
                                    calendar: Calendar = .current) async -> HabitFigures {
        let from = habitFiguresWindowStart(now: now, calendar: calendar)
        let sessions = await loadHabitSessionsBetween(store, from: from, to: now.addingTimeInterval(86_400),
                                                      habitId: habitId)
        let allTime = (try? await store.habitSessionSummary(habitId: habitId))
            ?? HabitSessionSummary(count: 0, totalSeconds: 0, firstStartedAt: nil)
        return habitFigures(sessions, allTime: allTime, now: now, calendar: calendar)
    }

    // MARK: Writes: habits

    /// Create a habit. Nil when the name is blank (nothing is written).
    @discardableResult
    static func createHabit(_ store: WhoopStore, name: String, colorKey: String, symbol: String,
                            now: Date = Date()) async -> HabitRow? {
        guard let stored = storedHabitName(name) else { return nil }
        let nowSec = Int(now.timeIntervalSince1970)
        let row = HabitRow(id: UUID().uuidString, name: stored, colorKey: colorKey, symbol: symbol,
                           createdAt: nowSec, updatedAt: nowSec)
        try? await store.upsertHabit(row)
        await habitsDidChange(store)
        return row
    }

    /// Rename a habit, or change its colour or symbol. False when the new name is blank (nothing is
    /// written).
    @discardableResult
    static func editHabit(_ store: WhoopStore, _ habit: HabitRow, name: String, colorKey: String, symbol: String,
                          now: Date = Date()) async -> Bool {
        guard let stored = storedHabitName(name) else { return false }
        var row = habit
        row.name = stored
        row.colorKey = colorKey
        row.symbol = symbol
        row.updatedAt = Int(now.timeIntervalSince1970)
        try? await store.upsertHabit(row)
        await habitsDidChange(store)
        return true
    }

    /// Forget a habit and all its sessions (the editor asks first, naming how many).
    static func removeHabit(_ store: WhoopStore, _ habit: HabitRow) async {
        try? await store.deleteHabitAndSessions(id: habit.id)
        if UserDefaults.standard.string(forKey: lastStartedKey) == habit.id {
            UserDefaults.standard.removeObject(forKey: lastStartedKey)
        }
        await habitsDidChange(store)
    }

    // MARK: Writes: the stopwatch

    /// Start the stopwatch of `habitId` at `startedAt`. A stopwatch still running is ended at that
    /// instant first, so one runs at a time (the screen asks before calling this).
    @discardableResult
    static func startHabitStopwatch(_ store: WhoopStore, habitId: String, startedAt: Date = Date(),
                                    now: Date = Date()) async -> HabitSessionRow {
        let startSec = Int(startedAt.timeIntervalSince1970)
        let nowSec = Int(now.timeIntervalSince1970)
        if var open = try? await store.runningHabitSession() {
            open.endedAt = max(open.startedAt, startSec)
            open.updatedAt = nowSec
            try? await store.upsertHabitSession(open)
        }
        let row = HabitSessionRow(id: UUID().uuidString, habitId: habitId, startedAt: startSec, endedAt: nil,
                                  note: nil, isManual: false, createdAt: nowSec, updatedAt: nowSec)
        try? await store.upsertHabitSession(row)
        UserDefaults.standard.set(habitId, forKey: lastStartedKey)
        await habitsDidChange(store)
        return row
    }

    /// Stop the running `session` at `endedAt` (never before its start), with an optional note. Returns
    /// the saved row.
    @discardableResult
    static func stopHabitStopwatch(_ store: WhoopStore, _ session: HabitSessionRow, endedAt: Date = Date(),
                                   note: String? = nil, now: Date = Date()) async -> HabitSessionRow {
        var row = session
        row.endedAt = max(row.startedAt, Int(endedAt.timeIntervalSince1970))
        if let note = storedNote(note) { row.note = note }
        row.updatedAt = Int(now.timeIntervalSince1970)
        try? await store.upsertHabitSession(row)
        await habitsDidChange(store)
        return row
    }

    /// « Resume » on the sheet that follows a stop: the session just stopped runs again from its own
    /// start, as if it had never stopped. Nothing happens when another stopwatch started meanwhile.
    static func resumeHabitStopwatch(_ store: WhoopStore, _ session: HabitSessionRow, now: Date = Date()) async {
        if let open = try? await store.runningHabitSession(), open.id != session.id { return }
        var row = session
        row.endedAt = nil
        row.updatedAt = Int(now.timeIntervalSince1970)
        try? await store.upsertHabitSession(row)
        await habitsDidChange(store)
    }

    // MARK: Writes: sessions after the fact

    /// The other sessions of `habitId` that could overlap `[startSec, endSec)`: those started in the
    /// 12 hours before it up to its end, plus the running one.
    private static func neighbourSessions(_ store: WhoopStore, habitId: String, startSec: Int,
                                          endSec: Int) async -> [HabitSessionRow] {
        var rows = (try? await store.habitSessionsStarted(fromSec: startSec - maxSessionSeconds,
                                                          toSec: max(endSec, startSec + 1),
                                                          habitId: habitId)) ?? []
        if let running = try? await store.runningHabitSession(), running.habitId == habitId,
           !rows.contains(where: { $0.id == running.id }) {
            rows.append(running)
        }
        return rows
    }

    /// Add a session by hand. Returns why it was refused (nothing written), or nil once saved.
    @discardableResult
    static func addHabitSessionByHand(_ store: WhoopStore, habitId: String, startedAt: Date, endedAt: Date,
                                      note: String?, now: Date = Date()) async -> HabitSessionProblem? {
        let startSec = Int(startedAt.timeIntervalSince1970)
        let endSec = Int(endedAt.timeIntervalSince1970)
        let nowSec = Int(now.timeIntervalSince1970)
        let others = await neighbourSessions(store, habitId: habitId, startSec: startSec, endSec: endSec)
        if let problem = habitSessionProblem(startSec: startSec, endSec: endSec, others: others, editingId: nil,
                                             nowSec: nowSec) {
            return problem
        }
        let row = HabitSessionRow(id: UUID().uuidString, habitId: habitId, startedAt: startSec, endedAt: endSec,
                                  note: storedNote(note), isManual: true, createdAt: nowSec, updatedAt: nowSec)
        try? await store.upsertHabitSession(row)
        await habitsDidChange(store)
        return nil
    }

    /// Correct a session: its start, its end (a session that has one) and its note (an empty note clears
    /// it). Returns why it was refused (nothing written), or nil once saved. A running session keeps
    /// running; only its start and note change, and its start must be in the past and clear of the
    /// habit's other sessions. When only the note changes, the times are not checked again.
    @discardableResult
    static func amendHabitSession(_ store: WhoopStore, _ session: HabitSessionRow, startedAt: Date,
                                  endedAt: Date?, note: String?, now: Date = Date()) async -> HabitSessionProblem? {
        let startSec = Int(startedAt.timeIntervalSince1970)
        let nowSec = Int(now.timeIntervalSince1970)
        var row = session
        row.startedAt = startSec
        if session.endedAt != nil, let endedAt { row.endedAt = Int(endedAt.timeIntervalSince1970) }
        let timesUnchanged = row.startedAt == session.startedAt && row.endedAt == session.endedAt
        if timesUnchanged {
            // Only the note changes (the note after a stop): a stopwatch left running past 12 h keeps it.
        } else if let endSec = row.endedAt {
            let others = await neighbourSessions(store, habitId: session.habitId, startSec: startSec, endSec: endSec)
            if let problem = habitSessionProblem(startSec: startSec, endSec: endSec, others: others,
                                                 editingId: session.id, nowSec: nowSec) {
                return problem
            }
        } else {
            if startSec > nowSec { return .inFuture }
            let others = await neighbourSessions(store, habitId: session.habitId, startSec: startSec, endSec: nowSec)
            let overlaps = others.contains { other in
                other.id != session.id && startSec < (other.endedAt ?? nowSec) && other.startedAt < nowSec
            }
            if overlaps { return .overlaps }
        }
        row.note = storedNote(note)
        row.updatedAt = nowSec
        try? await store.upsertHabitSession(row)
        await habitsDidChange(store)
        return nil
    }

    /// Forget one session (also « Don't keep » on a stopwatch just stopped or running).
    static func removeHabitSession(_ store: WhoopStore, _ session: HabitSessionRow) async {
        try? await store.deleteHabitSession(id: session.id)
        await habitsDidChange(store)
    }
}
