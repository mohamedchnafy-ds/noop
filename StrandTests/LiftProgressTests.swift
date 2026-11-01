import XCTest
@testable import Strand
import StrandAnalytics
import WhoopStore

/// The Progression rules (personal fork): what a record is, when an exercise is progressing, ready,
/// stalled or declining, how muscles are counted and prioritised, and how a session's form is measured.
final class LiftProgressTests: XCTestCase {

    private let day = 86_400
    private let now = 1_800_000_000

    private func set(_ exercise: String, _ kg: Double?, _ reps: Int?, ord: Int = 0, session: String = "x",
                     primary: LiftMuscle? = .quads, secondary: [LiftMuscle] = [], warmup: Bool = false) -> LiftSetRow {
        LiftSetRow(id: "\(session)-\(exercise)-\(ord)", deviceId: "d", sessionId: session, ord: ord, exercise: exercise,
                   primaryMuscle: primary, secondaryMuscles: secondary, setIndex: ord + 1,
                   weightKg: kg, reps: reps, rpe: nil, isWarmup: warmup,
                   startTs: nil, endTs: nil, restSec: nil, note: nil)
    }

    /// A session `daysAgo` before `now` with one exercise done as `sets` (weight, reps).
    private func session(_ id: String, daysAgo: Int, _ exercise: String, _ sets: [(Double?, Int?)],
                         primary: LiftMuscle? = .quads, secondary: [LiftMuscle] = []) -> LiftProgress.Session {
        let start = now - daysAgo * day
        let row = LiftSessionRow(id: id, deviceId: "d", startTs: start, endTs: start + 3_000, sport: "lift",
                                 programId: nil, programName: "Full body A", sessionRpe: nil, note: nil)
        let rows = sets.enumerated().map { index, s in
            set(exercise, s.0, s.1, ord: index, session: id, primary: primary, secondary: secondary)
        }
        return LiftProgress.Session(row: row, sets: rows)
    }

    private func line(_ exercise: String, sets: Int = 3, low: Int = 10, high: Int = 12,
                      primary: LiftMuscle = .quads) -> LiftProgress.ProgramLine {
        LiftProgress.ProgramLine(item: LiftPlanItem(exercise: exercise, primaryMuscle: primary, targetSets: sets,
                                                    targetRepsLow: low, targetRepsHigh: high),
                                 programName: "Full body A")
    }

    private func status(_ sessions: [LiftProgress.Session], line: LiftProgress.ProgramLine? = nil) -> LiftProgress.Status? {
        let lines = line.map { [$0.item.exercise: $0] } ?? [:]
        return LiftProgress.exercises(sessions: sessions, lines: lines, stepKg: 2.5).first?.status
    }

    // MARK: Records

    func testARecordIsAHeavierWeightOrMoreRepsAtAKnownWeight() {
        let flags = LiftProgress.recordFlags([
            [set("Squat", 40, 10)],             // baseline
            [set("Squat", 40, 11)],             // more reps at 40: record
            [set("Squat", 40, 11)],             // same: no record
            [set("Squat", 37.5, 12)],           // lighter, new weight: no record
            [set("Squat", 42.5, 6)],            // heavier than ever: record
            [set("Squat", 37.5, 12)],           // ties 37.5 × 12: no record
        ])
        XCTAssertEqual(flags, [false, true, false, false, true, false])
    }

    func testWarmupsAndSkippedSetsNeverMakeARecord() {
        let sessions = [
            session("a", daysAgo: 21, "Squat", [(40, 10), (40, 10)]),
            LiftProgress.Session(row: session("b", daysAgo: 14, "Squat", []).row,
                                 sets: [set("Squat", 60, 5, ord: 0, session: "b", warmup: true),
                                        set("Squat", 50, 0, ord: 1, session: "b"),
                                        set("Squat", 40, 10, ord: 2, session: "b")]),
        ]
        let points = LiftProgress.exercises(sessions: sessions, lines: [:], stepKg: 2.5).first?.points ?? []
        XCTAssertEqual(points.map(\.isRecord), [false, false])
        XCTAssertEqual(points.last?.sets.count, 1)
    }

    // MARK: Statuses

    func testFewerThanThreeSessionsHasNoVerdict() {
        let s = [session("a", daysAgo: 14, "Squat", [(40, 10)]), session("b", daysAgo: 7, "Squat", [(40, 11)])]
        XCTAssertEqual(status(s), .notEnough(sessions: 2))
    }

    func testARecordInTheLastThreeSessionsIsProgress() {
        let s = [session("a", daysAgo: 21, "Squat", [(40, 10)]),
                 session("b", daysAgo: 14, "Squat", [(40, 10)]),
                 session("c", daysAgo: 7, "Squat", [(40, 11)])]
        XCTAssertEqual(status(s), .progressing)
    }

    func testThreeSessionsWithoutARecordStall() {
        let s = [session("a", daysAgo: 35, "Press", [(30, 8)]),
                 session("b", daysAgo: 28, "Press", [(30, 9)]),          // record
                 session("c", daysAgo: 21, "Press", [(30, 8)]),
                 session("d", daysAgo: 14, "Press", [(30, 9)]),
                 session("e", daysAgo: 7, "Press", [(30, 8)])]
        XCTAssertEqual(status(s), .stalled(sessions: 3))
    }

    func testTheDoubleProgressionRuleSaysReady() {
        let s = [session("a", daysAgo: 21, "Squat", [(40, 10), (40, 10), (40, 10)]),
                 session("b", daysAgo: 14, "Squat", [(40, 11), (40, 11), (40, 10)]),
                 session("c", daysAgo: 7, "Squat", [(40, 12), (40, 12), (40, 12)])]
        XCTAssertEqual(status(s, line: line("Squat")), .ready(fromKg: 40, toKg: 42.5))
        // The same sessions in no program progress, but never read "ready".
        XCTAssertEqual(status(s), .progressing)
    }

    func testTwoClearlyWeakerSessionsWithoutARecordDecline() {
        let s = [session("a", daysAgo: 28, "RDL", [(50, 10)]),        // e1RM 66.7
                 session("b", daysAgo: 21, "RDL", [(50, 12)]),        // 70: record
                 session("c", daysAgo: 14, "RDL", [(50, 9)]),         // 65
                 session("d", daysAgo: 7, "RDL", [(50, 8)])]          // 63.3
        guard case let .declining(percent)? = status(s) else { return XCTFail("expected a decline") }
        XCTAssertEqual(percent, (50 * (1 + 8.0 / 30) / 70 - 1) * 100, accuracy: 0.001)
    }

    func testAStepUpThatLowersTheEstimateIsNotADecline() {
        let s = [session("a", daysAgo: 28, "Squat", [(40, 10)]),
                 session("b", daysAgo: 21, "Squat", [(40, 12)]),      // 56
                 session("c", daysAgo: 14, "Squat", [(45, 6)]),       // 54, but a heavier weight: record
                 session("d", daysAgo: 7, "Squat", [(45, 5)])]        // 52.5
        XCTAssertEqual(status(s), .progressing)
    }

    // MARK: Periods

    func testChangeAndRecordCountFollowThePeriod() {
        let s = [session("a", daysAgo: 60, "Squat", [(35, 10)]),
                 session("b", daysAgo: 20, "Squat", [(40, 10)]),
                 session("c", daysAgo: 10, "Squat", [(40, 12)])]
        let exercises = LiftProgress.exercises(sessions: s, lines: [:], stepKg: 2.5)
        let four = LiftProgress.points(exercises[0], in: .fourWeeks, now: now)
        XCTAssertEqual(four.count, 2)
        XCTAssertEqual(LiftProgress.change(four) ?? 0, (56.0 / (40 * (1 + 10.0 / 30)) - 1) * 100, accuracy: 0.001)
        XCTAssertEqual(LiftProgress.recordCount(exercises, in: .fourWeeks, now: now), 2)
        XCTAssertEqual(LiftProgress.recordCount(exercises, in: .all, now: now), 2)
    }

    // MARK: Ladder

    func testTheLadderHoldsTheSessionsAtTheCurrentWeight() {
        let s = [session("a", daysAgo: 28, "Squat", [(37.5, 12), (37.5, 12), (37.5, 12)]),
                 session("b", daysAgo: 21, "Squat", [(40, 10), (40, 10), (40, 9)]),
                 session("c", daysAgo: 14, "Squat", [(40, 11), (40, 11), (40, 10)]),
                 session("d", daysAgo: 7, "Squat", [(40, 12), (40, 12), (40, 12)])]
        let exercise = LiftProgress.exercises(sessions: s, lines: ["Squat": line("Squat")], stepKg: 2.5)[0]
        let ladder = LiftProgress.ladder(exercise)
        XCTAssertEqual(ladder?.weightKg, 40)
        XCTAssertEqual(ladder?.rows.map(\.reps), [[10, 10, 9], [11, 11, 10], [12, 12, 12]])
        XCTAssertEqual(ladder?.targetTotal, 36)
    }

    // MARK: Muscles

    func testWeeklySetsAreAveragedOverTheWeeksOfHistoryOnly() {
        // Two weeks of history, 3 direct sets each week: 3 a week, not 6 / 4.
        let s = [session("a", daysAgo: 10, "Squat", [(40, 10), (40, 10), (40, 10)], secondary: [.glutes]),
                 session("b", daysAgo: 3, "Squat", [(40, 10), (40, 10), (40, 10)], secondary: [.glutes])]
        let weekly = LiftProgress.weeklySets(s, period: .fourWeeks, now: now)
        XCTAssertEqual(weekly[.quads] ?? 0, 3, accuracy: 0.001)
        XCTAssertEqual(weekly[.glutes] ?? 0, 1.5, accuracy: 0.001)
    }

    func testAMuscleIsAPriorityUnderTheReferenceOrWhenAllItsExercisesAreStuck() {
        let stalled = [session("a", daysAgo: 35, "Press", [(30, 8)], primary: .frontDelts),
                       session("b", daysAgo: 28, "Press", [(30, 8)], primary: .frontDelts),
                       session("c", daysAgo: 21, "Press", [(30, 8)], primary: .frontDelts),
                       session("d", daysAgo: 14, "Press", [(30, 8)], primary: .frontDelts)]
        let exercises = LiftProgress.exercises(sessions: stalled, lines: [:], stepKg: 2.5)
        let weekly: [LiftMuscle: Double] = [.frontDelts: 7, .sideDelts: 3, .quads: 8, .neck: 0]
        let priorities = LiftProgress.priorities(weekly: weekly, exercises: exercises,
                                                 targeted: [.frontDelts, .sideDelts, .quads])
        XCTAssertEqual(priorities.map(\.muscle), [.sideDelts, .frontDelts])
        XCTAssertEqual(priorities.first { $0.muscle == .frontDelts }?.stuckExercises, ["Press"])
        XCTAssertEqual(priorities.first { $0.muscle == .sideDelts }?.belowReference, true)
        // The neck gets no sets, but no program targets it: never a priority.
        XCTAssertFalse(priorities.contains { $0.muscle == .neck })
    }

    func testBalancesNeedSetsOnBothSides() {
        let weekly: [LiftMuscle: Double] = [.quads: 8, .hamstrings: 6, .frontDelts: 7]
        XCTAssertEqual(LiftProgress.BalancePair.quadsHamstrings.totals(weekly)?.left, 8)
        XCTAssertNil(LiftProgress.BalancePair.frontRearDelts.totals(weekly))
    }

    // MARK: Form

    func testFormComparesEachSessionWithTheFourBefore() {
        let values: [(Double?, Int?)] = [(40, 10), (40, 10), (40, 10), (40, 10), (40, 12)]
        let s = values.enumerated().map { index, v in
            session("s\(index)", daysAgo: 30 - index * 5, "Squat", [v])
        }
        let form = LiftProgress.formSessions(LiftProgress.exercises(sessions: s, lines: [:], stepKg: 2.5))
        XCTAssertEqual(form.count, 1)
        XCTAssertEqual(form[0].percent, (56.0 / (40 * (1 + 10.0 / 30)) - 1) * 100, accuracy: 0.001)
        XCTAssertEqual(LiftProgress.chargeBand(70), .high)
        XCTAssertEqual(LiftProgress.chargeBand(50), .middle)
        XCTAssertEqual(LiftProgress.sleepBand(350), .low)
        XCTAssertEqual(LiftProgress.median([3, 1, 2, 10]), 2.5)
    }
}
