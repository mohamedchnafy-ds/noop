import XCTest
@testable import Strand
import WhoopStore

/// Fork chantier 9 (Nutrition by moment): the food search (journal foods first, then Ciqual, Open Food
/// Facts parsed from a search answer) and the day grouped into its four moments.
@MainActor
final class NutritionFoodSearchTests: XCTestCase {

    private let skyr = MealPer100(kcal: 63, proteinG: 11, carbsG: 4, fatG: 0.2)
    private let rice = MealPer100(kcal: 155, proteinG: 3.3, carbsG: 33.2, fatG: 0.7)

    private func entry(_ id: String, at eatenAt: Int, slot: MealSlot? = nil, items: [MealItemRow]) -> MealEntry {
        MealEntry(meal: MealRow(id: id, day: "2026-11-04", eatenAt: eatenAt, name: id, origin: .manual,
                                createdAt: 0, updatedAt: 0, slot: slot),
                  items: items)
    }

    private func weighed(_ name: String, grams: Double, per100: MealPer100, ref: String?) -> MealItemRow {
        MealItemRow(id: UUID().uuidString, mealId: "", ord: 0, name: name, grams: grams,
                    nutrients: MealMath.portion(per100: per100, grams: grams), foodRef: ref, per100: per100)
    }

    func testJournalFoodsAreTheLatestWeighedLineOfEachFood() {
        let typed = MealJournal.typedMealLine(name: "Shaker", proteinG: 30, carbsG: 10, fatG: 3)
        let entries = [
            entry("old", at: 1_000, items: [weighed("Skyr nature", grams: 100, per100: skyr, ref: "ean:1")]),
            entry("new", at: 2_000, items: [weighed("Skyr nature", grams: 150, per100: skyr, ref: "ean:1"),
                                            weighed("Riz blanc, cuit", grams: 200, per100: rice, ref: "ciqual:9104")]),
            entry("typed", at: 3_000, items: [typed]),
        ]
        let foods = NutritionFoodSearch.journalFoodHits(entries)
        XCTAssertEqual(foods.map(\.name), ["Skyr nature", "Riz blanc, cuit"], "a typed line has no values for 100 g")
        XCTAssertEqual(foods.first?.lastGrams, 150, "the latest quantity")
        XCTAssertEqual(NutritionFoodSearch.startingPortion(foods[0]), 150)
        XCTAssertEqual(NutritionFoodSearch.matchJournalFoods("skyr", in: foods, limit: 5).map(\.name), ["Skyr nature"])
        XCTAssertEqual(NutritionFoodSearch.matchJournalFoods("riz cuit", in: foods, limit: 5).map(\.name), ["Riz blanc, cuit"])
        XCTAssertTrue(NutritionFoodSearch.matchJournalFoods("riz poulet", in: foods, limit: 5).isEmpty, "every word must match")
    }

    func testTheJournalComesFirstAndCiqualDoesNotRepeatIt() {
        let journal = [NutritionFoodHit(name: "Riz blanc, cuit", per100: rice, foodRef: "ciqual:9104", source: .journal,
                                        lastGrams: 180)]
        let table = [CiqualFood(code: 9104, nameFr: "Riz blanc, cuit", nameEn: "Rice, white, cooked", per100: rice),
                     CiqualFood(code: 9100, nameFr: "Riz complet, cuit", nameEn: "Rice, brown, cooked", per100: rice)]
        let hits = NutritionFoodSearch.searchFoodHits("riz", journal: journal, ciqual: table)
        XCTAssertEqual(hits.map(\.source), [.journal, .ciqual])
        XCTAssertEqual(hits.map(\.foodRef), ["ciqual:9104", "ciqual:9100"])
        let line = NutritionFoodSearch.hitLine(hits[0], grams: 180)
        XCTAssertEqual(line.grams, 180)
        XCTAssertEqual(line.nutrients, MealMath.portion(per100: rice, grams: 180))
        XCTAssertEqual(NutritionFoodSearch.hitOrigin(hits[0]), .manual)
    }

    func testAnOpenFoodFactsSearchKeepsTheUsableProductsWithTheirBarcode() throws {
        let json = """
        {"count": 3, "products": [
          {"code": "3033490004743", "product_name_fr": "Skyr nature", "brands": "Siggi's",
           "nutriments": {"energy-kcal_100g": 63, "proteins_100g": 11, "carbohydrates_100g": 4, "fat_100g": 0.2}},
          {"code": "123", "product_name": "Too short a code",
           "nutriments": {"energy-kcal_100g": 63, "proteins_100g": 11, "carbohydrates_100g": 4, "fat_100g": 0.2}},
          {"code": "3017620422003", "product_name": "No values", "nutriments": {}},
          {"code": "3033490004743", "product_name": "Twice", "nutriments": {"proteins_100g": 1, "carbohydrates_100g": 1, "fat_100g": 1}}
        ]}
        """
        let products = OpenFoodFacts.parseSearch(Data(json.utf8))
        XCTAssertEqual(products.map(\.barcode), ["3033490004743"])
        XCTAssertEqual(products.first?.name, "Skyr nature · Siggi's")
        let hit = NutritionFoodSearch.productHit(try XCTUnwrap(products.first))
        XCTAssertEqual(hit.foodRef, "ean:3033490004743")
        XCTAssertEqual(hit.source, .openFoodFacts)
        XCTAssertEqual(NutritionFoodSearch.hitOrigin(hit), .barcode)
        let url = try XCTUnwrap(OpenFoodFacts.searchURL(terms: "skyr nature"))
        XCTAssertTrue(url.absoluteString.hasPrefix("https://world.openfoodfacts.org/cgi/search.pl?search_terms=skyr%20nature"))
    }

    func testTheDayIsGroupedInItsFourMoments() {
        let cal = Calendar.current
        func at(_ hour: Int, _ minute: Int) -> Int {
            Int(cal.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: hour, minute: minute))!.timeIntervalSince1970)
        }
        let line = MealJournal.typedMealLine(name: "x", proteinG: 10, carbsG: 10, fatG: 1, kcal: 500)
        let meals = [
            entry("shake", at: at(18, 15), slot: .snack, items: [line]),
            entry("oats", at: at(7, 40), items: [line]),
            entry("lunch", at: at(13, 5), items: [line]),
        ]
        let groups = NutritionSlots.groupMealsBySlot(meals)
        XCTAssertEqual(groups.map(\.slot), [.breakfast, .lunch, .snack, .dinner])
        XCTAssertEqual(groups.map { $0.meals.map(\.meal.id) }, [["oats"], ["lunch"], ["shake"], []],
                       "a saved moment wins over the time")
        XCTAssertEqual(groups[0].totals.kcal, 500)
        XCTAssertEqual(groups[0].shareOfGoal(2_500), 20)
        XCTAssertNil(groups[3].shareOfGoal(2_500), "no meal, no share")
        XCTAssertNil(groups[0].shareOfGoal(nil))
    }
}
