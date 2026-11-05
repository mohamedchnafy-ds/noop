import XCTest
import WhoopStore
@testable import Strand

/// Pins the record rule of the Lift Log (personal fork, chantier 12): a heavier load than ever, or more
/// reps at a load already done; never on the first session of an exercise; warm-ups never count.
final class LiftRecordsTests: XCTestCase {

    private func set(_ exercise: String, _ kg: Double?, _ reps: Int?, warmup: Bool = false) -> LiftSetRow {
        LiftSetRow(id: UUID().uuidString, deviceId: "d", sessionId: "s", ord: 0, exercise: exercise,
                   primaryMuscle: nil, setIndex: 1, weightKg: kg, reps: reps, rpe: nil, isWarmup: warmup,
                   startTs: nil, endTs: nil, restSec: nil, note: nil)
    }

    private var book: LiftRecordBook {
        LiftRecordBook.liftRecordBook(from: [
            set("Squat", 100, 5), set("Squat", 90, 8), set("Squat", 100, 3),
            set("Squat", 140, 1, warmup: true),
            set("Bench", nil, 10), set("Bench", 60, 0),
        ])
    }

    func testAHeavierLoadIsARecord() {
        XCTAssertTrue(book.liftRecordCheck(exercise: "Squat", weightKg: 102.5, reps: 1))
    }

    func testMoreRepsAtALoadAlreadyDoneIsARecord() {
        XCTAssertTrue(book.liftRecordCheck(exercise: "Squat", weightKg: 90, reps: 9))
        XCTAssertTrue(book.liftRecordCheck(exercise: "Squat", weightKg: 100.0, reps: 6))
    }

    func testEqualOrFewerRepsAtALoadIsNot() {
        XCTAssertFalse(book.liftRecordCheck(exercise: "Squat", weightKg: 100, reps: 5))
        XCTAssertFalse(book.liftRecordCheck(exercise: "Squat", weightKg: 90, reps: 7))
    }

    func testANewLoadBelowTheTopIsNot() {
        XCTAssertFalse(book.liftRecordCheck(exercise: "Squat", weightKg: 95, reps: 20))
    }

    func testTheFirstSessionOfAnExerciseIsNever() {
        XCTAssertFalse(book.liftRecordCheck(exercise: "Deadlift", weightKg: 200, reps: 5))
        // Only sets without a load or reps were done on the bench: nothing to beat yet.
        XCTAssertFalse(book.liftRecordCheck(exercise: "Bench", weightKg: 60, reps: 10))
    }

    func testWarmUpsNeverCountNorBeat() {
        // The 140 kg warm-up is not the top load …
        XCTAssertTrue(book.liftRecordCheck(exercise: "Squat", weightKg: 105, reps: 1))
        // … and a warm-up set is never a record itself.
        XCTAssertFalse(book.liftRecordCheck(exercise: "Squat", weightKg: 150, reps: 1, isWarmup: true))
    }

    func testASetWithoutNumbersIsNot() {
        XCTAssertFalse(book.liftRecordCheck(exercise: "Squat", weightKg: nil, reps: 12))
        XCTAssertFalse(book.liftRecordCheck(exercise: "Squat", weightKg: 120, reps: nil))
    }
}
