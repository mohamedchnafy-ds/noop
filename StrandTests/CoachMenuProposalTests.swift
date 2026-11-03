import XCTest
@testable import Strand
import WhoopStore

/// The Coach's menu card (personal fork, chantier 8, lot 3): `plan_menu` → the meals of one day, at their
/// planned times, values from Ciqual; then "Add as planned" writes them planned, counted nowhere.
@MainActor
final class CoachMenuProposalTests: XCTestCase {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Paris")!
        return cal
    }

    private let rice = CiqualFood(code: 9104, nameFr: "Riz blanc, cuit", nameEn: "Rice, white, cooked",
                                  per100: MealPer100(kcal: 155, proteinG: 3.3, carbsG: 33.2, fatG: 0.7))
    private let chicken = CiqualFood(code: 36032, nameFr: "Poulet, rôti", nameEn: "Chicken, roasted",
                                     per100: MealPer100(kcal: 189, proteinG: 29.8, carbsG: 0, fatG: 7.8))

    private func food(_ code: Int) -> CiqualFood? { [rice, chicken].first { $0.code == code } }

    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 9))! }

    private func input(date: String?) -> [String: Any] {
        var input: [String: Any] = [
            "meals": [
                ["name": "Dîner", "time": "19:30",
                 "items": [["ciqual_code": 36032, "grams": 150], ["ciqual_code": 9104, "grams": 200]]],
                ["name": "Déjeuner", "time": "12:30",
                 "items": [["ciqual_code": 9104, "grams": 180], ["ciqual_code": 99999, "grams": 50]]],
                ["name": "Rien", "time": "16:00", "items": [["ciqual_code": 99998, "grams": 50]]],
            ],
        ]
        if let date { input["date"] = date }
        return input
    }

    func testAMenuIsTheUsableMealsInTimeOrderOnTheDayAsked() throws {
        let parsed = CoachMenuProposal.fromMenuInput(input(date: "2026-11-04"), now: now, calendar: calendar, food: food)
        let menu = try XCTUnwrap(parsed.proposal)
        XCTAssertEqual(menu.day, "2026-11-04")
        XCTAssertEqual(menu.meals.map(\.name), ["Déjeuner", "Dîner"], "sorted by time; a meal with no known food is left out")
        XCTAssertEqual(parsed.unknownCodes, [99999, 99998])
        let lunch = Date(timeIntervalSince1970: TimeInterval(menu.meals[0].eatenAt))
        let parts = calendar.dateComponents([.day, .hour, .minute], from: lunch)
        XCTAssertEqual([parts.day, parts.hour, parts.minute], [4, 12, 30], "a planned time may be after now")
        XCTAssertEqual(menu.totals, MealMath.totals(menu.meals.flatMap { $0.itemRows.map(\.nutrients) }))
        XCTAssertFalse(menu.isAdded)
    }

    func testTheDayStaysWithinTodayAndAWeekAhead() {
        XCTAssertEqual(MealJournal.mealDayKey(CoachMenuProposal.menuDay(nil, now: now, calendar: calendar), calendar: calendar),
                       "2026-11-03")
        XCTAssertEqual(MealJournal.mealDayKey(CoachMenuProposal.menuDay("2026-11-10", now: now, calendar: calendar), calendar: calendar),
                       "2026-11-10")
        XCTAssertEqual(MealJournal.mealDayKey(CoachMenuProposal.menuDay("2026-11-11", now: now, calendar: calendar), calendar: calendar),
                       "2026-11-03", "more than 7 days ahead falls back to today")
        XCTAssertEqual(MealJournal.mealDayKey(CoachMenuProposal.menuDay("2026-11-01", now: now, calendar: calendar), calendar: calendar),
                       "2026-11-03", "a past day is not planned")
        let noon = CoachMenuProposal.menuTime("25:00", on: calendar.startOfDay(for: now), calendar: calendar)
        XCTAssertEqual(calendar.component(.hour, from: noon), 12)
    }

    func testNoUsableMealMakesNoCard() {
        let parsed = CoachMenuProposal.fromMenuInput(["meals": [["name": "x", "time": "12:00",
                                                                 "items": [["ciqual_code": 1, "grams": 10]]]]],
                                                     now: now, calendar: calendar, food: food)
        XCTAssertNil(parsed.proposal)
        XCTAssertEqual(parsed.unknownCodes, [1])
    }

    func testTheCardRoundTripsInTheReplyBlock() throws {
        let menu = try XCTUnwrap(CoachMenuProposal.fromMenuInput(input(date: nil), now: now, calendar: calendar,
                                                                 food: food).proposal)
        let text = CoachReplyMeta.join(body: "Voici un menu.", meta: CoachReplyMeta(menu: menu))
        XCTAssertEqual(CoachReplyMeta.split(text).meta?.menu, menu)
        XCTAssertEqual(CoachReplyMeta.body(text), "Voici un menu.")
        XCTAssertTrue(CoachReplyMeta.forModel(text, system: .metric).contains("[Menu for 2026-11-03"))
    }

    func testTheMenuToolIsACard() {
        let names = CoachTools.definitions(dataConsent: false, labBook: false).compactMap { $0["name"] as? String }
        XCTAssertTrue(names.contains(CoachMenuProposal.toolName))
    }
}
