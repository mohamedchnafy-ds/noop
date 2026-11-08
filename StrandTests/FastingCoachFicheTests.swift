import XCTest
import StrandAnalytics
import WhoopStore
@testable import Strand

/// Personal fork, chantier 15 PR C: the fiche's FASTING block states the Jeûne page's figures.
final class FastingCoachFicheTests: XCTestCase {

    private let utc = TimeZone(identifier: "UTC")!
    /// 08:00 UTC on a fixed day.
    private let t0 = Date(timeIntervalSince1970: TimeInterval(1_800_000_000 - 1_800_000_000 % 86_400 + 8 * 3600))

    private func row(start: Date, end: Date?, goal: Int = 960) -> FastRow {
        FastRow(id: "f", startedAt: Int(start.timeIntervalSince1970), endedAt: end.map { Int($0.timeIntervalSince1970) },
                goalMinutes: goal, createdAt: 0, updatedAt: 0)
    }

    private let summary = FastingTimeline.Summary(averageMinutes: 989, keptCount: 5, fastedCount: 6, streak: 1)

    func testARunningFastStatesItsFiguresThePhaseAndTheWeek() {
        let now = t0.addingTimeInterval(11 * 3600 + 42 * 60)
        let running = FastingLog.fastingState(of: row(start: t0, end: nil), now: now)
        let block = CoachFiche.fastingBlock(
            CoachFiche.Fasting(running: running, lastOver: nil, dayMinutes: [960, 0, 1000, 980, 990, 1010, 702],
                               summary: summary, goalMinutes: 960, waterML: 1250, waterGoalML: 2900),
            zone: utc)
        XCTAssertTrue(block.hasPrefix("FASTING ("))
        XCTAssertTrue(block.contains("11h 42m done out of a 16h 00m goal, 4h 18m left"), block)
        XCTAssertTrue(block.contains("phase: glycogen (8-12 h)"), block)
        XCTAssertTrue(block.contains("6 days with a fast, goal kept 5, mean 16h 29m, streak 1 day"), block)
        XCTAssertTrue(block.contains("16h 00m, -, 16h 40m"), block)
        XCTAssertTrue(block.contains("water today: 1.25 L of a 2.90 L goal"), block)
    }

    func testNoFastRunningStatesTheLastOneOrSaysSo() {
        let end = t0.addingTimeInterval(16 * 3600 + 20 * 60)
        let last = FastingLog.fastingState(of: row(start: t0, end: end), now: end.addingTimeInterval(3600))
        let empty = FastingTimeline.Summary(averageMinutes: 0, keptCount: 0, fastedCount: 0, streak: 0)
        let block = CoachFiche.fastingBlock(
            CoachFiche.Fasting(running: nil, lastOver: last, dayMinutes: Array(repeating: 0, count: 7),
                               summary: empty, goalMinutes: 960, waterML: 0, waterGoalML: 2900), zone: utc)
        XCTAssertTrue(block.contains("no fast running; the last one:"), block)
        XCTAssertTrue(block.contains("16h 20m out of 16h 00m (goal reached)"), block)
        XCTAssertTrue(block.contains("the last 7 days: no fast"), block)
        let none = CoachFiche.fastingBlock(
            CoachFiche.Fasting(running: nil, lastOver: nil, dayMinutes: [], summary: empty, goalMinutes: 960,
                               waterML: 500, waterGoalML: 2900), zone: utc)
        XCTAssertTrue(none.contains("no fast logged yet"), none)
    }
}
