import XCTest

final class WidgetSnapshotTests: XCTestCase {
    func testAltStoreProvisionedGroupWinsOverBuildTimeIdentifier() {
        let configured = "group.com.noopapp.noop.staging"
        let remapped = configured + ".TEAM123456"

        XCTAssertEqual(
            WidgetSnapshot.resolveSuiteName(infoDictionary: [
                "AppGroupIdentifier": configured,
                "ALTAppGroups": [remapped]
            ]),
            remapped
        )
    }

    func testXcodeBuildFallsBackToConfiguredGroup() {
        XCTAssertEqual(
            WidgetSnapshot.resolveSuiteName(infoDictionary: [
                "AppGroupIdentifier": "group.example.noop"
            ]),
            "group.example.noop"
        )
    }

    func testUnrelatedAltStoreGroupsDoNotOverrideConfiguredGroup() {
        XCTAssertEqual(
            WidgetSnapshot.resolveSuiteName(infoDictionary: [
                "AppGroupIdentifier": "group.example.noop",
                "ALTAppGroups": [
                    "group.example.first",
                    "group.example.second"
                ]
            ]),
            "group.example.noop"
        )
    }

    func testSingleProvisionedGroupIsUsableWithoutConfiguredIdentifier() {
        XCTAssertEqual(
            WidgetSnapshot.resolveSuiteName(infoDictionary: [
                "ALTAppGroups": ["group.example.noop.TEAM123456"]
            ]),
            "group.example.noop.TEAM123456"
        )
    }

    /// SideStore's "Use Main Profile" leaves `ALTAppGroups` out of the extension (personal fork): the extension
    /// follows its containing app's list rather than the build-time identifier nobody writes to.
    func testAnExtensionWithoutItsOwnListFollowsTheContainingApp() {
        let configured = "group.com.noopapp.noop.staging"
        let remapped = configured + ".TEAM123456"
        XCTAssertEqual(
            WidgetSnapshot.resolveSuiteName(
                infoDictionary: ["AppGroupIdentifier": configured],
                hostInfoDictionary: ["AppGroupIdentifier": configured, "ALTAppGroups": [remapped]]),
            remapped
        )
    }

    func testTheGroupTheSignatureGrantsWins() {
        let configured = "group.com.noopapp.noop.staging"
        let remapped = configured + ".TEAM123456"
        XCTAssertEqual(
            WidgetSnapshot.resolveSuiteName(
                infoDictionary: ["AppGroupIdentifier": configured],
                hostInfoDictionary: ["ALTAppGroups": [remapped]],
                isGranted: { $0 == remapped }),
            remapped
        )
        XCTAssertEqual(
            WidgetSnapshot.resolveSuiteName(
                infoDictionary: ["AppGroupIdentifier": configured, "ALTAppGroups": [remapped]],
                isGranted: { $0 == configured }),
            configured,
            "a listed group the signature does not grant loses to one it does"
        )
    }

    func testTheSigningProfilesGroupsAreReadFromItsEnvelope() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict><key>Entitlements</key><dict>
        <key>com.apple.security.application-groups</key><array>
        <string>group.com.noopapp.noop.staging.TEAM123456</string></array></dict></dict></plist>
        """
        var envelope = Data([0x30, 0x80, 0x06, 0x09])
        envelope.append(Data(xml.utf8))
        envelope.append(Data([0x00, 0x00, 0xA0]))
        XCTAssertEqual(WidgetSnapshot.profileGroups(provisioningProfile: envelope),
                       ["group.com.noopapp.noop.staging.TEAM123456"])
        XCTAssertEqual(WidgetSnapshot.profileGroups(provisioningProfile: Data([0x30, 0x80])), [])

        // A signer that wrote no list at all: the profile's group is the one the signature grants.
        XCTAssertEqual(
            WidgetSnapshot.resolveSuiteName(
                infoDictionary: ["AppGroupIdentifier": "group.com.noopapp.noop.staging"],
                profileGroups: ["group.com.noopapp.noop.staging.TEAM123456"],
                isGranted: { $0.hasSuffix(".TEAM123456") }),
            "group.com.noopapp.noop.staging.TEAM123456"
        )
    }

    func testTheContainingAppIsReadOnlyFromAnExtension() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let app = root.appendingPathComponent("NOOP.app")
        let appex = app.appendingPathComponent("PlugIns/NOOPWidgets.appex")
        try FileManager.default.createDirectory(at: appex, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let info: NSDictionary = ["ALTAppGroups": ["group.example.noop.TEAM123456"]]
        XCTAssertTrue(info.write(to: app.appendingPathComponent("Info.plist"), atomically: true))

        let read = WidgetSnapshot.containingAppInfoDictionary(bundleURL: appex)
        XCTAssertEqual(read["ALTAppGroups"] as? [String], ["group.example.noop.TEAM123456"])
        XCTAssertTrue(WidgetSnapshot.containingAppInfoDictionary(bundleURL: app).isEmpty,
                      "the app itself has no containing app")
    }

    func testRuntimeUnavailableSnapshotContainsNoDemoValues() {
        let snapshot = WidgetSnapshot.unavailable

        XCTAssertNil(snapshot.recovery)
        XCTAssertNil(snapshot.bpm)
        XCTAssertNil(snapshot.batteryPct)
        XCTAssertFalse(snapshot.bonded)
    }

    private func renderedSnapshot(updated: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> WidgetSnapshot {
        WidgetSnapshot(recovery: 72, bpm: 58, batteryPct: 84, bonded: true, updated: updated,
                       effort: 38, rest: 81, hrv: 64, restingHr: 52,
                       effortDisplay: "38", effortWhoop: false)
    }

    func testRenderedContentFirstPublishAlwaysChanges() {
        XCTAssertTrue(WidgetSnapshot.renderedContentChanged(from: nil, to: renderedSnapshot()))
    }

    func testRenderedContentIgnoresTimestampOnlyChange() {
        let previous = renderedSnapshot()
        let next = renderedSnapshot(updated: previous.updated.addingTimeInterval(900))

        XCTAssertFalse(WidgetSnapshot.renderedContentChanged(from: previous, to: next))
    }

    func testRenderedContentDetectsLiveFieldChange() {
        let previous = renderedSnapshot()
        var next = previous
        next.bpm = 59

        XCTAssertTrue(WidgetSnapshot.renderedContentChanged(from: previous, to: next))
    }

    func testRenderedContentDetectsScoreFieldChange() {
        let previous = renderedSnapshot()
        var next = previous
        next.rest = 82

        XCTAssertTrue(WidgetSnapshot.renderedContentChanged(from: previous, to: next))
    }

    func testLiveUpdateReusesSnapshotWithinSameLocalDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let previous = renderedSnapshot(updated: Date(timeIntervalSince1970: 1_700_000_000))
        let oneHourLater = previous.updated.addingTimeInterval(3_600)

        XCTAssertFalse(WidgetSnapshot.liveUpdateRequiresFullBuild(
            previous: previous, now: oneHourLater, calendar: calendar))
    }

    func testLiveUpdateRequiresFullBuildAfterLocalDayRollover() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let previous = renderedSnapshot(updated: Date(timeIntervalSince1970: 1_700_000_000))
        let nextDay = previous.updated.addingTimeInterval(86_400)

        XCTAssertTrue(WidgetSnapshot.liveUpdateRequiresFullBuild(
            previous: previous, now: nextDay, calendar: calendar))
        XCTAssertTrue(WidgetSnapshot.liveUpdateRequiresFullBuild(
            previous: nil, now: nextDay, calendar: calendar))
    }
}
