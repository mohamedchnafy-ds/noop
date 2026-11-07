import XCTest
import WhoopStore
@testable import Strand

/// Personal fork, chantier 14 step 2: the place tracking's settings and rules (`PlaceTrackingRules`).
final class PlaceTrackingTests: XCTestCase {

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func at(_ hour: Int, _ minute: Int) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: hour, minute: minute))!
    }

    func testAQuietSpanCanRunOverMidnight() {
        let night = PlaceTrackingSettings.night
        XCTAssertTrue(night.containsMinute(23 * 60))
        XCTAssertTrue(night.containsMinute(3 * 60))
        XCTAssertFalse(night.containsMinute(7 * 60), "07:00 is the end, excluded")
        XCTAssertFalse(night.containsMinute(12 * 60))
        let lunch = PlaceQuietRange(startMinute: 12 * 60, endMinute: 14 * 60)
        XCTAssertTrue(lunch.containsMinute(13 * 60))
        XCTAssertFalse(lunch.containsMinute(14 * 60))
        XCTAssertFalse(PlaceQuietRange(startMinute: 600, endMinute: 600).containsMinute(600), "an empty span")
    }

    func testQuietTimeFollowsTheNightSwitchAndTheOtherSpans() {
        let lunch = PlaceQuietRange(startMinute: 12 * 60, endMinute: 14 * 60)
        XCTAssertTrue(PlaceTrackingRules.isQuietTime(at(2, 0), night: true, ranges: [], calendar: utc))
        XCTAssertFalse(PlaceTrackingRules.isQuietTime(at(2, 0), night: false, ranges: [], calendar: utc))
        XCTAssertTrue(PlaceTrackingRules.isQuietTime(at(12, 30), night: true, ranges: [lunch], calendar: utc))
        XCTAssertFalse(PlaceTrackingRules.isQuietTime(at(15, 0), night: true, ranges: [lunch], calendar: utc))
    }

    func testBalancedKeepsOnePointPerIntervalWithALittleSlack() {
        let t0: Int64 = 1_800_000_000_000
        func keeps(_ afterMinutes: Double) -> Bool {
            PlaceTrackingRules.keepsFix(mode: .balanced, intervalMinutes: 15, distanceMeters: 100,
                                        lastTsMs: t0, lastLat: 48.85, lastLon: 2.35,
                                        tsMs: t0 + Int64(afterMinutes * 60_000), lat: 48.85, lon: 2.35)
        }
        XCTAssertFalse(keeps(10))
        XCTAssertTrue(keeps(14.2), "a fix a little early still counts, so 15 min does not drift to 16")
        XCTAssertTrue(keeps(20))
        XCTAssertTrue(PlaceTrackingRules.keepsFix(mode: .balanced, intervalMinutes: 15, distanceMeters: 100,
                                                  lastTsMs: nil, lastLat: nil, lastLon: nil,
                                                  tsMs: t0, lat: 48.85, lon: 2.35), "the first fix")
        XCTAssertFalse(PlaceTrackingRules.keepsFix(mode: .eco, intervalMinutes: 15, distanceMeters: 100,
                                                   lastTsMs: t0, lastLat: 48.85, lastLon: 2.35,
                                                   tsMs: t0, lat: 48.9, lon: 2.4), "never twice the same instant")
    }

    func testPreciseKeepsOnePointPerDistance() {
        let t0: Int64 = 1_800_000_000_000
        func keeps(lat: Double) -> Bool {
            PlaceTrackingRules.keepsFix(mode: .precise, intervalMinutes: 15, distanceMeters: 100,
                                        lastTsMs: t0, lastLat: 48.8500, lastLon: 2.35,
                                        tsMs: t0 + 60_000, lat: lat, lon: 2.35)
        }
        XCTAssertFalse(keeps(lat: 48.8504), "about 45 m")
        XCTAssertTrue(keeps(lat: 48.8510), "about 110 m")
    }

    func testAVagueFixIsNotKept() {
        XCTAssertTrue(PlaceTrackingRules.isUsableAccuracy(65))
        XCTAssertFalse(PlaceTrackingRules.isUsableAccuracy(-1))
        XCTAssertFalse(PlaceTrackingRules.isUsableAccuracy(3_000))
    }

    func testDefaultsAreBalancedFifteenMinutesWithPauseAndQuietNight() {
        let defaults = UserDefaults(suiteName: "PlaceTrackingTests")!
        defaults.removePersistentDomain(forName: "PlaceTrackingTests")
        XCTAssertFalse(PlaceTrackingSettings.isEnabled(defaults))
        XCTAssertEqual(PlaceTrackingSettings.mode(defaults), .balanced)
        XCTAssertEqual(PlaceTrackingSettings.intervalMinutes(defaults), 15)
        XCTAssertEqual(PlaceTrackingSettings.distanceMeters(defaults), 100)
        XCTAssertTrue(PlaceTrackingSettings.pausesWhenStill(defaults))
        XCTAssertTrue(PlaceTrackingSettings.quietAtNight(defaults))
        XCTAssertEqual(PlaceTrackingSettings.keepPointsDays(defaults), 365)
        XCTAssertFalse(PlaceTrackingSettings.coachReadsPlaces(defaults))
        defaults.set(7, forKey: PlaceTrackingSettings.intervalKey)
        XCTAssertEqual(PlaceTrackingSettings.intervalMinutes(defaults), 15, "an unknown value reads as the default")
        let lunch = PlaceQuietRange(startMinute: 720, endMinute: 840)
        PlaceTrackingSettings.setQuietRanges([lunch], defaults)
        XCTAssertEqual(PlaceTrackingSettings.quietRanges(defaults), [lunch])
        defaults.removePersistentDomain(forName: "PlaceTrackingTests")
    }

    func testAnUnnamedPlaceIsNumberedByCreation() {
        let a = PlaceRow(id: "a", lat: 1, lon: 1, radiusM: 150, createdAt: 10)
        let b = PlaceRow(id: "b", name: "Maison", lat: 2, lon: 2, radiusM: 150, createdAt: 5)
        let c = PlaceRow(id: "c", lat: 3, lon: 3, radiusM: 150, createdAt: 20)
        XCTAssertEqual(PlaceNaming.placeName(b, in: [a, b, c]), "Maison")
        XCTAssertEqual(PlaceTrackingSettings.rangeLabel(PlaceQuietRange(startMinute: 720, endMinute: 840)),
                       "12:00 – 14:00")
        XCTAssertNotEqual(PlaceNaming.placeName(a, in: [a, b, c]), PlaceNaming.placeName(c, in: [a, b, c]))
    }
}
