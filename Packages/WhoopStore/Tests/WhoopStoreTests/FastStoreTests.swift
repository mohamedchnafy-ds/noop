import XCTest
import GRDB
@testable import WhoopStore

/// Personal fork, chantier 15: the intermittent fasts (migration v55-fasts).
///
/// A fast stores when only; phases, progress and history are derived by `FastingTimeline`.
/// Kotlin twin of the schema: `FastsMigrationTest` (and `SchemaOracleTest` for both).
final class FastStoreTests: XCTestCase {

    private func fast(_ id: String, start: Int, end: Int?, goal: Int = 960) -> FastRow {
        FastRow(id: id, startedAt: start, endedAt: end, goalMinutes: goal, createdAt: start, updatedAt: start)
    }

    // MARK: - Migration v55

    func testV55CreatesTheTableAndIsTheLastMigration() async throws {
        let store = try await WhoopStore.inMemory()
        let tables = try await store.tableNames()
        XCTAssertTrue(tables.contains("fast"))
        XCTAssertEqual(WhoopStore.makeMigrator().migrations.last, "v55-fasts")
    }

    /// The migration only adds a table: a visit written before it is still there.
    func testV55KeepsTheRowsWrittenBefore() async throws {
        let dbQueue = try DatabaseQueue()
        try WhoopStore.makeMigrator().migrate(dbQueue, upTo: "v54-places")
        try await dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO placeVisit (id, placeId, arrivedAt, departedAt, lat, lon, accuracyM)
                VALUES ('old', 'home', 1, 2, 48.85, 2.35, 40)
                """)
        }
        try WhoopStore.makeMigrator().migrate(dbQueue)
        let count = try await dbQueue.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM placeVisit") }
        XCTAssertEqual(count, 1)
    }

    // MARK: - Running fast

    func testTheRunningFastIsTheNewestOpenOne() async throws {
        let store = try await WhoopStore.inMemory()
        var none = try await store.runningFast()
        XCTAssertNil(none)
        try await store.upsertFast(fast("a", start: 1_000, end: 50_000))
        none = try await store.runningFast()
        XCTAssertNil(none, "an ended fast is not running")
        try await store.upsertFast(fast("b", start: 60_000, end: nil))
        try await store.upsertFast(fast("c", start: 70_000, end: nil))
        let running = try await store.runningFast()
        XCTAssertEqual(running?.id, "c", "two left open: the most recently started one")
    }

    // MARK: - Upsert

    func testUpsertKeepsCreatedAtAndReplacesTheRest() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.upsertFast(fast("a", start: 1_000, end: nil))
        var edited = fast("a", start: 500, end: 40_000, goal: 1_080)
        edited.createdAt = 999_999          // must not win over the stored createdAt
        edited.updatedAt = 40_000
        try await store.upsertFast(edited)
        let rows = try await store.recentFasts(limit: 10)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.startedAt, 500)
        XCTAssertEqual(rows.first?.endedAt, 40_000)
        XCTAssertEqual(rows.first?.goalMinutes, 1_080)
        XCTAssertEqual(rows.first?.createdAt, 1_000)
        XCTAssertEqual(rows.first?.updatedAt, 40_000)
    }

    // MARK: - Windows and order

    func testFastsBetweenReturnsTheOverlappingOnesOldestFirst() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.upsertFast(fast("early", start: 1_000, end: 2_000))
        try await store.upsertFast(fast("inside", start: 5_000, end: 6_000))
        try await store.upsertFast(fast("straddles", start: 9_000, end: 11_000))
        try await store.upsertFast(fast("open", start: 12_000, end: nil))
        try await store.upsertFast(fast("later", start: 20_000, end: 21_000))

        let window = try await store.fastsBetween(fromSec: 4_000, toSec: 10_000)
        XCTAssertEqual(window.map(\.id), ["inside", "straddles"], "from included, to excluded; ends before from are out")

        let tail = try await store.fastsBetween(fromSec: 15_000, toSec: 30_000)
        XCTAssertEqual(tail.map(\.id), ["open", "later"], "a fast still going overlaps everything after its start")

        let recent = try await store.recentFasts(limit: 2)
        XCTAssertEqual(recent.map(\.id), ["later", "open"], "newest first")
    }

    func testDeleteForgetsOneFast() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.upsertFast(fast("a", start: 1_000, end: 2_000))
        try await store.upsertFast(fast("b", start: 3_000, end: nil))
        try await store.deleteFast(id: "b")
        let rows = try await store.recentFasts(limit: 10)
        XCTAssertEqual(rows.map(\.id), ["a"])
        let running = try await store.runningFast()
        XCTAssertNil(running)
    }
}
