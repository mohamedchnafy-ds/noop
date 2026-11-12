import XCTest
@testable import Strand
import WhoopStore

/// Fork chantier 18, lot A: the weight repeats from one set to the next, « Set done » in one tap from the
/// rest, the rest shortened by the card, and the weight step of each exercise.
@MainActor
final class LiftQuickEntryTests: XCTestCase {

    private let t0 = 1_800_000_000

    private func slot(_ e: Int, _ s: Int) -> LiftSlot { LiftSlot(exerciseIndex: e, setIndex: s) }

    /// Two exercises with their own targets, four sets then three.
    private func plan() -> [LiftPlanItem] {
        [LiftPlanItem(exercise: "Bench press", primaryMuscle: .chest, targetSets: 4,
                      restSec: 120, targetRepsLow: 8, targetWeightKg: 60),
         LiftPlanItem(exercise: "Cable row", primaryMuscle: .lats, targetSets: 3,
                      restSec: 90, targetRepsLow: 10, targetWeightKg: 45)]
    }

    private func controller() -> LiftSessionController {
        LiftSessionController(buzz: { _ in }, setStrapHandler: { _ in })
    }

    override func tearDown() {
        LiftSessionPersistence.clear()
        super.tearDown()
    }

    // MARK: - The weight repeats

    /// Last session went 60, 62.5, 65: the weight of set 1 is what every set shows, not a pyramid.
    func testTheWeightOfTheFirstSetRepeatsOnEverySet() {
        let e = LiftSessionEngine(plan: plan(), startTs: t0)
        let last = [1: LiftSetCarry(weightKg: 60, reps: 8), 2: LiftSetCarry(weightKg: 62.5, reps: 8),
                    3: LiftSetCarry(weightKg: 65, reps: 6)]
        for set in 1...4 {
            XCTAssertEqual(e.carry(for: slot(0, set), lastSession: last).weightKg, 60, "set \(set)")
        }
        XCTAssertEqual(e.carry(for: slot(0, 3), lastSession: last).reps, 6, "reps keep last time's set")
    }

    /// A weight given to set 2 becomes the weight of sets 3 and 4; set 1, done, keeps its own.
    func testAWeightChangedOnASetBecomesTheWeightOfTheSetsAfterIt() {
        let c = controller()
        c.start(plan: plan(), programId: nil, programName: nil)
        c.advance()                                   // set 1
        c.advance()                                   // set 1 done, resting
        c.updateSet(slot(0, 2), weightKg: 62.5, reps: nil, rpe: nil, isWarmup: false)

        XCTAssertEqual(c.values(of: slot(0, 1)).weightKg, 60, "a set already done does not move")
        XCTAssertEqual(c.carry(for: slot(0, 3)).weightKg, 62.5)
        XCTAssertEqual(c.carry(for: slot(0, 4)).weightKg, 62.5)
    }

    /// Each exercise has its own chain: the second one starts from its own weight.
    func testANewExerciseTakesNothingFromThePreviousOne() {
        let c = controller()
        c.start(plan: plan(), programId: nil, programName: nil)
        c.updateSet(slot(0, 1), weightKg: 80, reps: nil, rpe: nil, isWarmup: false)
        XCTAssertEqual(c.carry(for: slot(0, 4)).weightKg, 80)
        XCTAssertEqual(c.carry(for: slot(1, 1)).weightKg, 45)
        XCTAssertEqual(c.carry(for: slot(1, 3)).weightKg, 45)
    }

    /// A light warm-up first does not pull the working sets down.
    func testAWarmUpIsLeftOutOfTheChain() {
        let c = controller()
        c.start(plan: plan(), programId: nil, programName: nil)
        c.setWarmup(slot(0, 1), true)
        c.updateSet(slot(0, 1), weightKg: 20, reps: 15, rpe: nil, isWarmup: true)
        XCTAssertEqual(c.carry(for: slot(0, 2)).weightKg, 60, "the plan's weight, not the warm-up's")
    }

    // MARK: - One tap

    /// From the rest, « Set done » records the next set at once with its timing from the rest's end, and
    /// starts the rest after it.
    func testSetDoneFromTheRestRecordsTheNextSet() {
        var e = LiftSessionEngine(plan: plan(), startTs: t0)
        e.advance(now: t0 + 60)                        // set 1
        e.advance(now: t0 + 100)                       // set 1 done; rest until t0 + 220
        XCTAssertEqual(e.quickEntrySlot, slot(0, 2), "the card stands on the set coming up")

        XCTAssertTrue(e.completeQuickSet(now: t0 + 260))
        let set2 = e.recordedSet(for: slot(0, 2))
        XCTAssertEqual(set2?.startTs, t0 + 220, "the set began when the rest ran out")
        XCTAssertEqual(set2?.endTs, t0 + 260)
        XCTAssertEqual(e.recordedSet(for: slot(0, 1))?.restSec, 120)
        XCTAssertEqual(e.stage, .resting(slot(0, 2), endsAt: t0 + 260 + 120))
        XCTAssertEqual(e.quickEntrySlot, slot(0, 3))

        e.undo()
        XCTAssertNil(e.recordedSet(for: slot(0, 2)), "one tap, one undo step")
        XCTAssertEqual(e.stage, .resting(slot(0, 1), endsAt: t0 + 220))
    }

    /// A rest cut short: the set claims no time before the tap.
    func testSetDoneDuringTheRestStartsTheSetNow() {
        var e = LiftSessionEngine(plan: plan(), startTs: t0)
        e.advance(now: t0 + 60)
        e.advance(now: t0 + 100)
        XCTAssertTrue(e.completeQuickSet(now: t0 + 150))
        XCTAssertEqual(e.recordedSet(for: slot(0, 2))?.startTs, t0 + 150)
        XCTAssertEqual(e.recordedSet(for: slot(0, 1))?.restSec, 50)
    }

    /// Nothing to do from the warm-up (the card starts the first set) or once everything is done.
    func testSetDoneDoesNothingWithoutASetToRecord() {
        var e = LiftSessionEngine(plan: [LiftPlanItem(exercise: "Curl", targetSets: 1)], startTs: t0)
        XCTAssertFalse(e.completeQuickSet(now: t0))
        e.advance(now: t0 + 10)
        XCTAssertTrue(e.completeQuickSet(now: t0 + 40))
        XCTAssertNil(e.quickEntrySlot)
        XCTAssertFalse(e.completeQuickSet(now: t0 + 50))
    }

    /// What the card shows is what the set records: a weight given before the tap lands in the set.
    func testTheControllerAppliesWhatTheCardHeld() {
        let c = controller()
        c.start(plan: plan(), programId: nil, programName: nil)
        c.completeQuickSet()                          // warm-up: starts set 1
        XCTAssertEqual(c.engine?.stage, .working(slot(0, 1)))
        c.updateSet(slot(0, 1), weightKg: 62.5, reps: 7, rpe: nil, isWarmup: false)
        c.completeQuickSet()
        XCTAssertEqual(c.engine?.recordedSet(for: slot(0, 1))?.weightKg, 62.5)
        XCTAssertEqual(c.engine?.recordedSet(for: slot(0, 1))?.reps, 7)
        XCTAssertTrue(c.pendingValues.isEmpty)
    }

    // MARK: - The rest

    func testTheRestIsShortenedButNeverPastNow() {
        var e = LiftSessionEngine(plan: plan(), startTs: t0)
        e.advance(now: t0)
        e.advance(now: t0 + 40)                        // rest until t0 + 160
        XCTAssertTrue(e.shortenRest(by: 15, now: t0 + 50))
        XCTAssertEqual(e.restRemaining(now: t0 + 50), 95)
        XCTAssertTrue(e.shortenRest(by: 300, now: t0 + 50))
        XCTAssertEqual(e.restRemaining(now: t0 + 50), 0)
        XCTAssertFalse(e.shortenRest(by: 15, now: t0 + 50), "a rest already over has nothing to cut")
    }

    // MARK: - The weight step

    func testTheStepIsGuessedFromTheName() {
        XCTAssertEqual(LiftWeightStep.guessedStep(for: "Développé couché"), 2.5)
        XCTAssertEqual(LiftWeightStep.guessedStep(for: "Curl haltères"), 1)
        XCTAssertEqual(LiftWeightStep.guessedStep(for: "Dumbbell press"), 1)
        XCTAssertEqual(LiftWeightStep.guessedStep(for: "Tirage poitrine"), 5)
        XCTAssertEqual(LiftWeightStep.guessedStep(for: "Leg press"), 5)
    }

    func testTheChosenStepIsKeptPerExercise() {
        let defaults = UserDefaults(suiteName: "LiftQuickEntryTests")!
        defaults.removePersistentDomain(forName: "LiftQuickEntryTests")
        LiftWeightStep.setStep(2, for: "Curl haltères", defaults: defaults)
        XCTAssertEqual(LiftWeightStep.step(for: "Curl haltères", defaults: defaults), 2)
        XCTAssertEqual(LiftWeightStep.step(for: "Développé couché", defaults: defaults), 2.5)
        XCTAssertEqual(LiftWeightStep.nextStep(after: 5), 1, "the button cycles back to the first step")
        defaults.removePersistentDomain(forName: "LiftQuickEntryTests")
    }

    func testMinusAndPlusLandOnTheStepsGrid() {
        XCTAssertEqual(LiftWeightStep.moved(60, by: 1, step: 2.5), 62.5)
        XCTAssertEqual(LiftWeightStep.moved(61, by: 1, step: 2.5), 62.5)
        XCTAssertEqual(LiftWeightStep.moved(61, by: -1, step: 2.5), 60)
        XCTAssertEqual(LiftWeightStep.moved(1, by: -1, step: 2.5), 0, "never below zero")
        XCTAssertEqual(LiftWeightStep.wheelValues(step: 5, current: 62.5, maxKg: 70),
                       [0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60, 62.5, 65, 70])
    }
}
