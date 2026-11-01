import Foundation
import WhoopStore

// Personal fork, Nutrition: the app's access to the meal journal (`MealLogStore` in WhoopStore).
//
// The Nutrition screens and the Coach build and read meals through here, so a meal is dated by the same
// local day and its lines are rounded by the same `MealMath`, wherever it was entered: typed by hand,
// read off a photo, dictated or scanned. Nothing here touches the interface.

enum MealJournal {

    /// UserDefaults counter bumped after every write, so a screen showing meals (Today's line under the
    /// calories, Nutrition) reloads when one is added, edited, starred or deleted elsewhere.
    static let revisionKey = "nutrition.mealJournalRevision"

    @MainActor
    private static func bumpMealRevision() {
        let defaults = UserDefaults.standard
        defaults.set(defaults.integer(forKey: revisionKey) &+ 1, forKey: revisionKey)
    }

    /// The local day `date` falls on, "yyyy-MM-dd": the journal's day key. Written with the meal, so
    /// travelling to another time zone never moves a meal to another day.
    static func mealDayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// A line typed by hand, with no quantity: its energy from the macros (4 / 4 / 9) unless the wearer
    /// typed their own, and its macros to one decimal.
    static func typedMealLine(name: String, proteinG: Double, carbsG: Double, fatG: Double,
                              kcal typed: Int? = nil) -> MealItemRow {
        let kcal = typed.map { max($0, 0) } ?? MealMath.kcal(proteinG: proteinG, carbsG: carbsG, fatG: fatG)
        return MealItemRow(id: UUID().uuidString, mealId: "", ord: 0, name: name, grams: nil,
                           nutrients: MealNutrients(kcal: kcal, proteinG: MealMath.tenth(proteinG),
                                                    carbsG: MealMath.tenth(carbsG), fatG: MealMath.tenth(fatG)))
    }

    /// A line from a food's values per 100 g (the Ciqual table or a label) and the quantity eaten. The
    /// quantity is kept to one decimal first, and the values are computed from that kept quantity, so a
    /// later edit recomputes from exactly what is stored.
    static func measuredMealLine(name: String, grams: Double, estimated: Bool, per100: MealPer100,
                                 foodRef: String?) -> MealItemRow {
        let kept = MealMath.tenth(grams)
        return MealItemRow(id: UUID().uuidString, mealId: "", ord: 0, name: name, grams: kept,
                           gramsEstimated: estimated, nutrients: MealMath.portion(per100: per100, grams: kept),
                           foodRef: foodRef, per100: per100)
    }

    /// Save a meal eaten at `eatenAt` with its lines, in that order. Pass the `id` of an existing meal
    /// to edit it: it keeps its first save time, everything else is replaced.
    @discardableResult
    static func saveMealEntry(_ store: WhoopStore, id: String? = nil, name: String, origin: MealOrigin,
                              eatenAt: Date, favorite: Bool = false, lines: [MealItemRow],
                              now: Date = Date()) async throws -> MealEntry {
        let stamp = Int(now.timeIntervalSince1970)
        let meal = MealRow(id: id ?? UUID().uuidString, day: mealDayKey(eatenAt),
                           eatenAt: Int(eatenAt.timeIntervalSince1970), name: name, origin: origin,
                           favorite: favorite, createdAt: stamp, updatedAt: stamp)
        try await store.saveMeal(meal, items: lines)
        await bumpMealRevision()
        let saved = lines.enumerated().map { index, line -> MealItemRow in
            var row = line
            row.mealId = meal.id
            row.ord = index
            return row
        }
        return MealEntry(meal: meal, items: saved)
    }

    /// A recent meal added again at `eatenAt`: the same lines under new ids, as a new entry.
    @discardableResult
    static func addMealAgain(_ store: WhoopStore, _ entry: MealEntry, eatenAt: Date = Date()) async throws -> MealEntry {
        let lines = entry.items.map { line -> MealItemRow in
            var copy = line
            copy.id = UUID().uuidString
            return copy
        }
        return try await saveMealEntry(store, name: entry.meal.name, origin: entry.meal.origin,
                                       eatenAt: eatenAt, lines: lines)
    }

    /// The meals of one local day, in the order eaten.
    static func mealJournalDay(_ store: WhoopStore, day: String) async throws -> [MealEntry] {
        try await store.mealEntries(fromDay: day, toDay: day)
    }

    /// The meals from `fromDay` to `toDay`, both included, in the order eaten.
    static func mealJournalRange(_ store: WhoopStore, fromDay: String, toDay: String) async throws -> [MealEntry] {
        try await store.mealEntries(fromDay: fromDay, toDay: toDay)
    }

    /// One meal with its lines, or nil.
    static func mealEntryById(_ store: WhoopStore, id: String) async throws -> MealEntry? {
        try await store.mealEntry(id: id)
    }

    /// What "Recent" offers: the latest meal of each name, favorites first.
    static func recentMealEntries(_ store: WhoopStore, limit: Int = 12) async throws -> [MealEntry] {
        try await store.recentMeals(limit: limit)
    }

    /// Mark or unmark a meal as a favorite.
    static func markMealFavorite(_ store: WhoopStore, id: String, favorite: Bool, now: Date = Date()) async throws {
        try await store.setMealFavorite(id: id, favorite: favorite, updatedAt: Int(now.timeIntervalSince1970))
        await bumpMealRevision()
    }

    /// Delete a meal and its lines.
    static func removeMeal(_ store: WhoopStore, id: String) async throws {
        try await store.deleteMeal(id: id)
        await bumpMealRevision()
    }
}

extension MealEntry {
    /// The meal's energy and macros: the sum of its lines (`MealMath.totals`).
    var mealTotals: MealNutrients { MealMath.totals(items.map(\.nutrients)) }
}
