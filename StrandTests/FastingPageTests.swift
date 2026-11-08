import XCTest
import StrandAnalytics
@testable import Strand

/// Personal fork, chantier 15: the ring geometry, the shared formats and the phase texts of the Jeûne page.
final class FastingPageTests: XCTestCase {

    func testTheRingOpensAtTheBottomLikeTheNightRing() {
        XCTAssertEqual(FastingRingMath.angle(permille: 0), 225, accuracy: 0.001, "the start, bottom left")
        XCTAssertEqual(FastingRingMath.angle(permille: 500), 360, accuracy: 0.001, "half way, at the top")
        XCTAssertEqual(FastingRingMath.angle(permille: 1000), 495, accuracy: 0.001, "the goal, bottom right")
        XCTAssertEqual(FastingRingMath.angle(permille: 1400), 495, accuracy: 0.001, "clamped at the goal")
        XCTAssertEqual(FastingRingMath.angle(permille: -3), 225, accuracy: 0.001)
        let top = FastingRingMath.point(CGPoint(x: 100, y: 100), 50, degrees: 360)
        XCTAssertEqual(top.x, 100, accuracy: 0.001)
        XCTAssertEqual(top.y, 50, accuracy: 0.001)
    }

    func testEveryPhaseHasItsWords() {
        XCTAssertEqual(FastingPhaseText.count, FastingTimeline.phaseIds.count)
        var names: Set<String> = []
        for index in 0..<FastingPhaseText.count {
            XCTAssertFalse(FastingPhaseText.name(index).isEmpty)
            XCTAssertFalse(FastingPhaseText.short(index).isEmpty)
            XCTAssertFalse(FastingPhaseText.what(index).isEmpty)
            XCTAssertFalse(FastingPhaseText.feel(index).isEmpty)
            XCTAssertFalse(FastingPhaseText.symbol(index).isEmpty)
            names.insert(FastingPhaseText.name(index))
        }
        XCTAssertEqual(names.count, FastingPhaseText.count, "six different names")
        XCTAssertEqual(FastingPhaseText.name(99), FastingPhaseText.name(FastingPhaseText.count - 1), "out of range clamps")
        XCTAssertTrue(FastingPhaseText.range(0).contains("0"))
        XCTAssertTrue(FastingPhaseText.range(FastingPhaseText.count - 1).contains("24"))
    }

    func testTheFormatsReadAsTheRestOfTheApp() {
        XCTAssertEqual(FastingFormat.duration(minutes: 42), String(localized: "\(42) min"))
        XCTAssertEqual(FastingFormat.duration(minutes: 960), String(localized: "\(16)h"))
        XCTAssertEqual(FastingFormat.duration(minutes: 702), String(localized: "\(11)h \(42)m"))
        XCTAssertEqual(FastingFormat.duration(minutes: -5), String(localized: "\(0) min"))
        XCTAssertEqual(FastingFormat.percent(permille: 731), String(localized: "\(73)%"))
        XCTAssertEqual(FastingFormat.percent(permille: 1400), String(localized: "\(100)%"))
        XCTAssertTrue(FastingFormat.litres(ml: 1250).hasSuffix(" L"))
        XCTAssertFalse(FastingFormat.litres(ml: 1250).contains("1.250"), "two decimals at most")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(FastingFormat.dayWord(now, now: now), String(localized: "Today"))
        XCTAssertEqual(FastingFormat.dayWord(now.addingTimeInterval(-86_400), now: now), String(localized: "Yesterday"))
        XCTAssertEqual(FastingFormat.dayWord(now.addingTimeInterval(86_400), now: now), String(localized: "Tomorrow"))
    }
}
