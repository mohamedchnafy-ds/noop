package com.noop.nutrition

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Pins [NutritionSeries] against its Swift twin by ORACLE (personal fork, chantier 8).
 *
 * The expected block is shared verbatim with the Swift suite `NutritionSeriesOracleTests`
 * (`StrandTests/NutritionSeriesOracleTests.swift`): both print the same cases from their own
 * implementation and compare them to this exact text. Do not hand-edit one copy.
 *
 * The cases: days given out of order and a day split across meals (sorted, added in order), binary
 * fractions brought back to one decimal, a meal with no line (a logged day at 0), and NaN, infinity
 * and negatives cleaned by [MealMath.totals].
 */
class NutritionSeriesParityOracleTest {

    /** Shared with the Swift suite. Do not hand-edit: change both copies together. */
    private val expected = """
        2026-10-29 calories_in 195.0
        2026-10-29 protein_g 17.2
        2026-10-29 carbs_g 6.3
        2026-10-29 fat_g 0.6
        2026-10-30 calories_in 0.0
        2026-10-30 protein_g 0.0
        2026-10-30 carbs_g 0.0
        2026-10-30 fat_g 0.0
        2026-10-31 calories_in 0.0
        2026-10-31 protein_g 0.0
        2026-10-31 carbs_g 0.0
        2026-10-31 fat_g 0.0
        2026-11-01 calories_in 650.0
        2026-11-01 protein_g 40.1
        2026-11-01 carbs_g 80.1
        2026-11-01 fat_g 18.1
        2026-11-02 calories_in 750.0
        2026-11-02 protein_g 54.0
        2026-11-02 carbs_g 96.0
        2026-11-02 fat_g 16.0
    """.trimIndent()

    private fun oracle(): String {
        val nan = Double.NaN
        val inf = Double.POSITIVE_INFINITY
        val meals = listOf(
            "2026-11-02" to listOf(MealNutrients(520, 22.0, 82.0, 11.0)),
            "2026-11-01" to listOf(
                MealNutrients(300, 33.0, 0.0, 12.0), MealNutrients(260, 5.0, 57.0, 0.6),
                MealNutrients(90, 2.0, 23.0, 5.4),
            ),
            "2026-11-02" to listOf(MealNutrients(230, 32.0, 14.0, 5.0)),
            "2026-11-01" to listOf(MealNutrients(0, 0.1, 0.1, 0.1)),
            "2026-10-30" to emptyList(),
            "2026-10-31" to listOf(MealNutrients(-5, nan, inf, -1.0)),
            "2026-10-29" to listOf(MealNutrients(100, 0.05, 0.05, 0.05), MealNutrients(0, 0.1, 0.2, 0.3)),
            "2026-10-29" to listOf(MealNutrients(95, 17.0, 6.0, 0.3)),
        )
        return NutritionSeries.nutritionSeriesPoints(meals).joinToString("\n") { "${it.day} ${it.key} ${it.value}" }
    }

    @Test
    fun matchesTheSharedExpectedBlock() {
        assertEquals(expected, oracle())
    }

    @Test
    fun theContractConstants() {
        assertEquals("noop-nutrition", NutritionSeries.NUTRITION_DEVICE_ID)
        assertEquals(listOf("calories_in", "protein_g", "carbs_g", "fat_g"), NutritionSeries.NUTRITION_KEYS)
    }
}
