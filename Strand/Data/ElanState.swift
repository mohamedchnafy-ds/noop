import Foundation
import WhoopStore

// Personal fork, chantier 10 (Élan), PR A: THE ONE resolver of what Élan states, read by the Élan screen
// (its three tabs), the Plus row's status line and, later, the reminders and the short session (PR C).
//
// The rules are pure (`ElanResolver`: day marks, the missed session of yesterday, the week recap, the
// « Avant / maintenant » windows, the « jour Nutrition tenu » rule) and read one day-keyed `ElanLedger`;
// `loadElanState` fills that ledger from the same reads the Training screen, Progression and Nutrition
// use (`TrainingSnapshot`, `LiftProgressData`, the `noop-nutrition` series, `Repository.days`), so no
// figure of Élan can disagree with the screen that owns it. Nothing here touches the interface.

/// Day-key arithmetic for Élan ("yyyy-MM-dd"), on a fixed Gregorian UTC calendar so two keys are the same
/// number of days apart whatever the device's zone or locale.
enum ElanDays {
    private static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC") ?? .current
        return c
    }()

    /// The key as a date at UTC midnight; nil for a malformed key.
    static func elanDate(_ key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// Whole days from `from` to `to` (negative when `to` is earlier); nil when a key is malformed.
    static func elanDaysBetween(_ from: String, _ to: String) -> Int? {
        guard let a = elanDate(from), let b = elanDate(to) else { return nil }
        return calendar.dateComponents([.day], from: a, to: b).day
    }

    /// The key `days` days after `key` (negative = before); the key itself when malformed.
    static func elanDay(_ key: String, adding days: Int) -> String {
        guard let date = elanDate(key),
              let moved = calendar.date(byAdding: .day, value: days, to: date) else { return key }
        let p = calendar.dateComponents([.year, .month, .day], from: moved)
        return String(format: "%04d-%02d-%02d", p.year ?? 0, p.month ?? 0, p.day ?? 0)
    }
}

/// How a day of the week stands on Élan's « Cette semaine » row.
enum ElanDayMark: Equatable {
    /// A session was done (a Lift Log session, or a planned item matched).
    case done
    /// Planned and still to do, later this week.
    case planned
    /// Planned, not done, and the day is over.
    case missed
    /// Today, nothing done yet.
    case today
    /// Today, the short session accepted for tonight (the sand mark).
    case todayShort
    /// Nothing planned, nothing done.
    case rest
}

struct ElanWeekDay: Equatable {
    var key: String
    var mark: ElanDayMark
}

/// The program yesterday's plan held and that was not done: what « Jamais deux fois de suite » is about.
struct ElanMissedSession: Equatable {
    var programId: String
    var name: String
    var day: String
}

/// « Cette semaine »: the seven days, the tally, Nutrition held, the average night and the weigh-ins.
struct ElanWeekRecap: Equatable {
    var days: [ElanWeekDay]
    var done: Int
    var planned: Int
    var nutritionHeldDays: Int
    var nutritionLoggedDays: Int
    var averageNightMinutes: Double?
    var weighIns: Int
}

/// One window of « Avant / maintenant »: its figures over `startDay`…`endDay` (both inclusive).
struct ElanWindow: Equatable {
    var startDay: String
    var endDay: String
    var sessions: Int
    var sets: Int
    var records: Int
    var nutritionHeld: Int
    var nutritionLogged: Int
    var averageNightMinutes: Double?

    var days: Int { (ElanDays.elanDaysBetween(startDay, endDay) ?? 0) + 1 }
    var sessionsPerWeek: Double { Double(sessions) * 7 / Double(max(1, days)) }
    var setsPerWeek: Double { Double(sets) * 7 / Double(max(1, days)) }
}

/// « Quand tu étais lancé » (the best four weeks of the last six months, before the recent window) beside
/// « Ces 3 semaines ». `launched` is nil when no four weeks reach `ElanResolver.launchedMinimumSessions`.
struct ElanComparison: Equatable {
    var launched: ElanWindow?
    var recent: ElanWindow
}

/// Sessions done and planned over one week of the calendar (`TrainingDays.sessionTally`).
struct ElanWeekTally: Equatable {
    var done: Int
    var planned: Int
}

/// One of the last seven days on the Poids page: held, not held, or nothing logged.
struct ElanNutritionDay: Equatable {
    enum Status: Equatable { case held, missed, none }
    var day: String
    var status: Status
}

/// What Élan states, resolved once.
struct ElanState: Equatable {
    var today: String
    /// Yesterday's planned program left undone, whatever the wearer chose about it.
    var missedYesterday: ElanMissedSession?
    /// « Pas aujourd'hui » was tapped today.
    var shortSessionDismissed: Bool
    /// The program whose short version was accepted for tonight, when one was.
    var shortSessionAccepted: String?
    /// Days since the last session day (0 = one today); nil when none is known.
    var daysSinceLastSession: Int?
    var week: ElanWeekRecap
    var comparison: ElanComparison
    var weight: ElanWeightSummary
    var why: String?
    /// The last `ElanResolver.tallyWeeks` weeks, oldest first, the current week last (Victoires' streak).
    var recentWeeks: [ElanWeekTally] = []
    /// The last seven days, oldest first (the Poids page's « Jours Nutrition tenus »).
    var nutritionWeek: [ElanNutritionDay] = []
}

/// The day-keyed inputs the pure rules read: what was done, eaten, slept and weighed, by local day.
struct ElanLedger: Equatable {
    /// One entry per session: a Lift Log session, or a cardio workout of at least
    /// `ElanResolver.cardioMinimumMinutes`.
    var sessionDays: [String]
    /// Working sets of the Lift Log sessions, by day.
    var setsByDay: [String: Int]
    /// One entry per record (`LiftProgress.Point.isRecord`), the day it was set.
    var recordDays: [String]
    /// The meal journal's day totals, kcal (`NutritionSeries`: a day with no meal has no entry).
    var kcalByDay: [String: Int]
    /// The current intake goal, kcal; nil or 0 when none applies.
    var goalKcal: Int?
    /// Minutes slept, by day, the days with a night only.
    var sleepMinutesByDay: [String: Double]
    var weighIns: [ElanWeighIn]
}

enum ElanResolver {

    // MARK: Tunables

    /// « Ces 3 semaines »: the days before today the recent window spans.
    static let recentDays = 21
    /// « Quand tu étais lancé »: the length of the best window.
    static let launchedDays = 28
    /// How far back the best window is looked for.
    static let lookbackDays = 182
    /// Under this many sessions, no four weeks count as « lancé » (there was no momentum to compare with).
    static let launchedMinimumSessions = 4
    /// A cardio workout shorter than this is not a session.
    static let cardioMinimumMinutes = 15
    /// How much history the loader reads.
    static let historyDays = 190
    /// Weeks of tallies kept for Victoires' streak.
    static let tallyWeeks = 26

    // MARK: Rules

    /// « Tenu »: the day's intake is within 10 % of the intake goal (Nutrition → Objectifs). Integer
    /// arithmetic, so 1 800 holds a 2 000 goal and 1 799 does not.
    static func elanNutritionHeld(kcal: Int, goalKcal: Int) -> Bool {
        goalKcal > 0 && abs(kcal - goalKcal) * 10 <= goalKcal
    }

    /// The mark of one day of the week.
    static func elanDayMark(_ day: TrainingDay, shortAccepted: Bool) -> ElanDayMark {
        let doneSomething = !day.lifts.isEmpty || day.planned.contains(where: \.isDone)
        if day.isToday {
            if doneSomething { return .done }
            return shortAccepted ? .todayShort : .today
        }
        if doneSomething { return .done }
        if day.isMissed { return .missed }
        if day.isPlannedOpen { return .planned }
        return .rest
    }

    static func elanWeekDays(_ days: [TrainingDay], shortAccepted: Bool) -> [ElanWeekDay] {
        days.map { ElanWeekDay(key: $0.key, mark: elanDayMark($0, shortAccepted: shortAccepted)) }
    }

    /// Yesterday's first planned program left undone, named; nil when yesterday was not missed (cardio
    /// left undone proposes no short session).
    static func elanMissedYesterday(_ yesterday: TrainingDay?, programNames: [String: String]) -> ElanMissedSession? {
        guard let yesterday, yesterday.isMissed, let id = yesterday.openProgramIds.first else { return nil }
        return ElanMissedSession(programId: id, name: programNames[id] ?? String(localized: "Session"),
                                 day: yesterday.key)
    }

    /// Days since the last session day on or before `today` (0 = a session today); nil without one.
    static func elanDaysSinceLastSession(sessionDays: [String], today: String) -> Int? {
        guard let last = sessionDays.filter({ $0 <= today }).max() else { return nil }
        return ElanDays.elanDaysBetween(last, today)
    }

    /// Logged days and held days over `from`…`to`.
    static func elanNutritionTally(_ ledger: ElanLedger, from: String, to: String) -> (held: Int, logged: Int) {
        var held = 0
        var logged = 0
        for (day, kcal) in ledger.kcalByDay where day >= from && day <= to {
            logged += 1
            if let goal = ledger.goalKcal, elanNutritionHeld(kcal: kcal, goalKcal: goal) { held += 1 }
        }
        return (held, logged)
    }

    /// The average night over `from`…`to`, the days with a night only; nil without one.
    static func elanAverageNight(_ ledger: ElanLedger, from: String, to: String) -> Double? {
        let nights = ledger.sleepMinutesByDay
            .filter { $0.key >= from && $0.key <= to && $0.value > 0 }
            .map(\.value)
        guard !nights.isEmpty else { return nil }
        return nights.reduce(0, +) / Double(nights.count)
    }

    /// The figures of one window.
    static func elanWindow(_ ledger: ElanLedger, from: String, to: String) -> ElanWindow {
        let nutrition = elanNutritionTally(ledger, from: from, to: to)
        let sets = ledger.setsByDay.filter { $0.key >= from && $0.key <= to }.values.reduce(0, +)
        return ElanWindow(startDay: from, endDay: to,
                          sessions: ledger.sessionDays.filter { $0 >= from && $0 <= to }.count,
                          sets: sets,
                          records: ledger.recordDays.filter { $0 >= from && $0 <= to }.count,
                          nutritionHeld: nutrition.held, nutritionLogged: nutrition.logged,
                          averageNightMinutes: elanAverageNight(ledger, from: from, to: to))
    }

    /// « Cette semaine » over the seven `days` of the calendar (Monday first).
    static func elanWeekRecap(days: [TrainingDay], ledger: ElanLedger, shortAccepted: Bool) -> ElanWeekRecap {
        let tally = TrainingDays.sessionTally(days)
        let from = days.first?.key ?? ""
        let to = days.last?.key ?? ""
        let nutrition = elanNutritionTally(ledger, from: from, to: to)
        let weighIns = ElanWeight.dedupe(ledger.weighIns).filter { $0.day >= from && $0.day <= to }.count
        return ElanWeekRecap(days: elanWeekDays(days, shortAccepted: shortAccepted),
                             done: tally.done, planned: tally.planned,
                             nutritionHeldDays: nutrition.held, nutritionLoggedDays: nutrition.logged,
                             averageNightMinutes: elanAverageNight(ledger, from: from, to: to),
                             weighIns: weighIns)
    }

    /// « Avant / maintenant »: the recent window is the `recentDays` days before `today`; « lancé » is the
    /// `launchedDays`-day window ending before it, inside `lookbackDays`, with the most sessions (then the
    /// most sets; the most recent among equals), when it has `launchedMinimumSessions`.
    static func elanComparison(_ ledger: ElanLedger, today: String) -> ElanComparison {
        let recentEnd = ElanDays.elanDay(today, adding: -1)
        let recentStart = ElanDays.elanDay(today, adding: -recentDays)
        let recent = elanWindow(ledger, from: recentStart, to: recentEnd)
        let floor = ElanDays.elanDay(today, adding: -lookbackDays)
        var best: ElanWindow?
        var end = ElanDays.elanDay(recentStart, adding: -1)
        while true {
            let start = ElanDays.elanDay(end, adding: -(launchedDays - 1))
            if start < floor { break }
            let window = elanWindow(ledger, from: start, to: end)
            if let current = best {
                if window.sessions > current.sessions
                    || (window.sessions == current.sessions && window.sets > current.sets) {
                    best = window
                }
            } else {
                best = window
            }
            end = ElanDays.elanDay(end, adding: -1)
        }
        if let best, best.sessions >= launchedMinimumSessions {
            return ElanComparison(launched: best, recent: recent)
        }
        return ElanComparison(launched: nil, recent: recent)
    }

    /// The last seven days ending on `today`, oldest first, against the ledger's meals and goal.
    static func elanNutritionWeek(_ ledger: ElanLedger, today: String) -> [ElanNutritionDay] {
        (0..<7).reversed().map { back in
            let day = ElanDays.elanDay(today, adding: -back)
            guard let kcal = ledger.kcalByDay[day] else { return ElanNutritionDay(day: day, status: .none) }
            if let goal = ledger.goalKcal, elanNutritionHeld(kcal: kcal, goalKcal: goal) {
                return ElanNutritionDay(day: day, status: .held)
            }
            return ElanNutritionDay(day: day, status: .missed)
        }
    }

    /// The ledger from the store's rows, by the calendar's local day. `nights` are the banked days' sleep
    /// (`DailyMetric.totalSleepMin`); a day without one is left out.
    static func elanLedger(lifts: [TrainingLiftDone], activities: [TrainingActivityDone], recordTimestamps: [Int],
                           kcal: [(day: String, kcal: Int)], goalKcal: Int?, nights: [(day: String, minutes: Double?)],
                           weighIns: [ElanWeighIn], calendar: Calendar) -> ElanLedger {
        func key(_ ts: Int) -> String {
            TrainingCalendar.trainingDayKey(Date(timeIntervalSince1970: TimeInterval(ts)), calendar: calendar)
        }
        var sessionDays = lifts.map { key($0.startTs) }
        for activity in activities where activity.minutes >= cardioMinimumMinutes {
            if WorkoutHistoryLogic.workoutKind(sport: activity.sport, source: "") == .cardio {
                sessionDays.append(key(activity.startTs))
            }
        }
        var setsByDay: [String: Int] = [:]
        for lift in lifts { setsByDay[key(lift.startTs), default: 0] += lift.workingSets }
        var kcalByDay: [String: Int] = [:]
        for entry in kcal { kcalByDay[entry.day] = entry.kcal }
        var sleep: [String: Double] = [:]
        for night in nights {
            if let minutes = night.minutes, minutes > 0 { sleep[night.day] = minutes }
        }
        return ElanLedger(sessionDays: sessionDays.sorted(), setsByDay: setsByDay,
                          recordDays: recordTimestamps.map(key).sorted(),
                          kcalByDay: kcalByDay, goalKcal: goalKcal, sleepMinutesByDay: sleep, weighIns: weighIns)
    }
}

// MARK: - The wearer's choice about the short session, per day

/// « Pas aujourd'hui » and « Ce soir · l'ajouter à aujourd'hui » are remembered for the day only: a new day
/// starts clean. UserDefaults; a choice is not data.
enum ElanShortSessionChoice {
    static let dismissedDayKey = "elan.shortSession.dismissedDay"
    static let acceptedDayKey = "elan.shortSession.acceptedDay"
    static let acceptedProgramKey = "elan.shortSession.acceptedProgramId"

    static func isDismissed(day: String, _ d: UserDefaults = .standard) -> Bool {
        d.string(forKey: dismissedDayKey) == day
    }

    static func dismiss(day: String, _ d: UserDefaults = .standard) {
        d.set(day, forKey: dismissedDayKey)
    }

    /// The program accepted for `day`, nil when none (or another day's acceptance).
    static func acceptedProgramId(day: String, _ d: UserDefaults = .standard) -> String? {
        guard d.string(forKey: acceptedDayKey) == day else { return nil }
        return d.string(forKey: acceptedProgramKey)
    }

    static func accept(day: String, programId: String, _ d: UserDefaults = .standard) {
        d.set(day, forKey: acceptedDayKey)
        d.set(programId, forKey: acceptedProgramKey)
        d.removeObject(forKey: dismissedDayKey)
    }

    /// « Retirer »: the accepted session is dropped and not proposed again that day.
    static func withdraw(day: String, _ d: UserDefaults = .standard) {
        d.removeObject(forKey: acceptedDayKey)
        d.removeObject(forKey: acceptedProgramKey)
        d.set(day, forKey: dismissedDayKey)
    }
}

// MARK: - Loader

extension ElanResolver {

    /// Élan's state from the store, read as the Training screen, Progression and Nutrition read theirs. Nil
    /// when the store is not open.
    @MainActor
    static func loadElanState(repo: Repository, profile: ProfileStore, now: Date = Date(),
                              calendar: Calendar = .current, defaults: UserDefaults = .standard,
                              progress preloaded: LiftProgressData? = nil) async -> ElanState? {
        guard let snapshot = await TrainingSnapshot.loadTrainingSnapshot(repo: repo, historyDays: historyDays,
                                                                         effortScale: .hundred, now: now)
        else { return nil }
        let today = TrainingCalendar.trainingDayKey(now, calendar: calendar)
        let monday = TrainingCalendar.mondayOf(now, calendar: calendar)
        let week = TrainingDays.buildTrainingDays(TrainingCalendar.weekDates(from: monday, calendar: calendar),
                                                  plan: snapshot.plan, lifts: snapshot.lifts,
                                                  activities: snapshot.activities, now: now, calendar: calendar)
        let yesterdayDate = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)) ?? now
        let yesterday = TrainingDays.buildTrainingDays([yesterdayDate], plan: snapshot.plan, lifts: snapshot.lifts,
                                                       activities: snapshot.activities, now: now,
                                                       calendar: calendar).first
        let programNames = Dictionary(snapshot.programs.map { ($0.id, $0.name) },
                                      uniquingKeysWith: { first, _ in first })

        let progress: LiftProgressData?
        if let preloaded {
            progress = preloaded
        } else {
            progress = await LiftProgressData.load(repo: repo, stepKg: LiftProgression.metricStepKg)
        }
        var recordTimestamps: [Int] = []
        for exercise in progress?.exercises ?? [] {
            for point in exercise.points where point.isRecord { recordTimestamps.append(point.startTs) }
        }
        let weighIns = await repo.elanWeighIns(days: 400)
        let kcalSeries = await repo.series(key: "calories_in", source: NutritionSeries.nutritionDeviceId,
                                           days: historyDays)
        let goal = NutritionDayReader.currentPlan(profile: profile, defaults: defaults).intakeKcal
        let ledger = elanLedger(lifts: snapshot.lifts, activities: snapshot.activities,
                                recordTimestamps: recordTimestamps,
                                kcal: kcalSeries.map { (day: $0.day, kcal: Int($0.value.rounded())) },
                                goalKcal: goal,
                                nights: repo.days.map { (day: $0.day, minutes: $0.totalSleepMin) },
                                weighIns: weighIns, calendar: calendar)
        // The last weeks' tallies, oldest first, for Victoires' streak.
        var recentWeeks: [ElanWeekTally] = []
        for back in (0..<tallyWeeks).reversed() {
            guard let weekMonday = calendar.date(byAdding: .day, value: -7 * back, to: monday) else { continue }
            let days = TrainingDays.buildTrainingDays(TrainingCalendar.weekDates(from: weekMonday, calendar: calendar),
                                                      plan: snapshot.plan, lifts: snapshot.lifts,
                                                      activities: snapshot.activities, now: now, calendar: calendar)
            let tally = TrainingDays.sessionTally(days)
            recentWeeks.append(ElanWeekTally(done: tally.done, planned: tally.planned))
        }
        let accepted = ElanShortSessionChoice.acceptedProgramId(day: today, defaults)
        let weight = ElanWeight.weightSummary(weighIns: weighIns, targetKg: ElanWeight.targetKg(defaults))
        ElanWeight.syncProfileWeight(weight, profile: profile, defaults: defaults)
        return ElanState(today: today,
                         missedYesterday: elanMissedYesterday(yesterday, programNames: programNames),
                         shortSessionDismissed: ElanShortSessionChoice.isDismissed(day: today, defaults),
                         shortSessionAccepted: accepted,
                         daysSinceLastSession: elanDaysSinceLastSession(sessionDays: ledger.sessionDays, today: today),
                         week: elanWeekRecap(days: week, ledger: ledger, shortAccepted: accepted != nil),
                         comparison: elanComparison(ledger, today: today),
                         weight: weight,
                         why: ElanWhy.text(defaults),
                         recentWeeks: recentWeeks,
                         nutritionWeek: elanNutritionWeek(ledger, today: today))
    }
}
