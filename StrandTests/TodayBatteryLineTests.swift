import XCTest
@testable import Strand

/// The battery card under Today's title (personal fork): the same funnel as the header ring, the level in
/// words, no stale percentage without a link.
final class TodayBatteryLineTests: XCTestCase {
    private typealias Display = LiquidTodayView.StrapBatteryDisplay

    func testNoLinkStatesNoPercentage() {
        let line = TodayBatteryLine.todayBatteryLine(.offline, estimate: "~5 days left")
        XCTAssertNil(line?.value)
        XCTAssertEqual(line?.detail, "Strap not connected")
        XCTAssertEqual(line?.level, .unknown)
    }

    func testANonActiveDeviceDrawsNothing() {
        XCTAssertNil(TodayBatteryLine.todayBatteryLine(.notActiveDevice, estimate: nil))
    }

    func testLevelsAndDetails() {
        let good = TodayBatteryLine.todayBatteryLine(.charge(pct: 73, charging: false, isRing: false),
                                                     estimate: "~5 days left")
        XCTAssertEqual(good?.level, .good)
        XCTAssertEqual(good?.value, StrapLogReader.strapLogPercent(73))
        XCTAssertEqual(good?.detail, "~5 days left")
        XCTAssertEqual(good?.title, "Strap battery")

        XCTAssertEqual(TodayBatteryLine.todayBatteryLine(.charge(pct: 30, charging: false, isRing: false),
                                                         estimate: nil)?.level, .low)
        let critical = TodayBatteryLine.todayBatteryLine(.charge(pct: 12, charging: false, isRing: false),
                                                         estimate: "~20h left")
        XCTAssertEqual(critical?.level, .critical)
        XCTAssertEqual(critical?.detail, "Charge it soon · ~20h left")

        let charging = TodayBatteryLine.todayBatteryLine(.charge(pct: 12, charging: true, isRing: false),
                                                         estimate: nil)
        XCTAssertEqual(charging?.level, .charging)
        XCTAssertEqual(charging?.detail, "Charging")
        XCTAssertEqual(TodayBatteryLine.todayBatteryLine(.charge(pct: 50, charging: false, isRing: true),
                                                         estimate: nil)?.title, "Ring battery")
    }

    func testTheGlyphFollowsTheLevel() {
        func symbol(_ pct: Double) -> String {
            TodayBatteryCard.symbol(TodayBatteryLine.todayBatteryLine(.charge(pct: pct, charging: false, isRing: false),
                                                                      estimate: nil)!)
        }
        XCTAssertEqual(symbol(5), "battery.0percent")
        XCTAssertEqual(symbol(30), "battery.25percent")
        XCTAssertEqual(symbol(73), "battery.75percent")
        XCTAssertEqual(symbol(95), "battery.100percent")
    }
}
