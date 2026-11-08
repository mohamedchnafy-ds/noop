import XCTest
import StrandAnalytics
@testable import Strand

/// Personal fork, chantier 15 PR C: the FASTING block of the Coach's fiche and the fasting chips. Pure
/// formatting over resolved inputs.
final class CoachFastingBlockTests: XCTestCase {

    private let utc = TimeZone(identifier: "UTC")!
    /// 2026-11-07 20:30 UTC.
    private let start = Date(timeIntervalSince1970: 1_794_083_400)

    private func fasting(running: CoachFiche.Fasting.Running? = nil, last: CoachFiche.Fasting.Last? = nil,
                         summary: FastingTimeline.Summary = FastingTimeline.Summary(averageMinutes: 989, keptCount: 5, fastedCount: 6, streak: 1))
        -> CoachFiche.Fasting {
        CoachFiche.Fasting(running: running, last: last, weekSummary: summary, weekDays: 7, weekGoalMinutes: 960,
                           waterML: 1250, waterGoalML: 2900)
    }

    func testARunningFastStatesItsFiguresPhaseAndTheWeek() {
        let running = CoachFiche.Fasting.Running(startedAt: start, elapsedMinutes: 702, goalMinutes: 960, remainingMinutes: 258,
                                                 plannedEnd: start.addingTimeInterval(16 * 3600), phaseIndex: 2)
        let block = CoachFiche.fastingBlock(fasting(running: running), timeZone: utc)
        XCTAssertTrue(block.hasPrefix("FASTING ("), block)
        XCTAssertTrue(block.contains("running since 2026-11-07 20:30: 11h 42m done out of 16h 00m, 4h 18m left, planned end 2026-11-08 12:30, phase glycogen running low (8–12 h)"), block)
        XCTAssertTrue(block.contains("last 7 days: fasted 6 of 7 days, goal (16h 00m) kept 5, mean 16h 29m, streak 1 day"), block)
        XCTAssertTrue(block.contains("water today: 1.25 L of 2.9 L goal"), block)
        XCTAssertTrue(block.contains("not medical advice"), block)
    }

    func testPastTheGoalTheBlockSaysSoInsteadOfALeftTime() {
        let running = CoachFiche.Fasting.Running(startedAt: start, elapsedMinutes: 980, goalMinutes: 960, remainingMinutes: 0,
                                                 plannedEnd: start.addingTimeInterval(16 * 3600), phaseIndex: 4)
        let block = CoachFiche.fastingBlock(fasting(running: running), timeZone: utc)
        XCTAssertTrue(block.contains("16h 20m done out of 16h 00m, goal reached (20m past it), phase ketosis (16–24 h)"), block)
        XCTAssertFalse(block.contains("left"), block)
    }

    func testWithoutARunningFastTheLastOneIsStated() {
        let last = CoachFiche.Fasting.Last(startedAt: start, endedAt: start.addingTimeInterval(15 * 3600), durationMinutes: 900, goalMinutes: 960)
        let block = CoachFiche.fastingBlock(fasting(last: last), timeZone: utc)
        XCTAssertTrue(block.contains("no fast running; last fast 2026-11-07 20:30 → 2026-11-08 11:30, 15h 00m out of 16h 00m (stopped 1h 00m before the goal)"), block)
    }

    func testAWeekWithoutAFastKeepsOneLine() {
        let block = CoachFiche.fastingBlock(fasting(summary: FastingTimeline.Summary(averageMinutes: 0, keptCount: 0, fastedCount: 0, streak: 0)), timeZone: utc)
        XCTAssertTrue(block.contains("no fast running\n"), block)
        XCTAssertTrue(block.contains("last 7 days: fasted 0 of 7 days\n"), block)
        XCTAssertFalse(block.contains("mean"), block)
    }

    func testTheHeadPutsFastingAfterNutritionAndOmitsItWhenNil() {
        var inputs = CoachFiche.Inputs()
        inputs.today = CoachFiche.Today(day: "2026-11-08")
        XCTAssertFalse(CoachFiche.head(inputs, told: "").contains("FASTING"))
        inputs.fasting = fasting()
        let head = CoachFiche.head(inputs, told: "")
        let today = head.range(of: "TODAY (")!.lowerBound
        let fastingAt = head.range(of: "FASTING (")!.lowerBound
        XCTAssertTrue(today < fastingAt, head)
    }

    func testLitresDropTrailingZeros() {
        XCTAssertEqual(CoachFiche.litres(1250), "1.25 L")
        XCTAssertEqual(CoachFiche.litres(2900), "2.9 L")
        XCTAssertEqual(CoachFiche.litres(2000), "2 L")
        XCTAssertEqual(CoachFiche.litres(0), "0 L")
    }

    func testFastingChipsFollowTheFastAndTheWeek() {
        XCTAssertEqual(CoachPrompts.fastingQuickPrompts(running: false, hasWeekHistory: false), [])
        XCTAssertEqual(CoachPrompts.fastingQuickPrompts(running: true, hasWeekHistory: false).count, 1)
        XCTAssertEqual(CoachPrompts.fastingQuickPrompts(running: true, hasWeekHistory: true).count, 2)
        XCTAssertEqual(CoachPrompts.fastingQuickPrompts(running: false, hasWeekHistory: true).map(\.label),
                       [String(localized: "My fasting this week")])
    }
}
