import XCTest
@testable import Strand
import WhoopStore

/// The step-up rule shown in the session sheet (personal fork), and the question the finish sheet
/// hands to the Coach.
final class LiftProgressionTests: XCTestCase {

    private func set(_ ord: Int, kg: Double?, reps: Int?, rpe: Double? = nil, warmup: Bool = false,
                     exercise: String = "Bench press") -> LiftSetRow {
        LiftSetRow(id: "s\(ord)", deviceId: "d", sessionId: "x", ord: ord, exercise: exercise,
                   primaryMuscle: .chest, secondaryMuscles: [], setIndex: ord + 1,
                   weightKg: kg, reps: reps, rpe: rpe, isWarmup: warmup,
                   startTs: nil, endTs: nil, restSec: nil, note: nil)
    }

    private func item(sets: Int = 3, low: Int? = 8, high: Int? = 12, rpe: Double? = 8) -> LiftPlanItem {
        LiftPlanItem(exercise: "Bench press", primaryMuscle: .chest, targetSets: sets,
                     restSec: 90, targetRepsLow: low, targetRepsHigh: high, targetRpe: rpe)
    }

    /// Fork chantier 9: a step up earned puts the raised weight in last session's grey numbers, reps
    /// unchanged; a set with no weight and an exercise with no suggestion are left as they were.
    func testRaisedLastSessionCarriesTheRaisedWeight() {
        let bySet: [Int: LiftSetCarry] = [1: LiftSetCarry(weightKg: 60, reps: 12),
                                          2: LiftSetCarry(weightKg: 60, reps: 12),
                                          3: LiftSetCarry(weightKg: nil, reps: 10)]
        let raised = LiftProgression.raisedLastSession(bySet, suggestion: .init(fromKg: 60, toKg: 62.5))
        XCTAssertEqual(raised[1], LiftSetCarry(weightKg: 62.5, reps: 12))
        XCTAssertEqual(raised[2], LiftSetCarry(weightKg: 62.5, reps: 12))
        XCTAssertEqual(raised[3], LiftSetCarry(weightKg: nil, reps: 10))
        XCTAssertEqual(LiftProgression.raisedLastSession(bySet, suggestion: nil), bySet)
    }

    func testEverySetAtTheTopOfTheRangeUnderTheRpeCapEarnsAStep() {
        let last = [set(0, kg: 40, reps: 8, warmup: true), set(1, kg: 60, reps: 12, rpe: 7.5),
                    set(2, kg: 60, reps: 12, rpe: 8), set(3, kg: 60, reps: 13)]
        XCTAssertEqual(LiftProgression.suggest(lastSets: last, item: item()),
                       LiftProgression.Suggestion(fromKg: 60, toKg: 62.5))
    }

    func testOneShortSetOrOneHardSetHoldsTheLoad() {
        let short = [set(1, kg: 60, reps: 12), set(2, kg: 60, reps: 11), set(3, kg: 60, reps: 12)]
        XCTAssertNil(LiftProgression.suggest(lastSets: short, item: item()))
        let hard = [set(1, kg: 60, reps: 12, rpe: 8), set(2, kg: 60, reps: 12, rpe: 9), set(3, kg: 60, reps: 12)]
        XCTAssertNil(LiftProgression.suggest(lastSets: hard, item: item()))
    }

    func testFewerSetsThanPlannedOrMixedWeightsHold() {
        let few = [set(1, kg: 60, reps: 12), set(2, kg: 60, reps: 12)]
        XCTAssertNil(LiftProgression.suggest(lastSets: few, item: item()))
        let pyramid = [set(1, kg: 50, reps: 12), set(2, kg: 55, reps: 12), set(3, kg: 60, reps: 12)]
        XCTAssertNil(LiftProgression.suggest(lastSets: pyramid, item: item()))
    }

    func testNoRepTargetMeansNoOpinionAndNoRpeCapMeansNoRpeTest() {
        let last = [set(1, kg: 60, reps: 12, rpe: 10), set(2, kg: 60, reps: 12, rpe: 10), set(3, kg: 60, reps: 12)]
        XCTAssertNil(LiftProgression.suggest(lastSets: last, item: item(low: nil, high: nil)))
        XCTAssertNotNil(LiftProgression.suggest(lastSets: last, item: item(rpe: nil)))
        // A single rep target (low only) is the bar when there is no high.
        XCTAssertNotNil(LiftProgression.suggest(lastSets: last, item: item(low: 12, high: nil, rpe: nil)))
    }

    func testImperialStepIsFivePounds() {
        let last = [set(1, kg: 60, reps: 12), set(2, kg: 60, reps: 12), set(3, kg: 60, reps: 12)]
        let s = LiftProgression.suggest(lastSets: last, item: item(rpe: nil), stepKg: LiftProgression.imperialStepKg)!
        XCTAssertEqual((s.toKg - s.fromKg) * UnitFormatter.poundsPerKilogram, 5, accuracy: 1e-9)
    }

    func testSessionPromptListsWorkingSetsPerExerciseThenAsks() {
        let sets = [set(0, kg: 40, reps: 8, warmup: true), set(1, kg: 60, reps: 10, rpe: 8),
                    set(2, kg: 20, reps: 12, exercise: "Curl"), set(3, kg: 60, reps: 9),
                    set(4, kg: 60, reps: 0)]
        let p = CoachSessionPrompt.prompt(programName: "Superset A", startTs: 0, endTs: 52 * 60,
                                          sessionRpe: 7, sets: sets, system: .metric)
        let lines = p.components(separatedBy: "\n")
        XCTAssertEqual(lines[0], "Superset A, 52 min, RPE 7")
        XCTAssertEqual(lines[1], "- Bench press: 60×10 @8, 60×9 (kg)")
        XCTAssertEqual(lines[2], "- Curl: 20×12 (kg)")
        XCTAssertTrue(lines.last!.contains("Analyse"), "ends with the ask")
    }
}
