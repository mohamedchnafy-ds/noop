import Foundation

// Personal fork, Nutrition: the intake goals the Nutrition screens show, every number from a formula the
// Goals screen spells out. Nothing here reads a store, a clock or a setting: the screens pass everything
// in, so each rule is pinned by `NutritionGoalsTests`.
//
// - Basal metabolic rate: the revised Harris-Benedict equation, with exactly the coefficients the calorie
//   estimator charges as resting energy (`Calories.estimateDayEnergy`), so "basal" here and "resting"
//   under Today's calories are one figure. A test holds the two together.
// - Reference expenditure: the mean of the totals the strap measured on the last complete days.
// - Intake goal: that mean × (1 + the goal percentage), rounded to 10 kcal.
// - Protein and fat: grams per kilogram of body weight; carbohydrates: the energy that is left, ÷ 4.

enum NutritionGoals {

    // MARK: Settings (this device only; not part of the .noopbak settings whitelist)

    /// Protein in tenths of a gram per kilogram (20 = 2.0 g/kg).
    static let proteinTenthsKey = "nutrition.proteinTenthsPerKg"
    /// Fat in tenths of a gram per kilogram (10 = 1.0 g/kg).
    static let fatTenthsKey = "nutrition.fatTenthsPerKg"
    /// The goal against the reference expenditure, in percent: −10 loses, 0 maintains, +10 gains.
    static let goalPercentKey = "nutrition.goalPercent"

    static let defaultProteinTenths = 20
    static let defaultFatTenths = 10
    static let defaultGoalPercent = 0
    static let proteinTenthsRange = 10...30
    static let fatTenthsRange = 5...20
    static let goalPercentRange = -25...25
    /// The goal percentage moves by this much.
    static let goalPercentStep = 5

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

    // MARK: Reference expenditure

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
        /// The intake goal, kcal a day, rounded to 10; nil without a reference expenditure.
        let intakeKcal: Int?
        let proteinG: Int
        let fatG: Int
        /// The energy left after protein and fat, ÷ 4; never below 0. Nil without an intake goal.
        let carbsG: Int?

        var proteinKcal: Int { 4 * proteinG }
        var fatKcal: Int { 9 * fatG }
        var carbsKcal: Int? { carbsG.map { 4 * $0 } }

        /// A part's share of the intake goal, in whole percent.
        func shareOfIntake(_ kcal: Int) -> Int? {
            guard let intakeKcal, intakeKcal > 0 else { return nil }
            return Int((Double(kcal) * 100 / Double(intakeKcal)).rounded())
        }
    }

    /// The intake goal from the reference expenditure: `reference × (1 + percent / 100)`, to 10 kcal.
    static func intakeKcal(reference: Double, goalPercent: Int) -> Int {
        let raw = reference * (1 + Double(goalPercent) / 100)
        return Int((raw / 10).rounded()) * 10
    }

    /// Grams from tenths of a gram per kilogram, to the whole gram.
    static func gramsFromTenths(tenthsPerKg: Int, weightKg: Double) -> Int {
        Int((Double(tenthsPerKg) / 10 * max(weightKg, 0)).rounded())
    }

    static func intakePlan(weightKg: Double, proteinTenths: Int, fatTenths: Int, goalPercent: Int,
                     reference: Reference?) -> Plan {
        let protein = gramsFromTenths(tenthsPerKg: proteinTenths, weightKg: weightKg)
        let fat = gramsFromTenths(tenthsPerKg: fatTenths, weightKg: weightKg)
        let intake = reference.map { intakeKcal(reference: $0.kcal, goalPercent: goalPercent) }
        let carbs = intake.map { max(0, Int((Double($0 - 4 * protein - 9 * fat) / 4).rounded())) }
        return Plan(intakeKcal: intake, proteinG: protein, fatG: fat, carbsG: carbs)
    }

    /// A stored setting brought back into its range (an unset key reads 0, which means the default).
    static func clampedTenths(_ stored: Int, range: ClosedRange<Int>, fallback: Int) -> Int {
        stored == 0 ? fallback : min(max(stored, range.lowerBound), range.upperBound)
    }

    static func clampedPercent(_ stored: Int) -> Int {
        let stepped = (stored / goalPercentStep) * goalPercentStep
        return min(max(stepped, goalPercentRange.lowerBound), goalPercentRange.upperBound)
    }
}
