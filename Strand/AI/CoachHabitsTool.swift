import Foundation
import WhoopStore

// MARK: - get_habits (personal fork, chantier 24, PR C)
//
// The habits the user created and their timed sessions, notes included. The Coach reads them ONLY when a
// question is about a habit: the tool is not in the fiche nor in the brief, and the role tells the model
// never to bring habits up by itself (the owner's rule, 15 Nov 2026). To cross them with the rest (sleep,
// HRV, heart rate, recovery, meals, workouts), the model calls the other read tools over the same period.
// PURE: the engine reads the rows (`AICoachEngine.runTool`), the wording is here and tested on its own.

extension CoachTools {

    /// How far back `get_habits` reads, in days.
    static let habitDayRange = 7...365

    /// The tool as sent to the model (with « Use my data » only, like every read tool).
    static var habitsDefinition: [String: Any] {
        ["name": Name.habits.rawValue,
         "description": "The habits the user created (e.g. reading, meditation, an instrument) and every session they "
            + "timed or added by hand over the last N days, oldest first: the day, start and end times, duration and "
            + "the user's own free note. Recorded on demand: no goal, no streak, and a day without a session says "
            + "nothing. Call it ONLY when the question is about a habit or its notes; never bring habits up otherwise.",
         "input_schema": [
            "type": "object",
            "properties": [
                "days": ["type": "integer", "minimum": habitDayRange.lowerBound, "maximum": habitDayRange.upperBound],
                "habit": ["type": "string", "description": "Optional: one habit's name, as the user wrote it."],
            ] as [String: Any],
            "required": ["days"],
         ] as [String: Any]]
    }

    /// `get_habits`: per habit (or the one asked for), its sessions that started in the period, with their
    /// notes. The day of a session is the day it started (the app's rule).
    static func habitsResult(_ habits: [HabitRow], sessions: [HabitSessionRow], days: Int, habitName: String?,
                             now: Date, calendar: Calendar = .current) -> String {
        guard !habits.isEmpty else {
            return "The user has created no habit yet (Habits, in the More sheet)."
        }
        let wanted = habitName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let shown = habits.filter { wanted == nil || wanted == "" || $0.name.lowercased() == wanted }
        guard !shown.isEmpty else {
            return "No habit named \"\(habitName ?? "")\". The user's habits: "
                + habits.map(\.name).joined(separator: ", ") + "."
        }
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.calendar = calendar
        dayFormatter.timeZone = calendar.timeZone
        dayFormatter.dateFormat = "yyyy-MM-dd"
        let clock = DateFormatter()
        clock.locale = Locale(identifier: "en_US_POSIX")
        clock.timeZone = calendar.timeZone
        clock.dateFormat = "HH:mm"
        let nowSec = Int(now.timeIntervalSince1970)
        var lines = ["Habits the user created and timed, last \(days) days (sessions oldest first; "
                     + "recorded on demand, no goal; notes are the user's own words):"]
        for habit in shown {
            let own = sessions.filter { $0.habitId == habit.id }
            let ended = own.filter { $0.endedAt != nil }
            let total = ended.reduce(0) { $0 + HabitLog.habitSessionSeconds($1, nowSec: nowSec) }
            lines.append("\(habit.name): \(ended.count) session(s), \(habitDuration(total)) in total.")
            for session in own {
                let start = Date(timeIntervalSince1970: TimeInterval(session.startedAt))
                let day = dayFormatter.string(from: HabitLog.habitSessionDay(session, calendar: calendar))
                var line = "  \(day) \(clock.string(from: start))"
                if let end = session.endedAt {
                    line += "-\(clock.string(from: Date(timeIntervalSince1970: TimeInterval(end))))"
                        + " (\(habitDuration(HabitLog.habitSessionSeconds(session, nowSec: nowSec))))"
                } else {
                    line += " running now (\(habitDuration(HabitLog.habitSessionSeconds(session, nowSec: nowSec))) so far)"
                }
                if session.isManual { line += " [added by hand]" }
                if let note = session.note { line += " note: \"\(note)\"" }
                lines.append(line)
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Seconds as "1h 05m" or "12m".
    private static func habitDuration(_ seconds: Int) -> String {
        let minutes = max(0, seconds) / 60
        return minutes >= 60 ? String(format: "%dh %02dm", minutes / 60, minutes % 60) : "\(minutes)m"
    }
}
