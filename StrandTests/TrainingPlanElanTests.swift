import XCTest
@testable import Strand

/// Personal fork, chantier 10 (Élan), PR C: Élan's short session accepted for one day, inside the week plan
/// (`TrainingWeekPlan.extraByDay`): what `planDecision` says, what the calendar marks, what the tally counts,
/// and that nothing of it is stored with the plan.
final class TrainingPlanElanTests: XCTestCase {

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// 2026-11-dd at 09:00 UTC. The 2nd is a Monday.
    private func date(_ day: Int, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }

    private func defaults() -> UserDefaults {
        let name = "TrainingPlanElanTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    func testAnExtraMakesAPlannedDayOfARestDayAndFollowsTheWeekdaysItems() {
        let plan = TrainingWeekPlan(days: ["1": [.program("A")], "3": [.program("B")]], since: "2026-11-02")
        // Tuesday the 3rd is rest: with the extra it is planned, the extra alone.
        let tuesday = plan.adding(.program("B"), toDay: "2026-11-03")
        XCTAssertEqual(tuesday.planDecision(for: date(3), calendar: calendar), .planned([.program("B")]))
        XCTAssertEqual(tuesday.planDecision(for: date(10), calendar: calendar), .rest, "the extra is for its day only")
        // Monday plans A: the extra B follows it; an extra the weekday already plans is not added twice.
        let monday = plan.adding(.program("B"), toDay: "2026-11-02").adding(.program("A"), toDay: "2026-11-02")
        XCTAssertEqual(monday.planDecision(for: date(2), calendar: calendar), .planned([.program("A"), .program("B")]))
        // Without any plan, the extra alone decides its day; other days stay undecided.
        let bare = TrainingWeekPlan().adding(.program("B"), toDay: "2026-11-03")
        XCTAssertEqual(bare.planDecision(for: date(3), calendar: calendar), .planned([.program("B")]))
        XCTAssertNil(bare.planDecision(for: date(4), calendar: calendar))
        // Before the plan applies, the extra still decides its day; the day beside it stays undecided.
        let october27 = calendar.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 9))!
        let early = plan.adding(.program("B"), toDay: "2026-10-27")
        XCTAssertEqual(early.planDecision(for: october27, calendar: calendar), .planned([.program("B")]))
        XCTAssertNil(early.planDecision(for: october27.addingTimeInterval(86_400), calendar: calendar))
    }

    func testTheExtraIsNeverStoredAndSurvivesKeepingPrograms() {
        let plan = TrainingWeekPlan(days: ["1": [.program("A")]], since: "2026-11-02", sessionMinutes: 18 * 60 + 30)
            .adding(.program("B"), toDay: "2026-11-03")
        let decoded = TrainingWeekPlan.decodeWeekPlan(plan.encodedWeekPlan())
        XCTAssertTrue(decoded.extraByDay.isEmpty, "the extra is today's choice, not the plan")
        XCTAssertEqual(decoded.sessionMinutes, 18 * 60 + 30, "the usual hour is part of the plan")
        XCTAssertEqual(decoded.days, plan.days)
        XCTAssertEqual(plan.keepingPrograms(["A", "B"]).extraByDay, ["2026-11-03": [.program("B")]])
        XCTAssertTrue(plan.keepingPrograms(["A"]).extraByDay.isEmpty, "a deleted program leaves the extra too")
        XCTAssertEqual(plan.keepingPrograms(["A"]).sessionMinutes, 18 * 60 + 30)
    }

    func testTheStoredPlanTakesTodaysAcceptedShortSession() {
        let d = defaults()
        TrainingWeekPlan(days: ["1": [.program("A")]], since: "2026-11-02").storeWeekPlan(d)
        let today = date(3)
        XCTAssertTrue(TrainingWeekPlan.loadWeekPlan(d, now: today, calendar: calendar).extraByDay.isEmpty)
        ElanShortSessionChoice.accept(day: "2026-11-03", programId: "B", d)
        let loaded = TrainingWeekPlan.loadWeekPlan(d, now: today, calendar: calendar)
        XCTAssertEqual(loaded.extraByDay, ["2026-11-03": [.program("B")]])
        XCTAssertEqual(loaded.planDecision(for: today, calendar: calendar), .planned([.program("B")]))
        // Another day: the acceptance is today's only.
        XCTAssertTrue(TrainingWeekPlan.loadWeekPlan(d, now: date(4), calendar: calendar).extraByDay.isEmpty)
        // Withdrawn: gone, and the day remembers the refusal.
        ElanShortSessionChoice.withdraw(day: "2026-11-03", d)
        XCTAssertTrue(TrainingWeekPlan.loadWeekPlan(d, now: today, calendar: calendar).extraByDay.isEmpty)
        XCTAssertTrue(ElanShortSessionChoice.isDismissed(day: "2026-11-03", d))
        XCTAssertEqual(d.integer(forKey: ElanShortSessionChoice.revisionKey), 2, "each choice bumps the revision")
    }

    func testTheCalendarMarksTheExtraAndTheTallyLeavesItOutOfPlanned() {
        let plan = TrainingWeekPlan(days: ["1": [.program("A")], "3": [.program("B")], "5": [.program("A")]],
                                    since: "2026-11-02")
            .adding(.program("B"), toDay: "2026-11-05")   // Thursday, after Wednesday's miss
        let now = date(5, hour: 12)
        let week = TrainingDays.buildTrainingDays(TrainingCalendar.weekDates(from: date(2), calendar: calendar),
                                                  plan: plan, lifts: [], activities: [], now: now, calendar: calendar)
        let thursday = week[3]
        XCTAssertEqual(thursday.planned.count, 1)
        XCTAssertTrue(thursday.planned[0].isExtra)
        XCTAssertEqual(thursday.openProgramIds, ["B"], "to do, like a planned item")
        XCTAssertTrue(thursday.isPlannedOpen)
        XCTAssertFalse(week[0].planned[0].isExtra, "the weekday's own item is not an extra")
        var tally = TrainingDays.sessionTally(week)
        XCTAssertEqual(tally.planned, 3, "the week plans three; Élan's addition does not make it four")
        XCTAssertEqual(tally.done, 0)
        // The short session done Thursday evening: matched to the extra, counted as done, still 3 planned.
        let start = Int(date(5, hour: 19).timeIntervalSince1970)
        let done = TrainingLiftDone(sessionId: "s", programId: "B", name: "Full body B · short", startTs: start,
                                    endTs: start + 1200, workingSets: 12, effort: nil)
        let after = TrainingDays.buildTrainingDays(TrainingCalendar.weekDates(from: date(2), calendar: calendar),
                                                   plan: plan, lifts: [done], activities: [], now: now, calendar: calendar)
        XCTAssertTrue(after[3].planned[0].isDone)
        XCTAssertTrue(after[3].planned[0].isExtra)
        tally = TrainingDays.sessionTally(after)
        XCTAssertEqual(tally.done, 1)
        XCTAssertEqual(tally.planned, 3)
    }

    func testTheShortTargetIsTodaysPlannedProgramElseTheMissedOne() {
        let missed = ElanMissedSession(programId: "B", name: "Full body B", day: "2026-11-04")
        let names = ["A": "Full body A", "B": "Full body B"]
        func day(_ planned: [TrainingPlannedItem]) -> TrainingDay {
            TrainingDay(date: date(5), key: "2026-11-05", isToday: true, isPast: false, planned: planned, lifts: [], activities: [])
        }
        // A rest day: the missed program.
        XCTAssertEqual(ElanResolver.elanShortTarget(missed: missed, today: day([]), programNames: names),
                       ElanShortTarget(programId: "B", name: "Full body B"))
        // A planned day: today's session, short.
        XCTAssertEqual(ElanResolver.elanShortTarget(missed: missed, today: day([TrainingPlannedItem(item: .program("A"), isDone: false)]),
                                                    programNames: names),
                       ElanShortTarget(programId: "A", name: "Full body A"))
        // Today's planned program already done, or Élan's own extra: not a target.
        XCTAssertEqual(ElanResolver.elanShortTarget(missed: missed, today: day([TrainingPlannedItem(item: .program("A"), isDone: true),
                                                                                 TrainingPlannedItem(item: .program("B"), isDone: false, isExtra: true)]),
                                                    programNames: names)?.programId, "B")
        // Only cardio planned: the missed program.
        XCTAssertEqual(ElanResolver.elanShortTarget(missed: missed, today: day([TrainingPlannedItem(item: .cardio(sport: "Running", minutes: 30), isDone: false)]),
                                                    programNames: names)?.programId, "B")
        XCTAssertNil(ElanResolver.elanShortTarget(missed: nil, today: day([]), programNames: names))
    }
}
