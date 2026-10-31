import XCTest
@testable import Strand
import WhoopStore

/// Supersets in the Lift Log session engine (personal fork).
///
/// Consecutive plan lines sharing a label are ONE ROUND: A1 straight onto A2 with nothing to tick between
/// them, one tap records every member's set, the rest comes once, and the next round starts by itself
/// when the rest runs out. Pure, like the engine: a whole superset session is driven through a known
/// timeline with no strap, no database and no simulator.
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

    /// Start the session and return it working round 1 at t0.
    private func started(_ plan: [LiftPlanItem]) -> LiftSessionEngine {
        var e = LiftSessionEngine(plan: plan, startTs: t0)
        e.advance(now: t0)
        return e
    }

    // MARK: - The round

    func testTheRoundIsDrivenThroughItsLead() {
        let e = LiftSessionEngine(plan: plan(), startTs: t0)
        XCTAssertEqual(e.roundSlots(for: slot(1, 2)), [slot(0, 2), slot(1, 2)])
        XCTAssertEqual(e.leadSlot(slot(1, 2)), slot(0, 2))
        XCTAssertEqual(e.roundSlots(for: slot(2, 1)), [slot(2, 1)], "a line on its own is its own round")
        XCTAssertEqual(e.nextPendingSlot, slot(0, 1))
    }

    func testOneTapRecordsTheWholeRoundAndRestsTheLastLinesRest() {
        var e = started(plan())
        XCTAssertEqual(e.stage, .working(slot(0, 1)))
        XCTAssertNil(e.restRemaining(now: t0 + 10), "no rest runs inside a round")

        e.advance(now: t0 + 60)
        XCTAssertEqual(e.stage, .resting(slot(0, 1), endsAt: t0 + 60 + 95),
                       "the round's rest is the LAST line's 95 s — A1's own 30 s is never used")
        XCTAssertTrue(e.isCompleted(slot(0, 1)))
        XCTAssertTrue(e.isCompleted(slot(1, 1)))
        XCTAssertEqual(e.sets.map(\.slot), [slot(0, 1), slot(1, 1)])
        XCTAssertEqual(e.sets.map(\.startTs), [t0, t0], "both carry the round's timing")
        XCTAssertEqual(e.sets.map(\.endTs), [t0 + 60, t0 + 60])
        XCTAssertEqual(e.completedWorkingSets, 2)
    }

    func testTheNextRoundStartsByItselfWhenTheRestRunsOut() {
        var e = started(plan())
        e.advance(now: t0 + 60)                      // round 1 done, rest until t0 + 155
        XCTAssertFalse(e.isNextRoundDue(at: t0 + 100))
        XCTAssertFalse(e.startNextRoundIfRestEnded(at: t0 + 100), "rest still running")
        XCTAssertTrue(e.isNextRoundDue(at: t0 + 200))
        XCTAssertTrue(e.startNextRoundIfRestEnded(at: t0 + 200))
        XCTAssertEqual(e.stage, .working(slot(0, 2)))
        XCTAssertEqual(e.stageStartedAt, t0 + 155, "stamped with the rest's END, not with when the phone noticed")
        XCTAssertEqual(e.recordedSet(for: slot(0, 1))?.restSec, 95)
        XCTAssertEqual(e.recordedSet(for: slot(1, 1))?.restSec, 95, "every member rested the same gap")
    }

    func testALineOnItsOwnStillWaitsForTheTap() {
        var e = LiftSessionEngine(plan: plan(), startTs: t0)
        e.start(slot(2, 1), now: t0)
        e.advance(now: t0 + 30)
        XCTAssertFalse(e.isNextRoundDue(at: t0 + 1000))
        XCTAssertFalse(e.startNextRoundIfRestEnded(at: t0 + 1000))
        if case .resting = e.stage {} else { XCTFail("still resting: \(e.stage)") }
    }

    func testTheLastRestDoesNotStartTheLineAfterTheSuperset() {
        var e = started(plan())
        var now = t0
        for _ in 1...3 {
            now += 60
            e.advance(now: now)                      // round done, rest runs
            now += 130
            _ = e.startNextRoundIfRestEnded(at: now) // next round by itself, if there is one
        }
        // Superset done; its last rest ran out, but the calf raise is another machine: it waits for the tap.
        XCTAssertFalse(e.isNextRoundDue(at: now))
        if case .resting(let s, _) = e.stage { XCTAssertEqual(s, slot(0, 3)) } else { XCTFail("\(e.stage)") }
        XCTAssertEqual(e.upcomingSlot, slot(2, 1))
        e.advance(now: now)
        XCTAssertEqual(e.stage, .working(slot(2, 1)), "the tap takes the session on")
    }

    func testSkippingTheRestMovesOnAndRecordsWhatWasRested() {
        var e = started(plan())
        e.advance(now: t0 + 60)
        e.advance(now: t0 + 90)                      // skip: 30 s rested, not 95
        XCTAssertEqual(e.stage, .working(slot(0, 2)))
        XCTAssertEqual(e.recordedSet(for: slot(0, 1))?.restSec, 30)
        XCTAssertEqual(e.recordedSet(for: slot(1, 1))?.restSec, 30)
    }

    func testAFullSupersetIsThreeTapsThenTheNextLine() {
        var e = started(plan())
        var now = t0
        var rounds: [LiftSlot] = []
        while case .working(let s) = e.stage, s.exerciseIndex < 2 {
            rounds.append(s)
            now += 60
            e.advance(now: now)                      // round done
            now += 100
            e.advance(now: now)                      // rest over (tapped)
        }
        XCTAssertEqual(rounds, [slot(0, 1), slot(0, 2), slot(0, 3)], "the session only ever stands on the lead")
        XCTAssertEqual(e.sets.count, 6, "and every member's set is recorded")
        XCTAssertEqual(e.stage, .working(slot(2, 1)), "once the superset is done, on to the next line")
    }

    // MARK: - Uneven set counts

    func testWhenA1HasAnExtraSetTheLastRoundIsA1AloneWithTheGroupsRest() {
        var e = started(plan(curlSets: 2, extensionSets: 1))
        e.advance(now: t0 + 60)                      // round 1: A1·1 + A2·1
        XCTAssertEqual(e.sets.count, 2)
        e.advance(now: t0 + 160)                     // rest over → round 2
        XCTAssertEqual(e.stage, .working(slot(0, 2)))
        XCTAssertEqual(e.roundSlots(for: slot(0, 2)), [slot(0, 2)], "A2 has nothing left in this round")
        e.advance(now: t0 + 200)
        XCTAssertEqual(e.stage, .resting(slot(0, 2), endsAt: t0 + 200 + 95),
                       "the round closes on A1 alone, with the superset's rest")
        XCTAssertEqual(e.sets.count, 3)
        e.advance(now: t0 + 300)
        XCTAssertEqual(e.stage, .working(slot(2, 1)))
    }

    func testWhenA2HasAnExtraSetTheLastRoundIsA2Alone() {
        var e = started(plan(curlSets: 1, extensionSets: 2))
        e.advance(now: t0 + 60)                      // round 1
        e.advance(now: t0 + 160)                     // → round 2: only A2 has a set left
        XCTAssertEqual(e.stage, .working(slot(1, 2)))
        XCTAssertEqual(e.leadSlot(slot(1, 2)), slot(1, 2), "A2 leads a round A1 is not in")
    }

    // MARK: - What "next" says

    func testUpcomingNamesTheNextRoundAndThenTheLineAfter() {
        var e = started(plan(curlSets: 1, extensionSets: 1))
        XCTAssertEqual(e.upcomingSlot, slot(2, 1), "working the only round: next is the line after")
        var two = started(plan())
        XCTAssertEqual(two.upcomingSlot, slot(0, 2), "working round 1: next is round 2")
        two.advance(now: t0 + 60)
        XCTAssertEqual(two.upcomingSlot, slot(0, 2), "resting: still round 2")
        e.advance(now: t0 + 60)
        XCTAssertEqual(e.upcomingSlot, slot(2, 1))
    }

    @MainActor
    func testTheBarAndLockScreenNameTheRound() {
        var e = started(plan())
        XCTAssertEqual(LiftSessionController.nextLine(e), "Next: Round 2 · A · Curl + Triceps extension")
        e.advance(now: t0 + 60)
        e.advance(now: t0 + 160)
        e.advance(now: t0 + 220)
        e.advance(now: t0 + 320)                     // round 3 in hand
        XCTAssertEqual(LiftSessionController.nextLine(e), "Next: Set 1 · Calf raise")
        XCTAssertEqual(LiftSessionController.exerciseLabel(e, index: 2, name: "Calf raise"), "Calf raise",
                       "a line on its own keeps its bare name")
    }

    // MARK: - Out of order, undo, rounds added

    func testStartingA2ByHandStartsTheWholeRoundAndRedoDropsIt() {
        var e = LiftSessionEngine(plan: plan(), startTs: t0)
        e.start(slot(1, 2), now: t0)
        XCTAssertEqual(e.stage, .working(slot(0, 2)), "a member starts its round, on the lead")
        e.advance(now: t0 + 60)
        XCTAssertEqual(e.sets.count, 2)
        e.start(slot(0, 2), now: t0 + 100)
        XCTAssertTrue(e.sets.isEmpty, "a redo drops every member's record")
    }

    func testUndoingARoundPutsEveryMemberBack() {
        var e = started(plan())
        e.advance(now: t0 + 60)
        XCTAssertEqual(e.sets.count, 2)
        e.undo()
        XCTAssertEqual(e.stage, .working(slot(0, 1)))
        XCTAssertTrue(e.sets.isEmpty)
        XCTAssertEqual(e.stageStartedAt, t0)
    }

    func testAddingAndRemovingARoundMovesEveryMember() {
        var e = LiftSessionEngine(plan: plan(), startTs: t0)
        XCTAssertTrue(e.addSet(toExercise: 1))
        XCTAssertEqual(e.plan[0].targetSets, 4)
        XCTAssertEqual(e.plan[1].targetSets, 4)
        XCTAssertTrue(e.removeSet(fromExercise: 0))
        XCTAssertEqual(e.plan[0].targetSets, 3)
        XCTAssertEqual(e.plan[1].targetSets, 3)
        XCTAssertEqual(e.plan[2].targetSets, 2, "a line on its own is unaffected")
    }

    func testFinishingDuringTheRestClosesEveryMembersRest() {
        var e = started(plan())
        e.advance(now: t0 + 60)
        e.finish(now: t0 + 100)
        XCTAssertTrue(e.isFinished)
        XCTAssertEqual(e.recordedSet(for: slot(0, 1))?.restSec, 40)
        XCTAssertEqual(e.recordedSet(for: slot(1, 1))?.restSec, 40)
    }

    func testFinishingMidRoundRecordsNothingForIt() {
        var e = started(plan())
        e.finish(now: t0 + 50)
        XCTAssertTrue(e.sets.isEmpty, "the round was started, never finished")
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
        XCTAssertFalse(e.isNextRoundDue(at: t0 + 1000))
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
        e.advance(now: t0)             // → round A
        e.advance(now: t0 + 60)        // A done: rest, NOT straight into superset B
        XCTAssertEqual(e.stage, .resting(slot(0, 1), endsAt: t0 + 60 + 90))
        XCTAssertFalse(e.isNextRoundDue(at: t0 + 200), "B is another superset: it waits for the tap")
        e.advance(now: t0 + 200)
        XCTAssertEqual(e.stage, .working(slot(2, 1)))
        e.advance(now: t0 + 260)
        XCTAssertEqual(e.sets.map(\.slot), [slot(0, 1), slot(1, 1), slot(2, 1), slot(3, 1)])
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
        e.advance(now: t0 + 60)
        let snap = LiftSessionPersistence.snapshot(engine: e, programId: "p", programName: "Superset A",
                                                   pendingValues: [:], pendingWarmups: [])
        let data = try XCTUnwrap(LiftSessionPersistence.encode(snap))
        let back = LiftSessionPersistence.engine(from: try XCTUnwrap(LiftSessionPersistence.decode(data)))
        XCTAssertEqual(back.plan.map(\.supersetGroup), ["A", "A", nil])
        XCTAssertEqual(back.stage, .resting(slot(0, 1), endsAt: t0 + 155))
        XCTAssertEqual(back.sets.count, 2)
        XCTAssertEqual(back.upcomingSlot, slot(0, 2))
        XCTAssertTrue(back.isNextRoundDue(at: t0 + 200))
    }

    func testASnapshotWrittenBeforeSupersetsDecodesWithNone() throws {
        let json = """
        {"startSec":\(t0),"plan":[{"exercise":"Curl","secondaryMuscles":[],"targetSets":2,"restSec":60}],
         "stage":{"kind":"warmup"},"sets":[],"stageStartedAt":\(t0)}
        """
        let snap = try XCTUnwrap(LiftSessionPersistence.decode(Data(json.utf8)))
        XCTAssertNil(snap.plan[0].supersetGroup)
        XCTAssertFalse(LiftSessionPersistence.engine(from: snap).isInSuperset(0))
    }
}

/// The strap side of a superset: one acted-on tap ends the round; numbers typed for either member
/// land on their own set.
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

    func testOneStrapTapEndsTheRoundAndBuzzesOnce() {
        let c = controller()
        c.start(plan: [LiftPlanItem(exercise: "Curl", targetSets: 2, supersetGroup: "A"),
                       LiftPlanItem(exercise: "Extension", targetSets: 2, restSec: 95, supersetGroup: "A")],
                programId: nil, programName: "Superset A")
        c.advance()                                   // warm-up → round 1 (button)
        c.updateSet(LiftSlot(exerciseIndex: 1, setIndex: 1), weightKg: 20, reps: 12, rpe: nil, isWarmup: false)
        c.advance(fromStrap: true)                    // round 1 done
        guard case .resting(let s, _) = c.engine?.stage else { return XCTFail("\(String(describing: c.engine?.stage))") }
        XCTAssertEqual(s, LiftSlot(exerciseIndex: 0, setIndex: 1))
        XCTAssertEqual(c.engine?.sets.count, 2)
        XCTAssertEqual(c.engine?.recordedSet(for: LiftSlot(exerciseIndex: 1, setIndex: 1))?.weightKg, 20,
                       "numbers typed for A2 before the round land on A2's set")
        XCTAssertEqual(buzzes, [LiftSessionController.advanceConfirmBuzzes])
        XCTAssertEqual(c.presentation(system: .metric)?.exercise, "A · Curl + Extension")
        XCTAssertEqual(c.presentation(system: .metric)?.status, "Resting after round 1")
    }

    func testAKnockRightAfterTheRoundIsHeldBack() {
        let c = controller()
        c.start(plan: [LiftPlanItem(exercise: "Curl", targetSets: 2, supersetGroup: "A"),
                       LiftPlanItem(exercise: "Extension", targetSets: 2, supersetGroup: "A")],
                programId: nil, programName: nil)
        c.advance()                                   // warm-up → round 1 (button)
        c.advance(fromStrap: true)                    // round 1 done (strap, acted on)
        c.advance(fromStrap: true)                    // a knock seconds later
        guard case .resting = c.engine?.stage else { return XCTFail("the anti-knock window protects the rest") }
        XCTAssertEqual(buzzes, [LiftSessionController.advanceConfirmBuzzes])
    }
}
