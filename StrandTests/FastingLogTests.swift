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
}
