import XCTest
@testable import Strand
import WhoopStore

/// What the live heart-rate banner shows beside the bpm (personal fork, chantier 6): one figure the wearer picks,
/// each resolved by the rule the Today and Sleep screens state it with.
final class LiveHRBannerFiguresTests: XCTestCase {

    private func day(_ key: String, sleep: Double? = nil, hrv: Double? = nil, recovery: Double? = nil,
                     strain: Double? = nil) -> DailyMetric {
        DailyMetric(day: key, totalSleepMin: sleep, efficiency: nil, deepMin: nil, remMin: nil, lightMin: nil,
                    disturbances: nil, restingHr: nil, avgHrv: hrv, recovery: recovery, strain: strain,
                    exerciseCount: nil)
    }

    func testTheChoiceIsEffortUntilOneIsMade() {
        let defaults = UserDefaults(suiteName: "LiveHRBannerFiguresTests")!
        defaults.removePersistentDomain(forName: "LiveHRBannerFiguresTests")
        XCTAssertEqual(LiveHRBannerSide.storedSide(defaults), .effort)
        defaults.set("sleep", forKey: LiveHRBannerSide.defaultsKey)
        XCTAssertEqual(LiveHRBannerSide.storedSide(defaults), .sleep)
        defaults.set("garbage", forKey: LiveHRBannerSide.defaultsKey)
        XCTAssertEqual(LiveHRBannerSide.storedSide(defaults), .effort)
    }

    /// The night as Today's Rest ring names it: the day's own, else the last night within the carry window.
    func testTheNightIsTheDaysOwnElseAFreshCarry() {
        let days = [day("2026-10-30", sleep: 400), day("2026-11-01", sleep: 408), day("2026-11-02")]
        XCTAssertEqual(LiveHRBannerFigures.nightSleepMinutes(own: day("2026-11-02", sleep: 221), days: days,
                                                             dayKey: "2026-11-02", carries: true), 221)
        XCTAssertEqual(LiveHRBannerFigures.nightSleepMinutes(own: day("2026-11-02"), days: days,
                                                             dayKey: "2026-11-02", carries: true), 408)
        XCTAssertNil(LiveHRBannerFigures.nightSleepMinutes(own: day("2026-11-02"), days: days,
                                                           dayKey: "2026-11-02", carries: false))
        XCTAssertNil(LiveHRBannerFigures.nightSleepMinutes(own: nil, days: [day("2026-10-20", sleep: 400)],
                                                           dayKey: "2026-11-02", carries: true),
                     "a night weeks old is not named as last night")
    }

    func testEffortIsTheDaysEffortOnTheWearersScale() {
        let content = LiveHRBannerFigures.sideContent(.effort, day: day("2026-11-02", strain: 38), days: [],
                                                      dayKey: "2026-11-02", effortScale: .hundred, sleep: nil)
        XCTAssertEqual(content.label, "Effort")
        XCTAssertEqual(content.value, UnitFormatter.effortDisplay(38, scale: .hundred))
        XCTAssertNil(content.detail)
    }

    /// Charge and the night's HRV, carried from the last night that has one when the day has none.
    func testChargeCarriesTheLastNightsHRV() {
        let days = [day("2026-11-01", hrv: 45.6), day("2026-11-02", recovery: 72)]
        let content = LiveHRBannerFigures.sideContent(.charge, day: days[1], days: days, dayKey: "2026-11-02",
                                                      effortScale: .hundred, sleep: nil)
        XCTAssertEqual(content.value, "72")
        XCTAssertEqual(content.detail, "HRV 46 ms")
    }

    /// Sleep: the night, then the Synthèse's debt and bedtime once they are loaded.
    func testSleepNamesTheNightTheDebtAndTheBedtime() {
        let today = day("2026-11-02", sleep: 408)
        let figures = SleepSynthesisFigures(needMin: 480, debtMin: 72, isDebt: true, lastShortfallMin: 72,
                                            usualWakeMin: 7 * 60 + 10)
        XCTAssertEqual(figures.bedtimeMin, 23 * 60 + 10)
        let content = LiveHRBannerFigures.sideContent(.sleep, day: today, days: [today], dayKey: "2026-11-02",
                                                      effortScale: .hundred, sleep: figures)
        XCTAssertEqual(content.value, SleepDurationText.format(408))
        XCTAssertEqual(content.detail, "debt \(SleepDurationText.format(72)) · bedtime \(TodaySynthesisLogic.clock(23 * 60 + 10))")

        let loading = LiveHRBannerFigures.sideContent(.sleep, day: today, days: [today], dayKey: "2026-11-02",
                                                      effortScale: .hundred, sleep: nil)
        XCTAssertNil(loading.detail, "the night alone until the debt and bedtime are read")

        let met = SleepSynthesisFigures(needMin: 480, debtMin: 5, isDebt: false, lastShortfallMin: nil, usualWakeMin: nil)
        XCTAssertEqual(LiveHRBannerFigures.sideContent(.sleep, day: today, days: [today], dayKey: "2026-11-02",
                                                       effortScale: .hundred, sleep: met).detail, "debt None")
    }

    func testTheSubtitleNamesTheZone() {
        XCTAssertEqual(LiveHRBannerFigures.subtitle(zone: 2), "Live HR · zone 2")
        XCTAssertEqual(LiveHRBannerFigures.subtitle(zone: 0), "Live HR · resting zone")
        XCTAssertEqual(LiveHRBannerFigures.subtitle(zone: nil), "Live HR")
    }
}
