import XCTest
@testable import Strand
import WhoopStore

/// Pins `NutritionSeries` against its Kotlin twin by ORACLE (personal fork, chantier 8). The expected block
/// is shared verbatim with `NutritionSeriesParityOracleTest`
/// (`android/app/src/test/java/com/noop/nutrition/NutritionSeriesParityOracleTest.kt`): both print the same
/// cases from their own implementation. Do not hand-edit one copy. The rows cross the `.noopbak` boundary.
final class NutritionSeriesOracleTests: XCTestCase {

    /// Shared with the Kotlin suite. Do not hand-edit: change both copies together.
    private let expected = """
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
        """

    private func oracle() -> String {
        let nan = Double.nan
        let inf = Double.infinity
        let meals: [(day: String, lines: [MealNutrients])] = [
            ("2026-11-02", [MealNutrients(kcal: 520, proteinG: 22, carbsG: 82, fatG: 11)]),
            ("2026-11-01", [MealNutrients(kcal: 300, proteinG: 33, carbsG: 0, fatG: 12),
                            MealNutrients(kcal: 260, proteinG: 5, carbsG: 57, fatG: 0.6),
                            MealNutrients(kcal: 90, proteinG: 2, carbsG: 23, fatG: 5.4)]),
            ("2026-11-02", [MealNutrients(kcal: 230, proteinG: 32, carbsG: 14, fatG: 5)]),
            ("2026-11-01", [MealNutrients(kcal: 0, proteinG: 0.1, carbsG: 0.1, fatG: 0.1)]),
            ("2026-10-30", []),
            ("2026-10-31", [MealNutrients(kcal: -5, proteinG: nan, carbsG: inf, fatG: -1)]),
            ("2026-10-29", [MealNutrients(kcal: 100, proteinG: 0.05, carbsG: 0.05, fatG: 0.05),
                            MealNutrients(kcal: 0, proteinG: 0.1, carbsG: 0.2, fatG: 0.3)]),
            ("2026-10-29", [MealNutrients(kcal: 95, proteinG: 17, carbsG: 6, fatG: 0.3)]),
        ]
        return NutritionSeries.nutritionSeriesPoints(meals)
            .map { point in "\(point.day) \(point.key) \(point.value)" }
            .joined(separator: "\n")
    }

    func testMatchesTheSharedExpectedBlock() {
        XCTAssertEqual(oracle(), expected)
    }

    func testTheContractConstants() {
        XCTAssertEqual(NutritionSeries.nutritionDeviceId, "noop-nutrition")
        XCTAssertEqual(NutritionSeries.nutritionKeys, ["calories_in", "protein_g", "carbs_g", "fat_g"])
    }

    /// A day emptied of its last meal loses its four points; a day still logged keeps them (upserted).
    func testAnEmptiedDayIsDeletedNotZeroed() {
        let stored = ["2026-11-01", "2026-11-02"].flatMap { day in
            NutritionSeries.nutritionKeys.map { MetricPoint(day: day, key: $0, value: 1) }
        }
        let fresh = NutritionSeries.nutritionSeriesPoints(
            [(day: "2026-11-02", lines: [MealNutrients(kcal: 100, proteinG: 1, carbsG: 1, fatG: 1)])])
        let stale = NutritionSeries.staleSeriesPoints(stored: stored, fresh: fresh)
        XCTAssertEqual(stale.map(\.day), Array(repeating: "2026-11-01", count: 4))
        XCTAssertEqual(stale.map(\.key), NutritionSeries.nutritionKeys)
    }

    func testTheExplorerListsTheJournalSeries() {
        for key in NutritionSeries.nutritionKeys {
            XCTAssertNotNil(MetricCatalog.metric(key: key, source: NutritionSeries.nutritionDeviceId), key)
        }
    }
}
