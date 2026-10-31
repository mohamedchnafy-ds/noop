import XCTest
@testable import Strand
import WhoopStore

/// Supersets in the Lift Log session engine (personal fork).
///
/// Consecutive plan lines sharing a label are worked in alternation — A1, A2, rest, A1, A2 — and the
/// rest comes only after the last member of each round. Pure, like the engine: a whole superset
/// session is driven through a known timeline with no strap, no database and no simulator.
final class LiftSessionSupersetTests: XCTestCase {

    private let t0 = 1_700_000_000

    private func slot(_ e: Int, _ s: Int) -> LiftSlot { LiftSlot(exerciseIndex: e, setIndex: s) }

    /// Curl + triceps extension as superset A (3 sets each), then a plain line. A1 carries a rest of
    /// its own that must NEVER be used: only the last line's rest counts in a superset.
    private func plan(curlSets: Int = 3, extensionSets: Int = 3) -> [LiftPlanItem] {
        [
            LiftPlanItem(exercise: "Curl", primaryMuscle: .biceps, targetSets: curlSets, restSec: 30,
                         supersetGroup: "A"),
            LiftPlanItem(exercise: "Triceps extension", primaryMuscle: .triceps, targetSets: extensionSets,
                         restSec: 95, supersetGroup: "A"),
            LiftPlanItem(exercise: "Calf raise", primaryMuscle: .calves, targetSets: 2, restSec: 60),
        ]
    }

    /// Start the session and return it working A1 set 1 at t0.
    private func started(_ plan: [LiftPlanItem]) -> LiftSessionEngine {
        var e = LiftSessionEngine(plan: plan, startTs: t0)
        e.advance(now: t0)
        return e
    }

    // MARK: - The alternation

    func testOneStepGoesFromA1StraightToA2WithNoRestStage() {
        var e = started(plan())
        XCTAssertEqual(e.stage, .working(slot(0, 1)))

        e.advance(now: t0 + 40)
        XCTAssertEqual(e.stage, .working(slot(1, 1)), "A1 done → A2 starts in the same step")
        XCTAssertEqual(e.stageStartedAt, t0 + 40, "A2 starts the instant A1 ends")
        XCTAssertEqual(e.sets.count, 1)
        XCTAssertEqual(e.sets[0].slot, slot(0, 1))
        XCTAssertEqual(e.sets[0].endTs, t0 + 40)
        XCTAssertEqual(e.sets[0].restSec, 0, "nothing was rested between A1 and A2, and it says so")
        XCTAssertNil(e.restRemaining(now: t0 + 41), "there is no rest running")
    }

    func testTheRestComesOnlyAfterTheLastMemberAndUsesTheLastLinesRest() {
        var e = started(plan())
        e.advance(now: t0 + 40)        // A1·1 done → A2·1
        e.advance(now: t0 + 80)        // A2·1 done → rest
        XCTAssertEqual(e.stage, .resting(slot(1, 1), endsAt: t0 + 80 + 95),
                       "the round's rest is the LAST line's 95 s — A1's own 30 s is never used")
        XCTAssertEqual(e.restRemaining(now: t0 + 100), 75)
    }

    func testAfterTheRestTheNextRoundStartsBackAtTheFirstMember() {
        var e = started(plan())
        e.advance(now: t0 + 40)        // → A2·1
        e.advance(now: t0 + 80)        // → rest
        e.advance(now: t0 + 175)       // rest over → A1·2
        XCTAssertEqual(e.stage, .working(slot(0, 2)))
        XCTAssertEqual(e.recordedSet(for: slot(1, 1))?.restSec, 95, "the rest actually taken is recorded")
    }

    func testAFullSupersetRunsA1A2RestThreeTimesThenLeavesTheGroup() {
        var e = started(plan())
        var now = t0
        var order: [LiftSlot] = []
        // Walk until the superset is finished, recording every set as it starts.
        while case .working(let s) = e.stage, s.exerciseIndex < 2 {
            order.append(s)
            now += 30
            e.advance(now: now)                         // set done
            if case .resting = e.stage { now += 90; e.advance(now: now) }  // rest over
        }
        XCTAssertEqual(order, [slot(0, 1), slot(1, 1), slot(0, 2), slot(1, 2), slot(0, 3), slot(1, 3)])
        XCTAssertEqual(e.stage, .working(slot(2, 1)), "once the superset is done, on to the next line")
    }

    // MARK: - Uneven set counts

    func testWhenA1HasAnExtraSetItsRoundEndsOnA1AndRestsTheGroupsRest() {
        var e = started(plan(curlSets: 2, extensionSets: 1))
        e.advance(now: t0 + 30)        // A1·1 → A2·1
        e.advance(now: t0 + 60)        // A2·1 → rest
        e.advance(now: t0 + 155)       // → A1·2
        XCTAssertEqual(e.stage, .working(slot(0, 2)))
        XCTAssertNil(e.supersetPartner(after: slot(0, 2)), "A2 has nothing left in this round")
        e.advance(now: t0 + 185)
        XCTAssertEqual(e.stage, .resting(slot(0, 2), endsAt: t0 + 185 + 95),
                       "the round closes on A1, with the superset's rest")
        e.advance(now: t0 + 280)
        XCTAssertEqual(e.stage, .working(slot(2, 1)))
    }

    func testWhenA2HasAnExtraSetTheLastRoundIsA2Alone() {
        var e = started(plan(curlSets: 1, extensionSets: 2))
        e.advance(now: t0 + 30)        // A1·1 → A2·1
        e.advance(now: t0 + 60)        // → rest
        e.advance(now: t0 + 155)       // → A2·2, the only member with a set left
        XCTAssertEqual(e.stage, .working(slot(1, 2)))
    }

    // MARK: - What "next" says

    func testUpcomingNamesThePartnerMidRoundAndTheFirstMemberAfterTheRest() {
        var e = started(plan())
        XCTAssertEqual(e.upcomingSlot, slot(1, 1), "working A1: next is A2, no rest between")
        e.advance(now: t0 + 40)
        XCTAssertEqual(e.upcomingSlot, slot(0, 2), "working A2: next is A1 of the next round")
        e.advance(now: t0 + 80)
        XCTAssertEqual(e.upcomingSlot, slot(0, 2), "resting: still A1 of the next round")
    }

    func testTheBarAndLockScreenTagSupersetLines() {
        var e = started(plan())
        XCTAssertEqual(LiftSessionController.nextLine(e), "Next: Set 1 · A2 · Triceps extension")
        e.advance(now: t0 + 40)
        XCTAssertEqual(LiftSessionController.nextLine(e), "Next: Set 2 · A1 · Curl")
        XCTAssertEqual(LiftSessionController.exerciseLabel(e, index: 2, name: "Calf raise"), "Calf raise",
                       "a line on its own keeps its bare name")
    }

    // MARK: - Out of order, and undo

    func testStartingA2ByHandRestsAfterItThenGoesBackToA1() {
        var e = LiftSessionEngine(plan: plan(), startTs: t0)
        e.start(slot(1, 1), now: t0)   // the curl station is taken
        e.advance(now: t0 + 30)
        XCTAssertEqual(e.stage, .resting(slot(1, 1), endsAt: t0 + 30 + 95),
                       "A2 is the last member, so it closes the round")
        e.advance(now: t0 + 125)
        XCTAssertEqual(e.stage, .working(slot(0, 1)), "the skipped A1·1 is what comes next")
        e.advance(now: t0 + 155)
        XCTAssertEqual(e.stage, .working(slot(1, 2)), "and its partner is A2's next pending set")
    }

    func testUndoingTheTransitionPutsTheSessionBackOnA1() {
        var e = started(plan())
        e.advance(now: t0 + 40)
        XCTAssertEqual(e.stage, .working(slot(1, 1)))
        e.undo()
        XCTAssertEqual(e.stage, .working(slot(0, 1)))
        XCTAssertTrue(e.sets.isEmpty, "A1·1 is no longer recorded")
        XCTAssertEqual(e.stageStartedAt, t0)
    }

    func testFinishingMidSupersetRecordsNoInventedRest() {
        var e = started(plan())
        e.advance(now: t0 + 40)        // A1·1 → A2·1
        e.finish(now: t0 + 50)
        XCTAssertTrue(e.isFinished)
        XCTAssertEqual(e.sets.map(\.slot), [slot(0, 1)], "A2·1 was started, never finished")
        XCTAssertEqual(e.sets[0].restSec, 0)
    }

    // MARK: - What makes a superset

    func testA1AndA2LabelsMeanSupersetA() {
        let p = [LiftPlanItem(exercise: "Curl", supersetGroup: "a1"),
                 LiftPlanItem(exercise: "Extension", supersetGroup: " A2 ")]
        let e = LiftSessionEngine(plan: p, startTs: t0)
        XCTAssertEqual(e.supersetMembers(of: 0), [0, 1])
        XCTAssertEqual(e.supersetTag(of: 0), "A1")
        XCTAssertEqual(e.supersetTag(of: 1), "A2")
    }

    func testALabelOnOneLineAloneIsNotASuperset() {
        let p = [LiftPlanItem(exercise: "Squat", targetSets: 2, restSec: 120, supersetGroup: "A"),
                 LiftPlanItem(exercise: "Curl", targetSets: 2, restSec: 60)]
        var e = LiftSessionEngine(plan: p, startTs: t0)
        XCTAssertFalse(e.isInSuperset(0))
        XCTAssertNil(e.supersetTag(of: 0))
        e.advance(now: t0)
        e.advance(now: t0 + 30)
        XCTAssertEqual(e.stage, .resting(slot(0, 1), endsAt: t0 + 30 + 120), "behaves exactly as before")
    }

    func testOnlyConsecutiveLinesFormASuperset() {
        let p = [LiftPlanItem(exercise: "Curl", supersetGroup: "A"),
                 LiftPlanItem(exercise: "Squat"),
                 LiftPlanItem(exercise: "Extension", supersetGroup: "A")]
        let e = LiftSessionEngine(plan: p, startTs: t0)
        XCTAssertEqual(e.blocks, [0..<1, 1..<2, 2..<3])
        XCTAssertFalse(e.isInSuperset(0))
        XCTAssertFalse(e.isInSuperset(2))
    }

    func testTwoSupersetsBackToBackStayApart() {
        let p = [LiftPlanItem(exercise: "Curl", targetSets: 1, supersetGroup: "A"),
                 LiftPlanItem(exercise: "Extension", targetSets: 1, restSec: 90, supersetGroup: "A"),
                 LiftPlanItem(exercise: "Bench", targetSets: 1, supersetGroup: "B"),
                 LiftPlanItem(exercise: "Row", targetSets: 1, restSec: 120, supersetGroup: "B")]
        var e = LiftSessionEngine(plan: p, startTs: t0)
        XCTAssertEqual(e.blocks, [0..<2, 2..<4])
        XCTAssertEqual(e.supersetTag(of: 2), "B1")
        XCTAssertEqual(e.blockStart(of: 3), 2)
        e.advance(now: t0)             // → A1
        e.advance(now: t0 + 30)        // → A2
        e.advance(now: t0 + 60)        // A2 done: rest, NOT straight into superset B
        XCTAssertEqual(e.stage, .resting(slot(1, 1), endsAt: t0 + 60 + 90))
        e.advance(now: t0 + 150)
        XCTAssertEqual(e.stage, .working(slot(2, 1)))
        e.advance(now: t0 + 180)
        XCTAssertEqual(e.stage, .working(slot(3, 1)))
    }

    func testAPlanWithNoSupersetsIsUnchanged() {
        let p = [LiftPlanItem(exercise: "Leg press", targetSets: 2, restSec: 90),
                 LiftPlanItem(exercise: "Leg curl", targetSets: 1, restSec: 60)]
        var e = LiftSessionEngine(plan: p, startTs: t0)
        e.advance(now: t0)
        XCTAssertEqual(e.upcomingSlot, slot(0, 2))
        e.advance(now: t0 + 30)
        XCTAssertEqual(e.stage, .resting(slot(0, 1), endsAt: t0 + 30 + 90))
        e.advance(now: t0 + 120)
        XCTAssertEqual(e.stage, .working(slot(0, 2)))
    }

    // MARK: - Crash safety

    func testTheSupersetSurvivesTheCrashSnapshot() throws {
        var e = started(plan())
        e.advance(now: t0 + 40)
        let snap = LiftSessionPersistence.snapshot(engine: e, programId: "p", programName: "Superset A",
                                                   pendingValues: [:], pendingWarmups: [])
        let data = try XCTUnwrap(LiftSessionPersistence.encode(snap))
        let back = LiftSessionPersistence.engine(from: try XCTUnwrap(LiftSessionPersistence.decode(data)))
        XCTAssertEqual(back.plan.map(\.supersetGroup), ["A", "A", nil])
        XCTAssertEqual(back.stage, .working(slot(1, 1)))
        XCTAssertEqual(back.upcomingSlot, slot(0, 2))
    }

    func testASnapshotWrittenBeforeSupersetsDecodesWithNone() throws {
        let json = """
        {"startSec":\(t0),"plan":[{"exercise":"Curl","secondaryMuscles":[],"targetSets":2,"restSec":60}],
         "stage":{"kind":"warmup"},"sets":[],"stageStartedAt":\(t0)}
        """
        // A plausible start time: the decoder refuses one more than a day in the future, not the past.
        let snap = try XCTUnwrap(LiftSessionPersistence.decode(Data(json.utf8)))
        XCTAssertNil(snap.plan[0].supersetGroup)
        XCTAssertFalse(LiftSessionPersistence.engine(from: snap).isInSuperset(0))
    }
}

/// The strap side of a superset: the A1 → A2 step is an ordinary acted-on tap.
@MainActor
final class LiftSessionSupersetStrapTests: XCTestCase {

    private var buzzes: [UInt8] = []

    private func controller() -> LiftSessionController {
        LiftSessionController(buzz: { [unowned self] in buzzes.append($0) },
                              setStrapHandler: { _ in }, log: { _ in })
    }

    override func tearDown() {
        LiftSessionPersistence.clear()
        buzzes = []
        super.tearDown()
    }

    func testTheA1ToA2StepBuzzesOnceAndStartsNoRest() {
        let c = controller()
        c.start(plan: [LiftPlanItem(exercise: "Curl", targetSets: 2, supersetGroup: "A"),
                       LiftPlanItem(exercise: "Extension", targetSets: 2, restSec: 95, supersetGroup: "A")],
                programId: nil, programName: "Superset A")
        c.advance(fromStrap: true)                    // warm-up → A1·1
        // A knock-free second tap, as the user would make it after a real set: bypass the 5 s window
        // by acting through the on-screen path, which is never held back.
        c.advance()                                   // A1·1 → A2·1
        XCTAssertEqual(c.engine?.stage, .working(LiftSlot(exerciseIndex: 1, setIndex: 1)))
        XCTAssertEqual(buzzes, [LiftSessionController.advanceConfirmBuzzes],
                       "one confirming buzz for the strap tap, and no rest warning for a step with no rest")
        XCTAssertEqual(c.presentation(system: .metric)?.exercise, "A2 · Extension")
    }

    func testAKnockRightAfterTheA1ToA2StepIsHeldBack() {
        let c = controller()
        c.start(plan: [LiftPlanItem(exercise: "Curl", targetSets: 2, supersetGroup: "A"),
                       LiftPlanItem(exercise: "Extension", targetSets: 2, supersetGroup: "A")],
                programId: nil, programName: nil)
        c.advance()                                   // warm-up → A1·1 (button)
        c.advance(fromStrap: true)                    // A1·1 → A2·1 (strap, acted on)
        c.advance(fromStrap: true)                    // a knock seconds later
        XCTAssertEqual(c.engine?.stage, .working(LiftSlot(exerciseIndex: 1, setIndex: 1)),
                       "the anti-knock window protects A2 exactly as it protects any set")
        XCTAssertEqual(buzzes, [LiftSessionController.advanceConfirmBuzzes])
    }
}
