import XCTest
@testable import Strand
import WhoopStore

/// A new barcode looked up on Open Food Facts (personal fork): what is read from its answer, and what
/// is refused.
final class OpenFoodFactsTests: XCTestCase {

    private func answer(_ product: [String: Any], status: Int = 1) -> Data {
        try! JSONSerialization.data(withJSONObject: ["code": "3017620422003", "status": status, "product": product])
    }

    func testTheRequestAsksForTheBarcodeAndOnlyTheFieldsUsed() {
        let url = OpenFoodFacts.productURL(barcode: "3017620422003")?.absoluteString ?? ""
        XCTAssertTrue(url.hasPrefix("https://world.openfoodfacts.org/api/v2/product/3017620422003.json"))
        XCTAssertTrue(url.contains("fields=code,product_name,product_name_fr,brands,nutriments"))
    }

    func testAProductWithItsValuesForOneHundredGrams() {
        let data = answer(["product_name_fr": "Skyr nature 0 %", "brands": "Siggi's, Arla",
                           "nutriments": ["energy-kcal_100g": 63, "proteins_100g": 11, "carbohydrates_100g": 4,
                                          "fat_100g": 0.2]])
        let product = OpenFoodFacts.parseProduct(data, barcode: "3017620422003")
        XCTAssertEqual(product?.name, "Skyr nature 0 % · Siggi's")
        XCTAssertEqual(product?.per100, MealPer100(kcal: 63, proteinG: 11, carbsG: 4, fatG: 0.2))
        XCTAssertEqual(product?.source, .openFoodFacts)
        XCTAssertNil(product?.lastGrams)
    }

    func testEnergyFromKilojoulesOrTheMacrosAndNumbersWrittenAsText() {
        let kj = answer(["product_name": "Pain complet",
                         "nutriments": ["energy-kj_100g": 1046, "proteins_100g": "9,5", "carbohydrates_100g": "41",
                                        "fat_100g": 3]])
        XCTAssertEqual(OpenFoodFacts.parseProduct(kj, barcode: "1")?.per100.kcal ?? 0, 250, accuracy: 0.05)
        XCTAssertEqual(OpenFoodFacts.parseProduct(kj, barcode: "1")?.per100.proteinG, 9.5)
        let macros = answer(["product_name": "Riz", "nutriments": ["proteins_100g": 7, "carbohydrates_100g": 78,
                                                                    "fat_100g": 1]])
        XCTAssertEqual(OpenFoodFacts.parseProduct(macros, barcode: "1")?.per100.kcal, 349)
    }

    func testUnusableAnswersAreRefused() {
        XCTAssertNil(OpenFoodFacts.parseProduct(answer([:], status: 0), barcode: "1"), "product not found")
        XCTAssertNil(OpenFoodFacts.parseProduct(answer(["product_name": "Sans valeurs", "nutriments": [:]]),
                                                barcode: "1"))
        XCTAssertNil(OpenFoodFacts.parseProduct(answer(["product_name": "Trop", "nutriments": [
            "energy-kcal_100g": 400, "proteins_100g": 60, "carbohydrates_100g": 60, "fat_100g": 1]]), barcode: "1"),
                     "more than 100 g of macros in 100 g")
        XCTAssertNil(OpenFoodFacts.parseProduct(answer(["nutriments": [
            "energy-kcal_100g": 100, "proteins_100g": 1, "carbohydrates_100g": 1, "fat_100g": 1]]), barcode: "1"),
                     "no name")
        XCTAssertNil(OpenFoodFacts.parseProduct(Data("not json".utf8), barcode: "1"))
    }

    func testTheBrandIsNotRepeatedAndTheNameIsCut() {
        XCTAssertEqual(OpenFoodFacts.productName(["product_name": "Nutella", "brands": "Nutella,Ferrero"]), "Nutella")
        let long = String(repeating: "a", count: 80)
        XCTAssertEqual(OpenFoodFacts.productName(["product_name": long]).count, 60)
    }
}
