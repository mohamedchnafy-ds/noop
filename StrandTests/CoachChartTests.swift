import XCTest
@testable import Strand

/// The Coach's charts (personal fork, chantier 9): what `show_chart` accepts, the figures under a chart and
/// sent back to the model, and how the request is stored with the reply.
final class CoachChartTests: XCTestCase {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Paris")!
        return cal
    }

    private func parse(_ input: [String: Any], back: Int? = 0) -> (spec: CoachChartSpec?, problem: String?) {
        CoachChart.fromToolInput(input, today: "2026-11-04") { _ in back }
    }

    func testALineTakesACatalogueMetricAndTheNearestExplorePeriod() {
        let spec = parse(["kind": "line", "metric": "my-whoop:hrv", "days": 28]).spec
        XCTAssertEqual(spec, CoachChartSpec(kind: .line, metric: "my-whoop:hrv", days: 30, day: "2026-11-04"))
        XCTAssertEqual(CoachChart.nearestPeriod(10), 7)
        XCTAssertEqual(CoachChart.nearestPeriod(400), 365)
        XCTAssertEqual(CoachChart.nearestPeriod(22), 30, "a tie goes to the longer period")
    }

    func testUnknownMetricsAndPairsWithoutASecondAreRefused() {
        XCTAssertNil(parse(["kind": "line", "metric": "my-whoop:nope"]).spec)
        XCTAssertNil(parse(["kind": "bubbles", "metric": "my-whoop:hrv"]).spec)
        XCTAssertNil(parse(["kind": "pair", "metric": "my-whoop:hrv"]).spec)
        XCTAssertNil(parse(["kind": "pair", "metric": "my-whoop:hrv", "second_metric": "my-whoop:hrv"]).spec)
        let pair = parse(["kind": "pair", "metric": "my-whoop:hrv", "second_metric": "my-whoop:sleep_total_min"]).spec
        XCTAssertEqual(pair?.second, "my-whoop:sleep_total_min")
    }

    func testADayChartIsTodayByDefaultAndStaysInTheLookback() {
        XCTAssertEqual(parse(["kind": "day"]).spec,
                       CoachChartSpec(kind: .day, day: "2026-11-04", series: .heartRate))
        XCTAssertEqual(parse(["kind": "day", "series": "stress", "date": "2026-11-02"], back: 2).spec?.series, .stress)
        XCTAssertNil(parse(["kind": "day", "date": "2026-11-05"], back: -1).spec)
        XCTAssertNil(parse(["kind": "day", "date": "2025-01-01"], back: CoachChart.dayLookback + 1).spec)
        XCTAssertNil(parse(["kind": "day", "date": "hier"], back: nil).spec)
    }

    func testTheFiguresAreTheMeanTheMiddleHalfAndTheLast() throws {
        let stats = try XCTUnwrap(CoachChart.stats([40, 44, 38, 50, 42]))
        XCTAssertEqual(stats.mean, 42.8, accuracy: 0.001)
        XCTAssertEqual(stats.low, 40)
        XCTAssertEqual(stats.high, 44)
        XCTAssertEqual(stats.lowest, 38)
        XCTAssertEqual(stats.highest, 50)
        XCTAssertEqual(stats.last, 42)
        XCTAssertNil(CoachChart.stats([]))
    }

    func testTheWindowEndsOnItsDayAndSkipsDaysWithoutAValue() {
        let window = CoachChart.windowDays(endingOn: "2026-11-02", days: 3, calendar: calendar)
        XCTAssertEqual(window, ["2026-10-31", "2026-11-01", "2026-11-02"])
        let points = CoachChart.dailyPoints([(day: "2026-10-30", value: 1), (day: "2026-11-01", value: 2),
                                             (day: "2026-11-02", value: 3)], window: window, calendar: calendar)
        XCTAssertEqual(points.map(\.value), [2, 3])
    }

    func testAPairIsDrawnOnScalesOfItsOwn() {
        let base = Date(timeIntervalSince1970: 0)
        let points = [CoachChartPoint(date: base, value: 40), CoachChartPoint(date: base + 86_400, value: 50)]
        XCTAssertEqual(CoachChart.normalized(points).map(\.value), [0, 1])
        XCTAssertEqual(CoachChart.normalized([points[0]]).map(\.value), [0.5])
    }

    func testTheModelGetsTheFiguresAndReadsTheChartBack() {
        let spec = CoachChartSpec(kind: .line, metric: "my-whoop:hrv", days: 30, day: "2026-11-04")
        let base = Date(timeIntervalSince1970: 0)
        let result = CoachChart.shownResult(spec, first: [CoachChartPoint(date: base, value: 41),
                                                          CoachChartPoint(date: base + 86_400, value: 45)], second: [])
        XCTAssertTrue(result.contains("2 values, mean 43"), result)
        XCTAssertTrue(result.contains("last 45"), result)
        XCTAssertTrue(CoachChart.wireText(spec).contains("last 30 days to 2026-11-04"))
    }

    func testTheChartsAreStoredWithTheReply() throws {
        let spec = CoachChartSpec(kind: .day, day: "2026-11-03", series: .stress)
        let text = CoachReplyMeta.join(body: "Calme.", meta: CoachReplyMeta(charts: [spec]))
        let split = CoachReplyMeta.split(text)
        XCTAssertEqual(split.body, "Calme.")
        XCTAssertEqual(split.meta?.charts, [spec])
        XCTAssertTrue(CoachReplyMeta.forModel(text, system: .metric).contains("[Chart shown: stress on 2026-11-03]"))
        XCTAssertTrue(CoachChart.metricIds.contains("my-whoop:hrv"))
        XCTAssertEqual(Set(CoachChart.metricIds).count, CoachChart.metricIds.count)
    }
}
