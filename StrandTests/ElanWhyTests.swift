import XCTest
@testable import Strand

/// Personal fork, chantier 10 (Élan), PR A: « Mon pourquoi » (`ElanWhy`) — trimmed, cut, kept under its
/// `.noopbak` key, and handed to the Coach only with the switch on.
final class ElanWhyTests: XCTestCase {

    private func defaults() -> UserDefaults {
        let name = "ElanWhyTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    func testTheTextIsTrimmedAndAnEmptyOneRemoved() {
        let d = defaults()
        XCTAssertNil(ElanWhy.text(d))
        ElanWhy.setText("  Pour tenir la distance avec mes enfants.\n", d)
        XCTAssertEqual(ElanWhy.text(d), "Pour tenir la distance avec mes enfants.")
        XCTAssertEqual(d.string(forKey: "elan.why"), "Pour tenir la distance avec mes enfants.",
                       "stored under the backup's canonical key")
        ElanWhy.setText("   \n", d)
        XCTAssertNil(ElanWhy.text(d))
        XCTAssertNil(d.object(forKey: ElanWhy.textKey))
    }

    func testALongTextIsCut() {
        let long = String(repeating: "a", count: ElanWhy.maxLength + 50)
        XCTAssertEqual(ElanWhy.normalized(long)?.count, ElanWhy.maxLength)
    }

    func testTheCoachReadsItOnlyWithTheSwitchOn() {
        let d = defaults()
        XCTAssertFalse(ElanWhy.coachCanRead(d), "off by default")
        ElanWhy.setCoachCanRead(true, d)
        XCTAssertTrue(ElanWhy.coachCanRead(d))

        XCTAssertNil(ElanWhy.coachBlock(text: "Pour moi.", allowed: false))
        XCTAssertNil(ElanWhy.coachBlock(text: "  ", allowed: true))
        let block = try! XCTUnwrap(ElanWhy.coachBlock(text: " Pour moi. ", allowed: true))
        XCTAssertTrue(block.hasPrefix("WHY ("))
        XCTAssertTrue(block.hasSuffix("\nPour moi."))
    }
}
