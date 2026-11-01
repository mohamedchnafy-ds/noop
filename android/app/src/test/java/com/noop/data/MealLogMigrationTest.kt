package com.noop.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Guards the additive v42 -> v43 Room migration (personal fork, Nutrition): the `meal` and `mealItem`
 * tables, the Android twin of the Swift WhoopStore `v51-meal-log` GRDB migration.
 *
 * The SQL is pinned here against Room's generated shape for [MealEntity] and [MealItemEntity]; the
 * column order, affinities, defaults, keys and indexes are compared to `schema_oracle.json` by
 * `SchemaOracleTest`, and the chain is opened for real by `WhoopDatabaseUpgradeTest`.
 *
 * Swift twin: `MealLogStoreTests`, which runs the store against a real database.
 */
class MealLogMigrationTest {

    @Test
    fun migration_isAdditive_onlyCreateStatements() {
        val sql = WhoopDatabase.MEAL_LOG_SQL
        assertEquals("two tables and three indexes", 5, sql.size)
        for (s in sql) {
            val up = s.trimStart().uppercase()
            assertTrue("only CREATE TABLE / CREATE INDEX allowed, got: $s",
                up.startsWith("CREATE TABLE IF NOT EXISTS") || up.startsWith("CREATE INDEX IF NOT EXISTS"))
            for (banned in listOf("DROP ", "DELETE ", "UPDATE ", "INSERT ", "ALTER ")) {
                assertTrue("additive migration must not contain '$banned': $s", !up.contains(banned))
            }
        }
    }

    @Test
    fun migration_createsExactTables() {
        assertEquals(
            listOf(
                "CREATE TABLE IF NOT EXISTS `meal` (`id` TEXT NOT NULL, `day` TEXT NOT NULL, " +
                    "`eatenAt` INTEGER NOT NULL, `name` TEXT NOT NULL, `origin` TEXT NOT NULL, " +
                    "`favorite` INTEGER NOT NULL DEFAULT 0, `createdAt` INTEGER NOT NULL, " +
                    "`updatedAt` INTEGER NOT NULL, PRIMARY KEY(`id`))",
                "CREATE INDEX IF NOT EXISTS `idx_meal_day_eatenAt` ON `meal` (`day`, `eatenAt`)",
                "CREATE TABLE IF NOT EXISTS `mealItem` (`id` TEXT NOT NULL, `mealId` TEXT NOT NULL, " +
                    "`ord` INTEGER NOT NULL, `name` TEXT NOT NULL, `grams` REAL, " +
                    "`gramsEstimated` INTEGER NOT NULL DEFAULT 0, `kcal` INTEGER NOT NULL, " +
                    "`proteinG` REAL NOT NULL, `carbsG` REAL NOT NULL, `fatG` REAL NOT NULL, `foodRef` TEXT, " +
                    "`kcalPer100g` REAL, `proteinPer100g` REAL, `carbsPer100g` REAL, `fatPer100g` REAL, " +
                    "PRIMARY KEY(`id`))",
                "CREATE INDEX IF NOT EXISTS `idx_mealItem_meal_ord` ON `mealItem` (`mealId`, `ord`)",
                "CREATE INDEX IF NOT EXISTS `idx_mealItem_foodRef` ON `mealItem` (`foodRef`)",
            ),
            WhoopDatabase.MEAL_LOG_SQL,
        )
    }

    @Test
    fun migration_versionPair_is42to43() {
        assertEquals(42, WhoopDatabase.MIGRATION_42_43.startVersion)
        assertEquals(43, WhoopDatabase.MIGRATION_42_43.endVersion)
        assertTrue(WhoopDatabase.ALL_MIGRATIONS.contains(WhoopDatabase.MIGRATION_42_43))
    }

    @Test
    fun entityDefaults_matchTheGrdbRow() {
        val meal = MealEntity(id = "m", day = "2026-11-01", eatenAt = 1L, name = "Déjeuner",
            origin = "photo", createdAt = 1L, updatedAt = 1L)
        assertEquals(false, meal.favorite)
        val line = MealItemEntity(id = "i", mealId = "m", ord = 0, name = "Riz", kcal = 231,
            proteinG = 5.2, carbsG = 50.6, fatG = 0.7)
        assertEquals(null, line.grams)
        assertEquals(false, line.gramsEstimated)
        assertEquals(null, line.foodRef)
        assertEquals(null, line.kcalPer100g)
    }
}
