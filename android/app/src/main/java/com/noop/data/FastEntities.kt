package com.noop.data

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

/**
 * Intermittent fasts (personal fork, chantier 15) — the Room half of GRDB's `v55-fasts`
 * (`FastStore.swift`), added by [WhoopDatabase.MIGRATION_46_47].
 *
 * A fast stores WHEN only: its start (the last meal, editable after the fact), its end (null while it
 * is going) and the duration aimed at, in minutes. The phases, the progress and the history are derived
 * by [com.noop.nutrition.FastingTimeline], never stored. No `deviceId`: a fast belongs to the person.
 *
 * WHAT THIS DELIBERATELY IS NOT. There is no DAO and no Compose UI here: the fasting section and its
 * screens are iPhone only in this fork. What lands is the half that keeps a `.noopbak` portable — the
 * schema, pinned by `SchemaOracleTest` against the same `schema_oracle.json` the GRDB suite checks.
 *
 * FIELD ORDER IS THE CONTRACT: the class follows its GRDB `create(table:)` column order exactly. The text
 * `id` is a non-null `String`, which is the existing `sqlite-text-pk-nullable` ledger entry.
 */
@Entity(
    tableName = "fast",
    indices = [Index(name = "idx_fast_startedAt", value = ["startedAt"])],
)
data class FastEntity(
    @PrimaryKey
    val id: String,
    /** Unix seconds: the last meal. */
    val startedAt: Long,
    /** Unix seconds; null while the fast is still going. */
    val endedAt: Long? = null,
    /** The duration aimed at, minutes (16 h = 960). */
    val goalMinutes: Int,
    /** Unix seconds. */
    val createdAt: Long,
    /** Unix seconds. */
    val updatedAt: Long,
)
