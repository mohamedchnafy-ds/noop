import Foundation
import WhoopStore

// Personal fork, Nutrition (chantier 22): the micronutrients of a journal line, a meal and a day.
//
// Nothing new is stored: a line keeps its `foodRef` ("ciqual:<code>" or "ean:<barcode>") and its grams,
// and its micronutrients are read again from the embedded Ciqual table (`CiqualFood.micros`) or from the
// values Open Food Facts gave for that barcode (`OpenFoodFactsMicros`), so the whole journal has them.
// A line typed by hand, a line without a quantity, or a food without the value has none: it is counted
// as missing, never as 0, and every screen says how many lines lacked the value.
//
// The one resolver: the Nutrition card, the detail screen, a meal, a portion and the Coach all read
// `MealMicros`; the references come from `MicroReference`.

/// The unit a micronutrient is stored and summed in (the unit Ciqual gives it in).
enum MicroUnit: Sendable {
    case grams, milligrams, micrograms

    var symbol: String {
        switch self {
        case .grams: return "g"
        case .milligrams: return "mg"
        case .micrograms: return "µg"
        }
    }
}

/// The groups the detail screen shows, in this order.
enum MicroGroup: CaseIterable, Sendable {
    case carbsAndFats, omegas, minerals, vitamins
}

/// One micronutrient. The raw value is its column in `Ciqual2025.tsv` (`Tools/ciqual_build.py`).
enum MicroNutrient: String, CaseIterable, Sendable {
    case fiber = "fiber_g"
    case sugars = "sugars_g"
    case saturatedFat = "sfa_g"
    case monounsaturatedFat = "mufa_g"
    case polyunsaturatedFat = "pufa_g"
    case cholesterol = "cholesterol_mg"
    case salt = "salt_g"
    case alphaLinolenicAcid = "ala_g"
    case epaDha = "epa_dha_g"
    case linoleicAcid = "la_g"
    case calcium = "calcium_mg"
    case iron = "iron_mg"
    case magnesium = "magnesium_mg"
    case potassium = "potassium_mg"
    case sodium = "sodium_mg"
    case zinc = "zinc_mg"
    case phosphorus = "phosphorus_mg"
    case iodine = "iodine_ug"
    case selenium = "selenium_ug"
    case copper = "copper_mg"
    case manganese = "manganese_mg"
    case vitaminA = "vitA_ug"
    case vitaminD = "vitD_ug"
    case vitaminE = "vitE_mg"
    case vitaminK1 = "vitK1_ug"
    case vitaminC = "vitC_mg"
    case vitaminB1 = "vitB1_mg"
    case vitaminB2 = "vitB2_mg"
    case vitaminB3 = "vitB3_mg"
    case vitaminB5 = "vitB5_mg"
    case vitaminB6 = "vitB6_mg"
    case vitaminB9 = "vitB9_ug"
    case vitaminB12 = "vitB12_ug"

    /// The unit it is stored and summed in, read off its column name.
    var unit: MicroUnit {
        if rawValue.hasSuffix("_ug") { return .micrograms }
        if rawValue.hasSuffix("_mg") { return .milligrams }
        return .grams
    }

    /// The unit it is shown in: EPA + DHA reads better in milligrams.
    var shownUnit: MicroUnit { self == .epaDha ? .milligrams : unit }

    /// An amount in `unit` as an amount in `shownUnit`.
    func shownAmount(_ amount: Double) -> Double { self == .epaDha ? amount * 1_000 : amount }

    var group: MicroGroup {
        switch self {
        case .fiber, .sugars, .saturatedFat, .monounsaturatedFat, .polyunsaturatedFat, .cholesterol, .salt:
            return .carbsAndFats
        case .alphaLinolenicAcid, .epaDha, .linoleicAcid:
            return .omegas
        case .calcium, .iron, .magnesium, .potassium, .sodium, .zinc, .phosphorus, .iodine, .selenium,
             .copper, .manganese:
            return .minerals
        default:
            return .vitamins
        }
    }

    /// A ceiling (not to pass) rather than a target (to reach).
    var isCeiling: Bool { self == .sugars || self == .saturatedFat || self == .salt }

    /// The few a meal's line and a food's line show, in this order (the rest: the detail screen).
    static let headline: [MicroNutrient] = [.fiber, .iron, .salt, .magnesium, .vitaminB9, .vitaminB12,
                                            .calcium, .vitaminC, .zinc]
}

/// The day's references, adult (ANSES, 2021 update of the nutritional references): the target or the
/// ceiling of each micronutrient, in its `unit`; nil = no reference (shown without a bar). Those set as a
/// share of energy use the day's intake goal.
enum MicroReference {

    /// The reference for `nutrient`. `sex` is the profile's ("female" takes the women's values; every
    /// other value the men's); `intakeKcal` the intake goal (≤ 0: 2 000 kcal).
    static func reference(for nutrient: MicroNutrient, sex: String, intakeKcal: Int) -> Double? {
        let female = sex == "female"
        let kcal = Double(intakeKcal > 0 ? intakeKcal : 2_000)
        switch nutrient {
        case .fiber: return 30
        case .sugars: return 100
        case .saturatedFat: return kcal * 0.12 / 9
        case .monounsaturatedFat, .polyunsaturatedFat, .cholesterol, .sodium: return nil
        case .salt: return 5
        case .alphaLinolenicAcid: return kcal * 0.01 / 9
        case .epaDha: return 0.5
        case .linoleicAcid: return kcal * 0.04 / 9
        case .calcium: return 950
        case .iron: return female ? 16 : 11
        case .magnesium: return female ? 360 : 420
        case .potassium: return 3_500
        case .zinc: return female ? 8.9 : 11
        case .phosphorus: return 700
        case .iodine: return 150
        case .selenium: return 70
        case .copper: return female ? 1.0 : 1.3
        case .manganese: return female ? 2.5 : 2.8
        case .vitaminA: return female ? 650 : 750
        case .vitaminD: return 15
        case .vitaminE: return female ? 9.9 : 10.5
        case .vitaminK1: return 79
        case .vitaminC: return 110
        case .vitaminB1: return female ? 1.2 : 1.5
        case .vitaminB2: return female ? 1.5 : 1.6
        case .vitaminB3: return female ? 14 : 17
        case .vitaminB5: return female ? 4.7 : 5.8
        case .vitaminB6: return female ? 1.5 : 1.8
        case .vitaminB9: return 330
        case .vitaminB12: return 4
        }
    }

    /// `amount` as a whole percentage of `reference`, or nil without a reference.
    static func percent(_ amount: Double, of reference: Double?) -> Int? {
        guard let reference, reference > 0, amount.isFinite else { return nil }
        return Int((max(0, amount) * 100 / reference).rounded())
    }
}

/// The micronutrients summed over some journal lines.
struct MicroTotals: Equatable {
    /// The sum of the lines that have the value, in each nutrient's `unit`. Absent: no line had it.
    var amounts: [MicroNutrient: Double] = [:]
    /// The lines that do NOT have the value (no source, no quantity, or unknown for that food).
    var missing: [MicroNutrient: Int] = [:]
    /// The lines summed.
    var lineCount = 0
    /// The lines with at least one micronutrient.
    var linesWithMicros = 0

    func amount(_ nutrient: MicroNutrient) -> Double? { amounts[nutrient] }
    func missingLines(_ nutrient: MicroNutrient) -> Int { missing[nutrient] ?? 0 }
}

/// What one food brought of a nutrient (the detail screen's "Where it comes from").
struct MicroSource: Equatable {
    let name: String
    let amount: Double
}

enum MealMicros {

    /// The micronutrients for 100 g of the food a line came from: the Ciqual table for "ciqual:<code>",
    /// Open Food Facts' values for "ean:<barcode>"; nil for anything else.
    static func microsPer100(foodRef: String?) -> [MicroNutrient: Double]? {
        guard let ref = foodRef else { return nil }
        if ref.hasPrefix("ciqual:"), let code = Int(ref.dropFirst("ciqual:".count)) {
            return CiqualTable.food(code: code)?.micros
        }
        if ref.hasPrefix("ean:") {
            return OpenFoodFactsMicros.storedMicros(barcode: String(ref.dropFirst("ean:".count)))
        }
        return nil
    }

    /// `per100` scaled to `grams`.
    static func portionMicros(_ per100: [MicroNutrient: Double], grams: Double) -> [MicroNutrient: Double] {
        let g = grams.isFinite ? max(0, grams) : 0
        return per100.mapValues { $0 * g / 100 }
    }

    /// One line's micronutrients, or nil when it has none (typed by hand, no quantity, no source).
    static func lineMicros(_ item: MealItemRow) -> [MicroNutrient: Double]? {
        guard let grams = item.grams, grams > 0,
              let per100 = microsPer100(foodRef: item.foodRef), !per100.isEmpty else { return nil }
        return portionMicros(per100, grams: grams)
    }

    /// The micronutrients of some lines (a meal, a day).
    static func microTotals(_ items: [MealItemRow]) -> MicroTotals {
        var totals = MicroTotals()
        totals.lineCount = items.count
        for item in items {
            let micros = lineMicros(item)
            if micros != nil { totals.linesWithMicros += 1 }
            for nutrient in MicroNutrient.allCases {
                if let amount = micros?[nutrient] {
                    totals.amounts[nutrient, default: 0] += amount
                } else {
                    totals.missing[nutrient, default: 0] += 1
                }
            }
        }
        return totals
    }

    /// The daily average over some days, each given by its lines: the days without a line are left out
    /// (a day nothing was logged is not a day nothing was eaten). Missing lines are added up.
    static func dailyAverage(_ days: [[MealItemRow]]) -> (totals: MicroTotals, days: Int) {
        let logged = days.filter { !$0.isEmpty }
        guard !logged.isEmpty else { return (MicroTotals(), 0) }
        var average = MicroTotals()
        for day in logged {
            let totals = microTotals(day)
            average.lineCount += totals.lineCount
            average.linesWithMicros += totals.linesWithMicros
            for (nutrient, amount) in totals.amounts { average.amounts[nutrient, default: 0] += amount }
            for (nutrient, count) in totals.missing { average.missing[nutrient, default: 0] += count }
        }
        let count = Double(logged.count)
        average.amounts = average.amounts.mapValues { $0 / count }
        return (average, logged.count)
    }

    /// The foods that brought the most of `nutrient`, by name, largest first.
    static func topSources(_ nutrient: MicroNutrient, in items: [MealItemRow], limit: Int = 3) -> [MicroSource] {
        var byName: [String: Double] = [:]
        var order: [String] = []
        for item in items {
            guard let amount = lineMicros(item)?[nutrient], amount > 0 else { continue }
            if byName[item.name] == nil { order.append(item.name) }
            byName[item.name, default: 0] += amount
        }
        return order.map { MicroSource(name: $0, amount: byName[$0] ?? 0) }
            .sorted { $0.amount != $1.amount ? $0.amount > $1.amount : $0.name < $1.name }
            .prefix(max(0, limit)).map { $0 }
    }

    /// The share of the reference reached, for sorting "furthest from the target" (targets only).
    static func targetShortfall(_ totals: MicroTotals, sex: String, intakeKcal: Int) -> [(MicroNutrient, Int)] {
        MicroNutrient.allCases.compactMap { nutrient -> (MicroNutrient, Int)? in
            guard !nutrient.isCeiling,
                  let reference = MicroReference.reference(for: nutrient, sex: sex, intakeKcal: intakeKcal),
                  let amount = totals.amount(nutrient),
                  let pct = MicroReference.percent(amount, of: reference) else { return nil }
            return (nutrient, pct)
        }
        .sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.rawValue < $1.0.rawValue }
    }
}

/// The micronutrients Open Food Facts gave for a barcode, kept on the iPhone (fork chantier 22) so a
/// scanned product's lines have them again offline. Only what the product page gives (often fiber,
/// sugars, salt and saturated fat); a product looked up before this existed has none until looked up again.
enum OpenFoodFactsMicros {

    static let storageKey = "nutrition.offMicros.v1"
    static let orderKey = "nutrition.offMicros.order.v1"
    /// The products kept; the oldest go first.
    static let maxProducts = 400

    /// Open Food Facts' `nutriments` keys (all per 100 g, in grams) and the factor to each nutrient's unit.
    static let offFields: [(key: String, nutrient: MicroNutrient, factor: Double)] = [
        ("fiber_100g", .fiber, 1),
        ("sugars_100g", .sugars, 1),
        ("saturated-fat_100g", .saturatedFat, 1),
        ("monounsaturated-fat_100g", .monounsaturatedFat, 1),
        ("polyunsaturated-fat_100g", .polyunsaturatedFat, 1),
        ("cholesterol_100g", .cholesterol, 1_000),
        ("salt_100g", .salt, 1),
        ("sodium_100g", .sodium, 1_000),
        ("calcium_100g", .calcium, 1_000),
        ("iron_100g", .iron, 1_000),
        ("magnesium_100g", .magnesium, 1_000),
        ("potassium_100g", .potassium, 1_000),
        ("zinc_100g", .zinc, 1_000),
        ("phosphorus_100g", .phosphorus, 1_000),
        ("vitamin-a_100g", .vitaminA, 1_000_000),
        ("vitamin-d_100g", .vitaminD, 1_000_000),
        ("vitamin-c_100g", .vitaminC, 1_000),
        ("vitamin-b12_100g", .vitaminB12, 1_000_000),
    ]

    /// The micronutrients of a product's `nutriments` object, per 100 g.
    static func parseOffMicros(_ nutriments: [String: Any]) -> [MicroNutrient: Double] {
        var micros: [MicroNutrient: Double] = [:]
        for field in offFields {
            let raw = nutriments[field.key]
            let value = (raw as? NSNumber)?.doubleValue ?? (raw as? String).flatMap(Double.init)
            if let value, value.isFinite, value >= 0 { micros[field.nutrient] = value * field.factor }
        }
        return micros
    }

    /// Keep a product's micronutrients (nothing when it gave none).
    static func rememberMicros(barcode: String, micros: [MicroNutrient: Double],
                               defaults: UserDefaults = .standard) {
        guard !micros.isEmpty else { return }
        var all = defaults.dictionary(forKey: storageKey) as? [String: [String: Double]] ?? [:]
        var order = defaults.stringArray(forKey: orderKey) ?? []
        all[barcode] = Dictionary(uniqueKeysWithValues: micros.map { ($0.key.rawValue, $0.value) })
        order.removeAll { $0 == barcode }
        order.append(barcode)
        while order.count > maxProducts {
            all[order.removeFirst()] = nil
        }
        defaults.set(all, forKey: storageKey)
        defaults.set(order, forKey: orderKey)
    }

    /// A product's kept micronutrients, or nil.
    static func storedMicros(barcode: String, defaults: UserDefaults = .standard) -> [MicroNutrient: Double]? {
        guard let all = defaults.dictionary(forKey: storageKey) as? [String: [String: Double]],
              let raw = all[barcode] else { return nil }
        var micros: [MicroNutrient: Double] = [:]
        for (key, value) in raw {
            if let nutrient = MicroNutrient(rawValue: key) { micros[nutrient] = value }
        }
        return micros
    }
}
