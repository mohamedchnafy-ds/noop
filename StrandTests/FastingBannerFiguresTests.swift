import XCTest
import WhoopStore
@testable import Strand

/// Personal fork, chantier 15 PR C: the words of the fast's Lock Screen banner (`FastingBannerFigures`),
/// resolved app-side from the one resolver's state. Pure.
final class FastingBannerFiguresTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func state(elapsedHours: Double, ended: Bool = false) -> FastingState {
        let now = t0.addingTimeInterval(elapsedHours * 3600)
        let row = FastRow(id: "f", startedAt: Int(t0.timeIntervalSince1970),
                          endedAt: ended ? Int(now.timeIntervalSince1970) : nil, goalMinutes: 960,
                          createdAt: 0, updatedAt: 0)
        return FastingLog.fastingState(of: row, now: now)
    }

    func testARunningFastHasItsTitleDatesAndWords() throws {
        let figures = try XCTUnwrap(FastingBannerFigures.fastingBannerFigures(state(elapsedHours: 11.7)))
        XCTAssertTrue(figures.title.contains("16h"), figures.title)
        XCTAssertEqual(figures.startedAt, t0)
        XCTAssertEqual(figures.plannedEnd, t0.addingTimeInterval(16 * 3600))
        XCTAssertEqual(figures.goalMinutes, 960)
        XCTAssertFalse(figures.goalReached)
        XCTAssertFalse(figures.leftLabel.isEmpty)
        XCTAssertFalse(figures.stopLabel.isEmpty)
        XCTAssertTrue(figures.endLabel.contains(FastingFormat.clock(figures.plannedEnd)), figures.endLabel)
    }

    func testPastTheGoalTheBannerSaysSo() throws {
        let figures = try XCTUnwrap(FastingBannerFigures.fastingBannerFigures(state(elapsedHours: 16.5)))
        XCTAssertTrue(figures.goalReached)
        XCTAssertFalse(figures.goalReachedLabel.isEmpty)
    }

    func testAFastOverHasNoBanner() {
        XCTAssertNil(FastingBannerFigures.fastingBannerFigures(state(elapsedHours: 16.5, ended: true)))
    }
}
