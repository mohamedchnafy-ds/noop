import XCTest
import WhoopStore
@testable import Strand

/// Personal fork, chantier 15 PR C: what a meal logged during a fast proposes (`FastingMealLink`). Pure:
/// rows in, a proposal or nil out; no store, no defaults.
final class FastingMealLinkTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func fast(start: Date, end: Date? = nil, goal: Int = 960) -> FastRow {
        FastRow(id: "fast", startedAt: Int(start.timeIntervalSince1970),
                endedAt: end.map { Int($0.timeIntervalSince1970) }, goalMinutes: goal,
                createdAt: Int(start.timeIntervalSince1970), updatedAt: Int(start.timeIntervalSince1970))
    }

    private func meal(at eaten: Date, name: String = "Lunch") -> MealRow {
        MealRow(id: "meal", day: "2027-01-15", eatenAt: Int(eaten.timeIntervalSince1970), name: name,
                origin: .manual, createdAt: 0, updatedAt: 0)
    }

    private func hours(_ h: Double) -> TimeInterval { h * 3600 }

    // MARK: Running fast

    func testAMealDuringARunningFastProposesToEndItAtTheMealTime() {
        let eaten = t0.addingTimeInterval(hours(15.5))
        let now = t0.addingTimeInterval(hours(17))
        let proposal = FastingMealLink.fastingEndProposal(fast: fast(start: t0), meal: meal(at: eaten), kcal: 520, now: now)
        XCTAssertEqual(proposal, FastingMealProposal(kind: .endRunning, fastId: "fast", mealId: "meal", mealName: "Lunch",
                                                     endSec: Int(eaten.timeIntervalSince1970)),
                       "the end is the meal's time, not now: a meal logged late moves the real end back")
    }

    func testAMealDatedInTheFutureCountsAsEatenNow() {
        let now = t0.addingTimeInterval(hours(10))
        let proposal = FastingMealLink.fastingEndProposal(fast: fast(start: t0), meal: meal(at: now.addingTimeInterval(3600)),
                                                          kcal: 300, now: now)
        XCTAssertEqual(proposal?.endSec, Int(now.timeIntervalSince1970))
    }

    func testADrinkWithoutCaloriesAsksNothing() {
        let now = t0.addingTimeInterval(hours(10))
        XCTAssertNil(FastingMealLink.fastingEndProposal(fast: fast(start: t0), meal: meal(at: now, name: "Black coffee"),
                                                        kcal: 0, now: now))
    }

    func testAMealAtOrBeforeTheStartIsTheLastMealNotABreak() {
        let now = t0.addingTimeInterval(hours(10))
        XCTAssertNil(FastingMealLink.fastingEndProposal(fast: fast(start: t0), meal: meal(at: t0), kcal: 600, now: now))
        XCTAssertNil(FastingMealLink.fastingEndProposal(fast: fast(start: t0), meal: meal(at: t0.addingTimeInterval(-600)),
                                                        kcal: 600, now: now))
    }

    // MARK: Fast over

    func testAMealBeforeTheRecordedEndMovesTheEndBack() {
        let end = t0.addingTimeInterval(hours(16))
        let eaten = t0.addingTimeInterval(hours(15.25))
        let now = t0.addingTimeInterval(hours(18))
        let proposal = FastingMealLink.fastingEndProposal(fast: fast(start: t0, end: end), meal: meal(at: eaten), kcal: 400, now: now)
        XCTAssertEqual(proposal?.kind, .moveEndBack)
        XCTAssertEqual(proposal?.endSec, Int(eaten.timeIntervalSince1970))
    }

    func testAMealAfterTheRecordedEndAsksNothing() {
        let end = t0.addingTimeInterval(hours(16))
        let now = t0.addingTimeInterval(hours(18))
        XCTAssertNil(FastingMealLink.fastingEndProposal(fast: fast(start: t0, end: end), meal: meal(at: end), kcal: 400, now: now))
        XCTAssertNil(FastingMealLink.fastingEndProposal(fast: fast(start: t0, end: end),
                                                        meal: meal(at: end.addingTimeInterval(1800)), kcal: 400, now: now))
    }

    // MARK: Still holds

    func testAProposalNoLongerHoldsOnceTheFastChanged() {
        let eaten = t0.addingTimeInterval(hours(15))
        let running = FastingMealProposal(kind: .endRunning, fastId: "fast", mealId: "meal", mealName: "Lunch",
                                          endSec: Int(eaten.timeIntervalSince1970))
        XCTAssertTrue(FastingMealLink.proposalStillHolds(running, for: fast(start: t0)))
        XCTAssertFalse(FastingMealLink.proposalStillHolds(running, for: fast(start: t0, end: t0.addingTimeInterval(hours(16)))),
                       "the fast was stopped meanwhile: nothing to end")
        XCTAssertFalse(FastingMealLink.proposalStillHolds(running, for: fast(start: eaten.addingTimeInterval(60))),
                       "the start moved past the meal")
        let moveBack = FastingMealProposal(kind: .moveEndBack, fastId: "fast", mealId: "meal", mealName: "Lunch",
                                           endSec: Int(eaten.timeIntervalSince1970))
        XCTAssertTrue(FastingMealLink.proposalStillHolds(moveBack, for: fast(start: t0, end: t0.addingTimeInterval(hours(16)))))
        XCTAssertFalse(FastingMealLink.proposalStillHolds(moveBack, for: fast(start: t0, end: eaten)),
                       "the end already is the meal's time")
        XCTAssertFalse(FastingMealLink.proposalStillHolds(moveBack, for: fast(start: t0)), "reopened meanwhile")
    }

    func testTheDismissalMemoNamesTheMealAndTheTime() {
        let proposal = FastingMealProposal(kind: .endRunning, fastId: "fast", mealId: "meal", mealName: "Lunch", endSec: 1234)
        XCTAssertEqual(FastingMealLink.dismissalMemo(proposal), "meal:1234")
    }
}
