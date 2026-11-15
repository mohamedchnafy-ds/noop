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

    /// Spent in whole kcal, rounded as Today's cell rounds it (`TodayEnergy.Split.totalWholeKcal`).
    var spentKcal: Int? { spent?.totalWholeKcal }

    /// Eaten minus spent, in whole kcal; nil without a measured expenditure.
    var balanceKcal: Int? {
        spentKcal.map { eaten.kcal - $0 }
    }

    /// True when a quantity on any line was estimated from a photo.
    var hasEstimate: Bool { meals.contains { $0.items.contains(where: \.gramsEstimated) } }
}

/// A day's « Spent » kept once per data generation (`NutritionDayReader.spentOnDay`): the first reader
/// fixes the figure, every later reader of the same generation gets it back, and a new generation
/// starts afresh. PURE: tested on its own (`NutritionDayTests`).
struct DaySpentMemo {
    /// What the figure was resolved from, minus the clock.
    struct Key: Hashable {
        var dayKey: String
        /// Still being counted (its window ends at the reader's now).
        var open: Bool
        var windowStart: Int
        /// `Repository.refreshSeq` when the reading began.
        var generation: Int
        /// The body, HR max and resting HR the estimator ran with.
        var inputs: String
        /// The recorded sessions' bounds, flattened: a session added or edited is a new key.
        var sessions: [Int]
    }

    private struct Entry {
        let split: TodayEnergy.Split?
    }

    private var entries: [Key: Entry] = [:]

    /// The figure kept for `key`; `.some(nil)` when it was resolved as « nothing measured ».
    func recalled(_ key: Key) -> TodayEnergy.Split?? {
        guard let entry = entries[key] else { return nil }
        return .some(entry.split)
    }

    /// Keeps `split` for `key` unless a figure was kept first, and returns the figure kept. Figures of
    /// other generations are dropped.
    mutating func keep(_ split: TodayEnergy.Split?, for key: Key) -> TodayEnergy.Split? {
        if let entry = entries[key] { return entry.split }
        entries = entries.filter { $0.key.generation == key.generation }
        entries[key] = Entry(split: split)
        return split
    }
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
        let window = await heartRateWindowOfDay(repo, day: day, now: now)
        return await repo.hrSamples(from: window.lowerBound, to: window.upperBound, limit: 200_000)
    }

    /// The window `heartRateOfDay` reads, without reading it.
    static func heartRateWindowOfDay(_ repo: Repository, day: Date, now: Date = Date()) async -> ClosedRange<Int> {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: day)
        let nextStart = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        let mode = DayCycleMode.persisted(UserDefaults.standard.string(forKey: DayCycleMode.storageKey))
        let markers = mode == .sleepOnset
            ? await repo.exploreSeries(key: DayCycleIntelligenceIntegration.onsetKey, source: "my-whoop") : []
        return TodayEnergy.heartRateWindow(
            dayStart: Int(dayStart.timeIntervalSince1970),
            dayEnd: Int((isOpenDay(day, now: now) ? now : nextStart).timeIntervalSince1970),
            dayKey: Repository.localDayKey(dayStart), nextDayKey: Repository.localDayKey(nextStart),
            cycleMarkers: markers)
    }

    /// True when the day `day` falls on is still being counted at `now`: today's calendar day, or the
    /// logical day Today shows in the small hours (`Repository.logicalDayKey`), whose window runs to now.
    static func isOpenDay(_ day: Date, now: Date) -> Bool {
        Calendar.current.isDate(day, inSameDayAs: now)
            || Repository.localDayKey(day) == Repository.logicalDayKey(now)
    }

    /// The day's energy from its heart rate and its recorded sessions with Today's estimator and inputs
    /// (`TodayEnergy.dayEnergySplit`), then the Apple Health activity when the strap has nothing
    /// (`TodayEnergy.resolvedSplit`). Not memoised: every reader goes through `spentOnDay`, which is.
    private static func splitFromSamples(_ repo: Repository, profile: ProfileStore, day: Date, hr: [HRSample],
                                         sessions: [ClosedRange<Int>], now: Date) async -> TodayEnergy.Split? {
        let dayKey = Repository.localDayKey(day)
        let body = UserProfile(weightKg: profile.weightKg, heightCm: profile.heightCm,
                               age: Double(profile.age), sex: profile.sex)
        let hrmax = profile.effortHRmax
        let rest = restingHROfDay(repo, day: day, now: now)
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

    /// The resting heart rate the estimator is anchored on for `day`: the row Today shows for it.
    static func restingHROfDay(_ repo: Repository, day: Date, now: Date = Date()) -> Double? {
        let dayKey = Repository.localDayKey(day)
        let row = (isOpenDay(day, now: now) ? repo.today : nil) ?? repo.days.last(where: { $0.day == dayKey })
        return row?.restingHr.map(Double.init)
    }

    /// The figures already resolved in this data generation (`spentOnDay`).
    private static var spentMemo = DaySpentMemo()

    /// THE ONE RESOLVER of the energy the strap measured on the day `day` falls on: Today's « Spent » cell,
    /// Nutrition's « Spent » and « Net », the Nutrition history, the widgets and the Coach all read it.
    ///
    /// For today the window runs to `now`, and heart rate keeps arriving between two loads without a data
    /// refresh, so two screens computing it a minute apart differed by a kcal (13 Nov. recording: Today
    /// « 1 766 », Nutrition « 1 767 »). The first reading of a day in a data generation
    /// (`Repository.refreshSeq`) is therefore kept and every later reader of the same generation gets
    /// it back, whatever its own clock says: one figure per refresh, one clock for every screen.
    /// `samples`: the day's heart rate when the caller already read it over this same window (Today).
    static func spentOnDay(_ repo: Repository, profile: ProfileStore, day: Date, now: Date = Date(),
                           samples: [HRSample]? = nil) async -> TodayEnergy.Split? {
        let generation = repo.refreshSeq
        let window = await heartRateWindowOfDay(repo, day: day, now: now)
        let hr: [HRSample]
        if let samples {
            hr = samples
        } else {
            hr = await repo.hrSamples(from: window.lowerBound, to: window.upperBound, limit: 200_000)
        }
        let sessions = await recordedSessions(repo, hr: hr, now: now)
        let inputs = [String(profile.weightKg), String(profile.heightCm), String(profile.age), profile.sex,
                      profile.effortHRmax.map { String($0) } ?? "-",
                      restingHROfDay(repo, day: day, now: now).map { String($0) } ?? "-"].joined(separator: "|")
        let key = DaySpentMemo.Key(dayKey: Repository.localDayKey(day), open: isOpenDay(day, now: now),
                                   windowStart: window.lowerBound, generation: generation, inputs: inputs,
                                   sessions: sessions.flatMap { [$0.lowerBound, $0.upperBound] })
        if let kept = spentMemo.recalled(key) { return kept }
        let split = await splitFromSamples(repo, profile: profile, day: day, hr: hr, sessions: sessions, now: now)
        // Another reader of the same generation may have finished first while this one computed: its
        // figure is the one already on screen, so this one adopts it.
        return spentMemo.keep(split, for: key)
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
