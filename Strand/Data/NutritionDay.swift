import Foundation
import StrandAnalytics
import WhoopProtocol
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

    /// The strap's heart rate of the calendar day `day` falls on, over the window Today reads a day's
    /// calories over (`TodayEnergy.heartRateWindow`: from that day's sleep onset when the day cycle
    /// follows sleep, else midnight, up to the next onset, the next midnight, or now for today).
    static func heartRateOfDay(_ repo: Repository, day: Date, now: Date = Date()) async -> [HRSample] {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: day)
        let nextStart = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        let isToday = cal.isDate(dayStart, inSameDayAs: now)
        let mode = DayCycleMode.persisted(UserDefaults.standard.string(forKey: DayCycleMode.storageKey))
        let markers = mode == .sleepOnset
            ? await repo.exploreSeries(key: DayCycleIntelligenceIntegration.onsetKey, source: "my-whoop") : []
        let window = TodayEnergy.heartRateWindow(
            dayStart: Int(dayStart.timeIntervalSince1970),
            dayEnd: Int((isToday ? now : nextStart).timeIntervalSince1970),
            dayKey: Repository.localDayKey(dayStart), nextDayKey: Repository.localDayKey(nextStart),
            cycleMarkers: markers)
        return await repo.hrSamples(from: window.lowerBound, to: window.upperBound, limit: 200_000)
    }

    /// The day's energy from its heart rate and its recorded sessions with Today's estimator and inputs
    /// (`TodayEnergy.dayEnergySplit`), then the Apple Health activity when the strap has nothing
    /// (`TodayEnergy.resolvedSplit`).
    static func spentFromSamples(_ repo: Repository, profile: ProfileStore, day: Date, hr: [HRSample],
                                 now: Date = Date()) async -> TodayEnergy.Split? {
        let dayKey = Repository.localDayKey(day)
        let isToday = Calendar.current.isDate(day, inSameDayAs: now)
        let body = UserProfile(weightKg: profile.weightKg, heightCm: profile.heightCm,
                               age: Double(profile.age), sex: profile.sex)
        let hrmax = profile.effortHRmax
        let row = (isToday ? repo.today : nil) ?? repo.days.last(where: { $0.day == dayKey })
        let rest = row?.restingHr.map(Double.init)
        let sessions = await recordedSessions(repo, hr: hr, now: now)
        let split = await Task.detached(priority: .utility) {
            TodayEnergy.dayEnergySplit(hr: hr, sessions: sessions, profile: body, hrmax: hrmax, restingHR: rest)
        }.value
        var imported: Double?
        if split == nil {
            imported = (await repo.appleDailyRows()).filter { $0.day == dayKey }.compactMap { $0.activeKcal }.max()
        }
        return TodayEnergy.resolvedSplit(split, importedActiveKcal: imported)
    }

    /// The recorded sessions (Lift Log, manual and detected workouts, as the Workouts list shows them) inside
    /// the span `hr` covers, merged and clipped (`TodayEnergy.sessionWindows`); empty without heart rate.
    static func recordedSessions(_ repo: Repository, hr: [HRSample], now: Date = Date()) async -> [ClosedRange<Int>] {
        guard let first = hr.map(\.ts).min(), let last = hr.map(\.ts).max() else { return [] }
        let daysBack = max(2, (Int(now.timeIntervalSince1970) - first) / 86_400 + 2)
        let workouts = await repo.workoutRows(days: daysBack)
        return TodayEnergy.sessionWindows(workouts, within: first...last)
    }

    /// The energy the strap measured on the calendar day `day` falls on, as Today's calories show it.
    static func spentOnDay(_ repo: Repository, profile: ProfileStore, day: Date, now: Date = Date()) async -> TodayEnergy.Split? {
        let hr = await heartRateOfDay(repo, day: day, now: now)
        return await spentFromSamples(repo, profile: profile, day: day, hr: hr, now: now)
    }

    /// The day with its meals and its measured energy.
    static func readDay(_ repo: Repository, profile: ProfileStore, day: Date) async -> NutritionDaySummary {
        let dayKey = Repository.localDayKey(day)
        let meals = await mealsOfDay(repo, dayKey: dayKey)
        let spent = await spentOnDay(repo, profile: profile, day: day)
        return NutritionDaySummary(dayKey: dayKey, meals: meals, spent: spent)
    }

    /// The expenditure the strap measured over the `NutritionGoals.referenceWindowDays` complete days
    /// before `today`: shown beside the goals for information, never used to calculate them.
    static func referenceBefore(_ repo: Repository, today: Date = Date()) -> NutritionGoals.Reference? {
        let cal = Calendar.current
        let start = cal.startOfDay(for: today)
        let from = cal.date(byAdding: .day, value: -NutritionGoals.referenceWindowDays, to: start) ?? start
        return NutritionGoals.referenceExpenditure(
            totals: repo.days.map { (day: $0.day, kcal: $0.activeKcalEst) },
            fromDay: Repository.localDayKey(from), beforeDay: Repository.localDayKey(start))
    }

    /// The body the goals are calculated for: the profile, an unset value reading the estimator's default.
    static func goalBody(_ profile: ProfileStore) -> NutritionGoals.Body {
        NutritionGoals.Body(sex: profile.sex, weightKg: profile.weightKg, heightCm: profile.heightCm,
                            age: Double(profile.age))
    }

    /// The goals for the profile and settings as they stand: the one resolver Nutrition, its history, the
    /// widget and the Coach read (`NutritionGoals.intakePlan`).
    static func currentPlan(profile: ProfileStore, defaults: UserDefaults = .standard) -> NutritionGoals.Plan {
        NutritionGoals.intakePlan(body: goalBody(profile), settings: .storedGoalSettings(defaults))
    }
}
