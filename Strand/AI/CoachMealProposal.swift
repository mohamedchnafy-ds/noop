import Foundation
import WhoopStore

/// A meal the Coach proposes as a card (personal fork, Nutrition 4c): what `log_meal` sends, read and
/// bounded here, then shown with "Add to journal" and "Edit". Nothing is stored until one of them is
/// tapped; the proposal travels with the reply (`CoachReplyMeta.meal`), like the session card.
///
/// The model names foods by their Ciqual code and gives a quantity in grams; their values per 100 g are
/// copied from the embedded table (`CiqualTable`) when the card is made, and every figure on the card is
/// computed by the app from them (`MealJournal.measuredMealLine`), never written by the model.
///
/// One exception, the product card (Nutrition 4d, `read_label`): a packaged product's values for 100 g
/// are copied by the model from a photo of its nutrition label, shown for the wearer to check, and kept
/// with the product's barcode so the next scan finds them offline (`BarcodeCatalog`). The portion's
/// values are still computed by the app.
struct CoachMealProposal: Codable, Equatable {

    struct Line: Codable, Equatable {
        /// The name the card shows ("Riz blanc").
        var name: String
        /// The Ciqual food; nil for a product read from its label.
        var ciqualCode: Int?
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
    /// A product read from its label: its barcode, when the question carried one.
    var barcode: String? = nil
    /// Fork chantier 9: the moment of the day a menu's meal goes to, when the Coach named one; nil files
    /// it by its time (`MealJournal.mealSlotForTime`).
    var slot: MealSlot? = nil

    static let logToolName = "log_meal"
    static let searchToolName = "search_foods"
    static let labelToolName = "read_label"
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

    // MARK: A product's label (Nutrition 4d)

    /// Most kcal 100 g of anything can hold (pure fat is 900).
    static let labelKcalRange = 0.0...900.0
    /// A label whose protein, carbs and fat add up to more than this many grams per 100 g is misread.
    static let labelMacroCeiling = 102.0
    static let kilojoulesPerKcal = 4.184

    /// `read_label`: the product card. Sent with every tool question; nothing is saved by the call.
    static var labelDefinition: [String: Any] {
        func number(_ description: String) -> [String: Any] {
            ["type": "number", "minimum": 0, "description": description]
        }
        return [
            "name": labelToolName,
            "description": "Only for a photo of a packaged product's nutrition label: show the product as a card "
                + "with “Add to journal” and “Edit”. Copy the values for 100 g exactly as printed; leave out a value "
                + "that is not printed or not readable, never guess it. The app computes the portion's values.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "name": ["type": "string", "description": "The product's name as on the pack, short."],
                    "barcode": ["type": "string", "description": "The barcode given with the question, digits only."],
                    "kcal": number("Energy per 100 g in kcal, as printed."),
                    "kj": number("Energy per 100 g in kJ, only when kcal is not printed."),
                    "protein_g": number("Protein per 100 g."),
                    "carbs_g": number("Carbohydrate per 100 g (not the sugars line)."),
                    "fat_g": number("Fat per 100 g (not the saturates line)."),
                    "grams": ["type": "number", "minimum": gramRange.lowerBound, "maximum": gramRange.upperBound,
                              "description": "The portion eaten: one unit's net weight if the user ate it whole, "
                                + "else what they said, else 100."],
                    "time": ["type": "string", "description": "HH:MM, when it was eaten; leave out for now."],
                    "date": ["type": "string", "description": "YYYY-MM-DD; leave out for today."],
                ] as [String: Any],
                "required": ["name", "protein_g", "carbs_g", "fat_g"],
            ] as [String: Any],
        ]
    }

    /// The product card in a `read_label` input, or the reason it cannot be made. The barcode of the
    /// question wins over the model's; the energy is the printed kcal, else the printed kJ ÷ 4.184, else
    /// computed from the macros (4 / 4 / 9).
    static func fromLabelInput(_ input: [String: Any], questionBarcode: String?, now: Date,
                               calendar: Calendar = .current) -> (proposal: CoachMealProposal?, problem: String?) {
        guard let protein = numberValue(input["protein_g"]), let carbs = numberValue(input["carbs_g"]),
              let fat = numberValue(input["fat_g"]), [protein, carbs, fat].allSatisfy({ $0.isFinite && $0 >= 0 }) else {
            return (nil, "Give protein_g, carbs_g and fat_g per 100 g as printed on the label.")
        }
        guard protein + carbs + fat <= labelMacroCeiling else {
            return (nil, "Protein, carbs and fat add up to more than 100 g per 100 g: read the label again, "
                    + "per 100 g (not per portion).")
        }
        var kcal: Double
        if let printed = numberValue(input["kcal"]), printed.isFinite, printed > 0 {
            kcal = printed
        } else if let kj = numberValue(input["kj"]), kj.isFinite, kj > 0 {
            kcal = kj / kilojoulesPerKcal
        } else {
            kcal = Double(MealMath.kcal(proteinG: protein, carbsG: carbs, fatG: fat))
        }
        guard labelKcalRange.contains(kcal) else {
            return (nil, "More than 900 kcal per 100 g is not possible: read the energy line again (kcal, per 100 g).")
        }
        kcal = MealMath.tenth(kcal)
        let per100 = MealPer100(kcal: kcal, proteinG: MealMath.tenth(protein), carbsG: MealMath.tenth(carbs),
                                fatG: MealMath.tenth(fat))
        let grams = numberValue(input["grams"]).flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? 100
        let name = String((CoachTools.text(input, "name") ?? String(localized: "Product")).prefix(60))
        let barcode = questionBarcode ?? CoachTools.text(input, "barcode").flatMap(BarcodeCatalog.normalizedBarcode)
        let eatenAt = mealTime(time: CoachTools.text(input, "time"), date: CoachTools.text(input, "date"),
                               now: now, calendar: calendar)
        let line = Line(name: name, ciqualCode: nil,
                        grams: MealMath.tenth(min(max(grams, gramRange.lowerBound), gramRange.upperBound)),
                        estimated: false, per100: per100)
        return (CoachMealProposal(name: name, eatenAt: Int(eatenAt.timeIntervalSince1970), origin: .barcode,
                                  lines: [line], mealId: nil, barcode: barcode), nil)
    }

    /// What the model is told once the product card is shown.
    static let labelShownResult = "Shown to the user as a product card with “Add to journal” and “Edit”, the values "
        + "for 100 g as you read them and the portion computed by the app. Nothing is saved until they tap. Add "
        + "nothing after the card."

    /// Values for 100 g as the model reads them: "63 kcal, P 11, C 4, F 0.2".
    static func per100Text(_ p: MealPer100) -> String {
        "\(tenthText(p.kcal)) kcal, P \(tenthText(p.proteinG)), C \(tenthText(p.carbsG)), F \(tenthText(p.fatG))"
    }

    // MARK: Values

    /// The journal lines of the card, each computed from its food's values for 100 g.
    var itemRows: [MealItemRow] {
        lines.map { line in
            MealJournal.measuredMealLine(name: line.name, grams: line.grams, estimated: line.estimated,
                                         per100: line.per100, foodRef: lineRef(line))
        }
    }

    /// A line's food: "ciqual:<code>", or "ean:<barcode>" for a product read from its label.
    private func lineRef(_ line: Line) -> String? {
        if let code = line.ciqualCode { return "ciqual:\(code)" }
        return barcode.map(BarcodeCatalog.productRef)
    }

    /// True for a product read from its nutrition label (`read_label`).
    var isLabelProduct: Bool { lines.contains { $0.ciqualCode == nil } }

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
            let source = line.ciqualCode.map { "Ciqual \($0)" }
                ?? "from the label, per 100 g: \(Self.per100Text(line.per100))" + (barcode.map { ", barcode \($0)" } ?? "")
            out.append("- \(line.name) (\(source)) \(line.estimated ? "≈ " : "")\(Self.tenthText(line.grams)) g: "
                       + "\(n.kcal) kcal, P \(Self.tenthText(n.proteinG)), C \(Self.tenthText(n.carbsG)), F \(Self.tenthText(n.fatG))")
        }
        let t = totals
        out.append("Total: \(t.kcal) kcal, P \(Self.tenthText(t.proteinG)), C \(Self.tenthText(t.carbsG)), F \(Self.tenthText(t.fatG))")
        return out.joined(separator: "\n")
    }
}
