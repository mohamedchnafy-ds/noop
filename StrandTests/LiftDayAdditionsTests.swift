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

    // MARK: Program lines left out for today (the day card's list of every exercise)

    private func line(_ ord: Int, _ exercise: String, group: String? = nil, sets: Int = 3) -> LiftProgramItemRow {
        LiftProgramItemRow(id: "l\(ord)", deviceId: "d", programId: "A", ord: ord, exercise: exercise,
                           targetSets: sets, targetRepsLow: 8, targetRepsHigh: 10, targetRpe: nil,
                           targetWeightKg: 40, restSec: 90, note: nil, supersetGroup: group)
    }

    func testALineLeftOutIsForItsDayAndProgramAndCanBePutBack() {
        LiftDayAdditions.setLineLeftOut("l1", left: true, day: "d", programId: "A", defaults: defaults)
        XCTAssertEqual(LiftDayAdditions.removedLineIds(day: "d", programId: "A", defaults: defaults), ["l1"])
        XCTAssertTrue(LiftDayAdditions.removedLineIds(day: "d", programId: "B", defaults: defaults).isEmpty)
        XCTAssertTrue(LiftDayAdditions.removedLineIds(day: "e", programId: "A", defaults: defaults).isEmpty)
        LiftDayAdditions.setLineLeftOut("l1", left: false, day: "d", programId: "A", defaults: defaults)
        XCTAssertTrue(LiftDayAdditions.removedLinesByProgram(day: "d", defaults: defaults).isEmpty)
        XCTAssertNil(defaults.data(forKey: LiftDayAdditions.defaultsKey), "nothing left to keep")
    }

    func testAdditionsAndLinesLeftOutLiveTogetherAndAreTakenTogether() {
        LiftDayAdditions.setLineLeftOut("l0", left: true, day: "d", programId: "A", defaults: defaults)
        LiftDayAdditions.add(addition("Curl"), day: "d", programId: "A", defaults: defaults)
        XCTAssertEqual(LiftDayAdditions.removedLineIds(day: "d", programId: "A", defaults: defaults), ["l0"],
                       "an addition keeps the lines left out")
        LiftDayAdditions.remove(id: "Curl", day: "d", programId: "A", defaults: defaults)
        XCTAssertEqual(LiftDayAdditions.removedLineIds(day: "d", programId: "A", defaults: defaults), ["l0"])
        XCTAssertTrue(LiftDayAdditions.takeAdditions(day: "d", programId: "A", defaults: defaults).isEmpty)
        XCTAssertTrue(LiftDayAdditions.removedLineIds(day: "d", programId: "A", defaults: defaults).isEmpty,
                      "the session took the day's list, lines left out included")
    }

    func testTheStartNeverRunsAnEmptyProgram() {
        let items = [line(0, "Squat"), line(1, "Row")]
        XCTAssertEqual(LiftDayAdditions.keptProgramLines(items, removed: ["l0"]).map(\.exercise), ["Row"])
        XCTAssertEqual(LiftDayAdditions.keptProgramLines(items, removed: ["l0", "l1"]).map(\.exercise),
                       ["Squat", "Row"], "nothing would be left: every line is kept")
    }

    func testTheDayCardReadsTheProgramAsTodaysSessionWillRunIt() {
        let items = [line(0, "Squat", group: "A"), line(1, "Row", group: "A"),
                     line(2, "Bench", group: "B"), line(3, "Lunge", group: "B"), line(4, "Curl", sets: 2)]
        var summary = TrainingDays.programSummary(id: "A", name: "Full body", items: items,
                                                  finished: [(startTs: 0, endTs: 3_000)])
        summary.raises = [TrainingRaise(exercise: "Row", fromKg: 40, toKg: 42.5),
                          TrainingRaise(exercise: "Bench", fromKg: 40, toKg: 42.5)]
        XCTAssertEqual(summary.items.map(\.id), ["l0", "l1", "l2", "l3", "l4"])

        let day = TrainingDays.dayProgramSummary(summary, leftOut: ["l1"])
        XCTAssertEqual(day.supersets, 1, "A2 left out: A1 is done alone")
        XCTAssertEqual(day.singles, 2)
        XCTAssertEqual(day.totalSets, 11)
        XCTAssertEqual(day.blocks.map(\.text), ["Squat", "A1 Bench · A2 Lunge"])
        XCTAssertEqual(day.blockCount, 3)
        XCTAssertEqual(day.raises.map(\.exercise), ["Bench"], "no raise for a line left out")
        XCTAssertEqual(day.typicalMinutes, summary.typicalMinutes)
        XCTAssertEqual(day.items, summary.items, "every line stays listed, so one can be put back")
        XCTAssertEqual(TrainingDays.dayProgramSummary(summary, leftOut: []), summary)

        let lines = TrainingDays.dayProgramLines(items, leftOut: ["l1"])
        XCTAssertEqual(lines.map(\.tag), [nil, nil, "A1", "A2", nil])
        XCTAssertEqual(lines.map(\.leftOut), [false, true, false, false, false])
    }

    func testTheListToggleSaysWhatIsHiddenAndLeftOut() {
        XCTAssertEqual(TrainingText.allLinesToggle(more: 0, leftOut: 0), String(localized: "All exercises"))
        XCTAssertEqual(TrainingText.allLinesToggle(more: 2, leftOut: 1),
                       String(localized: "+ \(2) more") + " · " + String(localized: "1 left out today"))
    }

    // MARK: A superset added for today (« Superset » in the sheet)

    func testASupersetAddedForTodayIsOneLinkedBlock() {
        XCTAssertFalse(LiftDayAdditions.addSuperset([addition("Curl")], day: "d", programId: "A", defaults: defaults),
                       "a superset takes two exercises or more")
        LiftDayAdditions.add(addition("Dips"), day: "d", programId: "A", defaults: defaults)
        XCTAssertTrue(LiftDayAdditions.addSuperset([addition("Curl"), addition("Extension")], day: "d",
                                                   programId: "A", defaults: defaults))
        XCTAssertTrue(LiftDayAdditions.addSuperset([addition("Fly"), addition("Raise")], day: "d",
                                                   programId: "A", defaults: defaults))
        let lines = LiftDayAdditions.additions(day: "d", programId: "A", defaults: defaults)
        XCTAssertNil(lines[0].group)
        XCTAssertEqual(lines[1].group, lines[2].group)
        XCTAssertNotNil(lines[1].group)
        XCTAssertNotEqual(lines[3].group, lines[1].group, "two supersets never share a label")
        XCTAssertEqual(LiftDayAdditions.additionBlocks(lines).map { $0.map(\.exercise) },
                       [["Dips"], ["Curl", "Extension"], ["Fly", "Raise"]])
    }

    func testASupersetJoinsTheSessionLinkedAndRelettered() {
        LiftDayAdditions.addSuperset([addition("Curl"), addition("Extension")], day: "d", programId: "A",
                                     defaults: defaults)
        let added = LiftDayAdditions.additions(day: "d", programId: "A", defaults: defaults)
            .map { LiftDayAdditions.planItem($0, lastSets: []) }
        XCTAssertEqual(added.map(\.restSec), [LiftProgramBlocks.supersetRestSec, LiftProgramBlocks.supersetRestSec])
        let program = [LiftPlanItem(exercise: "Squat", supersetGroup: "A"), LiftPlanItem(exercise: "Row", supersetGroup: "A"),
                       LiftPlanItem(exercise: "Plank")]
        let plan = LiftDayAdditions.joinedPlan(program, added)
        XCTAssertEqual(plan.map(\.supersetGroup), ["A", "A", nil, "B", "B"])
        XCTAssertEqual(LiftSuperset.blocks(plan.map(\.supersetGroup)).count, 3)
    }

    /// Kept at the finish, a superset added for today stays one in the program, after its own supersets.
    func testAKeptSupersetStaysLinkedInTheProgram() {
        let program = [line(0, "Squat", group: "A"), line(1, "Row", group: "A")]
        var curl = LiftPlanItem(exercise: "Curl", targetSets: 3, restSec: 90, programItemId: "c", addedInSession: true,
                                supersetGroup: "A")
        var dips = curl
        dips.exercise = "Dips"
        dips.programItemId = "x"
        // Relettered at the start with the program's Row left out: the added superset reads « A » too.
        curl.supersetGroup = "A"
        dips.supersetGroup = "A"
        let plan = [LiftPlanItem(exercise: "Squat", programItemId: "l0"), curl, dips]
        let after = LiftSessionController.programAfterSession([], plan: plan, program: program, keepingChanges: true,
                                                              programId: "A", deviceId: "d")
        XCTAssertEqual(after.map(\.exercise), ["Squat", "Row", "Curl", "Dips"])
        XCTAssertEqual(after.map(\.supersetGroup), ["A", "A", "B", "B"], "not merged with the program's A")
        XCTAssertEqual(after[3].restSec, 90)
    }
}
