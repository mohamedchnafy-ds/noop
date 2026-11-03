import Foundation
import UserNotifications
import WhoopStore

/// Meal reminders (personal fork, chantier 8, lot 3): opt-in, OFF by default, at most one a day.
///
/// - On a day the week plan sets a session: at a fixed time (12:30 by default, adjustable), only while no meal
///   is logged that day: « Séance prévue aujourd'hui » / « Aucun repas noté pour l'instant. Pense à noter ce que
///   tu as mangé. »
/// - After a session (the Lift Log's or any workout): an hour after it ends, only while no meal is logged
///   since: « Séance terminée » / « Tu as noté un repas depuis ? ». It goes before the fixed-time one when it
///   is still to come.
///
/// Never a deficit stated, never a figure. Re-planned whenever the day widgets are published (a meal, a week
/// plan or a session saved, the return to the foreground), so a meal logged cancels the day's reminder. The
/// next six days' fixed-time reminders are scheduled too, so a day the app is not opened still has one.
enum MealReminder {

    static let enabledKey = "nutrition.mealReminders.enabled"
    static let minutesKey = "nutrition.mealReminders.minutes"
    /// 12:30, Mohamed's choice.
    static let defaultMinutes = 12 * 60 + 30
    /// The fire time of today's pending reminder, kept so a second one is never planned the same day.
    static let todayFireKey = "nutrition.mealReminders.todayFireAt"
    /// How long after a session ends the after-session reminder comes.
    static let afterSessionDelay: TimeInterval = 3600
    /// Today plus the next six days.
    static let daysAhead = 7

    enum Kind: String, Equatable {
        case trainingDay, afterSession
    }

    struct Reminder: Equatable {
        var kind: Kind
        var fireAt: Date
    }

    /// The reminders to have pending at `now`, today's first. Pure.
    /// - Parameters:
    ///   - minutes: the fixed time of the training-day reminder, in minutes since midnight.
    ///   - isTrainingDay: whether the week plan sets a session on that day (given at midnight).
    ///   - mealTimesToday: when today's logged meals were eaten.
    ///   - sessionEndsToday: when today's finished sessions and workouts ended.
    ///   - firedToday: the fire time of a reminder already planned today, if any.
    static func planMealReminders(now: Date, calendar: Calendar, minutes: Int, isTrainingDay: (Date) -> Bool,
                                  mealTimesToday: [Date], sessionEndsToday: [Date], firedToday: Date?) -> [Reminder] {
        let today = calendar.startOfDay(for: now)
        let clamped = min(max(minutes, 0), 24 * 60 - 1)
        func atFixedTime(_ day: Date) -> Date? {
            calendar.date(bySettingHour: clamped / 60, minute: clamped % 60, second: 0, of: day)
        }
        var reminders: [Reminder] = []

        // Today: nothing more once one went off.
        let alreadyWent = firedToday.map { calendar.isDate($0, inSameDayAs: now) && $0 <= now } ?? false
        if !alreadyWent {
            let lastEnd = sessionEndsToday.filter { $0 <= now && calendar.isDate($0, inSameDayAs: now) }.max()
            if let lastEnd, !mealTimesToday.contains(where: { $0 >= lastEnd }) {
                let fireAt = lastEnd.addingTimeInterval(afterSessionDelay)
                if fireAt > now, calendar.isDate(fireAt, inSameDayAs: now) {
                    reminders.append(Reminder(kind: .afterSession, fireAt: fireAt))
                }
            }
            if reminders.isEmpty, mealTimesToday.isEmpty, isTrainingDay(today),
               let fireAt = atFixedTime(today), fireAt > now {
                reminders.append(Reminder(kind: .trainingDay, fireAt: fireAt))
            }
        }

        // The next days: the fixed-time reminder on each planned session day.
        for offset in 1..<daysAhead {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today), isTrainingDay(day),
                  let fireAt = atFixedTime(day) else { continue }
            reminders.append(Reminder(kind: .trainingDay, fireAt: fireAt))
        }
        return reminders
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
        }
    }

    // MARK: Scheduling

    private static let requestPrefix = "meal-reminder-"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    static var reminderMinutes: Int {
        let stored = UserDefaults.standard.object(forKey: minutesKey) as? Int ?? defaultMinutes
        return min(max(stored, 0), 24 * 60 - 1)
    }

    /// The pending requests, one per day: today's id and the next days' ids.
    static func mealReminderRequests(_ reminders: [Reminder], calendar: Calendar) -> [UNNotificationRequest] {
        reminders.map { reminder in
            let text = mealReminderText(reminder.kind)
            let content = UNMutableNotificationContent()
            content.title = text.title
            content.body = text.body
            content.sound = .default
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireAt)
            let day = calendar.dateComponents([.year, .month, .day], from: reminder.fireAt)
            let id = requestPrefix + "\(day.year ?? 0)-\(day.month ?? 0)-\(day.day ?? 0)"
            return UNNotificationRequest(identifier: id, content: content,
                                         trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
        }
    }

    /// Re-plan from the day as the Synthèse and the Nutrition screen read it. Off: every pending one removed.
    @MainActor
    static func refreshMealReminders(repo: Repository, now: Date = Date()) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(requestPrefix) }
        guard isEnabled else {
            center.removePendingNotificationRequests(withIdentifiers: pending)
            UserDefaults.standard.removeObject(forKey: todayFireKey)
            return
        }
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: now)
        guard let resolution = await TodaySessionResolver.resolveTodaySession(
            repo: repo, calendarFrom: Int(dayStart.timeIntervalSince1970),
            calendarTo: Int(now.timeIntervalSince1970), isToday: true, now: now) else { return }
        let meals = await NutritionDayReader.mealsOfDay(repo, dayKey: Repository.localDayKey(dayStart))
        let ends = resolution.performed.compactMap(\.row.endTs) + resolution.otherWorkouts.map(\.endTs)
        let stored = UserDefaults.standard.object(forKey: todayFireKey) as? Double
        let plan = resolution.plan
        let reminders = planMealReminders(
            now: now, calendar: calendar, minutes: reminderMinutes,
            isTrainingDay: { day in
                // Any planned item makes a training day, cardio included (fork chantier 8, lot 4).
                if case .planned = plan.planDecision(for: day, calendar: calendar) { return true }
                return false
            },
            mealTimesToday: meals.map { Date(timeIntervalSince1970: TimeInterval($0.meal.eatenAt)) },
            sessionEndsToday: ends.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            firedToday: stored.map { Date(timeIntervalSince1970: $0) })
        center.removePendingNotificationRequests(withIdentifiers: pending)
        for request in mealReminderRequests(reminders, calendar: calendar) {
            try? await center.add(request)
        }
        // Keep today's fire time while it stands, and the one that already went off today.
        if let today = reminders.first(where: { calendar.isDate($0.fireAt, inSameDayAs: now) }) {
            UserDefaults.standard.set(today.fireAt.timeIntervalSince1970, forKey: todayFireKey)
        } else if let stored, Date(timeIntervalSince1970: stored) > now
                    || !calendar.isDate(Date(timeIntervalSince1970: stored), inSameDayAs: now) {
            UserDefaults.standard.removeObject(forKey: todayFireKey)
        }
    }

    /// Turn the reminders on (asking for notifications first) or off. `completion` gets whether they are on.
    @MainActor
    static func setMealRemindersEnabled(_ on: Bool, repo: Repository, completion: @escaping @MainActor (Bool) -> Void) {
        guard on else {
            UserDefaults.standard.set(false, forKey: enabledKey)
            Task { await refreshMealReminders(repo: repo); completion(false) }
            return
        }
        Task {
            let center = UNUserNotificationCenter.current()
            let status = await center.notificationSettings().authorizationStatus
            var granted = status == .authorized || status == .provisional
            if status == .notDetermined {
                granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            }
            UserDefaults.standard.set(granted, forKey: enabledKey)
            await refreshMealReminders(repo: repo)
            completion(granted)
        }
    }
}
