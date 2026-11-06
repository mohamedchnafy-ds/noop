import XCTest
@testable import StrandDesign

/// Fork chantier 12 (6 Nov. evening): the beat's phase on the shared clock, so the heart beside Today's number
/// and the wave at the end of its curve beat together, at the true rhythm.
final class NoopHeartbeatPhaseTests: XCTestCase {

    /// A whole number of seconds since the reference date: a beat at 60 bpm starts there.
    private let start = Date(timeIntervalSinceReferenceDate: 120)

    func testThePhaseRunsFromZeroToOneOverOneBeat() {
        XCTAssertEqual(NoopHeartbeat.beatPhase(at: start, bpm: 60), 0, accuracy: 1e-9)
        XCTAssertEqual(NoopHeartbeat.beatPhase(at: start.addingTimeInterval(0.25), bpm: 60), 0.25, accuracy: 1e-9)
        XCTAssertEqual(NoopHeartbeat.beatPhase(at: start.addingTimeInterval(0.999), bpm: 60), 0.999, accuracy: 1e-9)
        XCTAssertEqual(NoopHeartbeat.beatPhase(at: start.addingTimeInterval(1), bpm: 60), 0, accuracy: 1e-9,
                       "the next beat starts over")
    }

    func testAFasterRateBeatsMoreOften() {
        // 120 bpm: a beat every half second, so a quarter of a second in is half a beat.
        XCTAssertEqual(NoopHeartbeat.beatPhase(at: start.addingTimeInterval(0.25), bpm: 120), 0.5, accuracy: 1e-9)
        XCTAssertEqual(NoopHeartbeat.beatPhase(at: start.addingTimeInterval(0.5), bpm: 120), 0, accuracy: 1e-9)
    }

    func testTwoViewsAtOneRateReadOnePhase() {
        let moment = Date(timeIntervalSinceReferenceDate: 7_654.321)
        XCTAssertEqual(NoopHeartbeat.beatPhase(at: moment, bpm: 73), NoopHeartbeat.beatPhase(at: moment, bpm: 73))
    }

    func testBelowTheSlowestBeatNothingBeats() {
        let moment = Date(timeIntervalSinceReferenceDate: 1.3)
        XCTAssertEqual(NoopHeartbeat.beatPhase(at: moment, bpm: NoopHeartbeat.slowestBeat - 1), 0)
        XCTAssertEqual(NoopHeartbeat.beatPhase(at: moment, bpm: 0), 0)
        XCTAssertGreaterThan(NoopHeartbeat.beatPhase(at: moment, bpm: NoopHeartbeat.slowestBeat), 0)
    }
}
