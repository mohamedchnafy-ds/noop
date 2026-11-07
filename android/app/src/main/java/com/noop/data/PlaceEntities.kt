package com.noop.data

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

/**
 * Positions, places and visits (personal fork, chantier 14 step 2) — the Room half of GRDB's
 * `v54-places` (`PlaceStore.swift`), added by [WhoopDatabase.MIGRATION_45_46].
 *
 * A point or a visit stores WHERE and WHEN only; the metrics shown per place are read by time from the
 * strap's data. No `deviceId`: a position belongs to the person, not to a strap.
 *
 * WHAT THIS DELIBERATELY IS NOT. There is no DAO and no Compose UI here: the place tracking and its
 * screens are iPhone only in this fork. What lands is the half that keeps a `.noopbak` portable — the
 * schema, pinned by `SchemaOracleTest` against the same `schema_oracle.json` the GRDB suite checks.
 *
 * FIELD ORDER IS THE CONTRACT: each class follows its GRDB `create(table:)` column order exactly. Each
 * text `id` is a non-null `String`, which is the existing `sqlite-text-pk-nullable` ledger entry.
 */
@Entity(tableName = "locationPoint")
data class LocationPointEntity(
    /** Unix milliseconds. */
    @PrimaryKey
    val ts: Long,
    val lat: Double,
    val lon: Double,
    /** Horizontal accuracy, metres. */
    val accuracyM: Double,
    /** The phone pedometer's steps since the previous point; null when unknown. */
    val steps: Int? = null,
)

/** A spot where the wearer stays: the centre and radius (metres) of the zone its visits fall in. */
@Entity(tableName = "place")
data class PlaceEntity(
    @PrimaryKey
    val id: String,
    /** The name the wearer gave it; null until then. */
    val name: String? = null,
    val lat: Double,
    val lon: Double,
    val radiusM: Double,
    /** Unix seconds. */
    val createdAt: Long,
)

/** One stay at a place; unix seconds, `departedAt` null while the wearer is still there. */
@Entity(
    tableName = "placeVisit",
    indices = [
        Index(name = "idx_placeVisit_place_arrivedAt", value = ["placeId", "arrivedAt"]),
        Index(name = "idx_placeVisit_arrivedAt", value = ["arrivedAt"]),
    ],
)
data class PlaceVisitEntity(
    @PrimaryKey
    val id: String,
    val placeId: String,
    val arrivedAt: Long,
    val departedAt: Long? = null,
    val lat: Double,
    val lon: Double,
    val accuracyM: Double,
)
