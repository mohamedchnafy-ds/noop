#if os(iOS)
import Foundation
import ActivityKit
import UIKit

/// Starts, updates and ends the fast's Live Activity (personal fork, chantier 15), on the model of
/// `LiftLiveActivityController`.
///
/// PUSHES ARE CONTENT-DRIVEN. The banner's ring and clocks tick on their own from the dates in the content
/// state, so a push goes out only when the fast itself changes: its start, its goal, its end (the words
/// follow). Called after every write to a fast (`FastingLog.onFastingChanged`) and when the app comes to
/// the foreground: iOS ends a Live Activity about eight hours in and starts one only for the app on
/// screen, so a banner lost overnight comes back the next time NOOP is opened (Mohamed, 8 Nov.).
@MainActor
final class FastingLiveActivityController {
    private var activity: Activity<FastingActivityAttributes>?
    private var lastSignature: String?
    private let authInfo = ActivityAuthorizationInfo()
    private var isStarting = false
    /// The last update sent to iOS, so the banner's button can wait for its own push before its intent returns.
    private var pendingUpdate: Task<Void, Never>?

    /// Drive the banner from the fast's state. `figures` nil means no fast is running, which ends any banner.
    func update(figures: FastingBannerFigures?) {
        guard authInfo.areActivitiesEnabled else { return }
        // A banner the wearer swiped off, or one iOS ended at its eight-hour limit, takes no more updates.
        if let current = activity, !Self.isShowing(current) { activity = nil }
        // Re-adopt an activity that outlived a previous app session (ActivityKit keeps them alive across
        // relaunches), so it is updated or ended rather than duplicated.
        if activity == nil {
            activity = Activity<FastingActivityAttributes>.activities.first(where: Self.isShowing)
        }
        guard UnitPrefs.fastingLiveActivityEnabled(), let figures else {
            if activity != nil { Task { await end() } }
            return
        }
        let state = FastingActivityAttributes.ContentState(
            title: figures.title, startedAt: figures.startedAt, plannedEnd: figures.plannedEnd,
            leftLabel: figures.leftLabel, endLabel: figures.endLabel,
            stopLabel: figures.stopLabel, goalReachedLabel: figures.goalReachedLabel, goalReached: figures.goalReached)
        let signature = [
            figures.title, "\(figures.startedAt.timeIntervalSince1970)", "\(figures.plannedEnd.timeIntervalSince1970)",
            figures.goalReached ? "reached" : "running",
        ].joined(separator: "|")
        // Never stale: a fast legitimately produces no content change for hours, and the clocks are the
        // banner's own.
        let content = ActivityContent(state: state, staleDate: nil)
        if let activity {
            guard signature != lastSignature else { return }
            lastSignature = signature
            pendingUpdate = Task { await activity.update(content) }
        } else {
            // iOS starts a Live Activity only for the app on screen; asked from the background it throws.
            guard UIApplication.shared.applicationState == .active, !isStarting else { return }
            isStarting = true
            do {
                activity = try Activity.request(attributes: FastingActivityAttributes(), content: content, pushType: nil)
                lastSignature = signature
            } catch {
                activity = nil
            }
            isStarting = false
        }
    }

    /// Returns once the last update sent to the banner has reached iOS (the Stop button's intent waits for it).
    func flushUpdate() async {
        await pendingUpdate?.value
    }

    func end() async {
        for act in Activity<FastingActivityAttributes>.activities {
            await act.end(nil, dismissalPolicy: .immediate)
        }
        activity = nil
        lastSignature = nil
    }

    private static func isShowing(_ activity: Activity<FastingActivityAttributes>) -> Bool {
        switch activity.activityState {
        case .ended, .dismissed: return false
        default: return true
        }
    }
}
#endif
