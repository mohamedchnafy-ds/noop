import XCTest
import StrandAnalytics
import WhoopStore
@testable import Strand

/// Personal fork, chantier 10 (Élan), PR B: what Élan calls a victory (`ElanVictoryRules`) and the gains of
/// « Ce que tu as construit », over Progression's own exercises.
final class ElanVictoriesTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var nowTs: Int { Int(now.timeIntervalSince1970) }

    private func set(_ exercise: String, _ kg: Double, _ reps: Int, session: String, ts: Int) -> LiftSetRow {
        LiftSetRow(id: UUID().uuidString, deviceId: "d", sessionId: session, ord: 0, exercise: exercise,
                   primaryMuscle: nil, setIndex: 1, weightKg: kg, reps: reps, rpe: nil, isWarmup: false,
                   startTs: ts, endTs: ts + 60, restSec: nil, note: nil)
    }

    private func session(_ id: String, daysAgo: Int, sets: (String) -> [LiftSetRow]) -> LiftProgress.Session {
        let ts = nowTs - daysAgo * 86_400
        let row = LiftSessionRow(id: id, deviceId: "d", startTs: ts, endTs: ts + 3600, sport: "Strength Training",
                                 programId: nil, programName: nil, sessionRpe: nil, note: nil)
        return LiftProgress.Session(row: row, sets: sets(id).map { set in
            LiftSetRow(id: set.id, deviceId: set.deviceId, sessionId: id, ord: set.ord, exercise: set.exercise,
                       primaryMuscle: set.primaryMuscle, setIndex: set.setIndex, weightKg: set.weightKg, reps: set.reps,
                       rpe: set.rpe, isWarmup: set.isWarmup, startTs: ts, endTs: ts + 60, restSec: nil, note: nil)
        })
    }

    /// Squat: 90 kg six weeks ago, 100 kg two weeks ago (a record), 100 kg yesterday; Bench: once only.
    private var exercises: [LiftProgress.Exercise] {
        let sessions = [
            session("s1", daysAgo: 40) { [set("Squat", 90, 5, session: $0, ts: 0)] },
            session("s2", daysAgo: 14) { [set("Squat", 100, 5, session: $0, ts: 0)] },
            session("s3", daysAgo: 1) { [set("Squat", 100, 5, session: $0, ts: 0), set("Bench", 60, 8, session: $0, ts: 0)] },
        ]
        return LiftProgress.exercises(sessions: sessions, lines: [:], stepKg: 2.5)
    }

    func testRecordsAreCountedOverTheLastThirtyDays() {
        let count = ElanVictoryRules.elanRecentRecords(exercises, today: TrainingCalendar.trainingDayKey(now, calendar: .current),
                                                       calendar: .current)
        XCTAssertEqual(count, 1, "the 100 kg two weeks ago; the first session is the baseline, yesterday repeats it")
    }

    func testTheGainIsTheMoveOfTheEstimateOverSixWeeks() {
        let gains = ElanVictoryRules.elanLiftGains(exercises, now: nowTs)
        XCTAssertEqual(gains.map(\.name), ["Squat", "Bench"], "the gain first, then the heaviest")
        let squat = try! XCTUnwrap(gains.first)
        XCTAssertGreaterThan(squat.gainKg, 0)
        XCTAssertEqual(squat.weeks, 6)
        XCTAssertEqual(squat.nowKg, LiftMetricsProbe.oneRepMax(100, 5), accuracy: 0.001)
        XCTAssertEqual(squat.gainKg, LiftMetricsProbe.oneRepMax(100, 5) - LiftMetricsProbe.oneRepMax(90, 5), accuracy: 0.001)
        let bench = gains[1]
        XCTAssertEqual(bench.gainKg, 0, "a single point in the window: no move to state")
    }

    func testAnExerciseNotDoneInTheWindowIsLeftOut() {
        let old = [session("s0", daysAgo: 100) { [set("Row", 50, 10, session: $0, ts: 0)] }]
        let exercises = LiftProgress.exercises(sessions: old, lines: [:], stepKg: 2.5)
        XCTAssertTrue(ElanVictoryRules.elanLiftGains(exercises, now: nowTs).isEmpty)
    }

    func testThePlanStreakIsTheLongestRunOfKeptWeeks() {
        let weeks = [ElanWeekTally(done: 3, planned: 3), ElanWeekTally(done: 2, planned: 3),
                     ElanWeekTally(done: 3, planned: 3), ElanWeekTally(done: 4, planned: 3),
                     ElanWeekTally(done: 1, planned: 0), ElanWeekTally(done: 3, planned: 3)]
        let streak = try! XCTUnwrap(ElanVictoryRules.elanPlanStreak(weeks))
        XCTAssertEqual(streak.weeks, 2)
        XCTAssertEqual(streak.endIndex, 3)
    }

    func testAWeekWithoutAPlanBreaksTheRunAndOneWeekIsNoStreak() {
        XCTAssertNil(ElanVictoryRules.elanPlanStreak([ElanWeekTally(done: 3, planned: 3)]))
        XCTAssertNil(ElanVictoryRules.elanPlanStreak([ElanWeekTally(done: 3, planned: 3), ElanWeekTally(done: 2, planned: 0),
                                                       ElanWeekTally(done: 3, planned: 3)]))
        XCTAssertNil(ElanVictoryRules.elanPlanStreak([]))
    }

    func testTheVictoriesGatherTheThree() {
        let weeks = [ElanWeekTally(done: 3, planned: 3), ElanWeekTally(done: 3, planned: 3)]
        let victories = ElanVictoryRules.elanVictories(exercises: exercises, weeks: weeks, now: now, calendar: .current)
        XCTAssertEqual(victories.recentRecords, 1)
        XCTAssertEqual(victories.planStreak?.weeks, 2)
        XCTAssertEqual(victories.bestGain?.name, "Squat")
        XCTAssertEqual(victories.gains.count, 2)
    }

    func testWithoutAPositiveGainThereIsNoBestGain() {
        let sessions = [
            session("a", daysAgo: 20) { [set("Squat", 100, 5, session: $0, ts: 0)] },
            session("b", daysAgo: 2) { [set("Squat", 95, 5, session: $0, ts: 0)] },
        ]
        let exercises = LiftProgress.exercises(sessions: sessions, lines: [:], stepKg: 2.5)
        let victories = ElanVictoryRules.elanVictories(exercises: exercises, weeks: [], now: now, calendar: .current)
        XCTAssertNil(victories.bestGain)
        XCTAssertEqual(victories.gains.first?.gainKg ?? 0, LiftMetricsProbe.oneRepMax(95, 5) - LiftMetricsProbe.oneRepMax(100, 5),
                       accuracy: 0.001, "the list still shows the move, negative")
    }
}

/// The package's estimate, reached through the app module so the expected figures use the same formula.
private enum LiftMetricsProbe {
    static func oneRepMax(_ kg: Double, _ reps: Int) -> Double {
        LiftMetrics.estimatedOneRepMaxKg(weightKg: kg, reps: reps) ?? kg
    }
}
