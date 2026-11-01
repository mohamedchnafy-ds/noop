import Foundation
import WhoopStore

/// A meal the Coach proposes as a card (personal fork, Nutrition 4c): what `log_meal` sends, read and
/// bounded here, then shown with "Add to journal" and "Edit". Nothing is stored until one of them is
/// tapped; the proposal travels with the reply (`CoachReplyMeta.meal`), like the session card.
///
/// The model names foods by their Ciqual code and gives a quantity in grams; their values per 100 g are
/// copied from the embedded table (`CiqualTable`) when the card is made, and every figure on the card is
/// computed by the app from them (`MealJournal.measuredMealLine`), never written by the model.
struct CoachMealProposal: Codable, Equatable {

    struct Line: Codable, Equatable {
        /// The name the card shows ("Riz blanc").
        var name: String
        var ciqualCode: Int
        var grams: Double
        /// True for a quantity estimated from a photo ("≈").
        var estimated: Bool
        /// The food's values for 100 g, from the table, kept with the card.
        var per100: MealPer100
    }

    var name: String
    /// Unix seconds.
    var eatenAt: Int
    var origin: MealOrigin
    var lines: [Line]
    /// The journal meal it was saved as, once "Add to journal" (or Edit, then Save) was tapped.
    var mealId: String?

    static let logToolName = "log_meal"
    static let searchToolName = "search_foods"
    static let maxLines = 15
    static let gramRange = 1.0...2000.0
    static let searchLimitRange = 1...10
    /// How far back a meal can be dated.
    static let maxDaysBack = 7

    // MARK: The tools

    /// `search_foods`: the Ciqual table, read on the device. Sent with every tool question: it reads
    /// nothing of the user's.
    static var searchDefinition: [String: Any] {
        [
            "name": searchToolName,
            "description": "Search the Ciqual food composition table (ANSES, on the device) by food name, in French "
                + "or English. Returns Ciqual codes with each food's values for 100 g. Use it to find every food "
                + "of a meal before calling log_meal; search one food at a time with a few plain words "
                + "(\"riz blanc cuit\", \"chicken breast\").",
            "input_schema": [
                "type": "object",
                "properties": [
                    "query": ["type": "string"],
                    "limit": ["type": "integer", "minimum": searchLimitRange.lowerBound,
                              "maximum": searchLimitRange.upperBound],
                ] as [String: Any],
                "required": ["query"],
            ] as [String: Any],
        ]
    }

    /// `log_meal`: the card. Sent with every tool question; nothing is saved by the call.
    static var logDefinition: [String: Any] {
        let item: [String: Any] = [
            "type": "object",
            "properties": [
                "ciqual_code": ["type": "integer", "description": "A code returned by search_foods."],
                "name": ["type": "string", "description": "A short name for the card, in the user's language."],
                "grams": ["type": "number", "minimum": gramRange.lowerBound, "maximum": gramRange.upperBound],
                "estimated": ["type": "boolean",
                              "description": "True when the quantity is estimated from a photo."],
            ] as [String: Any],
            "required": ["ciqual_code", "grams"],
        ]
        return [
            "name": logToolName,
            "description": "Show the user a meal as a card with “Add to journal” and “Edit”. Nothing is saved until "
                + "they tap. Give every food by its Ciqual code and its quantity in grams: the app computes the "
                + "calories and macros from the Ciqual table, so never state them yourself.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "name": ["type": "string", "description": "The meal's name (\"Poulet, riz, légumes\")."],
                    "time": ["type": "string", "description": "HH:MM, when it was eaten; leave out for now."],
                    "date": ["type": "string", "description": "YYYY-MM-DD; leave out for today."],
                    "items": ["type": "array", "items": item, "minItems": 1, "maxItems": maxLines],
                ] as [String: Any],
                "required": ["name", "items"],
            ] as [String: Any],
        ]
    }

    /// What the model is told once the card is shown; the codes it gave that the table does not have are
    /// named so it can search again.
    static func shownResult(unknownCodes: [Int]) -> String {
        var text = "Shown to the user as a card with “Add to journal” and “Edit”. Nothing is saved until they "
            + "tap. The app computed the values from Ciqual: do not repeat them and add nothing after the card."
        if !unknownCodes.isEmpty {
            text += " Left out, not in the table: " + unknownCodes.map(String.init).joined(separator: ", ") + "."
        }
        return text
    }

    /// The answer to `search_foods`.
    static func searchResult(query: String, foods: [CiqualFood]) -> String {
        guard !foods.isEmpty else {
            return "No Ciqual food matches “\(query)”. Try fewer or more general words, in French or English."
        }
        var lines = ["Ciqual foods for “\(query)” (values for 100 g):"]
        for food in foods {
            let p = food.per100
            lines.append("\(food.code) · \(food.nameFr) / \(food.nameEn) · \(Int(p.kcal.rounded())) kcal, "
                         + "P \(tenthText(p.proteinG)), C \(tenthText(p.carbsG)), F \(tenthText(p.fatG))")
        }
        return lines.joined(separator: "\n")
    }

    /// The proposal in a `log_meal` input, bounded, with the codes the table does not know; a nil
    /// proposal when no item is usable.
    static func fromToolInput(_ input: [String: Any], origin: MealOrigin, now: Date,
                              calendar: Calendar = .current,
                              food: (Int) -> CiqualFood?) -> (proposal: CoachMealProposal?, unknownCodes: [Int]) {
        let rawItems = (input["items"] as? [[String: Any]]) ?? []
        var lines: [Line] = []
        var unknown: [Int] = []
        for raw in rawItems.prefix(maxLines) {
            guard let code = codeValue(raw["ciqual_code"]) else { continue }
            guard let found = food(code) else {
                unknown.append(code)
                continue
            }
            guard let grams = numberValue(raw["grams"]), grams.isFinite, grams > 0 else { continue }
            let name = CoachTools.text(raw, "name") ?? found.nameFr
            lines.append(Line(name: String(name.prefix(60)), ciqualCode: code,
                              grams: MealMath.tenth(min(max(grams, gramRange.lowerBound), gramRange.upperBound)),
                              estimated: (raw["estimated"] as? Bool) ?? false, per100: found.per100))
        }
        guard !lines.isEmpty else { return (nil, unknown) }
        let name = CoachTools.text(input, "name") ?? lines.map(\.name).joined(separator: ", ")
        let eatenAt = mealTime(time: CoachTools.text(input, "time"), date: CoachTools.text(input, "date"),
                               now: now, calendar: calendar)
        return (CoachMealProposal(name: String(name.prefix(60)), eatenAt: Int(eatenAt.timeIntervalSince1970),
                                  origin: origin, lines: lines, mealId: nil), unknown)
    }

    /// When the meal was eaten: `date` (else today) at `time` (else now's time), never after now and never
    /// more than `maxDaysBack` days back.
    static func mealTime(time: String?, date: String?, now: Date, calendar: Calendar = .current) -> Date {
        var day = calendar.startOfDay(for: now)
        if let date {
            let parts = date.split(separator: "-").compactMap { Int($0) }
            if parts.count == 3,
               let parsed = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) {
                day = calendar.startOfDay(for: parsed)
            }
        }
        var hour = calendar.component(.hour, from: now)
        var minute = calendar.component(.minute, from: now)
        if let time {
            let parts = time.split(separator: ":").compactMap { Int($0) }
            if parts.count >= 2, (0...23).contains(parts[0]), (0...59).contains(parts[1]) {
                hour = parts[0]
                minute = parts[1]
            }
        }
        let when = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? now
        let earliest = calendar.date(byAdding: .day, value: -maxDaysBack, to: calendar.startOfDay(for: now)) ?? now
        return min(max(when, earliest), now)
    }

    private static func codeValue(_ raw: Any?) -> Int? {
        if let n = raw as? NSNumber { return n.intValue }
        if let s = raw as? String { return Int(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    private static func numberValue(_ raw: Any?) -> Double? {
        if let n = raw as? NSNumber { return n.doubleValue }
        if let s = raw as? String { return Double(s.replacingOccurrences(of: ",", with: ".")) }
        return nil
    }

    /// A value to one decimal, without a trailing ".0", as the model reads it.
    static func tenthText(_ value: Double) -> String {
        let v = MealMath.tenth(value)
        return v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }

    // MARK: Values

    /// The journal lines of the card, each computed from its food's values for 100 g.
    var itemRows: [MealItemRow] {
        lines.map { line in
            MealJournal.measuredMealLine(name: line.name, grams: line.grams, estimated: line.estimated,
                                         per100: line.per100, foodRef: "ciqual:\(line.ciqualCode)")
        }
    }

    /// The meal's energy and macros: the sum of its lines.
    var totals: MealNutrients { MealMath.totals(itemRows.map(\.nutrients)) }

    /// True when a quantity was estimated from a photo.
    var hasEstimate: Bool { lines.contains(where: \.estimated) }

    /// The card as a journal entry not saved yet (for Edit before Add).
    func draftEntry(now: Date = Date()) -> MealEntry {
        let stamp = Int(now.timeIntervalSince1970)
        let meal = MealRow(id: UUID().uuidString,
                           day: MealJournal.mealDayKey(Date(timeIntervalSince1970: TimeInterval(eatenAt))),
                           eatenAt: eatenAt, name: name, origin: origin, createdAt: stamp, updatedAt: stamp)
        let items = itemRows.enumerated().map { index, row -> MealItemRow in
            var item = row
            item.mealId = meal.id
            item.ord = index
            return item
        }
        return MealEntry(meal: meal, items: items)
    }

    // MARK: Text

    /// The card as text, for Copy, Share and the Journal: one line per food, then the total.
    func cardText(clock: String, line: (MealItemRow) -> String, total: String) -> String {
        var out = ["**\(name)** · \(clock)"]
        out += itemRows.map(line)
        out.append(total)
        return out.joined(separator: "\n")
    }

    /// The card as the model reads it back in a later turn, so "add 50 g of rice" refers to it.
    func wireText(timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let when = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(eatenAt)))
        var out = ["[Meal shown to the user as a card" + (mealId == nil ? ", not saved yet" : ", added to their journal")
                   + "] \(name) · \(when)"]
        for (row, line) in zip(itemRows, lines) {
            let n = row.nutrients
            out.append("- \(line.name) (Ciqual \(line.ciqualCode)) \(line.estimated ? "≈ " : "")\(Self.tenthText(line.grams)) g: "
                       + "\(n.kcal) kcal, P \(Self.tenthText(n.proteinG)), C \(Self.tenthText(n.carbsG)), F \(Self.tenthText(n.fatG))")
        }
        let t = totals
        out.append("Total: \(t.kcal) kcal, P \(Self.tenthText(t.proteinG)), C \(Self.tenthText(t.carbsG)), F \(Self.tenthText(t.fatG))")
        return out.joined(separator: "\n")
    }
}
