import XCTest
import WhoopStore
@testable import Strand

/// Personal fork, chantier 15 PR C: « Nights of fasting » (`FastingNights`): which nights count as fasting
/// nights, the margin of the difference, the verdicts and the waiting rule. Pure.
final class FastingNightsTests: XCTestCase {

    /// 2026-11-07 00:00 UTC.
    private let day0 = 1_794_009_600

    private func night(_ index: Int, bedtimeHour: Int = 23, hrv: Double? = nil, rhr: Double? = nil, sleep: Double? = nil) -> FastingNight {
        FastingNight(day: "n\(index)", sleepStart: day0 + index * 86_400 + bedtimeHour * 3_600, durationMin: sleep, hrvMs: hrv, restingHr: rhr)
    }

    private func fast(startHour: Int, hours: Int?, day index: Int = 0) -> FastRow {
        let start = day0 + index * 86_400 + startHour * 3_600
        return FastRow(id: "f\(index)-\(startHour)", startedAt: start, endedAt: hours.map { start + $0 * 3_600 },
                       goalMinutes: 960, createdAt: start, updatedAt: start)
    }

    // MARK: Which nights

    func testANightCountsWhenALongEnoughFastWasRunningAtBedtime() {
        let fasts = [fast(startHour: 20, hours: 16)]
        XCTAssertTrue(FastingNights.isFastingNight(night(0), fasts: fasts, now: day0 + 3 * 86_400))
        XCTAssertFalse(FastingNights.isFastingNight(night(1), fasts: fasts, now: day0 + 3 * 86_400), "the fast ended at noon")
        XCTAssertFalse(FastingNights.isFastingNight(night(0, bedtimeHour: 19), fasts: fasts, now: day0 + 3 * 86_400),
                       "in bed before the fast started")
    }

    func testAShortFastDoesNotMakeAFastingNight() {
        XCTAssertFalse(FastingNights.isFastingNight(night(0), fasts: [fast(startHour: 20, hours: 11)], now: day0 + 86_400))
        XCTAssertTrue(FastingNights.isFastingNight(night(0), fasts: [fast(startHour: 20, hours: 12)], now: day0 + 86_400))
    }

    func testARunningFastCountsUpToNow() {
        let running = [fast(startHour: 20, hours: nil)]
        XCTAssertFalse(FastingNights.isFastingNight(night(0), fasts: running, now: day0 + 20 * 3_600 + 6 * 3_600),
                       "six hours in: not twelve yet")
        XCTAssertTrue(FastingNights.isFastingNight(night(0), fasts: running, now: day0 + 20 * 3_600 + 13 * 3_600))
    }

    // MARK: Margin and verdicts

    func testTheMarginIsTheWelchIntervalOfTheDifference() {
        XCTAssertNil(FastingNights.marginOfDifference([1, 2], [3]))
        XCTAssertEqual(FastingNights.marginOfDifference([50, 50, 50], [40, 40]), 0)
        // 48, 50, 52 (variance 4, n 3) against 60, 62 (variance 2, n 2): 1.96 × √(4/3 + 2/2) ≈ 2.994.
        XCTAssertEqual(FastingNights.marginOfDifference([48, 50, 52], [60, 62]) ?? 0, 2.994, accuracy: 0.002)
    }

    func testFewerThanFiveNightsOnASideIsTooFew() {
        let fasting = (0..<4).map { night($0, hrv: 70) }
        let others = (10..<20).map { night($0, hrv: 60) }
        let figure = FastingNights.fastingNightFigure(.hrv, fasting: fasting, others: others)
        XCTAssertEqual(figure.verdict, .tooFew)
        XCTAssertEqual(figure.fastingCount, 4)
        XCTAssertEqual(figure.delta ?? 0, 10, accuracy: 0.001, "the means are still computed")
    }

    func testADifferenceBeyondItsMarginIsAVerdictInTheFigureDirection() {
        let fasting = [66.0, 68, 70, 68, 69].enumerated().map { night($0.offset, hrv: $0.element, rhr: 52, sleep: 430) }
        let others = [60.0, 61, 62, 60, 61, 62].enumerated().map { night(10 + $0.offset, hrv: $0.element, rhr: 54, sleep: 425) }
        let figures = FastingNights.fastingNightFigures(fasting: fasting, others: others)
        XCTAssertEqual(figures.map(\.metric), [.hrv, .restingHr, .sleep])
        XCTAssertEqual(figures[0].verdict, .better, "HRV up by 7 ms, well past its margin")
        XCTAssertEqual(figures[0].delta ?? 0, 7.2, accuracy: 0.001)
        XCTAssertEqual(figures[1].verdict, .better, "a lower resting heart rate is better; no spread, margin 0")
        XCTAssertEqual(figures[1].delta ?? 0, -2, accuracy: 0.001)
        XCTAssertEqual(figures[2].verdict, .better, "sleep up with no spread on either side")
    }

    func testADifferenceWithinItsMarginIsClose() {
        let fasting = [60.0, 70, 50, 65, 55].enumerated().map { night($0.offset, hrv: $0.element) }
        let others = [58.0, 68, 48, 63, 53, 60].enumerated().map { night(10 + $0.offset, hrv: $0.element) }
        let figure = FastingNights.fastingNightFigure(.hrv, fasting: fasting, others: others)
        XCTAssertEqual(figure.verdict, .close)
        XCTAssertNotNil(figure.margin)
    }

    func testTheReportSaysHowManyNightsAreMissing() {
        let nights = (0..<3).map { night($0, hrv: 70) } + (10..<12).map { night($0, hrv: 60) }
        let fasts = (0..<3).map { fast(startHour: 20, hours: 16, day: $0) }
        let report = FastingNights.fastingNightsReport(nights: nights, fasts: fasts, now: day0 + 30 * 86_400)
        XCTAssertEqual(report.fastingCount, 3)
        XCTAssertEqual(report.otherCount, 2)
        XCTAssertTrue(report.waiting)
        XCTAssertEqual(report.missingFasting, 2)
        XCTAssertEqual(report.missingOthers, 3)
        XCTAssertEqual(report.figures.map(\.verdict), [.tooFew, .tooFew, .tooFew])
    }

    // MARK: Nights from blocks

    func testTheLongestBlockOfEachDayMakesTheNightWithTheDayScores() {
        func block(start: Int, end: Int, hrv: Double? = nil) -> CachedSleepSession {
            CachedSleepSession(startTs: start, endTs: end, efficiency: nil, restingHr: nil, avgHrv: hrv, stagesJSON: nil,
                               deviceId: "d")
        }
        let dayKey: (Int) -> String = { "d\(($0 - self.day0) / 86_400)" }
        let blocks = [block(start: day0 - 2 * 3_600, end: day0 + 6 * 3_600, hrv: 55),          // the night, 8 h
                      block(start: day0 + 14 * 3_600, end: day0 + 15 * 3_600),                   // a nap: under 3 h
                      block(start: day0 + 86_400 - 3_600, end: day0 + 86_400 + 5 * 3_600)]      // the next night, 6 h
        let metric = DailyMetric(day: "d0", totalSleepMin: 470, efficiency: nil, deepMin: nil, remMin: nil, lightMin: nil,
                                 disturbances: nil, restingHr: 51, avgHrv: 58, recovery: nil, strain: nil, exerciseCount: nil)
        let nights = FastingNights.fastingNightsFromBlocks(blocks, metricsByDay: ["d0": metric], dayKey: dayKey)
        XCTAssertEqual(nights.count, 2)
        XCTAssertEqual(nights[0].day, "d0")
        XCTAssertEqual(nights[0].sleepStart, day0 - 2 * 3_600)
        XCTAssertEqual(nights[0].hrvMs, 58, "the day's score wins over the block's")
        XCTAssertEqual(nights[0].restingHr, 51)
        XCTAssertEqual(nights[0].durationMin, 470)
        XCTAssertEqual(nights[1].durationMin ?? 0, 360, accuracy: 0.001, "no day score: the block's own length")
        XCTAssertNil(nights[1].restingHr)
    }
}
