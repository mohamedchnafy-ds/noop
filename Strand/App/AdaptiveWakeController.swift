import Foundation
import UserNotifications

// Personal fork, chantier 25 — the adaptive wake at night, and its notifications.
//
// `AppModel` feeds `AdaptiveWakeController.tick` every live heart-rate update. iOS keeps NOOP running in the
// background as a bluetooth-central while the strap streams (`UIBackgroundModes`), so the ticks keep coming
// at night with the screen off. When the session's detector fires inside the window, the strap buzzes (the
// confirmed one-shot buzz, `BLEManager.buzzStrapOnce`) and a notification asks how the wearer feels. The
// strap's firmware alarm stays armed at the deadline the whole time: nothing here can move it later or
// cancel it; only the wearer's answer (or « I'm up ») takes that one morning off the plan.

/// The notifications of the wake plan: the backups at each deadline and the adaptive wake's question.
enum WakeNotification {
    static let adaptiveCategoryId = "noop.wake.adaptive"
    static let deadlineCategoryId = "noop.wake.deadline"
    static let tiredActionId = "noop.wake.tired"
    static let freshActionId = "noop.wake.fresh"
    static let awakeActionId = "noop.wake.awake"
    static let adaptiveRequestId = "smart-alarm-wake-adaptive"
    static let backupIdPrefix = "smart-alarm-wake-plan-"
    /// The ids scheduled last time, so a re-plan removes exactly them.
    static let planIdsKey = "alarm.planBackupIds"

    /// What a tap on one of the actions asks.
    struct Response: Equatable {
        var window: WakeWindow
        var feeling: WakeFeeling?
        var awake: Bool
        var adaptive: Bool
    }

    /// The two categories, added to the app's set by `ElanReminder.registerCategories` (which replaces the
    /// whole set, so every category of the app is listed there).
    static func categories() -> [UNNotificationCategory] {
        let tired = UNNotificationAction(identifier: tiredActionId, title: String(localized: "Tired"), options: [])
        let fresh = UNNotificationAction(identifier: freshActionId, title: String(localized: "Rested"), options: [])
        let awake = UNNotificationAction(identifier: awakeActionId, title: String(localized: "I'm up"), options: [])
        return [
            UNNotificationCategory(identifier: adaptiveCategoryId, actions: [tired, fresh, awake], intentIdentifiers: []),
            UNNotificationCategory(identifier: deadlineCategoryId, actions: [tired, fresh], intentIdentifiers: []),
        ]
    }

    static func userInfo(_ window: WakeWindow) -> [String: Any] {
        ["wakeKind": window.kind.rawValue, "wakeStart": window.start.timeIntervalSince1970,
         "wakeDeadline": window.deadline.timeIntervalSince1970, "wakeAdaptive": window.adaptive]
    }

    static func wakeWindow(from userInfo: [AnyHashable: Any]) -> WakeWindow? {
        guard let raw = userInfo["wakeKind"] as? String, let kind = WakeAlarmKind(rawValue: raw),
              let start = userInfo["wakeStart"] as? Double, let deadline = userInfo["wakeDeadline"] as? Double
        else { return nil }
        return WakeWindow(kind: kind, start: Date(timeIntervalSince1970: start),
                          deadline: Date(timeIntervalSince1970: deadline),
                          adaptive: userInfo["wakeAdaptive"] as? Bool ?? false)
    }

    /// The action tapped on a wake notification, nil for any other notification or a plain tap.
    static func response(category: String, actionIdentifier: String,
                         userInfo: [AnyHashable: Any]) -> Response? {
        guard category == adaptiveCategoryId || category == deadlineCategoryId,
              let window = wakeWindow(from: userInfo) else { return nil }
        let adaptive = category == adaptiveCategoryId
        switch actionIdentifier {
        case tiredActionId: return Response(window: window, feeling: .tired, awake: true, adaptive: adaptive)
        case freshActionId: return Response(window: window, feeling: .fresh, awake: true, adaptive: adaptive)
        case awakeActionId: return Response(window: window, feeling: nil, awake: true, adaptive: adaptive)
        default: return nil
        }
    }

    /// "06:41" in the wearer's clock format.
    static func wakeClock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.activeLocale
        formatter.setLocalizedDateFormatFromTemplate("jj:mm")
        return formatter.string(from: date)
    }

    /// One backup per planned deadline, replacing the previous set. iOS only (macOS keeps its strap alarm).
    ///
    /// One-shot triggers rather than the classic alarm's repeating one: a Fajr deadline moves every day, a
    /// merged morning has no main alarm, and an answered morning must lose its backup without losing the
    /// next. The plan reaches `WakePlan.horizonDays` ahead and is rebuilt on every foreground, reconnect and
    /// settings change, so it does not run dry while the app is used.
    static func schedulePlanBackups(_ windows: [WakeWindow], log: ((String) -> Void)? = nil) {
        #if os(iOS)
        let center = UNUserNotificationCenter.current()
        let defaults = UserDefaults.standard
        center.removePendingNotificationRequests(withIdentifiers: defaults.stringArray(forKey: planIdsKey) ?? [])
        let chosen = Array(windows.prefix(WakePlan.horizonDays))
        defaults.set(chosen.map { backupIdPrefix + $0.id }, forKey: planIdsKey)
        func addRequests() {
            for window in chosen {
                let content = UNMutableNotificationContent()
                switch window.kind {
                case .main:
                    content.title = String(localized: "Smart alarm")
                    content.body = String(localized: "Backup wake: your smart alarm time is here.")
                case .fajr:
                    content.title = String(localized: "Fajr alarm")
                    content.body = String(localized: "Backup wake for Fajr, before the adhan.")
                }
                content.sound = .default
                content.categoryIdentifier = deadlineCategoryId
                content.userInfo = userInfo(window)
                let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second],
                                                            from: window.deadline)
                let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
                center.add(UNNotificationRequest(identifier: backupIdPrefix + window.id, content: content,
                                                 trigger: trigger))
            }
        }
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized:
                addRequests()
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    if granted { addRequests() }
                    else { log?("Wake plan: backup notifications NOT scheduled (notification permission denied)") }
                }
            default:
                log?("Wake plan: backup notifications NOT scheduled (notifications not authorized)")
            }
        }
        #endif
    }

    static func cancelPlanBackups() {
        #if os(iOS)
        let defaults = UserDefaults.standard
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: defaults.stringArray(forKey: planIdsKey) ?? [])
        defaults.removeObject(forKey: planIdsKey)
        #endif
    }

    /// The adaptive wake's question, posted at the buzz. Only when notifications are already allowed: no
    /// permission prompt at six in the morning.
    static func postAdaptiveWake(_ window: WakeWindow, at now: Date) {
        #if os(iOS)
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Adaptive wake")
            content.body = String(localized: "Your strap buzzed at \(wakeClock(now)), in a lighter phase. How do you feel?")
            content.sound = .default
            content.categoryIdentifier = adaptiveCategoryId
            content.userInfo = userInfo(window)
            center.add(UNNotificationRequest(identifier: adaptiveRequestId, content: content, trigger: nil))
        }
        #endif
    }
}

/// The overnight watcher: one `AdaptiveWakeSession` for the next window, fed by the live heart rate.
@MainActor
final class AdaptiveWakeController {
    /// The plan `applySmartAlarm` armed the strap from (`WakeSchedule.upcomingWindows`).
    private(set) var plan: [WakeWindow] = []
    private(set) var session: AdaptiveWakeSession?
    /// The window a passed deadline was last handled for, so it is handled once.
    private var closedWindowId: String?

    /// Buzzes the strap (wired to `BLEManager.buzzStrapOnce`).
    var buzz: () -> Void = {}
    /// The shareable strap log.
    var log: (String) -> Void = { _ in }
    /// Re-arms the strap from a fresh plan (wired to `AppModel.applySmartAlarm`).
    var rearm: () -> Void = {}

    func replan(_ windows: [WakeWindow]) { plan = windows }

    /// Stops the repeat buzzes of `windowId`'s session: the wearer is up.
    func stop(windowId: String) {
        guard session?.window.id == windowId else { return }
        session?.stop()
    }

    /// One live heart-rate tick. `bpm` is the app's smoothed value, nil when nothing streams.
    func tick(bpm: Int?, now: Date = Date()) {
        if let first = plan.first, first.deadline <= now {
            guard closedWindowId != first.id else { return }
            closedWindowId = first.id
            close(first)
            rearm()
            return
        }
        guard let window = plan.first, window.adaptive else { return }
        if session?.window.id != window.id {
            let fresh = AdaptiveWakeSession(window: window,
                                            riseBpm: WakeLearning.riseBpm(history: WakeJournal.load(), kind: window.kind))
            guard fresh.isObserving(at: now) else { return }
            session = fresh
            log("Adaptive wake: listening for the \(window.kind.rawValue) window "
                + "\(WakeNotification.wakeClock(window.start))–\(WakeNotification.wakeClock(window.deadline)), "
                + "threshold +\(fresh.detector.riseBpm) bpm over the night's trough; the strap alarm stays armed at the deadline")
        }
        guard var current = session else { return }
        let step = current.observe(bpm: bpm, at: now)
        session = current
        switch step {
        case .none:
            break
        case .wake:
            buzz()
            WakeNotification.postAdaptiveWake(window, at: now)
            WakeJournal.record(WakeEvent(id: window.id, kind: window.kind, windowStart: window.start,
                                         deadline: window.deadline, wokeAt: now, adaptive: true,
                                         trough: current.detector.trough, bpmAtWake: current.firedBpm,
                                         riseBpm: current.detector.riseBpm, feeling: nil, answeredAt: nil))
            log("Adaptive wake: \(current.firedBpm ?? 0) bpm held +\(current.detector.riseBpm) over the trough of "
                + "\(current.detector.trough ?? 0) bpm, strap buzzed at \(WakeNotification.wakeClock(now)); "
                + "the deadline \(WakeNotification.wakeClock(window.deadline)) stays armed")
        case .rebuzz:
            buzz()
            log("Adaptive wake: repeat buzz \(current.buzzes)/\(AdaptiveWakeSession.buzzCount)")
        }
    }

    /// A deadline passed: what the night came to, and the deadline wake in the journal for the question.
    private func close(_ window: WakeWindow) {
        if window.adaptive, session?.window.id == window.id, let current = session, current.firedAt == nil {
            // Rare-event evidence, always on: says what was observed, not why nothing fired.
            log("Adaptive wake: window ended without a lighter phase (\(current.detector.samples) samples, "
                + "trough \(current.detector.trough.map { "\($0) bpm" } ?? "none")); the strap alarm at the deadline was the wake")
        } else if window.adaptive, session?.window.id != window.id {
            log("Adaptive wake: no live heart rate reached the phone for this window; the strap alarm at the deadline was the wake")
        }
        WakeJournal.record(WakeEvent(id: window.id, kind: window.kind, windowStart: window.start,
                                     deadline: window.deadline, wokeAt: window.deadline, adaptive: false,
                                     trough: session?.detector.trough, bpmAtWake: nil,
                                     riseBpm: session?.detector.riseBpm, feeling: nil, answeredAt: nil))
        if session?.window.id == window.id { session = nil }
    }
}
