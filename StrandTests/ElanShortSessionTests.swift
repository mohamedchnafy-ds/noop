import XCTest
import WhoopStore
@testable import Strand

/// Personal fork, chantier 10 (Élan), PR C: the short session as the app builds it (`ElanShortSession`): the
/// first two blocks of the program, the sets and loads of the last session, the length estimate, and the
/// summary the Training day card shows.
final class ElanShortSessionTests: XCTestCase {

    private func line(_ ord: Int, _ exercise: String, group: String? = nil, sets: Int? = 3, reps: Int? = 8,
                      weight: Double? = nil, rest: Int? = nil) -> LiftProgramItemRow {
        LiftProgramItemRow(id: "i\(ord)", deviceId: "d", programId: "p", ord: ord, exercise: exercise,
                           targetSets: sets, targetRepsLow: reps, targetRepsHigh: reps.map { $0 + 2 }, targetRpe: nil,
                           targetWeightKg: weight, restSec: rest, note: nil, supersetGroup: group)
    }

    private func set(_ exercise: String, reps: Int, kg: Double?, warmup: Bool = false, index: Int = 1) -> LiftSetRow {
        LiftSetRow(id: UUID().uuidString, deviceId: "d", sessionId: "s", ord: index, exercise: exercise,
                   primaryMuscle: nil, secondaryMuscles: [], setIndex: index, weightKg: kg, reps: reps, rpe: nil,
                   isWarmup: warmup, startTs: nil, endTs: nil, restSec: nil, note: nil)
    }

    /// Two supersets, then a line on its own and a third superset: the mockup's program, in a shuffled order.
    private var program: [LiftProgramItemRow] {
        [line(2, "Pull-down", group: "B", reps: 10), line(0, "Romanian deadlift", group: "A", rest: 90),
         line(1, "Incline press", group: "A"), line(3, "Walking lunge", group: "B", reps: 10),
         line(4, "Curl", sets: 4), line(5, "Plank", group: "C"), line(6, "Row", group: "C")]
    }

    func testTheFirstTwoBlocksAreKeptInProgramOrder() {
        let kept = ElanShortSession.elanShortLines(program)
        XCTAssertEqual(kept.map { $0.map(\.exercise) },
                       [["Romanian deadlift", "Incline press"], ["Pull-down", "Walking lunge"]])
        XCTAssertEqual(ElanShortSession.elanShortLines(program, count: 3).count, 3, "the single line is a block too")
        XCTAssertTrue(ElanShortSession.elanShortLines([]).isEmpty)
        XCTAssertEqual(ElanShortSession.elanShortLines([line(0, "Curl")]).count, 1, "a one-block program stays whole")
    }

    func testTargetsComeFromTheLastSessionThenTheProgram() {
        let item = line(0, "Romanian deadlift", reps: 8, weight: 60)
        // Last session: three working sets, the heaviest at 70 kg × 7; a warm-up left out.
        let last = [set("Romanian deadlift", reps: 10, kg: 40, warmup: true, index: 0),
                    set("Romanian deadlift", reps: 8, kg: 65, index: 1),
                    set("Romanian deadlift", reps: 7, kg: 70, index: 2),
                    set("Romanian deadlift", reps: 8, kg: 65, index: 3)]
        let fromLast = ElanShortSession.elanShortTargets(line: item, lastSets: last)
        XCTAssertEqual(fromLast.sets, 3)
        XCTAssertEqual(fromLast.reps, 8, "the program's rep target wins over the last set's 7")
        XCTAssertEqual(fromLast.weightKg, 70)
        // Never logged: the program's own targets.
        let fromProgram = ElanShortSession.elanShortTargets(line: item, lastSets: [])
        XCTAssertEqual(fromProgram.sets, 3)
        XCTAssertEqual(fromProgram.reps, 8)
        XCTAssertEqual(fromProgram.weightKg, 60)
        // Nothing stated and never logged: 3 × 10, no load.
        let bare = ElanShortSession.elanShortTargets(line: line(0, "New", sets: nil, reps: nil), lastSets: [])
        XCTAssertEqual(bare.sets, 3)
        XCTAssertEqual(bare.reps, 10)
        XCTAssertNil(bare.weightKg)
        // Logged without a rep target: the last heaviest set's reps.
        let noTarget = ElanShortSession.elanShortTargets(line: line(0, "Curl", reps: nil), lastSets: [set("Curl", reps: 12, kg: 14)])
        XCTAssertEqual(noTarget.reps, 12)
        XCTAssertEqual(noTarget.sets, 1)
    }

    func testThePlanIsTaggedShapedAndTimed() {
        let plan = ElanShortSession.elanShortPlan(programId: "p", name: "Full body B", items: program, lastSets: { exercise in
            exercise == "Pull-down" ? [set("Pull-down", reps: 10, kg: 55), set("Pull-down", reps: 10, kg: 55),
                                       set("Pull-down", reps: 9, kg: 55)] : []
        })
        guard let plan else { return XCTFail("a program with lines gives a plan") }
        XCTAssertEqual(plan.blocks.count, 2)
        XCTAssertEqual(plan.lines.map(\.tag), ["A1", "A2", "B1", "B2"])
        XCTAssertEqual(plan.blocks.map(\.letter), ["A", "B"])
        XCTAssertEqual(plan.supersets, 2)
        XCTAssertEqual(plan.singles, 0)
        XCTAssertEqual(plan.totalSets, 12)
        XCTAssertEqual(plan.lines[2].weightKg, 55, "the pull-down's load comes from its last session")
        XCTAssertEqual(plan.blocks[0].restSec, 90, "the line's own rest")
        XCTAssertEqual(plan.blocks[1].restSec, ElanShortSession.defaultRestSec, "none stated: 1:30")
        // 12 sets × 45 s + (3 − 1) rounds × 90 s per superset = 540 + 360 = 900 s = 15 min.
        XCTAssertEqual(plan.estimatedMinutes, 15)
        XCTAssertEqual(plan.title, "Full body B · " + String(localized: "short version"))
        XCTAssertNil(ElanShortSession.elanShortPlan(programId: "p", name: "Empty", items: [], lastSets: { _ in [] }))
    }

    func testTheEstimateRoundsUpToFiveMinutes() {
        func block(_ sets: Int, superset: Bool, rest: Int = 90) -> ElanShortBlock {
            let lines = (0..<(superset ? 2 : 1)).map { i in
                ElanShortLine(item: line(i, "E\(i)"), tag: superset ? "A\(i + 1)" : nil, sets: sets, reps: 10, weightKg: nil, restSec: rest)
            }
            return ElanShortBlock(lines: lines)
        }
        // A single line of 3 sets: 135 s + 2 × 90 = 315 s → 10 min (rounded up).
        XCTAssertEqual(ElanShortSession.elanEstimatedMinutes([block(3, superset: false)]), 10)
        // Two supersets of 4 × 2 sets: 16 × 45 + 2 × 3 × 90 = 720 + 540 = 1 260 s = 21 min → 25.
        XCTAssertEqual(ElanShortSession.elanEstimatedMinutes([block(4, superset: true), block(4, superset: true)]), 25)
        XCTAssertEqual(ElanShortSession.elanEstimatedMinutes([]), 0)
    }

    func testTheDayCardSummaryShowsTheShortSession() {
        let plan = ElanShortSession.elanShortPlan(programId: "p", name: "Full body B", items: program, lastSets: { _ in [] })!
        let summary = ElanShortSession.elanProgramSummary(plan)
        XCTAssertEqual(summary.id, "p")
        XCTAssertTrue(summary.elanShort)
        XCTAssertEqual(summary.blocks.map(\.text), ["A1 Romanian deadlift · A2 Incline press", "B1 Pull-down · B2 Walking lunge"])
        XCTAssertEqual(summary.blocks.map(\.sets), [3, 3])
        XCTAssertEqual(summary.blockCount, 2)
        XCTAssertEqual(summary.typicalMinutes, plan.estimatedMinutes)
        XCTAssertTrue(summary.raises.isEmpty, "the short session runs the last loads: nothing to raise")
        XCTAssertEqual(ElanShortSession.elanPlannedLine(plan), "2 supersets · " + String(localized: "≈ \(plan.estimatedMinutes) min"))
    }

    func testTheLineTargetsAreWorded() {
        let withLoad = ElanShortLine(item: line(0, "Squat"), tag: "A1", sets: 3, reps: 8, weightKg: 70, restSec: 90)
        let worded = ElanShortSession.elanLineTargets(withLoad, system: .metric)
        XCTAssertEqual(worded.sets, "3 × 8")
        XCTAssertEqual(worded.load, UnitFormatter.massFromKilograms(70, system: .metric))
        let bare = ElanShortLine(item: line(0, "Plank"), tag: nil, sets: 2, reps: nil, weightKg: nil, restSec: 60)
        XCTAssertEqual(ElanShortSession.elanLineTargets(bare, system: .metric).sets, "2 ×")
        XCTAssertNil(ElanShortSession.elanLineTargets(bare, system: .metric).load)
        XCTAssertEqual(ElanShortSession.elanClock(90), "1:30")
        XCTAssertEqual(ElanShortSession.elanClock(600), "10:00")
    }
}
