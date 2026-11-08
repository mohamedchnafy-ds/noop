import Foundation
import WhoopStore

// Personal fork, Nutrition: the app's access to the meal journal (`MealLogStore` in WhoopStore).
//
// The Nutrition screens and the Coach build and read meals through here, so a meal is dated by the same
// local day and its lines are rounded by the same `MealMath`, wherever it was entered: typed by hand,
// read off a photo, dictated or scanned. Nothing here touches the interface. Every write that changes a
// day's totals rebuilds the journal's metric series (`NutritionSeries`) before the revision is bumped.

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
    /// to edit it: it keeps its first save time, everything else is replaced. `slot` (fork chantier 9):
    /// the moment of the day it goes to; nil files it by its time (`mealSlotForTime`). Every saved meal
    /// counts (fork chantier 9: no planned meal any more; the flag of a menu added before is cleared on edit).
    @discardableResult
    static func saveMealEntry(_ store: WhoopStore, id: String? = nil, name: String, origin: MealOrigin,
                              eatenAt: Date, favorite: Bool = false, slot: MealSlot? = nil, lines: [MealItemRow],
                              now: Date = Date()) async throws -> MealEntry {
        let stamp = Int(now.timeIntervalSince1970)
        let meal = MealRow(id: id ?? UUID().uuidString, day: mealDayKey(eatenAt),
                           eatenAt: Int(eatenAt.timeIntervalSince1970), name: name, origin: origin,
                           favorite: favorite, createdAt: stamp, updatedAt: stamp, planned: false,
                           slot: slot ?? mealSlotForTime(eatenAt))
        try await store.saveMeal(meal, items: lines)
        await NutritionSeries.rebuildNutritionSeries(store)
        await bumpMealRevision()
        let saved = lines.enumerated().map { index, line -> MealItemRow in
            var row = line
            row.mealId = meal.id
            row.ord = index
            return row
        }
        let entry = MealEntry(meal: meal, items: saved)
        // Fork chantier 15: a meal eaten during a fast proposes to end the fast at its time; the screen that
        // saved it asks (`FastingMealLink`). Recorded here so every way in (typed, scanned, the Coach) asks.
        await FastingMealLink.recordMealForFast(store, entry: entry, now: now)
        return entry
    }

    /// A recent meal added again at `eatenAt`, in `slot` (nil = by its time): the same lines under new
    /// ids, as a new entry.
    @discardableResult
    static func addMealAgain(_ store: WhoopStore, _ entry: MealEntry, eatenAt: Date = Date(),
                             slot: MealSlot? = nil) async throws -> MealEntry {
        let lines = entry.items.map { line -> MealItemRow in
            var copy = line
            copy.id = UUID().uuidString
            return copy
        }
        return try await saveMealEntry(store, name: entry.meal.name, origin: entry.meal.origin,
                                       eatenAt: eatenAt, slot: slot, lines: lines)
    }

    /// The meals of one local day, in the order eaten. Fork chantier 9: every meal counts, the menus the
    /// Coach planned before then included (they show as Coach meals; the wearer deletes what was not eaten).
    static func mealJournalDay(_ store: WhoopStore, day: String) async throws -> [MealEntry] {
        try await store.mealEntries(fromDay: day, toDay: day)
    }

    /// The meals from `fromDay` to `toDay`, both included, in the order eaten.
    static func mealJournalRange(_ store: WhoopStore, fromDay: String, toDay: String) async throws -> [MealEntry] {
        try await store.mealEntries(fromDay: fromDay, toDay: toDay)
    }

    // MARK: Moments of the day (fork chantier 9)

    /// The hours the moments start at (the owner's choice, 4 Nov 2026): 04:00 breakfast, 11:00 lunch,
    /// 15:00 snack, 18:00 dinner, which runs until 03:59. Fixed: they do not follow the day cycle setting.
    static let mealSlotStartHours = (breakfast: 4, lunch: 11, snack: 15, dinner: 18)

    /// The moment a time falls in (`mealSlotStartHours`): the default of a new meal, and the moment of a
    /// meal saved without one.
    static func mealSlotForTime(_ date: Date, calendar: Calendar = .current) -> MealSlot {
        let hour = calendar.component(.hour, from: date)
        let starts = mealSlotStartHours
        switch hour {
        case starts.breakfast..<starts.lunch: return .breakfast
        case starts.lunch..<starts.snack: return .lunch
        case starts.snack..<starts.dinner: return .snack
        default: return .dinner
        }
    }

    /// The moment a meal is shown in: the one saved with it, else the one its time falls in. The one rule
    /// Nutrition, the Coach and the widget file a meal by.
    static func mealSlot(of meal: MealRow, calendar: Calendar = .current) -> MealSlot {
        meal.slot ?? mealSlotForTime(Date(timeIntervalSince1970: TimeInterval(meal.eatenAt)), calendar: calendar)
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
        await NutritionSeries.rebuildNutritionSeries(store)
        await bumpMealRevision()
    }
}

extension MealEntry {
    /// The meal's energy and macros: the sum of its lines (`MealMath.totals`).
    var mealTotals: MealNutrients { MealMath.totals(items.map(\.nutrients)) }

    /// The moment it is shown in (`MealJournal.mealSlot`).
    var mealSlot: MealSlot { MealJournal.mealSlot(of: meal) }

    /// A meal of a menu the Coach proposed: added from the card (origin `coach`), or planned before
    /// fork chantier 9 turned menus into normal meals. Labelled "Coach" in the journal.
    var isCoachMenuMeal: Bool { meal.origin == .coach || meal.planned }
}
