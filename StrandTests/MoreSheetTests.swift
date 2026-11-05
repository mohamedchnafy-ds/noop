import XCTest
@testable import Strand

/// The More sheet's list (fork chantier 9, section 7): every screen once, the values on the right of five
/// rows, the last backup's wording.
@MainActor
final class MoreSheetTests: XCTestCase {

    func testEveryScreenIsListedOnce() {
        let listed = MoreSheetSection.allCases.flatMap(\.entries) + MoreSheetEntry.advanced
        XCTAssertEqual(listed.count, MoreSheetEntry.allCases.count)
        XCTAssertEqual(Set(listed), Set(MoreSheetEntry.allCases))
        XCTAssertEqual(MoreSheetEntry.advanced.count, 15)
        XCTAssertEqual(MoreSheetSection.analysis.entries, [.trends])
        XCTAssertTrue(MoreSheetEntry.advanced.allSatisfy { $0.isAdvanced && $0.formerGroup != nil })
        XCTAssertTrue(MoreSheetSection.allCases.flatMap(\.entries).allSatisfy { !$0.isAdvanced && $0.formerGroup == nil })
    }

    func testValuesSitOnTheirRowsOnly() {
        let values = MoreSheetValues(vitality: nil, stress: "Calm", labDay: "12 Mar", alarm: "06:04", backup: "yesterday")
        XCTAssertNil(values.value(for: .health))
        XCTAssertEqual(values.value(for: .stress), "Calm")
        XCTAssertEqual(values.value(for: .labBook), "12 Mar")
        XCTAssertEqual(values.value(for: .alarms), "06:04")
        XCTAssertEqual(values.value(for: .backupSync), "yesterday")
        XCTAssertNil(values.value(for: .trends))
        XCTAssertNil(values.value(for: .settings))
        XCTAssertNotNil(MoreSheetValues(vitality: 44).value(for: .health))
    }

    func testNoBackupNamesNothing() {
        XCTAssertNil(MoreSheetReader.moreBackupText(lastMs: 0, now: Date()))
        let now = Date(timeIntervalSince1970: 1_793_800_000)
        XCTAssertNotNil(MoreSheetReader.moreBackupText(lastMs: Int(now.timeIntervalSince1970 * 1000) - 86_400_000,
                                                       now: now))
    }

    func testTheAlarmRowIsGatedLikeTheAlarmScreen() {
        let now = Date(timeIntervalSince1970: 1_793_800_000)
        XCTAssertNil(SmartAlarmView.nextArmedStrapAlarm(enabled: false, minutes: 364, weekdays: [], overrides: [:],
                                                        isWhoop5: false, from: now))
        XCTAssertEqual(SmartAlarmView.nextArmedStrapAlarm(enabled: true, minutes: 364, weekdays: [], overrides: [:],
                                                          isWhoop5: false, from: now),
                       AppModel.nextSmartAlarmDate(minutes: 364, weekdays: [], overrides: [:], from: now))
    }
}
