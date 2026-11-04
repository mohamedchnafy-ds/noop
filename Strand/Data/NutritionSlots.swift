import Foundation
import WhoopStore

// Fork chantier 9 (Nutrition, mockup 4): the day's meals in its four moments — Breakfast, Lunch, Snack,
// Dinner — each with its total, its macros and its share of the intake goal. A meal goes to its moment
// through the one rule (`MealJournal.mealSlot`), so Nutrition, the Coach and the widget never disagree.

/// One moment of the day with its meals.
struct NutritionSlotGroup: Equatable, Identifiable {
    let slot: MealSlot
    /// In the order eaten.
    let meals: [MealEntry]

    var id: String { slot.rawValue }
    var hasMeals: Bool { !meals.isEmpty }
    /// Every line of the moment's meals added together (`MealMath.totals`).
    var totals: MealNutrients { MealMath.totals(meals.flatMap { $0.items.map(\.nutrients) }) }

    /// The moment's share of the intake goal, in whole percent; nil without a goal or without a meal.
    func shareOfGoal(_ goalKcal: Int?) -> Int? {
        guard hasMeals, let goalKcal, goalKcal > 0 else { return nil }
        return Int((Double(totals.kcal) * 100 / Double(goalKcal)).rounded())
    }
}

enum NutritionSlots {
    /// The four moments in the order of the day, each with its meals (empty ones included).
    static func groupMealsBySlot(_ meals: [MealEntry], calendar: Calendar = .current) -> [NutritionSlotGroup] {
        let ordered = meals.sorted { a, b in
            a.meal.eatenAt != b.meal.eatenAt ? a.meal.eatenAt < b.meal.eatenAt : a.meal.id < b.meal.id
        }
        let bySlot = Dictionary(grouping: ordered, by: { MealJournal.mealSlot(of: $0.meal, calendar: calendar) })
        return MealSlot.allCases.map { NutritionSlotGroup(slot: $0, meals: bySlot[$0] ?? []) }
    }
}
