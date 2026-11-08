import XCTest
@testable import Strand

/// Personal fork, chantier 10 (Élan), PR A: the weigh-ins and the one weight-trend resolver (`ElanWeight`).
/// The trend is the only figure ever stated: smoothed over days, absent under five weigh-ins, and never the
/// gap between two mornings.
final class ElanWeightTests: XCTestCase {

    private func weighIn(_ day: String, _ kg: Double) -> ElanWeighIn { ElanWeighIn(day: day, kg: kg) }

    /// `count` daily weigh-ins from 2026-10-05 at `kg`.
    private func flat(_ count: Int, kg: Double, from day: String = "2026-10-05") -> [ElanWeighIn] {
        (0..<count).map { weighIn(ElanDays.elanDay(day, adding: $0), kg) }
    }

    private func defaults() -> UserDefaults {
        let name = "ElanWeightTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    // MARK: - Trend

    func testTheTrendNeedsFiveWeighIns() {
        XCTAssertTrue(ElanWeight.weightTrend(flat(4, kg: 86)).isEmpty)
        let five = ElanWeight.weightTrend(flat(5, kg: 86))
        XCTAssertEqual(five.count, 5)
        XCTAssertEqual(five.first?.day, "2026-10-05")
        XCTAssertEqual(five.first?.kg, 86)
    }

    func testADailyWeighInMovesTheTrendByATenthOfTheGap() {
        let trend = ElanWeight.weightTrend(flat(4, kg: 80) + [weighIn("2026-10-09", 90)])
        XCTAssertEqual(trend.last?.kg ?? 0, 81.0, accuracy: 1e-9)
        XCTAssertEqual(trend.last?.day, "2026-10-09")
    }

    func testAGapCountsAsThatManyDailySteps() {
        // Ten days of silence: the weigh-in weighs as ten daily steps would (1 − 0.9^10 ≈ 0.651).
        let trend = ElanWeight.weightTrend(flat(4, kg: 80) + [weighIn("2026-10-18", 90)])
        XCTAssertEqual(trend.last?.kg ?? 0, 80 + (1 - pow(0.9, 10)) * 10, accuracy: 1e-9)
    }

    func testTheSameDayTwiceKeepsTheLastValueAndSortsByDay() {
        let weighIns = [weighIn("2026-10-07", 85), weighIn("2026-10-05", 86), weighIn("2026-10-07", 84.6)]
        let deduped = ElanWeight.dedupe(weighIns)
        XCTAssertEqual(deduped, [weighIn("2026-10-05", 86), weighIn("2026-10-07", 84.6)])
    }

    // MARK: - Rate and date

    func testTheRateReadsTheLastFourWeeksOfTrend() {
        let trend = [ElanWeightTrendPoint(day: "2026-08-01", kg: 90),   // outside the window, ignored
                     ElanWeightTrendPoint(day: "2026-10-08", kg: 85),
                     ElanWeightTrendPoint(day: "2026-10-20", kg: 84),
                     ElanWeightTrendPoint(day: "2026-11-05", kg: 83)]
        XCTAssertEqual(ElanWeight.ratePerWeek(trend) ?? 0, -2.0 / 28 * 7, accuracy: 1e-9)
    }

    func testTheRateNeedsTwoWeeksOfTrend() {
        let trend = [ElanWeightTrendPoint(day: "2026-10-25", kg: 85), ElanWeightTrendPoint(day: "2026-11-05", kg: 84)]
        XCTAssertNil(ElanWeight.ratePerWeek(trend))
        XCTAssertNil(ElanWeight.ratePerWeek([]))
    }

    func testTheDateIsStatedOnlyWhenTheRateHeadsToTheTarget() {
        // 6.1 kg to lose at 0.45 kg a week: 94.9 days → 95.
        XCTAssertEqual(ElanWeight.etaDay(trendKg: 84.1, targetKg: 78, ratePerWeekKg: -0.45, from: "2026-11-05"),
                       ElanDays.elanDay("2026-11-05", adding: 95))
        XCTAssertNil(ElanWeight.etaDay(trendKg: 84.1, targetKg: 78, ratePerWeekKg: 0.3, from: "2026-11-05"),
                     "gaining while the target is below: no date")
        XCTAssertNil(ElanWeight.etaDay(trendKg: 84.1, targetKg: 78, ratePerWeekKg: -0.01, from: "2026-11-05"),
                     "under the floor: no date")
        XCTAssertNil(ElanWeight.etaDay(trendKg: 84.1, targetKg: 60, ratePerWeekKg: -0.05, from: "2026-11-05"),
                     "beyond the horizon: no date")
        XCTAssertEqual(ElanWeight.etaDay(trendKg: 70, targetKg: 72, ratePerWeekKg: 0.5, from: "2026-11-05"),
                       ElanDays.elanDay("2026-11-05", adding: 28), "gaining toward a higher target works too")
    }

    // MARK: - Summary

    func testTheSummaryStatesTheChangeSinceTheStartAndWhatRemains() {
        var weighIns = flat(5, kg: 86)
        weighIns.append(contentsOf: (5..<30).map { weighIn(ElanDays.elanDay("2026-10-05", adding: $0), 84) })
        let summary = ElanWeight.weightSummary(weighIns: weighIns, targetKg: 78)
        XCTAssertEqual(summary.count, 30)
        XCTAssertTrue(summary.hasTrend)
        let trend = try! XCTUnwrap(summary.trendKg)
        XCTAssertLessThan(trend, 86)
        XCTAssertGreaterThan(trend, 84)
        XCTAssertEqual(summary.changeSinceStartKg ?? 0, trend - 86, accuracy: 1e-9)
        XCTAssertEqual(summary.remainingKg ?? 0, trend - 78, accuracy: 1e-9)
        XCTAssertNotNil(summary.ratePerWeekKg)
        XCTAssertNotNil(summary.etaDay, "losing toward the target: a date is stated")
    }

    func testWithoutATrendNothingIsCompared() {
        let summary = ElanWeight.weightSummary(weighIns: flat(3, kg: 86), targetKg: 78)
        XCTAssertFalse(summary.hasTrend)
        XCTAssertNil(summary.trendKg)
        XCTAssertNil(summary.changeSinceStartKg)
        XCTAssertNil(summary.remainingKg)
        XCTAssertNil(summary.ratePerWeekKg)
        XCTAssertNil(summary.etaDay)
    }

    // MARK: - After a save

    func testTheFirstWeighInIsTheStartingPoint() {
        XCTAssertEqual(ElanWeight.weighInOutcome(before: [], saved: weighIn("2026-10-05", 86)), .startingPoint)
        // Re-saving the only day is still the starting point.
        XCTAssertEqual(ElanWeight.weighInOutcome(before: [weighIn("2026-10-05", 86)], saved: weighIn("2026-10-05", 85.8)),
                       .startingPoint)
    }

    func testUnderFiveWeighInsTheTrendIsStillBuilding() {
        XCTAssertEqual(ElanWeight.weighInOutcome(before: flat(2, kg: 86), saved: weighIn("2026-10-07", 85.5)),
                       .buildingTrend(count: 3, needed: 5))
    }

    func testAWeighInAboveTheTrendGetsTheWaterMessage() {
        let before = flat(6, kg: 84)
        XCTAssertEqual(ElanWeight.weighInOutcome(before: before, saved: weighIn("2026-10-11", 84.9)), .notedHigher)
        XCTAssertEqual(ElanWeight.weighInOutcome(before: before, saved: weighIn("2026-10-11", 83.7)), .noted)
        XCTAssertEqual(ElanWeight.weighInOutcome(before: before, saved: weighIn("2026-10-11", 84.0)), .noted)
    }

    func testWeighInsOverTheLastSevenDays() {
        let weighIns = flat(10, kg: 85, from: "2026-10-27")   // 27 Oct … 5 Nov
        XCTAssertEqual(ElanWeight.weighInCount(weighIns, lastDays: 7, today: "2026-11-05"), 7)
        XCTAssertEqual(ElanWeight.weighInCount(weighIns, lastDays: 7, today: "2026-11-08"), 4)
        XCTAssertEqual(ElanWeight.weighInCount(weighIns, lastDays: 7, today: "2026-10-26"), 0)
    }

    // MARK: - Settings

    func testTheTargetIsKeptOnlyInsideTheRange() {
        let d = defaults()
        XCTAssertNil(ElanWeight.targetKg(d))
        ElanWeight.setTargetKg(78, d)
        XCTAssertEqual(ElanWeight.targetKg(d), 78)
        ElanWeight.setTargetKg(5, d)
        XCTAssertNil(ElanWeight.targetKg(d), "an absurd target clears it")
        ElanWeight.setTargetKg(80, d)
        ElanWeight.setTargetKg(nil, d)
        XCTAssertNil(ElanWeight.targetKg(d))
    }

    func testTheProfileFollowsTheTrendByDefaultAndOnlyWithATrend() {
        let d = defaults()
        XCTAssertTrue(ElanWeight.profileFollowsTrend(d))
        ElanWeight.setProfileFollowsTrend(false, d)
        XCTAssertFalse(ElanWeight.profileFollowsTrend(d))

        let withTrend = ElanWeight.weightSummary(weighIns: flat(5, kg: 84.16), targetKg: nil)
        XCTAssertEqual(ElanWeight.profileWeight(following: withTrend, enabled: true), 84.2)
        XCTAssertNil(ElanWeight.profileWeight(following: withTrend, enabled: false))
        let noTrend = ElanWeight.weightSummary(weighIns: flat(2, kg: 84.16), targetKg: nil)
        XCTAssertNil(ElanWeight.profileWeight(following: noTrend, enabled: true))
    }

    // MARK: - Day arithmetic

    func testDayKeysAreCountedOnAFixedCalendar() {
        XCTAssertEqual(ElanDays.elanDaysBetween("2026-10-31", "2026-11-01"), 1)
        XCTAssertEqual(ElanDays.elanDaysBetween("2026-11-05", "2026-10-05"), -31)
        XCTAssertEqual(ElanDays.elanDay("2026-02-27", adding: 2), "2026-03-01")
        XCTAssertEqual(ElanDays.elanDay("2026-01-01", adding: -1), "2025-12-31")
        XCTAssertNil(ElanDays.elanDaysBetween("not-a-day", "2026-11-05"))
        XCTAssertEqual(ElanDays.elanDay("junk", adding: 3), "junk")
    }
}
