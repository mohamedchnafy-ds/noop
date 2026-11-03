import Foundation
import WhoopStore

// MARK: - The Coach's menu card (personal fork, chantier 8, lot 3)
//
// `plan_menu`: the Coach proposes the meals of one day (today or a day ahead) as a card. Nothing is saved
// until "Add as planned": each meal then goes to the journal as PLANNED (`MealRow.planned`), greyed in
// Nutrition and counted nowhere until it is marked eaten. "Undo" removes the meals the card added. Every
// food is a Ciqual code and a quantity, as on the meal card: the app computes the values.

struct CoachMenuProposal: Codable, Equatable {
    /// The day planned, "yyyy-MM-dd".
    var day: String
    /// The meals, in the order planned; each one's `eatenAt` is the time it is planned for.
    var meals: [CoachMealProposal]
    /// The journal meals the card added, once "Add as planned" was tapped; empty before (and after Undo).
    var mealIds: [String] = []

    static let toolName = "plan_menu"
    static let maxMeals = 6
    /// How far ahead a menu can be planned.
    static let maxDaysAhead = 7

    var isAdded: Bool { !mealIds.isEmpty }

    /// The day planned, as a date: its first meal's time (the day starts there), else now.
    var dayDate: Date { meals.first.map { Date(timeIntervalSince1970: TimeInterval($0.eatenAt)) } ?? Date() }

    /// The day's energy and macros: every line of every meal.
    var totals: MealNutrients { MealMath.totals(meals.flatMap { $0.itemRows.map(\.nutrients) }) }

    /// `plan_menu`: the card. Sent with every tool question; nothing is saved by the call.
    static var definition: [String: Any] {
        let item: [String: Any] = [
            "type": "object",
            "properties": [
                "ciqual_code": ["type": "integer", "description": "A code returned by search_foods."],
                "name": ["type": "string", "description": "A short name for the card, in the user's language."],
                "grams": ["type": "number", "minimum": CoachMealProposal.gramRange.lowerBound,
                          "maximum": CoachMealProposal.gramRange.upperBound],
            ] as [String: Any],
            "required": ["ciqual_code", "grams"],
        ]
        let meal: [String: Any] = [
            "type": "object",
            "properties": [
                "name": ["type": "string", "description": "The meal's name (\"Déjeuner : poulet, riz\")."],
                "time": ["type": "string", "description": "HH:MM, when it is planned."],
                "items": ["type": "array", "items": item, "minItems": 1, "maxItems": CoachMealProposal.maxLines],
            ] as [String: Any],
            "required": ["name", "time", "items"],
        ]
        return [
            "name": toolName,
            "description": "Propose a menu, the meals of one day, as a card with “Add as planned”. Only when the user "
                + "asks for a menu or a meal plan. Nothing is saved until they tap; the meals then go to their "
                + "journal as planned (greyed, counted nowhere until they mark one eaten). Give every food by its "
                + "Ciqual code from search_foods and its quantity in grams: the app computes the calories and "
                + "macros, so never state them yourself.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "date": ["type": "string", "description": "YYYY-MM-DD, today or up to 7 days ahead; leave out for today."],
                    "meals": ["type": "array", "items": meal, "minItems": 1, "maxItems": maxMeals],
                ] as [String: Any],
                "required": ["meals"],
            ] as [String: Any],
        ]
    }

    /// What the model is told once the card is shown.
    static func shownResult(unknownCodes: [Int]) -> String {
        var text = "Shown to the user as a menu card with “Add as planned”. Nothing is saved until they tap. The "
            + "app computed the values from Ciqual: do not repeat them and add nothing after the card."
        if !unknownCodes.isEmpty {
            text += " Left out, not in the table: " + unknownCodes.map(String.init).joined(separator: ", ") + "."
        }
        return text
    }

    /// The menu in a `plan_menu` input, bounded, with the codes the table does not know; nil when no meal
    /// is usable.
    static func fromMenuInput(_ input: [String: Any], now: Date, calendar: Calendar = .current,
                              food: (Int) -> CiqualFood?) -> (proposal: CoachMenuProposal?, unknownCodes: [Int]) {
        let day = menuDay(CoachTools.text(input, "date"), now: now, calendar: calendar)
        var meals: [CoachMealProposal] = []
        var unknown: [Int] = []
        for raw in ((input["meals"] as? [[String: Any]]) ?? []).prefix(maxMeals) {
            var mealInput = raw
            mealInput["time"] = nil
            mealInput["date"] = nil
            let parsed = CoachMealProposal.fromToolInput(mealInput, origin: .manual, now: now, calendar: calendar, food: food)
            unknown += parsed.unknownCodes
            guard var meal = parsed.proposal else { continue }
            meal.eatenAt = Int(menuTime(CoachTools.text(raw, "time"), on: day, calendar: calendar).timeIntervalSince1970)
            meals.append(meal)
        }
        guard !meals.isEmpty else { return (nil, unknown) }
        meals.sort { $0.eatenAt < $1.eatenAt }
        return (CoachMenuProposal(day: MealJournal.mealDayKey(day, calendar: calendar), meals: meals), unknown)
    }

    /// The day planned: `date` when it is today or up to `maxDaysAhead` days ahead, else today.
    static func menuDay(_ date: String?, now: Date, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        guard let date else { return today }
        let parts = date.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let parsed = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
              let last = calendar.date(byAdding: .day, value: maxDaysAhead, to: today) else { return today }
        let day = calendar.startOfDay(for: parsed)
        return day < today || day > last ? today : day
    }

    /// `time` ("HH:MM") on `day`; noon when it is missing or not a time.
    static func menuTime(_ time: String?, on day: Date, calendar: Calendar = .current) -> Date {
        var hour = 12
        var minute = 0
        let parts = (time ?? "").split(separator: ":").compactMap { Int($0) }
        if parts.count >= 2, (0...23).contains(parts[0]), (0...59).contains(parts[1]) {
            hour = parts[0]
            minute = parts[1]
        }
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    /// The card as the model reads it back in a later turn, so "swap the rice" refers to it.
    func wireText() -> String {
        var out = ["[Menu for \(day) shown to the user as a card"
                   + (isAdded ? ", added to their journal as planned" : ", not saved yet") + "]"]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        for meal in meals {
            let t = meal.totals
            out.append("\(formatter.string(from: Date(timeIntervalSince1970: TimeInterval(meal.eatenAt)))) \(meal.name): "
                       + "\(t.kcal) kcal, P \(CoachMealProposal.tenthText(t.proteinG)), "
                       + "C \(CoachMealProposal.tenthText(t.carbsG)), F \(CoachMealProposal.tenthText(t.fatG))")
            for line in meal.lines {
                out.append("  - \(line.name) (Ciqual \(line.ciqualCode.map(String.init) ?? "?")) "
                           + "\(CoachMealProposal.tenthText(line.grams)) g")
            }
        }
        let t = totals
        out.append("Day total: \(t.kcal) kcal, P \(CoachMealProposal.tenthText(t.proteinG)), "
                   + "C \(CoachMealProposal.tenthText(t.carbsG)), F \(CoachMealProposal.tenthText(t.fatG))")
        return out.joined(separator: "\n")
    }
}
