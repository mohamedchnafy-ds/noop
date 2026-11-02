import XCTest
@testable import Strand
import WhoopStore

/// Packaged products (personal fork, Nutrition 4d): barcodes, the product found again in the journal,
/// and the product card the Coach makes from a photo of its label (`read_label`). Pure: no store, no
/// camera, no network.
final class BarcodeProductTests: XCTestCase {

    private let skyr = MealPer100(kcal: 63, proteinG: 11, carbsG: 4, fatG: 0.2)
    private let code = "3017620422003"

    private var now: Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 10, minute: 30))!
    }

    // MARK: Barcodes

    func testABarcodeIsEightToFourteenDigits() {
        XCTAssertEqual(BarcodeCatalog.normalizedBarcode(code), code)
        XCTAssertEqual(BarcodeCatalog.normalizedBarcode(" 3017620 422003 "), code)
        XCTAssertEqual(BarcodeCatalog.normalizedBarcode("96385074"), "96385074")
        XCTAssertNil(BarcodeCatalog.normalizedBarcode("1234567"))
        XCTAssertNil(BarcodeCatalog.normalizedBarcode("123456789012345"))
        XCTAssertNil(BarcodeCatalog.normalizedBarcode("30176204220a3"))
        XCTAssertNil(BarcodeCatalog.normalizedBarcode("３０１７６２０４２２００３"), "full-width digits are not a scan")
        XCTAssertEqual(BarcodeCatalog.productRef(code), "ean:3017620422003")
    }

    // MARK: The journal

    private func entry(_ id: String, eatenAt: Int, items: [MealItemRow]) -> MealEntry {
        MealEntry(meal: MealRow(id: id, day: "2026-10-12", eatenAt: eatenAt, name: id, origin: .barcode,
                                favorite: false, createdAt: eatenAt, updatedAt: eatenAt),
                  items: items)
    }

    private func line(_ name: String, grams: Double?, ref: String?, per100: MealPer100?) -> MealItemRow {
        MealItemRow(id: UUID().uuidString, mealId: "", ord: 0, name: name, grams: grams, gramsEstimated: false,
                    nutrients: MealNutrients(kcal: 1, proteinG: 0, carbsG: 0, fatG: 0), foodRef: ref, per100: per100)
    }

    func testTheLatestLineWithTheBarcodeIsTheProduct() throws {
        let newer = MealPer100(kcal: 60, proteinG: 10.5, carbsG: 4, fatG: 0.2)
        let entries = [
            entry("a", eatenAt: 100, items: [line("Skyr nature", grams: 150, ref: "ean:\(code)", per100: skyr)]),
            entry("b", eatenAt: 300, items: [line("Riz", grams: 200, ref: "ciqual:9104", per100: skyr),
                                             line("Skyr nature 0 %", grams: 170, ref: "ean:\(code)", per100: newer)]),
            entry("c", eatenAt: 400, items: [line("Skyr sans valeurs", grams: 150, ref: "ean:\(code)", per100: nil)]),
            entry("d", eatenAt: 500, items: [line("Autre", grams: 30, ref: "ean:96385074", per100: skyr)]),
        ]
        let product = try XCTUnwrap(BarcodeCatalog.latestProduct(barcode: code, in: entries))
        XCTAssertEqual(product.name, "Skyr nature 0 %")
        XCTAssertEqual(product.per100, newer)
        XCTAssertEqual(product.lastGrams, 170)
        XCTAssertEqual(product.lastEatenAt, 300)
        XCTAssertNil(BarcodeCatalog.latestProduct(barcode: "12345678", in: entries))
    }

    func testThePortionStartsAtLastTimeAndOffersIt() {
        let product = BarcodeProduct(barcode: code, name: "Skyr", per100: skyr, lastGrams: 150, lastEatenAt: 0)
        XCTAssertEqual(BarcodeCatalog.startingGrams(product), 150)
        XCTAssertEqual(BarcodeCatalog.portionChoices(lastGrams: 150), [100, 150, 200])
        XCTAssertEqual(BarcodeCatalog.portionChoices(lastGrams: 100), [100, 200])
        XCTAssertEqual(BarcodeCatalog.portionChoices(lastGrams: nil), [100, 200])
        let unweighed = BarcodeProduct(barcode: code, name: "Skyr", per100: skyr, lastGrams: nil, lastEatenAt: 0)
        XCTAssertEqual(BarcodeCatalog.startingGrams(unweighed), 100)
        XCTAssertEqual(MealJournal.clampedPortion(0), 1)
        XCTAssertEqual(MealJournal.clampedPortion(5_000), 2_000)
        XCTAssertEqual(MealJournal.clampedPortion(.nan), 100)
    }

    // MARK: The label card

    private func label(_ json: String, questionBarcode: String? = "3017620422003")
        -> (proposal: CoachMealProposal?, problem: String?) {
        CoachMealProposal.fromLabelInput(CoachTools.input(fromJSON: json), questionBarcode: questionBarcode, now: now)
    }

    func testTheLabelCardKeepsThePrintedValuesAndComputesThePortion() throws {
        let card = try XCTUnwrap(label("""
        {"name": "Skyr nature 0 %", "barcode": "999", "kcal": 63, "protein_g": 11, "carbs_g": 4, "fat_g": 0.2,
         "grams": 150}
        """).proposal)
        XCTAssertTrue(card.isLabelProduct)
        XCTAssertEqual(card.origin, .barcode)
        XCTAssertEqual(card.barcode, code, "the question's barcode wins over the model's")
        XCTAssertEqual(card.lines.first?.per100, skyr)
        XCTAssertNil(card.lines.first?.ciqualCode)
        let row = try XCTUnwrap(card.itemRows.first)
        XCTAssertEqual(row.foodRef, "ean:3017620422003")
        XCTAssertEqual(row.grams, 150)
        // 63 × 1,5 = 94,5 → 95 ; 11 × 1,5 = 16,5 ; 4 × 1,5 = 6 ; 0,2 × 1,5 = 0,3
        XCTAssertEqual(row.nutrients, MealNutrients(kcal: 95, proteinG: 16.5, carbsG: 6, fatG: 0.3))
        XCTAssertEqual(card.draftEntry(now: now).items.first?.foodRef, "ean:3017620422003")
        XCTAssertEqual(card.wireText().split(separator: "\n")[1],
                       "- Skyr nature 0 % (from the label, per 100 g: 63 kcal, P 11, C 4, F 0.2, barcode 3017620422003) "
                       + "150 g: 95 kcal, P 16.5, C 6, F 0.3")
    }

    func testTheEnergyComesFromKilojoulesOrTheMacrosWhenKcalIsNotPrinted() throws {
        let fromKJ = try XCTUnwrap(label(#"{"name": "Pain", "kj": 1046, "protein_g": 9, "carbs_g": 49, "fat_g": 3.2}"#).proposal)
        XCTAssertEqual(fromKJ.lines.first?.per100.kcal, 250, "1 046 kJ ÷ 4,184 = 250 kcal")
        XCTAssertEqual(fromKJ.lines.first?.grams, 100, "no portion given: 100 g")
        let fromMacros = try XCTUnwrap(label(#"{"name": "Mix", "protein_g": 10, "carbs_g": 20, "fat_g": 10}"#).proposal)
        XCTAssertEqual(fromMacros.lines.first?.per100.kcal, 210, "4 × 10 + 4 × 20 + 9 × 10")
    }

    func testAMisreadLabelGivesNoCardButAReason() {
        XCTAssertNil(label(#"{"name": "x", "kcal": 63, "protein_g": 11, "carbs_g": 4}"#).proposal)
        XCTAssertNotNil(label(#"{"name": "x", "kcal": 63, "protein_g": 11, "carbs_g": 4}"#).problem)
        let perPortion = label(#"{"name": "x", "kcal": 300, "protein_g": 60, "carbs_g": 40, "fat_g": 20}"#)
        XCTAssertNil(perPortion.proposal)
        XCTAssertTrue(perPortion.problem?.contains("per 100 g") ?? false)
        let tooRich = label(#"{"name": "x", "kcal": 1200, "protein_g": 0, "carbs_g": 0, "fat_g": 100}"#)
        XCTAssertNil(tooRich.proposal)
        XCTAssertTrue(tooRich.problem?.contains("900 kcal") ?? false)
    }

    func testWithoutAQuestionBarcodeTheModelsIsUsedWhenItIsOne() {
        let given = label(#"{"name": "x", "barcode": "3017620422003", "protein_g": 1, "carbs_g": 1, "fat_g": 1}"#,
                          questionBarcode: nil).proposal
        XCTAssertEqual(given?.barcode, code)
        let junk = label(#"{"name": "x", "barcode": "unknown", "protein_g": 1, "carbs_g": 1, "fat_g": 1}"#,
                         questionBarcode: nil).proposal
        XCTAssertNil(junk?.barcode)
        XCTAssertNil(junk?.itemRows.first?.foodRef, "no barcode, no product reference")
    }

    func testTheQuestionKeepsItsBarcodeApartFromItsWords() {
        let stored = CoachReplyMeta.join(body: "Lis l’étiquette", meta: CoachReplyMeta(photos: ["a.jpg"], barcode: code))
        let split = CoachReplyMeta.split(stored)
        XCTAssertEqual(split.body, "Lis l’étiquette")
        XCTAssertEqual(split.meta?.barcode, code)
        XCTAssertFalse(CoachReplyMeta(barcode: code).isEmpty)
        // A card stored before 4d still reads, with a Ciqual code on every line.
        let older = #"{"meal":{"name":"Riz","eatenAt":0,"origin":"manual","lines":[{"name":"Riz","ciqualCode":9104,"grams":200,"estimated":false,"per100":{"kcal":155,"proteinG":3.3,"carbsG":33.2,"fatG":0.7}}]}}"#
        let meta = CoachReplyMeta.split("A." + CoachReplyMeta.fenceOpen + older + CoachReplyMeta.fenceClose).meta
        XCTAssertEqual(meta?.meal?.lines.first?.ciqualCode, 9104)
        XCTAssertNil(meta?.meal?.barcode)
        XCTAssertFalse(meta?.meal?.isLabelProduct ?? true)
    }
}
