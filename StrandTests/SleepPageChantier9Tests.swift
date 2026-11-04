import XCTest
import WhoopStore
import StrandDesign
@testable import Strand

/// The Sleep tab of chantier 9 (personal fork): which sections the page draws from the saved order, the
/// blocks « Customize Sleep » puts back, the horseshoe ring's angles, and the stacked bars of Your nights.
final class SleepPageChantier9Tests: XCTestCase {

    // MARK: Page sections

    func testPageDrawsTheIndicatorsThenYourNightsByDefault() {
        XCTAssertEqual(SleepLayoutPrefs.pageSections(orderRaw: "", hiddenRaw: ""), [.nightDetail, .sleepDebt])
    }

    func testPageKeepsTheSavedOrderAndHiddenSetOfWhatItDraws() {
        let order = "sleepDebt,stages,nightDetail,sleepMarks"
        XCTAssertEqual(SleepLayoutPrefs.pageSections(orderRaw: order, hiddenRaw: ""), [.sleepDebt, .nightDetail])
        XCTAssertEqual(SleepLayoutPrefs.pageSections(orderRaw: order, hiddenRaw: "nightDetail"), [.sleepDebt])
    }

    func testFoldedSectionsAreTheOnesThePageNoLongerDraws() {
        XCTAssertEqual(SleepLayoutPrefs.pageFoldedSections,
                       [.stages, .sleepMarks, .bodyClock, .stagesVsTypical, .asleepDuration])
        XCTAssertEqual(SleepCustomizationSheet.foldedSections, SleepLayoutPrefs.pageFoldedSections)
    }

    // MARK: Blocks put back

    func testRestoredBlocksAreOffByDefaultAndRoundTrip() {
        XCTAssertEqual(SleepRestoredBlock.storageKey, "sleep.restoredBlocks")
        XCTAssertTrue(SleepRestoredBlock.decodeRestored("").isEmpty)
        let some: Set<SleepRestoredBlock> = [.sleepMarks, .tonight]
        XCTAssertEqual(SleepRestoredBlock.encodeRestored(some), "tonight,sleepMarks")
        XCTAssertEqual(SleepRestoredBlock.decodeRestored("sleepMarks, tonight,unknown,tonight"), some)
        XCTAssertEqual(SleepRestoredBlock.allCases.map(\.rawValue), ["tonight", "whySleep", "bodyClock", "sleepMarks"])
    }

    // MARK: Horseshoe ring

    func testTheNightRunsFromBottomLeftOverTheTopToBottomRight() {
        let night: TimeInterval = 4 * 3600
        // Bed at 225° (bottom left), the middle of the night at 360° (top), wake at 495° = 135° (bottom right).
        XCTAssertEqual(SleepNightRingMath.angle(seconds: 0, night: night), 225, accuracy: 0.001)
        XCTAssertEqual(SleepNightRingMath.angle(seconds: night / 2, night: night), 360, accuracy: 0.001)
        XCTAssertEqual(SleepNightRingMath.angle(seconds: night, night: night), 495, accuracy: 0.001)
        // A quarter in: 9 o'clock, on the left side.
        XCTAssertEqual(SleepNightRingMath.angle(seconds: night / 4, night: night), 292.5, accuracy: 0.001)
    }

    // MARK: Your nights

    private func day(_ key: String, total: Double?, deep: Double?, rem: Double?, light: Double?,
                     efficiency: Double?) -> DailyMetric {
        DailyMetric(day: key, totalSleepMin: total, efficiency: efficiency, deepMin: deep, remMin: rem,
                    lightMin: light, disturbances: nil, restingHr: nil, avgHrv: nil, recovery: nil,
                    strain: nil, exerciseCount: nil)
    }

    func testStageSplitsReadTheDailyRowsAndDeriveAwakeFromEfficiency() {
        let splits = SleepNightsData.nightStageSplits(days: [
            day("2026-11-01", total: 220, deep: 47, rem: 67, light: 106, efficiency: 88),
            day("2026-11-02", total: 400, deep: 60, rem: 90, light: 250, efficiency: 0.8),
            day("2026-11-03", total: 300, deep: nil, rem: nil, light: nil, efficiency: 90),
            day("2026-11-04", total: 300, deep: 50, rem: 60, light: 190, efficiency: nil),
        ])
        XCTAssertEqual(splits["2026-11-01"]?.asleep, 220)
        XCTAssertEqual(splits["2026-11-01"]?.awake ?? -1, 220 / 0.88 - 220, accuracy: 0.001)
        XCTAssertEqual(splits["2026-11-02"]?.awake ?? -1, 100, accuracy: 0.001)
        XCTAssertNil(splits["2026-11-03"], "a night without stages is a grey bar")
        XCTAssertNotNil(splits["2026-11-04"])
        XCTAssertNil(splits["2026-11-04"]?.awake, "no efficiency, no awake figure")
    }

    func testBarSegmentsStackDeepRemLightAndSumToTheBar() {
        let split = SleepNightsData.Split(deep: 60, rem: 90, light: 250, awake: 30)
        // A nap credited on top of the night: the minutes the stages do not cover stay grey, at the top.
        let withNap = SleepNightBar(day: "d", minutes: 430, split: split).segments
        XCTAssertEqual(withNap.map { $0.stage }, [.deep, .rem, .light, nil])
        XCTAssertEqual(withNap.map { $0.minutes }.reduce(0, +), 430, accuracy: 0.001)
        // Stages adding up to more than the bar are scaled down to it.
        let short = SleepNightBar(day: "d", minutes: 200, split: split).segments
        XCTAssertEqual(short.map { $0.stage }, [.deep, .rem, .light])
        XCTAssertEqual(short.map { $0.minutes }.reduce(0, +), 200, accuracy: 0.001)
        // No stages: one grey bar; no minutes: nothing.
        XCTAssertEqual(SleepNightBar(day: "d", minutes: 300, split: nil).segments.map { $0.stage }, [nil])
        XCTAssertTrue(SleepNightBar(day: "d", minutes: nil, split: split).segments.isEmpty)
    }
}
