import Foundation
import GRDB

// MARK: - v54 store: positions, places and visits (personal fork, chantier 14 step 2)
//
// PlaceStore.swift — GRDB CRUD over `locationPoint`, `place` and `placeVisit` (migration v54-places), in
// the MealLogStore idiom: plain rows, raw `Row` fetch + manual decode, all GRDB work through the actor's
// `syncWrite` / `syncRead`.
//
// A point or a visit stores WHERE and WHEN only. The metrics shown per place or per point (heart rate,
// stress, the nights' HRV and recovery) are read by time from the strap's data, never copied here, so
// a re-synced or corrected night changes the place's figures without touching these tables.
//
// The Android Room twin (`LocationPointEntity`, `PlaceEntity`, `PlaceVisitEntity`, MIGRATION_45_46) is the
// schema only: the place tracking and its screens are iPhone only in this fork, so Android has no DAO.

// MARK: - Rows

/// One position of the continuous tracking.
public struct LocationPointRow: Equatable, Codable, Sendable {
    /// Unix milliseconds (the key: one point per instant).
    public var ts: Int64
    public var lat: Double
    public var lon: Double
    /// Horizontal accuracy in metres, as iOS reported it.
    public var accuracyM: Double
    /// The iPhone pedometer's steps since the previous point; nil when unknown (no pedometer, no
    /// previous point, or a gap longer than iOS keeps).
    public var steps: Int?

    public init(ts: Int64, lat: Double, lon: Double, accuracyM: Double, steps: Int? = nil) {
        self.ts = ts
        self.lat = lat
        self.lon = lon
        self.accuracyM = accuracyM
        self.steps = steps
    }

    static func decode(_ row: Row) -> LocationPointRow {
        LocationPointRow(ts: row["ts"], lat: row["lat"], lon: row["lon"], accuracyM: row["accuracyM"],
                         steps: row["steps"])
    }
}

/// A spot where the wearer stays: the centre and radius of the zone its visits fall in.
public struct PlaceRow: Equatable, Codable, Sendable {
    public var id: String
    /// The name the wearer gave it ("Maison"); nil until then.
    public var name: String?
    public var lat: Double
    public var lon: Double
    /// Radius of the zone, metres.
    public var radiusM: Double
    /// Unix seconds.
    public var createdAt: Int

    public init(id: String, name: String? = nil, lat: Double, lon: Double, radiusM: Double, createdAt: Int) {
        self.id = id
        self.name = name
        self.lat = lat
        self.lon = lon
        self.radiusM = radiusM
        self.createdAt = createdAt
    }

    static func decode(_ row: Row) -> PlaceRow {
        PlaceRow(id: row["id"], name: row["name"], lat: row["lat"], lon: row["lon"], radiusM: row["radiusM"],
                 createdAt: row["createdAt"])
    }
}

/// One stay at a place, as iOS reported it (`CLVisit`).
public struct PlaceVisitRow: Equatable, Codable, Sendable {
    public var id: String
    public var placeId: String
    /// Unix seconds.
    public var arrivedAt: Int
    /// Unix seconds; nil while the wearer is still there.
    public var departedAt: Int?
    public var lat: Double
    public var lon: Double
    /// Horizontal accuracy of the visit's centre, metres.
    public var accuracyM: Double

    public init(id: String, placeId: String, arrivedAt: Int, departedAt: Int?, lat: Double, lon: Double,
                accuracyM: Double) {
        self.id = id
        self.placeId = placeId
        self.arrivedAt = arrivedAt
        self.departedAt = departedAt
        self.lat = lat
        self.lon = lon
        self.accuracyM = accuracyM
    }

    static func decode(_ row: Row) -> PlaceVisitRow {
        PlaceVisitRow(id: row["id"], placeId: row["placeId"], arrivedAt: row["arrivedAt"],
                      departedAt: row["departedAt"], lat: row["lat"], lon: row["lon"],
                      accuracyM: row["accuracyM"])
    }
}

// MARK: - Store

extension WhoopStore {

    // MARK: Points

    /// Store one point. A second point at the same millisecond is ignored (the first one stays).
    public func insertLocationPoint(_ point: LocationPointRow) async throws {
        try syncWrite { db in
            try db.execute(sql: """
                INSERT OR IGNORE INTO locationPoint (ts, lat, lon, accuracyM, steps) VALUES (?, ?, ?, ?, ?)
                """, arguments: [point.ts, point.lat, point.lon, point.accuracyM, point.steps])
        }
    }

    /// The points from `fromMs` (included) to `toMs` (excluded), oldest first.
    public func locationPointsBetween(fromMs: Int64, toMs: Int64) async throws -> [LocationPointRow] {
        try syncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM locationPoint WHERE ts >= ? AND ts < ? ORDER BY ts ASC
                """, arguments: [fromMs, toMs]).map(LocationPointRow.decode)
        }
    }

    /// The most recent point, or nil.
    public func latestLocationPoint() async throws -> LocationPointRow? {
        try syncRead { db in
            try Row.fetchOne(db, sql: "SELECT * FROM locationPoint ORDER BY ts DESC LIMIT 1")
                .map(LocationPointRow.decode)
        }
    }

    /// How many points were stored from `fromMs` on.
    public func countLocationPoints(fromMs: Int64) async throws -> Int {
        try syncRead { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM locationPoint WHERE ts >= ?",
                             arguments: [fromMs]) ?? 0
        }
    }

    /// Delete the points older than `beforeMs` (the retention setting).
    public func pruneLocationPoints(beforeMs: Int64) async throws {
        try syncWrite { db in
            try db.execute(sql: "DELETE FROM locationPoint WHERE ts < ?", arguments: [beforeMs])
        }
    }

    /// Delete every point.
    public func eraseLocationPoints() async throws {
        try syncWrite { db in
            try db.execute(sql: "DELETE FROM locationPoint")
        }
    }

    // MARK: Places

    /// Insert `place`, or replace every field of the place with the same id but its `createdAt`.
    public func upsertPlace(_ place: PlaceRow) async throws {
        try syncWrite { db in
            try db.execute(sql: """
                INSERT INTO place (id, name, lat, lon, radiusM, createdAt) VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    name = excluded.name, lat = excluded.lat, lon = excluded.lon, radiusM = excluded.radiusM
                """, arguments: [place.id, place.name, place.lat, place.lon, place.radiusM, place.createdAt])
        }
    }

    /// Every place, oldest first.
    public func allPlaces() async throws -> [PlaceRow] {
        try syncRead { db in
            try Row.fetchAll(db, sql: "SELECT * FROM place ORDER BY createdAt ASC, id ASC")
                .map(PlaceRow.decode)
        }
    }

    /// Give a place a name; an empty or blank name clears it.
    public func renamePlace(id: String, name: String?) async throws {
        let kept = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        try syncWrite { db in
            try db.execute(sql: "UPDATE place SET name = ? WHERE id = ?",
                           arguments: [(kept?.isEmpty ?? true) ? nil : kept, id])
        }
    }

    /// Forget a place and every visit to it, in one transaction.
    public func forgetPlace(id: String) async throws {
        try syncWrite { db in
            try db.execute(sql: "DELETE FROM placeVisit WHERE placeId = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM place WHERE id = ?", arguments: [id])
        }
    }

    /// Delete every place and every visit.
    public func erasePlaces() async throws {
        try syncWrite { db in
            try db.execute(sql: "DELETE FROM placeVisit")
            try db.execute(sql: "DELETE FROM place")
        }
    }

    // MARK: Visits

    /// Insert `visit`, or replace every field of the visit with the same id.
    public func upsertPlaceVisit(_ visit: PlaceVisitRow) async throws {
        try syncWrite { db in
            try db.execute(sql: """
                INSERT INTO placeVisit (id, placeId, arrivedAt, departedAt, lat, lon, accuracyM)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    placeId = excluded.placeId, arrivedAt = excluded.arrivedAt,
                    departedAt = excluded.departedAt, lat = excluded.lat, lon = excluded.lon,
                    accuracyM = excluded.accuracyM
                """, arguments: [visit.id, visit.placeId, visit.arrivedAt, visit.departedAt, visit.lat,
                                 visit.lon, visit.accuracyM])
        }
    }

    /// The visits that overlap `[fromSec, toSec)` (a visit still going overlaps everything after its
    /// arrival), in the order of arrival.
    public func placeVisitsBetween(fromSec: Int, toSec: Int) async throws -> [PlaceVisitRow] {
        try syncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM placeVisit
                WHERE arrivedAt < ? AND (departedAt IS NULL OR departedAt > ?)
                ORDER BY arrivedAt ASC, id ASC
                """, arguments: [toSec, fromSec]).map(PlaceVisitRow.decode)
        }
    }

    /// Delete the visits that ended before `beforeSec` (the retention setting); a place left with no
    /// visit is deleted with them unless the wearer named it.
    public func prunePlaceVisits(beforeSec: Int) async throws {
        try syncWrite { db in
            try db.execute(sql: "DELETE FROM placeVisit WHERE departedAt IS NOT NULL AND departedAt < ?",
                           arguments: [beforeSec])
            try db.execute(sql: """
                DELETE FROM place WHERE name IS NULL
                  AND NOT EXISTS (SELECT 1 FROM placeVisit v WHERE v.placeId = place.id)
                """)
        }
    }
}
