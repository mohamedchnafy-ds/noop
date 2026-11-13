import XCTest
@testable import StrandDesign

/// Fork chantier 12 (6 Nov.): the entrance ledger. A plain key plays once per launch (a cascade, a record);
/// a key given a generation plays once per showing of its screen, so a tab shown again replays its rings
/// while a lazy row scrolled back into view within the same showing does not.
final class NoopLaunchOnceTests: XCTestCase {

    func testPlainKeyPlaysOncePerLaunch() {
        let key = "test.launch.\(UUID().uuidString)"
        XCTAssertFalse(NoopLaunchOnce.hasPlayed(key))
        XCTAssertTrue(NoopLaunchOnce.markPlayed(key))
        XCTAssertTrue(NoopLaunchOnce.hasPlayed(key))
        XCTAssertFalse(NoopLaunchOnce.markPlayed(key), "the second caller does not get to play it")
    }

    func testGenerationKeyPlaysOncePerShowing() {
        let key = "test.showing.\(UUID().uuidString)"
        XCTAssertFalse(NoopLaunchOnce.hasPlayed(key, generation: 1))
        XCTAssertTrue(NoopLaunchOnce.markPlayed(key, generation: 1))
        XCTAssertTrue(NoopLaunchOnce.hasPlayed(key, generation: 1))
        XCTAssertFalse(NoopLaunchOnce.markPlayed(key, generation: 1),
                       "a lazy row back in view within the same showing stays drawn")
        XCTAssertFalse(NoopLaunchOnce.hasPlayed(key, generation: 2))
        XCTAssertTrue(NoopLaunchOnce.markPlayed(key, generation: 2), "the screen shown again plays anew")
        XCTAssertFalse(NoopLaunchOnce.hasPlayed(key, generation: 1), "one generation is current at a time")
    }

    func testTheTwoLedgersAreSeparate() {
        let key = "test.both.\(UUID().uuidString)"
        XCTAssertTrue(NoopLaunchOnce.markPlayed(key))
        XCTAssertFalse(NoopLaunchOnce.hasPlayed(key, generation: 0))
        XCTAssertTrue(NoopLaunchOnce.markPlayed(key, generation: 0))
        XCTAssertTrue(NoopLaunchOnce.hasPlayed(key))
    }

    /// 8 Nov.: an entrance played again when its screen comes back runs faster, and none moves under the
    /// quiet-motion gate.
    func testADrawPhaseShownAgainSpeedsItsEntranceUp() {
        let draw = NoopMotion.ringDraw
        XCTAssertEqual(NoopDrawPhase(drawn: true, still: false).motion(draw), draw,
                       "the first showing keeps the full tempo")
        XCTAssertNotEqual(NoopDrawPhase(drawn: true, still: false, quick: true).motion(draw), draw,
                          "a showing again plays at the replay speed")
        XCTAssertNil(NoopDrawPhase(drawn: true, still: true, quick: true).motion(draw))
        XCTAssertGreaterThan(NoopMotion.replaySpeed, 1)
    }

    /// 13 Nov.: a surface waiting for its entrance empties at once, never through an animation, so the
    /// draw-in that follows starts from empty instead of adding to a fall.
    func testAWaitingDrawPhaseNeverAnimatesItsEmptying() {
        let draw = NoopMotion.ringDraw
        XCTAssertNil(NoopDrawPhase(drawn: false, still: false).motion(draw))
        XCTAssertNil(NoopDrawPhase(drawn: false, still: false, quick: true).motion(draw))
        XCTAssertEqual(NoopDrawPhase(drawn: true, still: false).motion(draw), draw)
        XCTAssertGreaterThan(NoopMotion.leaveSettle, 0, "a leave of a few frames is not a showing")
    }
}
