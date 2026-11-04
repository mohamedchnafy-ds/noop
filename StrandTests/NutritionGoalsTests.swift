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

    // MARK: Goals (fork chantier 9: basal × activity level, then % or typed kcal)

    /// The mockup's profile: homme, 31 ans, 172 cm, 112 kg.
    private let mockupBody = NutritionGoals.Body(sex: "male", weightKg: 112, heightCm: 172, age: 31)

    func testActivityFactorsAreTheClassicOnes() {
        XCTAssertEqual(NutritionGoals.ActivityLevel.allCases.map(\.factor), [1.2, 1.375, 1.55, 1.725, 1.9])
        XCTAssertEqual(NutritionGoals.ActivityLevel.defaultLevel, .light)
    }

    func testIntakeGoalRoundsTheExpenditureTimesThePercentageToTen() {
        // 2 330 × 1.10 = 2 563 → 2 560; 2 334 × 0.90 = 2 100.6 → 2 100; 2 345 × 0.90 = 2 110.5 → 2 110
        XCTAssertEqual(NutritionGoals.intakeKcal(expenditure: 2_330, goalPercent: 10), 2_560)
        XCTAssertEqual(NutritionGoals.intakeKcal(expenditure: 2_330, goalPercent: 0), 2_330)
        XCTAssertEqual(NutritionGoals.intakeKcal(expenditure: 2_334, goalPercent: -10), 2_100)
        XCTAssertEqual(NutritionGoals.intakeKcal(expenditure: 2_345, goalPercent: -10), 2_110)
    }

    /// Mockup 4, screen 3: 2 238 × 1,375 = 3 078 · −20 % → 2 460.
    func testPlanOfTheMockup() {
        let plan = NutritionGoals.intakePlan(body: mockupBody,
                                             settings: NutritionGoals.Settings(activity: .light, goalPercent: -20))
        XCTAssertEqual(plan.basalKcal, 2_238)        // 88.362 + 13.397 × 112 + 4.799 × 172 − 5.677 × 31 = 2 238.267
        XCTAssertEqual(plan.expenditureKcal, 3_078)  // 2 238.267 × 1.375 = 3 077.6
        XCTAssertEqual(plan.intakeKcal, 2_460)       // 3 077.6 × 0.80 = 2 462.1
        XCTAssertFalse(plan.isBelowBasal)
        XCTAssertFalse(plan.isTyped)
        XCTAssertEqual(plan.proteinG, 224)
        XCTAssertEqual(plan.fatG, 112)
        XCTAssertEqual(plan.carbsG, 139)             // (2 460 − 896 − 1 008) ÷ 4
        XCTAssertEqual(plan.proteinKcal, 896)
        XCTAssertEqual(plan.fatKcal, 1_008)
        XCTAssertEqual(plan.carbsKcal, 556)
        XCTAssertEqual(plan.shareOfIntake(plan.proteinKcal), 36)
    }

    func testEveryLevelMultipliesTheBasalRate() {
        let expected = [(NutritionGoals.ActivityLevel.sedentary, 2_686), (.light, 3_078), (.moderate, 3_469),
                        (.active, 3_861), (.extreme, 4_253)]
        for (level, kcal) in expected {
            let plan = NutritionGoals.intakePlan(body: mockupBody, settings: NutritionGoals.Settings(activity: level))
            XCTAssertEqual(plan.expenditureKcal, kcal, level.rawValue)
            XCTAssertEqual(plan.intakeKcal, Int((Double(kcal) / 10).rounded()) * 10, level.rawValue)
        }
    }

    /// The strap's measured expenditure never enters the goal: the plan has no input for it.
    func testTheTypedGoalStandsWhateverTheBodyOrTheLevel() {
        let settings = NutritionGoals.Settings(activity: .extreme, mode: .kcal, goalPercent: -30, manualKcal: 2_400)
        let heavy = NutritionGoals.intakePlan(body: mockupBody, settings: settings)
        let light = NutritionGoals.intakePlan(body: NutritionGoals.Body(sex: "female", weightKg: 55, heightCm: 160, age: 50),
                                              settings: settings)
        XCTAssertEqual(heavy.intakeKcal, 2_400)
        XCTAssertEqual(light.intakeKcal, 2_400)
        XCTAssertTrue(heavy.isTyped)
        XCTAssertFalse(heavy.isBelowBasal)
        XCTAssertEqual(heavy.expenditureKcal, 4_253, "the expenditure is still estimated beside the typed goal")
    }

    func testKcalModeWithoutATypedGoalFallsBackOnThePercentage() {
        let plan = NutritionGoals.intakePlan(body: mockupBody,
                                             settings: NutritionGoals.Settings(mode: .kcal, goalPercent: -20, manualKcal: 0))
        XCTAssertFalse(plan.isTyped)
        XCTAssertEqual(plan.intakeKcal, 2_460)
    }

    func testAGoalUnderTheBasalRateIsFlagged() {
        let lowPercent = NutritionGoals.intakePlan(body: mockupBody,
                                                   settings: NutritionGoals.Settings(activity: .sedentary, goalPercent: -30))
        XCTAssertEqual(lowPercent.intakeKcal, 1_880)  // 2 238.267 × 1.2 × 0.70 = 1 880.1
        XCTAssertTrue(lowPercent.isBelowBasal)
        let typed = NutritionGoals.intakePlan(body: mockupBody, settings: NutritionGoals.Settings(mode: .kcal, manualKcal: 2_250))
        XCTAssertFalse(typed.isBelowBasal, "2 250 is over 2 238.267")
    }

    func testCarbsNeverGoNegative() {
        let plan = NutritionGoals.intakePlan(body: NutritionGoals.Body(sex: "male", weightKg: 100, heightCm: 180, age: 30),
                                             settings: NutritionGoals.Settings(mode: .kcal, manualKcal: 1_000,
                                                                               proteinTenths: 30, fatTenths: 20))
        XCTAssertEqual(plan.intakeKcal, 1_000)
        XCTAssertEqual(plan.carbsG, 0)
    }

    func testStoredSettingsAreBroughtBackIntoRange() {
        XCTAssertEqual(NutritionGoals.clampedTenths(0, range: NutritionGoals.proteinTenthsRange, fallback: 20), 20)
        XCTAssertEqual(NutritionGoals.clampedTenths(45, range: NutritionGoals.proteinTenthsRange, fallback: 20), 30)
        XCTAssertEqual(NutritionGoals.clampedTenths(2, range: NutritionGoals.fatTenthsRange, fallback: 10), 5)
        XCTAssertEqual(NutritionGoals.clampedPercent(12), 10)
        XCTAssertEqual(NutritionGoals.clampedPercent(-30), -30)
        XCTAssertEqual(NutritionGoals.clampedPercent(-40), -30)
        XCTAssertEqual(NutritionGoals.clampedPercent(40), 25)
        XCTAssertEqual(NutritionGoals.clampedPercent(0), 0)
        XCTAssertEqual(NutritionGoals.clampedManualKcal(0), 0)
        XCTAssertEqual(NutritionGoals.clampedManualKcal(2_462), 2_450)
        XCTAssertEqual(NutritionGoals.clampedManualKcal(2_475), 2_500)
        XCTAssertEqual(NutritionGoals.clampedManualKcal(300), 1_000)
        XCTAssertEqual(NutritionGoals.clampedManualKcal(9_000), 6_000)
        let unset = NutritionGoals.Settings.settingsFromStored(activity: nil, mode: "nonsense", goalPercent: 0, manualKcal: 0,
                                                               proteinTenths: 0, fatTenths: 0)
        XCTAssertEqual(unset, NutritionGoals.Settings())
        XCTAssertEqual(unset.activity, .light)
        XCTAssertEqual(unset.mode, .percent)
    }

    func testStoredSettingsAreReadFromTheDefaults() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "NutritionGoalsTests-\(UUID().uuidString)"))
        defaults.set("active", forKey: NutritionGoals.activityLevelKey)
        defaults.set("kcal", forKey: NutritionGoals.goalModeKey)
        defaults.set(2_412, forKey: NutritionGoals.manualKcalKey)
        defaults.set(-35, forKey: NutritionGoals.goalPercentKey)
        defaults.set(22, forKey: NutritionGoals.proteinTenthsKey)
        let settings = NutritionGoals.Settings.storedGoalSettings(defaults)
        XCTAssertEqual(settings, NutritionGoals.Settings(activity: .active, mode: .kcal, goalPercent: -30, manualKcal: 2_400,
                                                         proteinTenths: 22, fatTenths: 10))
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
