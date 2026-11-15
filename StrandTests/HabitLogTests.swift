import XCTest
import WhoopStore
@testable import Strand

/// Personal fork, chantier 24: the one resolver of a habit's figures (`HabitLog`), the checks of a
/// session entered by hand, and the writes that keep one stopwatch running at a time.
final class HabitLogTests: XCTestCase {

    private let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func at(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        utc.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    private func sec(_ date: Date) -> Int { Int(date.timeIntervalSince1970) }

    private func session(_ id: String, _ start: Date, _ end: Date?, habit: String = "h") -> HabitSessionRow {
        HabitSessionRow(id: id, habitId: habit, startedAt: sec(start), endedAt: end.map(sec), note: nil,
                        isManual: false, createdAt: sec(start), updatedAt: sec(start))
    }

    private let noSummary = HabitSessionSummary(count: 0, totalSeconds: 0, firstStartedAt: nil)

    // MARK: - Pure rules

    func testNotesAndNamesAreTrimmedAndBlankMeansNone() {
        XCTAssertNil(HabitLog.storedNote(nil))
        XCTAssertNil(HabitLog.storedNote("  \n "))
        XCTAssertEqual(HabitLog.storedNote("  Du mal à me concentrer. \n"), "Du mal à me concentrer.")
        XCTAssertNil(HabitLog.storedHabitName("   "))
        XCTAssertEqual(HabitLog.storedHabitName(" Lecture "), "Lecture")
    }

    func testARunningSessionLastsUpToNow() {
        let running = session("r", at(11, 15, 21, 48), nil)
        XCTAssertEqual(HabitLog.habitSessionSeconds(running, nowSec: sec(at(11, 15, 22, 1))), 13 * 60)
        let ended = session("e", at(11, 15, 21, 0), at(11, 15, 21, 30))
        XCTAssertEqual(HabitLog.habitSessionSeconds(ended, nowSec: sec(at(11, 16, 9))), 30 * 60)
    }

    func testTheProblemsOfASessionEnteredByHand() {
        let now = sec(at(11, 15, 12))
        let others = [session("a", at(11, 15, 9), at(11, 15, 10)), session("run", at(11, 15, 11, 30), nil)]
        func problem(_ start: Date, _ end: Date, editing: String? = nil) -> HabitSessionProblem? {
            HabitLog.habitSessionProblem(startSec: sec(start), endSec: sec(end), others: others, editingId: editing,
                                         nowSec: now)
        }
        XCTAssertEqual(problem(at(11, 15, 8), at(11, 15, 8)), .endNotAfterStart)
        XCTAssertEqual(problem(at(11, 15, 8), at(11, 15, 7)), .endNotAfterStart)
        XCTAssertEqual(problem(at(11, 15, 11, 50), at(11, 15, 13)), .inFuture)
        XCTAssertEqual(problem(at(11, 14, 6), at(11, 14, 18, 1)), .tooLong)
        XCTAssertNil(problem(at(11, 14, 6), at(11, 14, 18)), "exactly 12 h is accepted")
        XCTAssertEqual(problem(at(11, 15, 9, 30), at(11, 15, 10, 30)), .overlaps)
        XCTAssertNil(problem(at(11, 15, 10), at(11, 15, 11)), "touching ends do not overlap")
        XCTAssertEqual(problem(at(11, 15, 11), at(11, 15, 11, 45)), .overlaps, "the running one counts up to now")
        XCTAssertNil(problem(at(11, 15, 9, 15), at(11, 15, 9, 45), editing: "a"), "the edited session is left out")
    }

    func testASessionCountsForTheLogicalDayItStartedOn() {
        let lateSunday = session("s", at(11, 15, 23, 30), at(11, 16, 0, 40))
        XCTAssertEqual(HabitLog.habitSessionDay(lateSunday, calendar: utc, rolloverHour: 0), at(11, 15, 0))
        let smallHours = session("m", at(11, 16, 1), at(11, 16, 1, 30))
        XCTAssertEqual(HabitLog.habitSessionDay(smallHours, calendar: utc, rolloverHour: 0), at(11, 16, 0))
        XCTAssertEqual(HabitLog.habitSessionDay(smallHours, calendar: utc, rolloverHour: 4), at(11, 15, 0),
                       "with a 04:00 day cycle, 01:00 still belongs to the day before")
    }

    // MARK: - Bars

    func testTheWeekBarsRunMondayToSundayAndSkipTheRunningSession() {
        let now = at(11, 11, 10)                                         // Wednesday 11 Nov 2026
        let sessions = [
            session("lastSunday", at(11, 8, 20), at(11, 8, 20, 30)),       // previous week: out
            session("monday", at(11, 9, 21, 30), at(11, 9, 22, 10)),       // 40 min
            session("tuesdayLate", at(11, 10, 23, 30), at(11, 11, 0, 40)), // 70 min, counts on Tuesday
            session("running", at(11, 11, 9), nil),                        // running: out
        ]
        let bars = HabitLog.habitBars(sessions, period: .week, now: now, calendar: utc, rolloverHour: 0)
        XCTAssertEqual(bars.count, 7)
        XCTAssertEqual(bars.first?.start, at(11, 9, 0))
        XCTAssertEqual(bars.last?.start, at(11, 15, 0))
        XCTAssertEqual(bars.map(\.seconds), [40 * 60, 70 * 60, 0, 0, 0, 0, 0])
    }

    func testTheMonthAndQuarterBarsEndToday() {
        let now = at(11, 11, 10)
        let sessions = [session("old", at(8, 1, 9), at(8, 1, 10)), session("today", at(11, 11, 7), at(11, 11, 7, 20))]
        let month = HabitLog.habitBars(sessions, period: .month, now: now, calendar: utc, rolloverHour: 0)
        XCTAssertEqual(month.count, 30)
        XCTAssertEqual(month.first?.start, at(10, 13, 0))
        XCTAssertEqual(month.last?.start, at(11, 11, 0))
        XCTAssertEqual(month.last?.seconds, 20 * 60)
        XCTAssertEqual(month.map(\.seconds).reduce(0, +), 20 * 60, "a session before the 30 days is out")

        let quarter = HabitLog.habitBars(sessions, period: .quarter, now: now, calendar: utc, rolloverHour: 0)
        XCTAssertEqual(quarter.count, 12)
        XCTAssertEqual(quarter.last?.start, at(11, 9, 0), "the last bar is this week, from Monday")
        XCTAssertEqual(quarter.first?.start, at(8, 24, 0))
        XCTAssertEqual(quarter.last?.seconds, 20 * 60)
    }

    // MARK: - Figures

    func testWeekAndMonthTotalsCountEndedSessionsByTheirStartDay() {
        let now = at(11, 3, 12)                                          // Tuesday 3 Nov; month from Sunday 1 Nov
        let sessions = [
            session("october", at(10, 31, 21), at(10, 31, 21, 30)),        // neither
            session("sunday", at(11, 1, 21), at(11, 1, 21, 15)),           // month only
            session("monday", at(11, 2, 21), at(11, 2, 21, 45)),           // both
            session("running", at(11, 3, 11), nil),                        // neither: running
        ]
        let summary = HabitSessionSummary(count: 3, totalSeconds: 90 * 60, firstStartedAt: sec(at(10, 31, 21)))
        let figures = HabitLog.habitFigures(sessions, allTime: summary, now: now, calendar: utc, rolloverHour: 0)
        XCTAssertEqual(figures.weekSeconds, 45 * 60)
        XCTAssertEqual(figures.monthSeconds, 60 * 60)
        XCTAssertEqual(figures.allTime, summary)
        XCTAssertEqual(figures.bars(.week), figures.weekBars)
        XCTAssertEqual(figures.weekBars.map(\.seconds).reduce(0, +), figures.weekSeconds,
                       "the week bars and the week total are one figure")
    }

    func testDaySpansSplitAtMidnight() {
        let late = session("late", at(11, 15, 23, 30), at(11, 16, 0, 40))
        XCTAssertEqual(HabitLog.habitDaySpans(late, nowSec: sec(at(11, 16, 9)), calendar: utc),
                       [HabitDaySpan(startMinute: 1_410, endMinute: 1_440), HabitDaySpan(startMinute: 0, endMinute: 40)])
        let running = session("run", at(11, 16, 7, 10), nil)
        XCTAssertEqual(HabitLog.habitDaySpans(running, nowSec: sec(at(11, 16, 7, 25)), calendar: utc),
                       [HabitDaySpan(startMinute: 430, endMinute: 445)])
    }

    func testTheFiguresWindowCoversTwelveWeeks() {
        let now = at(11, 11, 10)
        let from = HabitLog.habitFiguresWindowStart(now: now, calendar: utc, rolloverHour: 0)
        XCTAssertEqual(from, at(8, 23, 0), "the Monday of the first of the 12 weeks, a day early")
        let figures = HabitLog.habitFigures([], allTime: noSummary, now: now, calendar: utc, rolloverHour: 0)
        XCTAssertGreaterThanOrEqual(figures.quarterBars.first!.start, from)
    }

    // MARK: - Writes

    func testStartingAStopwatchEndsTheOneRunningAndRemembersTheHabit() async throws {
        let store = try await WhoopStore.inMemory()
        let t0 = at(11, 15, 21)
        let first = await HabitLog.startHabitStopwatch(store, habitId: "read", startedAt: t0, now: t0)
        let second = await HabitLog.startHabitStopwatch(store, habitId: "meditate", startedAt: t0.addingTimeInterval(600),
                                                        now: t0.addingTimeInterval(600))
        let running = await HabitLog.resolveRunningHabit(store)
        XCTAssertEqual(running?.id, second.id)
        let reads = await HabitLog.loadHabitSessions(store, habitId: "read")
        XCTAssertEqual(reads.first?.id, first.id)
        XCTAssertEqual(reads.first?.endedAt, sec(t0) + 600, "closed at the new start")
        XCTAssertEqual(UserDefaults.standard.string(forKey: HabitLog.lastStartedKey), "meditate")

        let stopped = await HabitLog.stopHabitStopwatch(store, second, endedAt: t0, note: "  Distrait. ",
                                                        now: t0.addingTimeInterval(900))
        XCTAssertEqual(stopped.endedAt, stopped.startedAt, "an end before the start is pulled up to the start")
        XCTAssertEqual(stopped.note, "Distrait.")
        let none = await HabitLog.resolveRunningHabit(store)
        XCTAssertNil(none)
    }

    func testASessionByHandIsRefusedOnOverlapAndSavedOtherwise() async throws {
        let store = try await WhoopStore.inMemory()
        let now = at(11, 15, 20)
        let refused = await HabitLog.addHabitSessionByHand(store, habitId: "h", startedAt: at(11, 15, 12),
                                                           endedAt: at(11, 15, 11), note: nil, now: now)
        XCTAssertEqual(refused, .endNotAfterStart)
        let saved = await HabitLog.addHabitSessionByHand(store, habitId: "h", startedAt: at(11, 15, 13),
                                                         endedAt: at(11, 15, 13, 18), note: "Pause déjeuner.", now: now)
        XCTAssertNil(saved)
        let overlap = await HabitLog.addHabitSessionByHand(store, habitId: "h", startedAt: at(11, 15, 13, 10),
                                                           endedAt: at(11, 15, 14), note: nil, now: now)
        XCTAssertEqual(overlap, .overlaps)
        let otherHabit = await HabitLog.addHabitSessionByHand(store, habitId: "other", startedAt: at(11, 15, 13, 10),
                                                              endedAt: at(11, 15, 14), note: nil, now: now)
        XCTAssertNil(otherHabit, "another habit may overlap")
        let rows = await HabitLog.loadHabitSessions(store, habitId: "h")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.isManual, true)
        XCTAssertEqual(rows.first?.note, "Pause déjeuner.")
    }

    func testAmendingASessionChecksItAndClearsAnEmptyNote() async throws {
        let store = try await WhoopStore.inMemory()
        let now = at(11, 15, 20)
        await HabitLog.addHabitSessionByHand(store, habitId: "h", startedAt: at(11, 15, 9), endedAt: at(11, 15, 10),
                                             note: "a", now: now)
        await HabitLog.addHabitSessionByHand(store, habitId: "h", startedAt: at(11, 15, 13), endedAt: at(11, 15, 14),
                                             note: "b", now: now)
        let rows = await HabitLog.loadHabitSessions(store, habitId: "h")
        let morning = try XCTUnwrap(rows.last)
        let clash = await HabitLog.amendHabitSession(store, morning, startedAt: at(11, 15, 9),
                                                     endedAt: at(11, 15, 13, 30), note: "a", now: now)
        XCTAssertEqual(clash, .overlaps)
        let fixed = await HabitLog.amendHabitSession(store, morning, startedAt: at(11, 15, 8, 30),
                                                     endedAt: at(11, 15, 10, 15), note: "  ", now: now)
        XCTAssertNil(fixed)
        let after = await HabitLog.loadHabitSessions(store, habitId: "h")
        XCTAssertEqual(after.last?.startedAt, sec(at(11, 15, 8, 30)))
        XCTAssertEqual(after.last?.endedAt, sec(at(11, 15, 10, 15)))
        XCTAssertNil(after.last?.note)

        let running = await HabitLog.startHabitStopwatch(store, habitId: "h", startedAt: at(11, 15, 19), now: now)
        let future = await HabitLog.amendHabitSession(store, running, startedAt: at(11, 15, 21), endedAt: nil,
                                                      note: nil, now: now)
        XCTAssertEqual(future, .inFuture)
        let earlier = await HabitLog.amendHabitSession(store, running, startedAt: at(11, 15, 18), endedAt: nil,
                                                       note: "Commencé plus tôt", now: now)
        XCTAssertNil(earlier)
        let stillRunning = await HabitLog.resolveRunningHabit(store)
        XCTAssertEqual(stillRunning?.startedAt, sec(at(11, 15, 18)))
        XCTAssertNil(stillRunning?.endedAt, "a running session keeps running")
    }

    func testHabitsAreCreatedEditedAndRemovedWithTheirSessions() async throws {
        let store = try await WhoopStore.inMemory()
        let blank = await HabitLog.createHabit(store, name: "  ", colorKey: "cyan", symbol: "book.fill")
        XCTAssertNil(blank)
        let created = await HabitLog.createHabit(store, name: " Lecture ", colorKey: "cyan", symbol: "book.fill",
                                                 now: at(11, 1, 9))
        let read = try XCTUnwrap(created)
        XCTAssertEqual(read.name, "Lecture")
        let refused = await HabitLog.editHabit(store, read, name: "", colorKey: "violet", symbol: "book.fill")
        XCTAssertFalse(refused)
        let edited = await HabitLog.editHabit(store, read, name: "Lecture du soir", colorKey: "violet",
                                              symbol: "book.closed.fill")
        XCTAssertTrue(edited)
        var habits = await HabitLog.loadHabitList(store)
        XCTAssertEqual(habits.map(\.name), ["Lecture du soir"])
        XCTAssertEqual(habits.first?.colorKey, "violet")

        await HabitLog.startHabitStopwatch(store, habitId: read.id, startedAt: at(11, 15, 21), now: at(11, 15, 21))
        await HabitLog.removeHabit(store, read)
        habits = await HabitLog.loadHabitList(store)
        XCTAssertTrue(habits.isEmpty)
        let running = await HabitLog.resolveRunningHabit(store)
        XCTAssertNil(running, "its running stopwatch went with it")
        XCTAssertNil(UserDefaults.standard.string(forKey: HabitLog.lastStartedKey))
    }

    func testTheFiguresReadAgainstTheStore() async throws {
        let store = try await WhoopStore.inMemory()
        let now = at(11, 11, 20)
        await HabitLog.addHabitSessionByHand(store, habitId: "h", startedAt: at(11, 10, 21), endedAt: at(11, 10, 21, 30),
                                             note: nil, now: now)
        await HabitLog.addHabitSessionByHand(store, habitId: "h", startedAt: at(7, 1, 21), endedAt: at(7, 1, 22),
                                             note: nil, now: now)
        let figures = await HabitLog.resolveHabitFigures(store, habitId: "h", now: now, calendar: utc)
        XCTAssertEqual(figures.allTime.count, 2)
        XCTAssertEqual(figures.allTime.totalSeconds, 90 * 60)
        XCTAssertEqual(figures.allTime.firstStartedAt, sec(at(7, 1, 21)))
        let between = await HabitLog.loadHabitSessionsBetween(store, from: at(11, 1, 0), to: now)
        XCTAssertEqual(between.count, 1)
    }
}
