import XCTest
import GRDB
@testable import WhoopStore

/// Personal fork, chantier 14 step 2: positions, places and visits (migration v54-places).
///
/// A point or a visit stores where and when only; the metrics are read by time from the strap's data.
/// Kotlin twin of the schema: `PlacesMigrationTest` (and `SchemaOracleTest` for both).
final class PlaceStoreTests: XCTestCase {

    private func visit(_ id: String, place: String, from arrived: Int, to departed: Int?) -> PlaceVisitRow {
        PlaceVisitRow(id: id, placeId: place, arrivedAt: arrived, departedAt: departed, lat: 48.85,
                      lon: 2.35, accuracyM: 40)
    }

    // MARK: - Migration v54

    func testV54CreatesTheThreeTablesAndIsTheLastMigration() async throws {
        let store = try await WhoopStore.inMemory()
        let tables = try await store.tableNames()
        XCTAssertTrue(tables.contains("locationPoint"))
        XCTAssertTrue(tables.contains("place"))
        XCTAssertTrue(tables.contains("placeVisit"))
        XCTAssertEqual(WhoopStore.makeMigrator().migrations.last, "v54-places")
    }

    /// The migration only adds tables: a meal written before it is still there.
    func testV54KeepsTheRowsWrittenBefore() async throws {
        let dbQueue = try DatabaseQueue()
        try WhoopStore.makeMigrator().migrate(dbQueue, upTo: "v53-meal-slot")
        try await dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO meal (id, day, eatenAt, name, origin, favorite, createdAt, updatedAt, planned, slot)
                VALUES ('old', '2026-11-01', 1, 'Old', 'manual', 0, 1, 1, 0, NULL)
                """)
        }
        try WhoopStore.makeMigrator().migrate(dbQueue)
        let count = try await dbQueue.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM meal") }
        XCTAssertEqual(count, 1)
    }

    // MARK: - Points

    func testPointsKeepTheirOrderStepsAndFirstWriteAtTheSameInstant() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.insertLocationPoint(LocationPointRow(ts: 2_000, lat: 48.1, lon: 2.1, accuracyM: 65,
                                                             steps: 120))
        try await store.insertLocationPoint(LocationPointRow(ts: 1_000, lat: 48.0, lon: 2.0, accuracyM: 30))
        try await store.insertLocationPoint(LocationPointRow(ts: 2_000, lat: 0, lon: 0, accuracyM: 5, steps: 1))
        let all = try await store.locationPointsBetween(fromMs: 0, toMs: 10_000)
        XCTAssertEqual(all.map(\.ts), [1_000, 2_000])
        XCTAssertEqual(all.map(\.steps), [nil, 120], "no steps = unknown; the first point at 2 000 ms stays")
        XCTAssertEqual(all.last?.lat, 48.1)
        let window = try await store.locationPointsBetween(fromMs: 1_000, toMs: 2_000)
        XCTAssertEqual(window.map(\.ts), [1_000], "from included, to excluded")
        let latest = try await store.latestLocationPoint()
        XCTAssertEqual(latest?.ts, 2_000)
        let counted = try await store.countLocationPoints(fromMs: 1_500)
        XCTAssertEqual(counted, 1)

        try await store.pruneLocationPoints(beforeMs: 1_500)
        let pruned = try await store.locationPointsBetween(fromMs: 0, toMs: 10_000)
        XCTAssertEqual(pruned.map(\.ts), [2_000])
        try await store.eraseLocationPoints()
        let none = try await store.latestLocationPoint()
        XCTAssertNil(none)
    }

    // MARK: - Places and visits

    func testAPlaceKeepsItsCreationTimeAndABlankNameClearsIt() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.upsertPlace(PlaceRow(id: "home", lat: 48.85, lon: 2.35, radiusM: 150, createdAt: 10))
        try await store.upsertPlace(PlaceRow(id: "home", name: "Maison", lat: 48.86, lon: 2.36, radiusM: 120,
                                             createdAt: 99))
        var places = try await store.allPlaces()
        XCTAssertEqual(places.count, 1)
        XCTAssertEqual(places.first?.createdAt, 10)
        XCTAssertEqual(places.first?.name, "Maison")
        XCTAssertEqual(places.first?.radiusM, 120)

        try await store.renamePlace(id: "home", name: "  Chez moi ")
        places = try await store.allPlaces()
        XCTAssertEqual(places.first?.name, "Chez moi")
        try await store.renamePlace(id: "home", name: "   ")
        places = try await store.allPlaces()
        XCTAssertNil(places.first?.name)
    }

    func testVisitsOverlapTheWindowAndAnOpenVisitOverlapsEverythingAfter() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.upsertPlaceVisit(visit("a", place: "home", from: 100, to: 200))
        try await store.upsertPlaceVisit(visit("b", place: "work", from: 300, to: 400))
        try await store.upsertPlaceVisit(visit("c", place: "home", from: 500, to: nil))
        var hits = try await store.placeVisitsBetween(fromSec: 150, toSec: 350)
        XCTAssertEqual(hits.map(\.id), ["a", "b"])
        hits = try await store.placeVisitsBetween(fromSec: 200, toSec: 300)
        XCTAssertEqual(hits.map(\.id), [], "touching ends do not overlap")
        hits = try await store.placeVisitsBetween(fromSec: 10_000, toSec: 20_000)
        XCTAssertEqual(hits.map(\.id), ["c"], "a visit still going")

        try await store.upsertPlaceVisit(visit("c", place: "home", from: 500, to: 900))
        hits = try await store.placeVisitsBetween(fromSec: 10_000, toSec: 20_000)
        XCTAssertEqual(hits.map(\.id), [], "closed by its departure")
    }

    func testForgettingAPlaceDeletesItsVisitsOnly() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.upsertPlace(PlaceRow(id: "home", lat: 1, lon: 1, radiusM: 150, createdAt: 1))
        try await store.upsertPlace(PlaceRow(id: "work", lat: 2, lon: 2, radiusM: 150, createdAt: 2))
        try await store.upsertPlaceVisit(visit("a", place: "home", from: 100, to: 200))
        try await store.upsertPlaceVisit(visit("b", place: "work", from: 300, to: 400))
        try await store.forgetPlace(id: "home")
        let places = try await store.allPlaces()
        XCTAssertEqual(places.map(\.id), ["work"])
        let visits = try await store.placeVisitsBetween(fromSec: 0, toSec: 1_000)
        XCTAssertEqual(visits.map(\.id), ["b"])

        try await store.erasePlaces()
        let noPlace = try await store.allPlaces()
        XCTAssertEqual(noPlace, [])
        let noVisit = try await store.placeVisitsBetween(fromSec: 0, toSec: 1_000)
        XCTAssertEqual(noVisit, [])
    }

    /// Retention: an old visit goes, a visit still going stays, and an unnamed place left empty goes too.
    func testPruningVisitsKeepsNamedPlacesAndOpenVisits() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.upsertPlace(PlaceRow(id: "hotel", lat: 1, lon: 1, radiusM: 150, createdAt: 1))
        try await store.upsertPlace(PlaceRow(id: "parents", name: "Parents", lat: 2, lon: 2, radiusM: 150,
                                             createdAt: 2))
        try await store.upsertPlace(PlaceRow(id: "home", lat: 3, lon: 3, radiusM: 150, createdAt: 3))
        try await store.upsertPlaceVisit(visit("old1", place: "hotel", from: 10, to: 20))
        try await store.upsertPlaceVisit(visit("old2", place: "parents", from: 30, to: 40))
        try await store.upsertPlaceVisit(visit("open", place: "home", from: 50, to: nil))
        try await store.prunePlaceVisits(beforeSec: 1_000)
        let places = try await store.allPlaces()
        XCTAssertEqual(places.map(\.id), ["parents", "home"])
        let visits = try await store.placeVisitsBetween(fromSec: 0, toSec: 10_000)
        XCTAssertEqual(visits.map(\.id), ["open"])
    }
}
