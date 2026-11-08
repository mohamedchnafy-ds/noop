import XCTest
@testable import Strand

/// The meal reminders (personal fork, chantier 8; unified with Élan's in chantier 10 PR C): which ones are
/// proposed and when. Pure: no notification center. The budget (never two the same day) is the shared
/// planner's, tested in `ReminderPlannerTests`.
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
                      kinds: Set<MealReminder.Kind> = [.trainingDay, .afterSession]) -> [MealReminder.Reminder] {
        MealReminder.planMealReminders(
            now: now, calendar: calendar, minutes: MealReminder.defaultMinutes, kinds: kinds,
            isTrainingDay: { training.contains(self.calendar.component(.day, from: $0)) },
            mealTimesToday: meals, sessionEndsToday: ends)
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

    func testAfterASessionAnHourLaterIsProposedBesideTheFixedTime() {
        let reminders = plan(now: at(10, 15), ends: [at(10)])
        XCTAssertEqual(reminders, [MealReminder.Reminder(kind: .afterSession, fireAt: at(11)),
                                   MealReminder.Reminder(kind: .trainingDay, fireAt: at(12, 30))],
                       "both proposed; the planner keeps the earlier")
        // A meal since the end cancels it; a meal before does not.
        XCTAssertTrue(plan(now: at(10, 15), meals: [at(10, 5)], ends: [at(10)]).isEmpty)
        XCTAssertEqual(plan(now: at(18), meals: [at(8)], ends: [at(17, 30)]),
                       [MealReminder.Reminder(kind: .afterSession, fireAt: at(18, 30))])
        // An end past the hour already: nothing.
        XCTAssertTrue(plan(now: at(18), training: [], ends: [at(16)]).isEmpty)
    }

    func testTheNextPlannedDaysAreScheduledAtTheFixedTime() {
        let reminders = plan(now: at(20), training: [3, 5, 9, 10])
        XCTAssertEqual(reminders.map(\.fireAt), [at(12, 30, day: 5), at(12, 30, day: 9)])
        XCTAssertTrue(reminders.allSatisfy { $0.kind == .trainingDay })
    }

    func testTheEveningReminderEveryDayWhileNothingIsLogged() {
        let reminders = plan(now: at(9), training: [], kinds: [.evening])
        XCTAssertEqual(reminders.count, MealReminder.daysAhead)
        XCTAssertEqual(reminders.first?.fireAt, at(21))
        XCTAssertTrue(reminders.allSatisfy { $0.kind == .evening })
        // Something logged today: tomorrow's is the first.
        XCTAssertEqual(plan(now: at(9), training: [], meals: [at(8)], kinds: [.evening]).first?.fireAt, at(21, 0, day: 4))
        // Every kind off: nothing.
        XCTAssertTrue(plan(now: at(9), kinds: []).isEmpty)
    }

    func testTheKindsAreWordedAndCarriedToThePlanner() {
        let candidate = MealReminder.mealCandidate(MealReminder.Reminder(kind: .afterSession, fireAt: at(11)))
        XCTAssertEqual(candidate.kind, .mealAfterSession)
        XCTAssertEqual(candidate.title, MealReminder.mealReminderText(.afterSession).title)
        XCTAssertFalse(MealReminder.mealReminderText(.evening).body.isEmpty)
        XCTAssertEqual(MealReminder.Kind.trainingDay.reminderKind, .mealTrainingDay)
        XCTAssertEqual(MealReminder.Kind.evening.reminderKind, .mealEvening)
    }

    func testTheLegacySwitchIsCarriedOverOnce() {
        let name = "MealReminderTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        // Never set: the new defaults (training day and after session on, evening off).
        XCTAssertEqual(MealReminder.enabledKinds(d), [.trainingDay, .afterSession])
        // The chantier 8 switch left OFF on another install: its two kinds stay off.
        let off = UserDefaults(suiteName: name + "-off")!
        off.removePersistentDomain(forName: name + "-off")
        off.set(false, forKey: MealReminder.legacyEnabledKey)
        XCTAssertEqual(MealReminder.enabledKinds(off), [])
        // Carried once: turning a kind on afterwards sticks.
        off.set(true, forKey: MealReminder.trainingDayKey)
        XCTAssertEqual(MealReminder.enabledKinds(off), [.trainingDay])
        XCTAssertEqual(MealReminder.reminderMinutes(d), MealReminder.defaultMinutes)
        XCTAssertEqual(MealReminder.eveningMinutes(d), MealReminder.defaultEveningMinutes)
        d.removePersistentDomain(forName: name)
        off.removePersistentDomain(forName: name + "-off")
    }
}
