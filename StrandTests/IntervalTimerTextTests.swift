import XCTest
@testable import Strand

/// The interval timer's durations in words (personal fork, Démarrer tools).
final class IntervalTimerTextTests: XCTestCase {
    func testSecondsReadAsSecondsAndWholeMinutesAsMinutes() {
        XCTAssertEqual(IntervalTimerView.secondsText(30), "30\u{00A0}s")
        XCTAssertEqual(IntervalTimerView.secondsText(600), "10 min")
        XCTAssertEqual(IntervalTimerView.secondsText(90), "1 min 30\u{00A0}s")
    }

    func testTheStepperRangeInWords() {
        XCTAssertEqual(IntervalTimerView.rangeText(5...600, step: 5, seconds: true),
                       "From 5\u{00A0}s to 10 min, in steps of 5\u{00A0}s")
        XCTAssertEqual(IntervalTimerView.rangeText(1...30, step: 1, seconds: false), "From 1 to 30")
    }
}
