import XCTest
@testable import Strand

/// « My chart » (fork chantier 17, step 3): the pure engine and the saved-chart store. No strap, no database.
final class MyChartTests: XCTestCase {

    // MARK: Days

    func testDayNumberCountsDaysSinceTheEpoch() {
        XCTAssertEqual(MyChartEngine.dayNumber("1970-01-01"), 0)
        XCTAssertEqual(MyChartEngine.dayNumber("1970-01-02"), 1)
        XCTAssertEqual(MyChartEngine.dayNumber("1969-12-31"), -1)
        XCTAssertEqual(MyChartEngine.dayNumber("2000-03-01"), 11_017)
        XCTAssertEqual(MyChartEngine.dayNumber("2026-11-09"), 20_766)
        XCTAssertNil(MyChartEngine.dayNumber("2026-13-01"))
        XCTAssertNil(MyChartEngine.dayNumber("not a day"))
    }

    // MARK: Window

    func testWindowEndsTodayAndStepsBackWholePeriods() {
        let now = MyChartEngine.periodWindow(period: .week, offset: 0, zoom: 0...1, today: 100, earliest: nil)
        XCTAssertEqual(now, MyChartWindow(start: 94, end: 100, lower: 94, upper: 100))
        let before = MyChartEngine.periodWindow(period: .week, offset: 1, zoom: 0...1, today: 100, earliest: nil)
        XCTAssertEqual(before, MyChartWindow(start: 87, end: 93, lower: 87, upper: 93))
    }

    func testWindowZoomNarrowsInsideThePeriod() {
        // 90 days: 111…200, length 89; a quarter in is day 22.25 → 22.
        let w = MyChartEngine.periodWindow(period: .quarter, offset: 0, zoom: 0.25...1, today: 200, earliest: nil)
        XCTAssertEqual(w.start, 111)
        XCTAssertEqual(w.lower, 133)
        XCTAssertEqual(w.upper, 200)
    }

    func testAllStartsAtTheFirstReadingAndIgnoresTheOffset() {
        let w = MyChartEngine.periodWindow(period: .all, offset: 3, zoom: 0...1, today: 500, earliest: 120)
        XCTAssertEqual(w.start, 120)
        XCTAssertEqual(w.end, 500)
    }

    func testAZoomNeverGoesUnderAWeek() {
        let w = MyChartEngine.periodWindow(period: .month, offset: 0, zoom: 0.5...0.51, today: 100, earliest: nil)
        XCTAssertGreaterThanOrEqual(w.upper - w.lower, 6)
    }

    // MARK: Buckets

    func testBucketSizeWidensWithTheSpan() {
        XCTAssertEqual(MyChartEngine.bucketSize(span: 100), 1)
        XCTAssertEqual(MyChartEngine.bucketSize(span: 120), 1)
        XCTAssertEqual(MyChartEngine.bucketSize(span: 121), 3)
        XCTAssertEqual(MyChartEngine.bucketSize(span: 240), 3)
        XCTAssertEqual(MyChartEngine.bucketSize(span: 241), 7)
    }

    func testBucketsAverageTheirDaysAndSitInTheMiddle() {
        let series: [MyChartDayValue] = (0...5).map { (day: $0, value: Double($0 + 1)) }
        let out = MyChartEngine.bucketed(series, lower: 0, upper: 5, bucket: 3)
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out[0].day, 1, accuracy: 1e-9)
        XCTAssertEqual(out[0].value, 2, accuracy: 1e-9)
        XCTAssertEqual(out[1].day, 4, accuracy: 1e-9)
        XCTAssertEqual(out[1].value, 5, accuracy: 1e-9)
    }

    func testABucketWithNoReadingHasNoPoint() {
        let series: [MyChartDayValue] = [(day: 0, value: 4), (day: 7, value: 8)]
        XCTAssertEqual(MyChartEngine.bucketed(series, lower: 0, upper: 8, bucket: 3).count, 2)
    }

    // MARK: Axes

    func testTicksAreRoundAndInsideTheDomain() {
        let t = MyChartEngine.axisTicks(lower: 0, upper: 100)
        XCTAssertEqual(t.values, [0, 20, 40, 60, 80, 100])
        XCTAssertEqual(t.step, 20)
        XCTAssertTrue(MyChartEngine.axisTicks(lower: 5, upper: 5).values.isEmpty)
    }

    func testAutoScaleLeavesRoomAroundTheRange() {
        let r = resolve([MyChartItem(metricID: "a")], ["a": [(day: 0, value: 10), (day: 1, value: 20)]])
        // 10…20 with 14 % room: 8.6…21.4.
        XCTAssertEqual(r.series[0].points[0].fraction, 1.4 / 12.8, accuracy: 1e-9)
        XCTAssertEqual(r.series[0].points[1].fraction, 11.4 / 12.8, accuracy: 1e-9)
    }

    func testAFlippedAxisPutsTheLowValueOnTop() {
        var item = MyChartItem(metricID: "a")
        item.inverted = true
        let r = resolve([item], ["a": [(day: 0, value: 10), (day: 1, value: 20)]])
        XCTAssertEqual(r.series[0].points[0].fraction, 1 - 1.4 / 12.8, accuracy: 1e-9)
    }

    func testAFixedScaleReadsAgainstTheWearersOwnBounds() {
        var item = MyChartItem(metricID: "a")
        item.scale = .fixed
        item.fixedMin = 0
        item.fixedMax = 100
        let r = resolve([item], ["a": [(day: 0, value: 25), (day: 1, value: 80)]])
        XCTAssertEqual(r.series[0].points[0].fraction, 0.25, accuracy: 1e-9)
        XCTAssertEqual(r.series[0].points[1].fraction, 0.8, accuracy: 1e-9)
    }

    func testBarsStartAtZero() {
        var item = MyChartItem(metricID: "a")
        item.kind = .bars
        let r = resolve([item], ["a": [(day: 0, value: 10), (day: 1, value: 20)]])
        // 0…22: the bar's base is the bottom.
        XCTAssertEqual(r.series[0].baseFraction, 0, accuracy: 1e-9)
        XCTAssertEqual(r.series[0].points[1].fraction, 20 / 22.0, accuracy: 1e-9)
    }

    func testTwoMeasuresOnOneSideShareTheirUnion() {
        let data: [String: [MyChartDayValue]] = ["a": [(day: 0, value: 0), (day: 1, value: 10)],
                                                  "b": [(day: 0, value: 50), (day: 1, value: 60)]]
        var b = MyChartItem(metricID: "b")
        b.scale = .fixed
        b.fixedMin = 0
        b.fixedMax = 100
        var a = MyChartItem(metricID: "a")
        a.scale = .fixed
        a.fixedMin = 0
        a.fixedMax = 100
        let r = resolve([a, b], data)
        XCTAssertEqual(r.left?.lower, 0)
        XCTAssertEqual(r.left?.upper, 100)
        XCTAssertNil(r.right)
    }

    func testComparingShapesPutsEveryMeasureOnItsOwnZeroToOne() {
        let data: [String: [MyChartDayValue]] = ["a": [(day: 0, value: 10), (day: 1, value: 20)],
                                                  "b": [(day: 0, value: 500), (day: 1, value: 900)]]
        let items = [MyChartItem(metricID: "a"), MyChartItem(metricID: "b", axis: .right)]
        let r = MyChartEngine.resolveSeries(items: items, data: data, lower: 0, upper: 1, normalized: true)
        XCTAssertEqual(r.series[0].points.map(\.fraction), [0, 1])
        XCTAssertEqual(r.series[1].points.map(\.fraction), [0, 1])
        XCTAssertNil(r.left)
        XCTAssertNil(r.right)
    }

    // MARK: Link between two measures

    func testPerfectLinesCorrelateToPlusAndMinusOne() {
        let up: [MyChartDayValue] = (1...8).map { (day: $0, value: Double($0)) }
        let double: [MyChartDayValue] = (1...8).map { (day: $0, value: Double($0 * 2)) }
        let down: [MyChartDayValue] = (1...8).map { (day: $0, value: Double(-$0)) }
        XCTAssertEqual(MyChartEngine.correlation(up, double, lower: 1, upper: 8) ?? 0, 1, accuracy: 1e-9)
        XCTAssertEqual(MyChartEngine.correlation(up, down, lower: 1, upper: 8) ?? 0, -1, accuracy: 1e-9)
    }

    func testTooFewSharedDaysOrAFlatSeriesHaveNoLink() {
        let a: [MyChartDayValue] = (1...6).map { (day: $0, value: Double($0)) }
        XCTAssertNil(MyChartEngine.correlation(a, a, lower: 1, upper: 6))
        let flat: [MyChartDayValue] = (1...8).map { (day: $0, value: 5) }
        let up: [MyChartDayValue] = (1...8).map { (day: $0, value: Double($0)) }
        XCTAssertNil(MyChartEngine.correlation(flat, up, lower: 1, upper: 8))
    }

    func testLinkStrengthWords() {
        XCTAssertEqual(MyChartEngine.link(0.1), .negligible)
        XCTAssertEqual(MyChartEngine.link(-0.3), .weak)
        XCTAssertEqual(MyChartEngine.link(0.5), .moderate)
        XCTAssertEqual(MyChartEngine.link(-0.7), .strong)
        XCTAssertEqual(MyChartEngine.link(0.9), .veryStrong)
    }

    func testPersonalBandIsTheMeanPlusOrMinusHalfADeviation() {
        let band = MyChartEngine.personalBand([1, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(band?.mean ?? 0, 4, accuracy: 1e-9)
        XCTAssertEqual(band?.low ?? 0, 3, accuracy: 1e-9)
        XCTAssertEqual(band?.high ?? 0, 5, accuracy: 1e-9)
        XCTAssertNil(MyChartEngine.personalBand([1, 2, 3]))
    }

    // MARK: Store

    func testSavedChartsSurviveAJSONRoundTrip() {
        var spec = MyChartSpec.fresh(name: "Recovery & HRV", metricID: "my-whoop:recovery")
        spec.items.append(MyChartItem(metricID: "my-whoop:hrv", kind: .area, axis: .right, scale: .fixed,
                                      inverted: true, fixedMin: 20, fixedMax: 120))
        spec.normalized = true
        let back = MyChartStore.decodeSaved(MyChartStore.encodeSaved([spec]))
        XCTAssertEqual(back, [spec])
        XCTAssertEqual(MyChartStore.decodeSaved(""), [])
        XCTAssertEqual(MyChartStore.decodeSaved("{not json"), [])
    }

    func testPinningKeepsOneChartPinnedAndASecondTapUnpins() {
        let a = MyChartSpec.fresh(name: "A", metricID: "x:a")
        let b = MyChartSpec.fresh(name: "B", metricID: "x:b")
        var specs = MyChartStore.pinning([a, b], at: 1)
        XCTAssertEqual(specs.map(\.pinned), [false, true])
        XCTAssertEqual(MyChartStore.pinnedIndex(specs), 1)
        specs = MyChartStore.pinning(specs, at: 0)
        XCTAssertEqual(specs.map(\.pinned), [true, false])
        specs = MyChartStore.pinning(specs, at: 0)
        XCTAssertEqual(specs.map(\.pinned), [false, false])
        XCTAssertEqual(MyChartStore.pinnedIndex(specs), 0)
    }

    // MARK: Helpers

    private func resolve(_ items: [MyChartItem], _ data: [String: [MyChartDayValue]]) -> (
        series: [MyChartResolved], left: MyChartAxisDomain?, right: MyChartAxisDomain?, bucket: Int) {
        MyChartEngine.resolveSeries(items: items, data: data, lower: 0, upper: 1, normalized: false)
    }
}
