import Foundation
import UserNotifications
import WhoopStore

// Personal fork, chantier 10 (Élan), PR C: the ONE budget Élan's reminders and the meal reminders share.
//
// Mohamed's rule (5 Nov.): at most one reminder a day (or four, or two, a week), the weigh-in apart; no
// reminder during the quiet hours (21:30–07:00); when two fall the same day, the most useful one goes:
// a missed session, then a planned session, then a meal, then three days without a session, then the
// week's recap. Each source proposes its candidates (`MealReminder.planMealReminders`,
// `ElanReminder.planElanReminders`, both pure); `pickReminders` applies the budget (pure, tested in
// `ReminderPlannerTests`); `refreshAllReminders` schedules what is left and remembers what it scheduled,
// so a reminder that already went off today closes the day whatever is proposed later.

/// Every reminder the planner knows, in the order the same-day rule prefers them.
enum ReminderKind: String, Codable, CaseIterable, Equatable {
    case elanMissed
    case elanPlanned
    case mealTrainingDay
    case mealAfterSession
    case mealEvening
    case elanThreeDays
    case elanWeekly
    case elanWeighIn

    /// Lower goes first when two fall the same day. The three meal kinds share one rank; among equals the
    /// earlier one goes.
    var priority: Int {
        switch self {
        case .elanMissed: return 0
        case .elanPlanned: return 1
        case .mealTrainingDay, .mealAfterSession, .mealEvening: return 2
        case .elanThreeDays: return 3
        case .elanWeekly: return 4
        case .elanWeighIn: return 9
        }
    }

    /// The weigh-in is « à part, hors limite »: it never takes the day's one reminder.
    var countsInBudget: Bool { self != .elanWeighIn }

    /// The notification category: what a tap or an action does (`NotificationPresenter`).
    var categoryId: String {
        switch self {
        case .elanMissed: return ElanReminder.missedCategoryId
        case .elanWeighIn: return ElanReminder.weighCategoryId
        case .elanPlanned, .elanThreeDays, .elanWeekly: return ElanReminder.plainCategoryId
        case .mealTrainingDay, .mealAfterSession, .mealEvening: return ElanReminder.mealCategoryId
        }
    }
}

/// How many in-budget reminders may go: one a day, or four or two a week (and still at most one a day).
enum ReminderBudget: String, CaseIterable, Equatable {
    case daily, fourPerWeek, twoPerWeek

    /// The week's cap; nil for « 1 par jour » (the day cap alone).
    var perWeek: Int? {
        switch self {
        case .daily: return nil
        case .fourPerWeek: return 4
        case .twoPerWeek: return 2
        }
    }
}

/// The hours no reminder goes, in minutes since midnight; a span crossing midnight (21:30 → 07:00) is the usual one.
struct ReminderQuietHours: Equatable {
    var startMinutes: Int
    var endMinutes: Int

    static let standard = ReminderQuietHours(startMinutes: 21 * 60 + 30, endMinutes: 7 * 60)

    /// Whether a time of day (minutes since midnight) falls in the quiet hours.
    func contains(_ minutes: Int) -> Bool {
        if startMinutes == endMinutes { return false }
        if startMinutes < endMinutes { return minutes >= startMinutes && minutes < endMinutes }
        return minutes >= startMinutes || minutes < endMinutes
    }

    /// Whether the time is in the MORNING part of a span crossing midnight (before its end): such a
    /// reminder waits until the quiet hours end; one in the evening part is dropped.
    func isMorningPart(_ minutes: Int) -> Bool {
        startMinutes > endMinutes && minutes < endMinutes
    }
}

/// One reminder a source proposes, worded, before the budget.
struct ReminderCandidate: Equatable {
    var kind: ReminderKind
    var fireAt: Date
    var title: String
    var body: String
    /// What the notification carries for its actions (the program of a missed session).
    var programId: String? = nil
}

/// What was scheduled for a day, kept so a reminder that went off closes its day.
struct ReminderPick: Codable, Equatable {
    var day: String
    var kind: ReminderKind
    var fireAt: Date
}

enum ReminderPlanner {

    /// UserDefaults: the picks scheduled (JSON), the last `pickMemoryDays` days.
    static let picksKey = "reminders.picks"
    static let pickMemoryDays = 14
    /// Request ids: one in-budget reminder per day, the weigh-in apart.
    static let requestPrefix = "reminder-"
    static let weighRequestPrefix = "elan-weigh-"
    /// The ids chantier 8 used, removed once so an upgrade leaves nothing behind.
    static let legacyMealPrefix = "meal-reminder-"

    // MARK: The rule

    /// The candidates to schedule, from everything proposed: past ones dropped; the quiet hours applied (a
    /// morning one waits for their end, an evening one is dropped); one weigh-in a day apart; then, per day,
    /// the one in-budget candidate of best priority (the earlier among equals), a day whose scheduled pick
    /// already went off (`pastPicks`, `fireAt` ≤ `now`) taking none; a weekly budget counts the week's picks
    /// gone and the days chosen in order, and stops at its cap.
    static func pickReminders(candidates: [ReminderCandidate], now: Date, calendar: Calendar,
                              budget: ReminderBudget, quiet: ReminderQuietHours,
                              pastPicks: [ReminderPick]) -> [ReminderCandidate] {
        func dayKey(_ date: Date) -> String { TrainingCalendar.trainingDayKey(date, calendar: calendar) }
        func minutesOfDay(_ date: Date) -> Int {
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
        // Quiet hours, then the past.
        var usable: [ReminderCandidate] = []
        for var candidate in candidates {
            let minutes = minutesOfDay(candidate.fireAt)
            if quiet.contains(minutes) {
                guard quiet.isMorningPart(minutes),
                      let moved = calendar.date(bySettingHour: quiet.endMinutes / 60, minute: quiet.endMinutes % 60,
                                                second: 0, of: candidate.fireAt) else { continue }
                candidate.fireAt = moved
            }
            guard candidate.fireAt > now else { continue }
            usable.append(candidate)
        }
        usable.sort { $0.fireAt < $1.fireAt }

        var picked: [ReminderCandidate] = []
        // The weigh-in: one a day, the earliest.
        var weighDays: Set<String> = []
        for candidate in usable where !candidate.kind.countsInBudget {
            if weighDays.insert(dayKey(candidate.fireAt)).inserted { picked.append(candidate) }
        }
        // The budget.
        let gone = pastPicks.filter { $0.fireAt <= now && $0.kind.countsInBudget }
        let goneDays = Set(gone.map(\.day))
        let byDay = Dictionary(grouping: usable.filter(\.kind.countsInBudget)) { dayKey($0.fireAt) }
        var weekCounts: [Date: Int] = [:]
        func weekStart(_ date: Date) -> Date { TrainingCalendar.mondayOf(date, calendar: calendar) }
        for pick in gone {
            weekCounts[weekStart(pick.fireAt), default: 0] += 1
        }
        for day in byDay.keys.sorted() {
            guard !goneDays.contains(day), let options = byDay[day] else { continue }
            let best = options.min { a, b in
                a.kind.priority != b.kind.priority ? a.kind.priority < b.kind.priority : a.fireAt < b.fireAt
            }
            guard let best else { continue }
            if let cap = budget.perWeek {
                let week = weekStart(best.fireAt)
                guard weekCounts[week, default: 0] < cap else { continue }
                weekCounts[week, default: 0] += 1
            }
            picked.append(best)
        }
        return picked.sorted { $0.fireAt < $1.fireAt }
    }

    /// The requests for the picks: `reminder-<day>` for the day's in-budget one, `elan-weigh-<day>` for the
    /// weigh-in, the kind's category, the program id in the user info for the actions.
    static func reminderRequests(_ picks: [ReminderCandidate], calendar: Calendar) -> [UNNotificationRequest] {
        picks.map { pick in
            let content = UNMutableNotificationContent()
            content.title = pick.title
            content.body = pick.body
            content.sound = .default
            content.categoryIdentifier = pick.kind.categoryId
            var info: [String: Any] = ["kind": pick.kind.rawValue]
            if let programId = pick.programId { info["programId"] = programId }
            content.userInfo = info
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: pick.fireAt)
            let day = TrainingCalendar.trainingDayKey(pick.fireAt, calendar: calendar)
            let id = (pick.kind.countsInBudget ? requestPrefix : weighRequestPrefix) + day
            return UNNotificationRequest(identifier: id, content: content,
                                         trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
        }
    }

    /// The picks to remember after scheduling: the ones already gone (kept `pickMemoryDays` days) and the
    /// new in-budget ones, one per day, the new ones replacing a pending one of the same day.
    static func mergedPicks(previous: [ReminderPick], scheduled: [ReminderCandidate], now: Date,
                            calendar: Calendar) -> [ReminderPick] {
        let floor = calendar.date(byAdding: .day, value: -pickMemoryDays, to: now) ?? now
        var kept = previous.filter { $0.fireAt <= now && $0.fireAt >= floor && $0.kind.countsInBudget }
        for pick in scheduled where pick.kind.countsInBudget {
            let day = TrainingCalendar.trainingDayKey(pick.fireAt, calendar: calendar)
            kept.removeAll { $0.day == day && $0.fireAt > now }
            kept.append(ReminderPick(day: day, kind: pick.kind, fireAt: pick.fireAt))
        }
        return kept.sorted { $0.fireAt < $1.fireAt }
    }

    // MARK: Settings

    static let budgetKey = "reminders.budget"
    static let quietStartKey = "reminders.quietStart"
    static let quietEndKey = "reminders.quietEnd"

    static func budget(_ d: UserDefaults = .standard) -> ReminderBudget {
        ReminderBudget(rawValue: d.string(forKey: budgetKey) ?? "") ?? .daily
    }

    static func quietHours(_ d: UserDefaults = .standard) -> ReminderQuietHours {
        let start = d.object(forKey: quietStartKey) as? Int ?? ReminderQuietHours.standard.startMinutes
        let end = d.object(forKey: quietEndKey) as? Int ?? ReminderQuietHours.standard.endMinutes
        return ReminderQuietHours(startMinutes: min(max(start, 0), 24 * 60 - 1), endMinutes: min(max(end, 0), 24 * 60 - 1))
    }

    static func storedPicks(_ d: UserDefaults = .standard) -> [ReminderPick] {
        guard let data = d.data(forKey: picksKey) else { return [] }
        return (try? JSONDecoder().decode([ReminderPick].self, from: data)) ?? []
    }

    static func storePicks(_ picks: [ReminderPick], _ d: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(picks) { d.set(data, forKey: picksKey) }
    }

    // MARK: Scheduling

    /// Re-plan every reminder from today as the screens read it: the meal reminders and Élan's, through the
    /// one budget. Without notification permission nothing is scheduled and nothing is asked: the Rappels
    /// screen asks, with its words around the request.
    @MainActor
    static func refreshAllReminders(repo: Repository, profile: ProfileStore, now: Date = Date(),
                                    defaults: UserDefaults = .standard) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter {
            $0.hasPrefix(requestPrefix) || $0.hasPrefix(weighRequestPrefix) || $0.hasPrefix(legacyMealPrefix)
        }
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else {
            center.removePendingNotificationRequests(withIdentifiers: pending)
            return
        }
        let calendar = Calendar.current
        var candidates = await MealReminder.mealReminderCandidates(repo: repo, now: now, defaults: defaults)
        candidates += await ElanReminder.elanReminderCandidates(repo: repo, profile: profile, now: now, defaults: defaults)
        let previous = storedPicks(defaults)
        let picks = pickReminders(candidates: candidates, now: now, calendar: calendar, budget: budget(defaults),
                                  quiet: quietHours(defaults), pastPicks: previous)
        center.removePendingNotificationRequests(withIdentifiers: pending)
        for request in reminderRequests(picks, calendar: calendar) {
            try? await center.add(request)
        }
        storePicks(mergedPicks(previous: previous, scheduled: picks, now: now, calendar: calendar), defaults)
    }
}
