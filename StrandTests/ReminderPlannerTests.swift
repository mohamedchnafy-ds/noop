import XCTest
@testable import Strand

/// Personal fork, chantier 10 (Élan), PR C: the one budget the meal reminders and Élan's share
/// (`ReminderPlanner.pickReminders`): one a day or a week's cap, the same-day priority, the quiet hours, the
/// weigh-in apart, a day whose reminder already went off, and the requests and the memory of the picks.
final class ReminderPlannerTests: XCTestCase {

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// 2026-11-dd at hh:mm UTC. The 2nd is a Monday.
    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func candidate(_ kind: ReminderKind, _ fireAt: Date) -> ReminderCandidate {
        ReminderCandidate(kind: kind, fireAt: fireAt, title: kind.rawValue, body: "")
    }

    private func pick(_ candidates: [ReminderCandidate], now: Date, budget: ReminderBudget = .daily,
                      quiet: ReminderQuietHours = .standard, past: [ReminderPick] = []) -> [ReminderKind] {
        ReminderPlanner.pickReminders(candidates: candidates, now: now, calendar: calendar, budget: budget,
                                      quiet: quiet, pastPicks: past).map(\.kind)
    }

    func testOneADayTheMostUsefulAndThePastDropped() {
        let picks = pick([candidate(.mealTrainingDay, at(3, 12, 30)), candidate(.elanMissed, at(3, 18)),
                          candidate(.elanThreeDays, at(3, 18)), candidate(.mealTrainingDay, at(5, 12, 30)),
                          candidate(.elanPlanned, at(5, 17, 30)), candidate(.elanWeekly, at(1, 19))],
                         now: at(3, 9))
        XCTAssertEqual(picks, [.elanMissed, .elanPlanned], "missed over a meal on the 3rd; planned over a meal on the 5th; the 1st is past")
    }

    func testEqualPriorityTheEarlierGoes() {
        XCTAssertEqual(pick([candidate(.mealEvening, at(3, 21)), candidate(.mealAfterSession, at(3, 15))], now: at(3, 9)),
                       [.mealAfterSession])
    }

    func testTheQuietHoursWaitInTheMorningAndDropInTheEvening() {
        let picked = ReminderPlanner.pickReminders(
            candidates: [candidate(.elanWeighIn, at(3, 6, 30)), candidate(.mealEvening, at(3, 22)), candidate(.elanPlanned, at(3, 17, 30))],
            now: at(3, 5), calendar: calendar, budget: .daily, quiet: .standard, pastPicks: [])
        XCTAssertEqual(picked.map(\.kind), [.elanWeighIn, .elanPlanned])
        XCTAssertEqual(picked[0].fireAt, at(3, 7), "06:30 waits for the quiet hours to end")
        // Quiet hours inside one day (a siesta): dropped inside, kept outside.
        let siesta = ReminderQuietHours(startMinutes: 13 * 60, endMinutes: 15 * 60)
        XCTAssertEqual(pick([candidate(.mealAfterSession, at(3, 14)), candidate(.elanThreeDays, at(3, 18))], now: at(3, 9), quiet: siesta),
                       [.elanThreeDays])
        XCTAssertFalse(ReminderQuietHours(startMinutes: 7 * 60, endMinutes: 7 * 60).contains(7 * 60), "an empty span is no quiet")
    }

    func testTheWeighInIsApartOnePerDay() {
        let picks = pick([candidate(.elanWeighIn, at(3, 7, 30)), candidate(.elanWeighIn, at(3, 9, 30)),
                          candidate(.elanMissed, at(3, 18)), candidate(.elanWeighIn, at(4, 7, 30))], now: at(3, 6))
        XCTAssertEqual(picks, [.elanWeighIn, .elanMissed, .elanWeighIn])
    }

    func testADayWhoseReminderWentOffTakesNoOther() {
        let went = ReminderPick(day: "2026-11-03", kind: .mealTrainingDay, fireAt: at(3, 12, 30))
        XCTAssertEqual(pick([candidate(.elanMissed, at(3, 18)), candidate(.elanWeighIn, at(3, 19))], now: at(3, 14), past: [went]),
                       [.elanWeighIn], "the meal reminder went at 12:30: nothing more in the budget today, the weigh-in apart")
        // A pick still to come does not close the day: a better one replaces it.
        let pending = ReminderPick(day: "2026-11-03", kind: .mealTrainingDay, fireAt: at(3, 12, 30))
        XCTAssertEqual(pick([candidate(.elanMissed, at(3, 18)), candidate(.mealTrainingDay, at(3, 12, 30))], now: at(3, 9), past: [pending]),
                       [.elanMissed])
        // Yesterday's does not close today.
        let yesterday = ReminderPick(day: "2026-11-02", kind: .elanPlanned, fireAt: at(2, 17, 30))
        XCTAssertEqual(pick([candidate(.elanMissed, at(3, 18))], now: at(3, 9), past: [yesterday]), [.elanMissed])
    }

    func testAWeeklyBudgetCountsWhatWentAndStopsAtItsCap() {
        // Four days proposed this week (Mon 2 … Sun 8), two a week: the first two days chosen, in order.
        let candidates = [candidate(.mealTrainingDay, at(3, 12, 30)), candidate(.elanPlanned, at(4, 17, 30)),
                          candidate(.mealTrainingDay, at(6, 12, 30)), candidate(.elanWeekly, at(8, 19)),
                          candidate(.elanPlanned, at(9, 17, 30))]
        XCTAssertEqual(pick(candidates, now: at(3, 9), budget: .twoPerWeek), [.mealTrainingDay, .elanPlanned, .elanPlanned],
                       "two this week, then next week's starts a new count")
        // One already went this week: one left.
        let went = ReminderPick(day: "2026-11-02", kind: .elanMissed, fireAt: at(2, 18))
        XCTAssertEqual(pick(candidates, now: at(3, 9), budget: .twoPerWeek, past: [went]), [.mealTrainingDay, .elanPlanned])
        XCTAssertEqual(pick(candidates, now: at(3, 9), budget: .fourPerWeek), [.mealTrainingDay, .elanPlanned, .mealTrainingDay, .elanWeekly, .elanPlanned])
        // Still one a day under a weekly budget.
        XCTAssertEqual(pick([candidate(.mealTrainingDay, at(3, 12, 30)), candidate(.elanMissed, at(3, 18))], now: at(3, 9), budget: .fourPerWeek),
                       [.elanMissed])
    }

    func testRequestsCarryTheDayTheCategoryAndTheProgram() {
        var missed = candidate(.elanMissed, at(3, 18))
        missed.programId = "p1"
        let requests = ReminderPlanner.reminderRequests([missed, candidate(.elanWeighIn, at(4, 7, 30))], calendar: calendar)
        XCTAssertEqual(requests.map(\.identifier), ["reminder-2026-11-03", "elan-weigh-2026-11-04"])
        XCTAssertEqual(requests[0].content.categoryIdentifier, ElanReminder.missedCategoryId)
        XCTAssertEqual(requests[0].content.userInfo["programId"] as? String, "p1")
        XCTAssertEqual(requests[1].content.categoryIdentifier, ElanReminder.weighCategoryId)
        XCTAssertEqual(ReminderKind.mealEvening.categoryId, ElanReminder.mealCategoryId)
        XCTAssertEqual(ReminderKind.elanWeekly.categoryId, ElanReminder.plainCategoryId)
    }

    func testThePicksRememberedAreTheGoneOnesAndTheNewOnes() {
        let previous = [ReminderPick(day: "2026-10-01", kind: .elanMissed, fireAt: at(1, 18).addingTimeInterval(-33 * 86_400)),
                        ReminderPick(day: "2026-11-02", kind: .elanPlanned, fireAt: at(2, 17, 30)),
                        ReminderPick(day: "2026-11-03", kind: .mealTrainingDay, fireAt: at(3, 12, 30))]
        let merged = ReminderPlanner.mergedPicks(previous: previous,
                                                 scheduled: [candidate(.elanMissed, at(3, 18)), candidate(.elanWeighIn, at(3, 19))],
                                                 now: at(3, 9), calendar: calendar)
        XCTAssertEqual(merged, [ReminderPick(day: "2026-11-02", kind: .elanPlanned, fireAt: at(2, 17, 30)),
                                ReminderPick(day: "2026-11-03", kind: .elanMissed, fireAt: at(3, 18))],
                       "the old one is forgotten, today's pending one is replaced, the weigh-in is not remembered")
    }

    func testTheActionsOfANotificationAreRead() {
        XCTAssertEqual(ElanReminder.elanAction(category: ElanReminder.missedCategoryId, actionIdentifier: ElanReminder.notTodayActionId), .notToday)
        XCTAssertEqual(ElanReminder.elanAction(category: ElanReminder.missedCategoryId, actionIdentifier: ElanReminder.shortSessionActionId), .openShortSession)
        XCTAssertEqual(ElanReminder.elanAction(category: ElanReminder.missedCategoryId, actionIdentifier: "com.apple.UNNotificationDefaultActionIdentifier"), .openShortSession)
        XCTAssertEqual(ElanReminder.elanAction(category: ElanReminder.weighCategoryId, actionIdentifier: ElanReminder.laterActionId), .weighLater)
        XCTAssertEqual(ElanReminder.elanAction(category: ElanReminder.weighCategoryId, actionIdentifier: ElanReminder.logWeighActionId), .openWeighIn)
        XCTAssertEqual(ElanReminder.elanAction(category: ElanReminder.plainCategoryId, actionIdentifier: "x"), .openElan)
        XCTAssertEqual(ElanReminder.elanAction(category: ElanReminder.mealCategoryId, actionIdentifier: "x"), .openNutrition)
        XCTAssertNil(ElanReminder.elanAction(category: "fasting", actionIdentifier: "x"))
    }
}
