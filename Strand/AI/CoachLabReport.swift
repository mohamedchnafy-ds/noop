import Foundation
import StrandImport
import WhoopStore

/// A lab report read by the Coach (personal fork, chantier 8): the PDF goes whole to Anthropic, once, under its
/// own consent (`AICoachEngine.labReportConsent`); the model copies each value through `record_lab_values`; the
/// review sheet shows them one by one and only "Add to Lab Book" writes, with the source `lab-pdf`.
///
/// PURE: the tool input is read and bounded here, against the catalog and the Lab Book rows the screen already
/// reads, so the rules are tested without a store. Values and units are kept as printed (never converted); a
/// date without a time becomes local noon of that day (`LabBookFormat.noonEpoch`); a reading already in the
/// Lab Book that day is flagged and left unticked, never merged.
struct CoachLabReport: Equatable {

    struct Line: Equatable, Identifiable {
        var id: Int
        /// The name as the report prints it.
        var printedName: String
        /// A catalog key, or the `custom_<slug>` key the manual editor would mint for that name.
        var markerKey: String
        var category: LabMarkerCategory
        var value: Double?
        var valueText: String?
        /// As printed, verbatim.
        var unit: String
        /// The report's own reference range, verbatim; nil when it prints none.
        var referenceText: String?
        /// What the Lab Book already holds for this marker on that day ("95 µg/L, Manual"), nil when nothing.
        var existing: String?
        /// Ticked on the review sheet: everything new, nothing already there.
        var include: Bool

        /// "12,5 µg/L" or the qualitative text, as the sheet shows it.
        var valueLine: String {
            let number = value.map { LiftFormat.trim($0) } ?? valueText ?? "—"
            return unit.isEmpty ? number : number + " " + unit
        }
    }

    /// `yyyy-MM-dd`, the day the sample was taken.
    var day: String
    var lines: [Line]
    /// Catalog keys the model suggests showing in Nutrition, beyond those already shown there.
    var nutritionSuggestions: [String]

    static let toolName = "record_lab_values"
    static let source = "lab-pdf"
    static let maxLines = 80
    /// The request's limit is 32 MB in all; the file is sent base64 (4/3 larger) with the instructions.
    static let maxBytes = 20 * 1024 * 1024
    /// The page limit for models with a 200k context, the smallest the Coach can be set to.
    static let maxPages = 100

    // MARK: The tool

    static var definition: [String: Any] {
        let value: [String: Any] = [
            "type": "object",
            "properties": [
                "name": ["type": "string", "description": "The test's name exactly as printed."],
                "marker_key": ["type": "string",
                               "description": "The catalog key from the list in the instructions when it is that test; leave out otherwise."],
                "value": ["type": "number", "description": "The result as a number, when it is one (decimal point)."],
                "value_text": ["type": "string", "description": "The result as printed when it is not a number (\"négatif\", \"< 0,5\")."],
                "unit": ["type": "string", "description": "The unit exactly as printed; empty when none."],
                "reference": ["type": "string", "description": "The reference range exactly as printed, when there is one."],
            ] as [String: Any],
            "required": ["name", "unit"],
        ]
        return [
            "name": toolName,
            "description": "Record the results printed in the user's lab report so the app can show them for review. "
                + "Copy every value, unit and reference range exactly as printed; never convert a unit, never "
                + "interpret a result. Nothing is saved until the user reviews each value.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "date": ["type": "string", "description": "YYYY-MM-DD, the day the sample was taken (else the report's date)."],
                    "values": ["type": "array", "items": value, "minItems": 1, "maxItems": maxLines],
                    "nutrition_markers": ["type": "array", "items": ["type": "string"],
                                          "description": "Catalog keys of results tied to diet worth showing in the Nutrition screen."],
                ] as [String: Any],
                "required": ["date", "values"],
            ] as [String: Any],
        ]
    }

    /// The instructions of the one request: the catalog the keys come from, and the rules.
    static func systemPrompt(languageName: String) -> String {
        let catalog = MarkerCatalog.builtIn.map { "\($0.key) (\($0.displayName))" }.joined(separator: ", ")
        return """
        You read one lab report (a PDF the user chose) and copy its results for their own Lab Book. Call \
        \(toolName) once with every result. Copy each value, unit and reference range exactly as printed: never \
        convert, round or interpret, and leave out anything that is not a measured result (names, addresses, \
        comments, prices). Give marker_key only when the test is one of these: \(catalog). Give the date the \
        sample was taken. In nutrition_markers, list at most two catalog keys of results tied to diet that the \
        user may want to follow in Nutrition (not vitamin_d, ferritin, vitamin_b12 or hba1c, already shown). \
        After the call, say in one short sentence in \(languageName) how many results you copied. Never give a \
        diagnosis or an opinion on a result. If the document is not a lab report, say so in one sentence in \
        \(languageName) without calling the tool.
        """
    }

    // MARK: Reading the input

    /// The report from the tool's input, each line checked against the Lab Book rows of that day. Nil with the
    /// problem when nothing usable came.
    static func fromToolInput(_ input: [String: Any], existing: [LabMarkerRow],
                              existingSource: (String) -> String = { $0 }) -> (report: CoachLabReport?, problem: String?) {
        guard let rawDay = (input["date"] as? String)?.trimmingCharacters(in: .whitespaces),
              LabBookFormat.noonEpoch(rawDay) > 0 else {
            return (nil, "Give the date as YYYY-MM-DD.")
        }
        let day = rawDay
        guard let values = input["values"] as? [[String: Any]], !values.isEmpty else {
            return (nil, "No result to record.")
        }
        var lines: [Line] = []
        var seen = Set<String>()
        for entry in values.prefix(maxLines) {
            guard let name = (entry["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty else { continue }
            let number = (entry["value"] as? NSNumber)?.doubleValue
            let text = (entry["value_text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard (number.map { $0.isFinite } ?? false) || !(text ?? "").isEmpty else { continue }
            let given = (entry["marker_key"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
            let definition = MarkerCatalog.definition(for: given)
            let key = definition?.key ?? LabMarkerCsvImport.customKey(name)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            let unit = (entry["unit"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let reference = (entry["reference"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let already = existing.filter { $0.markerKey == key && $0.day == day }
            let existingText = already.first.map { row in
                (row.value.map { LiftFormat.trim($0) } ?? row.valueText ?? "—")
                    + (row.unit.isEmpty ? "" : " " + row.unit) + ", " + existingSource(row.source)
            }
            lines.append(Line(id: lines.count, printedName: name, markerKey: key,
                              category: definition?.category ?? .bloodPanel,
                              value: number.flatMap { $0.isFinite ? $0 : nil },
                              valueText: number == nil ? text : nil, unit: unit,
                              referenceText: (reference ?? "").isEmpty ? nil : reference,
                              existing: existingText, include: existingText == nil))
        }
        guard !lines.isEmpty else { return (nil, "No usable result: give each result's name with a value.") }
        let shown = Set(NutritionLabMarkers.defaultKeys)
        let suggestions = ((input["nutrition_markers"] as? [String]) ?? [])
            .filter { MarkerCatalog.definition(for: $0) != nil && !shown.contains($0) }
        return (CoachLabReport(day: day, lines: lines, nutritionSuggestions: Array(suggestions.prefix(2))), nil)
    }

    /// The rows "Add to Lab Book" writes: the ticked lines, at local noon of the day, under `lab-pdf`.
    func labRows(deviceId: String) -> [LabMarkerRow] {
        let epoch = LabBookFormat.noonEpoch(day)
        return lines.filter(\.include).map { line in
            LabMarkerRow(id: "\(line.markerKey)-\(epoch)-\(UUID().uuidString.prefix(8))", deviceId: deviceId,
                         markerKey: line.markerKey, category: line.category.rawValue, day: day, takenAt: epoch,
                         value: line.value, valueText: line.valueText, unit: line.unit, source: Self.source,
                         note: line.printedName == displayName(line.markerKey) ? nil : line.printedName,
                         referenceText: line.referenceText)
        }
    }

    private func displayName(_ key: String) -> String? { MarkerCatalog.definition(for: key)?.displayName }
}

/// The Lab Book markers the Nutrition screen shows (personal fork, chantier 8): vitamin D, ferritin, B12 and
/// HbA1c by default (Mohamed's choice), plus any the user adds from a report the Coach read.
enum NutritionLabMarkers {
    static let defaultsKey = "nutrition.labMarkerKeys"
    static let defaultKeys = ["vitamin_d", "ferritin", "vitamin_b12", "hba1c"]

    static func storedKeys(_ defaults: UserDefaults = .standard) -> [String] {
        let extra = (defaults.stringArray(forKey: defaultsKey) ?? []).filter { !defaultKeys.contains($0) }
        return defaultKeys + extra
    }

    /// `keys` added after the ones already shown, without duplicates.
    static func addKeys(_ keys: [String], _ defaults: UserDefaults = .standard) {
        var extra = (defaults.stringArray(forKey: defaultsKey) ?? []).filter { !defaultKeys.contains($0) }
        for key in keys where !defaultKeys.contains(key) && !extra.contains(key) { extra.append(key) }
        defaults.set(extra, forKey: defaultsKey)
    }
}
