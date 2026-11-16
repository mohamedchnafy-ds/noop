import Foundation

// Personal fork, chantier 25 — the app side of the wake plan: the settings as stored, the journal of wakes,
// the dismissed mornings, and `WakeSchedule.upcomingWindows`, the ONE funnel every reader of "when will I be
// woken" goes through (the strap arm, the backups, the night watcher, the Alarms screen, the More sheet and
// the Coach). iPhone only, in UserDefaults: not in the `.noopbak`, no migration, nothing on Android.

/// The keys of the adaptive mode and the Fajr alarm. The main alarm's own keys stay `BehaviorStore`'s.
enum WakeAlarmSettings {
    static let adaptiveKey = "alarm.adaptive.enabled"
    static let windowKey = "alarm.adaptive.windowMinutes"
    static let fajrKey = "alarm.fajr.enabled"
    static let fajrLeadKey = "alarm.fajr.leadMinutes"
    static let fajrAdaptiveKey = "alarm.fajr.adaptive"
    static let journalKey = "alarm.wakeJournal.v1"
    static let dismissedKey = "alarm.wakeDismissed.v1"
    /// `BehaviorStore`'s keys, read here so the funnel needs no store instance (the Coach has none).
    static let mainOnKey = "behavior.smartAlarmEnabled"
    static let mainMinutesKey = "behavior.smartAlarmMinutes"
    static let mainWeekdaysKey = "behavior.smartAlarmWeekdays"

    static func adaptiveEnabled(_ d: UserDefaults = .standard) -> Bool { d.bool(forKey: adaptiveKey) }

    static func windowMinutes(_ d: UserDefaults = .standard) -> Int {
        WakePlan.clampedWindow(d.object(forKey: windowKey) as? Int ?? WakePlan.defaultWindowMinutes)
    }

    static func fajrEnabled(_ d: UserDefaults = .standard) -> Bool { d.bool(forKey: fajrKey) }

    static func fajrLeadMinutes(_ d: UserDefaults = .standard) -> Int {
        WakePlan.clampedLead(d.object(forKey: fajrLeadKey) as? Int ?? WakePlan.defaultLeadMinutes)
    }

    /// Adaptive by default: the margin before the adhan is exactly what the mode is for.
    static func fajrAdaptive(_ d: UserDefaults = .standard) -> Bool { d.object(forKey: fajrAdaptiveKey) as? Bool ?? true }

    /// True when the alarms run on the wake plan (adaptive windows or the Fajr alarm). False keeps the classic
    /// alarm on its original path, repeating backup notification included, byte for byte.
    static func usesPlan(_ d: UserDefaults = .standard) -> Bool {
        (d.bool(forKey: mainOnKey) && adaptiveEnabled(d)) || fajrEnabled(d)
    }

    /// True when any alarm is on, the gate for arming the strap at all.
    static func anyAlarmEnabled(_ d: UserDefaults = .standard) -> Bool { d.bool(forKey: mainOnKey) || fajrEnabled(d) }

    /// Main actor: the per-day times are `WindDownNudge`'s, which lives there.
    @MainActor
    static func mainConfig(_ d: UserDefaults = .standard) -> WakeMainConfig {
        WakeMainConfig(enabled: d.bool(forKey: mainOnKey),
                       minutes: d.object(forKey: mainMinutesKey) as? Int ?? 7 * 60,
                       weekdays: Set((d.array(forKey: mainWeekdaysKey) as? [Int] ?? []).filter { (1...7).contains($0) }),
                       overrides: WindDownNudge.perDayWakeOverrides,
                       adaptive: adaptiveEnabled(d), windowMinutes: windowMinutes(d))
    }

    static func fajrConfig(_ d: UserDefaults = .standard) -> WakeFajrConfig {
        WakeFajrConfig(enabled: fajrEnabled(d), leadMinutes: fajrLeadMinutes(d), adaptive: fajrAdaptive(d))
    }
}

/// The journal of wakes and the dismissed mornings, in UserDefaults.
enum WakeJournal {
    static func load(_ d: UserDefaults = .standard) -> [WakeEvent] {
        guard let data = d.data(forKey: WakeAlarmSettings.journalKey) else { return [] }
        return (try? JSONDecoder().decode([WakeEvent].self, from: data)) ?? []
    }

    static func save(_ events: [WakeEvent], _ d: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(events) { d.set(data, forKey: WakeAlarmSettings.journalKey) }
    }

    /// Adds or merges one wake (`WakeLearning.upserting`).
    static func record(_ event: WakeEvent, _ d: UserDefaults = .standard) {
        save(WakeLearning.upserting(event, into: load(d)), d)
    }

    /// Stores the answer of the wake `id`, creating the entry from `fallback` when the night left none (the
    /// phone heard nothing and only the deadline's notification was answered).
    static func answer(id: String, feeling: WakeFeeling, fallback: WakeEvent?, now: Date = Date(),
                       _ d: UserDefaults = .standard) {
        var events = load(d)
        if let index = events.firstIndex(where: { $0.id == id }) {
            events[index].feeling = feeling
            events[index].answeredAt = now
            save(events, d)
        } else if var event = fallback {
            event.feeling = feeling
            event.answeredAt = now
            record(event, d)
        }
    }

    /// The mornings taken off the plan, keeping only those whose deadline is still within a day.
    static func dismissed(now: Date = Date(), _ d: UserDefaults = .standard) -> Set<String> {
        let all = d.dictionary(forKey: WakeAlarmSettings.dismissedKey) as? [String: Double] ?? [:]
        return Set(all.filter { now.timeIntervalSince1970 - $0.value < 24 * 3600 }.keys)
    }

    /// Takes `window` off the plan: its deadline will not be armed again.
    static func dismiss(_ window: WakeWindow, now: Date = Date(), _ d: UserDefaults = .standard) {
        var all = d.dictionary(forKey: WakeAlarmSettings.dismissedKey) as? [String: Double] ?? [:]
        all = all.filter { now.timeIntervalSince1970 - $0.value < 24 * 3600 }
        all[window.id] = window.deadline.timeIntervalSince1970
        d.set(all, forKey: WakeAlarmSettings.dismissedKey)
    }
}

/// What the Coach is told about the alarms (`CoachFiche.alarmBlock`).
struct WakeAlarmFacts: Equatable {
    var mainEnabled: Bool
    var mainMinutes: Int
    var mainWeekdays: Set<Int>
    var adaptive: Bool
    var windowMinutes: Int
    var fajrEnabled: Bool
    var fajrLeadMinutes: Int
    var fajrAdaptive: Bool
    var nextAdhan: Date?
    var adhanFromMosque: Bool
    var next: WakeWindow?
    var mainRiseBpm: Int
    var mainAnswers: Int
    var fajrRiseBpm: Int
    var fajrAnswers: Int
    var lastWake: WakeEvent?
}

enum WakeSchedule {
    /// The wake windows to come, soonest first: THE funnel.
    @MainActor
    static func upcomingWindows(now: Date = Date(), calendar: Calendar = .current,
                                defaults d: UserDefaults = .standard) -> [WakeWindow] {
        let timetable = FajrTimes.cachedTimetable()
        return WakePlan.upcoming(main: WakeAlarmSettings.mainConfig(d), fajr: WakeAlarmSettings.fajrConfig(d),
                                 adhan: { FajrTimes.adhan(on: $0, timetable: timetable)?.time },
                                 dismissed: WakeJournal.dismissed(now: now, d), from: now, calendar: calendar)
    }

    /// The next adhan of Fajr still ahead, and where it came from.
    static func nextAdhan(now: Date = Date(), calendar: Calendar = .current) -> (time: Date, source: FajrSource)? {
        let today = calendar.startOfDay(for: now)
        for offset in 0...2 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let adhan = FajrTimes.adhan(on: day), adhan.time > now else { continue }
            return adhan
        }
        return nil
    }

    /// Everything the Coach states about the alarms, from the same funnel the strap is armed from.
    @MainActor
    static func facts(now: Date = Date(), defaults d: UserDefaults = .standard) -> WakeAlarmFacts {
        let main = WakeAlarmSettings.mainConfig(d)
        let fajr = WakeAlarmSettings.fajrConfig(d)
        let journal = WakeJournal.load(d)
        let adhan = fajr.enabled ? nextAdhan(now: now) : nil
        var adhanFromMosque = false
        if case .mosque? = adhan?.source { adhanFromMosque = true }
        return WakeAlarmFacts(
            mainEnabled: main.enabled, mainMinutes: main.minutes, mainWeekdays: main.weekdays,
            adaptive: main.adaptive, windowMinutes: main.windowMinutes,
            fajrEnabled: fajr.enabled, fajrLeadMinutes: fajr.leadMinutes, fajrAdaptive: fajr.adaptive,
            nextAdhan: adhan?.time, adhanFromMosque: adhanFromMosque,
            next: upcomingWindows(now: now, defaults: d).first,
            mainRiseBpm: WakeLearning.riseBpm(history: journal, kind: .main),
            mainAnswers: WakeLearning.answeredCount(history: journal, kind: .main),
            fajrRiseBpm: WakeLearning.riseBpm(history: journal, kind: .fajr),
            fajrAnswers: WakeLearning.answeredCount(history: journal, kind: .fajr),
            lastWake: journal.max { $0.wokeAt < $1.wokeAt })
    }
}
