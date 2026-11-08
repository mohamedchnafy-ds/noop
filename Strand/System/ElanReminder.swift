import Foundation
import UserNotifications
import WhoopStore

/// Élan's reminders (personal fork, chantier 10 PR C): local notifications, planned when the app runs, that
/// bring Élan to the wearer on the days without (mockup v2.1 screens 4 and 6). Four in the shared budget
/// (`ReminderPlanner`): the day after a missed session (18:00, the short session proposed, with its two
/// actions), an hour before a planned session (the plan's usual hour), after three days without a session
/// (the wearer's why), the week's recap (Sunday 19:00); and the morning weigh-in (07:30, « Noter » / « Plus
/// tard »), apart from the budget. Never a figure of weight in a notification. The rules are pure
/// (`planElanReminders`, `ElanReminderTests`); the gathering reads `ElanResolver.loadElanState`, the one
/// resolver of what Élan states.
enum ElanReminder {

    // MARK: Settings (ON by default, the mockup's switches)

    static let missedKey = "elan.reminders.missed"
    static let plannedKey = "elan.reminders.planned"
    static let threeDaysKey = "elan.reminders.threeDays"
    static let weeklyKey = "elan.reminders.weekly"
    static let weighKey = "elan.reminders.weighIn"
    static let weighMinutesKey = "elan.reminders.weighMinutes"

    /// 18:00: the day after a miss, and the third day without a session.
    static let missedMinutes = 18 * 60
    static let threeDaysMinutes = 18 * 60
    /// Sunday, 19:00.
    static let weeklyMinutes = 19 * 60
    /// 07:30, before breakfast.
    static let defaultWeighMinutes = 7 * 60 + 30
    /// The planned-session reminder comes this long before the plan's usual hour.
    static let plannedLeadMinutes = 60
    /// The plan's usual hour when none was set (the mockup's 18:30).
    static let defaultSessionMinutes = 18 * 60 + 30
    /// « Après 3 jours sans séance ».
    static let threeDays = 3
    /// Today plus the next six days.
    static let daysAhead = 7
    /// How long « Plus tard » puts the weigh-in off.
    static let snoozeInterval: TimeInterval = 2 * 3600

    /// Notification categories (`registerCategories`): the missed session's actions, the weigh-in's, a tap
    /// that opens Élan, a meal reminder's tap.
    static let categoryPrefix = "elan"
    static let missedCategoryId = "elan-missed"
    static let weighCategoryId = "elan-weigh"
    static let plainCategoryId = "elan"
    static let mealCategoryId = "elan-meal"
    static let shortSessionActionId = "elan.shortSession"
    static let notTodayActionId = "elan.notToday"
    static let logWeighActionId = "elan.logWeigh"
    static let laterActionId = "elan.later"
    static let snoozeRequestId = "elan-weigh-later"

    struct Settings: Equatable {
        var missedOn = true
        var plannedOn = true
        var threeDaysOn = true
        var weeklyOn = true
        var weighOn = true
        var weighMinutes = ElanReminder.defaultWeighMinutes
    }

    static func settings(_ d: UserDefaults = .standard) -> Settings {
        func on(_ key: String) -> Bool { d.object(forKey: key) as? Bool ?? true }
        let minutes = d.object(forKey: weighMinutesKey) as? Int ?? defaultWeighMinutes
        return Settings(missedOn: on(missedKey), plannedOn: on(plannedKey), threeDaysOn: on(threeDaysKey),
                        weeklyOn: on(weeklyKey), weighOn: on(weighKey), weighMinutes: min(max(minutes, 0), 24 * 60 - 1))
    }

    // MARK: The rules

    /// What the rules read of the day, resolved once (`ElanResolver.loadElanState`, the plan).
    struct Input: Equatable {
        /// Yesterday's missed session, when the day after a miss is today.
        var missed: ElanMissedSession?
        /// The program the short session is built from, and its length when built.
        var shortTarget: ElanShortTarget?
        var shortMinutes: Int?
        /// « Pas aujourd'hui » tapped, or the short session accepted: nothing more to propose today.
        var shortDecided = false
        /// A session was done today.
        var sessionDoneToday = false
        /// The first program planned on a day, by its "yyyy-MM-dd" key, today and the next days (a day with
        /// only cardio names it instead); absent on a rest day.
        var plannedByDay: [String: String] = [:]
        /// The plan's usual hour, minutes since midnight.
        var sessionMinutes = ElanReminder.defaultSessionMinutes
        var daysSinceLastSession: Int?
        var whyText: String?
        /// The week's tally and Nutrition, for Sunday's recap.
        var weekDone = 0
        var weekPlanned = 0
        var nutritionHeld = 0
        var nutritionLogged = 0
        var weighedToday = false
    }

    /// The candidates to propose at `now` (the budget is the planner's). Pure.
    static func planElanReminders(_ input: Input, settings: Settings, now: Date, calendar: Calendar) -> [ReminderCandidate] {
        let today = calendar.startOfDay(for: now)
        func at(_ minutes: Int, _ day: Date) -> Date? {
            let clamped = min(max(minutes, 0), 24 * 60 - 1)
            return calendar.date(bySettingHour: clamped / 60, minute: clamped % 60, second: 0, of: day)
        }
        func key(_ day: Date) -> String { TrainingCalendar.trainingDayKey(day, calendar: calendar) }
        var out: [ReminderCandidate] = []

        // The day after a miss: the short session, while nothing is decided and nothing done.
        if settings.missedOn, let missed = input.missed, !input.shortDecided, !input.sessionDoneToday,
           let fireAt = at(missedMinutes, today), fireAt > now {
            let text = missedText(missed: missed, shortMinutes: input.shortMinutes)
            out.append(ReminderCandidate(kind: .elanMissed, fireAt: fireAt, title: text.title, body: text.body,
                                         programId: input.shortTarget?.programId ?? missed.programId))
        }

        // An hour before a planned session, today (while none is done) and the next days.
        if settings.plannedOn {
            for offset in 0..<daysAhead {
                guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                      let name = input.plannedByDay[key(day)],
                      let fireAt = at(input.sessionMinutes - plannedLeadMinutes, day), fireAt > now else { continue }
                if offset == 0, input.sessionDoneToday { continue }
                let text = plannedText(name: name, sessionMinutes: input.sessionMinutes)
                out.append(ReminderCandidate(kind: .elanPlanned, fireAt: fireAt, title: text.title, body: text.body))
            }
        }

        // The third day without a session: today when it is the third, else the day it will be.
        if settings.threeDaysOn, let since = input.daysSinceLastSession, since <= threeDays {
            let offset = threeDays - since
            if let day = calendar.date(byAdding: .day, value: offset, to: today), let fireAt = at(threeDaysMinutes, day),
               fireAt > now, !(offset == 0 && input.sessionDoneToday) {
                let text = threeDaysText(why: input.whyText)
                out.append(ReminderCandidate(kind: .elanThreeDays, fireAt: fireAt, title: text.title, body: text.body))
            }
        }

        // Sunday's recap, on Sunday itself (its figures are the day's).
        if settings.weeklyOn, TrainingCalendar.isoWeekday(today, calendar: calendar) == 7,
           let fireAt = at(weeklyMinutes, today), fireAt > now {
            let text = weeklyText(done: input.weekDone, planned: input.weekPlanned, held: input.nutritionHeld,
                                  logged: input.nutritionLogged)
            out.append(ReminderCandidate(kind: .elanWeekly, fireAt: fireAt, title: text.title, body: text.body))
        }

        // The morning weigh-in, every day, today only while none is logged.
        if settings.weighOn {
            let text = weighText()
            for offset in 0..<daysAhead {
                if offset == 0, input.weighedToday { continue }
                guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                      let fireAt = at(settings.weighMinutes, day), fireAt > now else { continue }
                out.append(ReminderCandidate(kind: .elanWeighIn, fireAt: fireAt, title: text.title, body: text.body))
            }
        }
        return out.sorted { $0.fireAt < $1.fireAt }
    }

    // MARK: Words

    static func missedText(missed: ElanMissedSession, shortMinutes: Int?) -> (title: String, body: String) {
        let title = String(localized: "\(missed.name) was yesterday")
        if let shortMinutes, shortMinutes > 0 {
            return (title, String(localized: "\(shortMinutes) minutes tonight are enough to keep the rhythm. Your loads are ready."))
        }
        return (title, String(localized: "Twenty minutes tonight are enough to keep the rhythm."))
    }

    static func plannedText(name: String, sessionMinutes: Int) -> (title: String, body: String) {
        (String(localized: "\(name) at \(TodaySynthesisLogic.clock(sessionMinutes))"),
         String(localized: "In an hour. Your loads are ready."))
    }

    static func threeDaysText(why: String?) -> (title: String, body: String) {
        let title = String(localized: "Three days without a session")
        if let why = why?.trimmingCharacters(in: .whitespacesAndNewlines), !why.isEmpty {
            return (title, String(why.prefix(140)))
        }
        return (title, String(localized: "A short one is enough to start again. Your before / now is in Élan."))
    }

    static func weeklyText(done: Int, planned: Int, held: Int, logged: Int) -> (title: String, body: String) {
        let title = planned > 0 ? String(localized: "Your week: \(done) / \(planned) sessions")
                                : String(localized: "Your week: \(done) sessions")
        let body = logged > 0 ? String(localized: "Nutrition held \(held) days out of \(logged).")
                              : String(localized: "The recap is in Élan.")
        return (title, body)
    }

    static func weighText() -> (title: String, body: String) {
        (String(localized: "Morning weigh-in"), String(localized: "30 seconds, before eating. Only your trend counts."))
    }

    // MARK: Gathering

    /// Today's Élan candidates, from the one resolver (`ElanResolver.loadElanState`) and the plan. Empty when
    /// the store is closed.
    @MainActor
    static func elanReminderCandidates(repo: Repository, profile: ProfileStore, now: Date = Date(),
                                       defaults: UserDefaults = .standard) async -> [ReminderCandidate] {
        let prefs = Self.settings(defaults)
        guard let state = await ElanResolver.loadElanState(repo: repo, profile: profile, now: now, defaults: defaults) else {
            return []
        }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let plan = TrainingWeekPlan.loadWeekPlan(defaults, now: now, calendar: calendar)
        var names: [String: String] = [:]
        if let store = await repo.storeHandle() {
            for program in (try? await store.liftPrograms(deviceId: repo.deviceId)) ?? [] { names[program.id] = program.name }
        }
        var plannedByDay: [String: String] = [:]
        for offset in 0..<daysAhead {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  case .planned(let items) = plan.planDecision(for: day, calendar: calendar),
                  let first = items.first else { continue }
            let key = TrainingCalendar.trainingDayKey(day, calendar: calendar)
            switch first {
            case .program(let id):
                plannedByDay[key] = names[id] ?? String(localized: "Session")
            case .cardio(let sport, let minutes):
                plannedByDay[key] = TodaySessionResolver.cardioName(sport, minutes: minutes)
            }
        }
        var shortMinutes: Int?
        if let target = state.shortTarget, state.shortSessionAccepted == nil, !state.shortSessionDismissed {
            shortMinutes = await ElanShortSession.loadElanShortSession(repo: repo, programId: target.programId)?.estimatedMinutes
        }
        let todayMark = state.week.days.first(where: { $0.key == state.today })?.mark
        let input = Input(missed: state.missedYesterday, shortTarget: state.shortTarget, shortMinutes: shortMinutes,
                          shortDecided: state.shortSessionDismissed || state.shortSessionAccepted != nil,
                          sessionDoneToday: todayMark == .done,
                          plannedByDay: plannedByDay,
                          sessionMinutes: plan.sessionMinutes ?? defaultSessionMinutes,
                          daysSinceLastSession: state.daysSinceLastSession,
                          whyText: state.why,
                          weekDone: state.week.done, weekPlanned: state.week.planned,
                          nutritionHeld: state.week.nutritionHeldDays, nutritionLogged: state.week.nutritionLoggedDays,
                          weighedToday: state.weight.latest?.day == state.today)
        return planElanReminders(input, settings: prefs, now: now, calendar: calendar)
    }

    // MARK: Notification actions

    /// What a tap or an action on one of these notifications asks of the app (`NotificationPresenter`).
    enum Action: Equatable {
        /// The missed-session notification's « Séance courte », or its tap: Élan on the short-session sheet.
        case openShortSession
        /// « Pas aujourd'hui »: remembered for the day, nothing opened.
        case notToday
        /// The weigh-in's « Noter », or its tap: Élan on the weigh-in sheet.
        case openWeighIn
        /// « Plus tard »: the weigh-in again in two hours, nothing opened.
        case weighLater
        /// Any other tap: Élan.
        case openElan
        /// A meal reminder's tap: Nutrition.
        case openNutrition
    }

    /// The action a response means, from its notification's category and the action tapped (the
    /// notification's own tap is `UNNotificationDefaultActionIdentifier`).
    static func elanAction(category: String, actionIdentifier: String) -> Action? {
        switch category {
        case missedCategoryId:
            return actionIdentifier == notTodayActionId ? .notToday : .openShortSession
        case weighCategoryId:
            return actionIdentifier == laterActionId ? .weighLater : .openWeighIn
        case plainCategoryId:
            return .openElan
        case mealCategoryId:
            return .openNutrition
        default:
            return nil
        }
    }

    /// Registers the categories with their actions: the first `UNNotificationCategory` of the app. Called
    /// once at launch by the iOS app root.
    static func registerCategories() {
        let shortSession = UNNotificationAction(identifier: shortSessionActionId,
                                                title: String(localized: "Short session"), options: [.foreground])
        let notToday = UNNotificationAction(identifier: notTodayActionId, title: String(localized: "Not today"), options: [])
        let log = UNNotificationAction(identifier: logWeighActionId, title: String(localized: "Log it"), options: [.foreground])
        let later = UNNotificationAction(identifier: laterActionId, title: String(localized: "Later"), options: [])
        let categories: Set<UNNotificationCategory> = [
            UNNotificationCategory(identifier: missedCategoryId, actions: [shortSession, notToday], intentIdentifiers: []),
            UNNotificationCategory(identifier: weighCategoryId, actions: [log, later], intentIdentifiers: []),
            UNNotificationCategory(identifier: plainCategoryId, actions: [], intentIdentifiers: []),
            UNNotificationCategory(identifier: mealCategoryId, actions: [], intentIdentifiers: []),
        ]
        UNUserNotificationCenter.current().setNotificationCategories(categories)
    }

    /// « Plus tard »: the weigh-in again in two hours, unless that lands in the quiet hours or on another day.
    @MainActor
    static func snoozeWeighIn(now: Date = Date(), defaults: UserDefaults = .standard) async {
        let calendar = Calendar.current
        let fireAt = now.addingTimeInterval(snoozeInterval)
        guard calendar.isDate(fireAt, inSameDayAs: now) else { return }
        let parts = calendar.dateComponents([.hour, .minute], from: fireAt)
        let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        guard !ReminderPlanner.quietHours(defaults).contains(minutes) else { return }
        let text = weighText()
        let content = UNMutableNotificationContent()
        content.title = text.title
        content.body = text.body
        content.sound = .default
        content.categoryIdentifier = weighCategoryId
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [snoozeRequestId])
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: snoozeInterval, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: snoozeRequestId, content: content, trigger: trigger))
    }
}
