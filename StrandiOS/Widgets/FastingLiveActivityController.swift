#if os(iOS)
import Foundation
import ActivityKit
import UIKit

/// Starts, updates and ends the fasting Live Activity (personal fork, chantier 15 PR C).
///
/// Driven by `FastingLog.onFastingChange` (every write to a fast) and by the return to the foreground, always
/// from the state `FastingLog.resolveFastingState` gives, so the banner, the Jeûne page and the Nutrition card
/// cannot disagree. Its own switch, OFF by default (`FastingNotifier.liveActivityKey`).
///
/// iOS ends any Live Activity after 8 hours; a fast lasts longer. A banner iOS ended is started again the next
/// time NOOP comes to the foreground while the fast runs (iOS starts one only for the app on screen).
@MainActor
final class FastingLiveActivityController {
    static let shared = FastingLiveActivityController()

    private var activity: Activity<FastingActivityAttributes>?
    private var lastState: FastingActivityAttributes.ContentState?
    private var isStarting = false

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: FastingNotifier.liveActivityKey) }

    /// The banner's content for `state`, every word translated here.
    static func fastingBannerState(_ state: FastingState) -> FastingActivityAttributes.ContentState {
        let goal = FastingFormat.duration(minutes: state.fast.goalMinutes)
        return FastingActivityAttributes.ContentState(
            startedAt: state.startedAt,
            plannedEnd: state.plannedEnd,
            title: String(localized: "Fasting · \(goal)"),
            endText: String(localized: "end \(FastingFormat.clock(state.plannedEnd))"),
            doneLabel: String(localized: "Fasted"),
            leftLabel: String(localized: "Left"),
            reachedText: String(localized: "\(goal) reached"),
            stopLabel: String(localized: "Stop"))
    }

    /// Show `state` (the running fast), or end the banner when nothing runs or the switch is off.
    func update(_ state: FastingState?) async {
        if let current = activity, !Self.isShowing(current) { activity = nil }
        if activity == nil {
            activity = Activity<FastingActivityAttributes>.activities.first(where: Self.isShowing)
        }
        guard Self.isEnabled, ActivityAuthorizationInfo().areActivitiesEnabled,
              let state, state.isRunning else {
            await end()
            return
        }
        let banner = Self.fastingBannerState(state)
        // The planned end as the stale date: past it, the widget shows the goal reached by itself.
        let content = ActivityContent(state: banner, staleDate: state.plannedEnd)
        if let activity {
            guard banner != lastState else { return }
            lastState = banner
            await activity.update(content)
        } else {
            guard UIApplication.shared.applicationState == .active, !isStarting else { return }
            isStarting = true
            activity = try? Activity.request(attributes: FastingActivityAttributes(), content: content, pushType: nil)
            lastState = activity == nil ? nil : banner
            isStarting = false
        }
    }

    func end() async {
        for act in Activity<FastingActivityAttributes>.activities {
            await act.end(nil, dismissalPolicy: .immediate)
        }
        activity = nil
        lastState = nil
    }

    private static func isShowing(_ activity: Activity<FastingActivityAttributes>) -> Bool {
        switch activity.activityState {
        case .ended, .dismissed: return false
        default: return true
        }
    }
}
#endif
