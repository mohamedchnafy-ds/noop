import Foundation
import UserNotifications

/// The fasting notifications (personal fork, chantier 15 PR C): « 16 h of fasting reached » at the planned end
/// (ON by default) and, when asked, one halfway (OFF by default). Both are local, scheduled from the running
/// fast as `FastingLog` resolves it, and re-planned after every write to a fast (a start, a new start time, a
/// new goal, a stop: `FastingLog.fastingDidChange`) and on each return to the foreground. Nothing running, or
/// the switch off: nothing pending.
enum FastingNotifier {

    /// UserDefaults: the planned-end notification (default ON, read default-true).
    static let endEnabledKey = "fasting.notify.end"
    /// UserDefaults: the halfway notification (default OFF).
    static let halfEnabledKey = "fasting.notify.half"
    /// UserDefaults: the Lock Screen and Dynamic Island banner of a running fast, iOS only (default OFF, the
    /// owner's choice, 8 Nov 2026). Read here so the Jeûne page's settings compile on macOS too.
    static let liveActivityKey = "fasting.liveActivity"
    /// The category a tap is recognised by (`NotificationPresenter` opens the Jeûne page).
    static let categoryId = "fasting"

    static var endEnabled: Bool {
        UserDefaults.standard.object(forKey: endEnabledKey) == nil ? true : UserDefaults.standard.bool(forKey: endEnabledKey)
    }

    static var halfEnabled: Bool { UserDefaults.standard.bool(forKey: halfEnabledKey) }

    enum Kind: String, Equatable, CaseIterable {
        case end, half
        var requestId: String { "fasting-" + rawValue }
    }

    struct Planned: Equatable {
        var kind: Kind
        var fireAt: Date
    }

    /// What to have pending for `state` at `now`. PURE: tested on its own (`FastingNotifierTests`). Only a
    /// running fast plans anything, and only what is still to come: the halfway point (start + goal / 2) and
    /// the planned end.
    static func planFastingNotifications(_ state: FastingState?, endOn: Bool, halfOn: Bool, now: Date) -> [Planned] {
        guard let state, state.isRunning else { return [] }
        var planned: [Planned] = []
        let half = state.startedAt.addingTimeInterval(TimeInterval(state.fast.goalMinutes * 30))
        if halfOn, half > now { planned.append(Planned(kind: .half, fireAt: half)) }
        if endOn, state.plannedEnd > now { planned.append(Planned(kind: .end, fireAt: state.plannedEnd)) }
        return planned
    }

    /// The title and text of one notification, in the app's language.
    static func fastingNotificationText(_ kind: Kind, state: FastingState) -> (title: String, body: String) {
        let goal = FastingFormat.duration(minutes: state.fast.goalMinutes)
        switch kind {
        case .end:
            return (String(localized: "\(goal) of fasting reached"),
                    String(localized: "Enjoy your meal. Open to end the fast or keep going."))
        case .half:
            let half = FastingFormat.duration(minutes: state.fast.goalMinutes / 2)
            return (String(localized: "Halfway through your fast"),
                    String(localized: "\(half) done, \(half) to go · planned end \(FastingFormat.clock(state.plannedEnd))"))
        }
    }

    /// Re-plan from `state` (the running fast resolved by `FastingLog`, or nil). Asks for notifications the
    /// first time a fast runs with one of them on.
    @MainActor
    static func refreshFastingNotifications(_ state: FastingState?, now: Date = Date()) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: Kind.allCases.map(\.requestId))
        let planned = planFastingNotifications(state, endOn: endEnabled, halfOn: halfEnabled, now: now)
        guard let state, !planned.isEmpty else { return }
        let status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        } else if status == .denied {
            return
        }
        for item in planned {
            let text = fastingNotificationText(item.kind, state: state)
            let content = UNMutableNotificationContent()
            content.title = text.title
            content.body = text.body
            content.sound = .default
            content.categoryIdentifier = categoryId
            let delay = max(1, item.fireAt.timeIntervalSince(now))
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: item.kind.requestId, content: content, trigger: trigger))
        }
    }
}
