import XCTest
import WhoopStore
@testable import Strand

/// Pins the pure half of the redesigned Trends screen (fork chantier 16): period windows and their
/// predecessor, the Charge / Effort quadrants and their reading, the personal normal band, and the
/// grid's day / week / month columns. No view is rendered here.
final class TrendsOverviewTests: XCTestCase {

    private func day(_ d: String, recovery: Double? = nil, strain: Double? = nil,
                     hrv: Double? = nil, rhr: Int? = nil, sleep: Double? = nil) -> DailyMetric {
        DailyMetric(day: d, totalSleepMin: sleep, efficiency: nil, deepMin: nil, remMin: nil, lightMin: nil,
                    disturbances: nil, restingHr: rhr, avgHrv: hrv, recovery: recovery, strain: strain,
                    exerciseCount: nil)
    }

    // MARK: Windows

    func testWeekWindowIsMondayToSundayContainingToday() {
        // 2026-11-08 is a Sunday: the week is Mon 2 → Sun 8.
        let w = TrendsOverview.window(range: .week, offset: 0, today: "2026-11-08")
        XCTAssertEqual(w, TrendsOverview.Window(start: "2026-11-02", end: "2026-11-08"))
        let back = TrendsOverview.window(range: .week, offset: 1, today: "2026-11-08")
        XCTAssertEqual(back, TrendsOverview.Window(start: "2026-10-26", end: "2026-11-01"))
    }

    func testTrailingWindowsEndTodayAndStepBackByTheirLength() {
        let m = TrendsOverview.window(range: .month, offset: 0, today: "2026-11-08")
        XCTAssertEqual(m, TrendsOverview.Window(start: "2026-10-10", end: "2026-11-08"))
        XCTAssertEqual(m?.dayCount, 30)
        let q1 = TrendsOverview.window(range: .quarter, offset: 1, today: "2026-11-08")
        XCTAssertEqual(q1?.end, "2026-08-10")
        XCTAssertEqual(q1?.dayCount, 90)
        XCTAssertNil(TrendsOverview.window(range: .all, offset: 0, today: "2026-11-08"))
    }

    func testPreviousWindowIsTheSameLengthImmediatelyBefore() {
        let w = TrendsOverview.Window(start: "2026-11-02", end: "2026-11-08")
        XCTAssertEqual(TrendsOverview.previous(w), TrendsOverview.Window(start: "2026-10-26", end: "2026-11-01"))
        XCTAssertEqual(TrendsOverview.civilDaysBetween("2026-02-27", "2026-03-02"), 3)
        XCTAssertEqual(TrendsOverview.civilDaysBetween("2028-02-28", "2028-03-01"), 2) // leap year
    }

    func testMaxOffsetStopsAtTheEarliestBankedDay() {
        XCTAssertEqual(TrendsOverview.maxOffset(range: .week, earliestDay: "2026-10-31", today: "2026-11-08"), 1)
        XCTAssertEqual(TrendsOverview.maxOffset(range: .week, earliestDay: "2026-11-03", today: "2026-11-08"), 0)
        XCTAssertEqual(TrendsOverview.maxOffset(range: .month, earliestDay: "2026-08-01", today: "2026-11-08"), 3)
        XCTAssertEqual(TrendsOverview.maxOffset(range: .week, earliestDay: nil, today: "2026-11-08"), 0)
    }

    func testDaysInWindowAreInclusiveAtBothEnds() {
        let days = ["2026-11-01", "2026-11-02", "2026-11-08", "2026-11-09"].map { day($0) }
        let w = TrendsOverview.Window(start: "2026-11-02", end: "2026-11-08")
        XCTAssertEqual(TrendsOverview.days(days, in: w).map(\.day), ["2026-11-02", "2026-11-08"])
        XCTAssertEqual(TrendsOverview.days(days, in: nil).count, 4)
    }

    // MARK: Means and changes

    func testChangeCarriesPointsAndPercent() {
        let c = TrendsOverview.change(current: 52, previous: 61)
        XCTAssertEqual(c?.delta ?? 0, -9, accuracy: 0.0001)
        XCTAssertEqual(c?.percent ?? 0, -14.754, accuracy: 0.001)
        XCTAssertNil(TrendsOverview.change(current: 52, previous: nil))
        XCTAssertNil(TrendsOverview.change(current: 1, previous: 0)?.percent)
    }

    // MARK: Bilan sentence

    func testBilanReadingNamesAThinPreviousPeriodBeforeReadingATrend() {
        XCTAssertEqual(TrendsOverview.bilanReading(chargeDelta: -9, effortDelta: 12, previousDays: 2),
                       .sparsePrevious(days: 2))
        XCTAssertEqual(TrendsOverview.bilanReading(chargeDelta: nil, effortDelta: nil, previousDays: 5), .noPrevious)
        XCTAssertEqual(TrendsOverview.bilanReading(chargeDelta: -9, effortDelta: 12, previousDays: 0), .noPrevious)
        XCTAssertEqual(TrendsOverview.bilanReading(chargeDelta: -9, effortDelta: 12, previousDays: 7), .loadUpChargeDown)
        XCTAssertEqual(TrendsOverview.bilanReading(chargeDelta: 6, effortDelta: -4, previousDays: 7), .loadDownChargeUp)
        XCTAssertEqual(TrendsOverview.bilanReading(chargeDelta: 6, effortDelta: 3, previousDays: 7), .bothUp)
        XCTAssertEqual(TrendsOverview.bilanReading(chargeDelta: -6, effortDelta: -3, previousDays: 7), .bothDown)
        XCTAssertEqual(TrendsOverview.bilanReading(chargeDelta: 2, effortDelta: -2.9, previousDays: 7), .steady)
    }

    // MARK: Quadrants

    func testQuadrantsSplitAtTheMidpoints() {
        XCTAssertEqual(TrendsOverview.quadrant(charge: 92, effort: 60), .optimal)
        XCTAssertEqual(TrendsOverview.quadrant(charge: 26, effort: 57), .overreaching)
        XCTAssertEqual(TrendsOverview.quadrant(charge: 26, effort: 20), .recovering)
        XCTAssertEqual(TrendsOverview.quadrant(charge: 80, effort: 20), .underused)
        XCTAssertEqual(TrendsOverview.quadrant(charge: 50, effort: 50), .optimal) // thresholds are inclusive
    }

    func testReadingOfTheWeekFromTheScreenshots() {
        // 2–8 Nov: Charge 92 81 46 26 27 58 36, Effort 60 60 59 57 50 58 53 → 3 optimal, 4 overreaching.
        let charges: [Double] = [92, 81, 46, 26, 27, 58, 36]
        let efforts: [Double] = [60, 60, 59, 57, 50, 58, 53]
        let days = (0..<7).map { i in day("2026-11-0\(2 + i)", recovery: charges[i], strain: efforts[i]) }
        let pts = TrendsOverview.balancePoints(days)
        XCTAssertEqual(pts.count, 7)
        let t = TrendsOverview.tally(pts)
        XCTAssertEqual(t[.optimal], 3)
        XCTAssertEqual(t[.overreaching], 4)
        XCTAssertEqual(t[.recovering], 0)
        XCTAssertEqual(t[.underused], 0)
        XCTAssertEqual(TrendsOverview.reading(pts), .overreaching(days: 4, of: 7))
    }

    func testReadingNeedsThreePlottedDaysAndSkipsHalfDays() {
        let two = [day("2026-11-01", recovery: 90, strain: 60), day("2026-11-02", recovery: 90, strain: 60),
                   day("2026-11-03", recovery: 90, strain: nil)]
        XCTAssertEqual(TrendsOverview.balancePoints(two).count, 2)
        XCTAssertEqual(TrendsOverview.reading(TrendsOverview.balancePoints(two)), .tooFew)
        let under = (1...5).map { day("2026-11-0\($0)", recovery: 80, strain: 10) }
        XCTAssertEqual(TrendsOverview.reading(TrendsOverview.balancePoints(under)), .underused(days: 5, of: 5))
    }

    // MARK: Band

    func testBandIsMeanPlusMinusHalfSDAndNeedsSevenReadings() {
        XCTAssertNil(TrendsOverview.band([40, 50, 60]))
        let b = TrendsOverview.band([40, 50, 60, 40, 50, 60, 50])
        XCTAssertNotNil(b)
        XCTAssertEqual(b!.mean, 50, accuracy: 0.0001)
        XCTAssertEqual(b!.sd, 7.559, accuracy: 0.001)
        XCTAssertEqual(b!.low, 46.22, accuracy: 0.01)
        XCTAssertEqual(b!.high, 53.78, accuracy: 0.01)
        XCTAssertEqual(TrendsOverview.deviation(45, band: b!), .below)
        XCTAssertEqual(TrendsOverview.deviation(50, band: b!), .inside)
        XCTAssertEqual(TrendsOverview.deviation(58, band: b!), .above)
    }

    func testAxisPositionSpansTwoSDEachSideAndClamps() {
        let b = TrendsOverview.Band(mean: 50, sd: 10)
        XCTAssertEqual(TrendsOverview.axisPosition(50, band: b), 0.5, accuracy: 0.0001)
        XCTAssertEqual(TrendsOverview.axisPosition(55, band: b), 0.625, accuracy: 0.0001) // band edge
        XCTAssertEqual(TrendsOverview.axisPosition(70, band: b), 0.97, accuracy: 0.0001)  // clamped
        XCTAssertEqual(TrendsOverview.axisPosition(0, band: b), 0.03, accuracy: 0.0001)
        XCTAssertEqual(TrendsOverview.axisPosition(99, band: TrendsOverview.Band(mean: 50, sd: 0)), 0.5)
    }

    func testBandWindowIsLongerThanThePeriod() {
        let week = TrendsOverview.Window(start: "2026-11-02", end: "2026-11-08")
        let bw = TrendsOverview.bandWindow(for: week, range: .week)
        XCTAssertEqual(bw.end, "2026-11-08")
        XCTAssertEqual(bw.dayCount, 30)
        XCTAssertEqual(TrendsOverview.bandDays(for: .quarter), 180)
        XCTAssertEqual(TrendsOverview.bandDays(for: .year), 365)
    }

    // MARK: Grid columns

    func testDayColumnsAreOnePerDay() {
        let w = TrendsOverview.Window(start: "2026-11-02", end: "2026-11-08")
        let cols = TrendsOverview.columns(window: w, bucket: .day)
        XCTAssertEqual(cols.count, 7)
        XCTAssertEqual(cols.first, TrendsOverview.Column(start: "2026-11-02", end: "2026-11-02"))
        XCTAssertEqual(cols.last?.end, "2026-11-08")
    }

    func testWeekColumnsAreMondayAlignedAndClipped() {
        // 10 Oct (Sat) → 8 Nov (Sun): partial first week, then Monday-aligned.
        let w = TrendsOverview.Window(start: "2026-10-10", end: "2026-11-08")
        let cols = TrendsOverview.columns(window: w, bucket: .week)
        XCTAssertEqual(cols.count, 5)
        XCTAssertEqual(cols[0], TrendsOverview.Column(start: "2026-10-10", end: "2026-10-11"))
        XCTAssertEqual(cols[1], TrendsOverview.Column(start: "2026-10-12", end: "2026-10-18"))
        XCTAssertEqual(cols[4], TrendsOverview.Column(start: "2026-11-02", end: "2026-11-08"))
        // The week that crosses into November carries the month label.
        XCTAssertTrue(cols[3].isMonthStart)   // 26 Oct → 1 Nov
        XCTAssertFalse(cols[1].isMonthStart)
    }

    func testMonthColumnsFollowCalendarMonthsAndClip() {
        let w = TrendsOverview.Window(start: "2025-11-15", end: "2026-02-10")
        let cols = TrendsOverview.columns(window: w, bucket: .month)
        XCTAssertEqual(cols.map(\.start), ["2025-11-15", "2025-12-01", "2026-01-01", "2026-02-01"])
        XCTAssertEqual(cols.map(\.end), ["2025-11-30", "2025-12-31", "2026-01-31", "2026-02-10"])
    }

    func testColumnMeanSkipsMissingReadings() {
        let days = [day("2026-11-02", hrv: 50), day("2026-11-03", hrv: nil), day("2026-11-04", hrv: 60),
                    day("2026-11-10", hrv: 99)]
        let col = TrendsOverview.Column(start: "2026-11-02", end: "2026-11-08")
        XCTAssertEqual(TrendsOverview.columnMean(days, column: col, { $0.avgHrv }) ?? 0, 55, accuracy: 0.0001)
        XCTAssertNil(TrendsOverview.columnMean(days, column: col, { $0.spo2Pct }))
    }

    func testBucketPerRange() {
        XCTAssertEqual(TrendsOverview.bucket(for: .week), .day)
        XCTAssertEqual(TrendsOverview.bucket(for: .month), .week)
        XCTAssertEqual(TrendsOverview.bucket(for: .quarter), .week)
        XCTAssertEqual(TrendsOverview.bucket(for: .half), .month)
        XCTAssertEqual(TrendsOverview.bucket(for: .year), .month)
    }
}
