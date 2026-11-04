import Foundation
import WhoopStore

// Personal fork (mockup « Historique », 4 Nov.): the history screen's summary card and its « By sport »
// bars. Pure: the windowed workout rows go in, the figures and the bars come out, so the rules are pinned
// by tests.

/// What a workout counts as in the history's bars: cardio (pink), a strength session (blue), the rest (cyan).
enum WorkoutHistoryKind: Equatable {
    case cardio, lift, other
}

/// One bar of the summary card: a day, a week or a month, and its minutes by kind.
struct WorkoutHistoryBar: Equatable {
    /// Midnight of the bar's first day.
    var start: Date
    var cardioMinutes: Int
    var liftMinutes: Int
    var otherMinutes: Int

    var totalMinutes: Int { cardioMinutes + liftMinutes + otherMinutes }
}

/// How long a bar of the summary card is.
enum WorkoutHistoryBarUnit: Equatable {
    case day, week, month
}

/// One line of « By sport »: a sport (as stored) and its sessions, minutes and calories over the window.
struct WorkoutHistorySport: Equatable {
    var sport: String
    var kind: WorkoutHistoryKind
    var sessions: Int
    var minutes: Int
    var kcal: Int
}

enum WorkoutHistoryLogic {
    /// Strength sports: the Lift Log's own rows ("Strength Training"), the catalogue's and the strap's.
    static let liftSportNames: Set<String> = [
        "Strength", "Bodybuilding", "Weightlifting", "Strength Training", "Traditional Strength Training",
        "Functional Strength Training",
    ]
    /// Cardio sports: the catalogue's endurance sports and the strap's usual names for them.
    static let cardioSportNames: Set<String> = [
        "Running", "Walking", "Hiking", "Cycling", "Open-water swim", "Rowing", "Treadmill run", "Treadmill walk",
        "Indoor cycle", "Pool swim", "Row machine", "Elliptical", "HIIT", "Swimming", "Spin", "Stairmaster",
        "Assault Bike", "Hiking/Rucking",
    ]
    /// The most bars a « month » chart draws (the « All » range keeps the last two years in the chart).
    static let maxMonthBars = 24

    /// The kind of a stored sport, whatever its spelling ("TraditionalStrengthTraining", "running"); an
    /// imported lifting session is a strength session whatever its label.
    static func workoutKind(sport: String, source: String) -> WorkoutHistoryKind {
        if WorkoutSource.classify(source) == .lifting { return .lift }
        let name = WorkoutSource.editableSport(sport).trimmingCharacters(in: .whitespaces)
        func contains(_ set: Set<String>) -> Bool {
            set.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
        }
        if contains(liftSportNames) { return .lift }
        if contains(cardioSportNames) { return .cardio }
        return .other
    }

    /// A workout's length in minutes: its stored duration, else end − start.
    static func workoutMinutes(_ row: WorkoutRow) -> Int {
        if let seconds = row.durationS, seconds > 0 { return Int((seconds / 60).rounded()) }
        return max(0, row.endTs - row.startTs) / 60
    }

    /// The bar length for a window of `days` days (nil = all): a day up to a month, a week for a quarter,
    /// a month beyond.
    static func barUnit(days: Int?) -> WorkoutHistoryBarUnit {
        guard let days else { return .month }
        if days <= 31 { return .day }
        if days <= 92 { return .week }
        return .month
    }

    /// The summary card's bars, oldest first, ending with the one holding `anchorTs` (the latest session:
    /// the window is relative to it, as the rows are). `days` days back for a dated window (weeks start on
    /// Monday); for « All », the months from the oldest row, at most `maxMonthBars`.
    static func historyBars(_ rows: [WorkoutRow], days: Int?, anchorTs: Int, calendar: Calendar) -> [WorkoutHistoryBar] {
        let anchor = calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(anchorTs)))
        let unit = barUnit(days: days)
        func barStart(_ date: Date) -> Date {
            switch unit {
            case .day: return calendar.startOfDay(for: date)
            case .week: return TrainingCalendar.mondayOf(date, calendar: calendar)
            case .month: return TrainingCalendar.monthStart(date, calendar: calendar)
            }
        }
        func step(_ date: Date, by count: Int) -> Date {
            let component: Calendar.Component = unit == .day ? .day : unit == .week ? .weekOfYear : .month
            return calendar.date(byAdding: component, value: count, to: date) ?? date
        }
        let last = barStart(anchor)
        let count: Int
        if let days {
            switch unit {
            case .day: count = days
            case .week: count = Int((Double(days) / 7).rounded(.up))
            case .month: count = Int((Double(days) / 30.44).rounded())
            }
        } else {
            let oldest = rows.map(\.startTs).min() ?? anchorTs
            let first = barStart(Date(timeIntervalSince1970: TimeInterval(oldest)))
            let months = calendar.dateComponents([.month], from: first, to: last).month ?? 0
            count = min(maxMonthBars, months + 1)
        }
        let starts = (0..<max(1, count)).reversed().map { step(last, by: -$0) }
        var bars = starts.map { WorkoutHistoryBar(start: $0, cardioMinutes: 0, liftMinutes: 0, otherMinutes: 0) }
        let index = Dictionary(starts.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        for row in rows {
            guard let at = index[barStart(Date(timeIntervalSince1970: TimeInterval(row.startTs)))] else { continue }
            let minutes = workoutMinutes(row)
            switch workoutKind(sport: row.sport, source: row.source) {
            case .cardio: bars[at].cardioMinutes += minutes
            case .lift: bars[at].liftMinutes += minutes
            case .other: bars[at].otherMinutes += minutes
            }
        }
        return bars
    }

    /// « By sport »: one line per sport (as stored), most minutes first, then most sessions, then the name.
    static func historySports(_ rows: [WorkoutRow]) -> [WorkoutHistorySport] {
        var bySport: [String: WorkoutHistorySport] = [:]
        for row in rows {
            var line = bySport[row.sport]
                ?? WorkoutHistorySport(sport: row.sport, kind: workoutKind(sport: row.sport, source: row.source),
                                       sessions: 0, minutes: 0, kcal: 0)
            line.sessions += 1
            line.minutes += workoutMinutes(row)
            line.kcal += Int((row.energyKcal ?? 0).rounded())
            bySport[row.sport] = line
        }
        return bySport.values.sorted { a, b in
            if a.minutes != b.minutes { return a.minutes > b.minutes }
            if a.sessions != b.sessions { return a.sessions > b.sessions }
            return a.sport < b.sport
        }
    }

    /// Minutes as the summary writes them: « 2h 36m », « 45 min » (the catalogue's existing forms).
    static func historyDuration(minutes: Int) -> String {
        let total = max(0, minutes)
        if total < 60 { return String(localized: "\(total) min") }
        return String(localized: "\(total / 60)h \(total % 60)m")
    }
}
