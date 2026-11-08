#if os(iOS)
import Foundation
import SwiftUI
import Combine
import WidgetKit

// Personal fork, chantier 6: the app's side of the three day widgets ("Today's session", "Nutrition",
// "Sleep"). It gathers the day through the funnels Today, Nutrition and Sleep read, has `DayWidgetsContent`
// word it, writes the snapshot into the App Group and reloads only the widgets whose section changed.

extension DayWidgetsSnapshot {
    /// Build today's snapshot and publish it when it changed. Rides every `WidgetSnapshot.publish` (the
    /// foreground, a dashboard refresh, the way to the background, a finished backfill) at most once every
    /// `DayWidgetsPublishGate.interval`; `force` — a meal, a week plan or a session saved — and a day that has
    /// ended skip that spacing.
    @MainActor
    static func publishDayWidgets(from model: AppModel, force: Bool = false) async {
        let now = Date()
        let stored = loadDayWidgets(suiteName: WidgetSnapshot.suiteName)
        let dayEnded = !(stored?.isCurrent(at: now) ?? false)
        guard DayWidgetsPublishGate.admit(now: now, force: force || dayEnded) else { return }
        repeat {
            let snapshot = await buildDayWidgets(from: model, now: Date())
            let previous = loadDayWidgets(suiteName: WidgetSnapshot.suiteName)
            if snapshot != previous {
                snapshot.saveDayWidgets(suiteName: WidgetSnapshot.suiteName)
                for kind in snapshot.changedWidgetKinds(from: previous) {
                    WidgetCenter.shared.reloadTimelines(ofKind: kind)
                }
            }
        } while DayWidgetsPublishGate.finishRun()
        // Personal fork, chantier 8 and chantier 10 PR C: the meal reminders and Élan's follow the same moments
        // (a meal, a plan, a session, Élan's choice, the foreground), through the one shared budget.
        await ReminderPlanner.refreshAllReminders(repo: model.repo, profile: model.profile, now: Date())
    }

    /// Today's three sections. The session and the week over the logical day, as the Synthèse resolves them;
    /// the meals over the calendar day, as the Nutrition screen and the Coach's fiche read them; the night as
    /// Today's Rest ring names it, with the Synthèse's sleep figures.
    @MainActor
    static func buildDayWidgets(from model: AppModel, now: Date) async -> DayWidgetsSnapshot {
        let repo = model.repo
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: Repository.logicalDay(now))

        let resolution = await TodaySessionResolver.resolveTodaySession(
            repo: repo, calendarFrom: Int(dayStart.timeIntervalSince1970),
            calendarTo: Int(now.timeIntervalSince1970), isToday: true, now: now)
        let session = resolution.map { DayWidgetsContent.sessionSection($0, today: dayStart, calendar: calendar) }

        var nutrition: DayWidgetsSnapshot.Nutrition?
        if await repo.storeHandle() != nil {
            let today = calendar.startOfDay(for: now)
            let todayKey = Repository.localDayKey(today)
            let meals = await NutritionDayReader.mealsOfDay(repo, dayKey: todayKey)
            let spent = await NutritionDayReader.spentOnDay(repo, profile: model.profile, day: today, now: now)
            nutrition = DayWidgetsContent.nutritionSection(
                NutritionDaySummary(dayKey: todayKey, meals: meals, spent: spent),
                plan: NutritionDayReader.currentPlan(profile: model.profile))
        }

        let rowKey = repo.today?.day ?? Repository.localDayKey(dayStart)
        let night = LiveHRBannerFigures.nightSleepMinutes(own: repo.days.last(where: { $0.day == rowKey }),
                                                          days: repo.days, dayKey: rowKey, carries: true)
        let figures = await repo.sleepSynthesisFigures(now: now)
        let sleep = DayWidgetsContent.sleepSection(nightMinutes: night, figures: figures,
                                                   night: DayWidgetsContent.widgetNight(repo.sleeps, now: now))

        // Widgets v2: Today's rings, the heart-rate thresholds of the day and the stress card.
        let rings = await widgetRings(model: model, now: now, dayStart: dayStart, nightMinutes: night)
        let midnight = calendar.startOfDay(for: now)
        let heart = await DayWidgetsHeartMemo.heartThresholds(repo: repo, midnight: midnight, now: now)
        var stress: DayWidgetsSnapshot.Stress?
        if let scored = await StressDayCurve.today(repo: repo, now: now, calendar: calendar) {
            let from = Int(midnight.timeIntervalSince1970)
            let stressModel = TodayStressLogic.model(result: scored.result, dayStart: from,
                                                     now: Int(now.timeIntervalSince1970), isToday: true)
            stress = DayWidgetsContent.stressSection(stressModel, dayStart: from)
        }

        return DayWidgetsContent.daySnapshot(dayStart: dayStart, calendar: calendar, session: session,
                                             nutrition: nutrition, sleep: sleep, rings: rings, heart: heart,
                                             stress: stress)
    }

    /// Today's four rings: the activity of the calendar day (the funnel Today and Nutrition read) against
    /// the activity goal Today resolved, and the Charge, Effort and Rest of the glance the app just published
    /// (`WidgetSnapshot.publish`, on Today's own anchor day).
    @MainActor
    private static func widgetRings(model: AppModel, now: Date, dayStart: Date,
                                    nightMinutes: Double?) async -> DayWidgetsSnapshot.Rings? {
        let repo = model.repo
        guard await repo.storeHandle() != nil else { return nil }
        let calendar = Calendar.current
        let activity = await NutritionDayReader.spentOnDay(repo, profile: model.profile,
                                                           day: calendar.startOfDay(for: now), now: now)
        let dayKey = Repository.localDayKey(dayStart)
        let goal = TodayEnergy.goal(setting: UserDefaults.standard.integer(forKey: TodayEnergy.goalKey),
                                    defaultGoal: TodayHeroFigures.activityGoalDefault(dayKey: dayKey))
        let glance = WidgetSnapshot.load()
        let scale = UnitPrefs.resolveEffortScale(UserDefaults.standard.string(forKey: UnitPrefs.effortScaleKey) ?? "")
        let anchor = Repository.widgetAnchor(days: repo.days, now: now)
        return DayWidgetsContent.ringsSection(activity: activity, activityGoal: goal,
                                              charge: glance?.recovery.map(Double.init), effortStored: anchor?.strain,
                                              effortScale: scale, rest: glance?.rest.map(Double.init),
                                              nightMinutes: nightMinutes)
    }
}

/// The heart-rate widget's thresholds, read once a day: the usual rate of each 5-minute slot over the
/// fortnight before (`HabitualHR`) and the awake floor are what Today's card reads, and they do not move
/// during the day. The day's sleep is read again on each build, so a night synced later is left uncoloured.
@MainActor
enum DayWidgetsHeartMemo {
    private static var day: Int?
    private static var habitual: [Int: Double] = [:]
    private static var floor: Double?

    static func heartThresholds(repo: Repository, midnight: Date, now: Date) async -> DayWidgetsSnapshot.Heart? {
        let dayStart = Int(midnight.timeIntervalSince1970)
        let nowTs = Int(now.timeIntervalSince1970)
        let sleep = repo.sleeps
            .map { $0.effectiveStartTs...max($0.effectiveStartTs, $0.endTs) }
            .filter { $0.upperBound > dayStart - 86_400 && $0.lowerBound < nowTs }
        if day != dayStart {
            let zone = TimeZone.current
            let history = await repo.hrBuckets(from: dayStart - HabitualHR.windowDays * 86_400, to: dayStart,
                                               bucketSeconds: HabitualHR.bucketSeconds)
            guard !history.isEmpty else { return nil }
            let historySleep = repo.sleeps.map { $0.effectiveStartTs...max($0.effectiveStartTs, $0.endTs) }
            let (profile, awake) = await Task.detached(priority: .utility) {
                (HabitualHR.profile(buckets: history, zone: zone),
                 TodayHRAlert.awakeFloor(buckets: history, sleep: historySleep, zone: zone))
            }.value
            habitual = profile
            floor = awake
            day = dayStart
        }
        let todayKey = Repository.localDayKey(midnight)
        let resting = repo.days.last(where: { $0.day <= todayKey && $0.restingHr != nil })?.restingHr.map(Double.init)
        return DayWidgetsContent.heartSection(habitual: habitual, awakeFloor: floor, restingHR: resting, sleep: sleep)
    }
}

/// Spaces the day widgets' builds: each reads the day's heart rate for the calories, so the dashboard's
/// refreshes do not each start one. A forced request arriving during a build runs it once more after.
@MainActor
enum DayWidgetsPublishGate {
    static let interval: TimeInterval = 120
    private static var lastStart: Date = .distantPast
    private static var running = false
    private static var again = false

    /// True (and the build counts as started) when one may start now.
    static func admit(now: Date, force: Bool) -> Bool {
        if running {
            if force { again = true }
            return false
        }
        guard force || now.timeIntervalSince(lastStart) >= interval else { return false }
        running = true
        lastStart = now
        return true
    }

    /// Ends a build: true when a forced request came in meanwhile and the build must run again.
    static func finishRun() -> Bool {
        if again {
            again = false
            lastStart = Date()
            return true
        }
        running = false
        return false
    }
}

/// Republishes the day widgets when what they show changes in the app: a meal added, edited or deleted
/// (`MealJournal.revisionKey`), the week plan saved (`TrainingWeekPlan.storageKey`), a Lift Log session saved.
struct DayWidgetsRefreshHooks: ViewModifier {
    let model: AppModel
    let savedSessions: AnyPublisher<Int, Never>
    @AppStorage(MealJournal.revisionKey) private var mealRevision = 0
    @AppStorage(TrainingWeekPlan.storageKey) private var weekPlanRaw = ""
    /// Élan's choice about the short session (personal fork, chantier 10 PR C): it moves today's session.
    @AppStorage(ElanShortSessionChoice.revisionKey) private var elanRevision = 0

    func body(content: Content) -> some View {
        content
            .onChange(of: mealRevision) { _, _ in republish() }
            .onChange(of: weekPlanRaw) { _, _ in republish() }
            .onChange(of: elanRevision) { _, _ in republish() }
            .onReceive(savedSessions.dropFirst()) { _ in republish() }
    }

    private func republish() {
        Task { await DayWidgetsSnapshot.publishDayWidgets(from: model, force: true) }
    }
}
#endif
