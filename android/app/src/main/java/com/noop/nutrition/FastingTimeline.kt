package com.noop.nutrition

/**
 * FastingTimeline — the pure arithmetic of an intermittent fast (personal fork, chantier 15).
 *
 * Kotlin twin of the Swift `FastingTimeline` (StrandAnalytics); keep every threshold, integer division
 * and clamp BYTE-IDENTICAL. A fast is three stored values (start, end, goal in minutes; the `fast` table
 * of [com.noop.data.FastEntity]); the phase reached, the progress, what remains, the ring markers and the
 * history figures are all derived here. Integer minutes in, integers out; no clock, no store, no strings.
 *
 * The phases are the usual indicative landmarks of the fasting literature (hours since the last meal),
 * NOT a measurement and NOT medical advice: 0 digestion · 4 insulin drop · 8 glycogen running low ·
 * 12 fat burning · 16 ketosis · 24 autophagy.
 *
 * The fasting screens are iPhone only in this fork, so nothing on Android calls this yet; like `MealMath`,
 * the twin lives in `com.noop.nutrition`, outside the parity ledger's governed roots, and is checked
 * against the same shared expected block as the Swift suite (`FastingTimelineTest`).
 */
object FastingTimeline {

    /** Hour at which each phase starts, in the order of [phaseIds]. */
    val phaseStartHours: List<Int> = listOf(0, 4, 8, 12, 16, 24)

    /** Stable identifiers of the phases. */
    val phaseIds: List<String> = listOf("digestion", "insulinDrop", "glycogen", "fatBurn", "ketosis", "autophagy")

    /** Goal bounds, minutes: 12 h to 36 h; 16 h the first time. */
    const val MIN_GOAL_MINUTES: Int = 720
    const val MAX_GOAL_MINUTES: Int = 2160
    const val DEFAULT_GOAL_MINUTES: Int = 960

    /** The quick picks offered next to the wheel, hours. */
    val quickGoalHours: List<Int> = listOf(14, 16, 18, 20)

    /** Where a phase starts on the ring: permille of the goal (0..1000). */
    data class FastingMarker(val phaseIndex: Int, val permille: Int)

    /** History figures over a run of days (one duration per day, 0 = no fast that day). */
    data class FastingSummary(val averageMinutes: Int, val keptCount: Int, val fastedCount: Int, val streak: Int)

    /** Index in [phaseIds] of the phase reached after `elapsedMinutes` (negative counts as 0). */
    fun fastingPhaseIndex(elapsedMinutes: Int): Int {
        val elapsed = maxOf(elapsedMinutes, 0)
        var index = 0
        for ((i, hour) in phaseStartHours.withIndex()) if (elapsed >= hour * 60) index = i
        return index
    }

    /** Progress toward the goal in permille, 0..1000 (integer division); 0 for a goal of 0 or less. */
    fun fastingProgressPermille(elapsedMinutes: Int, goalMinutes: Int): Int {
        if (goalMinutes <= 0) return 0
        val elapsed = maxOf(elapsedMinutes, 0)
        return minOf(1000, (elapsed * 1000) / goalMinutes)
    }

    /** Minutes left before the goal, never negative. */
    fun fastingRemainingMinutes(elapsedMinutes: Int, goalMinutes: Int): Int =
        maxOf(0, goalMinutes - maxOf(elapsedMinutes, 0))

    /** The phase starts that fall inside the goal, as permille of the goal, in phase order. */
    fun fastingMarkers(goalMinutes: Int): List<FastingMarker> {
        if (goalMinutes <= 0) return emptyList()
        val out = ArrayList<FastingMarker>()
        for (i in 1 until phaseStartHours.size) {
            val start = phaseStartHours[i] * 60
            if (start <= goalMinutes) out.add(FastingMarker(i, (start * 1000) / goalMinutes))
        }
        return out
    }

    /** History figures over `durationsMinutes`, one per day oldest first (0 = no fast). */
    fun fastingSummary(durationsMinutes: List<Int>, goalMinutes: Int): FastingSummary {
        val fasted = durationsMinutes.filter { it > 0 }
        val average = if (fasted.isEmpty()) 0 else fasted.sum() / fasted.size
        val kept = if (goalMinutes > 0) durationsMinutes.count { it >= goalMinutes } else 0
        var streak = 0
        for (duration in durationsMinutes.asReversed()) {
            if (goalMinutes > 0 && duration >= goalMinutes) streak += 1 else break
        }
        return FastingSummary(average, kept, fasted.size, streak)
    }

    /** A goal kept within the bounds, minutes. */
    fun clampGoalMinutes(minutes: Int): Int = minOf(MAX_GOAL_MINUTES, maxOf(MIN_GOAL_MINUTES, minutes))
}
