import XCTest
@testable import Strand
import WhoopStore

/// Fork chantier 22 (micronutrients): the Ciqual columns read by name, an empty cell unknown (never 0),
/// a line's portion, a day's totals with the lines missing a value counted, the 7-day average over the
/// logged days only, Open Food Facts' values kept per barcode, and the references.
@MainActor
final class MealMicrosTests: XCTestCase {

    private let lentilsPer100 = MealPer100(kcal: 125, proteinG: 10.1, carbsG: 16.2, fatG: 0.6)
    private let testBarcode = "0000000022001"

    override func tearDown() {
        var all = UserDefaults.standard.dictionary(forKey: OpenFoodFactsMicros.storageKey) ?? [:]
        all[testBarcode] = nil
        UserDefaults.standard.set(all, forKey: OpenFoodFactsMicros.storageKey)
        let order = (UserDefaults.standard.stringArray(forKey: OpenFoodFactsMicros.orderKey) ?? [])
            .filter { $0 != testBarcode }
        UserDefaults.standard.set(order, forKey: OpenFoodFactsMicros.orderKey)
        super.tearDown()
    }

    private func line(_ name: String, grams: Double?, ref: String?) -> MealItemRow {
        MealItemRow(id: UUID().uuidString, mealId: "", ord: 0, name: name, grams: grams,
                    nutrients: MealNutrients(kcal: 100, proteinG: 1, carbsG: 1, fatG: 1), foodRef: ref,
                    per100: lentilsPer100)
    }

    func testTheTableReadsMicroColumnsByTheirHeaderNameAndLeavesEmptyCellsUnknown() {
        let text = """
        # Anses. 2025.
        # code\tname_fr\tname_en\tkcal\tprotein_g\tcarbs_g\tfat_g\tiron_mg\tfiber_g\tvitD_ug
        20360\tLentille, cuite\tLentil, cooked\t125\t10.1\t16.2\t0.6\t2.45\t8.45\t
        9104\tRiz blanc, cuit\tRice, white, cooked\t155\t3.3\t33.2\t0.7\t0\t\t0.1
        """
        let foods = CiqualTable.parseCiqualLines(text)
        XCTAssertEqual(foods.count, 2)
        XCTAssertEqual(foods[0].micros[.iron], 2.45)
        XCTAssertEqual(foods[0].micros[.fiber], 8.45)
        XCTAssertNil(foods[0].micros[.vitaminD], "an empty cell is unknown, not 0")
        XCTAssertEqual(foods[1].micros[.iron], 0, "a written 0 (traces) stays 0")
        XCTAssertNil(foods[1].micros[.fiber])
        XCTAssertEqual(foods[0].per100, lentilsPer100)
    }

    func testATableWithoutTheHeaderLineStillReadsItsMacros() {
        let foods = CiqualTable.parseCiqualLines("20360\tLentille\tLentil\t125\t10.1\t16.2\t0.6\t2.45")
        XCTAssertEqual(foods.count, 1)
        XCTAssertTrue(foods[0].micros.isEmpty)
    }

    func testAPortionScalesEveryValueByItsGrams() {
        let portion = MealMicros.portionMicros([.iron: 2.45, .fiber: 8.45], grams: 200)
        XCTAssertEqual(portion[.iron] ?? 0, 4.9, accuracy: 1e-9)
        XCTAssertEqual(portion[.fiber] ?? 0, 16.9, accuracy: 1e-9)
    }

    func testATypedLineOrALineWithoutGramsHasNoMicros() {
        XCTAssertNil(MealMicros.lineMicros(line("Sandwich", grams: nil, ref: nil)))
        XCTAssertNil(MealMicros.lineMicros(line("Sandwich", grams: 150, ref: nil)))
        XCTAssertNil(MealMicros.lineMicros(line("Lentilles", grams: nil, ref: "ciqual:20360")))
    }

    func testOpenFoodFactsValuesAreConvertedToEachUnitAndKeptPerBarcode() {
        let parsed = OpenFoodFactsMicros.parseOffMicros(["fiber_100g": 4, "salt_100g": "0.3",
                                                         "iron_100g": 0.0021, "vitamin-d_100g": 0.0000025,
                                                         "sugars_100g": -1])
        XCTAssertEqual(parsed[.fiber], 4)
        XCTAssertEqual(parsed[.salt], 0.3)
        XCTAssertEqual(parsed[.iron] ?? 0, 2.1, accuracy: 1e-9)
        XCTAssertEqual(parsed[.vitaminD] ?? 0, 2.5, accuracy: 1e-9)
        XCTAssertNil(parsed[.sugars], "a negative value is not a value")

        OpenFoodFactsMicros.rememberMicros(barcode: testBarcode, micros: parsed)
        let bar = MealMicros.lineMicros(line("Barre", grams: 50, ref: "ean:" + testBarcode))
        XCTAssertEqual(bar?[.fiber] ?? 0, 2, accuracy: 1e-9)
        XCTAssertNil(bar?[.magnesium])
    }

    func testDayTotalsSumTheKnownValuesAndCountTheLinesMissingThem() {
        OpenFoodFactsMicros.rememberMicros(barcode: testBarcode, micros: [.fiber: 4, .salt: 0.3])
        let items = [line("Barre", grams: 100, ref: "ean:" + testBarcode),
                     line("Barre", grams: 50, ref: "ean:" + testBarcode),
                     line("Sandwich", grams: nil, ref: nil)]
        let totals = MealMicros.microTotals(items)
        XCTAssertEqual(totals.lineCount, 3)
        XCTAssertEqual(totals.linesWithMicros, 2)
        XCTAssertEqual(totals.amount(.fiber) ?? 0, 6, accuracy: 1e-9)
        XCTAssertEqual(totals.missingLines(.fiber), 1)
        XCTAssertNil(totals.amount(.iron), "no line had iron: unknown, not 0")
        XCTAssertEqual(totals.missingLines(.iron), 3)

        let sources = MealMicros.topSources(.fiber, in: items)
        XCTAssertEqual(sources.count, 1, "the same food is one source")
        XCTAssertEqual(sources.first?.amount ?? 0, 6, accuracy: 1e-9)
    }

    func testTheWeekAverageLeavesTheDaysWithoutAMealOut() {
        OpenFoodFactsMicros.rememberMicros(barcode: testBarcode, micros: [.fiber: 10])
        let day = [line("Barre", grams: 100, ref: "ean:" + testBarcode)]
        let twice = [line("Barre", grams: 300, ref: "ean:" + testBarcode)]
        let average = MealMicros.dailyAverage([day, [], twice, []])
        XCTAssertEqual(average.days, 2)
        XCTAssertEqual(average.totals.amount(.fiber) ?? 0, 20, accuracy: 1e-9)
        XCTAssertEqual(MealMicros.dailyAverage([[], []]).days, 0)
    }

    func testReferencesFollowTheProfileAndTheIntakeGoal() {
        XCTAssertEqual(MicroReference.reference(for: .iron, sex: "male", intakeKcal: 2_500), 11)
        XCTAssertEqual(MicroReference.reference(for: .iron, sex: "female", intakeKcal: 2_500), 16)
        XCTAssertEqual(MicroReference.reference(for: .saturatedFat, sex: "male", intakeKcal: 2_700) ?? 0,
                       36, accuracy: 1e-9, "12 % of the energy, at 9 kcal a gram")
        XCTAssertEqual(MicroReference.reference(for: .saturatedFat, sex: "male", intakeKcal: 0) ?? 0,
                       2_000 * 0.12 / 9, accuracy: 1e-9)
        XCTAssertNil(MicroReference.reference(for: .cholesterol, sex: "male", intakeKcal: 2_000))
        XCTAssertEqual(MicroReference.percent(2.1, of: 15), 14)
        XCTAssertNil(MicroReference.percent(2.1, of: nil))
        XCTAssertTrue(MicroNutrient.salt.isCeiling)
        XCTAssertFalse(MicroNutrient.iron.isCeiling)
    }

    func testTheShortfallListsTargetsFurthestFromTheirReferenceFirst() {
        var totals = MicroTotals()
        totals.amounts = [.vitaminD: 3, .iron: 11, .fiber: 15, .salt: 9]
        let list = MealMicros.targetShortfall(totals, sex: "male", intakeKcal: 2_000)
        XCTAssertEqual(list.map { $0.0 }, [.vitaminD, .fiber, .iron], "ceilings (salt) are not in it")
        XCTAssertEqual(list.map { $0.1 }, [20, 50, 100])
    }

    func testTheCoachToolWritesEachNutrientWithItsReferenceAndTheFoodsMissingIt() {
        var totals = MicroTotals()
        totals.lineCount = 4
        totals.linesWithMicros = 3
        totals.amounts = [.iron: 10.8, .salt: 6.3]
        totals.missing = [.iron: 1]
        let text = CoachTools.micronutrients(totals, loggedDays: 5, from: "2026-11-01", to: "2026-11-07",
                                             sex: "male", intakeKcal: 2_000,
                                             sources: [.iron: [MicroSource(name: "Lentilles", amount: 4.4)]])
        XCTAssertTrue(text.contains("iron_mg: 10.8 mg/day · reference 11 mg (98 %) · missing in 1 of 4 foods · most from Lentilles 4.4 mg"), text)
        XCTAssertTrue(text.contains("salt_g: 6.3 g/day · ceiling 5.0 g (126 %)"), text)
        XCTAssertTrue(text.contains("vitD_ug: unknown (no food with a value) · reference 15 µg"), text)
        XCTAssertTrue(CoachTools.micronutrients(MicroTotals(), loggedDays: 0, from: "a", to: "b", sex: "male",
                                                intakeKcal: 2_000, sources: [:]).hasPrefix("No meal logged"))
    }

    func testEveryNutrientHasAColumnUnitAndGroup() {
        XCTAssertEqual(MicroNutrient.allCases.count, 33)
        XCTAssertEqual(MicroNutrient.vitaminD.unit, .micrograms)
        XCTAssertEqual(MicroNutrient.iron.unit, .milligrams)
        XCTAssertEqual(MicroNutrient.fiber.unit, .grams)
        XCTAssertEqual(MicroNutrient.epaDha.shownUnit, .milligrams)
        XCTAssertEqual(MicroNutrient.epaDha.shownAmount(0.12), 120, accuracy: 1e-9)
        XCTAssertEqual(MicroNutrient.alphaLinolenicAcid.group, .omegas)
        XCTAssertEqual(MicroNutrient.vitaminB12.group, .vitamins)
    }
}
