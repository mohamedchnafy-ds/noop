import XCTest
@testable import Strand
import StrandAnalytics
import WhoopProtocol
import WhoopStore

/// The Nutrition screens' arithmetic (personal fork): the basal metabolic rate against the calorie
/// estimator's own resting rate, the reference expenditure, the intake goal and its rounding, the macro
/// goals, the day's eaten / balance figures, the Today day window, and reading a typed number.
final class NutritionGoalsTests: XCTestCase {

    // MARK: Basal metabolic rate

    /// The basal rate the Goals screen writes out is exactly the resting rate the calorie estimator
    /// charges: a still day of heart rate, scaled to 24 h, gives the same kcal for every sex.
    func testBasalRateIsTheEstimatorsRestingRate() {
        let samples = stride(from: 0, through: 3_600, by: 1).map { HRSample(ts: 1_000_000 + $0, bpm: 50) }
        for sex in ["male", "female", "nonbinary"] {
            let profile = UserProfile(weightKg: 80, heightCm: 178, age: 30, sex: sex)
            let energy = Calories.estimateDayEnergy(samples, profile: profile, hrmax: 190, restingHR: 60)
            XCTAssertEqual(energy.activeKcal, 0, "50 bpm stays under the active gate")
            let perDay = energy.restingKcal / energy.observedSeconds * 86_400
            let basal = NutritionGoals.basalKcalPerDay(NutritionGoals.Body(sex: sex, weightKg: 80, heightCm: 178, age: 30))
            XCTAssertEqual(basal, perDay, accuracy: 1e-6, sex)
        }
    }

    func testBasalRateOfTheMockupProfile() {
        // 88.362 + 13.397 × 80 + 4.799 × 178 − 5.677 × 30 = 1 844.034
        let basal = NutritionGoals.basalKcalPerDay(NutritionGoals.Body(sex: "male", weightKg: 80, heightCm: 178, age: 30))
        XCTAssertEqual(basal, 1_844.034, accuracy: 1e-9)
    }

    func testUnsetProfileValuesReadTheEstimatorsDefaults() {
        let body = NutritionGoals.Body(sex: "female", weightKg: 0, heightCm: 0, age: 0)
        XCTAssertEqual(body.weightKg, 70)
        XCTAssertEqual(body.heightCm, 170)
        XCTAssertEqual(body.age, 30)
    }

    // MARK: Reference expenditure

    func testReferenceAveragesTheMeasuredDaysOfTheWindowOnly() {
        let totals: [(day: String, kcal: Double?)] = [
            (day: "2026-10-17", kcal: 9_000),      // before the window
            (day: "2026-10-18", kcal: 2_300),
            (day: "2026-10-19", kcal: nil),        // not measured
            (day: "2026-10-20", kcal: 0),          // nothing measured
            (day: "2026-10-21", kcal: 2_400),
            (day: "2026-10-31", kcal: 2_290),
            (day: "2026-11-01", kcal: 800),        // today, not complete
        ]
        let reference = NutritionGoals.referenceExpenditure(totals: totals, fromDay: "2026-10-18", beforeDay: "2026-11-01")
        XCTAssertEqual(reference?.days, 3)
        XCTAssertEqual(reference?.kcal ?? 0, (2_300 + 2_400 + 2_290) / 3, accuracy: 1e-9)
    }

    func testReferenceNeedsThreeDays() {
        let totals: [(day: String, kcal: Double?)] = [(day: "2026-10-30", kcal: 2_300), (day: "2026-10-31", kcal: 2_400)]
        XCTAssertNil(NutritionGoals.referenceExpenditure(totals: totals, fromDay: "2026-10-18", beforeDay: "2026-11-01"))
    }

    // MARK: Goals

    func testIntakeGoalOfTheMockup() {
        // 2 330 × 1.10 = 2 563 → 2 560
        XCTAssertEqual(NutritionGoals.intakeKcal(reference: 2_330, goalPercent: 10), 2_560)
        XCTAssertEqual(NutritionGoals.intakeKcal(reference: 2_330, goalPercent: 0), 2_330)
        // 2 334 × 0.90 = 2 100.6 → 2 100; 2 345 × 0.90 = 2 110.5 → 2 110
        XCTAssertEqual(NutritionGoals.intakeKcal(reference: 2_334, goalPercent: -10), 2_100)
        XCTAssertEqual(NutritionGoals.intakeKcal(reference: 2_345, goalPercent: -10), 2_110)
    }

    func testPlanOfTheMockup() {
        let plan = NutritionGoals.intakePlan(weightKg: 80, proteinTenths: 20, fatTenths: 10, goalPercent: 10,
                                             reference: NutritionGoals.Reference(kcal: 2_330, days: 14))
        XCTAssertEqual(plan.intakeKcal, 2_560)
        XCTAssertEqual(plan.proteinG, 160)
        XCTAssertEqual(plan.fatG, 80)
        XCTAssertEqual(plan.carbsG, 300)            // (2 560 − 640 − 720) ÷ 4
        XCTAssertEqual(plan.proteinKcal, 640)
        XCTAssertEqual(plan.fatKcal, 720)
        XCTAssertEqual(plan.carbsKcal, 1_200)
        XCTAssertEqual(plan.shareOfIntake(plan.proteinKcal), 25)
        XCTAssertEqual(plan.shareOfIntake(plan.fatKcal), 28)
        XCTAssertEqual(plan.shareOfIntake(1_200), 47)
    }

    func testPlanWithoutReferenceKeepsProteinAndFat() {
        let plan = NutritionGoals.intakePlan(weightKg: 73.4, proteinTenths: 21, fatTenths: 9, goalPercent: 0, reference: nil)
        XCTAssertNil(plan.intakeKcal)
        XCTAssertNil(plan.carbsG)
        XCTAssertEqual(plan.proteinG, 154)          // 2.1 × 73.4 = 154.14
        XCTAssertEqual(plan.fatG, 66)               // 0.9 × 73.4 = 66.06
        XCTAssertNil(plan.shareOfIntake(100))
    }

    func testCarbsNeverGoNegative() {
        let plan = NutritionGoals.intakePlan(weightKg: 100, proteinTenths: 30, fatTenths: 20, goalPercent: -25,
                                             reference: NutritionGoals.Reference(kcal: 1_800, days: 14))
        XCTAssertEqual(plan.intakeKcal, 1_350)
        XCTAssertEqual(plan.carbsG, 0)
    }

    func testStoredSettingsAreBroughtBackIntoRange() {
        XCTAssertEqual(NutritionGoals.clampedTenths(0, range: NutritionGoals.proteinTenthsRange, fallback: 20), 20)
        XCTAssertEqual(NutritionGoals.clampedTenths(45, range: NutritionGoals.proteinTenthsRange, fallback: 20), 30)
        XCTAssertEqual(NutritionGoals.clampedTenths(2, range: NutritionGoals.fatTenthsRange, fallback: 10), 5)
        XCTAssertEqual(NutritionGoals.clampedPercent(12), 10)
        XCTAssertEqual(NutritionGoals.clampedPercent(-40), -25)
        XCTAssertEqual(NutritionGoals.clampedPercent(0), 0)
    }

    // MARK: The day

    private func meal(_ id: String, _ lines: [MealNutrients], estimated: Bool = false) -> MealEntry {
        MealEntry(meal: MealRow(id: id, day: "2026-11-01", eatenAt: 0, name: id, origin: .manual,
                                createdAt: 0, updatedAt: 0),
                  items: lines.enumerated().map { index, n in
                      MealItemRow(id: "\(id)-\(index)", mealId: id, ord: index, name: "line", grams: estimated ? 100 : nil,
                                  gramsEstimated: estimated, nutrients: n)
                  })
    }

    func testDaySumsEveryLineAndTakesTheBalanceAgainstSpent() {
        let day = NutritionDaySummary(
            dayKey: "2026-11-01",
            meals: [meal("a", [MealNutrients(kcal: 520, proteinG: 22, carbsG: 82, fatG: 11)]),
                    meal("b", [MealNutrients(kcal: 400, proteinG: 25.1, carbsG: 50, fatG: 10.2),
                               MealNutrients(kcal: 250, proteinG: 15.0, carbsG: 30, fatG: 7.9)], estimated: true)],
            spent: TodayEnergy.Split(restingKcal: 1_580.4, activityKcal: 520.2))
        XCTAssertEqual(day.eaten.kcal, 1_170)
        XCTAssertEqual(day.eaten.proteinG, 62.1, accuracy: 1e-9)
        XCTAssertEqual(day.eaten.fatG, 29.1, accuracy: 1e-9)
        XCTAssertEqual(day.balanceKcal, 1_170 - 2_101)
        XCTAssertTrue(day.hasEstimate)
        XCTAssertNil(NutritionDaySummary(dayKey: "2026-11-01", meals: [], spent: nil).balanceKcal)
    }

    func testIntakeGaugeFillsToTheGoalThenMarksIt() {
        XCTAssertEqual(NutritionIntakeGauge.intakeArc(eaten: 1_280, goal: 2_560).fill, 0.5, accuracy: 1e-9)
        XCTAssertNil(NutritionIntakeGauge.intakeArc(eaten: 1_280, goal: 2_560).goalMark)
        let over = NutritionIntakeGauge.intakeArc(eaten: 3_200, goal: 2_560)
        XCTAssertEqual(over.fill, 1, accuracy: 1e-9)
        XCTAssertEqual(over.goalMark ?? 0, 0.8, accuracy: 1e-9)
        XCTAssertEqual(NutritionIntakeGauge.intakeArc(eaten: 900, goal: nil).fill, 0)
    }

    // MARK: Today's window

    func testHeartRateWindowFollowsTheSleepOnsetMarkers() {
        let markers: [(day: String, value: Double)] = [(day: "2026-11-01", value: 1_000), (day: "2026-11-02", value: 5_000)]
        XCTAssertEqual(TodayEnergy.heartRateWindow(dayStart: 2_000, dayEnd: 9_000, dayKey: "2026-11-01",
                                                   nextDayKey: "2026-11-02", cycleMarkers: markers), 1_000...4_999)
        XCTAssertEqual(TodayEnergy.heartRateWindow(dayStart: 2_000, dayEnd: 9_000, dayKey: "2026-11-01",
                                                   nextDayKey: "2026-11-02", cycleMarkers: []), 2_000...8_999)
        XCTAssertEqual(TodayEnergy.heartRateWindow(dayStart: 2_000, dayEnd: 2_000, dayKey: "2026-11-01",
                                                   nextDayKey: "2026-11-02", cycleMarkers: []), 2_000...2_000)
    }

    func testImportedActivityStandsInOnlyWithoutStrapEnergy() {
        let strap = TodayEnergy.Split(restingKcal: 1_500, activityKcal: 300)
        XCTAssertEqual(TodayEnergy.resolvedSplit(strap, importedActiveKcal: 999), strap)
        XCTAssertEqual(TodayEnergy.resolvedSplit(nil, importedActiveKcal: 420),
                       TodayEnergy.Split(restingKcal: 0, activityKcal: 420))
        XCTAssertNil(TodayEnergy.resolvedSplit(nil, importedActiveKcal: nil))
    }

    // MARK: Typing

    func testTypedNumbersReadBothDecimalMarks() {
        XCTAssertEqual(NutritionInput.typedNumber("28"), 28)
        XCTAssertEqual(NutritionInput.typedNumber("28,5"), 28.5)
        XCTAssertEqual(NutritionInput.typedNumber(" 28.5 "), 28.5)
        XCTAssertEqual(NutritionInput.typedNumber("1\u{202F}500"), 1_500)
        XCTAssertNil(NutritionInput.typedNumber(""))
        XCTAssertNil(NutritionInput.typedNumber("abc"))
        XCTAssertNil(NutritionInput.typedNumber("-3"))
    }

    func testDefaultTimeIsNowTodayAndTheSameClockTimeOnAnotherDay() {
        let cal = Calendar.current
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 20, minute: 40))!
        XCTAssertEqual(NutritionMealEditor.defaultTime(on: cal.startOfDay(for: now), now: now), now)
        let yesterday = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: now))!
        let parts = cal.dateComponents([.day, .hour, .minute], from: NutritionMealEditor.defaultTime(on: yesterday, now: now))
        XCTAssertEqual(parts.day, 31)
        XCTAssertEqual(parts.hour, 20)
        XCTAssertEqual(parts.minute, 40)
    }
}
