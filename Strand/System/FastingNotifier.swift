import Foundation
import UserNotifications
import WhoopStore

/// The fast's local notifications (personal fork, chantier 15 PR C): « 16h of fasting reached » at the
/// planned end (on by default), « Halfway through your fast » at half the goal (off by default), both
/// behind the gear of the Jeûne page.
///
/// Re-planned from the one resolver (`FastingLog.resolveFastingState`) after every write to a fast
/// (`FastingLog.onFastingChanged`, wired by the app roots), so a start moved back, a new goal or a stop
/// moves or removes them at once. One pending request per kind, replaced each time. Nothing is sent
/// anywhere: the notifications are planned on the phone.
enum FastingNotifier {

    /// UserDefaults: the end notification, read default-true like the Live Activity switches.
    static let endEnabledKey = "fasting.notifyEnd"
    /// UserDefaults: the halfway notification, off by default.
    static let halfEnabledKey = "fasting.notifyHalf"
    /// The category of both, so a tap opens the Jeûne page (`NotificationPresenter.onFastingTapped`).
    static let categoryId = "fasting"
    private static let requestPrefix = "fasting-"

    static var endEnabled: Bool {
        UserDefaults.standard.object(forKey: endEnabledKey) == nil
            ? true : UserDefaults.standard.bool(forKey: endEnabledKey)
    }

    static var halfEnabled: Bool { UserDefaults.standard.bool(forKey: halfEnabledKey) }

    enum Kind: String, Equatable, CaseIterable {
        case half, end
    }

    struct Planned: Equatable {
        var kind: Kind
        var fireAt: Date
    }

    /// The notifications to have pending for `state` at `now`, the earlier first. Pure. Nothing without a
    /// running fast; a time already past is not planned (a start moved back past the half, say).
    static func fastingNotificationPlan(state: FastingState?, endOn: Bool, halfOn: Bool, now: Date) -> [Planned] {
        guard let state, state.isRunning else { return [] }
        var out: [Planned] = []
        if halfOn {
            let half = state.startedAt.addingTimeInterval(TimeInterval(state.fast.goalMinutes * 60 / 2))
            if half > now { out.append(Planned(kind: .half, fireAt: half)) }
        }
        if endOn, state.plannedEnd > now { out.append(Planned(kind: .end, fireAt: state.plannedEnd)) }
        return out
    }

    /// The title and text of a notification, in the app's language, for a fast aiming at `goalMinutes`.
    static func fastingNotificationText(_ kind: Kind, goalMinutes: Int) -> (title: String, body: String) {
        switch kind {
        case .end:
            return (String(localized: "\(FastingFormat.duration(minutes: goalMinutes)) of fasting reached"),
                    String(localized: "Enjoy your meal. Open NOOP to end the fast or keep going."))
        case .half:
            let half = goalMinutes / 2
            return (String(localized: "Halfway through your fast"),
                    String(localized: "\(FastingFormat.duration(minutes: half)) done, \(FastingFormat.duration(minutes: goalMinutes - half)) to go."))
        }
    }

    /// One request per planned notification, id `fasting-<kind>`.
    static func fastingNotificationRequests(_ plan: [Planned], goalMinutes: Int,
                                            calendar: Calendar = .current) -> [UNNotificationRequest] {
        plan.map { planned in
            let text = fastingNotificationText(planned.kind, goalMinutes: goalMinutes)
            let content = UNMutableNotificationContent()
            content.title = text.title
            content.body = text.body
            content.sound = .default
            content.categoryIdentifier = categoryId
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: planned.fireAt)
            return UNNotificationRequest(identifier: requestPrefix + planned.kind.rawValue, content: content,
                                         trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
        }
    }

    // MARK: Scheduling

    /// Re-plan from the fast as stored: every pending fasting notification removed, the plan added back.
    /// Asks for notifications the first time one is planned (nothing is asked while nothing is planned).
    @MainActor
    static func replanFastingNotifications(_ store: WhoopStore, now: Date = Date()) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(requestPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        let state = await FastingLog.resolveFastingState(store, now: now)
        let plan = fastingNotificationPlan(state: state, endOn: endEnabled, halfOn: halfEnabled, now: now)
        guard let state, !plan.isEmpty else { return }
        guard await requestAuthorizationIfNeeded() else { return }
        for request in fastingNotificationRequests(plan, goalMinutes: state.fast.goalMinutes) {
            try? await center.add(request)
        }
    }

    /// Whether notifications are allowed, asking once when the wearer has never been asked.
    @MainActor
    static func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        }
        return status == .authorized || status == .provisional
    }

    /// Whether the wearer refused notifications: the settings sheet then says where to turn them on.
    @MainActor
    static func notificationsDenied() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }
}
