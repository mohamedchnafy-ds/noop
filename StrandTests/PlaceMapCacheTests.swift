import XCTest
import WhoopStore
@testable import Strand

/// Personal fork, chantier 14 (Carte v2): what keeps the Map's Lieux fast (`PlaceMapFreeze`).
final class PlaceMapCacheTests: XCTestCase {

    private func figure(_ value: Double?, _ verdict: PlaceVerdict) -> PlaceFigure {
        PlaceFigure(value: value, normal: value.map { $0 - 2 }, delta: value == nil ? nil : 2, verdict: verdict, count: 4)
    }

    private func summary(_ id: String, stress: PlaceFigure) -> PlaceSummary {
        let none = PlaceFigure(value: nil, normal: nil, delta: nil, verdict: .none, count: 0)
        return PlaceSummary(place: PlaceRow(id: id, lat: 48.8, lon: 2.3, radiusM: 150, createdAt: 0),
                            name: id, visits: 5, nights: 3, lastArrival: 100,
                            heartRate: figure(70, .close), stress: stress, hrv: figure(52, .better),
                            recovery: none, sleep: none, nightBars: [PlaceNightBar(day: "2026-11-01", hrv: 51)])
    }

    func testAPastDayIsKeptOnlyOnceItEndedADayAgo() {
        let end = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertFalse(PlaceMapFreeze.isFrozenDay(dayEnd: end, now: end.addingTimeInterval(3_600)),
                       "yesterday can still receive a late sync")
        XCTAssertTrue(PlaceMapFreeze.isFrozenDay(dayEnd: end, now: end.addingTimeInterval(86_400)))
        XCTAssertFalse(PlaceMapFreeze.isFrozenDay(dayEnd: end, now: end.addingTimeInterval(-10)), "today")
    }

    func testThePrunedStoreDropsOldDaysAndAnotherStressSetting() {
        var store = PlaceMapDayStore(personalBaseline: false)
        store.stress = ["2026-07-01": [PlaceStressWindow(start: 0, end: 3_600, level: 1)],
                        "2026-11-01": [PlaceStressWindow(start: 0, end: 3_600, level: 2)]]
        store.heartRate = ["2026-07-01": [PlaceHRBucket(ts: 0, bpm: 60)],
                           "2026-11-01": [PlaceHRBucket(ts: 300, bpm: 62)]]
        let pruned = PlaceMapFreeze.prunedDayStore(store, oldestKey: "2026-08-01", personalBaseline: false)
        XCTAssertEqual(Array(pruned.stress.keys), ["2026-11-01"])
        XCTAssertEqual(Array(pruned.heartRate.keys), ["2026-11-01"])

        let switched = PlaceMapFreeze.prunedDayStore(store, oldestKey: "2026-08-01", personalBaseline: true)
        XCTAssertTrue(switched.stress.isEmpty, "stress scored with the other baseline is dropped")
        XCTAssertEqual(Array(switched.heartRate.keys), ["2026-11-01"], "heart rate does not depend on it")
        XCTAssertTrue(switched.personalBaseline)

        var old = store
        old.version = PlaceMapDayStore.formatVersion + 1
        XCTAssertEqual(PlaceMapFreeze.prunedDayStore(old, oldestKey: "2026-08-01", personalBaseline: false),
                       PlaceMapDayStore(personalBaseline: false))
    }

    func testFiguresComputedWithoutStressKeepTheLastStress() {
        let none = PlaceFigure(value: nil, normal: nil, delta: nil, verdict: .none, count: 0)
        let previous = [summary("home", stress: figure(12, .worse))]
        let fresh = [summary("home", stress: none), summary("gym", stress: none)]
        let merged = PlaceMapFreeze.carryPlaceStress(from: previous, into: fresh)
        XCTAssertEqual(merged[0].stress, figure(12, .worse))
        XCTAssertEqual(merged[1].stress, none, "a new place has no stress to keep")
        let scored = [summary("home", stress: figure(4, .close))]
        XCTAssertEqual(PlaceMapFreeze.carryPlaceStress(from: previous, into: scored)[0].stress, figure(4, .close),
                       "a fresh stress figure wins")
    }

    func testTheSnapshotRoundTrips() throws {
        let snapshot = PlaceMapSnapshot(computedAt: 42, summaries: [summary("home", stress: figure(12, .worse))])
        let data = try JSONEncoder().encode(snapshot)
        XCTAssertEqual(try JSONDecoder().decode(PlaceMapSnapshot.self, from: data), snapshot)
    }
}
