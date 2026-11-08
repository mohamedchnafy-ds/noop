import XCTest
import UserNotifications
import WhoopStore
@testable import Strand

/// Personal fork, chantier 15 PR C: the fast's end and halfway notifications (`FastingNotifier`). Pure: the
/// plan from a resolved state and the switches, the words, the requests; no notification center.
final class FastingNotifierTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func state(elapsedHours: Double, goal: Int = 960, ended: Bool = false) -> FastingState {
        let start = t0
        let now = start.addingTimeInterval(elapsedHours * 3600)
        let row = FastRow(id: "f", startedAt: Int(start.timeIntervalSince1970),
                          endedAt: ended ? Int(now.timeIntervalSince1970) : nil, goalMinutes: goal,
                          createdAt: 0, updatedAt: 0)
        return FastingLog.fastingState(of: row, now: now)
    }

    private func now(_ elapsedHours: Double) -> Date { t0.addingTimeInterval(elapsedHours * 3600) }

    // MARK: Plan

    func testNothingIsPlannedWithoutARunningFast() {
        XCTAssertEqual(FastingNotifier.fastingNotificationPlan(state: nil, endOn: true, halfOn: true, now: t0), [])
        XCTAssertEqual(FastingNotifier.fastingNotificationPlan(state: state(elapsedHours: 17, ended: true),
                                                               endOn: true, halfOn: true, now: now(17)), [])
    }

    func testBothArePlannedAtTheStartTheHalfFirst() {
        let plan = FastingNotifier.fastingNotificationPlan(state: state(elapsedHours: 0), endOn: true, halfOn: true, now: t0)
        XCTAssertEqual(plan, [FastingNotifier.Planned(kind: .half, fireAt: t0.addingTimeInterval(8 * 3600)),
                              FastingNotifier.Planned(kind: .end, fireAt: t0.addingTimeInterval(16 * 3600))])
    }

    func testTheDefaultsPlanTheEndOnly() {
        let plan = FastingNotifier.fastingNotificationPlan(state: state(elapsedHours: 1), endOn: true, halfOn: false, now: now(1))
        XCTAssertEqual(plan.map(\.kind), [.end])
    }

    func testATimeAlreadyPastIsNotPlanned() {
        // The start was moved back past the half: only the end is still to come.
        let plan = FastingNotifier.fastingNotificationPlan(state: state(elapsedHours: 9), endOn: true, halfOn: true, now: now(9))
        XCTAssertEqual(plan.map(\.kind), [.end])
        // Past the goal, nothing is left to announce.
        XCTAssertEqual(FastingNotifier.fastingNotificationPlan(state: state(elapsedHours: 17), endOn: true, halfOn: true,
                                                               now: now(17)), [])
    }

    func testEverythingOffPlansNothing() {
        XCTAssertEqual(FastingNotifier.fastingNotificationPlan(state: state(elapsedHours: 0), endOn: false, halfOn: false, now: t0), [])
    }

    // MARK: Words and requests

    func testTheEndSaysHowLongWasReachedAndTheHalfWhatIsLeft() {
        let end = FastingNotifier.fastingNotificationText(.end, goalMinutes: 960)
        XCTAssertTrue(end.title.contains("16h"), end.title)
        XCTAssertFalse(end.body.isEmpty)
        let half = FastingNotifier.fastingNotificationText(.half, goalMinutes: 1080)
        XCTAssertTrue(half.body.contains("9h"), "9h done, 9h to go: \(half.body)")
    }

    func testRequestsCarryTheFastingCategoryAndOneIdPerKind() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let plan = FastingNotifier.fastingNotificationPlan(state: state(elapsedHours: 0), endOn: true, halfOn: true, now: t0)
        let requests = FastingNotifier.fastingNotificationRequests(plan, goalMinutes: 960, calendar: calendar)
        XCTAssertEqual(requests.map(\.identifier), ["fasting-half", "fasting-end"])
        XCTAssertEqual(Set(requests.map(\.content.categoryIdentifier)), [FastingNotifier.categoryId])
        let trigger = requests[1].trigger as? UNCalendarNotificationTrigger
        XCTAssertNotNil(trigger)
        XCTAssertEqual(calendar.date(from: trigger!.dateComponents), t0.addingTimeInterval(16 * 3600))
    }
}
