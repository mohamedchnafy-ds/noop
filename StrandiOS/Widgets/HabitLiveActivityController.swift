#if os(iOS)
import Foundation
import ActivityKit
import UIKit
import WhoopStore

/// Starts, updates and ends the habit stopwatch Live Activity (personal fork, chantier 24 PR C).
///
/// Driven by `HabitLog.onHabitChange` (every write to the habits) and by the return to the foreground, always
/// from `HabitLog.resolveRunningHabit`, so the banner and the Habits screens cannot disagree. On by default
/// (the owner's choice, 15 Nov 2026), within what iOS allows (`areActivitiesEnabled`).
///
/// iOS ends any Live Activity after 8 hours; a banner iOS ended is started again the next time NOOP comes to
/// the foreground while the stopwatch runs (iOS starts one only for the app on screen).
@MainActor
final class HabitLiveActivityController {
    static let shared = HabitLiveActivityController()

    private var activity: Activity<HabitActivityAttributes>?
    private var lastState: HabitActivityAttributes.ContentState?
    private var isStarting = false

    /// The banner's content for the running `session` of `habit`, every word translated here.
    static func habitBannerState(_ session: HabitSessionRow, habit: HabitRow) -> HabitActivityAttributes.ContentState {
        let start = Date(timeIntervalSince1970: TimeInterval(session.startedAt))
        return HabitActivityAttributes.ContentState(
            startedAt: start,
            title: habit.name,
            sinceText: String(localized: "since \(FastingFormat.clock(start))"),
            symbol: habit.symbol,
            stopLabel: String(localized: "Stop"))
    }

    /// Show the running stopwatch, or end the banner when nothing runs.
    func update(running: HabitSessionRow?, habit: HabitRow?) async {
        if let current = activity, !Self.isShowing(current) { activity = nil }
        if activity == nil {
            activity = Activity<HabitActivityAttributes>.activities.first(where: Self.isShowing)
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled, let running, running.endedAt == nil, let habit else {
            await end()
            return
        }
        let banner = Self.habitBannerState(running, habit: habit)
        let content = ActivityContent(state: banner, staleDate: nil)
        if let activity {
            guard banner != lastState else { return }
            lastState = banner
            await activity.update(content)
        } else {
            guard UIApplication.shared.applicationState == .active, !isStarting else { return }
            isStarting = true
            activity = try? Activity.request(attributes: HabitActivityAttributes(), content: content, pushType: nil)
            lastState = activity == nil ? nil : banner
            isStarting = false
        }
    }

    func end() async {
        for act in Activity<HabitActivityAttributes>.activities {
            await act.end(nil, dismissalPolicy: .immediate)
        }
        activity = nil
        lastState = nil
    }

    private static func isShowing(_ activity: Activity<HabitActivityAttributes>) -> Bool {
        switch activity.activityState {
        case .ended, .dismissed: return false
        default: return true
        }
    }

    /// Everything that follows a change to the habits outside the screens: the banner, then the Home Screen
    /// quick action's words (and the menu installed again with them).
    static func refreshHabitSurroundings(_ store: WhoopStore) async {
        let running = await HabitLog.resolveRunningHabit(store)
        let habits = await HabitLog.loadHabitList(store)
        let habit = running.flatMap { open in habits.first { $0.id == open.habitId } }
        await shared.update(running: running, habit: habit)
        await HabitLog.refreshHabitQuickAction(store)
        HomeScreenQuickAction.install(in: UIApplication.shared)
    }
}
#endif
