package com.noop.ui

import com.noop.data.SleepSession
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test
import java.util.Calendar
import java.util.TimeZone

/**
 * Pins the BEDTIME-ONSET consistency fallback (#sleep-consistency-parity) — the score must be
 * byte-identical to iOS `SleepView.consistencySeries` (bedtime-minute rolling-14 SD → 100·(1−sd/120)),
 * NOT the old duration proxy. Runs under a fixed UTC default timezone so the local-time bed-minute is
 * deterministic (both platforms use the device tz; the algorithm — not the tz — is what parity pins).
 */
class SleepConsistencyParityTest {

    private var savedTz: TimeZone? = null

    @Before fun forceUtc() {
        savedTz = TimeZone.getDefault()
        TimeZone.setDefault(TimeZone.getTimeZone("UTC"))
    }

    @After fun restoreTz() { savedTz?.let { TimeZone.setDefault(it) } }

    /** Unix seconds for a given UTC wall-clock (matches the tz the production Calendar reads under). */
    private fun ts(year: Int, month0: Int, day: Int, hour: Int, minute: Int): Long {
        val c = Calendar.getInstance(TimeZone.getTimeZone("UTC"))
        c.clear()
        c.set(year, month0, day, hour, minute, 0)
        return c.timeInMillis / 1000L
    }

    private fun session(startTs: Long) =
        SleepSession(deviceId = "my-whoop", startTs = startTs, endTs = startTs + 8 * 3600)

    @Test fun onsetSpreadScore_matchesTheHandComputedIosValue() {
        // Bedtimes 23:00 / 23:30 / 22:30 → bed-minutes 1380 / 1410 / 1350 (all >= 12h, no wrap).
        // window mean 1380, population variance (0 + 900 + 900)/3 = 600, sd = √600 = 24.49490,
        // score = 100·(1 − 24.49490/120) = 79.58758…  (only the 3rd night has a >=3 window).
        val sessions = listOf(
            session(ts(2026, 5, 1, 23, 0)),
            session(ts(2026, 5, 2, 23, 30)),
            session(ts(2026, 5, 3, 22, 30)),
        )
        val m = consistencySeries(sessions)
        assertEquals(1, m.series.size)
        assertEquals(79.58758, m.latest!!, 1e-4)
        assertEquals(79.58758, m.typical!!, 1e-4)
    }

    @Test fun fewerThanThreeNights_yieldsEmpty() {
        val m = consistencySeries(listOf(session(ts(2026, 5, 1, 23, 0)), session(ts(2026, 5, 2, 23, 0))))
        assertNull(m.latest)
        assertEquals(0, m.series.size)
    }

    /** Order is by startTs (matching iOS repo.sleeps), and the ONSET value uses effectiveStartTs
     *  (startTsAdjusted when a bedtime was hand-edited). */
    @Test fun sortsByStartTs_andReadsEffectiveOnset() {
        val edited = SleepSession(
            deviceId = "my-whoop",
            startTs = ts(2026, 5, 2, 21, 0),               // raw onset 21:00…
            endTs = ts(2026, 5, 3, 5, 0),
            startTsAdjusted = ts(2026, 5, 2, 23, 0),       // …hand-set to 23:00 → this is what counts
        )
        val sessions = listOf(
            session(ts(2026, 5, 1, 23, 0)),
            edited,
            session(ts(2026, 5, 3, 23, 0)),
        )
        // All three effective onsets are 23:00 → zero spread → score 100.
        val m = consistencySeries(sessions)
        assertEquals(100.0, m.latest!!, 1e-9)
    }

    // Personal fork (13 Nov 2026): ONE bedtime per night. The same three cases and expected values as iOS
    // SleepConsistencyNightsTests: a nap used to count as a bedtime and pushed the tile to a fake 0 %.

    private fun block(startTs: Long, minutes: Int) =
        SleepSession(deviceId = "my-whoop", startTs = startTs, endTs = startTs + minutes * 60L)

    @Test fun aNapAmongRegularNights_noLongerReadsZero() {
        val nights = (1..4).map { block(ts(2026, 10, it, 23, 30), 450) }
        val nap = block(ts(2026, 10, 3, 14, 0), 40)
        val m = consistencySeries((nights + nap).sortedBy { it.startTs })
        assertEquals(100.0, m.latest!!, 1e-9)
    }

    @Test fun twoNightsAndANap_areNotEnough() {
        val m = consistencySeries(listOf(
            block(ts(2026, 10, 1, 23, 30), 450),
            block(ts(2026, 10, 2, 23, 30), 450),
            block(ts(2026, 10, 3, 14, 0), 40),
        ))
        assertNull(m.latest)
    }

    @Test fun aRealSpread_isStillScored() {
        // Bedtimes 22:00, 23:00, 00:00 → 1320 / 1380 / 1440, variance 2400 → 100·(1 − √2400/120).
        val m = consistencySeries(listOf(
            block(ts(2026, 10, 1, 22, 0), 420),
            block(ts(2026, 10, 2, 23, 0), 420),
            block(ts(2026, 10, 4, 0, 0), 420),
        ))
        assertEquals(59.1751709536137, m.latest!!, 1e-9)
    }
}
