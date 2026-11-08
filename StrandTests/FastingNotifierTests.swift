import XCTest
import WhoopStore
@testable import Strand

/// Personal fork, chantier 15 PR C: what the fasting notifications plan for a fast, from its resolved state.
final class FastingNotifierTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func state(end: Date?, goal: Int = 960, now: Date) -> FastingState {
        let row = FastRow(id: "f", startedAt: Int(t0.timeIntervalSince1970),
                          endedAt: end.map { Int($0.timeIntervalSince1970) }, goalMinutes: goal,
                          createdAt: Int(t0.timeIntervalSince1970), updatedAt: Int(t0.timeIntervalSince1970))
        return FastingLog.fastingState(of: row, now: now)
    }

    func testARunningFastPlansTheEndAndTheHalfwayPointWhenAsked() {
        let now = t0.addingTimeInterval(3 * 3600)
        let s = state(end: nil, now: now)
        XCTAssertEqual(FastingNotifier.planFastingNotifications(s, endOn: true, halfOn: false, now: now),
                       [.init(kind: .end, fireAt: t0.addingTimeInterval(16 * 3600))])
        XCTAssertEqual(FastingNotifier.planFastingNotifications(s, endOn: true, halfOn: true, now: now),
                       [.init(kind: .half, fireAt: t0.addingTimeInterval(8 * 3600)),
                        .init(kind: .end, fireAt: t0.addingTimeInterval(16 * 3600))])
        XCTAssertEqual(FastingNotifier.planFastingNotifications(s, endOn: false, halfOn: false, now: now), [])
    }

    func testOnlyWhatIsStillToComeIsPlanned() {
        let now = t0.addingTimeInterval(10 * 3600)
        let s = state(end: nil, now: now)
        XCTAssertEqual(FastingNotifier.planFastingNotifications(s, endOn: true, halfOn: true, now: now),
                       [.init(kind: .end, fireAt: t0.addingTimeInterval(16 * 3600))], "halfway is past")
        let late = t0.addingTimeInterval(17 * 3600)
        XCTAssertEqual(FastingNotifier.planFastingNotifications(state(end: nil, now: late), endOn: true, halfOn: true, now: late), [])
    }

    func testAFastOverOrNoFastPlansNothing() {
        let now = t0.addingTimeInterval(3 * 3600)
        XCTAssertEqual(FastingNotifier.planFastingNotifications(state(end: now, now: now), endOn: true, halfOn: true, now: now), [])
        XCTAssertEqual(FastingNotifier.planFastingNotifications(nil, endOn: true, halfOn: true, now: now), [])
    }
}
