import Foundation
import WhoopStore

// Personal fork, chantier 8 (lot 3): the Nutrition history, 7 or 30 days.
//
// Every day is a `NutritionDaySummary`, the one the day screen reads, so a day's eaten, spent and balance in
// the history are the figures its own page shows. Three rules (dossier §2.6 bis):
// - a day with no meal written down is a hole, never 0 kcal: an empty journal is not a fast, and a 0 would
//   print a deficit that never happened;
// - the goals are the CURRENT ones (no dated snapshot of the goals is kept), and the screen says so;
// - the balance is an estimate, as on the day page (the expenditure is the strap's estimate).
// The range is the N complete days before today: today is still being written, it is on the page above.

/// One day of the history.
struct NutritionHistoryDay: Equatable, Identifiable {
    let dayKey: String
    /// Local noon of the day, where its bar is drawn.
    let date: Date
    /// What the day's meals add up to; nil when no meal was written down that day (a hole).
    let eaten: MealNutrients?
    /// Eaten minus the estimated expenditure; nil without a meal or without a measured expenditure.
    let balanceKcal: Int?

    var id: String { dayKey }
    var isLogged: Bool { eaten != nil }
}

/// The two ranges the card offers.
enum NutritionHistoryRange: Int, CaseIterable, Identifiable {
    case week = 7
    case month = 30

    var id: Int { rawValue }
}

/// The days of one range against the current goals, with the averages over the logged days only.
struct NutritionHistoryModel: Equatable {
    let days: [NutritionHistoryDay]
    let goalKcal: Int?
    let proteinGoalG: Int?
    let carbsGoalG: Int?
    let fatGoalG: Int?

    init(days: [NutritionHistoryDay], goalKcal: Int?, proteinGoalG: Int?, carbsGoalG: Int?, fatGoalG: Int?) {
        self.days = days
        self.goalKcal = goalKcal
        self.proteinGoalG = proteinGoalG
        self.carbsGoalG = carbsGoalG
        self.fatGoalG = fatGoalG
    }

    init(days: [NutritionHistoryDay], plan: NutritionGoals.Plan) {
        self.init(days: days, goalKcal: plan.intakeKcal,
                  proteinGoalG: plan.proteinG > 0 ? plan.proteinG : nil,
                  carbsGoalG: plan.carbsG,
                  fatGoalG: plan.fatG > 0 ? plan.fatG : nil)
    }

    var loggedDays: [NutritionHistoryDay] { days.filter(\.isLogged) }

    /// The average intake over the logged days, in whole kcal; nil when none is logged.
    var averageKcal: Int? {
        let eaten = loggedDays.compactMap(\.eaten)
        guard !eaten.isEmpty else { return nil }
        return Int((Double(eaten.map(\.kcal).reduce(0, +)) / Double(eaten.count)).rounded())
    }

    /// A macro's average over the logged days, to one decimal; nil when none is logged.
    func averageGrams(_ grams: (MealNutrients) -> Double) -> Double? {
        let eaten = loggedDays.compactMap(\.eaten)
        guard !eaten.isEmpty else { return nil }
        return MealMath.tenth(eaten.map(grams).reduce(0, +) / Double(eaten.count))
    }

    /// The average estimated balance over the days that have one; nil when none has.
    var averageBalanceKcal: Int? {
        let balances = days.compactMap(\.balanceKcal)
        guard !balances.isEmpty else { return nil }
        return Int((Double(balances.reduce(0, +)) / Double(balances.count)).rounded())
    }
}

enum NutritionHistory {

    /// The `count` day keys before `today`'s local day, oldest first ("yyyy-MM-dd", `MealJournal.mealDayKey`).
    static func historyDayKeys(before today: Date, count: Int, calendar: Calendar = .current) -> [String] {
        let start = calendar.startOfDay(for: today)
        return (1...max(1, count)).reversed().compactMap { back in
            calendar.date(byAdding: .day, value: -back, to: start).map { MealJournal.mealDayKey($0, calendar: calendar) }
        }
    }

    /// One history day from the day's summary: no meal, no figures; the balance is the summary's own.
    static func historyDay(_ summary: NutritionDaySummary, calendar: Calendar = .current) -> NutritionHistoryDay {
        let logged = !summary.meals.isEmpty
        return NutritionHistoryDay(dayKey: summary.dayKey, date: noonOf(summary.dayKey, calendar: calendar),
                                   eaten: logged ? summary.eaten : nil,
                                   balanceKcal: logged ? summary.balanceKcal : nil)
    }

    /// Local noon of a "yyyy-MM-dd" day key.
    static func noonOf(_ dayKey: String, calendar: Calendar = .current) -> Date {
        let parts = dayKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return Date(timeIntervalSince1970: 0) }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
            ?? Date(timeIntervalSince1970: 0)
    }

    /// The `range` complete days before today, read as the day page reads a day (`NutritionDayReader`): the
    /// meals of the whole range in one query, then the measured expenditure of the logged days only (a
    /// hole has no balance to show, so its heart rate is never read).
    @MainActor
    static func loadNutritionHistory(_ repo: Repository, profile: ProfileStore, range: NutritionHistoryRange,
                                     now: Date = Date()) async -> [NutritionHistoryDay] {
        let keys = historyDayKeys(before: now, count: range.rawValue)
        guard let first = keys.first, let last = keys.last else { return [] }
        var meals: [MealEntry] = []
        if let store = await repo.storeHandle() {
            meals = (try? await MealJournal.mealJournalRange(store, fromDay: first, toDay: last)) ?? []
        }
        let byDay = Dictionary(grouping: meals, by: \.meal.day)
        var days: [NutritionHistoryDay] = []
        for key in keys {
            let dayMeals = byDay[key] ?? []
            var spent: TodayEnergy.Split?
            if !dayMeals.isEmpty {
                spent = await NutritionDayReader.spentOnDay(repo, profile: profile, day: noonOf(key), now: now)
            }
            days.append(historyDay(NutritionDaySummary(dayKey: key, meals: dayMeals, spent: spent)))
        }
        return days
    }
}
