import XCTest
@testable import Strand
import WhoopStore

/// The session's pause (personal fork): every clock stands still, nothing runs out, a strap double-tap does
/// nothing, and the time paused is left out of the length the session saves. Also the buttons the Lock Screen
/// banner offers for each state of the session.
@MainActor
final class LiftSessionPauseTests: XCTestCase {

    private let t0 = 1_800_000_000

    private func single(sets: Int = 2, restSec: Int = 90) -> [LiftPlanItem] {
        [LiftPlanItem(exercise: "Bench press", primaryMuscle: .chest, targetSets: sets, restSec: restSec)]
    }

    private func superset(restSec: Int = 60) -> [LiftPlanItem] {
        [LiftPlanItem(exercise: "Squat", primaryMuscle: .quads, targetSets: 2, restSec: restSec, supersetGroup: "A"),
         LiftPlanItem(exercise: "Row", primaryMuscle: .lats, targetSets: 2, restSec: restSec, supersetGroup: "A")]
    }

    private func slot(_ e: Int, _ s: Int) -> LiftSlot { LiftSlot(exerciseIndex: e, setIndex: s) }

    override func tearDown() {
        LiftSessionPersistence.clear()
        super.tearDown()
    }

    // MARK: - Engine

    /// A rest paused with 70 s left still has 70 s left when the session resumes, however long the pause.
    func testAPausedRestStandsStillAndKeepsItsTimeLeft() {
        var e = LiftSessionEngine(plan: single(), startTs: t0)
        e.advance(now: t0 + 10)                                  // set 1
        e.advance(now: t0 + 40)                                  // rest until t0 + 130
        XCTAssertTrue(e.pauseSession(now: t0 + 60))
        XCTAssertTrue(e.isPaused)
        XCTAssertEqual(e.restRemaining(now: t0 + 300), 70, "the countdown stands where it was paused")

        XCTAssertTrue(e.resumeSession(now: t0 + 300))
        XCTAssertFalse(e.isPaused)
        XCTAssertEqual(e.pausedTotalSec, 240)
        XCTAssertEqual(e.stage, .resting(slot(0, 1), endsAt: t0 + 370))
        XCTAssertEqual(e.restRemaining(now: t0 + 300), 70)

        e.advance(now: t0 + 320)                                 // set 2
        XCTAssertEqual(e.sets.first?.restSec, 40, "the rest taken leaves the pause out: 20 s + 20 s")
        XCTAssertEqual(e.sets.first?.endTs, t0 + 40, "the set keeps the second it really ended")
    }

    /// A set's clock stands still through a pause and picks up where it stood.
    func testAPausedSetsClockLeavesThePauseOut() {
        var e = LiftSessionEngine(plan: single(), startTs: t0)
        e.advance(now: t0 + 10)
        e.pauseSession(now: t0 + 30)
        XCTAssertEqual(e.stageSeconds(now: t0 + 100), 20)
        e.resumeSession(now: t0 + 100)
        XCTAssertEqual(e.stageSeconds(now: t0 + 110), 30)
        e.advance(now: t0 + 110)
        XCTAssertEqual(e.sets.first.map { $0.endTs - $0.startTs }, 30, "the set lasted 30 s of lifting")
    }

    /// The session's clock and the length it saves leave every pause out — the one that is over and the one
    /// still running.
    func testTheSessionsLengthLeavesPausesOut() {
        var e = LiftSessionEngine(plan: single(), startTs: t0)
        e.advance(now: t0 + 10)
        e.pauseSession(now: t0 + 100)
        e.resumeSession(now: t0 + 400)
        e.pauseSession(now: t0 + 500)
        XCTAssertEqual(e.sessionSeconds(now: t0 + 550), 200)
        XCTAssertEqual(e.sessionSeconds(now: t0 + 600), 200, "the session's clock stands still too")
        XCTAssertEqual(e.activeSeconds(until: t0 + 600), 200)
    }

    /// Finishing while paused ends the pause first: the rest it closes leaves the pause out, and so does the
    /// length the session saves.
    func testFinishingWhilePausedEndsThePauseFirst() {
        var e = LiftSessionEngine(plan: single(sets: 1), startTs: t0)
        e.advance(now: t0 + 10)
        e.advance(now: t0 + 40)                                  // the last set done; resting
        e.pauseSession(now: t0 + 50)
        e.finish(now: t0 + 650)
        XCTAssertTrue(e.isFinished)
        XCTAssertFalse(e.isPaused)
        XCTAssertEqual(e.pausedTotalSec, 600)
        XCTAssertEqual(e.sets.first?.restSec, 10)
        XCTAssertEqual(e.activeSeconds(until: t0 + 650), 50)
    }

    /// A superset's next round does not start by itself while the session is paused; it starts when the rest,
    /// pushed back by the pause, runs out.
    func testAPausedSupersetRestDoesNotStartTheNextRound() {
        var e = LiftSessionEngine(plan: superset(), startTs: t0)
        e.advance(now: t0)                                       // round 1
        e.advance(now: t0 + 30)                                  // rest until t0 + 90
        e.pauseSession(now: t0 + 40)
        XCTAssertFalse(e.isNextRoundDue(at: t0 + 200))
        XCTAssertFalse(e.startNextRoundIfRestEnded(at: t0 + 200))
        e.resumeSession(now: t0 + 200)
        XCTAssertFalse(e.isNextRoundDue(at: t0 + 249))
        XCTAssertTrue(e.isNextRoundDue(at: t0 + 250))
    }

    /// A rest that was already over before the pause stays over: the pause adds no time to it.
    func testARestAlreadyOverBeforeThePauseStaysOver() {
        var e = LiftSessionEngine(plan: single(), startTs: t0)
        e.advance(now: t0 + 10)
        e.advance(now: t0 + 40)                                  // rest until t0 + 130
        e.pauseSession(now: t0 + 200)
        e.resumeSession(now: t0 + 300)
        XCTAssertEqual(e.stage, .resting(slot(0, 1), endsAt: t0 + 130))
        XCTAssertEqual(e.restRemaining(now: t0 + 300), 0)
    }

    func testPauseAndResumeDeclineWhenThereIsNothingToDo() {
        var e = LiftSessionEngine(plan: single(), startTs: t0)
        XCTAssertFalse(e.resumeSession(now: t0 + 5), "not paused")
        XCTAssertTrue(e.pauseSession(now: t0 + 5))
        XCTAssertFalse(e.pauseSession(now: t0 + 6), "already paused")
        e.finish(now: t0 + 10)
        XCTAssertFalse(e.pauseSession(now: t0 + 20), "a finished session cannot be paused")
    }

    // MARK: - Controller

    /// The strap's double-tap does nothing while paused, with no buzz, and the strap log says why.
    func testAStrapDoubleTapDoesNothingWhilePaused() {
        var buzzes: [UInt8] = []
        var logged: [String] = []
        var strap: (@MainActor () -> Void)?
        let c = LiftSessionController(buzz: { buzzes.append($0) }, setStrapHandler: { strap = $0 },
                                      log: { logged.append($0) })
        c.start(plan: single(), programId: nil, programName: "Push")
        c.advance()                                              // set 1, from the app
        c.pause()
        XCTAssertTrue(c.isPaused)
        strap?()
        XCTAssertEqual(c.engine?.stage, .working(slot(0, 1)), "the set is still the one being worked")
        XCTAssertTrue(buzzes.isEmpty, "no buzz: the tap was not acted on")
        XCTAssertTrue(logged.contains { $0.contains("paused") && $0.contains("not acted on") }, "\(logged)")
    }

    /// A button pressed in the app picks a paused session up before it takes its step.
    func testTheAppsButtonPicksAPausedSessionUp() {
        let c = LiftSessionController(buzz: { _ in }, setStrapHandler: { _ in })
        c.start(plan: single(), programId: nil, programName: "Push")
        c.advance()
        c.pause()
        c.advance()
        XCTAssertFalse(c.isPaused)
        guard case .resting(let s, _) = c.engine?.stage else { return XCTFail("expected a rest") }
        XCTAssertEqual(s, slot(0, 1))
    }

    /// Which buttons the banner offers: rest → skip, +30 s, pause; set → set done, pause; round → round done,
    /// pause; paused → resume; none during the warm-up; only pause once every set is done.
    func testBannerControlsFollowTheSession() {
        typealias C = LiftSessionController
        var e = LiftSessionEngine(plan: single(sets: 1), startTs: t0)
        XCTAssertEqual(C.bannerControls(e), [])
        e.advance(now: t0 + 10)
        XCTAssertEqual(C.bannerControls(e), [.setDone, .pause])
        e.pauseSession(now: t0 + 20)
        XCTAssertEqual(C.bannerControls(e), [.resume])
        e.resumeSession(now: t0 + 30)
        e.advance(now: t0 + 40)
        XCTAssertEqual(C.bannerControls(e), [.pause], "every set is done: Finish is in the app")

        var s = LiftSessionEngine(plan: superset(), startTs: t0)
        s.advance(now: t0)
        XCTAssertEqual(C.bannerControls(s), [.roundDone, .pause])
        s.advance(now: t0 + 30)
        XCTAssertEqual(C.bannerControls(s), [.skipRest, .addRest, .pause])
        XCTAssertEqual(C.bannerControls(nil), [])
    }

    /// Paused, the banner reads "Paused" and, for a rest, the time it still has — the validated mockup.
    func testAPausedRestReadsPausedWithItsTimeLeft() {
        let c = LiftSessionController(buzz: { _ in }, setStrapHandler: { _ in })
        c.start(plan: single(restSec: 90), programId: nil, programName: "Push")
        c.advance()
        c.advance()                                              // resting after set 1
        c.pause()
        let shown = c.presentation(system: .metric)
        XCTAssertEqual(shown?.exercise, "Paused")
        XCTAssertTrue(shown?.status.hasPrefix("Resting after set 1 · 1:") ?? false, shown?.status ?? "nil")
        XCTAssertTrue(shown?.status.hasSuffix(" left") ?? false, shown?.status ?? "nil")
        XCTAssertNil(shown?.detail)
        XCTAssertNotNil(shown?.pausedAt)
        XCTAssertEqual(shown?.controls, [.resume])

        c.resumeFromPause()
        let running = c.presentation(system: .metric)
        XCTAssertEqual(running?.exercise, "Bench press")
        XCTAssertNil(running?.pausedAt)
        XCTAssertEqual(running?.controls, [.skipRest, .addRest, .pause])
    }

    /// A paused rest neither buzzes its warning nor ends.
    func testAPausedRestDoesNotBuzzItsWarning() {
        var buzzes: [UInt8] = []
        let c = LiftSessionController(buzz: { buzzes.append($0) }, setStrapHandler: { _ in })
        c.start(plan: single(restSec: 2), programId: nil, programName: "Push")
        c.advance()
        c.advance()                                              // a 2 s rest
        c.pause()
        RunLoop.main.run(until: Date().addingTimeInterval(3.2))
        XCTAssertTrue(buzzes.isEmpty)
        XCTAssertEqual(c.presentation(system: .metric)?.status.hasPrefix("Resting after set 1"), true)
    }

    // MARK: - Persistence

    /// A pause survives NOOP being closed in the background, as the rest of the session does.
    func testAPauseSurvivesARelaunch() throws {
        let c = LiftSessionController(buzz: { _ in }, setStrapHandler: { _ in })
        c.start(plan: single(), programId: nil, programName: "Push")
        c.advance()
        c.pause()
        let snapshot = try XCTUnwrap(LiftSessionPersistence.load())
        let restored = LiftSessionPersistence.engine(from: snapshot)
        XCTAssertTrue(restored.isPaused)
        XCTAssertEqual(restored.pausedAt, c.engine?.pausedAt)

        c.resumeFromPause()
        let resumed = LiftSessionPersistence.engine(from: try XCTUnwrap(LiftSessionPersistence.load()))
        XCTAssertFalse(resumed.isPaused)
        XCTAssertEqual(resumed.pausedTotalSec, c.engine?.pausedTotalSec)
    }
}
