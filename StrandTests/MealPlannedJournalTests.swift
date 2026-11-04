import XCTest
@testable import Strand
import WhoopStore

/// Fork chantier 9: every meal counts (no planned meal any more; a menu planned in chantier 8 counts as a
/// Coach meal), and a meal is filed in a moment of the day — the one saved with it, else its time's.
@MainActor
final class MealPlannedJournalTests: XCTestCase {

    private func line(_ kcal: Int) -> MealItemRow {
        MealJournal.typedMealLine(name: "x", proteinG: 10, carbsG: 10, fatG: 1, kcal: kcal)
    }

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: hour, minute: minute))!
    }

    func testAMenuPlannedBeforeChantier9CountsAsACoachMeal() async throws {
        let store = try await WhoopStore.inMemory()
        let noon = at(12)
        let day = MealJournal.mealDayKey(noon)
        try await MealJournal.saveMealEntry(store, name: "Skyr", origin: .manual, eatenAt: at(11), lines: [line(95)])
        let menu = MealRow(id: "menu", day: day, eatenAt: Int(noon.timeIntervalSince1970), name: "Poulet, riz",
                           origin: .manual, createdAt: 0, updatedAt: 0, planned: true)
        try await store.saveMeal(menu, items: [line(650)])

        let meals = try await MealJournal.mealJournalDay(store, day: day)
        XCTAssertEqual(meals.map(\.meal.name), ["Skyr", "Poulet, riz"])
        XCTAssertEqual(NutritionDaySummary(dayKey: day, meals: meals, spent: nil).eaten.kcal, 745)
        XCTAssertEqual(meals.map(\.isCoachMenuMeal), [false, true])
        let range = try await MealJournal.mealJournalRange(store, fromDay: day, toDay: day)
        XCTAssertEqual(range.count, 2)

        // Edited, it is saved as an eaten meal in its moment, and still reads as a Coach meal only if it
        // came from the Coach's card.
        let edited = try await MealJournal.saveMealEntry(store, id: "menu", name: "Poulet, riz", origin: .coach,
                                                         eatenAt: noon, lines: [line(700)])
        XCTAssertFalse(edited.meal.planned)
        XCTAssertEqual(edited.meal.slot, .lunch)
        XCTAssertTrue(edited.isCoachMenuMeal)
        await NutritionSeries.rebuildNutritionSeries(store)
        let series = try await store.metricSeries(deviceId: NutritionSeries.nutritionDeviceId, key: "calories_in",
                                                  from: day, to: day)
        XCTAssertEqual(series.map(\.value), [795])
    }

    func testTheMomentOfATime() {
        let expected: [(Int, Int, MealSlot)] = [
            (4, 0, .breakfast), (10, 59, .breakfast), (11, 0, .lunch), (14, 59, .lunch), (15, 0, .snack),
            (17, 59, .snack), (18, 0, .dinner), (23, 59, .dinner), (0, 0, .dinner), (3, 59, .dinner),
        ]
        for (hour, minute, slot) in expected {
            XCTAssertEqual(MealJournal.mealSlotForTime(at(hour, minute)), slot, "\(hour):\(minute)")
        }
    }

    func testASavedMomentWinsOverTheTime() async throws {
        let store = try await WhoopStore.inMemory()
        let saved = try await MealJournal.saveMealEntry(store, name: "Shaker", origin: .voice, eatenAt: at(18, 15),
                                                        slot: .snack, lines: [line(230)])
        XCTAssertEqual(saved.meal.slot, .snack)
        XCTAssertEqual(saved.mealSlot, .snack)
        let byTime = try await MealJournal.saveMealEntry(store, name: "Avoine", origin: .manual, eatenAt: at(7, 40),
                                                         lines: [line(520)])
        XCTAssertEqual(byTime.meal.slot, .breakfast, "saved without a moment: the one its time falls in")
        let old = MealRow(id: "o", day: "2026-11-03", eatenAt: Int(at(13, 5).timeIntervalSince1970), name: "o",
                          origin: .manual, createdAt: 0, updatedAt: 0)
        XCTAssertEqual(MealJournal.mealSlot(of: old), .lunch, "a meal from before v53 is filed by its time")
    }
}
