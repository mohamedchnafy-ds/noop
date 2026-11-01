import XCTest
import GRDB
@testable import WhoopStore

/// Personal fork, Nutrition: the meal journal (migration v51-meal-log) and its arithmetic.
///
/// A meal's nutrients are the sum of its lines, computed on read; each line is rounded once at write.
/// `MealMath` is pinned against the same expected block as its Kotlin twin (`MealMathParityOracleTest`).
final class MealLogStoreTests: XCTestCase {

    private func meal(_ id: String, day: String, at eatenAt: Int, name: String,
                      origin: MealOrigin = .manual, favorite: Bool = false) -> MealRow {
        MealRow(id: id, day: day, eatenAt: eatenAt, name: name, origin: origin, favorite: favorite,
                createdAt: eatenAt, updatedAt: eatenAt)
    }

    private func line(_ id: String, _ name: String, kcal: Int, p: Double, c: Double, f: Double,
                      grams: Double? = nil) -> MealItemRow {
        MealItemRow(id: id, mealId: "", ord: 0, name: name, grams: grams,
                    nutrients: MealNutrients(kcal: kcal, proteinG: p, carbsG: c, fatG: f))
    }

    // MARK: - Migration v51

    func testV51CreatesBothTablesAndIsTheLastMigration() async throws {
        let store = try await WhoopStore.inMemory()
        let tables = try await store.tableNames()
        XCTAssertTrue(tables.contains("meal"))
        XCTAssertTrue(tables.contains("mealItem"))
        XCTAssertEqual(WhoopStore.makeMigrator().migrations.last, "v51-meal-log")
    }

    func testV51IsAdditiveOverAnExistingDatabase() throws {
        let dbQueue = try DatabaseQueue()
        try WhoopStore.makeMigrator().migrate(dbQueue, upTo: "v50-coach-conversations")
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO coachConversation (id, title, createdAt, updatedAt, pinned, titleEdited)
                VALUES ('c', 'Kept', 1, 1, 0, 0)
                """)
        }
        try WhoopStore.makeMigrator().migrate(dbQueue)
        let (meals, kept) = try dbQueue.read { db in
            (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM meal"),
             try String.fetchOne(db, sql: "SELECT title FROM coachConversation WHERE id = 'c'"))
        }
        XCTAssertEqual(meals, 0)
        XCTAssertEqual(kept, "Kept", "rows written before v51 are untouched")
    }

    // MARK: - Store

    func testSaveAndReadADayInTheOrderEaten() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.saveMeal(meal("dinner", day: "2026-11-01", at: 2_000, name: "Dîner"),
                                 items: [line("d1", "Riz", kcal: 260, p: 5.4, c: 56.2, f: 0.6, grams: 200)])
        try await store.saveMeal(meal("lunch", day: "2026-11-01", at: 1_000, name: "Déjeuner", origin: .photo),
                                 items: [line("l1", "Poulet", kcal: 250, p: 46.5, c: 0, f: 5.4, grams: 150),
                                         line("l2", "Riz basmati", kcal: 231, p: 5.2, c: 50.6, f: 0.7, grams: 180)])
        try await store.saveMeal(meal("other", day: "2026-11-02", at: 90_000, name: "Pomme"),
                                 items: [line("o1", "Pomme", kcal: 78, p: 0.5, c: 17.4, f: 0.3)])

        let day = try await store.mealEntries(fromDay: "2026-11-01", toDay: "2026-11-01")
        XCTAssertEqual(day.map(\.meal.id), ["lunch", "dinner"])
        XCTAssertEqual(day[0].meal.origin, .photo)
        XCTAssertEqual(day[0].items.map(\.name), ["Poulet", "Riz basmati"])
        XCTAssertEqual(day[0].items.map(\.ord), [0, 1])
        XCTAssertEqual(day[0].items.map(\.mealId), ["lunch", "lunch"], "lines are attached to the meal saved")
        XCTAssertEqual(MealMath.totals(day[0].items.map(\.nutrients)), MealNutrients(kcal: 481, proteinG: 51.7, carbsG: 50.6, fatG: 6.1))

        let both = try await store.mealEntries(fromDay: "2026-11-01", toDay: "2026-11-02")
        XCTAssertEqual(both.map(\.meal.id), ["lunch", "dinner", "other"])
        let dayTotal = MealMath.totals(both.prefix(2).flatMap(\.items).map(\.nutrients))
        XCTAssertEqual(dayTotal.kcal, 741)
    }

    func testSavingAgainReplacesTheLinesAndKeepsCreatedAt() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.saveMeal(meal("m", day: "2026-11-01", at: 1_000, name: "Déjeuner"),
                                 items: [line("a", "A", kcal: 100, p: 1, c: 1, f: 1),
                                         line("b", "B", kcal: 200, p: 2, c: 2, f: 2)])
        var edited = meal("m", day: "2026-11-01", at: 1_200, name: "Déjeuner léger", favorite: true)
        edited.createdAt = 9_999
        edited.updatedAt = 5_000
        try await store.saveMeal(edited, items: [line("b", "B", kcal: 150, p: 2, c: 2, f: 2)])

        let entry = try await store.mealEntry(id: "m")
        XCTAssertEqual(entry?.meal.name, "Déjeuner léger")
        XCTAssertEqual(entry?.meal.eatenAt, 1_200)
        XCTAssertEqual(entry?.meal.favorite, true)
        XCTAssertEqual(entry?.meal.createdAt, 1_000, "an existing meal keeps when it was first saved")
        XCTAssertEqual(entry?.meal.updatedAt, 5_000)
        XCTAssertEqual(entry?.items.map(\.id), ["b"])
        XCTAssertEqual(entry.map { MealMath.totals($0.items.map(\.nutrients)).kcal }, 150)
    }

    func testLineRoundTripsItsQuantityAndValuesPer100g() async throws {
        let store = try await WhoopStore.inMemory()
        let per100 = MealPer100(kcal: 128.3, proteinG: 2.9, carbsG: 28.1, fatG: 0.4)
        let rice = MealItemRow(id: "r", mealId: "x", ord: 7, name: "Riz basmati, cuit", grams: 180,
                               gramsEstimated: true, nutrients: MealMath.portion(per100: per100, grams: 180),
                               foodRef: "ciqual:9100", per100: per100)
        let typed = line("t", "Pâtes bolognaise", kcal: 596, p: 28, c: 85, f: 16)
        try await store.saveMeal(meal("m", day: "2026-11-01", at: 1_000, name: "Déjeuner"), items: [rice, typed])

        let items = try await store.mealEntry(id: "m")?.items ?? []
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].grams, 180)
        XCTAssertTrue(items[0].gramsEstimated)
        XCTAssertEqual(items[0].foodRef, "ciqual:9100")
        XCTAssertEqual(items[0].per100, per100)
        XCTAssertEqual(items[0].nutrients, MealNutrients(kcal: 231, proteinG: 5.2, carbsG: 50.6, fatG: 0.7))
        XCTAssertNil(items[1].grams)
        XCTAssertFalse(items[1].gramsEstimated)
        XCTAssertNil(items[1].foodRef)
        XCTAssertNil(items[1].per100)
    }

    func testRecentMealsKeepTheLatestOfEachNameWithFavoritesFirst() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.saveMeal(meal("shake-old", day: "2026-10-30", at: 100, name: "Shaker whey", favorite: true),
                                 items: [line("s1", "Whey", kcal: 230, p: 30, c: 10, f: 5)])
        try await store.saveMeal(meal("apple", day: "2026-10-31", at: 200, name: "Pomme"),
                                 items: [line("a1", "Pomme", kcal: 78, p: 0.5, c: 17.4, f: 0.3)])
        try await store.saveMeal(meal("shake-new", day: "2026-11-01", at: 300, name: "Shaker whey"),
                                 items: [line("s2", "Whey", kcal: 230, p: 30, c: 10, f: 5)])
        try await store.saveMeal(meal("oats", day: "2026-11-01", at: 400, name: "Flocons d'avoine"),
                                 items: [line("o1", "Avoine", kcal: 520, p: 18, c: 80, f: 12)])

        let recent = try await store.recentMeals(limit: 10)
        XCTAssertEqual(recent.map(\.meal.id), ["shake-old", "oats", "apple"],
                       "one per name; the favorite version represents its name and comes first")
        XCTAssertEqual(recent[0].items.map(\.id), ["s1"])
        let one = try await store.recentMeals(limit: 1)
        XCTAssertEqual(one.map(\.meal.id), ["shake-old"])
    }

    func testFavoriteAndDelete() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.saveMeal(meal("m", day: "2026-11-01", at: 1_000, name: "Skyr"),
                                 items: [line("i", "Skyr", kcal: 95, p: 16, c: 6, f: 0.3)])
        try await store.setMealFavorite(id: "m", favorite: true, updatedAt: 2_000)
        let favorite = try await store.mealEntry(id: "m")
        XCTAssertEqual(favorite?.meal.favorite, true)
        XCTAssertEqual(favorite?.meal.updatedAt, 2_000)

        try await store.deleteMeal(id: "m")
        let gone = try await store.mealEntry(id: "m")
        XCTAssertNil(gone)
        let orphans = try await store.mealEntries(fromDay: "0000-00-00", toDay: "9999-99-99")
        XCTAssertTrue(orphans.isEmpty)
    }

    func testUnknownOriginReadsAsManual() throws {
        let dbQueue = try DatabaseQueue()
        try WhoopStore.makeMigrator().migrate(dbQueue)
        let meals = try dbQueue.write { db -> [MealRow] in
            try db.execute(sql: """
                INSERT INTO meal (id, day, eatenAt, name, origin, favorite, createdAt, updatedAt)
                VALUES ('m', '2026-11-01', 1, 'X', 'something-new', 0, 1, 1)
                """)
            return try Row.fetchAll(db, sql: "SELECT * FROM meal").map(MealRow.decode)
        }
        XCTAssertEqual(meals.map(\.origin), [.manual])
    }

    func testAMealWithNoLineWeighsNothing() {
        let empty = MealEntry(meal: meal("m", day: "2026-11-01", at: 1, name: "X"), items: [])
        XCTAssertEqual(MealMath.totals(empty.items.map(\.nutrients)),
                       MealNutrients(kcal: 0, proteinG: 0, carbsG: 0, fatG: 0))
    }
}

/// `MealMath` pinned by oracle. The same cases and the same expected block are in the Kotlin twin's
/// `MealMathParityOracleTest`; both suites print the block from their own implementation and compare
/// it verbatim, so the two can only change together. Do not hand-edit one copy.
final class MealMathOracleTests: XCTestCase {

    private static let expected = """
        == kcal ==
        #1 596
        #2 1
        #3 1
        #4 642
        #5 40
        #6 13
        #7 5
        #8 400000
        == tenth ==
        #1 0.1
        #2 1.2
        #3 2.3
        #4 0.0
        #5 123.5
        #6 0.0
        #7 0.0
        #8 1.0
        #9 100000.0
        == portion ==
        #1 231 5.2 50.6 0.7
        #2 249 46.5 0.0 5.4
        #3 78 0.5 17.4 0.3
        #4 113 0.0 0.0 12.5
        #5 0 0.0 0.0 0.0
        #6 0 0.0 0.0 0.0
        #7 0 5.0 5.0 5.0
        #8 130 4.5 19.5 2.3
        == totals ==
        #1 558 52.2 68.0 6.4
        #2 0 0.0 0.0 0.0
        #3 300 0.3 0.6 0.9
        #4 0 0.0 2.0 0.0
        """

    private func text(_ n: MealNutrients) -> String {
        "\(n.kcal) \(n.proteinG) \(n.carbsG) \(n.fatG)"
    }

    private func oracle() -> String {
        let nan = Double.nan
        let inf = Double.infinity
        let kcalCases: [(Double, Double, Double)] = [
            (28, 85, 16), (0.125, 0, 0), (0.1, 0.2, 0), (40, 80, 18), (-5, 10, nan), (inf, 1, 1),
            (0, 0, 0.5), (200_000, 0, 0),
        ]
        let tenthCases: [Double] = [0.05, 1.15, 2.25, 0, 123.456, nan, -3, 0.95, 1e9]
        let portionCases: [(MealPer100, Double)] = [
            (MealPer100(kcal: 128.3, proteinG: 2.9, carbsG: 28.1, fatG: 0.4), 180),
            (MealPer100(kcal: 166.0, proteinG: 31.0, carbsG: 0.0, fatG: 3.6), 150),
            (MealPer100(kcal: 52.0, proteinG: 0.3, carbsG: 11.6, fatG: 0.2), 150),
            (MealPer100(kcal: 900, proteinG: 0, carbsG: 0, fatG: 100), 12.5),
            (MealPer100(kcal: 100, proteinG: 10, carbsG: 10, fatG: 10), 0),
            (MealPer100(kcal: 100, proteinG: 10, carbsG: 10, fatG: 10), nan),
            (MealPer100(kcal: -1, proteinG: 5, carbsG: 5, fatG: 5), 100),
            (MealPer100(kcal: 389, proteinG: 13.5, carbsG: 58.7, fatG: 7.0), 33.3),
        ]
        let portions = portionCases.map { MealMath.portion(per100: $0.0, grams: $0.1) }
        let totalsCases: [[MealNutrients]] = [
            Array(portions.prefix(3)),
            [],
            Array(repeating: MealNutrients(kcal: 100, proteinG: 0.1, carbsG: 0.2, fatG: 0.3), count: 3),
            [MealNutrients(kcal: -50, proteinG: -1, carbsG: 2, fatG: nan)],
        ]
        var out = ["== kcal =="]
        out += kcalCases.enumerated().map { "#\($0.offset + 1) \(MealMath.kcal(proteinG: $0.element.0, carbsG: $0.element.1, fatG: $0.element.2))" }
        out.append("== tenth ==")
        out += tenthCases.enumerated().map { "#\($0.offset + 1) \(MealMath.tenth($0.element))" }
        out.append("== portion ==")
        out += portions.enumerated().map { "#\($0.offset + 1) \(text($0.element))" }
        out.append("== totals ==")
        out += totalsCases.enumerated().map { "#\($0.offset + 1) \(text(MealMath.totals($0.element)))" }
        return out.joined(separator: "\n")
    }

    func testMatchesTheSharedExpectedBlock() {
        XCTAssertEqual(oracle(), Self.expected)
    }
}
