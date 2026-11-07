package com.noop.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Guards the additive v45 -> v46 Room migration (personal fork, chantier 14 step 2): the `locationPoint`,
 * `place` and `placeVisit` tables, the Android twin of the Swift WhoopStore `v54-places` GRDB migration.
 *
 * The SQL is pinned here against Room's generated shape for the three entities; the column order,
 * affinities, keys and indexes are compared to `schema_oracle.json` by `SchemaOracleTest`, and the chain
 * is opened for real by `WhoopDatabaseUpgradeTest`.
 *
 * Swift twin: `PlaceStoreTests`, which runs the store against a real database.
 */
class PlacesMigrationTest {

    @Test
    fun migration_isAdditive_onlyCreateStatements() {
        val sql = WhoopDatabase.PLACES_SQL
        assertEquals("three tables and two indexes", 5, sql.size)
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
                "CREATE TABLE IF NOT EXISTS `locationPoint` (`ts` INTEGER NOT NULL, `lat` REAL NOT NULL, " +
                    "`lon` REAL NOT NULL, `accuracyM` REAL NOT NULL, `steps` INTEGER, PRIMARY KEY(`ts`))",
                "CREATE TABLE IF NOT EXISTS `place` (`id` TEXT NOT NULL, `name` TEXT, `lat` REAL NOT NULL, " +
                    "`lon` REAL NOT NULL, `radiusM` REAL NOT NULL, `createdAt` INTEGER NOT NULL, PRIMARY KEY(`id`))",
                "CREATE TABLE IF NOT EXISTS `placeVisit` (`id` TEXT NOT NULL, `placeId` TEXT NOT NULL, " +
                    "`arrivedAt` INTEGER NOT NULL, `departedAt` INTEGER, `lat` REAL NOT NULL, `lon` REAL NOT NULL, " +
                    "`accuracyM` REAL NOT NULL, PRIMARY KEY(`id`))",
                "CREATE INDEX IF NOT EXISTS `idx_placeVisit_place_arrivedAt` ON `placeVisit` (`placeId`, `arrivedAt`)",
                "CREATE INDEX IF NOT EXISTS `idx_placeVisit_arrivedAt` ON `placeVisit` (`arrivedAt`)",
            ),
            WhoopDatabase.PLACES_SQL,
        )
    }

    @Test
    fun migration_versionPair_is45to46() {
        assertEquals(45, WhoopDatabase.MIGRATION_45_46.startVersion)
        assertEquals(46, WhoopDatabase.MIGRATION_45_46.endVersion)
        assertTrue(WhoopDatabase.ALL_MIGRATIONS.contains(WhoopDatabase.MIGRATION_45_46))
    }

    @Test
    fun entityDefaults_matchTheGrdbRow() {
        val point = LocationPointEntity(ts = 1_000L, lat = 48.85, lon = 2.35, accuracyM = 65.0)
        assertNull(point.steps)
        val place = PlaceEntity(id = "p", lat = 48.85, lon = 2.35, radiusM = 150.0, createdAt = 1L)
        assertNull(place.name)
        val visit = PlaceVisitEntity(id = "v", placeId = "p", arrivedAt = 1L, lat = 48.85, lon = 2.35,
            accuracyM = 40.0)
        assertNull(visit.departedAt)
    }
}
