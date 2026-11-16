import Foundation

// Personal fork, chantier 25 — the adaptive wake and the Fajr alarm.
//
// The pure half of the alarms: which wake windows the next mornings hold, from the main alarm's settings and
// the Fajr timetable. Every reader goes through `WakePlan.upcoming` (through `WakeSchedule` on the app side):
// the strap arm, the backup notifications, the overnight watcher, the screen's countdown, the More sheet row
// and the Coach. One resolver, so no two of them can name a different wake.

/// Which alarm a wake window belongs to.
enum WakeAlarmKind: String, Codable, Equatable {
    case main
    case fajr
}

/// One morning's wake: the adaptive buzz may fire from `start`, and the strap's own alarm is armed at
/// `deadline`, which is never moved later. A classic (non-adaptive) alarm has `start == deadline`.
struct WakeWindow: Equatable, Codable {
    var kind: WakeAlarmKind
    var start: Date
    var deadline: Date
    var adaptive: Bool

    /// Stable for one morning of one alarm: what a dismissal, a journal entry and a notification name.
    var id: String { "\(kind.rawValue)-\(Int(deadline.timeIntervalSince1970))" }

    /// True while `now` is inside the margin the adaptive buzz may use.
    func contains(_ now: Date) -> Bool { now >= start && now < deadline }
}

/// The main alarm's settings, as the Alarms screen stores them.
struct WakeMainConfig: Equatable {
    var enabled: Bool
    /// Earliest acceptable wake (adaptive) or the wake time itself (classic), minutes since local midnight.
    var minutes: Int
    /// Calendar weekdays (1 = Sun … 7 = Sat); empty = every day.
    var weekdays: Set<Int>
    /// Per-weekday wake times (#1864), same meaning as `minutes`.
    var overrides: [Int: Int]
    var adaptive: Bool
    var windowMinutes: Int
}

/// The Fajr alarm's settings: anchored on the adhan, `leadMinutes` before it.
struct WakeFajrConfig: Equatable {
    var enabled: Bool
    var leadMinutes: Int
    var adaptive: Bool
}

enum WakePlan {
    /// Two windows of different alarms whose deadlines are this close make one alarm: the earlier one.
    static let mergeGapMinutes = 45
    /// The windows the Alarms screen offers for the main alarm.
    static let windowChoices = [10, 15, 20, 30, 45, 60]
    static let defaultWindowMinutes = 30
    /// The leads the Fajr alarm offers before the adhan.
    static let leadChoices = [10, 20, 30, 40]
    static let defaultLeadMinutes = 20
    /// How many mornings ahead the plan looks (the backup notifications are scheduled from it).
    static let horizonDays = 8

    /// The window clamped to what the screen offers, so a corrupted value cannot open a 0 or 10 h window.
    static func clampedWindow(_ minutes: Int) -> Int { min(60, max(5, minutes)) }

    /// The lead clamped to the Fajr choices' range.
    static func clampedLead(_ minutes: Int) -> Int { min(40, max(10, minutes)) }

    /// The minute of day the main alarm's deadline lands on for a wake setting of `minutes`.
    ///
    /// Adaptive: the setting is the EARLIEST wake, so the guaranteed one sits `windowMinutes` later. Rolling past
    /// midnight keeps the deadline on the enabled day and lets the window open the evening before, as Android's
    /// `SmartAlarmScheduler.nextDeadline` does.
    static func mainDeadlineMinutes(_ minutes: Int, _ config: WakeMainConfig) -> Int {
        guard config.adaptive else { return minutes }
        return (minutes + clampedWindow(config.windowMinutes)) % (24 * 60)
    }

    /// The main alarm's windows from `now`, soonest first.
    ///
    /// The deadlines come from `AppModel.nextSmartAlarmDate`, the resolver the classic alarm has always been
    /// armed from, fed the deadline minutes. With the adaptive mode off the first deadline is therefore exactly
    /// the time the strap was armed at before this chantier.
    static func mainWindows(_ config: WakeMainConfig, from now: Date, calendar: Calendar) -> [WakeWindow] {
        guard config.enabled else { return [] }
        let window = TimeInterval(clampedWindow(config.windowMinutes) * 60)
        let base = mainDeadlineMinutes(config.minutes, config)
        let overrides = config.overrides.mapValues { mainDeadlineMinutes($0, config) }
        guard let horizon = calendar.date(byAdding: .day, value: horizonDays, to: now) else { return [] }
        var windows: [WakeWindow] = []
        var cursor = now
        while windows.count < horizonDays,
              let deadline = AppModel.nextSmartAlarmDate(minutes: base, weekdays: config.weekdays,
                                                         overrides: overrides, from: cursor, calendar: calendar),
              deadline <= horizon {
            windows.append(WakeWindow(kind: .main,
                                      start: config.adaptive ? deadline.addingTimeInterval(-window) : deadline,
                                      deadline: deadline, adaptive: config.adaptive))
            cursor = deadline
        }
        return windows
    }

    /// The Fajr alarm's windows from `now`, soonest first: `leadMinutes` before each day's adhan.
    ///
    /// Adaptive: the margin before the adhan is the window and the adhan itself is the deadline. Classic: one
    /// buzz at the start of the margin. Never after the adhan either way. A day whose adhan is unknown has no
    /// window (the caller's timetable falls back to a calculation, so that only happens on a bad date).
    static func fajrWindows(_ config: WakeFajrConfig, adhan: (Date) -> Date?,
                            from now: Date, calendar: Calendar) -> [WakeWindow] {
        guard config.enabled else { return [] }
        let lead = TimeInterval(clampedLead(config.leadMinutes) * 60)
        let today = calendar.startOfDay(for: now)
        var windows: [WakeWindow] = []
        for offset in 0...horizonDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let time = adhan(day) else { continue }
            let start = time.addingTimeInterval(-lead)
            let deadline = config.adaptive ? time : start
            guard deadline > now else { continue }
            windows.append(WakeWindow(kind: .fajr, start: start, deadline: deadline, adaptive: config.adaptive))
        }
        return windows
    }

    /// The windows with each close pair of different alarms reduced to its earlier one.
    ///
    /// Sorted by deadline; a window whose deadline is within `mergeGapMinutes` after a kept window of the OTHER
    /// alarm is dropped. Keeping the earlier deadline keeps the Fajr promise (never after the adhan) whichever
    /// of the two comes first. Two windows of the same alarm never merge: they are different mornings.
    static func merged(_ windows: [WakeWindow]) -> [WakeWindow] {
        let gap = TimeInterval(mergeGapMinutes * 60)
        var kept: [WakeWindow] = []
        for window in windows.sorted(by: { $0.deadline < $1.deadline }) {
            let clash = kept.contains { other in
                other.kind != window.kind && window.deadline.timeIntervalSince(other.deadline) <= gap
            }
            if !clash { kept.append(window) }
        }
        return kept
    }

    /// Every wake to come, soonest first: both alarms, merged, without the mornings the wearer already
    /// dismissed (answered the wake question or said they are up), and only deadlines still ahead.
    ///
    /// The windows are built from `mergeGapMinutes` BEFORE now, merged, and only then cut to the future: a Fajr
    /// that rang twenty minutes ago must still absorb the main alarm due in fifteen, or the merge would undo
    /// itself the moment the first deadline passed. Dismissals are applied after the merge for the same
    /// reason: saying you are up for Fajr does not bring back the main alarm it replaced.
    static func upcoming(main: WakeMainConfig, fajr: WakeFajrConfig, adhan: (Date) -> Date?,
                         dismissed: Set<String>, from now: Date, calendar: Calendar) -> [WakeWindow] {
        let since = now.addingTimeInterval(-TimeInterval(mergeGapMinutes * 60))
        let all = mainWindows(main, from: since, calendar: calendar)
            + fajrWindows(fajr, adhan: adhan, from: since, calendar: calendar)
        return merged(all).filter { $0.deadline > now && !dismissed.contains($0.id) }
    }
}
