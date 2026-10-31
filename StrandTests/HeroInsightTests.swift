import XCTest
@testable import Strand

/// The arithmetic under the Today hero bubbles (personal fork): the 7-day gap and the bars it sits in.
final class HeroInsightTests: XCTestCase {

    func testDayKeysEndOnTheDayAndCrossMonthBoundaries() {
        XCTAssertEqual(HeroInsight.dayKeys(endingOn: "2026-03-02", count: 3),
                       ["2026-02-28", "2026-03-01", "2026-03-02"])
        XCTAssertEqual(HeroInsight.dayKeys(endingOn: "2026-01-01", count: 2), ["2025-12-31", "2026-01-01"])
        XCTAssertEqual(HeroInsight.dayKeys(endingOn: "garbage", count: 2), [])
    }

    func testDeltaIsValueMinusMeanOfThePriorWindowOnly() {
        // Seven prior days at 60, the day shown at 70: the shown day must not pull its own mean.
        var series: [String: Double] = [:]
        for key in HeroInsight.dayKeys(endingOn: "2026-10-30", count: 7) { series[key] = 60 }
        series["2026-10-31"] = 70
        let t = HeroInsight.trend(value: 70, series: series, day: "2026-10-31")
        XCTAssertEqual(t.delta, 10)
        XCTAssertEqual(t.bars.count, 7)
        XCTAssertEqual(t.bars.last!, 70)
    }

    func testTooFewPriorReadingsClaimNoGapButStillDrawBars() {
        let series = ["2026-10-30": 50.0, "2026-10-29": 52.0]
        let t = HeroInsight.trend(value: 61, series: series, day: "2026-10-31")
        XCTAssertNil(t.delta)
        XCTAssertEqual(t.bars.compactMap { $0 }, [52, 50, 61])
        XCTAssertNil(t.bars[0])
    }

    func testNoValueMeansNoDeltaAndTheLastBarStaysStored() {
        var series: [String: Double] = [:]
        for key in HeroInsight.dayKeys(endingOn: "2026-10-30", count: 7) { series[key] = 40 }
        let t = HeroInsight.trend(value: nil, series: series, day: "2026-10-31")
        XCTAssertNil(t.delta)
        XCTAssertNil(t.bars.last!)
    }

    func testTheShownValueOverridesTheStoredRowForTheLastBar() {
        // Live Effort runs ahead of the stored row; the bar must match the number in the bubble.
        var series: [String: Double] = [:]
        for key in HeroInsight.dayKeys(endingOn: "2026-10-31", count: 8) { series[key] = 8 }
        let t = HeroInsight.trend(value: 12.5, series: series, day: "2026-10-31")
        XCTAssertEqual(t.bars.last!, 12.5)
        XCTAssertEqual(t.delta!, 4.5, accuracy: 1e-9)
    }

    func testDeltaTextUsesASignAndATrueMinus() {
        let en = Locale(identifier: "en_US")
        XCTAssertEqual(HeroInsight.deltaText(6.4, decimals: 0, locale: en), "+6")
        XCTAssertEqual(HeroInsight.deltaText(-3.6, decimals: 0, locale: en), "−4")
        XCTAssertEqual(HeroInsight.deltaText(0.2, decimals: 0, locale: en), "0")
        XCTAssertEqual(HeroInsight.deltaText(1.26, decimals: 1, locale: en), "+1.3")
        XCTAssertEqual(HeroInsight.deltaText(-0.04, decimals: 1, locale: en), "0.0")
        XCTAssertEqual(HeroInsight.deltaText(1.26, decimals: 1, locale: Locale(identifier: "fr_FR")), "+1,3")
    }

    func testDirectionFollowsTheRoundedGap() {
        XCTAssertEqual(HeroInsight.direction(0.4, decimals: 0), nil)
        XCTAssertEqual(HeroInsight.direction(0.6, decimals: 0), true)
        XCTAssertEqual(HeroInsight.direction(-0.06, decimals: 1), false)
    }

    func testSleepPartsSplitMinutesAndRefuseNothing() {
        XCTAssertNil(HeroInsight.sleepParts(minutes: nil))
        XCTAssertNil(HeroInsight.sleepParts(minutes: 0))
        let p = HeroInsight.sleepParts(minutes: 440.4)!
        XCTAssertEqual(p.hours, 7)
        XCTAssertEqual(p.minutes, 20)
    }
}
