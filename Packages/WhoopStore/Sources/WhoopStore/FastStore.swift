import Foundation
import GRDB

// MARK: - v55 store: intermittent fasts (personal fork, chantier 15)
//
// FastStore.swift — GRDB CRUD over `fast` (migration v55-fasts), in the PlaceStore idiom: a plain row,
// raw `Row` fetch + manual decode, all GRDB work through the actor's `syncWrite` / `syncRead`.
//
// A fast stores WHEN only: its start (the last meal, editable after the fact), its end (nil while it is
// going) and the duration aimed at. Everything shown about it (elapsed, remaining, phase, history) is
// derived from those values by `FastingTimeline` in StrandAnalytics, so a corrected start or end changes
// every readout at once and nothing derived is ever stale in the table.
//
// The Android Room twin (`FastEntity`, MIGRATION_46_47) is the schema only: the fasting section and its
// screens are iPhone only in this fork, so Android has no DAO.

// MARK: - Row

/// One intermittent fast. Unix seconds throughout.
public struct FastRow: Equatable, Codable, Sendable {
    public var id: String
    /// When the fast started: the last meal. Editable after the fact ("I forgot to press Start").
    public var startedAt: Int
    /// When it ended; nil while the fast is still going. Editable too ("I ate before opening the app").
    public var endedAt: Int?
    /// The duration aimed at, in minutes (16 h = 960). The planned end is `startedAt + goalMinutes * 60`.
    public var goalMinutes: Int
    public var createdAt: Int
    public var updatedAt: Int

    public init(id: String, startedAt: Int, endedAt: Int?, goalMinutes: Int, createdAt: Int, updatedAt: Int) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.goalMinutes = goalMinutes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    static func decode(_ row: Row) -> FastRow {
        FastRow(id: row["id"], startedAt: row["startedAt"], endedAt: row["endedAt"], goalMinutes: row["goalMinutes"],
                createdAt: row["createdAt"], updatedAt: row["updatedAt"])
    }
}

// MARK: - Store

extension WhoopStore {

    /// Insert `fast`, or replace every field of the fast with the same id but its `createdAt`.
    public func upsertFast(_ fast: FastRow) async throws {
        try syncWrite { db in
            try db.execute(sql: """
                INSERT INTO fast (id, startedAt, endedAt, goalMinutes, createdAt, updatedAt)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    startedAt = excluded.startedAt, endedAt = excluded.endedAt,
                    goalMinutes = excluded.goalMinutes, updatedAt = excluded.updatedAt
                """, arguments: [fast.id, fast.startedAt, fast.endedAt, fast.goalMinutes, fast.createdAt,
                                 fast.updatedAt])
        }
    }

    /// The fast still going (no end), the most recently started one if several were left open; nil
    /// when nothing is running.
    public func runningFast() async throws -> FastRow? {
        try syncRead { db in
            try Row.fetchOne(db, sql: """
                SELECT * FROM fast WHERE endedAt IS NULL ORDER BY startedAt DESC, id DESC LIMIT 1
                """).map(FastRow.decode)
        }
    }

    /// The fasts that overlap `[fromSec, toSec)` (a fast still going overlaps everything after its start),
    /// oldest first.
    public func fastsBetween(fromSec: Int, toSec: Int) async throws -> [FastRow] {
        try syncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM fast
                WHERE startedAt < ? AND (endedAt IS NULL OR endedAt > ?)
                ORDER BY startedAt ASC, id ASC
                """, arguments: [toSec, fromSec]).map(FastRow.decode)
        }
    }

    /// The newest `limit` fasts, running or not, newest first.
    public func recentFasts(limit: Int) async throws -> [FastRow] {
        try syncRead { db in
            try Row.fetchAll(db, sql: "SELECT * FROM fast ORDER BY startedAt DESC, id DESC LIMIT ?",
                             arguments: [max(0, limit)]).map(FastRow.decode)
        }
    }

    /// Forget one fast.
    public func deleteFast(id: String) async throws {
        try syncWrite { db in
            try db.execute(sql: "DELETE FROM fast WHERE id = ?", arguments: [id])
        }
    }
}
