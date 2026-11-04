import XCTest
@testable import Strand
import WhoopStore

/// The program editor's blocks (personal fork, Supersets et blocs): a superset moves whole, a line leaves
/// its superset to sit right after it, a superset added from the body map arrives linked at the end, and
/// its lines take the targets of their last session.
final class LiftProgramBlocksTests: XCTestCase {

    // Superset A (0, 1) · Squat (2) · Superset B (3, 4, 5) · Plank (6)
    private let labels: [String?] = ["A", "A", nil, "B", "B", "B", nil]

    func testASupersetMovesWhole() {
        // Superset B up, past the squat.
        XCTAssertEqual(LiftProgramBlocks.moveProgramBlock(labels: labels, containing: 4, by: -1),
                       [0, 1, 3, 4, 5, 2, 6])
        // Superset A down, from any of its lines.
        XCTAssertEqual(LiftProgramBlocks.moveProgramBlock(labels: labels, containing: 1, by: 1),
                       [2, 0, 1, 3, 4, 5, 6])
        // Already first, already last: unchanged.
        XCTAssertEqual(LiftProgramBlocks.moveProgramBlock(labels: labels, containing: 0, by: -1), Array(0..<7))
        XCTAssertEqual(LiftProgramBlocks.moveProgramBlock(labels: labels, containing: 6, by: 1), Array(0..<7))
    }

    func testMovedSupersetsKeepTheirLinesTogether() {
        let order = LiftProgramBlocks.moveProgramBlock(labels: labels, containing: 3, by: -1)
        let moved = LiftSuperset.relabeled(order.map { labels[$0] })
        XCTAssertEqual(LiftSuperset.groups(moved), [0..<2, 2..<5])
        XCTAssertEqual(moved, ["A", "A", "B", "B", "B", nil, nil])
    }

    func testADetachedLineSitsRightAfterItsSuperset() {
        // B2 leaves: B1 and B3 stay linked, B2 follows them on its own.
        let three = LiftProgramBlocks.detachFromSuperset(labels: labels, index: 4)
        XCTAssertEqual(three.order, [0, 1, 2, 3, 5, 4, 6])
        XCTAssertEqual(three.labels, ["A", "A", nil, "B", "B", nil, nil])
        // A superset of two leaves two lines on their own.
        let two = LiftProgramBlocks.detachFromSuperset(labels: labels, index: 0)
        XCTAssertEqual(two.order, [1, 0, 2, 3, 4, 5, 6])
        XCTAssertEqual(two.labels, [nil, nil, nil, "A", "A", "A", nil])
        // A line on its own: unchanged.
        XCTAssertEqual(LiftProgramBlocks.detachFromSuperset(labels: labels, index: 2).order, Array(0..<7))
    }

    func testASupersetAddedFromTheMapArrivesLinkedAtTheEnd() {
        let after = LiftProgramBlocks.appendingSuperset(labels: labels, count: 2)
        XCTAssertEqual(after, ["A", "A", nil, "B", "B", "B", nil, "C", "C"])
        // After a superset, the new one stays a block of its own.
        XCTAssertEqual(LiftProgramBlocks.appendingSuperset(labels: ["A", "A"], count: 3),
                       ["A", "A", "B", "B", "B"])
        XCTAssertEqual(LiftProgramBlocks.appendingSuperset(labels: [], count: 1), [nil])
    }

    func testTheLinesTakeTheirLastSessionOrThreeByTen() {
        func set(_ kg: Double?, _ reps: Int?, warmup: Bool = false) -> LiftSetRow {
            LiftSetRow(id: UUID().uuidString, deviceId: "d", sessionId: "s", ord: 0, exercise: "Bench",
                       primaryMuscle: nil, setIndex: 0, weightKg: kg, reps: reps, rpe: nil, isWarmup: warmup,
                       startTs: nil, endTs: nil, restSec: nil, note: nil)
        }
        let last = [set(40, 10, warmup: true), set(60, 8), set(62.5, 6), set(62.5, 5), set(60, 8)]
        let targets = LiftProgramBlocks.supersetDraftTargets(lastSets: last)
        XCTAssertEqual(targets.sets, 4)
        XCTAssertEqual(targets.reps, 6, "the heaviest working set, the first of them on a tie")
        XCTAssertEqual(targets.weightKg, 62.5)

        let never = LiftProgramBlocks.supersetDraftTargets(lastSets: [])
        XCTAssertEqual(never.sets, 3)
        XCTAssertEqual(never.reps, 10)
        XCTAssertNil(never.weightKg)
    }
}
