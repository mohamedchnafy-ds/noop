import XCTest
import StrandAnalytics
import WhoopStore
@testable import Strand

/// Personal fork, chantier 15: the one resolver of a fast's state (`FastingLog`), and the writes that
/// keep one fast running at a time.
final class FastingLogTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func row(start: Date, end: Date?, goal: Int = 960) -> FastRow {
        FastRow(id: "f", startedAt: Int(start.timeIntervalSince1970),
                endedAt: end.map { Int($0.timeIntervalSince1970) }, goalMinutes: goal,
                createdAt: Int(start.timeIntervalSince1970), updatedAt: Int(start.timeIntervalSince1970))
    }

    private static func utcDayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    // MARK: - Resolver

    func testARunningFastIsResolvedAgainstNow() {
        let start = t0
        let now = t0.addingTimeInterval(11 * 3600 + 42 * 60 + 30)
        let state = FastingLog.fastingState(of: row(start: start, end: nil), now: now)
        XCTAssertTrue(state.isRunning)
        XCTAssertEqual(state.elapsedMinutes, 702, "whole minutes, seconds dropped")
        XCTAssertEqual(state.remainingMinutes, 258)
        XCTAssertEqual(state.progressPermille, 731)
        XCTAssertEqual(state.phaseIndex, 2)
        XCTAssertEqual(state.phaseId, "glycogen")
        XCTAssertEqual(state.markers.map(\.phaseIndex), [1, 2, 3, 4])
        XCTAssertEqual(state.plannedEnd, start.addingTimeInterval(16 * 3600))
        XCTAssertFalse(state.goalReached)
    }

    func testAnEndedFastIsResolvedAgainstItsEndNotNow() {
        let end = t0.addingTimeInterval(16 * 3600 + 20 * 60)
        let state = FastingLog.fastingState(of: row(start: t0, end: end), now: end.addingTimeInterval(48 * 3600))
        XCTAssertFalse(state.isRunning)
        XCTAssertEqual(state.elapsedMinutes, 980)
        XCTAssertEqual(state.remainingMinutes, 0)
        XCTAssertTrue(state.goalReached)
        XCTAssertEqual(state.progressPermille, 1000)
        XCTAssertEqual(state.phaseIndex, 4)
    }

    /// 13 Nov. recording: « Fast over · 17 h 10 min » above « Ketosis · current » and « Autophagy · to come ».
    /// A fast that is over is judged at its end: nothing is current, nothing is still to come.
    func testThePhasesOfAFastThatIsOverAreJudgedAtItsEnd() {
        let end = t0.addingTimeInterval(17 * 3600 + 10 * 60)
        let state = FastingLog.fastingState(of: row(start: t0, end: end), now: end.addingTimeInterval(3 * 86_400))
        let standings = (0..<FastingTimeline.phaseIds.count).map { state.phaseStanding($0) }
        XCTAssertEqual(standings, [.passed, .passed, .passed, .passed, .reachedAtEnd, .notReached])
        XCTAssertFalse(standings.contains(.current))
        let texts = standings.map { FastingPhaseText.standingText($0) }
        XCTAssertEqual(texts[4], String(localized: "reached at the end"))
        XCTAssertEqual(texts[5], String(localized: "not reached"))
        XCTAssertFalse(texts.contains(String(localized: "current")))
        XCTAssertFalse(texts.contains(String(localized: "to come")))
    }

    func testThePhasesOfARunningFastAreJudgedAgainstNow() {
        let now = t0.addingTimeInterval(11 * 3600 + 42 * 60 + 30)
        let state = FastingLog.fastingState(of: row(start: t0, end: nil), now: now)
        let standings = (0..<FastingTimeline.phaseIds.count).map { state.phaseStanding($0) }
        XCTAssertEqual(standings, [.passed, .passed, .current, .upcoming(inMinutes: 18),
                                   .upcoming(inMinutes: 258), .upcoming(inMinutes: 738)])
    }

    func testAStartInTheFutureCountsAsZero() {
        let state = FastingLog.fastingState(of: row(start: t0.addingTimeInterval(600), end: nil), now: t0)
        XCTAssertEqual(state.elapsedMinutes, 0)
        XCTAssertEqual(state.phaseIndex, 0)
        XCTAssertEqual(state.remainingMinutes, 960)
    }

    // MARK: - Daily durations

    func testTheLongestFastThatEndedEachDayMakesTheHistoryAndTodayIsStillRunning() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        // t0 = 2027-01-15 08:00:00 UTC.
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let day: TimeInterval = 86_400
        let fasts = [
            FastRow(id: "a", startedAt: Int((now - 2 * day - 20 * 3600).timeIntervalSince1970),
                    endedAt: Int((now - 2 * day - 4 * 3600).timeIntervalSince1970), goalMinutes: 960, createdAt: 0, updatedAt: 0),  // 16 h, two days ago
            FastRow(id: "b", startedAt: Int((now - 1 * day - 14 * 3600).timeIntervalSince1970),
                    endedAt: Int((now - 1 * day - 2 * 3600).timeIntervalSince1970), goalMinutes: 960, createdAt: 0, updatedAt: 0),   // 12 h, yesterday
            FastRow(id: "b2", startedAt: Int((now - 1 * day - 1 * 3600).timeIntervalSince1970),
                    endedAt: Int((now - 1 * day).timeIntervalSince1970), goalMinutes: 960, createdAt: 0, updatedAt: 0),             // 1 h, yesterday: the longer one counts
            FastRow(id: "c", startedAt: Int((now - 6 * 3600).timeIntervalSince1970), endedAt: nil, goalMinutes: 960,
                    createdAt: 0, updatedAt: 0),                                                                                   // running: 6 h so far
        ]
        let durations = FastingLog.dailyFastMinutes(fasts, days: 4, now: now, calendar: utc, dayKey: Self.utcDayKey)
        XCTAssertEqual(durations, [0, 960, 720, 360])
        let summary = FastingTimeline.fastingSummary(durationsMinutes: durations, goalMinutes: 960)
        XCTAssertEqual(summary.keptCount, 1)
        XCTAssertEqual(summary.fastedCount, 3)
        XCTAssertEqual(summary.streak, 0)
        XCTAssertEqual(FastingLog.dailyFastMinutes(fasts, days: 0, now: now, calendar: utc, dayKey: Self.utcDayKey), [])
    }

    // MARK: - Writes

    func testStartingAFastClosesTheOneStillRunningAndRemembersTheGoal() async throws {
        let store = try await WhoopStore.inMemory()
        UserDefaults.standard.removeObject(forKey: FastingLog.lastGoalKey)
        let first = await FastingLog.startFast(store, startedAt: t0, goalMinutes: 1_080, now: t0)
        let second = await FastingLog.startFast(store, startedAt: t0.addingTimeInterval(3_600), goalMinutes: 5_000,
                                                now: t0.addingTimeInterval(3_600))
        let running = try await store.runningFast()
        XCTAssertEqual(running?.id, second.id)
        XCTAssertEqual(running?.goalMinutes, FastingTimeline.maxGoalMinutes, "the goal is clamped")
        let rows = try await store.recentFasts(limit: 10)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.last?.id, first.id)
        XCTAssertEqual(rows.last?.endedAt, Int(t0.timeIntervalSince1970) + 3_600, "closed at the new start")
        XCTAssertEqual(UserDefaults.standard.integer(forKey: FastingLog.lastGoalKey), FastingTimeline.maxGoalMinutes)

        await FastingLog.endFast(store, second, endedAt: t0, now: t0.addingTimeInterval(7_200))
        let ended = try await store.recentFasts(limit: 1).first
        XCTAssertEqual(ended?.endedAt, ended?.startedAt, "an end before the start is pulled up to the start")
        let none = await FastingLog.resolveFastingState(store, now: t0.addingTimeInterval(7_200))
        XCTAssertNil(none)
    }

    func testAmendingKeepsTheStartBeforeTheEndAndLeavesARunningFastOpen() async throws {
        let store = try await WhoopStore.inMemory()
        let fast = await FastingLog.startFast(store, startedAt: t0, goalMinutes: 960, now: t0)
        await FastingLog.amendFast(store, fast, startedAt: t0.addingTimeInterval(-3_600), goalMinutes: 1_080,
                                   endedAt: t0.addingTimeInterval(600), now: t0)
        let openRow = try await store.runningFast()
        let open = try XCTUnwrap(openRow)
        XCTAssertNil(open.endedAt, "a running fast gets no end from an amendment")
        XCTAssertEqual(open.startedAt, Int(t0.timeIntervalSince1970) - 3_600)
        XCTAssertEqual(open.goalMinutes, 1_080)

        await FastingLog.endFast(store, open, endedAt: t0.addingTimeInterval(10 * 3600), now: t0.addingTimeInterval(10 * 3600))
        let endedRow = try await store.recentFasts(limit: 1).first
        let ended = try XCTUnwrap(endedRow)
        await FastingLog.amendFast(store, ended, startedAt: t0.addingTimeInterval(20 * 3600), now: t0)
        let fixedRow = try await store.recentFasts(limit: 1).first
        let fixed = try XCTUnwrap(fixedRow)
        XCTAssertEqual(fixed.startedAt, fixed.endedAt, "a start after the end is pulled back to the end")
    }

    // MARK: - A meal during a fast (PR C)

    func testAMealDuringARunningFastAsksToEndItAtTheMealTime() throws {
        let fast = row(start: t0, end: nil)
        let meal = t0.addingTimeInterval(16 * 3600)
        let q = try XCTUnwrap(FastingLog.mealEndQuestion(newest: fast, eatenAt: meal, kcal: 600,
                                                         now: meal.addingTimeInterval(90 * 60)))
        XCTAssertTrue(q.wasRunning)
        XCTAssertEqual(q.endAt, meal, "a meal logged later still ends the fast at its own time")
        XCTAssertEqual(q.minutesAtEnd, 960)
    }

    func testACalorieFreeDrinkAMealBeforeTheStartOrAFutureMealAsksNothing() {
        let fast = row(start: t0, end: nil)
        let now = t0.addingTimeInterval(10 * 3600)
        XCTAssertNil(FastingLog.mealEndQuestion(newest: fast, eatenAt: now, kcal: FastingLog.mealFreeKcal, now: now),
                     "10 kcal or less (black coffee, tea) is not a meal")
        XCTAssertNotNil(FastingLog.mealEndQuestion(newest: fast, eatenAt: now, kcal: FastingLog.mealFreeKcal + 1, now: now))
        XCTAssertNil(FastingLog.mealEndQuestion(newest: fast, eatenAt: t0, kcal: 500, now: now), "eaten at the start")
        XCTAssertNil(FastingLog.mealEndQuestion(newest: fast, eatenAt: t0.addingTimeInterval(-3600), kcal: 500, now: now))
        XCTAssertNil(FastingLog.mealEndQuestion(newest: fast, eatenAt: now.addingTimeInterval(120), kcal: 500, now: now),
                     "a meal planned later does not end the fast now")
        XCTAssertNil(FastingLog.mealEndQuestion(newest: nil, eatenAt: now, kcal: 500, now: now))
    }

    func testAMealInsideAFastAlreadyOverAsksToMoveItsEndBack() throws {
        let end = t0.addingTimeInterval(18 * 3600)
        let fast = row(start: t0, end: end)
        let now = end.addingTimeInterval(3600)
        let q = try XCTUnwrap(FastingLog.mealEndQuestion(newest: fast, eatenAt: end.addingTimeInterval(-90 * 60),
                                                         kcal: 450, now: now))
        XCTAssertFalse(q.wasRunning)
        XCTAssertEqual(q.minutesAtEnd, 16 * 60 + 30)
        XCTAssertNil(FastingLog.mealEndQuestion(newest: fast, eatenAt: end, kcal: 450, now: now), "at the end: nothing to move")
        XCTAssertNil(FastingLog.mealEndQuestion(newest: fast, eatenAt: end.addingTimeInterval(600), kcal: 450, now: now))
    }

    // MARK: - A fast over, on the card and the page (13 Nov 2026)

    private static let utc: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .current
        return cal
    }()

    private func utcDate(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        Self.utc.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute)) ?? t0
    }

    private func shown(_ fast: FastRow?, running: FastRow? = nil, dismissed: String = "", at now: Date,
                       rollover: Int) -> FastingState? {
        FastingLog.shownFastingState(running: running, newest: fast, dismissedId: dismissed, now: now,
                                     calendar: Self.utc, rolloverHour: rollover)
    }

    func testAFastOverStaysShownUntilTheEndOfTheLogicalDayAfterItsEnd() {
        // The screen recording of 13 Nov: a fast over on 10 Nov at 17:32 (17 h 10 min out of 18 h).
        let end = utcDate(10, 17, 32)
        let fast = row(start: end.addingTimeInterval(-(17 * 3600 + 10 * 60)), end: end, goal: 18 * 60)
        XCTAssertEqual(FastingLog.finishedFastShownUntil(endedAt: end, calendar: Self.utc, rolloverHour: 0),
                       utcDate(12, 0, 0))
        XCTAssertEqual(shown(fast, at: end.addingTimeInterval(60), rollover: 0)?.elapsedMinutes, 17 * 60 + 10)
        XCTAssertNotNil(shown(fast, at: utcDate(11, 23, 59), rollover: 0), "the next day still shows it")
        XCTAssertNil(shown(fast, at: utcDate(12, 0, 0), rollover: 0), "two days on: back to idle")
        XCTAssertNil(shown(fast, at: utcDate(13, 9, 0), rollover: 0), "the case seen on 13 Nov")
    }

    func testTheWindowFollowsTheLogicalDayRollover() {
        // Rolling at 04:00, a fast over at 01:00 on 11 Nov belongs to the logical day of 10 Nov.
        let end = utcDate(11, 1, 0)
        let fast = row(start: end.addingTimeInterval(-16 * 3600), end: end)
        XCTAssertEqual(FastingLog.finishedFastShownUntil(endedAt: end, calendar: Self.utc, rolloverHour: 4),
                       utcDate(12, 4, 0))
        XCTAssertNotNil(shown(fast, at: utcDate(12, 3, 59), rollover: 4))
        XCTAssertNil(shown(fast, at: utcDate(12, 4, 0), rollover: 4))
        // Rolling at midnight, the same end belongs to 11 Nov and is shown through 12 Nov.
        XCTAssertNotNil(shown(fast, at: utcDate(12, 23, 59), rollover: 0))
        XCTAssertNil(shown(fast, at: utcDate(13, 0, 0), rollover: 0))
    }

    func testARunningFastIsAlwaysShownAndADismissedOneNever() {
        let start = utcDate(1, 20, 0)
        let open = row(start: start, end: nil)
        let longAfter = utcDate(13, 9, 0)
        let state = shown(nil, running: open, at: longAfter, rollover: 0)
        XCTAssertEqual(state?.isRunning, true, "a running fast is never hidden, however long it runs")
        let over = row(start: utcDate(12, 20, 0), end: utcDate(13, 12, 0))
        XCTAssertNotNil(shown(over, at: utcDate(13, 13, 0), rollover: 0))
        XCTAssertNil(shown(over, dismissed: "f", at: utcDate(13, 13, 0), rollover: 0), "« New fast » hides it")
        XCTAssertNil(shown(nil, at: longAfter, rollover: 0), "no fast at all: idle")
    }
}
