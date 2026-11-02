import XCTest
@testable import Strand
import WhoopStore

/// Dictate and Photo in Add a meal (personal fork): the one-shot estimate's instructions and the names
/// the Ciqual search shows.
final class MealEstimateTests: XCTestCase {

    func testInstructionsNameTheToolsTheLanguageAndTheTime() {
        var c = DateComponents()
        c.year = 2026; c.month = 11; c.day = 2; c.hour = 12; c.minute = 40
        let utc = TimeZone(identifier: "UTC")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = utc
        let now = cal.date(from: c)!
        let prompt = AICoachEngine.mealEstimateSystemPrompt(now: now, languageName: "French", timeZone: utc)
        for tool in [CoachMealProposal.searchToolName, CoachMealProposal.logToolName, CoachMealProposal.labelToolName] {
            XCTAssertTrue(prompt.contains(tool), "the instructions name \(tool)")
        }
        XCTAssertTrue(prompt.contains("in French"))
        XCTAssertTrue(prompt.contains("2026-11-02 at 12:40"))
        XCTAssertTrue(prompt.contains("Never state calories or macros yourself"))
    }

    func testLanguageNameFollowsTheApp() {
        XCTAssertEqual(AICoachEngine.mealEstimateLanguageName(Locale(identifier: "fr_FR")), "French")
        XCTAssertEqual(AICoachEngine.mealEstimateLanguageName(Locale(identifier: "de_DE")), "German")
    }

    func testSearchShowsTheNameInTheAppLanguage() {
        let food = CiqualFood(code: 9104, nameFr: "Riz blanc, cuit", nameEn: "Rice, white, cooked",
                              per100: .init(kcal: 130, proteinG: 2.7, carbsG: 28, fatG: 0.3))
        XCTAssertEqual(NutritionFoodSearchSheet.displayName(food, locale: Locale(identifier: "fr_FR")), "Riz blanc, cuit")
        XCTAssertEqual(NutritionFoodSearchSheet.displayName(food, locale: Locale(identifier: "en_GB")),
                       "Rice, white, cooked")
    }
}
