import XCTest
@testable import Strand
import WhoopStore

/// A superset is one round, not two sets: the pair is performed back to back, recorded with one tap,
/// rested from together, and the next round starts by itself when the rest runs out.
final class LiftSessionSupersetTests: XCTestCase {

    private let t0 = 1_700_000_000

    /// Squat + leg curl as a superset of 3 rounds, then a line on its own.
    private func plan() -> [LiftPlanItem] {
        [
            LiftPlanItem(exercise: "Squat", primaryMuscle: .quads, targetSets: 3, restSec: 120,
                         targetRepsLow: 10, targetWeightKg: 40, supersetGroup: "A"),
            LiftPlanItem(exercise: "Lying leg curl", primaryMuscle: .hamstrings, targetSets: 3, restSec: 120,
                         targetRepsLow: 10, targetWeightKg: 60, supersetGroup: "A"),
            LiftPlanItem(exercise: "Calf raise", primaryMuscle: .calves, targetSets: 2, restSec: 60),
        ]
    }

    private func slot(_ e: Int, _ s: Int) -> LiftSlot { LiftSlot(exerciseIndex: e, setIndex: s) }

    func testMembersAndLead() {
        let e = LiftSessionEngine(plan: plan(), startTs: t0)
        XCTAssertEqual(e.supersetMembers(of: 0), [0, 1])
        XCTAssertEqual(e.supersetMembers(of: 1), [0, 1])
        XCTAssertEqual(e.supersetMembers(of: 2), [2])
        XCTAssertTrue(e.isSupersetLead(0))
        XCTAssertFalse(e.isSupersetLead(1))
        XCTAssertTrue(e.isSupersetLead(2))
        XCTAssertEqual(e.leadSlot(slot(1, 2)), slot(0, 2))
        XCTAssertEqual(e.roundSlots(for: slot(1, 2)), [slot(0, 2), slot(1, 2)])
    }

    func testAGroupOfOneIsNoSuperset() {
        let e = LiftSessionEngine(plan: [LiftPlanItem(exercise: "Squat", supersetGroup: "A")], startTs: t0)
        XCTAssertFalse(e.isSuperset(0))
    }

    func testOneTapRecordsTheWholeRoundAndRestsOnce() {
        var e = LiftSessionEngine(plan: plan(), startTs: t0)
        e.advance(now: t0 + 60)                      // start round 1
        XCTAssertEqual(e.stage, .working(slot(0, 1)))
        e.advance(now: t0 + 120)                     // round done
        XCTAssertEqual(e.stage, .resting(slot(0, 1), endsAt: t0 + 240))
        XCTAssertTrue(e.isCompleted(slot(0, 1)))
        XCTAssertTrue(e.isCompleted(slot(1, 1)))
        XCTAssertEqual(e.sets.count, 2)
        XCTAssertEqual(e.sets.map(\.startTs), [t0 + 60, t0 + 60])
        XCTAssertEqual(e.sets.map(\.endTs), [t0 + 120, t0 + 120])
        XCTAssertEqual(e.completedWorkingSets, 2)
    }

    func testTheNextRoundStartsByItselfWhenTheRestRunsOut() {
        var e = LiftSessionEngine(plan: plan(), startTs: t0)
        e.advance(now: t0 + 60)
        e.advance(now: t0 + 120)
        XCTAssertFalse(e.startNextRoundIfRestEnded(at: t0 + 200), "rest still running")
        XCTAssertTrue(e.startNextRoundIfRestEnded(at: t0 + 300))
        XCTAssertEqual(e.stage, .working(slot(0, 2)))
        // Stamped with the rest's END, not with when the phone noticed.
        XCTAssertEqual(e.stageStartedAt, t0 + 240)
        XCTAssertEqual(e.recordedSet(for: slot(0, 1))?.restSec, 120)
        XCTAssertEqual(e.recordedSet(for: slot(1, 1))?.restSec, 120)
    }

    func testAnOrdinaryLineStillWaitsForTheTap() {
        var e = LiftSessionEngine(plan: plan(), startTs: t0)
        e.start(slot(2, 1), now: t0)
        e.advance(now: t0 + 30)
        XCTAssertFalse(e.startNextRoundIfRestEnded(at: t0 + 1000))
        if case .resting = e.stage {} else { XCTFail("still resting: \(e.stage)") }
    }

    func testTheLastRestDoesNotStartAnything() {
        var e = LiftSessionEngine(plan: plan(), startTs: t0)
        var now = t0
        for _ in 1...3 {
            e.advance(now: now); now += 60
            e.advance(now: now); now += 130
            _ = e.startNextRoundIfRestEnded(at: now)
        }
        // Superset done; its last rest ran out, but the calf raise is another machine: it waits for the tap.
        if case .resting(let s, _) = e.stage { XCTAssertEqual(s, slot(0, 3)) } else { XCTFail("\(e.stage)") }
        XCTAssertEqual(e.upcomingSlot, slot(2, 1))
    }

    func testSkippingTheRestMovesOnAndRecordsWhatWasRested() {
        var e = LiftSessionEngine(plan: plan(), startTs: t0)
        e.advance(now: t0)
        e.advance(now: t0 + 60)
        e.advance(now: t0 + 90)                      // skip: 30 s rested, not 120
        XCTAssertEqual(e.stage, .working(slot(0, 2)))
        XCTAssertEqual(e.recordedSet(for: slot(0, 1))?.restSec, 30)
        XCTAssertEqual(e.recordedSet(for: slot(1, 1))?.restSec, 30)
    }

    func testStartingAMemberStartsItsLeadAndRedoDropsTheWholeRound() {
        var e = LiftSessionEngine(plan: plan(), startTs: t0)
        e.start(slot(1, 2), now: t0)
        XCTAssertEqual(e.stage, .working(slot(0, 2)))
        e.advance(now: t0 + 60)
        XCTAssertEqual(e.sets.count, 2)
        e.start(slot(0, 2), now: t0 + 100)
        XCTAssertTrue(e.sets.isEmpty)
    }

    func testNextPendingNeverLandsOnAMember() {
        var e = LiftSessionEngine(plan: plan(), startTs: t0)
        XCTAssertEqual(e.nextPendingSlot, slot(0, 1))
        var now = t0
        for _ in 1...3 {
            e.advance(now: now); now += 60
            e.advance(now: now); now += 130
            e.advance(now: now)
        }
        XCTAssertEqual(e.currentSlot, slot(2, 1))
        XCTAssertEqual(e.upcomingSlot, slot(2, 2))
    }

    func testAddingAndRemovingARoundMovesEveryMember() {
        var e = LiftSessionEngine(plan: plan(), startTs: t0)
        XCTAssertTrue(e.addSet(toExercise: 1))
        XCTAssertEqual(e.plan[0].targetSets, 4)
        XCTAssertEqual(e.plan[1].targetSets, 4)
        XCTAssertTrue(e.removeSet(fromExercise: 0))
        XCTAssertEqual(e.plan[0].targetSets, 3)
        XCTAssertEqual(e.plan[1].targetSets, 3)
        XCTAssertEqual(e.plan[2].targetSets, 2, "an ordinary line is unaffected")
    }

    func testFinishClosesEveryMembersRest() {
        var e = LiftSessionEngine(plan: plan(), startTs: t0)
        e.advance(now: t0)
        e.advance(now: t0 + 60)
        e.finish(now: t0 + 100)
        XCTAssertEqual(e.recordedSet(for: slot(0, 1))?.restSec, 40)
        XCTAssertEqual(e.recordedSet(for: slot(1, 1))?.restSec, 40)
    }

    func testTheSnapshotKeepsTheGroup() {
        let e = LiftSessionEngine(plan: plan(), startTs: t0)
        let snapshot = LiftSessionPersistence.snapshot(engine: e, programId: nil, programName: nil,
                                                       pendingValues: [:], pendingWarmups: [])
        let back = LiftSessionPersistence.engine(from: snapshot)
        XCTAssertEqual(back.plan.map(\.supersetGroup), ["A", "A", nil])
        XCTAssertTrue(back.isSuperset(0))
    }

    // MARK: - The editor's grouping

    func testLinkingAndUnlinkingLines() {
        let ids = ["a", "b", "c", "d"]
        var g = LiftSupersetGroups.linking(1, toPrevious: ids, groups: [:])
        XCTAssertNotNil(g["a"])
        XCTAssertEqual(g["a"], g["b"])
        XCTAssertTrue(LiftSupersetGroups.isLinkedToPrevious(1, ids: ids, groups: g))
        g = LiftSupersetGroups.linking(2, toPrevious: ids, groups: g)
        XCTAssertEqual(g["a"], g["c"], "three in a chain share one group")
        g = LiftSupersetGroups.unlinking(2, fromPrevious: ids, groups: g)
        XCTAssertEqual(g["a"], g["b"])
        XCTAssertNil(g["c"], "a group of one is dropped")
        XCTAssertFalse(LiftSupersetGroups.isLinkedToPrevious(2, ids: ids, groups: g))
    }

    func testAReorderCutsAGroupAtTheGap() {
        let g: LiftSupersetGroups.Groups = ["a": "g", "b": "x", "c": "g"]
        let out = LiftSupersetGroups.normalised(ids: ["a", "b", "c"], groups: g)
        XCTAssertTrue(out.isEmpty, "a and c are no longer adjacent, and b is alone")
        let kept = LiftSupersetGroups.normalised(ids: ["a", "c", "b"], groups: g)
        XCTAssertEqual(kept["a"], kept["c"])
        XCTAssertNil(kept["b"])
    }

    func testStoreRoundTripsAndDropsDeletedLines() {
        let defaults = UserDefaults(suiteName: "LiftSessionSupersetTests")!
        defaults.removePersistentDomain(forName: "LiftSessionSupersetTests")
        LiftSupersetGroups.store(["a": "g", "b": "g", "zombie": "g"], programId: "p",
                                 items: ["a", "b"], in: defaults)
        XCTAssertEqual(LiftSupersetGroups.groups(programId: "p", from: defaults), ["a": "g", "b": "g"])
        LiftSupersetGroups.remove(programId: "p", from: defaults)
        XCTAssertTrue(LiftSupersetGroups.groups(programId: "p", from: defaults).isEmpty)
    }
}
