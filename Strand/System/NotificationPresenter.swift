import Foundation
import UserNotifications

/// Foreground presentation delegate for the app's local notifications (wind-down nudge, smart-alarm
/// backup, battery/illness alerts).
///
/// Without a `UNUserNotificationCenterDelegate`, iOS/macOS suppress a notification's banner while the
/// app is in the FOREGROUND (the default). A user testing a reminder with the app open would see
/// nothing and conclude notifications are broken. Returning banner + sound + list here makes them
/// visible whether the app is open or not — matching what the user expects from a reminder.
///
/// Cross-platform (iOS + macOS). Register once at launch:
/// `UNUserNotificationCenter.current().delegate = NotificationPresenter.shared`.
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {

    static let shared = NotificationPresenter()

    private override init() { super.init() }

    /// K5: wired by the app root (`StrandApp` on macOS, `StrandiOSApp` on iOS) at launch to route a
    /// tapped scheduled morning-brief notification to the Coach screen via `NavRouter.openCoach()`. nil
    /// is a safe no-op (the tap is simply not routed) rather than a crash if this ever fires before the
    /// root has wired it.
    var onCoachBriefTapped: (() -> Void)?
    /// Personal fork, chantier 15 PR C: a tapped fasting notification opens the Jeûne page. Wired by the iOS
    /// app root; nil is a no-op.
    var onFastingTapped: (() -> Void)?
    /// Personal fork, chantier 10 PR C: an Élan or meal reminder's tap or action (`ElanReminder.elanAction`:
    /// the short session, « Pas aujourd'hui », the weigh-in, « Plus tard », Élan, Nutrition). Wired by the iOS
    /// app root; nil is a no-op.
    var onElanAction: ((ElanReminder.Action) -> Void)?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    /// Handle a tap on a delivered notification. The scheduled morning-brief category (K5), the fasting one
    /// and Élan's (personal fork) route somewhere; every other notification (wind-down, smart-alarm,
    /// battery/illness) just opens the app to wherever it was, matching the pre-K5 behaviour.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let category = response.notification.request.content.categoryIdentifier
        if category == CoachBriefScheduler.notificationCategoryId {
            onCoachBriefTapped?()
        } else if category == FastingNotifier.categoryId {
            onFastingTapped?()
        } else if let action = ElanReminder.elanAction(category: category, actionIdentifier: response.actionIdentifier) {
            onElanAction?(action)
        }
        completionHandler()
    }
}
