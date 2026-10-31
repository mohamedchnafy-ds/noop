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
