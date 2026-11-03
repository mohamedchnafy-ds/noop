import XCTest
@testable import Strand

/// The meal reminders (personal fork, chantier 8): which one, when, and never two the same day. Pure: no
/// notification center.
final class MealReminderTests: XCTestCase {

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// 2026-11-03 at hh:mm UTC (a Tuesday).
    private func at(_ hour: Int, _ minute: Int = 0, day: Int = 3) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func plan(now: Date, training: Set<Int> = [3], meals: [Date] = [], ends: [Date] = [],
                      fired: Date? = nil) -> [MealReminder.Reminder] {
        MealReminder.planMealReminders(
            now: now, calendar: calendar, minutes: MealReminder.defaultMinutes,
            isTrainingDay: { training.contains(self.calendar.component(.day, from: $0)) },
            mealTimesToday: meals, sessionEndsToday: ends, firedToday: fired)
    }

    func testATrainingDayWithoutAMealGetsTheFixedTime() {
        let reminders = plan(now: at(9))
        XCTAssertEqual(reminders, [MealReminder.Reminder(kind: .trainingDay, fireAt: at(12, 30))])
    }

    func testAMealLoggedOrTheTimePassedCancelsIt() {
        XCTAssertTrue(plan(now: at(9), meals: [at(8)]).isEmpty)
        XCTAssertTrue(plan(now: at(13)).isEmpty)
        // A rest day has none.
        XCTAssertTrue(plan(now: at(9), training: []).isEmpty)
    }

    func testAfterASessionAnHourLaterGoesFirstAndAloneThatDay() {
        let reminders = plan(now: at(10, 15), ends: [at(10)])
        XCTAssertEqual(reminders, [MealReminder.Reminder(kind: .afterSession, fireAt: at(11))])
        // A meal since the end cancels it; a meal before does not.
        XCTAssertTrue(plan(now: at(10, 15), meals: [at(10, 5)], ends: [at(10)]).isEmpty)
        XCTAssertEqual(plan(now: at(18), meals: [at(8)], ends: [at(17, 30)]),
                       [MealReminder.Reminder(kind: .afterSession, fireAt: at(18, 30))])
        // An end past the hour already: nothing.
        XCTAssertTrue(plan(now: at(18), training: [], ends: [at(16)]).isEmpty)
    }

    func testNeverTwoTheSameDay() {
        // The 12:30 one went off: no after-session one later that day.
        XCTAssertTrue(plan(now: at(17), ends: [at(16, 30)], fired: at(12, 30)).isEmpty)
        // A fire time still to come is not "already went".
        XCTAssertEqual(plan(now: at(9), fired: at(12, 30)).count, 1)
        // Yesterday's does not count.
        XCTAssertEqual(plan(now: at(9), fired: at(12, 30, day: 2)).count, 1)
    }

    func testTheNextPlannedDaysAreScheduledAtTheFixedTime() {
        let reminders = plan(now: at(20), training: [3, 5, 9, 10])
        XCTAssertEqual(reminders.map(\.fireAt), [at(12, 30, day: 5), at(12, 30, day: 9)])
        XCTAssertTrue(reminders.allSatisfy { $0.kind == .trainingDay })
    }

    func testOneRequestPerDayWithTheWording() {
        let requests = MealReminder.mealReminderRequests(
            [MealReminder.Reminder(kind: .afterSession, fireAt: at(11)),
             MealReminder.Reminder(kind: .trainingDay, fireAt: at(12, 30, day: 5))], calendar: calendar)
        XCTAssertEqual(requests.map(\.identifier), ["meal-reminder-2026-11-3", "meal-reminder-2026-11-5"])
        XCTAssertEqual(requests[0].content.title, MealReminder.mealReminderText(.afterSession).title)
        XCTAssertFalse(requests[1].content.body.isEmpty)
    }
}
