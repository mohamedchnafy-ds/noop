import XCTest
@testable import Strand
import WhoopStore

/// The guided superset screens (personal fork): which screen the session is on (`LiftSupersetGuide.make`),
/// the three moves only they offer — more rest, a different rest for the block, leaving the block — and
/// the program question a changed rest raises at the end. Pure, like the engine: driven through a known
/// timeline with no strap, no store and no SwiftUI.
final class LiftSessionGuidedTests: XCTestCase {

    private let t0 = 1_700_000_000

    private func slot(_ e: Int, _ s: Int) -> LiftSlot { LiftSlot(exerciseIndex: e, setIndex: s) }

    /// A line on its own, then squat + leg curl as superset A (3 rounds, 120 s rest on the LAST line),
    /// then another line on its own: three blocks, the superset second.
    private func plan() -> [LiftPlanItem] {
        [
            LiftPlanItem(exercise: "Bike", targetSets: 1, restSec: 60, programItemId: "bike"),
            LiftPlanItem(exercise: "Squat", primaryMuscle: .quads, secondaryMuscles: [.glutes],
                         targetSets: 3, restSec: 30, targetWeightKg: 40, programItemId: "squat",
                         supersetGroup: "A"),
            LiftPlanItem(exercise: "Leg curl", primaryMuscle: .hamstrings, targetSets: 3, restSec: 120,
                         targetWeightKg: 60, programItemId: "curl", supersetGroup: "A"),
            LiftPlanItem(exercise: "Calf raise", targetSets: 2, restSec: 45, programItemId: "calf"),
        ]
    }

    /// The bike done, resting before the superset.
    private func beforeTheSuperset() -> LiftSessionEngine {
        var e = LiftSessionEngine(plan: plan(), startTs: t0)
        e.advance(now: t0)            // warm-up → bike
        e.advance(now: t0 + 300)      // bike done → rest until t0 + 360
        return e
    }

    // MARK: - Which screen

    func testALineOnItsOwnKeepsTheSheet() {
        let e = LiftSessionEngine(plan: plan(), startTs: t0)
        XCTAssertNil(LiftSupersetGuide.make(e, now: t0), "the session opens on the bike, a line on its own")
    }

    func testTheRestBeforeASupersetShowsItReadyWithTheRestStillRunning() throws {
        let e = beforeTheSuperset()
        let guide = try XCTUnwrap(LiftSupersetGuide.make(e, now: t0 + 310))
        XCTAssertEqual(guide.phase, .ready(restEndsAt: t0 + 360))
        XCTAssertEqual(guide.letter, "A")
        XCTAssertEqual(guide.lead, 1)
        XCTAssertEqual(guide.members.map(\.tag), ["A1", "A2"])
        XCTAssertEqual(guide.blockNumber, 2)
        XCTAssertEqual(guide.blockCount, 3, "bike, superset A, calf raise")
        XCTAssertEqual(guide.rounds, 3)
        XCTAssertEqual(guide.round, 1)
        XCTAssertEqual(guide.restSec, 120, "the rest of the superset's LAST line")
        XCTAssertTrue(guide.doneRounds.isEmpty)

        let later = try XCTUnwrap(LiftSupersetGuide.make(e, now: t0 + 400))
        XCTAssertEqual(later.phase, .ready(restEndsAt: nil), "a rest that is over is not shown")
    }

    func testASupersetFirstOpensReady() throws {
        let e = LiftSessionEngine(plan: Array(plan().dropFirst()), startTs: t0)
        let guide = try XCTUnwrap(LiftSupersetGuide.make(e, now: t0))
        XCTAssertEqual(guide.phase, .ready(restEndsAt: nil))
        XCTAssertEqual(guide.blockNumber, 1)
    }

    func testARoundIsWorkingThenRestingThenTheNextRound() throws {
        var e = beforeTheSuperset()
        e.advance(now: t0 + 360)                       // round 1 starts
        var guide = try XCTUnwrap(LiftSupersetGuide.make(e, now: t0 + 370))
        XCTAssertEqual(guide.phase, .working(startedAt: t0 + 360))
        XCTAssertEqual(guide.round, 1)

        e.advance(now: t0 + 412)                       // round 1 done after 52 s
        guide = try XCTUnwrap(LiftSupersetGuide.make(e, now: t0 + 420))
        XCTAssertEqual(guide.phase, .resting(startedAt: t0 + 412, endsAt: t0 + 532))
        XCTAssertEqual(guide.round, 1)
        XCTAssertEqual(guide.nextRound, 2)
        XCTAssertEqual(guide.lastRoundSec, 52)
        XCTAssertEqual(guide.doneRounds, [1])

        XCTAssertTrue(e.startNextRoundIfRestEnded(at: t0 + 532))
        guide = try XCTUnwrap(LiftSupersetGuide.make(e, now: t0 + 540))
        XCTAssertEqual(guide.phase, .working(startedAt: t0 + 532))
        XCTAssertEqual(guide.round, 2)
    }

    func testAfterTheLastRoundTheSheetTakesOverForALineOnItsOwn() {
        var e = beforeTheSuperset()
        e.advance(now: t0 + 360)
        e.advance(now: t0 + 400)                       // round 1
        e.advance(now: t0 + 450)
        e.advance(now: t0 + 500)                       // round 2
        e.advance(now: t0 + 550)
        e.advance(now: t0 + 600)                       // round 3 → rest before the calf raise
        XCTAssertNil(LiftSupersetGuide.make(e, now: t0 + 610), "the calf raise is a line on its own")
    }

    func testTheRestAfterOneSupersetShowsTheNextOneReady() throws {
        var lines = Array(plan().prefix(3))
        lines[1].targetSets = 1
        lines[2].targetSets = 1
        lines += [LiftPlanItem(exercise: "Press", targetSets: 1, supersetGroup: "B"),
                  LiftPlanItem(exercise: "Row", targetSets: 1, restSec: 90, supersetGroup: "B")]
        var e = LiftSessionEngine(plan: lines, startTs: t0)
        e.advance(now: t0)
        e.advance(now: t0 + 60)                        // bike
        e.advance(now: t0 + 120)
        e.advance(now: t0 + 180)                       // A's only round → rest
        let guide = try XCTUnwrap(LiftSupersetGuide.make(e, now: t0 + 190))
        XCTAssertEqual(guide.letter, "B")
        XCTAssertEqual(guide.phase, .ready(restEndsAt: t0 + 300))
        XCTAssertEqual(guide.restSec, 90)
    }

    func testEverythingDoneLeavesTheGuidedScreens() {
        var e = LiftSessionEngine(plan: [LiftPlanItem(exercise: "Curl", targetSets: 1, supersetGroup: "A"),
                                         LiftPlanItem(exercise: "Dip", targetSets: 1, supersetGroup: "A")],
                                  startTs: t0)
        e.advance(now: t0)
        e.advance(now: t0 + 60)
        XCTAssertNil(LiftSupersetGuide.make(e, now: t0 + 70), "the sheet says all sets are done and leads to Finish")
    }

    // MARK: - +30 s

    func testMoreRestPushesTheEndBackAndUndoes() {
        var e = beforeTheSuperset()
        e.advance(now: t0 + 360)
        e.advance(now: t0 + 400)                       // rest until t0 + 520
        XCTAssertTrue(e.extendRest(by: 30, now: t0 + 450))
        XCTAssertEqual(e.stage, .resting(slot(1, 1), endsAt: t0 + 550))
        XCTAssertFalse(e.isNextRoundDue(at: t0 + 530), "the round waits for the longer rest")
        XCTAssertTrue(e.isNextRoundDue(at: t0 + 550))
        e.undo()
        XCTAssertEqual(e.stage, .resting(slot(1, 1), endsAt: t0 + 520))
    }

    func testMoreRestAfterTheRestRanOutCountsFromNow() {
        var e = beforeTheSuperset()                    // the bike's rest ended at t0 + 360
        XCTAssertTrue(e.extendRest(by: 30, now: t0 + 400))
        XCTAssertEqual(e.stage, .resting(slot(0, 1), endsAt: t0 + 430))
    }

    func testMoreRestDoesNothingOutsideARest() {
        var e = LiftSessionEngine(plan: plan(), startTs: t0)
        XCTAssertFalse(e.extendRest(by: 30, now: t0))
        e.advance(now: t0)
        XCTAssertFalse(e.extendRest(by: 30, now: t0 + 10))
        XCTAssertEqual(e.stage, .working(slot(0, 1)))
    }

    // MARK: - The block's rest

    func testTheBlocksRestIsSetOnItsLastLineAndBounded() {
        var e = LiftSessionEngine(plan: plan(), startTs: t0)
        XCTAssertTrue(e.setRest(135, forBlockOf: 1))
        XCTAssertEqual(e.plan[2].restSec, 135, "the line `restAfter` reads")
        XCTAssertEqual(e.plan[1].restSec, 30, "A1's own rest is never used, and is left alone")
        XCTAssertEqual(e.restAfter(slot(1, 1)), 135)
        XCTAssertFalse(e.setRest(135, forBlockOf: 2), "no change, nothing to undo")
        XCTAssertTrue(e.setRest(5_000, forBlockOf: 1))
        XCTAssertEqual(e.plan[2].restSec, LiftSessionEngine.maxRestSec)
        XCTAssertTrue(e.setRest(-15, forBlockOf: 1))
        XCTAssertEqual(e.plan[2].restSec, 0)
        e.undo()
        XCTAssertEqual(e.plan[2].restSec, LiftSessionEngine.maxRestSec)
    }

    func testANewRestAppliesToTheNextRestNotTheRunningOne() {
        var e = beforeTheSuperset()
        e.advance(now: t0 + 360)
        e.advance(now: t0 + 400)                       // rest until t0 + 520
        e.setRest(60, forBlockOf: 1)
        XCTAssertEqual(e.stage, .resting(slot(1, 1), endsAt: t0 + 520))
        _ = e.startNextRoundIfRestEnded(at: t0 + 520)
        e.advance(now: t0 + 560)
        XCTAssertEqual(e.stage, .resting(slot(1, 2), endsAt: t0 + 620))
    }

    // MARK: - Leaving the block

    func testEndingTheBlockMidRoundRecordsTheRoundAndDropsTheRest() {
        var e = beforeTheSuperset()
        e.advance(now: t0 + 360)
        e.advance(now: t0 + 400)                       // round 1
        _ = e.startNextRoundIfRestEnded(at: t0 + 520)  // round 2 starts
        XCTAssertTrue(e.endBlock(now: t0 + 570))
        XCTAssertTrue(e.isCompleted(slot(1, 2)))
        XCTAssertTrue(e.isCompleted(slot(2, 2)), "the round in hand was lifted, A2 included")
        XCTAssertEqual(e.plan[1].targetSets, 2)
        XCTAssertEqual(e.plan[2].targetSets, 2, "round 3 is gone from both lines")
        XCTAssertEqual(e.stage, .resting(slot(1, 2), endsAt: t0 + 690), "the usual rest follows")
        XCTAssertFalse(e.isNextRoundDue(at: t0 + 690), "nothing of the block is left to start by itself")
        XCTAssertEqual(e.slotAfter(slot(1, 2)), slot(3, 1), "the next block waits for its tap")
        XCTAssertTrue(e.unperformedSlots.allSatisfy { $0.exerciseIndex == 3 })
    }

    func testEndingTheBlockDuringItsRestKeepsTheRestRunning() {
        var e = beforeTheSuperset()
        e.advance(now: t0 + 360)
        e.advance(now: t0 + 400)                       // round 1, rest until t0 + 520
        XCTAssertTrue(e.endBlock(now: t0 + 430))
        XCTAssertEqual(e.stage, .resting(slot(1, 1), endsAt: t0 + 520))
        XCTAssertEqual(e.plan[1].targetSets, 1)
        XCTAssertEqual(e.plan[2].targetSets, 1)
        XCTAssertFalse(e.isNextRoundDue(at: t0 + 520))
    }

    func testEndingTheBlockIsOneUndo() {
        var e = beforeTheSuperset()
        e.advance(now: t0 + 360)
        let before = e
        e.endBlock(now: t0 + 400)
        e.undo()
        XCTAssertEqual(e.stage, before.stage)
        XCTAssertEqual(e.sets, before.sets)
        XCTAssertEqual(e.plan, before.plan)
    }

    func testEndingTheBlockNeedsASet() {
        var e = LiftSessionEngine(plan: plan(), startTs: t0)
        XCTAssertFalse(e.endBlock(now: t0))
        XCTAssertFalse(e.canUndo)
    }

    // MARK: - Last time

    private func row(_ session: String, _ exercise: String, set: Int, kg: Double, reps: Int,
                     start: Int, end: Int, rest: Int?) -> LiftSetRow {
        LiftSetRow(id: UUID().uuidString, deviceId: "d", sessionId: session, ord: 0, exercise: exercise,
                   primaryMuscle: nil, secondaryMuscles: [], setIndex: set, weightKg: kg, reps: reps, rpe: nil,
                   isWarmup: false, startTs: start, endTs: end, restSec: rest, note: nil)
    }

    func testLastTimeDescribesTheBlockFromOneSession() throws {
        let squat = (1...3).map { row("s", "Squat", set: $0, kg: 40, reps: 10, start: t0 + ($0 - 1) * 180,
                                      end: t0 + ($0 - 1) * 180 + 50, rest: $0 == 3 ? 30 : 120) }
        let curl = (1...3).map { row("s", "Leg curl", set: $0, kg: 60, reps: 10, start: t0 + ($0 - 1) * 180,
                                     end: t0 + ($0 - 1) * 180 + 50, rest: $0 == 3 ? 30 : 120) }
        let last = try XCTUnwrap(LiftSupersetGuide.lastTime(rows: [squat, curl]))
        XCTAssertEqual(last.rounds, 3)
        XCTAssertEqual(last.numbers, [LiftSetCarry(weightKg: 40, reps: 10), LiftSetCarry(weightKg: 60, reps: 10)])
        XCTAssertEqual(last.restSec, 120, "the rest taken most often")
        XCTAssertEqual(last.durationSec, 410)
        XCTAssertEqual(last.date, Date(timeIntervalSince1970: TimeInterval(t0)))
    }

    func testLastTimeIsNotStitchedFromTwoSessions() {
        let squat = [row("s1", "Squat", set: 1, kg: 40, reps: 10, start: t0, end: t0 + 50, rest: 120)]
        let curl = [row("s2", "Leg curl", set: 1, kg: 60, reps: 10, start: t0, end: t0 + 50, rest: 120)]
        XCTAssertNil(LiftSupersetGuide.lastTime(rows: [squat, curl]))
        XCTAssertNil(LiftSupersetGuide.lastTime(rows: [squat, []]), "a member never done before")
    }
}

/// The controller side: +30 s and the block's rest are kept across a relaunch, leaving the block drops
/// what was typed for the rounds it removed, and finishing offers a changed rest to the program.
@MainActor
final class LiftSessionGuidedControllerTests: XCTestCase {

    private func controller() -> LiftSessionController {
        LiftSessionController(buzz: { _ in }, setStrapHandler: { _ in }, log: { _ in })
    }

    override func tearDown() {
        LiftSessionPersistence.clear()
        super.tearDown()
    }

    private func superset() -> [LiftPlanItem] {
        [LiftPlanItem(exercise: "Squat", targetSets: 3, restSec: 30, programItemId: "squat", supersetGroup: "A"),
         LiftPlanItem(exercise: "Leg curl", targetSets: 3, restSec: 120, programItemId: "curl", supersetGroup: "A")]
    }

    func testMoreRestAndTheBlocksRestSurviveARelaunch() throws {
        let c = controller()
        c.start(plan: superset(), programId: "p", programName: "Superset A")
        c.setRest(150, forBlockOf: 0)
        c.advance()                                    // round 1
        c.advance()                                    // rest
        guard case .resting(_, let endsAt) = c.engine?.stage else { return XCTFail("resting") }
        c.extendRest()
        guard case .resting(_, let extended) = c.engine?.stage else { return XCTFail("still resting") }
        XCTAssertEqual(extended, endsAt + LiftSessionController.restExtensionSec)

        let back = controller()
        back.resumeSaved()
        XCTAssertEqual(back.engine?.plan[1].restSec, 150)
        guard case .resting(_, let restored) = back.engine?.stage else { return XCTFail("resumed resting") }
        XCTAssertEqual(restored, extended)
    }

    func testLeavingTheBlockDropsWhatWasTypedForTheRoundsItRemoved() {
        let c = controller()
        c.start(plan: superset(), programId: nil, programName: nil)
        c.updateSet(LiftSlot(exerciseIndex: 1, setIndex: 3), weightKg: 70, reps: 8, rpe: nil, isWarmup: false)
        c.setWarmup(LiftSlot(exerciseIndex: 0, setIndex: 3), true)
        c.updateSet(LiftSlot(exerciseIndex: 0, setIndex: 1), weightKg: 45, reps: 10, rpe: nil, isWarmup: false)
        c.advance()                                    // round 1 in hand
        c.endBlock()
        XCTAssertEqual(c.engine?.recordedSet(for: LiftSlot(exerciseIndex: 0, setIndex: 1))?.weightKg, 45,
                       "the round in hand keeps what was typed for it")
        XCTAssertEqual(c.engine?.plan.map(\.targetSets), [1, 1])
        XCTAssertEqual(c.enteredValues(for: LiftSlot(exerciseIndex: 1, setIndex: 3)).weightKg, nil)
        XCTAssertFalse(c.isWarmup(LiftSlot(exerciseIndex: 0, setIndex: 3)))
        XCTAssertTrue(c.unfinishedSlots.isEmpty)
    }

    private func item(_ id: String, _ exercise: String, rest: Int?) -> LiftProgramItemRow {
        LiftProgramItemRow(id: id, deviceId: "d", programId: "p", ord: 0, exercise: exercise,
                           targetSets: 3, targetRepsLow: 10, targetRepsHigh: nil, targetRpe: nil,
                           targetWeightKg: 50, restSec: rest, note: "keep me")
    }

    func testAChangedRestIsOfferedAndKeptOnlyWhenAskedTo() {
        var lines = superset()
        lines[1].restSec = 150
        let program = [item("squat", "Squat", rest: 30), item("curl", "Leg curl", rest: 120)]
        XCTAssertEqual(LiftSessionController.restChanges(plan: lines, program: program),
                       [LiftSessionController.RestChange(itemId: "curl", exercise: "Leg curl", from: 120, to: 150)])

        let kept = LiftSessionController.programAfterSession([], plan: lines, program: program,
                                                              keepingChanges: true, programId: "p", deviceId: "d")
        XCTAssertEqual(kept.map(\.restSec), [30, 150])
        XCTAssertEqual(kept[1].note, "keep me")
        let notKept = LiftSessionController.programAfterSession([], plan: lines, program: program,
                                                                 keepingChanges: false, programId: "p", deviceId: "d")
        XCTAssertEqual(notKept.map(\.restSec), [30, 120])
    }

    func testALineWithNoRestCountsAsTheDefault() {
        let lines = [LiftPlanItem(exercise: "Squat", restSec: nil, programItemId: "squat")]
        XCTAssertTrue(LiftSessionController.restChanges(plan: lines, program: [item("squat", "Squat", rest: nil)])
            .isEmpty)
    }
}
