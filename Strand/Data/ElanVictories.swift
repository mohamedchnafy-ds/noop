import Foundation
import WhoopStore

// Personal fork, chantier 10 (Élan), PR B: what Élan can call a victory, and « Ce que tu as construit ».
//
// Pure rules over what the Lift Log already knows (`LiftProgress.Exercise` and its points, the week tally
// of the calendar), so Élan never states a record or a gain that Progression would not. Victoires are
// past facts, worded gently: a count of records, the longest run of weeks kept to the plan, the best gain
// of the last weeks. Nothing is computed from raw sets here.

/// One exercise's standing for « Ce que tu as construit »: the estimate now and how it moved over `weeks`.
struct ElanLiftGain: Equatable, Identifiable {
    var name: String
    /// The plotted value now (estimated 1RM, else the best load), kg.
    var nowKg: Double
    /// Now minus the first value inside the window, kg; 0 when the window holds one point.
    var gainKg: Double
    var weeks: Int
    /// When the exercise was last done (unix seconds).
    var lastTs: Int

    var id: String { name }
}

/// Weeks kept to the plan in a row: how many, ending on which week (index in the input, oldest first).
struct ElanPlanStreak: Equatable {
    var weeks: Int
    var endIndex: Int
}

/// The victories Élan lists, resolved once.
struct ElanVictories: Equatable {
    /// Records set over the last `ElanVictoryRules.recordWindowDays` days.
    var recentRecords: Int
    /// The longest run of weeks kept to the plan over the weeks given, when at least two.
    var planStreak: ElanPlanStreak?
    /// The best gain over `ElanVictoryRules.gainWeeks`, when positive.
    var bestGain: ElanLiftGain?
    /// The exercises with a gain, best first, for « Ce que tu as construit ».
    var gains: [ElanLiftGain]
}

enum ElanVictoryRules {

    /// Records are counted over the last 30 days.
    static let recordWindowDays = 30

    /// « +7 kg en 6 semaines »: the window of a gain.
    static let gainWeeks = 6

    /// At most this many exercises in « Ce que tu as construit ».
    static let gainsShown = 3

    /// A streak is worth a word from two weeks.
    static let streakMinimumWeeks = 2

    /// Records set inside the last `recordWindowDays` days ending on `today`.
    static func elanRecentRecords(_ exercises: [LiftProgress.Exercise], today: String, calendar: Calendar) -> Int {
        let floor = ElanDays.elanDay(today, adding: -(recordWindowDays - 1))
        return exercises.reduce(0) { total, exercise in
            total + exercise.points.filter { point in
                guard point.isRecord else { return false }
                let day = TrainingCalendar.trainingDayKey(Date(timeIntervalSince1970: TimeInterval(point.startTs)),
                                                          calendar: calendar)
                return day >= floor && day <= today
            }.count
        }
    }

    /// The longest run of consecutive weeks where everything planned was done (a week with nothing planned
    /// breaks the run: no plan, no promise kept). Nil under `streakMinimumWeeks`.
    static func elanPlanStreak(_ weeks: [ElanWeekTally]) -> ElanPlanStreak? {
        var best: ElanPlanStreak?
        var run = 0
        for (index, week) in weeks.enumerated() {
            if week.planned > 0 && week.done >= week.planned {
                run += 1
                if run >= streakMinimumWeeks, run > (best?.weeks ?? 0) {
                    best = ElanPlanStreak(weeks: run, endIndex: index)
                }
            } else {
                run = 0
            }
        }
        return best
    }

    /// Each exercise's gain over the last `weeks` weeks: the latest plotted value minus the first one inside
    /// the window; exercises with a single point in the window have a gain of 0. Best gain first, then the
    /// heaviest; exercises never done in the window are left out.
    static func elanLiftGains(_ exercises: [LiftProgress.Exercise], now: Int, weeks: Int = gainWeeks) -> [ElanLiftGain] {
        let start = now - weeks * 7 * 86_400
        var gains: [ElanLiftGain] = []
        for exercise in exercises {
            let points = exercise.points.filter { $0.startTs >= start && $0.value != nil }
            guard let first = points.first?.value, let last = points.last, let lastValue = last.value else { continue }
            gains.append(ElanLiftGain(name: exercise.name, nowKg: lastValue, gainKg: lastValue - first,
                                      weeks: weeks, lastTs: last.startTs))
        }
        return gains.sorted { a, b in
            if a.gainKg != b.gainKg { return a.gainKg > b.gainKg }
            return a.nowKg > b.nowKg
        }
    }

    /// The victories from Progression's exercises and the calendar's weeks (oldest first).
    static func elanVictories(exercises: [LiftProgress.Exercise], weeks: [ElanWeekTally],
                              now: Date, calendar: Calendar) -> ElanVictories {
        let today = TrainingCalendar.trainingDayKey(now, calendar: calendar)
        let gains = elanLiftGains(exercises, now: Int(now.timeIntervalSince1970))
        let best = gains.first.flatMap { $0.gainKg > 0 ? $0 : nil }
        return ElanVictories(recentRecords: elanRecentRecords(exercises, today: today, calendar: calendar),
                             planStreak: elanPlanStreak(weeks),
                             bestGain: best,
                             gains: Array(gains.prefix(gainsShown)))
    }
}
