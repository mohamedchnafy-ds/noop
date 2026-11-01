import Foundation
import GRDB

// MARK: - v51 store: the meal journal (personal fork, Nutrition)
//
// MealLogStore.swift — GRDB CRUD over `meal` + `mealItem` (migration v51-meal-log), in the
// LiftLogStore / CoachConversationStore idiom: plain Codable rows, raw `Row` fetch + manual decode,
// all GRDB work through the actor's `syncWrite` / `syncRead`.
//
// A meal stores no nutrient of its own: its energy and macros are the sum of its lines, computed on
// read by `MealMath.totals`, so a meal, its lines and the day they add up to are one fact read three
// ways rather than three facts that could drift. Each line is rounded once, at write, by `MealMath`.
//
// The Android Room twin (`MealRow` / `MealItemRow`, MIGRATION_42_43) is the schema and `MealMath`;
// Android has no meal screens, so it has no DAO for these tables yet.

// MARK: - Arithmetic

/// Energy and macros of a meal line, a meal or a day: whole kcal, grams to one decimal.
public struct MealNutrients: Equatable, Codable, Sendable {
    public var kcal: Int
    public var proteinG: Double
    public var carbsG: Double
    public var fatG: Double

    public init(kcal: Int, proteinG: Double, carbsG: Double, fatG: Double) {
        self.kcal = kcal
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
    }
}

/// A food's values for 100 g, as read from the Ciqual table or a nutrition label.
public struct MealPer100: Equatable, Codable, Sendable {
    public var kcal: Double
    public var proteinG: Double
    public var carbsG: Double
    public var fatG: Double

    public init(kcal: Double, proteinG: Double, carbsG: Double, fatG: Double) {
        self.kcal = kcal
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
    }
}

/// The meal journal's arithmetic, shared by every screen and by the Coach so the same food always
/// gives the same numbers. PARITY: pure and deterministic; the Kotlin twin is `MealMath` in
/// `com.noop.data`, and both are pinned to one expected block (`MealMathOracleTests` here,
/// `MealMathParityOracleTest` on Android).
///
/// Rounding is half away from zero (`rounded()` here, `Math.round` there: the same for the
/// non-negative values these functions accept). A negative, NaN or infinite input counts as 0, and
/// an input above 100 000 counts as 100 000.
public enum MealMath {

    /// Energy from macros with the 4 / 4 / 9 kcal-per-gram factors, in whole kcal.
    /// Kotlin twin: `MealMath.kcal`.
    public static func kcal(proteinG: Double, carbsG: Double, fatG: Double) -> Int {
        let raw = 4 * clean(proteinG) + 4 * clean(carbsG) + 9 * clean(fatG)
        return Int(raw.rounded())
    }

    /// A gram amount kept to one decimal.
    /// Kotlin twin: `MealMath.tenth`.
    public static func tenth(_ grams: Double) -> Double {
        (clean(grams) * 10).rounded() / 10
    }

    /// The values of `grams` of a food from its values per 100 g: `value × grams / 100`, then
    /// whole kcal and macros to one decimal.
    /// Kotlin twin: `MealMath.portion`.
    public static func portion(per100: MealPer100, grams: Double) -> MealNutrients {
        let g = clean(grams)
        return MealNutrients(kcal: Int((clean(per100.kcal) * g / 100).rounded()),
                             proteinG: tenth(clean(per100.proteinG) * g / 100),
                             carbsG: tenth(clean(per100.carbsG) * g / 100),
                             fatG: tenth(clean(per100.fatG) * g / 100))
    }

    /// The sum of already-rounded lines (a meal, or every line of a day), added in order, macros
    /// brought back to one decimal so the sum carries no floating-point residue.
    /// Kotlin twin: `MealMath.totals`.
    public static func totals(_ lines: [MealNutrients]) -> MealNutrients {
        var kcal = 0
        var protein = 0.0
        var carbs = 0.0
        var fat = 0.0
        for line in lines {
            kcal += max(line.kcal, 0)
            protein += clean(line.proteinG)
            carbs += clean(line.carbsG)
            fat += clean(line.fatG)
        }
        return MealNutrients(kcal: kcal, proteinG: tenth(protein), carbsG: tenth(carbs), fatG: tenth(fat))
    }

    /// An input made safe: NaN, infinite or negative → 0, and at most 100 000 (grams, kcal or grams
    /// per 100 g): far above any meal, and low enough that every result fits a 32-bit integer on
    /// Android (the Kotlin twin's `INPUT_CAP`).
    /// Kotlin twin: `MealMath.clean`.
    static func clean(_ value: Double) -> Double {
        value.isFinite && value > 0 ? min(value, 100_000) : 0
    }
}

// MARK: - Rows

/// How a meal entered the journal.
public enum MealOrigin: String, Codable, Sendable, CaseIterable {
    case manual, photo, voice, barcode
}

/// One entry of the journal. Its nutrients are the sum of its lines (`MealMath.totals`).
public struct MealRow: Equatable, Codable, Sendable {
    public var id: String
    /// The local day it was eaten, "yyyy-MM-dd".
    public var day: String
    /// Unix seconds.
    public var eatenAt: Int
    public var name: String
    public var origin: MealOrigin
    /// Offered first among the recent meals.
    public var favorite: Bool
    /// Unix seconds.
    public var createdAt: Int
    /// Unix seconds.
    public var updatedAt: Int

    public init(id: String, day: String, eatenAt: Int, name: String, origin: MealOrigin,
                favorite: Bool = false, createdAt: Int, updatedAt: Int) {
        self.id = id
        self.day = day
        self.eatenAt = eatenAt
        self.name = name
        self.origin = origin
        self.favorite = favorite
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    static func decode(_ row: Row) -> MealRow {
        MealRow(id: row["id"], day: row["day"], eatenAt: row["eatenAt"], name: row["name"],
                origin: MealOrigin(rawValue: row["origin"] ?? "") ?? .manual,
                favorite: (row["favorite"] as Int) != 0,
                createdAt: row["createdAt"], updatedAt: row["updatedAt"])
    }
}

/// One line of a meal: the values for the quantity eaten, already rounded by `MealMath`.
public struct MealItemRow: Equatable, Codable, Sendable {
    public var id: String
    public var mealId: String
    /// Position within the meal; `saveMeal` rewrites it from the order it is given.
    public var ord: Int
    public var name: String
    /// Nil for a line typed by hand with no quantity.
    public var grams: Double?
    /// True when the quantity was read off a photo ("≈").
    public var gramsEstimated: Bool
    public var nutrients: MealNutrients
    /// "ciqual:<code>" or "ean:<barcode>"; nil for a line typed by hand.
    public var foodRef: String?
    /// The food's values per 100 g when they are known (table or label).
    public var per100: MealPer100?

    public init(id: String, mealId: String, ord: Int, name: String, grams: Double?,
                gramsEstimated: Bool = false, nutrients: MealNutrients, foodRef: String? = nil,
                per100: MealPer100? = nil) {
        self.id = id
        self.mealId = mealId
        self.ord = ord
        self.name = name
        self.grams = grams
        self.gramsEstimated = gramsEstimated
        self.nutrients = nutrients
        self.foodRef = foodRef
        self.per100 = per100
    }

    static func decode(_ row: Row) -> MealItemRow {
        let kcal: Double? = row["kcalPer100g"]
        let protein: Double? = row["proteinPer100g"]
        let carbs: Double? = row["carbsPer100g"]
        let fat: Double? = row["fatPer100g"]
        var per100: MealPer100?
        if let kcal, let protein, let carbs, let fat {
            per100 = MealPer100(kcal: kcal, proteinG: protein, carbsG: carbs, fatG: fat)
        }
        return MealItemRow(id: row["id"], mealId: row["mealId"], ord: row["ord"], name: row["name"],
                           grams: row["grams"], gramsEstimated: (row["gramsEstimated"] as Int) != 0,
                           nutrients: MealNutrients(kcal: row["kcal"], proteinG: row["proteinG"],
                                                    carbsG: row["carbsG"], fatG: row["fatG"]),
                           foodRef: row["foodRef"], per100: per100)
    }
}

/// A meal with its lines, in order. Its energy and macros are `MealMath.totals` of the lines.
public struct MealEntry: Equatable, Sendable {
    public var meal: MealRow
    public var items: [MealItemRow]

    public init(meal: MealRow, items: [MealItemRow]) {
        self.meal = meal
        self.items = items
    }
}

// MARK: - Store

extension WhoopStore {

    /// Save `meal` with ALL of its lines, in one transaction. An existing meal keeps its `createdAt`;
    /// its lines are replaced by `items`, renumbered in the order given and attached to `meal.id`.
    public func saveMeal(_ meal: MealRow, items: [MealItemRow]) async throws {
        try syncWrite { db in
            try db.execute(sql: """
                INSERT INTO meal (id, day, eatenAt, name, origin, favorite, createdAt, updatedAt)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    day = excluded.day, eatenAt = excluded.eatenAt, name = excluded.name,
                    origin = excluded.origin, favorite = excluded.favorite, updatedAt = excluded.updatedAt
                """, arguments: [meal.id, meal.day, meal.eatenAt, meal.name, meal.origin.rawValue,
                                 meal.favorite ? 1 : 0, meal.createdAt, meal.updatedAt])
            try db.execute(sql: "DELETE FROM mealItem WHERE mealId = ?", arguments: [meal.id])
            for (index, item) in items.enumerated() {
                try db.execute(sql: """
                    INSERT INTO mealItem (id, mealId, ord, name, grams, gramsEstimated, kcal, proteinG,
                        carbsG, fatG, foodRef, kcalPer100g, proteinPer100g, carbsPer100g, fatPer100g)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, arguments: [item.id, meal.id, index, item.name, item.grams,
                                     item.gramsEstimated ? 1 : 0, item.nutrients.kcal,
                                     item.nutrients.proteinG, item.nutrients.carbsG, item.nutrients.fatG,
                                     item.foodRef, item.per100?.kcal, item.per100?.proteinG,
                                     item.per100?.carbsG, item.per100?.fatG])
            }
        }
    }

    /// The meals eaten from `fromDay` to `toDay` ("yyyy-MM-dd", both included), in the order they
    /// were eaten, each with its lines.
    public func mealEntries(fromDay: String, toDay: String) async throws -> [MealEntry] {
        try syncRead { db in
            let meals = try Row.fetchAll(db, sql: """
                SELECT * FROM meal WHERE day >= ? AND day <= ? ORDER BY eatenAt ASC, id ASC
                """, arguments: [fromDay, toDay]).map(MealRow.decode)
            return try Self.attachItems(to: meals, in: db)
        }
    }

    /// One meal with its lines, or nil.
    public func mealEntry(id: String) async throws -> MealEntry? {
        try syncRead { db in
            let meals = try Row.fetchAll(db, sql: "SELECT * FROM meal WHERE id = ?", arguments: [id])
                .map(MealRow.decode)
            return try Self.attachItems(to: meals, in: db).first
        }
    }

    /// The latest meal of each name, favorites first, then the most recently eaten: what "Recent"
    /// offers to add again in one tap.
    public func recentMeals(limit: Int) async throws -> [MealEntry] {
        try syncRead { db in
            let meals = try Row.fetchAll(db, sql: """
                SELECT * FROM meal m
                WHERE m.id = (SELECT m2.id FROM meal m2 WHERE m2.name = m.name
                              ORDER BY m2.favorite DESC, m2.eatenAt DESC, m2.id DESC LIMIT 1)
                ORDER BY m.favorite DESC, m.eatenAt DESC, m.id DESC
                LIMIT ?
                """, arguments: [max(limit, 0)]).map(MealRow.decode)
            return try Self.attachItems(to: meals, in: db)
        }
    }

    /// Mark or unmark a meal as a favorite.
    public func setMealFavorite(id: String, favorite: Bool, updatedAt: Int) async throws {
        try syncWrite { db in
            try db.execute(sql: "UPDATE meal SET favorite = ?, updatedAt = ? WHERE id = ?",
                           arguments: [favorite ? 1 : 0, updatedAt, id])
        }
    }

    /// Delete a meal and its lines.
    public func deleteMeal(id: String) async throws {
        try syncWrite { db in
            try db.execute(sql: "DELETE FROM mealItem WHERE mealId = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM meal WHERE id = ?", arguments: [id])
        }
    }

    /// `meals` with their lines, keeping the meals' order.
    static func attachItems(to meals: [MealRow], in db: Database) throws -> [MealEntry] {
        guard !meals.isEmpty else { return [] }
        let marks = Array(repeating: "?", count: meals.count).joined(separator: ",")
        let items = try Row.fetchAll(db, sql: """
            SELECT * FROM mealItem WHERE mealId IN (\(marks)) ORDER BY mealId ASC, ord ASC
            """, arguments: StatementArguments(meals.map(\.id))).map(MealItemRow.decode)
        let byMeal = Dictionary(grouping: items, by: \.mealId)
        return meals.map { MealEntry(meal: $0, items: byMeal[$0.id] ?? []) }
    }
}
