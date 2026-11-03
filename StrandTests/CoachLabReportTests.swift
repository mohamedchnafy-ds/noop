import XCTest
@testable import Strand
import StrandImport
import WhoopStore

/// A lab report read by the Coach (personal fork, chantier 8): how `record_lab_values` is read and bounded,
/// how a reading already in the Lab Book is flagged, and what "Add to Lab Book" writes. Pure: no store, no
/// network.
final class CoachLabReportTests: XCTestCase {

    private func input(_ json: String) -> [String: Any] { CoachTools.input(fromJSON: json) }

    private let report = """
    {"date": "2026-10-28", "values": [
      {"name": "Ferritine", "marker_key": "ferritin", "value": 42, "unit": "µg/L", "reference": "30 - 400"},
      {"name": "25-OH Vitamine D", "marker_key": "vitamin_d", "value": 61.5, "unit": "nmol/L"},
      {"name": "Antigène HBs", "value_text": "négatif", "unit": ""},
      {"name": "Ferritine (contrôle)", "marker_key": "ferritin", "value": 44, "unit": "µg/L"},
      {"name": "Commentaire", "unit": ""},
      {"name": "Plaquettes", "marker_key": "not_a_key", "value": 250, "unit": "G/L"}
    ], "nutrition_markers": ["ldl", "ferritin", "unknown", "folate", "iron"]}
    """

    private func existingRow(_ key: String, day: String, value: Double, source: String) -> LabMarkerRow {
        LabMarkerRow(id: "x", deviceId: "d", markerKey: key, category: "blood_panel", day: day,
                     takenAt: LabBookFormat.noonEpoch(day), value: value, valueText: nil, unit: "µg/L",
                     source: source, note: nil, referenceText: nil)
    }

    func testValuesAreKeptAsPrinted() throws {
        let parsed = CoachLabReport.fromToolInput(input(report), existing: [])
        let report = try XCTUnwrap(parsed.report)
        XCTAssertNil(parsed.problem)
        XCTAssertEqual(report.day, "2026-10-28")
        // The second ferritin and the line without a value are dropped.
        XCTAssertEqual(report.lines.map(\.markerKey),
                       ["ferritin", "vitamin_d", LabMarkerCsvImport.customKey("Antigène HBs"),
                        LabMarkerCsvImport.customKey("Plaquettes")])
        XCTAssertEqual(report.lines[0].unit, "µg/L")
        XCTAssertEqual(report.lines[0].referenceText, "30 - 400")
        XCTAssertEqual(report.lines[0].valueLine, "42 µg/L")
        XCTAssertEqual(report.lines[1].valueLine, "61.5 nmol/L")
        XCTAssertNil(report.lines[1].referenceText)
        XCTAssertNil(report.lines[2].value)
        XCTAssertEqual(report.lines[2].valueText, "négatif")
        XCTAssertEqual(report.lines[2].valueLine, "négatif")
        XCTAssertEqual(report.lines[2].category, .other)
        XCTAssertEqual(report.lines[0].category, .bloodPanel)
        XCTAssertTrue(report.lines.allSatisfy(\.include))
    }

    func testNutritionSuggestionsAreCatalogKeysNotAlreadyShown() throws {
        let report = try XCTUnwrap(CoachLabReport.fromToolInput(input(report), existing: []).report)
        XCTAssertEqual(report.nutritionSuggestions, ["ldl", "folate"])
    }

    func testAReadingAlreadyThereThatDayIsFlaggedAndUnticked() throws {
        let existing = [existingRow("ferritin", day: "2026-10-28", value: 40, source: "manual"),
                        existingRow("vitamin_d", day: "2026-10-27", value: 60, source: "manual")]
        let report = try XCTUnwrap(CoachLabReport.fromToolInput(input(report), existing: existing,
                                                                existingSource: { "<\($0)>" }).report)
        XCTAssertEqual(report.lines[0].existing, "40 µg/L, <manual>")
        XCTAssertFalse(report.lines[0].include)
        // Another day is not a duplicate.
        XCTAssertNil(report.lines[1].existing)
        XCTAssertTrue(report.lines[1].include)
    }

    func testABadDateOrNoValueIsAProblem() {
        XCTAssertNotNil(CoachLabReport.fromToolInput(input(#"{"date": "28/10/2026", "values": [{"name": "A", "value": 1, "unit": ""}]}"#),
                                                     existing: []).problem)
        XCTAssertNotNil(CoachLabReport.fromToolInput(input(#"{"date": "2026-10-28", "values": []}"#), existing: []).problem)
        let empty = CoachLabReport.fromToolInput(input(#"{"date": "2026-10-28", "values": [{"name": "A", "unit": ""}]}"#),
                                                 existing: [])
        XCTAssertNil(empty.report)
        XCTAssertNotNil(empty.problem)
    }

    func testRowsAreTheTickedLinesAtNoonUnderTheirOwnSource() throws {
        var report = try XCTUnwrap(CoachLabReport.fromToolInput(input(report), existing: []).report)
        report.lines[3].include = false
        let rows = report.labRows(deviceId: "strap")
        XCTAssertEqual(rows.count, 3)
        XCTAssertTrue(rows.allSatisfy { $0.source == "lab-pdf" && $0.deviceId == "strap" && $0.day == "2026-10-28" })
        XCTAssertTrue(rows.allSatisfy { $0.takenAt == LabBookFormat.noonEpoch("2026-10-28") })
        XCTAssertEqual(rows[0].category, LabMarkerCategory.bloodPanel.rawValue)
        XCTAssertEqual(rows[0].value, 42)
        XCTAssertEqual(rows[0].referenceText, "30 - 400")
        // The printed name is kept as the note when it is not the catalog's own name.
        XCTAssertEqual(rows[0].note, "Ferritine")
        XCTAssertEqual(rows[2].valueText, "négatif")
        XCTAssertNil(rows[2].value)
        XCTAssertEqual(Set(rows.map(\.id)).count, 3)
    }

    func testToolDefinitionAsksForVerbatimValues() throws {
        let definition = CoachLabReport.definition
        XCTAssertEqual(definition["name"] as? String, "record_lab_values")
        let schema = try XCTUnwrap(definition["input_schema"] as? [String: Any])
        XCTAssertEqual(schema["required"] as? [String], ["date", "values"])
        let prompt = CoachLabReport.systemPrompt(languageName: "French")
        XCTAssertTrue(prompt.contains("ferritin (Ferritin)"))
        XCTAssertTrue(prompt.contains("Never give a diagnosis"))
    }

    func testNutritionMarkersKeepTheDefaultsFirst() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "CoachLabReportTests"))
        defaults.removePersistentDomain(forName: "CoachLabReportTests")
        XCTAssertEqual(NutritionLabMarkers.storedKeys(defaults), ["vitamin_d", "ferritin", "vitamin_b12", "hba1c"])
        NutritionLabMarkers.addKeys(["ldl", "ferritin", "ldl", "folate"], defaults)
        XCTAssertEqual(NutritionLabMarkers.storedKeys(defaults),
                       ["vitamin_d", "ferritin", "vitamin_b12", "hba1c", "ldl", "folate"])
        defaults.removePersistentDomain(forName: "CoachLabReportTests")
    }

    @MainActor
    func testSizeAndSourceNames() {
        XCTAssertNotNil(AICoachEngine.labReportSizeProblem(Data(count: CoachLabReport.maxBytes + 1)))
        XCTAssertNil(AICoachEngine.labReportSizeProblem(Data(count: 1024)))
        XCTAssertEqual(AICoachEngine.labSourceName("lab-csv"), "CSV")
        XCTAssertEqual(AICoachEngine.labSourceName("whoop-biomarkers"), "WHOOP")
    }
}
