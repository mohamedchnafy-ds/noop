package com.noop.data

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

/**
 * Habits (personal fork, chantier 24) — the Room half of GRDB's `v56-habits` (`HabitStore.swift`), added
 * by [WhoopDatabase.MIGRATION_47_48].
 *
 * A habit is a category the wearer creates (reading, meditation…); a session stores WHEN only (start,
 * end null while the stopwatch runs) plus an optional free note. Totals and charts are derived by the
 * iPhone app, never stored. No `deviceId`: a habit belongs to the person.
 *
 * WHAT THIS DELIBERATELY IS NOT. There is no DAO and no Compose UI here: the habits section is iPhone
 * only in this fork. What lands is the half that keeps a `.noopbak` portable — the schema, pinned by
 * `SchemaOracleTest` against the same `schema_oracle.json` the GRDB suite checks.
 *
 * FIELD ORDER IS THE CONTRACT: each class follows its GRDB `create(table:)` column order exactly. The
 * text `id` is a non-null `String`, which is the existing `sqlite-text-pk-nullable` ledger entry.
 */
@Entity(tableName = "habit")
data class HabitEntity(
    @PrimaryKey
    val id: String,
    /** What the wearer called it. */
    val name: String,
    /** A palette key ("cyan", "violet"…). */
    val colorKey: String,
    /** An SF Symbol name. */
    val symbol: String,
    /** Unix seconds. */
    val createdAt: Long,
    /** Unix seconds. */
    val updatedAt: Long,
)

/** One session of a habit (`habitSession`). See [HabitEntity]. */
@Entity(
    tableName = "habitSession",
    indices = [
        Index(name = "idx_habitSession_habitId_startedAt", value = ["habitId", "startedAt"]),
        Index(name = "idx_habitSession_startedAt", value = ["startedAt"]),
    ],
)
data class HabitSessionEntity(
    @PrimaryKey
    val id: String,
    /** The habit it belongs to ([HabitEntity.id]). */
    val habitId: String,
    /** Unix seconds. */
    val startedAt: Long,
    /** Unix seconds; null while the stopwatch runs. */
    val endedAt: Long? = null,
    /** The wearer's free note; null when there is none. */
    val note: String? = null,
    /** True for a session added by hand after the fact. */
    val manual: Boolean = false,
    /** Unix seconds. */
    val createdAt: Long,
    /** Unix seconds. */
    val updatedAt: Long,
)
