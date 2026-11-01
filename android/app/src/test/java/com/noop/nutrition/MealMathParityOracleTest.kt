package com.noop.nutrition

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Pins [MealMath] against its Swift twin by ORACLE (personal fork, Nutrition).
 *
 * The expected block is shared verbatim with the Swift suite `MealMathOracleTests`
 * (`Packages/WhoopStore/Tests/WhoopStoreTests/MealLogStoreTests.swift`): both print the same cases from
 * their own implementation and compare them to this exact text, so neither side can drift alone.
 * Do not hand-edit one copy.
 *
 * These numbers are stored (`mealItem`) and cross the `.noopbak` boundary, so a divergence would be a
 * meal that adds up differently after a restore. The cases sit where the two languages could differ:
 *  - halves (`0.125 g` of protein = 0.5 kcal, `12.5 g` of oil = 112.5 kcal): Swift `rounded()` and
 *    Kotlin [Math.round] both go up for a non-negative half;
 *  - binary fractions (`0.1 + 0.2`, three lines of 0.1 g): the sum is brought back to one decimal;
 *  - NaN, infinity, negatives and values past [MealMath.INPUT_CAP]: clamped the same way.
 */
class MealMathParityOracleTest {

    /** Shared with the Swift suite. Do not hand-edit: change both copies together. */
    private val expected = """
        == kcal ==
        #1 596
        #2 1
        #3 1
        #4 642
        #5 40
        #6 13
        #7 5
        #8 400000
        == tenth ==
        #1 0.1
        #2 1.2
        #3 2.3
        #4 0.0
        #5 123.5
        #6 0.0
        #7 0.0
        #8 1.0
        #9 100000.0
        == portion ==
        #1 231 5.2 50.6 0.7
        #2 249 46.5 0.0 5.4
        #3 78 0.5 17.4 0.3
        #4 113 0.0 0.0 12.5
        #5 0 0.0 0.0 0.0
        #6 0 0.0 0.0 0.0
        #7 0 5.0 5.0 5.0
        #8 130 4.5 19.5 2.3
        == totals ==
        #1 558 52.2 68.0 6.4
        #2 0 0.0 0.0 0.0
        #3 300 0.3 0.6 0.9
        #4 0 0.0 2.0 0.0
    """.trimIndent()

    private fun text(n: MealNutrients) = "${n.kcal} ${n.proteinG} ${n.carbsG} ${n.fatG}"

    private fun oracle(): String {
        val nan = Double.NaN
        val inf = Double.POSITIVE_INFINITY
        val kcalCases = listOf(
            Triple(28.0, 85.0, 16.0), Triple(0.125, 0.0, 0.0), Triple(0.1, 0.2, 0.0),
            Triple(40.0, 80.0, 18.0), Triple(-5.0, 10.0, nan), Triple(inf, 1.0, 1.0),
            Triple(0.0, 0.0, 0.5), Triple(200_000.0, 0.0, 0.0),
        )
        val tenthCases = listOf(0.05, 1.15, 2.25, 0.0, 123.456, nan, -3.0, 0.95, 1e9)
        val portionCases = listOf(
            MealPer100(128.3, 2.9, 28.1, 0.4) to 180.0,
            MealPer100(166.0, 31.0, 0.0, 3.6) to 150.0,
            MealPer100(52.0, 0.3, 11.6, 0.2) to 150.0,
            MealPer100(900.0, 0.0, 0.0, 100.0) to 12.5,
            MealPer100(100.0, 10.0, 10.0, 10.0) to 0.0,
            MealPer100(100.0, 10.0, 10.0, 10.0) to nan,
            MealPer100(-1.0, 5.0, 5.0, 5.0) to 100.0,
            MealPer100(389.0, 13.5, 58.7, 7.0) to 33.3,
        )
        val portions = portionCases.map { (per100, grams) -> MealMath.portion(per100, grams) }
        val totalsCases = listOf(
            portions.take(3),
            emptyList(),
            List(3) { MealNutrients(100, 0.1, 0.2, 0.3) },
            listOf(MealNutrients(-50, -1.0, 2.0, nan)),
        )
        val out = mutableListOf("== kcal ==")
        kcalCases.forEachIndexed { i, (p, c, f) -> out += "#${i + 1} ${MealMath.kcal(p, c, f)}" }
        out += "== tenth =="
        tenthCases.forEachIndexed { i, g -> out += "#${i + 1} ${MealMath.tenth(g)}" }
        out += "== portion =="
        portions.forEachIndexed { i, n -> out += "#${i + 1} ${text(n)}" }
        out += "== totals =="
        totalsCases.forEachIndexed { i, lines -> out += "#${i + 1} ${text(MealMath.totals(lines))}" }
        return out.joinToString("\n")
    }

    @Test
    fun matchesTheSharedExpectedBlock() {
        assertEquals(expected, oracle())
    }
}
