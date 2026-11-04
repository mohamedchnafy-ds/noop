import XCTest
@testable import Strand
import WhoopStore

/// Today's order in a session (personal fork, Supersets et blocs): a block that has not begun moves
/// whole, a block begun stays where it is, and finishing can carry the new order onto the program.
final class LiftSessionBlockOrderTests: XCTestCase {

    // Superset A (Bench, Triceps) · Squat · Superset B (Row, Curl)
    private func plan() -> [LiftPlanItem] {
        [LiftPlanItem(exercise: "Bench", targetSets: 2, programItemId: "p1", supersetGroup: "A"),
         LiftPlanItem(exercise: "Triceps", targetSets: 2, programItemId: "p2", supersetGroup: "A"),
         LiftPlanItem(exercise: "Squat", targetSets: 3, programItemId: "p3"),
         LiftPlanItem(exercise: "Row", targetSets: 2, programItemId: "p4", supersetGroup: "B"),
         LiftPlanItem(exercise: "Curl", targetSets: 2, programItemId: "p5", supersetGroup: "B")]
    }

    func testAPendingSupersetMovesWhole() {
        var engine = LiftSessionEngine(plan: plan(), startTs: 0)
        let moved = engine.moveSessionBlock(containing: 4, by: -1)
        XCTAssertEqual(engine.plan.map(\.exercise), ["Bench", "Triceps", "Row", "Curl", "Squat"])
        XCTAssertEqual(engine.blocks, [0..<2, 2..<4, 4..<5])
        XCTAssertEqual(moved?[3], 2)
        XCTAssertEqual(moved?[2], 4)
    }

    func testABlockBegunStaysWhereItIs() {
        var engine = LiftSessionEngine(plan: plan(), startTs: 0)
        engine.start(LiftSlot(exerciseIndex: 0, setIndex: 1), now: 10)
        XCTAssertTrue(engine.hasBlockStarted(0..<2))
        XCTAssertFalse(engine.canMoveSessionBlock(containing: 1, by: 1), "the block being worked")
        XCTAssertFalse(engine.canMoveSessionBlock(containing: 2, by: -1), "nor a block trading places with it")
        XCTAssertTrue(engine.canMoveSessionBlock(containing: 2, by: 1))
        XCTAssertNil(engine.moveSessionBlock(containing: 0, by: 1))
        XCTAssertNotNil(engine.moveSessionBlock(containing: 2, by: 1))
        XCTAssertEqual(engine.currentSlot, LiftSlot(exerciseIndex: 0, setIndex: 1), "the session stays on its set")
    }

    func testTwoSupersetsSpelledAlikeDoNotMerge() {
        let imported = [LiftPlanItem(exercise: "a", supersetGroup: "A"), LiftPlanItem(exercise: "b", supersetGroup: "A"),
                        LiftPlanItem(exercise: "c"),
                        LiftPlanItem(exercise: "d", supersetGroup: "A"), LiftPlanItem(exercise: "e", supersetGroup: "A")]
        var engine = LiftSessionEngine(plan: imported, startTs: 0)
        engine.moveSessionBlock(containing: 2, by: 1)
        XCTAssertEqual(engine.plan.map(\.exercise), ["a", "b", "d", "e", "c"])
        XCTAssertEqual(engine.blocks, [0..<2, 2..<4, 4..<5])
    }

    private func rows() -> [LiftProgramItemRow] {
        let lines: [(String, String, String?)] = [("p1", "Bench", "A"), ("p2", "Triceps", "A"), ("p3", "Squat", nil),
                                                   ("p4", "Row", "B"), ("p5", "Curl", "B")]
        return lines.enumerated().map { ord, line in
                LiftProgramItemRow(id: line.0, deviceId: "d", programId: "prog", ord: ord, exercise: line.1,
                                   targetSets: 2, targetRepsLow: 8, targetRepsHigh: nil, targetRpe: nil,
                                   targetWeightKg: nil, restSec: nil, note: nil, supersetGroup: line.2)
            }
    }

    func testTheProgramCanKeepTheNewOrder() {
        let program = rows()
        XCTAssertFalse(LiftSessionController.sessionOrderChanged(plan: plan(), program: program))

        var engine = LiftSessionEngine(plan: plan(), startTs: 0)
        engine.moveSessionBlock(containing: 3, by: -1)
        XCTAssertTrue(LiftSessionController.sessionOrderChanged(plan: engine.plan, program: program))

        let kept = LiftSessionController.applyingSessionOrder(plan: engine.plan, to: program)
        XCTAssertEqual(kept.map(\.id), ["p1", "p2", "p4", "p5", "p3"])
        XCTAssertEqual(kept.map(\.ord), [0, 1, 2, 3, 4])
        XCTAssertEqual(kept.map(\.supersetGroup), ["A", "A", "B", "B", nil])
    }
}
