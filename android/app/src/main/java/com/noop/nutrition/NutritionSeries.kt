package com.noop.nutrition

/**
 * The meal journal's day totals as a metric series (personal fork, chantier 8, lot 3). PARITY: the twin of
 * Swift `NutritionSeries` in `Strand/Data/NutritionSeries.swift`; both are pinned to one expected block
 * (`NutritionSeriesParityOracleTest` here, `NutritionSeriesOracleTests` on Apple).
 *
 * Storage contract, identical on both platforms because the rows cross the `.noopbak` boundary:
 *  - rows live in `metricSeries` under the dedicated source id [NUTRITION_DEVICE_ID] ("noop-nutrition"),
 *    never "nutrition-csv", so an import and the journal can never overwrite each other;
 *  - four keys per day ([NUTRITION_KEYS], the CSV import's names): calories_in in whole kcal, protein_g,
 *    carbs_g and fat_g to one decimal, the day's lines added by [MealMath.totals];
 *  - a day with no meal has no row (a hole, never 0).
 *
 * Android has no meal screen in this fork, so only its oracle test calls it, like [MealMath].
 */
object NutritionSeries {

    /** Dedicated source id (the `deviceId` column) of the journal's day totals. */
    const val NUTRITION_DEVICE_ID = "noop-nutrition"

    /** The four keys, in the order a day's points are written. */
    val NUTRITION_KEYS = listOf("calories_in", "protein_g", "carbs_g", "fat_g")

    /** One stored point: the day ("yyyy-MM-dd"), its key and its value. */
    data class SeriesPoint(val day: String, val key: String, val value: Double)

    /**
     * The points of every day that has at least one meal, by day then in [NUTRITION_KEYS] order. Each
     * day's lines are added in the order given (meals as eaten, then their lines).
     * Swift twin: `NutritionSeries.nutritionSeriesPoints`.
     */
    fun nutritionSeriesPoints(meals: List<Pair<String, List<MealNutrients>>>): List<SeriesPoint> {
        val byDay = LinkedHashMap<String, MutableList<MealNutrients>>()
        for ((day, lines) in meals) byDay.getOrPut(day) { mutableListOf() }.addAll(lines)
        return byDay.keys.sorted().flatMap { day ->
            val total = MealMath.totals(byDay[day].orEmpty())
            listOf(
                SeriesPoint(day, "calories_in", total.kcal.toDouble()),
                SeriesPoint(day, "protein_g", total.proteinG),
                SeriesPoint(day, "carbs_g", total.carbsG),
                SeriesPoint(day, "fat_g", total.fatG),
            )
        }
    }
}
