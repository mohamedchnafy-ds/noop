package com.noop.nutrition

/** Energy and macros of a meal line, a meal or a day: whole kcal, grams to one decimal. */
data class MealNutrients(val kcal: Int, val proteinG: Double, val carbsG: Double, val fatG: Double)

/** A food's values for 100 g, as read from the Ciqual table or a nutrition label. */
data class MealPer100(val kcal: Double, val proteinG: Double, val carbsG: Double, val fatG: Double)

/**
 * The meal journal's arithmetic (personal fork, Nutrition). PARITY: pure and deterministic, the twin
 * of Swift `MealMath` in `Packages/WhoopStore/Sources/WhoopStore/MealLogStore.swift`; both are pinned
 * to one expected block (`MealMathParityOracleTest` here, `MealMathOracleTests` on Apple).
 *
 * It lives beside the future meal screens rather than in `com.noop.data`: Android has no meal screen in
 * this fork, so for now only its oracle test calls it. The values it rounds are the ones stored in
 * `mealItem` ([com.noop.data.MealItemEntity]), which is why it must stay byte-identical to the Swift one.
 *
 * Rounding is half away from zero: [Math.round] here, Swift's `rounded()` there, the same for the
 * non-negative values these functions accept. A negative, NaN or infinite input counts as 0, and an
 * input above [INPUT_CAP] counts as [INPUT_CAP].
 */
object MealMath {

    /** The largest value any input may carry; every result then fits an [Int]. */
    const val INPUT_CAP = 100_000.0

    /**
     * Energy from macros with the 4 / 4 / 9 kcal-per-gram factors, in whole kcal.
     * Swift twin: `MealMath.kcal`.
     */
    fun kcal(proteinG: Double, carbsG: Double, fatG: Double): Int {
        val raw = 4 * clean(proteinG) + 4 * clean(carbsG) + 9 * clean(fatG)
        return Math.round(raw).toInt()
    }

    /**
     * A gram amount kept to one decimal.
     * Swift twin: `MealMath.tenth`.
     */
    fun tenth(grams: Double): Double = Math.round(clean(grams) * 10) / 10.0

    /**
     * The values of [grams] of a food from its values per 100 g: `value × grams / 100`, then whole
     * kcal and macros to one decimal.
     * Swift twin: `MealMath.portion`.
     */
    fun portion(per100: MealPer100, grams: Double): MealNutrients {
        val g = clean(grams)
        return MealNutrients(
            kcal = Math.round(clean(per100.kcal) * g / 100).toInt(),
            proteinG = tenth(clean(per100.proteinG) * g / 100),
            carbsG = tenth(clean(per100.carbsG) * g / 100),
            fatG = tenth(clean(per100.fatG) * g / 100),
        )
    }

    /**
     * The sum of already-rounded lines, added in order, macros brought back to one decimal.
     * Swift twin: `MealMath.totals`.
     */
    fun totals(lines: List<MealNutrients>): MealNutrients {
        var kcal = 0
        var protein = 0.0
        var carbs = 0.0
        var fat = 0.0
        for (line in lines) {
            kcal += maxOf(line.kcal, 0)
            protein += clean(line.proteinG)
            carbs += clean(line.carbsG)
            fat += clean(line.fatG)
        }
        return MealNutrients(kcal, tenth(protein), tenth(carbs), tenth(fat))
    }

    /**
     * An input made safe: NaN, infinite or negative → 0, and at most [INPUT_CAP].
     * Swift twin: `MealMath.clean`.
     */
    internal fun clean(value: Double): Double =
        if (value.isFinite() && value > 0) minOf(value, INPUT_CAP) else 0.0
}
