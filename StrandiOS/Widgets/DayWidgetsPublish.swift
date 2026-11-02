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
                plan: NutritionDayReader.currentPlan(repo, profile: model.profile))
        }

        let rowKey = repo.today?.day ?? Repository.localDayKey(dayStart)
        let night = LiveHRBannerFigures.nightSleepMinutes(own: repo.days.last(where: { $0.day == rowKey }),
                                                          days: repo.days, dayKey: rowKey, carries: true)
        let figures = await repo.sleepSynthesisFigures(now: now)
        let sleep = DayWidgetsContent.sleepSection(nightMinutes: night, figures: figures,
                                                   night: DayWidgetsContent.widgetNight(repo.sleeps, now: now))

        return DayWidgetsContent.daySnapshot(dayStart: dayStart, calendar: calendar, session: session,
                                             nutrition: nutrition, sleep: sleep)
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

    func body(content: Content) -> some View {
        content
            .onChange(of: mealRevision) { _, _ in republish() }
            .onChange(of: weekPlanRaw) { _, _ in republish() }
            .onReceive(savedSessions.dropFirst()) { _ in republish() }
    }

    private func republish() {
        Task { await DayWidgetsSnapshot.publishDayWidgets(from: model, force: true) }
    }
}
#endif
