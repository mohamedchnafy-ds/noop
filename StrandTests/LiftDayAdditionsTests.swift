import XCTest
@testable import Strand
import WhoopStore

/// Fork chantier 18, lot B2: exercises added to today's program from the Training screen.
final class LiftDayAdditionsTests: XCTestCase {

    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "LiftDayAdditionsTests")
        defaults.removePersistentDomain(forName: "LiftDayAdditionsTests")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "LiftDayAdditionsTests")
        super.tearDown()
    }

    private func addition(_ name: String) -> LiftDayAddition {
        LiftDayAddition(id: name, exercise: name, primaryMuscle: .biceps, secondaryMuscles: [])
    }

    func testAnAdditionIsForItsDayAndItsProgramOnly() {
        LiftDayAdditions.add(addition("Curl"), day: "2026-11-12", programId: "A", defaults: defaults)
        XCTAssertEqual(LiftDayAdditions.additions(day: "2026-11-12", programId: "A", defaults: defaults).map(\.exercise),
                       ["Curl"])
        XCTAssertTrue(LiftDayAdditions.additions(day: "2026-11-12", programId: "B", defaults: defaults).isEmpty)
        XCTAssertTrue(LiftDayAdditions.additions(day: "2026-11-13", programId: "A", defaults: defaults).isEmpty)
    }

    func testAnotherDaysAdditionsAreDroppedOnTheNextWrite() {
        LiftDayAdditions.add(addition("Curl"), day: "2026-11-12", programId: "A", defaults: defaults)
        LiftDayAdditions.add(addition("Dips"), day: "2026-11-13", programId: "A", defaults: defaults)
        XCTAssertTrue(LiftDayAdditions.additions(day: "2026-11-12", programId: "A", defaults: defaults).isEmpty)
        XCTAssertEqual(LiftDayAdditions.additionsByProgram(day: "2026-11-13", defaults: defaults).keys.sorted(), ["A"])
    }

    func testRemovingAndTakingAdditions() {
        LiftDayAdditions.add(addition("Curl"), day: "d", programId: "A", defaults: defaults)
        LiftDayAdditions.add(addition("Dips"), day: "d", programId: "A", defaults: defaults)
        LiftDayAdditions.add(addition("Row"), day: "d", programId: "B", defaults: defaults)
        LiftDayAdditions.remove(id: "Curl", day: "d", programId: "A", defaults: defaults)
        XCTAssertEqual(LiftDayAdditions.takeAdditions(day: "d", programId: "A", defaults: defaults).map(\.exercise),
                       ["Dips"])
        XCTAssertTrue(LiftDayAdditions.additions(day: "d", programId: "A", defaults: defaults).isEmpty,
                      "the session took them")
        XCTAssertEqual(LiftDayAdditions.additions(day: "d", programId: "B", defaults: defaults).count, 1)
    }

    /// Added during the session, so finishing asks whether the program keeps it; last time's set count.
    func testAnAdditionJoinsTheSessionAsAnAddedLine() {
        let row = LiftSetRow(id: "s", deviceId: "d", sessionId: "x", ord: 0, exercise: "Curl",
                             primaryMuscle: .biceps, secondaryMuscles: [], setIndex: 1, weightKg: 12, reps: 10,
                             rpe: nil, isWarmup: false, startTs: nil, endTs: nil, restSec: nil, note: nil)
        var second = row; second.setIndex = 2
        var warmup = row; warmup.isWarmup = true
        let item = LiftDayAdditions.planItem(addition("Curl"), lastSets: [warmup, row, second])
        XCTAssertTrue(item.addedInSession)
        XCTAssertEqual(item.programItemId, "Curl")
        XCTAssertEqual(item.targetSets, 2, "the working sets of last time, warm-ups left out")
        XCTAssertEqual(LiftDayAdditions.planItem(addition("New"), lastSets: []).targetSets,
                       LiftDayAdditions.defaultSets)
    }
}
