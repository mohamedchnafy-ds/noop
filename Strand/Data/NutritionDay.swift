import Foundation
import StrandAnalytics
import WhoopStore

// Personal fork, Nutrition: one calendar day of the meal journal beside the energy the strap measured
// that day, and the goals that go with it. The Nutrition screen, Today's line under the calories and the
// Coach all read a day through here, so "eaten", "spent" and "balance" are one set of figures.

/// One day of the journal: its meals and, when measured, the day's energy split.
struct NutritionDaySummary: Equatable {
    var dayKey: String
    var meals: [MealEntry]
    /// Today's own estimator over the day's heart rate (`TodayEnergy`), nil when nothing was measured.
    var spent: TodayEnergy.Split?

    /// Every line of the day added together (`MealMath.totals`).
    var eaten: MealNutrients { MealMath.totals(meals.flatMap { $0.items.map(\.nutrients) }) }

    /// Eaten minus spent, in whole kcal; nil without a measured expenditure.
    var balanceKcal: Int? {
        spent.map { eaten.kcal - Int($0.totalKcal.rounded()) }
    }

    /// True when a quantity on any line was estimated from a photo.
    var hasEstimate: Bool { meals.contains { $0.items.contains(where: \.gramsEstimated) } }
}

@MainActor
enum NutritionDayReader {

    /// The meals of `dayKey`, in the order eaten; empty when the store is not open.
    static func mealsOfDay(_ repo: Repository, dayKey: String) async -> [MealEntry] {
        guard let store = await repo.storeHandle() else { return [] }
        return (try? await MealJournal.mealJournalDay(store, day: dayKey)) ?? []
    }

    /// The energy the strap measured on the calendar day `day` falls on, read over the same window and
    /// with the same estimator as Today's calories (`TodayEnergy.heartRateWindow`, `TodayEnergy.split`,
    /// then the Apple Health activity when the strap has nothing).
    static func spentOnDay(_ repo: Repository, profile: ProfileStore, day: Date, now: Date = Date()) async -> TodayEnergy.Split? {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: day)
        let nextStart = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        let isToday = cal.isDate(dayStart, inSameDayAs: now)
        let dayKey = Repository.localDayKey(dayStart)
        let nextKey = Repository.localDayKey(nextStart)
        let mode = DayCycleMode.persisted(UserDefaults.standard.string(forKey: DayCycleMode.storageKey))
        let markers = mode == .sleepOnset
            ? await repo.exploreSeries(key: DayCycleIntelligenceIntegration.onsetKey, source: "my-whoop") : []
        let window = TodayEnergy.heartRateWindow(
            dayStart: Int(dayStart.timeIntervalSince1970),
            dayEnd: Int((isToday ? now : nextStart).timeIntervalSince1970),
            dayKey: dayKey, nextDayKey: nextKey, cycleMarkers: markers)
        let hr = await repo.hrSamples(from: window.lowerBound, to: window.upperBound, limit: 200_000)
        let body = UserProfile(weightKg: profile.weightKg, heightCm: profile.heightCm,
                               age: Double(profile.age), sex: profile.sex)
        let hrmax = profile.effortHRmax
        let row = (isToday ? repo.today : nil) ?? repo.days.last(where: { $0.day == dayKey })
        let rest = row?.restingHr.map(Double.init)
        let split = await Task.detached(priority: .utility) {
            TodayEnergy.split(hr: hr, profile: body, hrmax: hrmax, restingHR: rest)
        }.value
        var imported: Double?
        if split == nil {
            imported = (await repo.appleDailyRows()).filter { $0.day == dayKey }.compactMap { $0.activeKcal }.max()
        }
        return TodayEnergy.resolvedSplit(split, importedActiveKcal: imported)
    }

    /// The day with its meals and its measured energy.
    static func readDay(_ repo: Repository, profile: ProfileStore, day: Date) async -> NutritionDaySummary {
        let dayKey = Repository.localDayKey(day)
        let meals = await mealsOfDay(repo, dayKey: dayKey)
        let spent = await spentOnDay(repo, profile: profile, day: day)
        return NutritionDaySummary(dayKey: dayKey, meals: meals, spent: spent)
    }

    /// The reference expenditure for goals set on `today`: the strap's day totals over the
    /// `NutritionGoals.referenceWindowDays` complete days before it.
    static func referenceBefore(_ repo: Repository, today: Date = Date()) -> NutritionGoals.Reference? {
        let cal = Calendar.current
        let start = cal.startOfDay(for: today)
        let from = cal.date(byAdding: .day, value: -NutritionGoals.referenceWindowDays, to: start) ?? start
        return NutritionGoals.referenceExpenditure(
            totals: repo.days.map { (day: $0.day, kcal: $0.activeKcalEst) },
            fromDay: Repository.localDayKey(from), beforeDay: Repository.localDayKey(start))
    }

    /// The goals for the profile and settings as they stand.
    static func currentPlan(_ repo: Repository, profile: ProfileStore, defaults: UserDefaults = .standard) -> NutritionGoals.Plan {
        NutritionGoals.intakePlan(
            weightKg: profile.weightKg,
            proteinTenths: NutritionGoals.clampedTenths(
                defaults.integer(forKey: NutritionGoals.proteinTenthsKey),
                range: NutritionGoals.proteinTenthsRange, fallback: NutritionGoals.defaultProteinTenths),
            fatTenths: NutritionGoals.clampedTenths(
                defaults.integer(forKey: NutritionGoals.fatTenthsKey),
                range: NutritionGoals.fatTenthsRange, fallback: NutritionGoals.defaultFatTenths),
            goalPercent: NutritionGoals.clampedPercent(defaults.integer(forKey: NutritionGoals.goalPercentKey)),
            reference: referenceBefore(repo))
    }
}
