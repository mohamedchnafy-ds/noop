package com.noop.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Guards the additive v43 -> v44 Room migration (personal fork, chantier 8): `meal.planned`, the Android
 * twin of the Swift WhoopStore `v52-meal-planned` GRDB migration. The column's shape is compared to
 * `schema_oracle.json` by `SchemaOracleTest`, and the chain is opened for real by `WhoopDatabaseUpgradeTest`.
 *
 * Swift twin: `MealLogStoreTests.testAPlannedMealIsKeptApartAndCanBeMarkedEaten`.
 */
class MealPlannedMigrationTest {

    @Test
    fun migration_appendsOneNotNullColumnDefaultingToEaten() {
        assertEquals(
            listOf("ALTER TABLE `meal` ADD COLUMN `planned` INTEGER NOT NULL DEFAULT 0"),
            WhoopDatabase.MEAL_PLANNED_SQL,
        )
        for (s in WhoopDatabase.MEAL_PLANNED_SQL) {
            val up = s.uppercase()
            for (banned in listOf("DROP ", "DELETE ", "UPDATE ", "INSERT ")) {
                assertTrue("additive migration must not contain '$banned': $s", !up.contains(banned))
            }
        }
    }

    @Test
    fun migration_versionPair_is43to44() {
        assertEquals(43, WhoopDatabase.MIGRATION_43_44.startVersion)
        assertEquals(44, WhoopDatabase.MIGRATION_43_44.endVersion)
        assertTrue(WhoopDatabase.ALL_MIGRATIONS.contains(WhoopDatabase.MIGRATION_43_44))
    }

    @Test
    fun entityDefault_isEaten() {
        val meal = MealEntity(id = "m", day = "2026-11-03", eatenAt = 1L, name = "Déjeuner",
            origin = "manual", createdAt = 1L, updatedAt = 1L)
        assertEquals(false, meal.planned)
    }
}
