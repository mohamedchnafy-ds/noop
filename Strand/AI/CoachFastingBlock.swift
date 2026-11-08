import Foundation
import StrandAnalytics
import WhoopStore

// Personal fork, chantier 15 PR C: the FASTING block of the Coach's fiche, and the fasting chips of the
// empty Coach screen. Everything is read through the one resolver (`FastingLog`) and the hydration
// store, so the Coach states the figures the Jeûne page shows: the fast running (or the last one over),
// the last 7 days as the history card counts them, today's water against its goal.

extension CoachFiche {

    /// The fast as the Jeûne page shows it. Nil when fasting is not used: no fast running and none in
    /// the last 7 days (the block is then left out of the context).
    struct Fasting: Equatable {
        struct Running: Equatable {
            var startedAt: Date
            var elapsedMinutes: Int
            var goalMinutes: Int
            var remainingMinutes: Int
            var plannedEnd: Date
            var phaseIndex: Int
        }

        struct Last: Equatable {
            var startedAt: Date
            var endedAt: Date
            var durationMinutes: Int
            var goalMinutes: Int
        }

        var running: Running?
        /// The newest fast over, when none runs.
        var last: Last?
        /// The last 7 days as `FastingLog.fastingHistory` counts them.
        var weekSummary: FastingTimeline.Summary
        var weekDays: Int
        var weekGoalMinutes: Int
        var waterML: Double
        var waterGoalML: Int
    }

    /// English names of the phases for the Coach, in `FastingTimeline.phaseIds` order (the screens use the
    /// localized `FastingPhaseText`; the context is English like the rest of the fiche).
    static let fastingPhaseNames = ["digestion", "insulin dropping", "glycogen running low", "fat burning",
                                    "ketosis", "autophagy"]

    /// "2026-11-07 20:30", 24-hour, in `timeZone`: the coach reads it, not the user.
    static func fastingStamp(_ date: Date, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: date)
    }

    static func fastingBlock(_ f: Fasting, timeZone: TimeZone = .current) -> String {
        var lines = ["FASTING (intermittent fasting as the Jeûne page shows it; the phases are indicative landmarks "
                     + "of the general literature, not a measurement and not medical advice):"]
        if let r = f.running {
            let phase = fastingPhaseNames[min(max(r.phaseIndex, 0), fastingPhaseNames.count - 1)]
            let starts = FastingTimeline.phaseStartHours
            let range = r.phaseIndex + 1 < starts.count
                ? "\(starts[r.phaseIndex])–\(starts[r.phaseIndex + 1]) h" : "\(starts[r.phaseIndex]) h+"
            var line = "  running since \(fastingStamp(r.startedAt, timeZone: timeZone)): "
                + "\(duration(Double(r.elapsedMinutes))) done out of \(duration(Double(r.goalMinutes)))"
            if r.remainingMinutes > 0 {
                line += ", \(duration(Double(r.remainingMinutes))) left, planned end \(fastingStamp(r.plannedEnd, timeZone: timeZone))"
            } else {
                line += ", goal reached (\(duration(Double(r.elapsedMinutes - r.goalMinutes))) past it)"
            }
            line += ", phase \(phase) (\(range))"
            lines.append(line)
        } else if let l = f.last {
            let kept = l.durationMinutes >= l.goalMinutes ? "goal kept" : "stopped \(duration(Double(l.goalMinutes - l.durationMinutes))) before the goal"
            lines.append("  no fast running; last fast \(fastingStamp(l.startedAt, timeZone: timeZone)) → "
                         + "\(fastingStamp(l.endedAt, timeZone: timeZone)), \(duration(Double(l.durationMinutes))) "
                         + "out of \(duration(Double(l.goalMinutes))) (\(kept))")
        } else {
            lines.append("  no fast running")
        }
        let s = f.weekSummary
        var week = "  last \(f.weekDays) days: fasted \(s.fastedCount) of \(f.weekDays) days"
        if s.fastedCount > 0 {
            week += ", goal (\(duration(Double(f.weekGoalMinutes)))) kept \(s.keptCount), mean \(duration(Double(s.averageMinutes)))"
                + ", streak \(s.streak) day\(s.streak == 1 ? "" : "s")"
        }
        lines.append(week)
        lines.append("  water today: \(litres(f.waterML)) of \(litres(Double(f.waterGoalML))) goal")
        return lines.joined(separator: "\n")
    }

    /// "1.25 L" (two decimals at most, the trailing zeros dropped).
    static func litres(_ ml: Double) -> String {
        let value = max(0, ml) / 1000
        var text = String(format: "%.2f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text + " L"
    }
}

extension CoachPrompts {

    /// The fasting chips of an empty conversation (Mohamed, 8 Nov.): « What should I eat to break my fast? »
    /// while a fast runs, « My fasting this week » when the last 7 days hold a fast. None otherwise, so the
    /// six usual chips stay alone for a wearer who does not fast.
    static func fastingQuickPrompts(running: Bool, hasWeekHistory: Bool) -> [QuickPrompt] {
        var out: [QuickPrompt] = []
        if running {
            out.append(QuickPrompt(label: String(localized: "What should I eat to break my fast?"),
                                   question: String(localized: "What should I eat to break my fast?")))
        }
        if hasWeekHistory {
            out.append(QuickPrompt(label: String(localized: "My fasting this week"),
                                   question: String(localized: "How did my fasting go this week?")))
        }
        return out
    }
}

extension AICoachEngine {

    /// The fiche's FASTING block inputs, from the one resolver and the hydration store. Nil without a store,
    /// or when fasting is not used (nothing running, nothing in the last 7 days).
    func fastingFiche(now: Date = Date()) async -> CoachFiche.Fasting? {
        guard let store = await repo.storeHandle() else { return nil }
        let running = await FastingLog.resolveFastingState(store, now: now)
        var newest: FastRow?
        if running == nil { newest = await FastingLog.recentFastRows(store, limit: 1).first }
        // The goal the history is counted against: the fast's, else the last one picked, else 16 h.
        let stored = UserDefaults.standard.integer(forKey: FastingLog.lastGoalKey)
        let goal = running?.fast.goalMinutes ?? newest?.goalMinutes
            ?? (stored > 0 ? FastingTimeline.clampGoalMinutes(stored) : FastingTimeline.defaultGoalMinutes)
        let week = await FastingLog.fastingHistory(store, days: 7, goalMinutes: goal, now: now)
        guard running != nil || week.summary.fastedCount > 0 else { return nil }
        var last: CoachFiche.Fasting.Last?
        if let newest, let end = newest.endedAt {
            last = CoachFiche.Fasting.Last(startedAt: Date(timeIntervalSince1970: TimeInterval(newest.startedAt)),
                                           endedAt: Date(timeIntervalSince1970: TimeInterval(end)),
                                           durationMinutes: max(0, (end - newest.startedAt) / 60),
                                           goalMinutes: newest.goalMinutes)
        }
        let dayKey = Repository.logicalDayKey(now)
        return CoachFiche.Fasting(
            running: running.map {
                CoachFiche.Fasting.Running(startedAt: $0.startedAt, elapsedMinutes: $0.elapsedMinutes,
                                           goalMinutes: $0.fast.goalMinutes, remainingMinutes: $0.remainingMinutes,
                                           plannedEnd: $0.plannedEnd, phaseIndex: $0.phaseIndex)
            },
            last: last, weekSummary: week.summary, weekDays: 7, weekGoalMinutes: goal,
            waterML: await repo.hydrationTotal(day: dayKey),
            waterGoalML: repo.hydrationGoalML(profileSex: profile?.sex ?? ""))
    }

    /// The fasting chips of the empty screen, from the same reading as the fiche.
    func fastingQuickPrompts(now: Date = Date()) async -> [CoachPrompts.QuickPrompt] {
        guard let fasting = await fastingFiche(now: now) else { return [] }
        return CoachPrompts.fastingQuickPrompts(running: fasting.running != nil,
                                                hasWeekHistory: fasting.weekSummary.fastedCount > 0)
    }
}
