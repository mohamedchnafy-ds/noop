import XCTest
@testable import Strand

/// Personal fork, 13 Nov. recording: Today read « Spent 1 766 kcal » while Nutrition read « Spent 1767 » and
/// « Net −1767 » at the same moment. One rounding, one formatter, and one figure per data generation
/// (`DaySpentMemo`, behind `NutritionDayReader.spentOnDay`) for every reader of a day's « Spent ».
@MainActor
final class NutritionDayTests: XCTestCase {

    private func key(generation: Int = 7, day: String = "2026-11-13") -> DaySpentMemo.Key {
        DaySpentMemo.Key(dayKey: day, open: true, windowStart: 1_794_000_000, generation: generation,
                         inputs: "74.5|178|38|male|-|52", sessions: [])
    }

    // MARK: - One figure per generation

    func testTheFirstReadingOfAGenerationIsTheOneEveryReaderGets() {
        var memo = DaySpentMemo()
        let todayFigure = TodayEnergy.Split(restingKcal: 1_400.2, activityKcal: 366.0)   // 1 766
        let laterFigure = TodayEnergy.Split(restingKcal: 1_401.1, activityKcal: 366.0)   // 1 767, a minute on
        XCTAssertNil(memo.recalled(key()), "nothing kept yet")
        XCTAssertEqual(memo.keep(todayFigure, for: key()), todayFigure)
        XCTAssertEqual(memo.recalled(key()), .some(todayFigure))
        // A second screen that finished computing later, with a later clock, adopts the first figure.
        XCTAssertEqual(memo.keep(laterFigure, for: key()), todayFigure)
        XCTAssertEqual(memo.recalled(key())??.totalWholeKcal, 1_766)
    }

    func testANewGenerationReadsAfreshAndDropsTheOldOne() {
        var memo = DaySpentMemo()
        let before = TodayEnergy.Split(restingKcal: 1_400, activityKcal: 366)
        let after = TodayEnergy.Split(restingKcal: 1_420, activityKcal: 380)
        _ = memo.keep(before, for: key(generation: 7))
        XCTAssertEqual(memo.keep(after, for: key(generation: 8)), after)
        XCTAssertNil(memo.recalled(key(generation: 7)), "an older generation is not kept")
        XCTAssertEqual(memo.recalled(key(generation: 8)), .some(after))
    }

    func testOtherDaysOfTheSameGenerationAreKeptSideBySide() {
        var memo = DaySpentMemo()
        let today = TodayEnergy.Split(restingKcal: 1_400, activityKcal: 366)
        let yesterday = TodayEnergy.Split(restingKcal: 1_650, activityKcal: 420)
        _ = memo.keep(today, for: key())
        _ = memo.keep(yesterday, for: key(day: "2026-11-12"))
        XCTAssertEqual(memo.recalled(key()), .some(today))
        XCTAssertEqual(memo.recalled(key(day: "2026-11-12")), .some(yesterday))
    }

    func testADayWithNothingMeasuredIsKeptAsNothing() {
        var memo = DaySpentMemo()
        XCTAssertNil(memo.keep(nil, for: key()))
        XCTAssertEqual(memo.recalled(key()), .some(nil), "resolved as nothing, not « not resolved »")
        let late = TodayEnergy.Split(restingKcal: 10, activityKcal: 0)
        XCTAssertNil(memo.keep(late, for: key()), "the first answer of the generation stands")
    }

    // MARK: - One rounding, one formatter

    func testNutritionRoundsSpentAndNetAsTodaysCellDoes() {
        let split = TodayEnergy.Split(restingKcal: 1_400.25, activityKcal: 366.3)   // 1 766.55
        XCTAssertEqual(split.totalWholeKcal, 1_767)
        let day = NutritionDaySummary(dayKey: "2026-11-13", meals: [], spent: split)
        XCTAssertEqual(day.spentKcal, split.totalWholeKcal)
        XCTAssertEqual(day.balanceKcal, -split.totalWholeKcal)
        XCTAssertNil(NutritionDaySummary(dayKey: "2026-11-13", meals: [], spent: nil).balanceKcal)
    }

    func testSpentIsWrittenWithTheLanguagesGrouping() {
        // Today's cell and Nutrition's figures both write through `NutritionFormat.wholeKcal`.
        XCTAssertEqual(NutritionFormat.wholeKcal(1_766.55), NutritionFormat.whole(1_767))
        XCTAssertEqual(NutritionFormat.wholeKcal(1_766.4), NutritionFormat.whole(1_766))
        XCTAssertEqual(NutritionFormat.whole(1_767),
                       1_767.formatted(.number.locale(AppLanguage.activeLocale)))
        XCTAssertEqual(NutritionFormat.signedKcal(-1_767), "\u{2212}" + NutritionFormat.whole(1_767))
    }

    func testTodayIsAnOpenDayAndAWeekAgoIsNot() {
        let now = Date()
        XCTAssertTrue(NutritionDayReader.isOpenDay(now, now: now))
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
        XCTAssertFalse(NutritionDayReader.isOpenDay(weekAgo, now: now))
    }
}
