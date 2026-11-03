import XCTest
@testable import Strand
import StrandImport
import WhoopStore

/// The Lab Book markers Nutrition follows (personal fork, chantier 8): the latest reading of each, printed
/// the way the Lab Book prints it, in the order followed. Pure: no store.
final class NutritionLabLinesTests: XCTestCase {

    private func row(_ key: String, _ day: String, value: Double?, text: String? = nil, unit: String) -> LabMarkerRow {
        LabMarkerRow(id: key + day, deviceId: "d", markerKey: key, category: "blood_panel", day: day,
                     takenAt: LabBookFormat.noonEpoch(day), value: value, valueText: text, unit: unit,
                     source: "manual", note: nil, referenceText: nil)
    }

    func testEachLineIsTheLatestReadingAsTheLabBookPrintsIt() {
        let rows = [row("ferritin", "2026-10-28", value: 42, unit: "µg/L"),
                    row("vitamin_d", "2026-10-28", value: 61.5, unit: "nmol/L"),
                    row("vitamin_d", "2026-03-12", value: 48, unit: "nmol/L"),
                    row("custom_hbs", "2026-10-28", value: nil, text: "négatif", unit: "")]
        let lines = NutritionLabLines.buildLabLines(keys: ["vitamin_d", "ferritin", "vitamin_b12", "custom_hbs"], rows: rows)
        XCTAssertEqual(lines.map(\.key), ["vitamin_d", "ferritin", "vitamin_b12", "custom_hbs"])
        // vitamin_d has 0 catalog decimals: the Lab Book's card prints "62 nmol/L" too.
        XCTAssertEqual(lines[0].reading, LabBookFormat.readingLabel(rows[1], key: "vitamin_d"))
        XCTAssertEqual(lines[0].reading, "62 nmol/L")
        XCTAssertEqual(lines[1].reading, "42 µg/L")
        XCTAssertEqual(lines[2].reading, "—")
        XCTAssertNil(lines[2].day)
        XCTAssertEqual(lines[3].reading, "négatif")
        XCTAssertEqual(lines[3].name, LabBookView.humanise("custom_hbs"))
        XCTAssertEqual(lines[0].day.map { Calendar.current.component(.day, from: $0) }, 28)
    }

    func testCatalogMarkersHaveTheirNameKey() {
        for key in MarkerCatalog.builtIn.map(\.key) {
            XCTAssertFalse(NutritionLabLines.labMarkerName(key).hasPrefix("lab: "), key)
        }
    }
}
