import XCTest
@testable import Strand
import WhoopStore

/// Chantier 8, lot 3: a planned meal (a menu) counts nowhere until it is marked eaten. Every figure reads a
/// day through `MealJournal.mealJournalDay` / `mealJournalRange`, so those must leave it out; the journal
/// shows it apart (`plannedMealsOfDay`), and an edit keeps it planned.
@MainActor
final class MealPlannedJournalTests: XCTestCase {

    private func line(_ kcal: Int) -> MealItemRow {
        MealJournal.typedMealLine(name: "x", proteinG: 10, carbsG: 10, fatG: 1, kcal: kcal)
    }

    func testAPlannedMealCountsNowhereUntilEaten() async throws {
        let store = try await WhoopStore.inMemory()
        let cal = Calendar.current
        let noon = cal.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 12))!
        let day = MealJournal.mealDayKey(noon)
        try await MealJournal.saveMealEntry(store, name: "Skyr", origin: .manual,
                                            eatenAt: noon.addingTimeInterval(-3_600), lines: [line(95)])
        let menu = try await MealJournal.saveMealEntry(store, name: "Poulet, riz", origin: .manual,
                                                       eatenAt: noon, planned: true, lines: [line(650)])

        let eaten = try await MealJournal.mealJournalDay(store, day: day)
        XCTAssertEqual(eaten.map(\.meal.name), ["Skyr"])
        XCTAssertEqual(NutritionDaySummary(dayKey: day, meals: eaten, spent: nil).eaten.kcal, 95)
        let range = try await MealJournal.mealJournalRange(store, fromDay: day, toDay: day)
        XCTAssertEqual(range.count, 1)
        let series = try await store.metricSeries(deviceId: NutritionSeries.nutritionDeviceId, key: "calories_in",
                                                  from: day, to: day)
        XCTAssertEqual(series.map(\.value), [95], "the series ignores the menu")
        let plannedList = try await MealJournal.plannedMealsOfDay(store, day: day)
        XCTAssertEqual(plannedList.map(\.meal.id), [menu.meal.id])

        // Editing the menu (no `planned` given) keeps it planned.
        try await MealJournal.saveMealEntry(store, id: menu.meal.id, name: "Poulet, riz, légumes", origin: .manual,
                                            eatenAt: noon, lines: [line(700)])
        let stillPlanned = try await MealJournal.plannedMealsOfDay(store, day: day)
        XCTAssertEqual(stillPlanned.map(\.meal.name), ["Poulet, riz, légumes"])

        try await MealJournal.markMealEaten(store, id: menu.meal.id)
        let after = try await MealJournal.mealJournalDay(store, day: day)
        XCTAssertEqual(after.map(\.meal.name), ["Skyr", "Poulet, riz, légumes"])
        let noneLeft = try await MealJournal.plannedMealsOfDay(store, day: day)
        XCTAssertTrue(noneLeft.isEmpty)
        let updated = try await store.metricSeries(deviceId: NutritionSeries.nutritionDeviceId, key: "calories_in",
                                                   from: day, to: day)
        XCTAssertEqual(updated.map(\.value), [795])
    }
}
