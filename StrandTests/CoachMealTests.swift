import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Strand
import WhoopStore

/// The Coach's meals (personal fork, Nutrition 4c): the embedded Ciqual table and its search, the
/// `log_meal` card read and bounded, its values computed by the app, what the model reads back, the
/// photos sent with a question, and the fiche's NUTRITION block. Pure: no store, no network.
final class CoachMealTests: XCTestCase {

    private let fixture = """
    # Anses. 2025. Ciqual French food composition table.
    # code\tname_fr\tname_en\tkcal\tprotein_g\tcarbs_g\tfat_g
    9104\tRiz blanc, cuit, sans sel ajouté\tRice, white, cooked, no added salt\t155\t3.3\t33.2\t0.7
    9100\tRiz blanc, cru\tRice, white, raw\t350\t7.4\t77.5\t0.8
    36032\tPoulet, poitrine, viande et peau rôties/cuites au four\tChicken, breast, meat and skin, roasted\t189\t29.8\t0\t7.8
    13005\tBanane, chair sans peau, crue\tBanana, flesh without skin, raw\t88\t1.1\t19.7\t0
    22010\tOeuf dur\tEgg, hard-boiled\t134\t13.5\t0.5\t8.6
    bad line
    """

    private var foods: [CiqualFood] { CiqualTable.parseCiqualLines(fixture) }

    // MARK: The table

    func testTheTableReadsItsLinesAndSkipsTheRest() {
        XCTAssertEqual(foods.count, 5)
        XCTAssertEqual(foods[0].code, 9104)
        XCTAssertEqual(foods[0].per100, MealPer100(kcal: 155, proteinG: 3.3, carbsG: 33.2, fatG: 0.7))
        XCTAssertEqual(foods[0].foodRef, "ciqual:9104")
    }

    /// The table shipped with the app: Ciqual 2025, every food with its four values.
    func testTheBundledTableIsCiqual2025() throws {
        XCTAssertEqual(CiqualTable.bundled.count, 3_323)
        let rice = try XCTUnwrap(CiqualTable.food(code: 9104))
        XCTAssertEqual(rice.nameFr, "Riz blanc, cuit, sans sel ajouté")
        XCTAssertEqual(rice.per100.kcal, 155)
        XCTAssertEqual(CiqualTable.search("riz blanc cuit", limit: 1).first?.code, 9104)
    }

    func testSearchWordsFoldAccentsCaseAndPlurals() {
        XCTAssertEqual(CiqualTable.searchWords("Œufs durs, à la coque"), ["oeuf", "dur", "coque"])
        XCTAssertEqual(CiqualTable.searchWords("Pâtes cuites"), ["pate", "cuite"])
    }

    func testSearchPutsTheFoodsMatchingEveryWordFirst() {
        let index = foods.map(CiqualTable.IndexedFood.init)
        // Both words, then the better single match ("riz" whole beats "cuit" opening "cuites").
        XCTAssertEqual(CiqualTable.rankFoods("riz cuit", in: index, limit: 5).map(\.code), [9104, 9100, 36032])
        XCTAssertEqual(CiqualTable.rankFoods("riz cuit", in: index, limit: 1).map(\.code), [9104])
        XCTAssertEqual(CiqualTable.rankFoods("chicken breast", in: index, limit: 5).map(\.code), [36032])
        XCTAssertEqual(CiqualTable.rankFoods("oeufs", in: index, limit: 5).map(\.code), [22010])
        XCTAssertTrue(CiqualTable.rankFoods("pizza", in: index, limit: 5).isEmpty)
        XCTAssertTrue(CiqualTable.rankFoods("de la", in: index, limit: 5).isEmpty)
    }

    func testTheSearchResultGivesCodesAndValuesFor100g() {
        let text = CoachMealProposal.searchResult(query: "riz", foods: Array(foods.prefix(1)))
        XCTAssertTrue(text.contains("9104 · Riz blanc, cuit, sans sel ajouté / Rice, white, cooked, no added salt · 155 kcal, P 3.3, C 33.2, F 0.7"))
        XCTAssertTrue(CoachMealProposal.searchResult(query: "x", foods: []).hasPrefix("No Ciqual food"))
    }

    // MARK: The card

    private var now: Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 13, minute: 20))!
    }

    private func lookup(_ code: Int) -> CiqualFood? { foods.first { $0.code == code } }

    func testLogMealKeepsKnownFoodsBoundsQuantitiesAndNamesTheUnknown() throws {
        let input = CoachTools.input(fromJSON: """
        {"name": "Poulet, riz", "time": "13:05", "items": [
          {"ciqual_code": 36032, "name": "Poulet rôti", "grams": 180, "estimated": true},
          {"ciqual_code": "9104", "grams": 200.04, "estimated": true},
          {"ciqual_code": 99999, "grams": 50},
          {"ciqual_code": 13005, "grams": 5000},
          {"ciqual_code": 22010, "grams": 0}
        ]}
        """)
        let parsed = CoachMealProposal.fromToolInput(input, origin: .photo, now: now, food: lookup)
        let meal = try XCTUnwrap(parsed.proposal)
        XCTAssertEqual(parsed.unknownCodes, [99999])
        XCTAssertEqual(meal.name, "Poulet, riz")
        XCTAssertEqual(meal.origin, .photo)
        XCTAssertEqual(meal.lines.map(\.ciqualCode), [36032, 9104, 13005])
        XCTAssertEqual(meal.lines[1].name, "Riz blanc, cuit, sans sel ajouté", "no name: the table's")
        XCTAssertEqual(meal.lines[1].grams, 200)
        XCTAssertEqual(meal.lines[2].grams, 2000, "capped")
        XCTAssertTrue(meal.hasEstimate)
        let parts = Calendar.current.dateComponents([.hour, .minute],
                                                     from: Date(timeIntervalSince1970: TimeInterval(meal.eatenAt)))
        XCTAssertEqual(parts.hour, 13)
        XCTAssertEqual(parts.minute, 5)
    }

    func testNoUsableFoodMeansNoCard() {
        let input = CoachTools.input(fromJSON: #"{"name": "x", "items": [{"ciqual_code": 1, "grams": 10}]}"#)
        let parsed = CoachMealProposal.fromToolInput(input, origin: .manual, now: now, food: lookup)
        XCTAssertNil(parsed.proposal)
        XCTAssertEqual(parsed.unknownCodes, [1])
    }

    func testTheCardsValuesAreComputedFromCiqual() throws {
        let input = CoachTools.input(fromJSON: """
        {"name": "Poulet, riz", "items": [
          {"ciqual_code": 36032, "grams": 180, "estimated": true}, {"ciqual_code": 9104, "grams": 200}]}
        """)
        let meal = try XCTUnwrap(CoachMealProposal.fromToolInput(input, origin: .photo, now: now, food: lookup).proposal)
        let rows = meal.itemRows
        // 189 × 1.8 = 340.2; 29.8 × 1.8 = 53.64; 7.8 × 1.8 = 14.04
        XCTAssertEqual(rows[0].nutrients, MealNutrients(kcal: 340, proteinG: 53.6, carbsG: 0, fatG: 14))
        XCTAssertEqual(rows[0].foodRef, "ciqual:36032")
        XCTAssertTrue(rows[0].gramsEstimated)
        // 155 × 2 = 310; 3.3 × 2 = 6.6; 33.2 × 2 = 66.4; 0.7 × 2 = 1.4
        XCTAssertEqual(rows[1].nutrients, MealNutrients(kcal: 310, proteinG: 6.6, carbsG: 66.4, fatG: 1.4))
        XCTAssertEqual(meal.totals, MealNutrients(kcal: 650, proteinG: 60.2, carbsG: 66.4, fatG: 15.4))

        let draft = meal.draftEntry(now: now)
        XCTAssertEqual(draft.items.count, 2)
        XCTAssertEqual(draft.items.map(\.ord), [0, 1])
        XCTAssertEqual(draft.meal.origin, .photo)
        XCTAssertEqual(MealMath.totals(draft.items.map(\.nutrients)), meal.totals)
        XCTAssertEqual(Set(draft.items.map(\.mealId)), [draft.meal.id])
    }

    func testTheMealTimeStaysBetweenAWeekAgoAndNow() {
        let cal = Calendar.current
        func hm(_ d: Date) -> [Int] { [cal.component(.day, from: d), cal.component(.hour, from: d), cal.component(.minute, from: d)] }
        XCTAssertEqual(hm(CoachMealProposal.mealTime(time: nil, date: nil, now: now)), [1, 13, 20])
        XCTAssertEqual(hm(CoachMealProposal.mealTime(time: "07:40", date: nil, now: now)), [1, 7, 40])
        XCTAssertEqual(hm(CoachMealProposal.mealTime(time: "20:30", date: "2026-10-31", now: now)), [31, 20, 30])
        XCTAssertEqual(CoachMealProposal.mealTime(time: "21:00", date: nil, now: now), now, "not after now")
        XCTAssertEqual(hm(CoachMealProposal.mealTime(time: "25:99", date: "2026-10-01", now: now)),
                       hm(cal.date(byAdding: .day, value: -7, to: cal.startOfDay(for: now))!), "not before a week ago")
    }

    func testTheModelReadsTheCardBackWithItsValues() throws {
        let input = CoachTools.input(fromJSON: #"{"name": "Riz", "time": "12:00", "items": [{"ciqual_code": 9104, "grams": 200}]}"#)
        var meal = try XCTUnwrap(CoachMealProposal.fromToolInput(input, origin: .voice, now: now, food: lookup).proposal)
        let stored = CoachReplyMeta.join(body: "Voici ton repas.", meta: CoachReplyMeta(meal: meal))
        let forModel = CoachReplyMeta.forModel(stored, system: .metric)
        XCTAssertTrue(forModel.hasPrefix("Voici ton repas.\n\n[Meal shown to the user as a card, not saved yet] Riz · 2026-11-01 12:00"))
        XCTAssertTrue(forModel.contains("- Riz blanc, cuit, sans sel ajouté (Ciqual 9104) 200 g: 310 kcal, P 6.6, C 66.4, F 1.4"))
        XCTAssertTrue(forModel.hasSuffix("Total: 310 kcal, P 6.6, C 66.4, F 1.4"))
        meal.mealId = "m1"
        XCTAssertTrue(meal.wireText().contains("added to their journal"))
        XCTAssertEqual(CoachReplyMeta.split(stored).meta?.meal?.lines.first?.per100.kcal, 155)
    }

    func testTheShownResultNamesWhatWasLeftOut() {
        XCTAssertFalse(CoachMealProposal.shownResult(unknownCodes: []).contains("Left out"))
        XCTAssertTrue(CoachMealProposal.shownResult(unknownCodes: [1, 2]).hasSuffix("Left out, not in the table: 1, 2."))
    }

    // MARK: Questions with photos

    func testAQuestionsPhotosAreStoredApartFromItsWords() {
        let stored = CoachReplyMeta.join(body: "Analyse ce repas", meta: CoachReplyMeta(photos: ["a.jpg"], dictated: true))
        let split = CoachReplyMeta.split(stored)
        XCTAssertEqual(split.body, "Analyse ce repas")
        XCTAssertEqual(split.meta?.photos, ["a.jpg"])
        XCTAssertEqual(split.meta?.dictated, true)
        XCTAssertEqual(CoachReplyMeta.forModel(stored, system: .metric), "Analyse ce repas")
        // Only what is set is written: a reply's block is as short as before.
        XCTAssertEqual(CoachReplyMeta.join(body: "A.", meta: CoachReplyMeta(consulted: ["Lab Book"])),
                       "A." + CoachReplyMeta.fenceOpen + #"{"consulted":["Lab Book"]}"# + CoachReplyMeta.fenceClose)
        XCTAssertEqual(AICoachEngine.photoNames([stored, "plain"]), ["a.jpg"])
    }

    func testPhotosGoAsImageBlocksBeforeTheText() throws {
        let message = AnthropicToolRequest.userWithImages(text: "Q", jpegs: [Data([1, 2, 3])])
        XCTAssertEqual(message["role"] as? String, "user")
        let content = try XCTUnwrap(message["content"] as? [[String: Any]])
        XCTAssertEqual(content.count, 2)
        XCTAssertEqual(content[0]["type"] as? String, "image")
        let source = try XCTUnwrap(content[0]["source"] as? [String: Any])
        XCTAssertEqual(source["media_type"] as? String, "image/jpeg")
        XCTAssertEqual(source["data"] as? String, Data([1, 2, 3]).base64EncodedString())
        XCTAssertEqual(content[1]["text"] as? String, "Q")
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: message))
    }

    func testAPhotoIsReducedToItsLongEdge() throws {
        let width = 3000, height = 2000
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.8, green: 0.4, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let png = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(png as CFMutableData, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        let jpeg = try XCTUnwrap(CoachPhotoStore.reducedJPEG(png as Data))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(jpeg as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, 1568)
        let reducedHeight = try XCTUnwrap(properties[kCGImagePropertyPixelHeight] as? Int)
        XCTAssertTrue((1045...1046).contains(reducedHeight), "\(reducedHeight)")
        XCTAssertNil(CoachPhotoStore.reducedJPEG(Data("not an image".utf8)))
        XCTAssertTrue(CoachPhotoStore.isPhotoName(UUID().uuidString + ".jpg"))
        XCTAssertFalse(CoachPhotoStore.isPhotoName("../x.jpg"))
    }

    // MARK: The fiche

    func testTheNutritionBlockStatesTodayTheGoalsAndTheWeek() {
        let plan = NutritionGoals.intakePlan(weightKg: 80, proteinTenths: 20, fatTenths: 10, goalPercent: 10,
                                             reference: NutritionGoals.Reference(kcal: 2_330, days: 14))
        let block = CoachFiche.nutritionBlock(CoachFiche.Nutrition(
            eaten: MealNutrients(kcal: 1_495, proteinG: 111.3, carbsG: 182, fatG: 34.3), meals: 4,
            spentKcal: 2_100, balanceKcal: -605, plan: plan,
            reference: NutritionGoals.Reference(kcal: 2_330, days: 14), goalPercent: 10,
            proteinTenths: 20, fatTenths: 10, weekDaysLogged: 5, weekMeanKcal: 2_210, weekMeanProteinG: 142))
        XCTAssertTrue(block.hasPrefix("NUTRITION ("))
        XCTAssertTrue(block.contains("today so far: eaten 1495 kcal (protein 111 g, carbs 182 g, fat 34 g) in 4 meals; spent 2100 kcal; balance -605 kcal"))
        XCTAssertTrue(block.contains("intake 2560 kcal/day = mean expenditure 2330 kcal over 14 days × 1.10; protein 160 g (2.0 g/kg); fat 80 g (1.0 g/kg); carbs 300 g (the rest)"))
        XCTAssertTrue(block.contains("the 7 days before today: 5 days logged, mean eaten 2210 kcal, protein 142 g"))

        let empty = CoachFiche.nutritionBlock(CoachFiche.Nutrition(
            eaten: MealNutrients(kcal: 0, proteinG: 0, carbsG: 0, fatG: 0), meals: 0, spentKcal: nil, balanceKcal: nil,
            plan: NutritionGoals.intakePlan(weightKg: 80, proteinTenths: 20, fatTenths: 10, goalPercent: 0, reference: nil),
            reference: nil, goalPercent: 0, proteinTenths: 20, fatTenths: 10,
            weekDaysLogged: 0, weekMeanKcal: nil, weekMeanProteinG: nil))
        XCTAssertTrue(empty.contains("today so far: no meal logged"))
        XCTAssertTrue(empty.contains("intake not known yet (needs 3 complete days measured by the strap)"))
        XCTAssertTrue(empty.contains("the 7 days before today: no meal logged"))
    }

    func testAMealCardGetsTheMealFollowUps() {
        XCTAssertEqual(CoachPrompts.followUps(forFirstQuestion: "x", lastReplyHasSession: false, startsWithBrief: false,
                                              lastReplyHasMeal: true), CoachPrompts.mealFollowUps)
        XCTAssertTrue(CoachPrompts.suggestions.contains(CoachPrompts.photoMealPrompt))
    }

    func testTheMealsToolWritesTheLoggedDaysNewestFirst() {
        let days = [
            CoachTools.MealDay(day: "2026-10-31", meals: [
                .init(time: "08:00", name: "Avoine", nutrients: MealNutrients(kcal: 300, proteinG: 10, carbsG: 50, fatG: 6))]),
            CoachTools.MealDay(day: "2026-11-01", meals: [
                .init(time: "07:40", name: "Skyr", nutrients: MealNutrients(kcal: 95, proteinG: 17, carbsG: 6, fatG: 0.3)),
                .init(time: "12:30", name: "Riz", nutrients: MealNutrients(kcal: 310, proteinG: 6.6, carbsG: 66.4, fatG: 1.4),
                      slot: "lunch", fromCoachMenu: true)]),
            CoachTools.MealDay(day: "2026-10-30", meals: []),
        ]
        let text = CoachTools.meals(days, from: "2026-10-30", to: "2026-11-01")
        let lines = text.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines[1], "2026-11-01: 405 kcal, P 23.6, C 72.4, F 1.7 · 2 meals")
        XCTAssertEqual(lines[2], "  07:40 Skyr: 95 kcal, P 17, C 6, F 0.3")
        XCTAssertEqual(lines[3], "  12:30 lunch Riz (from your menu): 310 kcal, P 6.6, C 66.4, F 1.4")
        XCTAssertEqual(lines[4], "2026-10-31: 300 kcal, P 10, C 50, F 6 · 1 meal")
        XCTAssertFalse(text.contains("2026-10-30:"))
        XCTAssertTrue(CoachTools.meals([], from: "a", to: "b").hasPrefix("No meal logged"))
    }
}
