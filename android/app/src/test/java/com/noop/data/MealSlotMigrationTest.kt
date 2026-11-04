package com.noop.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Guards the additive v44 -> v45 Room migration (personal fork, chantier 9): `meal.slot`, the Android
 * twin of the Swift WhoopStore `v53-meal-slot` GRDB migration. The column's shape is compared to
 * `schema_oracle.json` by `SchemaOracleTest`, and the chain is opened for real by `WhoopDatabaseUpgradeTest`.
 *
 * Swift twin: `MealLogStoreTests.testAMealKeepsItsSlotAndOlderMealsHaveNone`.
 */
class MealSlotMigrationTest {

    @Test
    fun migration_appendsOneNullableTextColumn() {
        assertEquals(listOf("ALTER TABLE `meal` ADD COLUMN `slot` TEXT"), WhoopDatabase.MEAL_SLOT_SQL)
        for (s in WhoopDatabase.MEAL_SLOT_SQL) {
            val up = s.uppercase()
            for (banned in listOf("DROP ", "DELETE ", "UPDATE ", "INSERT ", "NOT NULL")) {
                assertTrue("additive nullable migration must not contain '$banned': $s", !up.contains(banned))
            }
        }
    }

    @Test
    fun migration_versionPair_is44to45() {
        assertEquals(44, WhoopDatabase.MIGRATION_44_45.startVersion)
        assertEquals(45, WhoopDatabase.MIGRATION_44_45.endVersion)
        assertTrue(WhoopDatabase.ALL_MIGRATIONS.contains(WhoopDatabase.MIGRATION_44_45))
    }

    @Test
    fun entityDefault_hasNoSlot() {
        val meal = MealEntity(id = "m", day = "2026-11-04", eatenAt = 1L, name = "Déjeuner",
            origin = "manual", createdAt = 1L, updatedAt = 1L)
        assertNull(meal.slot)
        assertEquals("lunch", meal.copy(slot = "lunch").slot)
    }
}
