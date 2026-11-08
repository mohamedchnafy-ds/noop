import Foundation
import WhoopStore

/// Meal reminders (personal fork, chantier 8, lot 3; unified with Élan's in chantier 10 PR C).
///
/// - On a day the week plan sets a session: at a fixed time (12:30 by default, adjustable), only while no meal
///   is logged that day: « Séance prévue aujourd'hui » / « Aucun repas noté pour l'instant. Pense à noter ce que
///   tu as mangé. »
/// - After a session (the Lift Log's or any workout): an hour after it ends, only while no meal is logged
///   since: « Séance terminée » / « Tu as noté un repas depuis ? ».
/// - In the evening (OFF by default): at 21:00, only while no meal is logged that day.
///
/// Never a deficit stated, never a figure. This type only PROPOSES (`planMealReminders`, pure); the shared
/// planner (`ReminderPlanner`) applies the one budget Élan's reminders and these share (at most one a day, or
/// four or two a week), the quiet hours and the same-day priority, and schedules what remains. Re-planned
/// whenever the day widgets are published (a meal, a week plan or a session saved, the return to the
/// foreground), so a meal logged cancels the day's reminder.
enum MealReminder {

    /// The legacy master switch of chantier 8 (« Remind me to log my meals »). Read once, by
    /// `migrateLegacySwitch`: an install that had it OFF keeps its two kinds OFF.
    static let legacyEnabledKey = "nutrition.mealReminders.enabled"
    static let minutesKey = "nutrition.mealReminders.minutes"
    /// Per kind (PR C): the training-day and after-session reminders, ON by default; the evening one, OFF.
    static let trainingDayKey = "nutrition.mealReminders.trainingDay"
    static let afterSessionKey = "nutrition.mealReminders.afterSession"
    static let eveningKey = "nutrition.mealReminders.evening"
    static let eveningMinutesKey = "nutrition.mealReminders.eveningMinutes"
    /// Set once the legacy switch has been read into the per-kind keys.
    static let migratedKey = "nutrition.mealReminders.migrated"
    /// 12:30, Mohamed's choice.
    static let defaultMinutes = 12 * 60 + 30
    /// 21:00, the mockup's evening reminder.
    static let defaultEveningMinutes = 21 * 60
    /// How long after a session ends the after-session reminder comes.
    static let afterSessionDelay: TimeInterval = 3600
    /// Today plus the next six days.
    static let daysAhead = 7

    enum Kind: String, Equatable, CaseIterable {
        case trainingDay, afterSession, evening

        var reminderKind: ReminderKind {
            switch self {
            case .trainingDay: return .mealTrainingDay
            case .afterSession: return .mealAfterSession
            case .evening: return .mealEvening
            }
        }
    }

    struct Reminder: Equatable {
        var kind: Kind
        var fireAt: Date
    }

    /// The reminders to propose at `now`, today's first. Pure.
    /// - Parameters:
    ///   - minutes: the fixed time of the training-day reminder, in minutes since midnight.
    ///   - eveningMinutes: the time of the evening reminder.
    ///   - kinds: the kinds switched on.
    ///   - isTrainingDay: whether the week plan sets a session on that day (given at midnight).
    ///   - mealTimesToday: when today's logged meals were eaten.
    ///   - sessionEndsToday: when today's finished sessions and workouts ended.
    static func planMealReminders(now: Date, calendar: Calendar, minutes: Int, eveningMinutes: Int = defaultEveningMinutes,
                                  kinds: Set<Kind> = [.trainingDay, .afterSession], isTrainingDay: (Date) -> Bool,
                                  mealTimesToday: [Date], sessionEndsToday: [Date]) -> [Reminder] {
        let today = calendar.startOfDay(for: now)
        func clamped(_ minutes: Int) -> Int { min(max(minutes, 0), 24 * 60 - 1) }
        func at(_ minutes: Int, _ day: Date) -> Date? {
            calendar.date(bySettingHour: clamped(minutes) / 60, minute: clamped(minutes) % 60, second: 0, of: day)
        }
        var reminders: [Reminder] = []

        // Today: after the last session when no meal followed it, the fixed time when nothing is logged yet.
        let lastEnd = sessionEndsToday.filter { $0 <= now && calendar.isDate($0, inSameDayAs: now) }.max()
        if kinds.contains(.afterSession), let lastEnd, !mealTimesToday.contains(where: { $0 >= lastEnd }) {
            let fireAt = lastEnd.addingTimeInterval(afterSessionDelay)
            if fireAt > now, calendar.isDate(fireAt, inSameDayAs: now) {
                reminders.append(Reminder(kind: .afterSession, fireAt: fireAt))
            }
        }
        if kinds.contains(.trainingDay), mealTimesToday.isEmpty, isTrainingDay(today),
           let fireAt = at(minutes, today), fireAt > now {
            reminders.append(Reminder(kind: .trainingDay, fireAt: fireAt))
        }
        if kinds.contains(.evening), mealTimesToday.isEmpty, let fireAt = at(eveningMinutes, today), fireAt > now {
            reminders.append(Reminder(kind: .evening, fireAt: fireAt))
        }

        // The next days: the fixed-time reminder on each planned session day; the evening one every day.
        for offset in 1..<daysAhead {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            if kinds.contains(.trainingDay), isTrainingDay(day), let fireAt = at(minutes, day) {
                reminders.append(Reminder(kind: .trainingDay, fireAt: fireAt))
            }
            if kinds.contains(.evening), let fireAt = at(eveningMinutes, day) {
                reminders.append(Reminder(kind: .evening, fireAt: fireAt))
            }
        }
        return reminders.sorted { $0.fireAt < $1.fireAt }
    }

    /// The title and text of a reminder, in the app's language.
    static func mealReminderText(_ kind: Kind) -> (title: String, body: String) {
        switch kind {
        case .trainingDay:
            return (String(localized: "Session planned today"),
                    String(localized: "No meal logged yet. Remember to log what you ate."))
        case .afterSession:
            return (String(localized: "Session done"),
                    String(localized: "Have you logged a meal since?"))
        case .evening:
            return (String(localized: "No meal logged today"),
                    String(localized: "Log what you ate, even roughly."))
        }
    }

    /// A reminder as the shared planner takes it.
    static func mealCandidate(_ reminder: Reminder) -> ReminderCandidate {
        let text = mealReminderText(reminder.kind)
        return ReminderCandidate(kind: reminder.kind.reminderKind, fireAt: reminder.fireAt, title: text.title, body: text.body)
    }

    // MARK: Settings

    /// The kinds switched on. The legacy master switch is carried over once: OFF (the default of chantier
    /// 8) leaves the training-day and after-session kinds OFF; ON, or never set, leaves the new defaults.
    static func enabledKinds(_ d: UserDefaults = .standard) -> Set<Kind> {
        migrateLegacySwitch(d)
        var kinds: Set<Kind> = []
        if d.object(forKey: trainingDayKey) as? Bool ?? true { kinds.insert(.trainingDay) }
        if d.object(forKey: afterSessionKey) as? Bool ?? true { kinds.insert(.afterSession) }
        if d.bool(forKey: eveningKey) { kinds.insert(.evening) }
        return kinds
    }

    /// Reads the chantier 8 master switch into the per-kind keys, once.
    static func migrateLegacySwitch(_ d: UserDefaults = .standard) {
        guard !d.bool(forKey: migratedKey) else { return }
        d.set(true, forKey: migratedKey)
        guard d.object(forKey: legacyEnabledKey) != nil, !d.bool(forKey: legacyEnabledKey) else { return }
        // The switch was turned off: the two kinds it governed stay off.
        if d.object(forKey: trainingDayKey) == nil { d.set(false, forKey: trainingDayKey) }
        if d.object(forKey: afterSessionKey) == nil { d.set(false, forKey: afterSessionKey) }
    }

    static func reminderMinutes(_ d: UserDefaults = .standard) -> Int {
        let stored = d.object(forKey: minutesKey) as? Int ?? defaultMinutes
        return min(max(stored, 0), 24 * 60 - 1)
    }

    static func eveningMinutes(_ d: UserDefaults = .standard) -> Int {
        let stored = d.object(forKey: eveningMinutesKey) as? Int ?? defaultEveningMinutes
        return min(max(stored, 0), 24 * 60 - 1)
    }

    // MARK: Gathering

    /// Today's meal reminders to propose, from the day as the Synthèse and the Nutrition screen read it.
    /// Empty when the store is closed or every kind is off.
    @MainActor
    static func mealReminderCandidates(repo: Repository, now: Date = Date(),
                                       defaults: UserDefaults = .standard) async -> [ReminderCandidate] {
        let kinds = enabledKinds(defaults)
        guard !kinds.isEmpty else { return [] }
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: now)
        guard let resolution = await TodaySessionResolver.resolveTodaySession(
            repo: repo, calendarFrom: Int(dayStart.timeIntervalSince1970),
            calendarTo: Int(now.timeIntervalSince1970), isToday: true, now: now) else { return [] }
        let meals = await NutritionDayReader.mealsOfDay(repo, dayKey: Repository.localDayKey(dayStart))
        let ends = resolution.performed.compactMap(\.row.endTs) + resolution.otherWorkouts.map(\.endTs)
        let plan = resolution.plan
        let reminders = planMealReminders(
            now: now, calendar: calendar, minutes: reminderMinutes(defaults), eveningMinutes: eveningMinutes(defaults),
            kinds: kinds,
            isTrainingDay: { day in
                // Any planned item makes a training day, cardio included (fork chantier 8, lot 4).
                if case .planned = plan.planDecision(for: day, calendar: calendar) { return true }
                return false
            },
            mealTimesToday: meals.map { Date(timeIntervalSince1970: TimeInterval($0.meal.eatenAt)) },
            sessionEndsToday: ends.map { Date(timeIntervalSince1970: TimeInterval($0)) })
        return reminders.map(mealCandidate)
    }
}
