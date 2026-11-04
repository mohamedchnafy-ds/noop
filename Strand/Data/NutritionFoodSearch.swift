import Foundation
import WhoopStore

// Fork chantier 9 (Nutrition, mockup 4): the food search at the top of Nutrition and in the sheet of each
// moment's "+". As the wearer types, the foods already in the journal come first (a weighed line keeps its
// values for 100 g), then the Ciqual table on the iPhone; Open Food Facts is asked only when the wearer
// taps the line that offers it (`OpenFoodFacts.searchProducts`). A food picked goes through a portion,
// then into the journal as a one-food meal whose values the app computes (`MealJournal.measuredMealLine`).

/// One food the search offers, whatever it came from.
struct NutritionFoodHit: Identifiable, Equatable {
    enum Source: String, Equatable {
        case journal, ciqual, openFoodFacts
    }

    let name: String
    let per100: MealPer100
    /// "ciqual:<code>" or "ean:<barcode>"; nil for a journal food that had none.
    let foodRef: String?
    let source: Source
    /// The quantity eaten last time (a journal food), where the portion starts.
    let lastGrams: Double?

    var id: String { source.rawValue + "|" + (foodRef ?? "name:" + name) }
}

enum NutritionFoodSearch {

    /// How far back the journal foods are read, and how many of each kind are listed.
    static let journalLookbackDays = 120
    static let journalLimit = 5
    static let ciqualLimit = 20

    /// The weighed foods of the journal, latest first, one per food (its `foodRef`, else its name).
    static func journalFoodHits(_ entries: [MealEntry]) -> [NutritionFoodHit] {
        let latestFirst = entries.sorted { a, b in
            a.meal.eatenAt != b.meal.eatenAt ? a.meal.eatenAt > b.meal.eatenAt : a.meal.id > b.meal.id
        }
        var seen = Set<String>()
        var hits: [NutritionFoodHit] = []
        for entry in latestFirst {
            for item in entry.items {
                guard let per100 = item.per100 else { continue }
                let key = item.foodRef ?? "name:" + item.name.lowercased()
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                hits.append(NutritionFoodHit(name: item.name, per100: per100, foodRef: item.foodRef,
                                             source: .journal, lastGrams: item.grams))
            }
        }
        return hits
    }

    /// The journal foods whose name holds every word of `query` (a word or the start of one, as the
    /// Ciqual search reads words), in the order given (latest first).
    static func matchJournalFoods(_ query: String, in foods: [NutritionFoodHit], limit: Int) -> [NutritionFoodHit] {
        let wanted = CiqualTable.searchWords(query)
        guard !wanted.isEmpty, limit > 0 else { return [] }
        let matching = foods.filter { food in
            let words = CiqualTable.searchWords(food.name)
            return wanted.allSatisfy { w in words.contains { $0 == w || (w.count >= 3 && $0.hasPrefix(w)) } }
        }
        return Array(matching.prefix(limit))
    }

    /// What the search lists for `query`: the matching journal foods, then the Ciqual foods the journal
    /// did not already offer (same `foodRef`).
    static func searchFoodHits(_ query: String, journal: [NutritionFoodHit], ciqual: [CiqualFood]) -> [NutritionFoodHit] {
        let mine = matchJournalFoods(query, in: journal, limit: journalLimit)
        let offered = Set(mine.compactMap(\.foodRef))
        let table = ciqual.filter { !offered.contains($0.foodRef) }.map { food in
            NutritionFoodHit(name: NutritionFoodSearchSheet.displayName(food), per100: food.per100,
                             foodRef: food.foodRef, source: .ciqual, lastGrams: nil)
        }
        return mine + table
    }

    /// A product Open Food Facts listed, as a hit (kept with its barcode, so a later scan finds it).
    static func productHit(_ product: BarcodeProduct) -> NutritionFoodHit {
        NutritionFoodHit(name: product.name, per100: product.per100,
                         foodRef: BarcodeCatalog.productRef(product.barcode), source: .openFoodFacts, lastGrams: nil)
    }

    /// The portion offered first: last time's, else 100 g.
    static func startingPortion(_ hit: NutritionFoodHit) -> Double {
        guard let last = hit.lastGrams, last > 0 else { return 100 }
        return MealJournal.clampedPortion(last)
    }

    /// How the meal entered the journal: a packaged product (a barcode) or a food picked by hand.
    static func hitOrigin(_ hit: NutritionFoodHit) -> MealOrigin {
        (hit.foodRef ?? "").hasPrefix("ean:") ? .barcode : .manual
    }

    /// The one line saved for `hit` at `grams`.
    static func hitLine(_ hit: NutritionFoodHit, grams: Double) -> MealItemRow {
        MealJournal.measuredMealLine(name: hit.name, grams: MealJournal.clampedPortion(grams), estimated: false,
                                     per100: hit.per100, foodRef: hit.foodRef)
    }

    /// The journal foods of the last `journalLookbackDays` days, read on the device.
    static func loadJournalFoods(_ store: WhoopStore, now: Date = Date()) async -> [NutritionFoodHit] {
        let from = Calendar.current.date(byAdding: .day, value: -journalLookbackDays, to: now) ?? now
        let entries = (try? await MealJournal.mealJournalRange(
            store, fromDay: MealJournal.mealDayKey(from), toDay: MealJournal.mealDayKey(now))) ?? []
        return journalFoodHits(entries)
    }
}
