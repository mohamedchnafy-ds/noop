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

    /// The reply and the card must give one number for one day: Effort goes to the model on the scale the
    /// card writes it on.
    func testEffortIsSentOnTheScaleTheCardShows() {
        let spec = CoachChartSpec(kind: .bars, metric: "my-whoop:strain", days: 7, day: "2026-11-04")
        let point = CoachChartPoint(date: Date(timeIntervalSince1970: 0), value: 50)
        let whoop = CoachChart.shownResult(spec, first: [point], second: [], effortScale: .whoop)
        XCTAssertTrue(whoop.contains("mean 10.5"), whoop)
        XCTAssertTrue(whoop.contains("(/21)"), whoop)
        let hundred = CoachChart.shownResult(spec, first: [point], second: [])
        XCTAssertTrue(hundred.contains("mean 50"), hundred)
    }

    /// The heart metrics take the app's short names on the card, so the title fits one line.
    func testTheCardUsesTheShortHeartNames() {
        XCTAssertEqual(CoachChartText.name(CoachChart.descriptor("my-whoop:hrv")), String(localized: "HRV"))
        let sleep = CoachChart.descriptor("my-whoop:sleep_total_min")
        XCTAssertEqual(CoachChartText.name(sleep), sleep?.title)
    }

    /// PR C: the sleep stages and the macros are stacked bars, by ids of their own; a line refuses them and
    /// a stacked chart refuses a catalogue id.
    func testAStackedChartTakesTheStagesOrTheMacros() {
        let stages = parse(["kind": "stacked", "metric": "sleep:stages", "days": 14]).spec
        XCTAssertEqual(stages, CoachChartSpec(kind: .stacked, metric: "sleep:stages", days: 14, day: "2026-11-04"))
        XCTAssertEqual(parse(["kind": "stacked", "metric": "nutrition:macros", "days": 7]).spec?.metric,
                       "nutrition:macros")
        XCTAssertNil(parse(["kind": "stacked", "metric": "my-whoop:hrv"]).spec)
        XCTAssertNil(parse(["kind": "line", "metric": "sleep:stages"]).spec)
        XCTAssertTrue(CoachChart.seriesIds.contains("sleep:stages"))
        XCTAssertTrue(CoachChart.seriesIds.contains("nutrition:macros"))
        XCTAssertFalse(CoachChart.metricIds.contains("sleep:stages"), "the catalogue ids stay the catalogue's")
    }

    func testTheModelReadsTheStackPartByPart() {
        let spec = CoachChartSpec(kind: .stacked, metric: "nutrition:macros", days: 7, day: "2026-11-04")
        let base = Date(timeIntervalSince1970: 0)
        let points = [CoachChartPoint(date: base, value: 470, parts: [150, 250, 70]),
                      CoachChartPoint(date: base + 86_400, value: 430, parts: [130, 230, 70])]
        let result = CoachChart.shownResult(spec, first: points, second: [])
        XCTAssertTrue(result.contains("2 days logged; mean protein 140, carbs 240, fat 70."), result)
        XCTAssertTrue(CoachChart.wireText(spec).hasPrefix("[Chart shown: Macros"))
    }

    /// `get_series` reads through the charts' reader: a catalogue id is a line, a stack a stacked chart;
    /// the days go one by one up to the limit, then by 7-day blocks.
    func testGetSeriesReadsDayByDayThenByBlocks() {
        XCTAssertEqual(CoachTools.seriesSpec(["metric": "my-whoop:hrv", "days": 10], today: "2026-11-04"),
                       CoachChartSpec(kind: .line, metric: "my-whoop:hrv", days: 10, day: "2026-11-04"))
        XCTAssertEqual(CoachTools.seriesSpec(["metric": "sleep:stages", "days": 400], today: "2026-11-04")?.kind,
                       .stacked)
        XCTAssertEqual(CoachTools.seriesSpec(["metric": "sleep:stages", "days": 400], today: "2026-11-04")?.days, 365)
        XCTAssertNil(CoachTools.seriesSpec(["metric": "my-whoop:nope", "days": 10], today: "2026-11-04"))

        let day = { (key: String) in CoachChart.dayDate(key, calendar: self.calendar)! }
        let short = CoachChartSpec(kind: .line, metric: "my-whoop:hrv", days: 3, day: "2026-11-04")
        let text = CoachTools.seriesResult(short, points: [CoachChartPoint(date: day("2026-11-02"), value: 41),
                                                           CoachChartPoint(date: day("2026-11-04"), value: 45)],
                                           calendar: calendar)
        XCTAssertTrue(text.contains("2 of 3 days with a value; mean 43"), text)
        XCTAssertTrue(text.contains("2026-11-02: 41\n2026-11-04: 45"), text)

        let long = CoachChartSpec(kind: .stacked, metric: "sleep:stages", days: 100, day: "2026-11-04")
        let blocks = CoachTools.seriesResult(long, points: [CoachChartPoint(date: day("2026-11-03"), value: 420,
                                                                            parts: [80, 100, 240]),
                                                            CoachChartPoint(date: day("2026-11-04"), value: 400,
                                                                            parts: [60, 100, 240])],
                                             calendar: calendar)
        XCTAssertTrue(blocks.contains("By 7-day blocks"), blocks)
        XCTAssertTrue(blocks.contains("(2 days): deep 70, REM 100, light 240"), blocks)
        XCTAssertTrue(CoachTools.seriesResult(short, points: [], calendar: calendar).contains("no value"))
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
