package com.noop.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Guards the additive v47 -> v48 Room migration (personal fork, chantier 24): the `habit` and
 * `habitSession` tables, the Android twin of the Swift WhoopStore `v56-habits` GRDB migration.
 *
 * The SQL is pinned here against Room's generated shape for the entities; the column order, affinities,
 * keys and indices are compared to `schema_oracle.json` by `SchemaOracleTest`, and the chain is opened
 * for real by `WhoopDatabaseUpgradeTest`.
 *
 * Swift twin: `HabitStoreTests`, which runs the store against a real database.
 */
class HabitsMigrationTest {

    @Test
    fun migration_isAdditive_onlyCreateStatements() {
        val sql = WhoopDatabase.HABITS_SQL
        assertEquals("two tables and two indices", 4, sql.size)
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
                "CREATE TABLE IF NOT EXISTS `habit` (`id` TEXT NOT NULL, `name` TEXT NOT NULL, " +
                    "`colorKey` TEXT NOT NULL, `symbol` TEXT NOT NULL, `createdAt` INTEGER NOT NULL, " +
                    "`updatedAt` INTEGER NOT NULL, PRIMARY KEY(`id`))",
                "CREATE TABLE IF NOT EXISTS `habitSession` (`id` TEXT NOT NULL, `habitId` TEXT NOT NULL, " +
                    "`startedAt` INTEGER NOT NULL, `endedAt` INTEGER, `note` TEXT, `manual` INTEGER NOT NULL, " +
                    "`createdAt` INTEGER NOT NULL, `updatedAt` INTEGER NOT NULL, PRIMARY KEY(`id`))",
                "CREATE INDEX IF NOT EXISTS `idx_habitSession_habitId_startedAt` ON `habitSession` (`habitId`, `startedAt`)",
                "CREATE INDEX IF NOT EXISTS `idx_habitSession_startedAt` ON `habitSession` (`startedAt`)",
            ),
            WhoopDatabase.HABITS_SQL,
        )
    }

    @Test
    fun migration_versionPair_is47to48() {
        assertEquals(47, WhoopDatabase.MIGRATION_47_48.startVersion)
        assertEquals(48, WhoopDatabase.MIGRATION_47_48.endVersion)
        assertTrue(WhoopDatabase.ALL_MIGRATIONS.contains(WhoopDatabase.MIGRATION_47_48))
    }

    @Test
    fun entityDefaults_matchTheGrdbRow() {
        val session = HabitSessionEntity(id = "s", habitId = "h", startedAt = 1_000L, createdAt = 1_000L,
            updatedAt = 1_000L)
        assertNull("a session with no end is still running", session.endedAt)
        assertNull("no note by default", session.note)
        assertFalse("timed by the stopwatch by default", session.manual)
    }
}
