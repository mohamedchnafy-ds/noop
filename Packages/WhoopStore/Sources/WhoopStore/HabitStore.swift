import Foundation
import GRDB

// MARK: - v56 store: habits (personal fork, chantier 24)
//
// HabitStore.swift — GRDB CRUD over `habit` and `habitSession` (migration v56-habits), in the FastStore
// idiom: plain rows, raw `Row` fetch + manual decode, all GRDB work through the actor's `syncWrite` /
// `syncRead`.
//
// A habit is a category the wearer creates (reading, meditation…): a name, a colour key and a symbol.
// A session stores WHEN only: its start, its end (nil while the stopwatch runs) and an optional free
// note. A running stopwatch is therefore a row with no end: nothing counts in the background, so the
// session survives the app being closed, the phone locked or restarted. Totals, bars and the
// time-of-day strip are derived from those values by the app (`HabitLog`), never stored.
//
// The Android Room twin (`HabitEntity`, `HabitSessionEntity`, MIGRATION_47_48) is the schema only: the
// habits section is iPhone only in this fork, so Android has no DAO.

// MARK: - Rows

/// One habit the wearer created. Unix seconds throughout.
public struct HabitRow: Equatable, Codable, Sendable {
    public var id: String
    /// What the wearer called it ("Lecture"). Never empty once saved.
    public var name: String
    /// A palette key the app maps to a design token ("cyan", "violet"…); an unknown key falls back.
    public var colorKey: String
    /// An SF Symbol name ("book.fill").
    public var symbol: String
    public var createdAt: Int
    public var updatedAt: Int

    public init(id: String, name: String, colorKey: String, symbol: String, createdAt: Int, updatedAt: Int) {
        self.id = id
        self.name = name
        self.colorKey = colorKey
        self.symbol = symbol
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    static func decode(_ row: Row) -> HabitRow {
        HabitRow(id: row["id"], name: row["name"], colorKey: row["colorKey"], symbol: row["symbol"],
                 createdAt: row["createdAt"], updatedAt: row["updatedAt"])
    }
}

/// One session of a habit. Unix seconds throughout.
public struct HabitSessionRow: Equatable, Codable, Sendable {
    public var id: String
    /// The habit it belongs to (`HabitRow.id`).
    public var habitId: String
    public var startedAt: Int
    /// When it ended; nil while the stopwatch runs.
    public var endedAt: Int?
    /// The wearer's free note ("hard to focus tonight"); nil when there is none.
    public var note: String?
    /// True for a session added by hand after the fact, false for one timed by the stopwatch.
    public var isManual: Bool
    public var createdAt: Int
    public var updatedAt: Int

    public init(id: String, habitId: String, startedAt: Int, endedAt: Int?, note: String?, isManual: Bool,
                createdAt: Int, updatedAt: Int) {
        self.id = id
        self.habitId = habitId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.note = note
        self.isManual = isManual
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    static func decode(_ row: Row) -> HabitSessionRow {
        HabitSessionRow(id: row["id"], habitId: row["habitId"], startedAt: row["startedAt"],
                        endedAt: row["endedAt"], note: row["note"], isManual: row["manual"],
                        createdAt: row["createdAt"], updatedAt: row["updatedAt"])
    }
}

/// What a habit adds up to over all its ENDED sessions (a running stopwatch is left out).
public struct HabitSessionSummary: Equatable, Sendable {
    /// Ended sessions.
    public var count: Int
    /// Their summed duration, seconds.
    public var totalSeconds: Int
    /// The start of the oldest one; nil when there is none.
    public var firstStartedAt: Int?

    public init(count: Int, totalSeconds: Int, firstStartedAt: Int?) {
        self.count = count
        self.totalSeconds = totalSeconds
        self.firstStartedAt = firstStartedAt
    }
}

// MARK: - Store

extension WhoopStore {

    /// Insert `habit`, or replace every field of the habit with the same id but its `createdAt`.
    public func upsertHabit(_ habit: HabitRow) async throws {
        try syncWrite { db in
            try db.execute(sql: """
                INSERT INTO habit (id, name, colorKey, symbol, createdAt, updatedAt)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    name = excluded.name, colorKey = excluded.colorKey, symbol = excluded.symbol,
                    updatedAt = excluded.updatedAt
                """, arguments: [habit.id, habit.name, habit.colorKey, habit.symbol, habit.createdAt,
                                 habit.updatedAt])
        }
    }

    /// Every habit, oldest first (the order they were created in).
    public func allHabits() async throws -> [HabitRow] {
        try syncRead { db in
            try Row.fetchAll(db, sql: "SELECT * FROM habit ORDER BY createdAt ASC, id ASC").map(HabitRow.decode)
        }
    }

    /// Forget one habit AND all its sessions, in one transaction: no session is left without its habit.
    public func deleteHabitAndSessions(id: String) async throws {
        try syncWrite { db in
            try db.execute(sql: "DELETE FROM habitSession WHERE habitId = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM habit WHERE id = ?", arguments: [id])
        }
    }

    /// Insert `session`, or replace every field of the session with the same id but its `createdAt`.
    public func upsertHabitSession(_ session: HabitSessionRow) async throws {
        try syncWrite { db in
            try db.execute(sql: """
                INSERT INTO habitSession (id, habitId, startedAt, endedAt, note, manual, createdAt, updatedAt)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    habitId = excluded.habitId, startedAt = excluded.startedAt, endedAt = excluded.endedAt,
                    note = excluded.note, manual = excluded.manual, updatedAt = excluded.updatedAt
                """, arguments: [session.id, session.habitId, session.startedAt, session.endedAt, session.note,
                                 session.isManual ? 1 : 0, session.createdAt, session.updatedAt])
        }
    }

    /// The stopwatch running (a session with no end), the most recently started one if several were
    /// left open; nil when nothing runs.
    public func runningHabitSession() async throws -> HabitSessionRow? {
        try syncRead { db in
            try Row.fetchOne(db, sql: """
                SELECT * FROM habitSession WHERE endedAt IS NULL ORDER BY startedAt DESC, id DESC LIMIT 1
                """).map(HabitSessionRow.decode)
        }
    }

    /// The sessions that STARTED in `[fromSec, toSec)`, of one habit or (nil) of every habit, oldest
    /// first. By start, because a session counts for the day it started on (the owner's choice).
    public func habitSessionsStarted(fromSec: Int, toSec: Int, habitId: String?) async throws -> [HabitSessionRow] {
        try syncRead { db in
            if let habitId {
                return try Row.fetchAll(db, sql: """
                    SELECT * FROM habitSession
                    WHERE habitId = ? AND startedAt >= ? AND startedAt < ?
                    ORDER BY startedAt ASC, id ASC
                    """, arguments: [habitId, fromSec, toSec]).map(HabitSessionRow.decode)
            }
            return try Row.fetchAll(db, sql: """
                SELECT * FROM habitSession WHERE startedAt >= ? AND startedAt < ?
                ORDER BY startedAt ASC, id ASC
                """, arguments: [fromSec, toSec]).map(HabitSessionRow.decode)
        }
    }

    /// The newest `limit` sessions of one habit, running or not, newest first.
    public func recentHabitSessions(habitId: String, limit: Int) async throws -> [HabitSessionRow] {
        try syncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM habitSession WHERE habitId = ? ORDER BY startedAt DESC, id DESC LIMIT ?
                """, arguments: [habitId, max(0, limit)]).map(HabitSessionRow.decode)
        }
    }

    /// Count, summed duration and first start of the ENDED sessions of one habit.
    public func habitSessionSummary(habitId: String) async throws -> HabitSessionSummary {
        try syncRead { db in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT COUNT(*) AS n, COALESCE(SUM(endedAt - startedAt), 0) AS total, MIN(startedAt) AS first
                FROM habitSession WHERE habitId = ? AND endedAt IS NOT NULL
                """, arguments: [habitId]) else {
                return HabitSessionSummary(count: 0, totalSeconds: 0, firstStartedAt: nil)
            }
            let count: Int = row["n"]
            let total: Int = row["total"]
            let first: Int? = row["first"]
            return HabitSessionSummary(count: count, totalSeconds: total, firstStartedAt: first)
        }
    }

    /// Forget one session.
    public func deleteHabitSession(id: String) async throws {
        try syncWrite { db in
            try db.execute(sql: "DELETE FROM habitSession WHERE id = ?", arguments: [id])
        }
    }
}
