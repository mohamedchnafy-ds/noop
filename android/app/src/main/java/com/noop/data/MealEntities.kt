package com.noop.data

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

/**
 * The meal journal (personal fork, Nutrition) — the Room half of GRDB's `v51-meal-log`
 * (`MealLogStore.swift`), added by [WhoopDatabase.MIGRATION_42_43].
 *
 * Two tables joined by id, like the Lift Log: `meal` is one entry of the journal and carries NO
 * nutrient of its own; `mealItem` is one line of it, with its values for the quantity eaten (rounded
 * once at write by [com.noop.nutrition.MealMath]) and, when the food came from a table or a label,
 * its values per 100 g. A meal's energy and macros are the sum of its lines, computed on read
 * ([com.noop.nutrition.MealMath.totals]).
 *
 * No `deviceId`: a meal belongs to the person, not to a strap, so it needs no re-keying when a strap
 * changes.
 *
 * WHAT THIS DELIBERATELY IS NOT. There is no DAO and no Compose UI here: the meal screens are iPhone
 * only in this fork. What lands is the half that keeps a `.noopbak` portable — the schema, pinned by
 * `SchemaOracleTest` against the same `schema_oracle.json` the GRDB suite checks — and the arithmetic
 * any future Android screen must share, pinned by `MealMathParityOracleTest`.
 *
 * FIELD ORDER IS THE CONTRACT: each class follows its GRDB `create(table:)` column order exactly.
 * `favorite` and `gramsEstimated` carry `@ColumnInfo(defaultValue = "0")` because GRDB declares them
 * NOT NULL DEFAULT 0 (a Kotlin constructor default never reaches the schema). Each `id` is a non-null
 * `String`, which is the existing `sqlite-text-pk-nullable` ledger entry.
 */
@Entity(
    tableName = "meal",
    indices = [
        Index(name = "idx_meal_day_eatenAt", value = ["day", "eatenAt"]),
    ],
)
data class MealEntity(
    @PrimaryKey
    val id: String,
    /** The local day it was eaten, "yyyy-MM-dd". */
    val day: String,
    /** Unix seconds. */
    val eatenAt: Long,
    val name: String,
    /** "manual" | "photo" | "voice" | "barcode" (Swift `MealOrigin`). A stored-data contract. */
    val origin: String,
    @ColumnInfo(defaultValue = "0")
    val favorite: Boolean = false,
    val createdAt: Long,
    val updatedAt: Long,
)

/** One line of a meal, e.g. "basmati rice, cooked · 180 g". */
@Entity(
    tableName = "mealItem",
    indices = [
        Index(name = "idx_mealItem_meal_ord", value = ["mealId", "ord"]),
        Index(name = "idx_mealItem_foodRef", value = ["foodRef"]),
    ],
)
data class MealItemEntity(
    @PrimaryKey
    val id: String,
    val mealId: String,
    /** Position within the meal. */
    val ord: Int,
    val name: String,
    /** Null for a line typed by hand with no quantity. */
    val grams: Double? = null,
    /** True when the quantity was read off a photo ("≈"). */
    @ColumnInfo(defaultValue = "0")
    val gramsEstimated: Boolean = false,
    val kcal: Int,
    val proteinG: Double,
    val carbsG: Double,
    val fatG: Double,
    /** "ciqual:<code>" or "ean:<barcode>"; null for a line typed by hand. */
    val foodRef: String? = null,
    val kcalPer100g: Double? = null,
    val proteinPer100g: Double? = null,
    val carbsPer100g: Double? = null,
    val fatPer100g: Double? = null,
)
