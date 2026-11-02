import XCTest
@testable import Strand
import WhoopStore

/// The Training screen's rules (personal fork): the stored week plan, Monday-first calendar arithmetic,
/// what a day shows (planned, done, missed, cardio), the week count, the split between Lift Log sessions
/// and other workouts, and a program's summary.
final class TrainingPlanTests: XCTestCase {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Paris")!
        cal.firstWeekday = 1  // Sunday first on purpose: the arithmetic must not depend on it
        return cal
    }

    private func date(_ day: Int, _ hour: Int = 0, month: Int = 11) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    private func ts(_ day: Int, _ hour: Int, month: Int = 11) -> Int {
        Int(date(day, hour, month: month).timeIntervalSince1970)
    }

    // MARK: - Plan

    func testPlanRoundTripsAndKeepsOnlyExistingPrograms() {
        var plan = TrainingWeekPlan()
        plan.assignProgram("A", weekday: 1)
        plan.assignProgram("B", weekday: 3)
        plan.assignProgram("C", weekday: 5)
        plan.assignProgram("A", weekday: 6)
        plan.assignProgram(nil, weekday: 6)
        plan.assignProgram("Z", weekday: 9)   // not a weekday: ignored
        plan.since = "2026-11-02"
        let stored = plan.encodedWeekPlan()
        XCTAssertEqual(TrainingWeekPlan.decodeWeekPlan(stored), plan)
        XCTAssertEqual(stored, TrainingWeekPlan.decodeWeekPlan(stored).encodedWeekPlan())
        XCTAssertEqual(plan.plannedWeekdays(of: "A"), [1])
        XCTAssertNil(plan.plannedProgramId(weekday: 2))
        XCTAssertEqual(plan.keepingPrograms(["A", "C"]).programs, ["1": "A", "5": "C"])
        XCTAssertEqual(TrainingWeekPlan.decodeWeekPlan("not json"), TrainingWeekPlan())
        XCTAssertEqual(TrainingWeekPlan.decodeWeekPlan(nil), TrainingWeekPlan())
    }

    func testPlanAppliesFromItsFirstDay() {
        var plan = TrainingWeekPlan(programs: ["1": "A"], since: "2026-11-02")
        XCTAssertFalse(plan.appliesToDay("2026-10-26"))
        XCTAssertTrue(plan.appliesToDay("2026-11-02"))
        XCTAssertTrue(plan.appliesToDay("2026-11-09"))
        plan.since = nil
        XCTAssertTrue(plan.appliesToDay("2020-01-01"))
    }

    func testPlanDecisionIsTheProgramRestOrNothingBeforeThePlan() {
        let plan = TrainingWeekPlan(programs: ["1": "A", "3": "B"], since: "2026-11-02")
        XCTAssertEqual(plan.planDecision(for: date(2, 9), calendar: calendar), .program("A"))
        XCTAssertEqual(plan.planDecision(for: date(3, 9), calendar: calendar), .rest)
        XCTAssertNil(plan.planDecision(for: date(28, 9, month: 10), calendar: calendar))  // before the plan
        XCTAssertNil(TrainingWeekPlan().planDecision(for: date(2, 9), calendar: calendar)) // no plan
    }

    // MARK: - Calendar

    func testIsoWeekdayAndMondayWhateverTheFirstWeekday() {
        XCTAssertEqual(TrainingCalendar.isoWeekday(date(2), calendar: calendar), 1)   // Monday 2 Nov 2026
        XCTAssertEqual(TrainingCalendar.isoWeekday(date(8), calendar: calendar), 7)   // Sunday 8 Nov
        XCTAssertEqual(TrainingCalendar.mondayOf(date(8, 21), calendar: calendar), date(2))
        XCTAssertEqual(TrainingCalendar.mondayOf(date(1), calendar: calendar), date(26, month: 10))
        let week = TrainingCalendar.weekDates(from: date(2), calendar: calendar)
        XCTAssertEqual(week.count, 7)
        XCTAssertEqual(week.last, date(8))
    }

    func testMonthCellsStartOnMonday() {
        // November 2026 starts on a Sunday: six blanks, then 30 days, padded to 42 cells.
        let cells = TrainingCalendar.monthCells(containing: date(17), calendar: calendar)
        XCTAssertEqual(cells.prefix(6).compactMap { $0 }.count, 0)
        XCTAssertEqual(cells[6], date(1))
        XCTAssertEqual(cells.compactMap { $0 }.count, 30)
        XCTAssertEqual(cells.count % 7, 0)
        XCTAssertEqual(TrainingCalendar.trainingDayKey(date(1), calendar: calendar), "2026-11-01")
    }

    // MARK: - Days

    private func lift(_ day: Int, _ hour: Int, program: String?, sets: Int = 18) -> TrainingLiftDone {
        TrainingLiftDone(sessionId: "s\(day)\(hour)", programId: program, name: program ?? "Session",
                         startTs: ts(day, hour), endTs: ts(day, hour) + 52 * 60, workingSets: sets, effort: nil)
    }

    private func activity(_ day: Int, _ hour: Int) -> TrainingActivityDone {
        TrainingActivityDone(sport: "Walk", source: "detected", startTs: ts(day, hour),
                             endTs: ts(day, hour) + 25 * 60, kcal: 140)
    }

    func testWeekDaysPlannedDoneMissedAndCardio() {
        let plan = TrainingWeekPlan(programs: ["1": "A", "3": "B", "5": "C"], since: "2026-11-02")
        let week = TrainingCalendar.weekDates(from: date(2), calendar: calendar)
        // Wednesday 4 Nov, 10:00: Monday's A was missed, B done on Tuesday, a walk on Wednesday.
        let days = TrainingDays.buildTrainingDays(week, plan: plan,
                                                  lifts: [lift(3, 18, program: "B")],
                                                  activities: [activity(4, 8)],
                                                  now: date(4, 10), calendar: calendar)
        XCTAssertTrue(days[0].isMissed)
        XCTAssertFalse(days[1].isMissed)
        XCTAssertTrue(days[1].hasLift)
        XCTAssertNil(days[1].plannedProgramId)
        XCTAssertTrue(days[2].isToday)
        XCTAssertTrue(days[2].isPlannedOpen)      // planned today, not done yet
        XCTAssertTrue(days[2].hasActivity)
        XCTAssertTrue(days[4].isPlannedOpen)      // Friday, still to do
        XCTAssertFalse(days[6].isPlannedOpen)     // Sunday: rest

        // A session moved to another day still counts for the week: 1 done / 3 planned.
        let tally = TrainingDays.sessionTally(days)
        XCTAssertEqual(tally.done, 1)
        XCTAssertEqual(tally.planned, 3)
        let totals = TrainingDays.periodTotals(days)
        XCTAssertEqual(totals.activities, 1)
        XCTAssertEqual(totals.minutes, 52 + 25)
    }

    func testDaysBeforeThePlanShowOnlyWhatWasDone() {
        let plan = TrainingWeekPlan(programs: ["1": "A"], since: "2026-11-02")
        let days = TrainingDays.buildTrainingDays([date(26, month: 10), date(2)], plan: plan, lifts: [],
                                                  activities: [], now: date(2, 9), calendar: calendar)
        XCTAssertNil(days[0].plannedProgramId)
        XCTAssertFalse(days[0].isMissed)
        XCTAssertEqual(days[1].plannedProgramId, "A")
    }

    func testCoachWeekPlanTextNamesTheDaysTheCountMissedAndToday() {
        let plan = TrainingWeekPlan(programs: ["1": "A", "3": "B", "5": "C"], since: "2026-11-02")
        let week = TrainingDays.buildTrainingDays(TrainingCalendar.weekDates(from: date(2), calendar: calendar),
                                                  plan: plan, lifts: [lift(3, 18, program: "B")],
                                                  activities: [], now: date(4, 10), calendar: calendar)
        let text = CoachFiche.weekPlanText(plan, programNames: ["A": "Full body A", "B": "Full body B", "C": "Full body C"],
                                           week: week)
        XCTAssertTrue(text.hasPrefix("WEEK PLAN"), text)
        XCTAssertTrue(text.contains("Monday: Full body A; Wednesday: Full body B; Friday: Full body C"), text)
        XCTAssertTrue(text.contains("1 Lift Log session done for 3 planned"), text)
        XCTAssertTrue(text.contains("Missed so far: Monday (Full body A)"), text)
        XCTAssertTrue(text.contains("Today (Wednesday): Full body B planned, not done yet"), text)
        XCTAssertEqual(CoachFiche.weekPlanText(TrainingWeekPlan(), programNames: [:], week: week), "")
    }

    // MARK: - Workouts

    private func workout(_ start: Int, sport: String, source: String = "manual") -> WorkoutRow {
        WorkoutRow(startTs: start, endTs: start + 3_000, sport: sport, source: source, durationS: 3_000,
                   energyKcal: 300, avgHr: 120, maxHr: 160, strain: 55, distanceM: nil, zonesJSON: nil,
                   notes: nil, steps: nil)
    }

    func testLiftSessionsOwnWorkoutRowsAreNotCountedAsActivities() {
        let start = ts(1, 14)
        let rows = [workout(start + 2, sport: "Strength Training"), workout(ts(1, 18), sport: "detected", source: "my-whoop-noop")]
        let split = TrainingDays.splitLiftWorkouts(rows, liftStarts: [start])
        XCTAssertEqual(split.lift[start]?.sport, "Strength Training")
        XCTAssertEqual(split.others.map(\.sport), ["detected"])
    }

    /// A session's length is its own workout row's, which leaves its pauses out (personal fork); without a row,
    /// end − start. The calendar's minutes read the same number.
    func testALiftSessionsLengthIsItsWorkoutRowsLeavingPausesOut() {
        let start = ts(1, 14)
        let row = workout(start, sport: "Strength Training")               // 3 000 s recorded
        XCTAssertEqual(TrainingDays.liftSessionSeconds(startTs: start, endTs: start + 3_600, workout: row), 3_000)
        XCTAssertEqual(TrainingDays.liftSessionSeconds(startTs: start, endTs: start + 3_600, workout: nil), 3_600)
        let done = TrainingLiftDone(sessionId: "s", programId: "A", name: "Full body A", startTs: start,
                                    endTs: start + 3_600, workingSets: 12, effort: nil, activeSeconds: 3_000)
        XCTAssertEqual(done.minutes, 50)
    }

    // MARK: - Program summary

    func testProgramSummaryShapeBlocksAndLength() {
        func line(_ ord: Int, _ name: String, _ sets: Int, _ group: String?) -> LiftProgramItemRow {
            LiftProgramItemRow(id: "\(ord)", deviceId: "d", programId: "A", ord: ord, exercise: name,
                               targetSets: sets, targetRepsLow: 8, targetRepsHigh: 10, targetRpe: nil,
                               targetWeightKg: nil, restSec: 90, note: nil, supersetGroup: group)
        }
        let items = [line(2, "Développé couché", 3, "B"), line(0, "Squat barre", 4, "A"),
                     line(1, "Tirage horizontal", 4, "A"), line(3, "Fentes", 3, "B"),
                     line(4, "Gainage", 2, nil)]
        let summary = TrainingDays.programSummary(
            id: "A", name: "Full body A", items: items,
            finished: [(startTs: ts(26, 18, month: 10), endTs: ts(26, 18, month: 10) + 50 * 60),
                       (startTs: ts(19, 18, month: 10), endTs: ts(19, 18, month: 10) + 60 * 60)])
        XCTAssertEqual(summary.supersets, 2)
        XCTAssertEqual(summary.singles, 1)
        XCTAssertEqual(summary.totalSets, 16)
        XCTAssertEqual(summary.typicalMinutes, 55)
        XCTAssertEqual(summary.lastDoneTs, ts(26, 18, month: 10))
        XCTAssertEqual(summary.blockCount, 3)
        XCTAssertEqual(summary.blocks, [
            TrainingBlockPreview(text: "A1 Squat barre · A2 Tirage horizontal", sets: 4),
            TrainingBlockPreview(text: "B1 Développé couché · B2 Fentes", sets: 3),
        ])
    }
}
