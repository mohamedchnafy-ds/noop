import Foundation
import StrandAnalytics
import WhoopStore

// Regularity (fork chantier 18, lot B, « Régularité » in the Progression screen): working sets per week over the
// last 12 weeks, and the days a session was done, as a calendar. Pure: the finished sessions and an instant in,
// the weeks out, so a test pins the counting. Weeks run Monday to Sunday (`TrainingCalendar.mondayOf`), the
// week the Training screen shows. A warm-up and a set discarded to zero reps are not working sets
// (`LiftMetrics.isPerformed`), as everywhere else sets are counted.

enum LiftRegularity {

    /// How many weeks the block shows, the current one last.
    static let weeks = 12

    struct Week: Equatable {
        /// The week's Monday, at midnight.
        var monday: Date
        var workingSets: Int
        var sessions: Int
        /// For each of its seven days (Monday first), whether a session was done that day.
        var days: [Bool]
    }

    /// The last `weeks` weeks up to the one holding `now`, oldest first.
    static func liftRegularityWeeks(_ sessions: [LiftProgress.Session], now: Date,
                                    calendar: Calendar, weeks count: Int = weeks) -> [Week] {
        let thisMonday = TrainingCalendar.mondayOf(now, calendar: calendar)
        let mondays = (0..<count).reversed().compactMap {
            calendar.date(byAdding: .day, value: -7 * $0, to: thisMonday)
        }
        var out = mondays.map { Week(monday: $0, workingSets: 0, sessions: 0, days: Array(repeating: false, count: 7)) }
        for session in sessions {
            let start = Date(timeIntervalSince1970: TimeInterval(session.row.startTs))
            let monday = TrainingCalendar.mondayOf(start, calendar: calendar)
            guard let index = out.firstIndex(where: { $0.monday == monday }) else { continue }
            let working = session.sets.filter { !$0.isWarmup && LiftMetrics.isPerformed(reps: $0.reps) }.count
            guard working > 0 else { continue }
            out[index].workingSets += working
            out[index].sessions += 1
            let weekday = TrainingCalendar.isoWeekday(calendar.startOfDay(for: start), calendar: calendar)
            if (1...7).contains(weekday) { out[index].days[weekday - 1] = true }
        }
        return out
    }

    /// Weeks in a row, ending with the current one, with at least one session. A current week with none
    /// yet does not break the run: it is not over.
    static func liftWeekStreak(_ weeks: [Week]) -> Int {
        var run = 0
        for (offset, week) in weeks.reversed().enumerated() {
            if week.sessions > 0 { run += 1 } else if offset > 0 { break }
        }
        return run
    }

    /// The average sessions per week over the weeks shown, the current one left out while it is not over.
    static func liftAverageSessions(_ weeks: [Week]) -> Double {
        let past = weeks.dropLast()
        guard !past.isEmpty else { return 0 }
        return Double(past.reduce(0) { $0 + $1.sessions }) / Double(past.count)
    }
}
