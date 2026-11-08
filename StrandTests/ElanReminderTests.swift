import XCTest
@testable import Strand

/// Personal fork, chantier 10 (Élan), PR C: what Élan proposes to the shared planner (`ElanReminder.planElanReminders`):
/// the day after a miss, before a planned session, the third day without one, Sunday's recap, the weigh-in.
final class ElanReminderTests: XCTestCase {

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// 2026-11-dd at hh:mm UTC. The 2nd is a Monday, the 8th a Sunday.
    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private let missed = ElanMissedSession(programId: "B", name: "Full body B", day: "2026-11-04")

    private func plan(_ input: ElanReminder.Input, settings: ElanReminder.Settings = .init(), now: Date) -> [ReminderCandidate] {
        ElanReminder.planElanReminders(input, settings: settings, now: now, calendar: calendar)
    }

    private func kinds(_ input: ElanReminder.Input, settings: ElanReminder.Settings = .init(), now: Date) -> [ReminderKind] {
        plan(input, settings: settings, now: now).map(\.kind)
    }

    func testTheDayAfterAMissProposesTheShortSessionAtSixWhileNothingIsDecided() {
        var input = ElanReminder.Input(missed: missed, shortTarget: ElanShortTarget(programId: "B", name: "Full body B"),
                                       shortMinutes: 20)
        var settings = ElanReminder.Settings()
        settings.weighOn = false
        let proposed = plan(input, settings: settings, now: at(5, 9))
        XCTAssertEqual(proposed.map(\.kind), [.elanMissed])
        XCTAssertEqual(proposed[0].fireAt, at(5, 18))
        XCTAssertEqual(proposed[0].programId, "B")
        XCTAssertEqual(proposed[0].title, "Full body B was yesterday")
        XCTAssertTrue(proposed[0].body.hasPrefix("20 minutes"))
        // Decided (« Pas aujourd'hui » or accepted), done, or past 18:00: nothing.
        input.shortDecided = true
        XCTAssertTrue(kinds(input, settings: settings, now: at(5, 9)).isEmpty)
        input.shortDecided = false
        input.sessionDoneToday = true
        XCTAssertTrue(kinds(input, settings: settings, now: at(5, 9)).isEmpty)
        input.sessionDoneToday = false
        XCTAssertTrue(kinds(input, settings: settings, now: at(5, 18, 30)).isEmpty)
        settings.missedOn = false
        XCTAssertTrue(kinds(input, settings: settings, now: at(5, 9)).isEmpty)
        // Without a built short session, the generic line.
        input.shortMinutes = nil
        XCTAssertEqual(ElanReminder.missedText(missed: missed, shortMinutes: nil).body,
                       String(localized: "Twenty minutes tonight are enough to keep the rhythm."))
    }

    func testAnHourBeforeEachPlannedSessionTodayWhileNoneIsDone() {
        var input = ElanReminder.Input(plannedByDay: ["2026-11-05": "Full body A", "2026-11-07": "Running · 30 min"],
                                       sessionMinutes: 18 * 60 + 30)
        var settings = ElanReminder.Settings()
        settings.weighOn = false
        let proposed = plan(input, settings: settings, now: at(5, 9))
        XCTAssertEqual(proposed.map(\.kind), [.elanPlanned, .elanPlanned])
        XCTAssertEqual(proposed.map(\.fireAt), [at(5, 17, 30), at(7, 17, 30)])
        XCTAssertTrue(proposed[0].title.hasPrefix("Full body A"))
        // Today's session done: today's reminder goes, the 7th stays.
        input.sessionDoneToday = true
        XCTAssertEqual(plan(input, settings: settings, now: at(5, 9)).map(\.fireAt), [at(7, 17, 30)])
        // Past the hour: only the later day.
        input.sessionDoneToday = false
        XCTAssertEqual(plan(input, settings: settings, now: at(5, 18)).map(\.fireAt), [at(7, 17, 30)])
        settings.plannedOn = false
        XCTAssertTrue(kinds(input, settings: settings, now: at(5, 9)).isEmpty)
    }

    func testTheThirdDayWithoutASessionTodayOrTheDayItWillBe() {
        var settings = ElanReminder.Settings()
        settings.weighOn = false
        // Two days since: the third is tomorrow.
        var input = ElanReminder.Input(daysSinceLastSession: 2, whyText: "Pour tenir la distance.")
        var proposed = plan(input, settings: settings, now: at(5, 9))
        XCTAssertEqual(proposed.map(\.kind), [.elanThreeDays])
        XCTAssertEqual(proposed[0].fireAt, at(6, 18))
        XCTAssertEqual(proposed[0].body, "Pour tenir la distance.", "the wearer's why is the body")
        // Three days since: today at 18:00.
        input.daysSinceLastSession = 3
        proposed = plan(input, settings: settings, now: at(5, 9))
        XCTAssertEqual(proposed.map(\.fireAt), [at(5, 18)])
        // Four days, or none known: nothing more (the third day went).
        input.daysSinceLastSession = 4
        XCTAssertTrue(kinds(input, settings: settings, now: at(5, 9)).isEmpty)
        input.daysSinceLastSession = nil
        XCTAssertTrue(kinds(input, settings: settings, now: at(5, 9)).isEmpty)
        // No why: the generic line.
        XCTAssertEqual(ElanReminder.threeDaysText(why: "  ").body,
                       String(localized: "A short one is enough to start again. Your before / now is in Élan."))
    }

    func testSundaysRecapOnSundayOnly() {
        var settings = ElanReminder.Settings()
        settings.weighOn = false
        let input = ElanReminder.Input(weekDone: 3, weekPlanned: 3, nutritionHeld: 5, nutritionLogged: 7)
        let sunday = plan(input, settings: settings, now: at(8, 9))
        XCTAssertEqual(sunday.map(\.kind), [.elanWeekly])
        XCTAssertEqual(sunday[0].fireAt, at(8, 19))
        XCTAssertEqual(sunday[0].title, "Your week: 3 / 3 sessions")
        XCTAssertEqual(sunday[0].body, "Nutrition held 5 days out of 7.")
        XCTAssertTrue(kinds(input, settings: settings, now: at(7, 9)).isEmpty, "Saturday: the figures are not the week's yet")
        XCTAssertTrue(kinds(input, settings: settings, now: at(8, 19, 30)).isEmpty)
        XCTAssertEqual(ElanReminder.weeklyText(done: 2, planned: 0, held: 0, logged: 0).title, "Your week: 2 sessions")
        XCTAssertEqual(ElanReminder.weeklyText(done: 2, planned: 0, held: 0, logged: 0).body, String(localized: "The recap is in Élan."))
    }

    func testTheWeighInEveryMorningTodayWhileNoneIsLogged() {
        var input = ElanReminder.Input()
        let proposed = plan(input, now: at(5, 6))
        XCTAssertEqual(proposed.count, ElanReminder.daysAhead)
        XCTAssertTrue(proposed.allSatisfy { $0.kind == .elanWeighIn })
        XCTAssertEqual(proposed.first?.fireAt, at(5, 7, 30))
        XCTAssertEqual(proposed.last?.fireAt, at(11, 7, 30))
        XCTAssertFalse(proposed[0].body.contains("kg"), "never a figure of weight")
        input.weighedToday = true
        XCTAssertEqual(plan(input, now: at(5, 6)).first?.fireAt, at(6, 7, 30), "logged: tomorrow's is the first")
        var settings = ElanReminder.Settings()
        settings.weighMinutes = 8 * 60
        XCTAssertEqual(plan(ElanReminder.Input(), settings: settings, now: at(5, 6)).first?.fireAt, at(5, 8))
        settings.weighOn = false
        XCTAssertTrue(plan(ElanReminder.Input(), settings: settings, now: at(5, 6)).isEmpty)
    }

    func testTheSettingsReadTheirDefaultsAndTheirKeys() {
        let name = "ElanReminderTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        XCTAssertEqual(ElanReminder.settings(d), ElanReminder.Settings())
        d.set(false, forKey: ElanReminder.plannedKey)
        d.set(6 * 60 + 45, forKey: ElanReminder.weighMinutesKey)
        let read = ElanReminder.settings(d)
        XCTAssertFalse(read.plannedOn)
        XCTAssertTrue(read.missedOn)
        XCTAssertEqual(read.weighMinutes, 6 * 60 + 45)
        XCTAssertEqual(ReminderPlanner.budget(d), .daily)
        XCTAssertEqual(ReminderPlanner.quietHours(d), .standard)
        d.set(ReminderBudget.twoPerWeek.rawValue, forKey: ReminderPlanner.budgetKey)
        d.set(22 * 60, forKey: ReminderPlanner.quietStartKey)
        XCTAssertEqual(ReminderPlanner.budget(d), .twoPerWeek)
        XCTAssertEqual(ReminderPlanner.quietHours(d).startMinutes, 22 * 60)
        d.removePersistentDomain(forName: name)
    }
}
