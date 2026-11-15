import XCTest
import GRDB
@testable import WhoopStore

/// Personal fork, chantier 24: the habits and their sessions (migration v56-habits).
///
/// A session stores when only (and a note); a running stopwatch is a session with no end.
/// Kotlin twin of the schema: `HabitsMigrationTest` (and `SchemaOracleTest` for both).
final class HabitStoreTests: XCTestCase {

    private func habit(_ id: String, name: String = "Lecture", created: Int = 1_000) -> HabitRow {
        HabitRow(id: id, name: name, colorKey: "cyan", symbol: "book.fill", createdAt: created, updatedAt: created)
    }

    private func session(_ id: String, habit: String = "h", start: Int, end: Int?, note: String? = nil,
                         manual: Bool = false) -> HabitSessionRow {
        HabitSessionRow(id: id, habitId: habit, startedAt: start, endedAt: end, note: note, isManual: manual,
                        createdAt: start, updatedAt: start)
    }

    // MARK: - Migration v56

    func testV56CreatesTheTwoTablesAndIsTheLastMigration() async throws {
        let store = try await WhoopStore.inMemory()
        let tables = try await store.tableNames()
        XCTAssertTrue(tables.contains("habit"))
        XCTAssertTrue(tables.contains("habitSession"))
        XCTAssertEqual(WhoopStore.makeMigrator().migrations.last, "v56-habits")
    }

    /// The migration only adds tables: a fast written before it is still there.
    func testV56KeepsTheRowsWrittenBefore() async throws {
        let dbQueue = try DatabaseQueue()
        try WhoopStore.makeMigrator().migrate(dbQueue, upTo: "v55-fasts")
        try await dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO fast (id, startedAt, endedAt, goalMinutes, createdAt, updatedAt)
                VALUES ('old', 1, 2, 960, 1, 1)
                """)
        }
        try WhoopStore.makeMigrator().migrate(dbQueue)
        let count = try await dbQueue.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM fast") }
        XCTAssertEqual(count, 1)
    }

    // MARK: - Habits

    func testHabitsComeOldestFirstAndUpsertKeepsCreatedAt() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.upsertHabit(habit("b", name: "Guitare", created: 2_000))
        try await store.upsertHabit(habit("a", name: "Lecture", created: 1_000))
        var edited = habit("b", name: "Guitare classique", created: 999_999)   // createdAt must not win
        edited.colorKey = "orange"
        edited.symbol = "guitars.fill"
        edited.updatedAt = 3_000
        try await store.upsertHabit(edited)
        let rows = try await store.allHabits()
        XCTAssertEqual(rows.map(\.id), ["a", "b"])
        XCTAssertEqual(rows.last?.name, "Guitare classique")
        XCTAssertEqual(rows.last?.colorKey, "orange")
        XCTAssertEqual(rows.last?.symbol, "guitars.fill")
        XCTAssertEqual(rows.last?.createdAt, 2_000)
        XCTAssertEqual(rows.last?.updatedAt, 3_000)
    }

    func testDeletingAHabitDeletesItsSessionsOnly() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.upsertHabit(habit("h"))
        try await store.upsertHabit(habit("other", name: "Méditation"))
        try await store.upsertHabitSession(session("s1", habit: "h", start: 1_000, end: 2_000))
        try await store.upsertHabitSession(session("s2", habit: "h", start: 3_000, end: nil))
        try await store.upsertHabitSession(session("keep", habit: "other", start: 1_500, end: 1_800))
        try await store.deleteHabitAndSessions(id: "h")
        let habits = try await store.allHabits()
        XCTAssertEqual(habits.map(\.id), ["other"])
        let left = try await store.habitSessionsStarted(fromSec: 0, toSec: 10_000, habitId: nil)
        XCTAssertEqual(left.map(\.id), ["keep"])
        let running = try await store.runningHabitSession()
        XCTAssertNil(running, "the running session went with its habit")
    }

    // MARK: - Sessions

    func testUpsertKeepsCreatedAtAndRoundTripsTheNoteAndTheManualFlag() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.upsertHabitSession(session("s", start: 1_000, end: nil))
        var edited = session("s", start: 900, end: 2_400, note: "Du mal à me concentrer.", manual: true)
        edited.createdAt = 999_999
        edited.updatedAt = 2_400
        try await store.upsertHabitSession(edited)
        let rows = try await store.recentHabitSessions(habitId: "h", limit: 10)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.startedAt, 900)
        XCTAssertEqual(rows.first?.endedAt, 2_400)
        XCTAssertEqual(rows.first?.note, "Du mal à me concentrer.")
        XCTAssertEqual(rows.first?.isManual, true)
        XCTAssertEqual(rows.first?.createdAt, 1_000)
        XCTAssertEqual(rows.first?.updatedAt, 2_400)

        var cleared = edited
        cleared.note = nil
        cleared.isManual = false
        try await store.upsertHabitSession(cleared)
        let again = try await store.recentHabitSessions(habitId: "h", limit: 10)
        XCTAssertNil(again.first?.note)
        XCTAssertEqual(again.first?.isManual, false)
    }

    func testTheRunningSessionIsTheNewestOpenOne() async throws {
        let store = try await WhoopStore.inMemory()
        var none = try await store.runningHabitSession()
        XCTAssertNil(none)
        try await store.upsertHabitSession(session("a", start: 1_000, end: 2_000))
        none = try await store.runningHabitSession()
        XCTAssertNil(none, "an ended session is not running")
        try await store.upsertHabitSession(session("b", start: 3_000, end: nil))
        try await store.upsertHabitSession(session("c", habit: "other", start: 4_000, end: nil))
        let running = try await store.runningHabitSession()
        XCTAssertEqual(running?.id, "c", "two left open: the most recently started one")
    }

    func testSessionsAreReadByTheirStart() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.upsertHabitSession(session("before", start: 900, end: 1_200))   // ends inside: out
        try await store.upsertHabitSession(session("from", start: 1_000, end: 1_100))   // from included
        try await store.upsertHabitSession(session("late", start: 1_900, end: 5_000))   // starts inside: in
        try await store.upsertHabitSession(session("to", start: 2_000, end: 2_100))     // to excluded
        try await store.upsertHabitSession(session("other", habit: "x", start: 1_500, end: 1_600))

        let one = try await store.habitSessionsStarted(fromSec: 1_000, toSec: 2_000, habitId: "h")
        XCTAssertEqual(one.map(\.id), ["from", "late"])
        let all = try await store.habitSessionsStarted(fromSec: 1_000, toSec: 2_000, habitId: nil)
        XCTAssertEqual(all.map(\.id), ["from", "other", "late"], "every habit, oldest first")

        let recent = try await store.recentHabitSessions(habitId: "h", limit: 2)
        XCTAssertEqual(recent.map(\.id), ["to", "late"], "newest first")
    }

    func testTheSummaryLeavesTheRunningSessionOut() async throws {
        let store = try await WhoopStore.inMemory()
        let empty = try await store.habitSessionSummary(habitId: "h")
        XCTAssertEqual(empty, HabitSessionSummary(count: 0, totalSeconds: 0, firstStartedAt: nil))
        try await store.upsertHabitSession(session("a", start: 5_000, end: 5_600))
        try await store.upsertHabitSession(session("b", start: 1_000, end: 2_800))
        try await store.upsertHabitSession(session("run", start: 500, end: nil))
        try await store.upsertHabitSession(session("x", habit: "other", start: 100, end: 9_000))
        let summary = try await store.habitSessionSummary(habitId: "h")
        XCTAssertEqual(summary, HabitSessionSummary(count: 2, totalSeconds: 2_400, firstStartedAt: 1_000))
    }

    func testDeleteForgetsOneSession() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.upsertHabitSession(session("a", start: 1_000, end: 2_000))
        try await store.upsertHabitSession(session("b", start: 3_000, end: nil))
        try await store.deleteHabitSession(id: "b")
        let rows = try await store.recentHabitSessions(habitId: "h", limit: 10)
        XCTAssertEqual(rows.map(\.id), ["a"])
        let running = try await store.runningHabitSession()
        XCTAssertNil(running)
    }
}
