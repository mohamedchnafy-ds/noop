import XCTest
@testable import Strand
import WhoopStore

/// The Nutrition history (personal fork, chantier 8, lot 3): a day with no meal is a hole, never 0; the
/// averages count the logged days only; the balance is the day page's own; the range stops before today.
@MainActor
final class NutritionHistoryTests: XCTestCase {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Paris")!
        return cal
    }

    private func meal(_ day: String, kcal: Int, protein: Double) -> MealEntry {
        MealEntry(meal: MealRow(id: day + "-\(kcal)", day: day, eatenAt: 0, name: "m", origin: .manual,
                                favorite: false, createdAt: 0, updatedAt: 0),
                  items: [MealItemRow(id: day + "-\(kcal)-0", mealId: day + "-\(kcal)", ord: 0, name: "m", grams: nil,
                                      nutrients: MealNutrients(kcal: kcal, proteinG: protein, carbsG: 10, fatG: 5))])
    }

    func testTheRangeIsTheCompleteDaysBeforeToday() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 9))!
        let keys = NutritionHistory.historyDayKeys(before: now, count: 7, calendar: calendar)
        XCTAssertEqual(keys, ["2026-10-27", "2026-10-28", "2026-10-29", "2026-10-30",
                              "2026-10-31", "2026-11-01", "2026-11-02"])
        XCTAssertEqual(NutritionHistory.historyDayKeys(before: now, count: 30, calendar: calendar).count, 30)
    }

    func testADayWithNoMealIsAHoleNotZero() {
        let empty = NutritionDaySummary(dayKey: "2026-11-01", meals: [],
                                        spent: TodayEnergy.Split(restingKcal: 1_600, activityKcal: 400))
        let day = NutritionHistory.historyDay(empty, calendar: calendar)
        XCTAssertNil(day.eaten)
        XCTAssertNil(day.balanceKcal, "an unwritten day must not print a 2 000 kcal deficit")
        XCTAssertFalse(day.isLogged)
    }

    func testTheBalanceIsTheDayPagesOwn() {
        let summary = NutritionDaySummary(dayKey: "2026-11-01", meals: [meal("2026-11-01", kcal: 1_800, protein: 120)],
                                          spent: TodayEnergy.Split(restingKcal: 1_600, activityKcal: 400))
        let day = NutritionHistory.historyDay(summary, calendar: calendar)
        XCTAssertEqual(day.eaten?.kcal, 1_800)
        XCTAssertEqual(day.balanceKcal, summary.balanceKcal)
        XCTAssertEqual(day.balanceKcal, -200)

        let unmeasured = NutritionDaySummary(dayKey: "2026-11-02", meals: [meal("2026-11-02", kcal: 900, protein: 50)],
                                             spent: nil)
        XCTAssertNil(NutritionHistory.historyDay(unmeasured, calendar: calendar).balanceKcal)
    }

    func testAveragesCountTheLoggedDaysOnly() {
        let days = [
            NutritionHistory.historyDay(NutritionDaySummary(dayKey: "2026-10-31", meals: [], spent: nil), calendar: calendar),
            NutritionHistory.historyDay(NutritionDaySummary(
                dayKey: "2026-11-01", meals: [meal("2026-11-01", kcal: 2_000, protein: 150)],
                spent: TodayEnergy.Split(restingKcal: 1_700, activityKcal: 500)), calendar: calendar),
            NutritionHistory.historyDay(NutritionDaySummary(
                dayKey: "2026-11-02", meals: [meal("2026-11-02", kcal: 1_000, protein: 81), meal("2026-11-02", kcal: 500, protein: 20)],
                spent: nil), calendar: calendar),
        ]
        let model = NutritionHistoryModel(days: days, goalKcal: 2_500, proteinGoalG: 160, carbsGoalG: 250, fatGoalG: 80)
        XCTAssertEqual(model.loggedDays.map(\.dayKey), ["2026-11-01", "2026-11-02"])
        XCTAssertEqual(model.averageKcal, 1_750, "(2 000 + 1 500) / 2, the empty day left out")
        XCTAssertEqual(model.averageGrams { $0.proteinG }, 125.5)
        XCTAssertEqual(model.averageBalanceKcal, -200, "only the day with a measured expenditure has a balance")

        let none = NutritionHistoryModel(days: [days[0]], goalKcal: nil, proteinGoalG: nil, carbsGoalG: nil, fatGoalG: nil)
        XCTAssertNil(none.averageKcal)
        XCTAssertNil(none.averageGrams { $0.proteinG })
        XCTAssertNil(none.averageBalanceKcal)
    }

    func testNoonOfADayKey() {
        let noon = NutritionHistory.noonOf("2026-11-01", calendar: calendar)
        let parts = calendar.dateComponents([.year, .month, .day, .hour], from: noon)
        XCTAssertEqual([parts.year, parts.month, parts.day, parts.hour], [2026, 11, 1, 12])
    }
}
