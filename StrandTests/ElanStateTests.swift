import XCTest
@testable import Strand

/// Personal fork, chantier 10 (Élan), PR A: the pure rules of the Élan resolver (`ElanResolver`) — the week's
/// marks, yesterday's missed session, the « jour Nutrition tenu » rule, the « Avant / maintenant » windows —
/// and the per-day short-session choice.
final class ElanStateTests: XCTestCase {

    private let today = "2026-11-05"   // a Thursday

    private func day(_ key: String, planned: [TrainingPlannedItem] = [], lifts: [TrainingLiftDone] = [],
                     isToday: Bool = false, isPast: Bool = false) -> TrainingDay {
        TrainingDay(date: ElanDays.elanDate(key) ?? Date(), key: key, isToday: isToday, isPast: isPast,
                    planned: planned, lifts: lifts, activities: [])
    }

    private func lift(_ day: String, program: String? = "p1", sets: Int = 12) -> TrainingLiftDone {
        let ts = Int((ElanDays.elanDate(day) ?? Date()).timeIntervalSince1970) + 18 * 3600
        return TrainingLiftDone(sessionId: UUID().uuidString, programId: program, name: "Full body",
                                startTs: ts, endTs: ts + 3600, workingSets: sets, effort: nil)
    }

    private func ledger(sessionDays: [String] = [], setsByDay: [String: Int] = [:], recordDays: [String] = [],
                        kcalByDay: [String: Int] = [:], goalKcal: Int? = 2000,
                        sleep: [String: Double] = [:], weighIns: [ElanWeighIn] = []) -> ElanLedger {
        ElanLedger(sessionDays: sessionDays, setsByDay: setsByDay, recordDays: recordDays, kcalByDay: kcalByDay,
                   goalKcal: goalKcal, sleepMinutesByDay: sleep, weighIns: weighIns)
    }

    private func defaults() -> UserDefaults {
        let name = "ElanStateTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    // MARK: - Day marks

    func testEachKindOfDayGetsItsMark() {
        let planned = [TrainingPlannedItem(item: .program("p1"), isDone: false)]
        let done = [TrainingPlannedItem(item: .program("p1"), isDone: true)]
        XCTAssertEqual(ElanResolver.elanDayMark(day("2026-11-02", planned: done, lifts: [lift("2026-11-02")], isPast: true),
                                                shortAccepted: false), .done)
        XCTAssertEqual(ElanResolver.elanDayMark(day("2026-11-03", isPast: true), shortAccepted: false), .rest)
        XCTAssertEqual(ElanResolver.elanDayMark(day("2026-11-04", planned: planned, isPast: true), shortAccepted: false),
                       .missed)
        XCTAssertEqual(ElanResolver.elanDayMark(day("2026-11-05", isToday: true), shortAccepted: false), .today)
        XCTAssertEqual(ElanResolver.elanDayMark(day("2026-11-05", isToday: true), shortAccepted: true), .todayShort)
        XCTAssertEqual(ElanResolver.elanDayMark(day("2026-11-05", lifts: [lift("2026-11-05")], isToday: true),
                                                shortAccepted: true), .done, "a session done today wins")
        XCTAssertEqual(ElanResolver.elanDayMark(day("2026-11-07", planned: planned), shortAccepted: false), .planned)
        XCTAssertEqual(ElanResolver.elanDayMark(day("2026-11-08"), shortAccepted: false), .rest)
    }

    func testAnUnplannedSessionIsADoneDay() {
        XCTAssertEqual(ElanResolver.elanDayMark(day("2026-11-03", lifts: [lift("2026-11-03", program: nil)], isPast: true),
                                                shortAccepted: false), .done)
    }

    // MARK: - Yesterday

    func testYesterdaysMissedProgramIsNamed() {
        let planned = [TrainingPlannedItem(item: .cardio(sport: "Running", minutes: 30), isDone: false),
                       TrainingPlannedItem(item: .program("p2"), isDone: false)]
        let missed = ElanResolver.elanMissedYesterday(day("2026-11-04", planned: planned, isPast: true),
                                                      programNames: ["p2": "Full body B"])
        XCTAssertEqual(missed, ElanMissedSession(programId: "p2", name: "Full body B", day: "2026-11-04"))
    }

    func testNoMissedSessionWithoutAnUndoneProgram() {
        XCTAssertNil(ElanResolver.elanMissedYesterday(nil, programNames: [:]))
        XCTAssertNil(ElanResolver.elanMissedYesterday(day("2026-11-04", isPast: true), programNames: [:]), "rest day")
        let done = [TrainingPlannedItem(item: .program("p1"), isDone: true)]
        XCTAssertNil(ElanResolver.elanMissedYesterday(day("2026-11-04", planned: done, isPast: true),
                                                      programNames: ["p1": "A"]))
        let cardio = [TrainingPlannedItem(item: .cardio(sport: "Running", minutes: 30), isDone: false)]
        XCTAssertNil(ElanResolver.elanMissedYesterday(day("2026-11-04", planned: cardio, isPast: true),
                                                      programNames: [:]), "cardio left undone proposes nothing")
    }

    func testDaysSinceTheLastSession() {
        XCTAssertEqual(ElanResolver.elanDaysSinceLastSession(sessionDays: ["2026-10-30", "2026-11-02"], today: today), 3)
        XCTAssertEqual(ElanResolver.elanDaysSinceLastSession(sessionDays: ["2026-11-05"], today: today), 0)
        XCTAssertNil(ElanResolver.elanDaysSinceLastSession(sessionDays: ["2026-11-09"], today: today),
                     "a future session (clock skew) is not the last one")
        XCTAssertNil(ElanResolver.elanDaysSinceLastSession(sessionDays: [], today: today))
    }

    // MARK: - Nutrition held

    func testADayIsHeldWithinTenPercentOfTheGoal() {
        XCTAssertTrue(ElanResolver.elanNutritionHeld(kcal: 1800, goalKcal: 2000))
        XCTAssertFalse(ElanResolver.elanNutritionHeld(kcal: 1799, goalKcal: 2000))
        XCTAssertTrue(ElanResolver.elanNutritionHeld(kcal: 2200, goalKcal: 2000))
        XCTAssertFalse(ElanResolver.elanNutritionHeld(kcal: 2201, goalKcal: 2000))
        XCTAssertFalse(ElanResolver.elanNutritionHeld(kcal: 0, goalKcal: 0), "no goal, nothing held")
    }

    func testTheTallyCountsLoggedDaysOnly() {
        let l = ledger(kcalByDay: ["2026-11-02": 1900, "2026-11-03": 1500, "2026-11-05": 2100, "2026-10-20": 2000])
        let tally = ElanResolver.elanNutritionTally(l, from: "2026-11-02", to: "2026-11-08")
        XCTAssertEqual(tally.held, 2)
        XCTAssertEqual(tally.logged, 3)
        let noGoal = ElanResolver.elanNutritionTally(ledger(kcalByDay: ["2026-11-02": 1900], goalKcal: nil),
                                                     from: "2026-11-02", to: "2026-11-08")
        XCTAssertEqual(noGoal.held, 0)
        XCTAssertEqual(noGoal.logged, 1)
    }

    // MARK: - The last seven days of Nutrition

    func testTheNutritionWeekMarksHeldMissedAndEmptyDays() {
        let l = ledger(kcalByDay: ["2026-11-05": 2000, "2026-11-04": 1500, "2026-10-30": 2100])
        let week = ElanResolver.elanNutritionWeek(l, today: today)
        XCTAssertEqual(week.map(\.day), ["2026-10-30", "2026-10-31", "2026-11-01", "2026-11-02", "2026-11-03", "2026-11-04", "2026-11-05"])
        XCTAssertEqual(week.map(\.status), [.held, .none, .none, .none, .none, .missed, .held])
    }

    // MARK: - Week recap

    func testTheWeekRecapReadsTheSevenDaysOnly() {
        let planned = [TrainingPlannedItem(item: .program("p1"), isDone: false)]
        let done = [TrainingPlannedItem(item: .program("p1"), isDone: true)]
        let days = [day("2026-11-02", planned: done, lifts: [lift("2026-11-02")], isPast: true),
                    day("2026-11-03", isPast: true),
                    day("2026-11-04", planned: planned, isPast: true),
                    day("2026-11-05", isToday: true),
                    day("2026-11-06"),
                    day("2026-11-07", planned: planned),
                    day("2026-11-08")]
        let l = ledger(kcalByDay: ["2026-11-01": 2000, "2026-11-02": 2000, "2026-11-03": 1000, "2026-11-04": 2050],
                       sleep: ["2026-11-01": 480, "2026-11-02": 360, "2026-11-03": 380, "2026-11-05": 0],
                       weighIns: [ElanWeighIn(day: "2026-11-01", kg: 85), ElanWeighIn(day: "2026-11-02", kg: 85),
                                  ElanWeighIn(day: "2026-11-04", kg: 84.8)])
        let recap = ElanResolver.elanWeekRecap(days: days, ledger: l, shortAccepted: true)
        XCTAssertEqual(recap.days.map(\.mark), [.done, .rest, .missed, .todayShort, .rest, .planned, .rest])
        XCTAssertEqual(recap.done, 1)
        XCTAssertEqual(recap.planned, 3)
        XCTAssertEqual(recap.nutritionHeldDays, 2)
        XCTAssertEqual(recap.nutritionLoggedDays, 3)
        XCTAssertEqual(recap.averageNightMinutes ?? 0, 370, accuracy: 1e-9, "the Sunday before and the empty night are out")
        XCTAssertEqual(recap.weighIns, 2)
    }

    // MARK: - Avant / maintenant

    func testAWindowCountsWhatFallsInsideIt() {
        let l = ledger(sessionDays: ["2026-10-01", "2026-10-05", "2026-10-05", "2026-10-29"],
                       setsByDay: ["2026-10-01": 10, "2026-10-05": 24, "2026-10-29": 8],
                       recordDays: ["2026-10-05", "2026-10-05", "2026-11-01"],
                       kcalByDay: ["2026-10-02": 2000, "2026-10-03": 1200],
                       sleep: ["2026-10-01": 400, "2026-10-02": 440])
        let window = ElanResolver.elanWindow(l, from: "2026-10-01", to: "2026-10-28")
        XCTAssertEqual(window.days, 28)
        XCTAssertEqual(window.sessions, 3)
        XCTAssertEqual(window.sessionsPerWeek, 0.75, accuracy: 1e-9)
        XCTAssertEqual(window.sets, 34)
        XCTAssertEqual(window.setsPerWeek, 8.5, accuracy: 1e-9)
        XCTAssertEqual(window.records, 2)
        XCTAssertEqual(window.nutritionHeld, 1)
        XCTAssertEqual(window.nutritionLogged, 2)
        XCTAssertEqual(window.averageNightMinutes ?? 0, 420, accuracy: 1e-9)
    }

    func testTheLaunchedWindowIsTheBestFourWeeksBeforeTheLastThree() {
        // Three sessions a week from 14 Sept to 11 Oct (12 sessions), then one a week.
        var sessions: [String] = []
        var cursor = "2026-09-14"
        while cursor <= "2026-10-11" {
            sessions += [cursor, ElanDays.elanDay(cursor, adding: 2), ElanDays.elanDay(cursor, adding: 4)]
            cursor = ElanDays.elanDay(cursor, adding: 7)
        }
        sessions += ["2026-10-19", "2026-10-26", "2026-11-02"]
        let comparison = ElanResolver.elanComparison(ledger(sessionDays: sessions), today: today)
        XCTAssertEqual(comparison.recent.startDay, "2026-10-15")
        XCTAssertEqual(comparison.recent.endDay, "2026-11-04")
        XCTAssertEqual(comparison.recent.sessions, 3)
        let launched = try! XCTUnwrap(comparison.launched)
        XCTAssertEqual(launched.days, 28)
        XCTAssertEqual(launched.sessions, 12)
        XCTAssertEqual(launched.sessionsPerWeek, 3, accuracy: 1e-9)
        XCTAssertGreaterThanOrEqual(launched.startDay, "2026-09-14")
        XCTAssertLessThanOrEqual(launched.endDay, "2026-10-14", "never overlaps the recent window")
        XCTAssertLessThanOrEqual(launched.endDay, "2026-10-14")
    }

    func testWithoutMomentumThereIsNoLaunchedWindow() {
        let comparison = ElanResolver.elanComparison(ledger(sessionDays: ["2026-09-01", "2026-10-01", "2026-11-02"]),
                                                     today: today)
        XCTAssertNil(comparison.launched)
        XCTAssertEqual(comparison.recent.sessions, 1)
    }

    func testTheLaunchedWindowStaysInsideSixMonths() {
        // Twelve sessions a year ago: too old to count.
        let old = (0..<12).map { ElanDays.elanDay("2025-09-01", adding: $0 * 2) }
        XCTAssertNil(ElanResolver.elanComparison(ledger(sessionDays: old), today: today).launched)
    }

    // MARK: - Ledger

    func testTheLedgerKeysRowsByLocalDayAndKeepsCardioSessionsOnly() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let base = Int((ElanDays.elanDate("2026-11-02") ?? Date()).timeIntervalSince1970)
        let lifts = [TrainingLiftDone(sessionId: "a", programId: "p1", name: "A", startTs: base + 7 * 3600,
                                      endTs: base + 8 * 3600, workingSets: 10, effort: nil),
                     TrainingLiftDone(sessionId: "b", programId: "p1", name: "A", startTs: base + 20 * 3600,
                                      endTs: base + 21 * 3600, workingSets: 6, effort: nil)]
        let activities = [TrainingActivityDone(sport: "Running", source: "recorded", startTs: base + 86_400,
                                               endTs: base + 86_400 + 40 * 60, kcal: nil),
                          TrainingActivityDone(sport: "Running", source: "detected", startTs: base + 2 * 86_400,
                                               endTs: base + 2 * 86_400 + 10 * 60, kcal: nil),
                          TrainingActivityDone(sport: "Yoga", source: "recorded", startTs: base + 3 * 86_400,
                                               endTs: base + 3 * 86_400 + 3600, kcal: nil)]
        let nights: [(day: String, minutes: Double?)] = [(day: "2026-11-02", minutes: 410), (day: "2026-11-03", minutes: nil),
                                                         (day: "2026-11-04", minutes: 0)]
        let ledger = ElanResolver.elanLedger(lifts: lifts, activities: activities, recordTimestamps: [base + 20 * 3600],
                                             kcal: [(day: "2026-11-02", kcal: 1900)], goalKcal: 2000, nights: nights,
                                             weighIns: [], calendar: calendar)
        XCTAssertEqual(ledger.sessionDays, ["2026-11-02", "2026-11-02", "2026-11-03"],
                       "two lifts, one run long enough; the 10-minute run and the yoga are out")
        XCTAssertEqual(ledger.setsByDay, ["2026-11-02": 16])
        XCTAssertEqual(ledger.recordDays, ["2026-11-02"])
        XCTAssertEqual(ledger.kcalByDay, ["2026-11-02": 1900])
        XCTAssertEqual(ledger.sleepMinutesByDay, ["2026-11-02": 410])
    }

    // MARK: - The wearer's choice

    func testTheShortSessionChoiceIsForTheDayOnly() {
        let d = defaults()
        XCTAssertFalse(ElanShortSessionChoice.isDismissed(day: today, d))
        ElanShortSessionChoice.dismiss(day: today, d)
        XCTAssertTrue(ElanShortSessionChoice.isDismissed(day: today, d))
        XCTAssertFalse(ElanShortSessionChoice.isDismissed(day: "2026-11-06", d), "a new day starts clean")

        ElanShortSessionChoice.accept(day: today, programId: "p2", d)
        XCTAssertEqual(ElanShortSessionChoice.acceptedProgramId(day: today, d), "p2")
        XCTAssertFalse(ElanShortSessionChoice.isDismissed(day: today, d), "accepting undoes « Pas aujourd'hui »")
        XCTAssertNil(ElanShortSessionChoice.acceptedProgramId(day: "2026-11-06", d))

        ElanShortSessionChoice.withdraw(day: today, d)
        XCTAssertNil(ElanShortSessionChoice.acceptedProgramId(day: today, d))
        XCTAssertTrue(ElanShortSessionChoice.isDismissed(day: today, d), "« Retirer » closes the day")
    }
}
