import XCTest
import WhoopStore
@testable import Strand

/// Personal fork: the Sleep tab shows one sleep need. "Hours vs needed" measures against the same
/// normative need as the debt ledger (`SleepModel.debtNeedMin`) instead of the mean-asleep floor.
/// Kotlin twin: SleepImportedFiguresTest.sessionInBedWindowDoesNotSubstituteForAsleep.
final class SleepNeedUnificationTests: XCTestCase {
    private func day(_ value: String, sleep: Double?) -> DailyMetric {
        DailyMetric(day: value, totalSleepMin: sleep, efficiency: nil,
                    deepMin: nil, remMin: nil, lightMin: nil, disturbances: nil,
                    restingHr: nil, avgHrv: nil, recovery: nil, strain: nil,
                    exerciseCount: nil, spo2Pct: nil, skinTempDevC: nil, respRateBpm: nil)
    }

    func testHoursVsNeededUsesTheDebtNeed() {
        // Two nights, under the 7-night minimum: the need cold-starts to the 8 h target (480 min). The
        // old mean-asleep rule would have used max(450, 415) = 450.
        let days = [day("2026-06-01", sleep: 420), day("2026-06-02", sleep: 410)]
        XCTAssertEqual(SleepModel.debtNeedMin(days: days), 480, accuracy: 1e-9)
        let metric = SleepModel.hoursVsNeededSeries(days: days, importedSleep: [:])
        XCTAssertEqual(metric.series.last ?? -1, 410.0 / 480.0 * 100.0, accuracy: 1e-9)
        // The ledger measures against the same need.
        let ledger = SleepModel.debtLedger(days: days, napSleepMinByDay: [:])
        XCTAssertEqual(ledger.needMin, 480, accuracy: 1e-9)
    }

    func testImportedNeedStillWinsPerDay() {
        let days = [day("2026-06-01", sleep: 400)]
        let imported = ["2026-06-01": ImportedSleepFigures(
            performancePct: nil, consistencyPct: nil, needMin: 500, debtMin: nil)]
        let metric = SleepModel.hoursVsNeededSeries(days: days, importedSleep: imported)
        XCTAssertEqual(metric.series.last ?? -1, 400.0 / 500.0 * 100.0, accuracy: 1e-9)
    }
}
