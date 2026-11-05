import Foundation

// Personal fork, Nutrition: the intake goals the Nutrition screens show, every number from a formula the
// Goals screen spells out. Nothing here reads a store, a clock or a setting: the screens pass everything
// in, so each rule is pinned by `NutritionGoalsTests`.
//
// - Basal metabolic rate: the revised Harris-Benedict equation, with exactly the coefficients the calorie
//   estimator charges as resting energy (`Calories.estimateDayEnergy`), so "basal" here and "resting"
//   under Today's calories are one figure. A test holds the two together.
// - Daily expenditure (fork chantier 9): that rate × the activity level's factor (1.2 to 1.9). The
//   strap's measured expenditure under-counts whenever it is not worn, so it is shown for information only
//   (`referenceExpenditure`) and never enters the goal.
// - Intake goal: the daily expenditure × (1 + the goal percentage), rounded to 10 kcal, or the kcal the
//   wearer typed (in steps of 50), which then no longer moves with the weight or the activity.
// - Protein and fat: grams per kilogram of body weight; carbohydrates: the energy that is left, ÷ 4.
//   Grams per kilogram of TOTAL weight overshoot on a heavy body: at 112 kg and 1 900 kcal, 2.0 g/kg of
//   protein and 1.0 g/kg of fat filled the whole goal and left « 0 g » of carbohydrates (5 Nov.). So the
//   protein is held to `proteinMaxShare` of the goal, and when protein and fat still leave carbohydrates
//   less than `carbsMinShare`, the fat comes down first, never under `fatMinShare` (then the protein).
//
// `NutritionDayReader.currentPlan` is the one resolver every reader goes through (Nutrition, its rings,
// the history, the widget, the Coach); the Goals screen calls `intakePlan` with the same settings.

enum NutritionGoals {

    // MARK: Settings (this device only; not part of the .noopbak settings whitelist)

    /// Protein in tenths of a gram per kilogram (20 = 2.0 g/kg).
    static let proteinTenthsKey = "nutrition.proteinTenthsPerKg"
    /// Fat in tenths of a gram per kilogram (10 = 1.0 g/kg).
    static let fatTenthsKey = "nutrition.fatTenthsPerKg"
    /// The goal against the daily expenditure, in percent: −20 loses, 0 maintains, +10 gains.
    static let goalPercentKey = "nutrition.goalPercent"
    /// The activity level the basal rate is multiplied by (`ActivityLevel` raw value).
    static let activityLevelKey = "nutrition.activityLevel"
    /// How the goal is set (`GoalMode` raw value): a percentage of the expenditure, or typed kcal.
    static let goalModeKey = "nutrition.goalMode"
    /// The intake goal typed by the wearer, kcal a day (0 = not typed yet).
    static let manualKcalKey = "nutrition.manualIntakeKcal"

    static let defaultProteinTenths = 20
    static let defaultFatTenths = 10
    static let defaultGoalPercent = 0
    static let proteinTenthsRange = 10...30
    static let fatTenthsRange = 5...20
    static let goalPercentRange = -30...25
    /// The goal percentage moves by this much.
    static let goalPercentStep = 5
    /// The starting percentage of each preset: Lose, Maintain, Gain.
    static let losePresetPercent = -20
    static let gainPresetPercent = 10
    /// The shares of the intake goal (in kcal) that bound the split: protein at most 40 %, carbohydrates
    /// at least 25 %, fat lowered for them but never under 20 %.
    static let proteinMaxShare = 0.40
    static let carbsMinShare = 0.25
    static let fatMinShare = 0.20
    /// The typed goal moves by this much, within this range.
    static let manualKcalStep = 50
    static let manualKcalRange = 1_000...6_000

    // MARK: Activity level and goal mode

    /// The classic activity factors applied to the basal rate.
    enum ActivityLevel: String, CaseIterable, Identifiable {
        case sedentary, light, moderate, active, extreme

        static let defaultLevel: ActivityLevel = .light

        var id: String { rawValue }

        var factor: Double {
            switch self {
            case .sedentary: return 1.2
            case .light: return 1.375
            case .moderate: return 1.55
            case .active: return 1.725
            case .extreme: return 1.9
            }
        }

        /// An unknown or missing stored value reads the default level.
        static func storedLevel(_ raw: String?) -> ActivityLevel {
            raw.flatMap(ActivityLevel.init(rawValue:)) ?? defaultLevel
        }
    }

    enum GoalMode: String, CaseIterable, Identifiable {
        /// A percentage of the daily expenditure.
        case percent
        /// Kcal typed by the wearer.
        case kcal

        var id: String { rawValue }

        static func storedMode(_ raw: String?) -> GoalMode { raw.flatMap(GoalMode.init(rawValue:)) ?? .percent }
    }

    /// Every setting the plan is calculated from, already brought back into range.
    struct Settings: Equatable {
        var activity: ActivityLevel
        var mode: GoalMode
        var goalPercent: Int
        /// The typed goal, kcal a day; 0 when none was typed (the % goal stands in until one is).
        var manualKcal: Int
        var proteinTenths: Int
        var fatTenths: Int

        init(activity: ActivityLevel = .defaultLevel, mode: GoalMode = .percent, goalPercent: Int = 0,
             manualKcal: Int = 0, proteinTenths: Int = NutritionGoals.defaultProteinTenths,
             fatTenths: Int = NutritionGoals.defaultFatTenths) {
            self.activity = activity
            self.mode = mode
            self.goalPercent = goalPercent
            self.manualKcal = manualKcal
            self.proteinTenths = proteinTenths
            self.fatTenths = fatTenths
        }

        /// The settings as stored on this device (`settingsFromStored`).
        static func storedGoalSettings(_ defaults: UserDefaults = .standard) -> Settings {
            settingsFromStored(activity: defaults.string(forKey: NutritionGoals.activityLevelKey),
                               mode: defaults.string(forKey: NutritionGoals.goalModeKey),
                               goalPercent: defaults.integer(forKey: NutritionGoals.goalPercentKey),
                               manualKcal: defaults.integer(forKey: NutritionGoals.manualKcalKey),
                               proteinTenths: defaults.integer(forKey: NutritionGoals.proteinTenthsKey),
                               fatTenths: defaults.integer(forKey: NutritionGoals.fatTenthsKey))
        }

        /// The stored values brought back into range, each the way it is read everywhere: an unknown
        /// level or mode reads the default, a percentage snaps to its step, an unset key reads its default.
        static func settingsFromStored(activity: String?, mode: String?, goalPercent: Int, manualKcal: Int,
                                       proteinTenths: Int, fatTenths: Int) -> Settings {
            Settings(activity: ActivityLevel.storedLevel(activity), mode: GoalMode.storedMode(mode),
                     goalPercent: NutritionGoals.clampedPercent(goalPercent),
                     manualKcal: NutritionGoals.clampedManualKcal(manualKcal),
                     proteinTenths: NutritionGoals.clampedTenths(proteinTenths, range: NutritionGoals.proteinTenthsRange,
                                                                 fallback: NutritionGoals.defaultProteinTenths),
                     fatTenths: NutritionGoals.clampedTenths(fatTenths, range: NutritionGoals.fatTenthsRange,
                                                             fallback: NutritionGoals.defaultFatTenths))
        }
    }

    // MARK: Basal metabolic rate

    /// The revised Harris-Benedict equation (Roza & Shizgal, 1984) for one sex:
    /// `alpha + perKg × weight + perCm × height − perYear × age`, in kcal a day. "nonbinary" (and any
    /// other value) takes the midpoint of the two, as the calorie estimator does.
    struct BasalFormula: Equatable {
        let alpha: Double
        let perKg: Double
        let perCm: Double
        let perYear: Double

        func kcalPerDay(weightKg: Double, heightCm: Double, age: Double) -> Double {
            max(0, alpha + perKg * weightKg + perCm * heightCm - perYear * age)
        }
    }

    static func basalFormula(sex: String) -> BasalFormula {
        switch sex.lowercased() {
        case "male": return BasalFormula(alpha: 88.362, perKg: 13.397, perCm: 4.799, perYear: 5.677)
        case "female": return BasalFormula(alpha: 447.593, perKg: 9.247, perCm: 3.098, perYear: 4.33)
        default: return BasalFormula(alpha: 267.9775, perKg: 11.322, perCm: 3.9485, perYear: 5.0035)
        }
    }

    /// The profile values the formula is given: an unset (zero) weight, height or age reads 70 kg,
    /// 170 cm and 30 years, the calorie estimator's own defaults, so the two never disagree.
    struct Body: Equatable {
        let sex: String
        let weightKg: Double
        let heightCm: Double
        let age: Double

        init(sex: String, weightKg: Double, heightCm: Double, age: Double) {
            self.sex = sex
            self.weightKg = weightKg > 0 ? weightKg : 70
            self.heightCm = heightCm > 0 ? heightCm : 170
            self.age = age > 0 ? age : 30
        }
    }

    static func basalKcalPerDay(_ body: Body) -> Double {
        basalFormula(sex: body.sex).kcalPerDay(weightKg: body.weightKg, heightCm: body.heightCm, age: body.age)
    }

    // MARK: Measured expenditure (shown for information only)

    /// Complete days the reference expenditure averages over, and the fewest it needs.
    static let referenceWindowDays = 14
    static let referenceMinDays = 3

    struct Reference: Equatable {
        /// Mean measured total, kcal a day.
        let kcal: Double
        /// Days that went into it.
        let days: Int
    }

    /// The mean of the measured day totals from `fromDay` up to (not including) `beforeDay`, both
    /// "yyyy-MM-dd"; a day with no total, or a total of zero, is left out. Nil under `referenceMinDays`.
    static func referenceExpenditure(totals: [(day: String, kcal: Double?)], fromDay: String,
                                     beforeDay: String) -> Reference? {
        var byDay: [String: Double] = [:]
        for row in totals where row.day >= fromDay && row.day < beforeDay {
            if let kcal = row.kcal, kcal.isFinite, kcal > 0 { byDay[row.day] = kcal }
        }
        guard byDay.count >= referenceMinDays else { return nil }
        return Reference(kcal: byDay.values.reduce(0, +) / Double(byDay.count), days: byDay.count)
    }

    // MARK: The plan

    struct Plan: Equatable {
        /// What it was calculated from.
        let settings: Settings
        /// The basal metabolic rate, kcal a day, to the whole kcal.
        let basalKcal: Int
        /// Basal rate × activity factor, kcal a day, to the whole kcal.
        let expenditureKcal: Int
        /// The intake goal, kcal a day: the % goal rounded to 10, or the typed goal.
        let intakeKcal: Int
        /// The goal sits under the basal rate: the Goals screen warns (it never blocks).
        let isBelowBasal: Bool
        let proteinG: Int
        let fatG: Int
        /// The energy left after protein and fat, ÷ 4; never below 0.
        let carbsG: Int
        /// The protein was held to `proteinMaxShare` of the goal, under its grams per kilogram.
        var proteinCapped: Bool = false
        /// The fat was lowered under its grams per kilogram so the carbohydrates keep `carbsMinShare`.
        var fatLowered: Bool = false

        var proteinKcal: Int { 4 * proteinG }
        var fatKcal: Int { 9 * fatG }
        var carbsKcal: Int { 4 * carbsG }
        /// True when the goal is the typed one (kcal mode with a typed value).
        var isTyped: Bool { settings.mode == .kcal && settings.manualKcal > 0 }

        /// A part's share of the intake goal, in whole percent.
        func shareOfIntake(_ kcal: Int) -> Int? {
            guard intakeKcal > 0 else { return nil }
            return Int((Double(kcal) * 100 / Double(intakeKcal)).rounded())
        }
    }

    /// The intake goal from an expenditure: `expenditure × (1 + percent / 100)`, to 10 kcal.
    static func intakeKcal(expenditure: Double, goalPercent: Int) -> Int {
        let raw = expenditure * (1 + Double(goalPercent) / 100)
        return Int((raw / 10).rounded()) * 10
    }

    /// Grams from tenths of a gram per kilogram, to the whole gram.
    static func gramsFromTenths(tenthsPerKg: Int, weightKg: Double) -> Int {
        Int((Double(tenthsPerKg) / 10 * max(weightKg, 0)).rounded())
    }

    /// The plan for a body and settings: basal × activity, then the % goal (or the typed one), then the
    /// macros against the body's weight.
    static func intakePlan(body: Body, settings: Settings) -> Plan {
        let basal = basalKcalPerDay(body)
        let expenditure = basal * settings.activity.factor
        let typed = settings.mode == .kcal && settings.manualKcal > 0
        let intake = typed ? settings.manualKcal : intakeKcal(expenditure: expenditure, goalPercent: settings.goalPercent)
        let split = macroSplit(intakeKcal: intake,
                               proteinG: gramsFromTenths(tenthsPerKg: settings.proteinTenths, weightKg: body.weightKg),
                               fatG: gramsFromTenths(tenthsPerKg: settings.fatTenths, weightKg: body.weightKg))
        return Plan(settings: settings, basalKcal: Int(basal.rounded()), expenditureKcal: Int(expenditure.rounded()),
                    intakeKcal: intake, isBelowBasal: Double(intake) < basal,
                    proteinG: split.proteinG, fatG: split.fatG, carbsG: split.carbsG,
                    proteinCapped: split.proteinCapped, fatLowered: split.fatLowered)
    }

    /// The grams of each macro for an intake goal, from the grams per kilogram asked: protein held to
    /// `proteinMaxShare`, then fat lowered (down to `fatMinShare`, then protein) until the carbohydrates
    /// keep `carbsMinShare`. Grams are rounded down when bounded, so a bound is never overshot.
    static func macroSplit(intakeKcal: Int, proteinG asked: Int, fatG askedFat: Int)
        -> (proteinG: Int, fatG: Int, carbsG: Int, proteinCapped: Bool, fatLowered: Bool) {
        let intake = Double(max(intakeKcal, 0))
        var protein = asked
        var fat = askedFat
        let proteinMax = Int(intake * proteinMaxShare / 4)
        let proteinCapped = protein > proteinMax
        if proteinCapped { protein = proteinMax }
        let budget = intake * (1 - carbsMinShare)
        var fatLowered = false
        if Double(4 * protein + 9 * fat) > budget {
            let fatFloor = min(fat, Int(intake * fatMinShare / 9))
            fat = max(fatFloor, Int((budget - Double(4 * protein)) / 9))
            fatLowered = fat < askedFat
            if Double(4 * protein + 9 * fat) > budget {
                protein = max(0, Int((budget - Double(9 * fat)) / 4))
            }
        }
        let carbs = max(0, Int(((intake - Double(4 * protein + 9 * fat)) / 4).rounded()))
        return (protein, fat, carbs, proteinCapped || protein < asked, fatLowered)
    }

    /// A stored setting brought back into its range (an unset key reads 0, which means the default).
    static func clampedTenths(_ stored: Int, range: ClosedRange<Int>, fallback: Int) -> Int {
        stored == 0 ? fallback : min(max(stored, range.lowerBound), range.upperBound)
    }

    static func clampedPercent(_ stored: Int) -> Int {
        let stepped = (stored / goalPercentStep) * goalPercentStep
        return min(max(stepped, goalPercentRange.lowerBound), goalPercentRange.upperBound)
    }

    /// A typed goal on its 50 kcal step, within `manualKcalRange`; 0 (not typed) stays 0.
    static func clampedManualKcal(_ stored: Int) -> Int {
        guard stored > 0 else { return 0 }
        let stepped = Int((Double(stored) / Double(manualKcalStep)).rounded()) * manualKcalStep
        return min(max(stepped, manualKcalRange.lowerBound), manualKcalRange.upperBound)
    }
}
