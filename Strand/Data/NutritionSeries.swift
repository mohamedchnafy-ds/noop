import Foundation
import WhoopStore

// Personal fork, chantier 8 (lot 3): the meal journal's day totals as a metric series, so Analyses
// (Explore, Compare, the correlation scan) can read what was eaten beside what the strap measured.
//
// Storage contract (PARITY, twin of Kotlin `com.noop.nutrition.NutritionSeries`, both pinned by one shared
// oracle block, `NutritionSeriesOracleTests` here and `NutritionSeriesParityOracleTest` there):
// - rows live in `metricSeries` under the dedicated source id "noop-nutrition", never "nutrition-csv" (an
//   import can then never overwrite the journal, nor the journal an import);
// - four keys per day, the names the CSV import uses: calories_in (whole kcal), protein_g, carbs_g, fat_g
//   (one decimal), the day's lines added by `MealMath.totals`, exactly the figures the day page shows;
// - a day with no meal has NO row (a hole, never 0): a day emptied of its last meal loses its rows;
// - only EATEN meals count: a planned meal (a menu) adds nothing until it is marked eaten;
// - the series is rebuilt from the journal, so it always says what the journal says (after every write,
//   and once after an update that brings the series in, for the meals written before it).

enum NutritionSeries {

    /// Dedicated source id (the `deviceId` column) of the journal's day totals.
    static let nutritionDeviceId = "noop-nutrition"

    /// The four keys, in the order a day's points are written.
    static let nutritionKeys = ["calories_in", "protein_g", "carbs_g", "fat_g"]

    /// Set once the series has been rebuilt from the whole journal on this install.
    static let backfillKey = "nutrition.seriesBackfilled.v1"

    /// The points of every day that has at least one meal, by day then in `nutritionKeys` order. Each day's
    /// lines are added in the order given (meals as eaten, then their lines), as `NutritionDaySummary.eaten`.
    static func nutritionSeriesPoints(_ meals: [(day: String, lines: [MealNutrients])]) -> [MetricPoint] {
        var order: [String] = []
        var byDay: [String: [MealNutrients]] = [:]
        for meal in meals {
            if byDay[meal.day] == nil {
                order.append(meal.day)
                byDay[meal.day] = []
            }
            byDay[meal.day]?.append(contentsOf: meal.lines)
        }
        return order.sorted().flatMap { day -> [MetricPoint] in
            let total = MealMath.totals(byDay[day] ?? [])
            return [MetricPoint(day: day, key: "calories_in", value: Double(total.kcal)),
                    MetricPoint(day: day, key: "protein_g", value: total.proteinG),
                    MetricPoint(day: day, key: "carbs_g", value: total.carbsG),
                    MetricPoint(day: day, key: "fat_g", value: total.fatG)]
        }
    }

    /// The stored points the fresh set no longer has (a day emptied of its meals), to delete.
    static func staleSeriesPoints(stored: [MetricPoint], fresh: [MetricPoint]) -> [MetricPoint] {
        let kept = Set(fresh.map { $0.key + "|" + $0.day })
        return stored.filter { !kept.contains($0.key + "|" + $0.day) }
    }

    /// Rebuild the series from the whole journal: upsert every logged day, delete the days left empty.
    static func rebuildNutritionSeries(_ store: WhoopStore) async {
        guard let meals = try? await MealJournal.mealJournalRange(store, fromDay: "0000-01-01", toDay: "9999-12-31")
        else { return }
        let fresh = nutritionSeriesPoints(meals.map { (day: $0.meal.day, lines: $0.items.map(\.nutrients)) })
        var stored: [MetricPoint] = []
        for key in nutritionKeys {
            stored += (try? await store.metricSeries(deviceId: nutritionDeviceId, key: key,
                                                     from: "0000-01-01", to: "9999-12-31")) ?? []
        }
        for point in staleSeriesPoints(stored: stored, fresh: fresh) {
            _ = try? await store.deleteMetricSeriesPoint(deviceId: nutritionDeviceId, day: point.day, key: point.key)
        }
        if !fresh.isEmpty {
            _ = try? await store.upsertMetricSeries(fresh, deviceId: nutritionDeviceId)
        }
    }

    /// The one-time rebuild for meals written before the series existed.
    @MainActor
    static func backfillNutritionSeriesIfNeeded(_ repo: Repository, defaults: UserDefaults = .standard) async {
        guard !defaults.bool(forKey: backfillKey), let store = await repo.storeHandle() else { return }
        await rebuildNutritionSeries(store)
        defaults.set(true, forKey: backfillKey)
    }
}
