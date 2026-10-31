import XCTest
@testable import WhoopStore

/// Supersets (personal fork): the label rule every surface shares, and the additive column that
/// stores it.
final class LiftSupersetTests: XCTestCase {

    // MARK: - Labels

    func testLabelsAreTrimmedUpperCasedAndBlankIsNone() {
        XCTAssertEqual(LiftSuperset.normalizedLabel(" a "), "A")
        XCTAssertNil(LiftSuperset.normalizedLabel("   "))
        XCTAssertNil(LiftSuperset.normalizedLabel(nil))
        XCTAssertEqual(LiftSuperset.normalizedLabel("push"), "PUSH")
    }

    func testOneLetterAndDigitsMeanThatLettersSuperset() {
        XCTAssertEqual(LiftSuperset.normalizedLabel("A1"), "A")
        XCTAssertEqual(LiftSuperset.normalizedLabel("b12"), "B")
        XCTAssertEqual(LiftSuperset.normalizedLabel("SS1"), "SS1", "only a SINGLE letter drops its digits")
        XCTAssertEqual(LiftSuperset.normalizedLabel("2"), "2")
    }

    func testALabelIsCapped() {
        XCTAssertEqual(LiftSuperset.normalizedLabel(String(repeating: "x", count: 50))?.count,
                       LiftSuperset.maxLabelLength)
    }

    // MARK: - Groups

    func testOnlyConsecutiveRunsOfTwoOrMoreAreSupersets() {
        XCTAssertEqual(LiftSuperset.groups(["A", "A", nil, "B", "B", "B"]), [0..<2, 3..<6])
        XCTAssertEqual(LiftSuperset.groups(["A", nil, "A"]), [], "split by another line: not a superset")
        XCTAssertEqual(LiftSuperset.groups(["A"]), [], "one line alone is not a superset")
        XCTAssertEqual(LiftSuperset.groups(["A1", "a2"]), [0..<2])
        XCTAssertEqual(LiftSuperset.groups([]), [])
    }

    func testBlocksCoverEveryLineOnce() {
        XCTAssertEqual(LiftSuperset.blocks([nil, "A", "A", nil]), [0..<1, 1..<3, 3..<4])
        XCTAssertEqual(LiftSuperset.blocks(["A", nil, "A"]), [0..<1, 1..<2, 2..<3])
    }

    func testTagsLetterSupersetsInOrderWhateverTheirSpelling() {
        let labels: [String?] = ["X", "X", nil, "1", "1"]
        XCTAssertEqual(LiftSuperset.tag(of: 0, in: labels), "A1")
        XCTAssertEqual(LiftSuperset.tag(of: 1, in: labels), "A2")
        XCTAssertNil(LiftSuperset.tag(of: 2, in: labels))
        XCTAssertEqual(LiftSuperset.tag(of: 4, in: labels), "B2")
        XCTAssertEqual(LiftSuperset.groupLetter(of: 3, in: labels), "B")
    }

    func testRelabelingIsCanonicalAndClearsLoneLines() {
        XCTAssertEqual(LiftSuperset.relabeled(["Q", "Q", "Z", nil, "C", "C"]),
                       ["A", "A", nil, nil, "B", "B"])
    }

    func testLettersGoPastZ() {
        XCTAssertEqual(LiftSuperset.letter(0), "A")
        XCTAssertEqual(LiftSuperset.letter(25), "Z")
        XCTAssertEqual(LiftSuperset.letter(26), "AA")
        XCTAssertEqual(LiftSuperset.letter(27), "AB")
    }

    // MARK: - Storage

    func testTheMigrationAddsANullableColumn() async throws {
        let store = try await WhoopStore.inMemory()
        let columns = try await store.columnNamesForTest(table: "liftProgramItem")
        XCTAssertTrue(columns.contains("supersetGroup"))
    }

    func testTheLabelRoundTripsAndALineWithoutOneReadsNil() async throws {
        let store = try await WhoopStore.inMemory()
        func item(_ id: String, _ ord: Int, _ group: String?) -> LiftProgramItemRow {
            LiftProgramItemRow(id: id, deviceId: "dev", programId: "p1", ord: ord, exercise: "E\(ord)",
                               targetSets: 3, targetRepsLow: 10, targetRepsHigh: nil, targetRpe: nil,
                               targetWeightKg: nil, restSec: 90, note: nil, supersetGroup: group)
        }
        _ = try await store.replaceLiftProgramItems(programId: "p1", items: [
            item("i1", 0, "a"), item("i2", 1, "A2"), item("i3", 2, nil),
        ])
        let back = try await store.liftProgramItems(programId: "p1")
        XCTAssertEqual(back.map(\.supersetGroup), ["A", "A", nil])
    }

    func testARowBuiltWithoutTheNewArgumentIsNotInASuperset() {
        let row = LiftProgramItemRow(id: "i", deviceId: "d", programId: "p", ord: 0, exercise: "Squat",
                                     targetSets: nil, targetRepsLow: nil, targetRepsHigh: nil,
                                     targetRpe: nil, targetWeightKg: nil, restSec: nil, note: nil)
        XCTAssertNil(row.supersetGroup)
    }
}
