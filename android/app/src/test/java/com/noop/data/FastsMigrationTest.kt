package com.noop.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Guards the additive v46 -> v47 Room migration (personal fork, chantier 15): the `fast` table, the
 * Android twin of the Swift WhoopStore `v55-fasts` GRDB migration.
 *
 * The SQL is pinned here against Room's generated shape for the entity; the column order, affinities,
 * key and index are compared to `schema_oracle.json` by `SchemaOracleTest`, and the chain is opened for
 * real by `WhoopDatabaseUpgradeTest`.
 *
 * Swift twin: `FastStoreTests`, which runs the store against a real database.
 */
class FastsMigrationTest {

    @Test
    fun migration_isAdditive_onlyCreateStatements() {
        val sql = WhoopDatabase.FASTS_SQL
        assertEquals("one table and one index", 2, sql.size)
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
    fun migration_createsExactTable() {
        assertEquals(
            listOf(
                "CREATE TABLE IF NOT EXISTS `fast` (`id` TEXT NOT NULL, `startedAt` INTEGER NOT NULL, " +
                    "`endedAt` INTEGER, `goalMinutes` INTEGER NOT NULL, `createdAt` INTEGER NOT NULL, " +
                    "`updatedAt` INTEGER NOT NULL, PRIMARY KEY(`id`))",
                "CREATE INDEX IF NOT EXISTS `idx_fast_startedAt` ON `fast` (`startedAt`)",
            ),
            WhoopDatabase.FASTS_SQL,
        )
    }

    @Test
    fun migration_versionPair_is46to47() {
        assertEquals(46, WhoopDatabase.MIGRATION_46_47.startVersion)
        assertEquals(47, WhoopDatabase.MIGRATION_46_47.endVersion)
        assertTrue(WhoopDatabase.ALL_MIGRATIONS.contains(WhoopDatabase.MIGRATION_46_47))
    }

    @Test
    fun entityDefaults_matchTheGrdbRow() {
        val fast = FastEntity(id = "f", startedAt = 1_000L, goalMinutes = 960, createdAt = 1_000L, updatedAt = 1_000L)
        assertNull("a fast with no end is still going", fast.endedAt)
        assertEquals(960, fast.goalMinutes)
    }
}
