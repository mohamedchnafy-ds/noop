import XCTest
@testable import Strand
import WhoopStore

/// The Lift Log as the Coach reads it (personal fork): what reaches the prompt, and what never does.
final class CoachLiftContextTests: XCTestCase {

    private let day = 86_400
    private let now = 1_761_900_000   // 2025-10-31

    private func set(_ session: String, _ ord: Int, _ exercise: String, _ muscle: LiftMuscle?,
                     kg: Double?, reps: Int?, rpe: Double? = nil, warmup: Bool = false,
                     secondary: [LiftMuscle] = []) -> LiftSetRow {
        LiftSetRow(id: "\(session)-\(ord)", deviceId: "d", sessionId: session, ord: ord, exercise: exercise,
                   primaryMuscle: muscle, secondaryMuscles: secondary, setIndex: ord + 1,
                   weightKg: kg, reps: reps, rpe: rpe, isWarmup: warmup,
                   startTs: nil, endTs: nil, restSec: nil, note: nil)
    }

    private func session(_ id: String, daysAgo: Int, program: String? = "p1", name: String? = "Superset A",
                         sets: [LiftSetRow]) -> CoachLiftContext.Session {
        let start = now - daysAgo * day
        return .init(row: LiftSessionRow(id: id, deviceId: "d", startTs: start, endTs: start + 52 * 60,
                                         sport: "Strength Training", programId: program, programName: name,
                                         sessionRpe: 7, note: nil),
                     sets: sets)
    }

    private func program(_ id: String, _ name: String, _ items: [LiftProgramItemRow]) -> CoachLiftContext.Program {
        .init(row: LiftProgramRow(id: id, deviceId: "d", name: name, note: nil, createdAt: 0, updatedAt: 0,
                                  archived: false),
              items: items)
    }

    private func item(_ id: String, _ ord: Int, _ exercise: String, sets: Int, reps: Int, kg: Double,
                      rest: Int?, group: String? = nil) -> LiftProgramItemRow {
        LiftProgramItemRow(id: id, deviceId: "d", programId: "p", ord: ord, exercise: exercise,
                           targetSets: sets, targetRepsLow: reps, targetRepsHigh: nil, targetRpe: 8,
                           targetWeightKg: kg, restSec: rest, note: nil, supersetGroup: group)
    }

    func testNothingLoggedMeansNoBlockAtAll() {
        XCTAssertEqual(CoachLiftContext.summary(sessions: [], programs: [], now: now), "")
    }

    func testASessionIsSummarisedSetBySetWithoutWarmUpsOrDiscardedSets() {
        let s = session("s1", daysAgo: 1, sets: [
            set("s1", 0, "Curl", .biceps, kg: 6, reps: 12, warmup: true),
            set("s1", 1, "Curl", .biceps, kg: 12, reps: 10, rpe: 8),
            set("s1", 2, "Extension", .triceps, kg: 20, reps: 12, rpe: 7),
            set("s1", 3, "Curl", .biceps, kg: 12, reps: 9, rpe: 9),
            set("s1", 4, "Extension", .triceps, kg: 0, reps: 0),          // discarded at finish
        ])
        let text = CoachLiftContext.summary(sessions: [s], programs: [], now: now)
        XCTAssertTrue(text.hasPrefix("LIFT LOG"))
        XCTAssertTrue(text.contains("Superset A, 52 min, session RPE 7:"), text)
        XCTAssertTrue(text.contains("Curl (biceps): 12×10, 12×9 · RPE 8.5 · e1RM 16"), text)
        XCTAssertTrue(text.contains("Extension (triceps): 20×12 · RPE 7 · e1RM 28"), text)
        XCTAssertFalse(text.contains("6×12"), "a warm-up is not a working set")
        XCTAssertFalse(text.contains("0×0"), "a discarded set is not a set")
    }

    func testWeeklySetsPerMuscleCountOnlyTheLastSevenDays() {
        let recent = session("s1", daysAgo: 2, sets: [
            set("s1", 0, "Bench", .chest, kg: 60, reps: 8, secondary: [.triceps]),
            set("s1", 1, "Bench", .chest, kg: 60, reps: 8, secondary: [.triceps]),
        ])
        let old = session("s0", daysAgo: 10, sets: [set("s0", 0, "Squat", .quads, kg: 100, reps: 5)])
        let text = CoachLiftContext.summary(sessions: [recent, old], programs: [], now: now)
        XCTAssertTrue(text.contains("chest 2, triceps 1"), text)
        XCTAssertFalse(text.contains("quads 1"), "ten days ago is not this week")
    }

    func testProgressionComparesTheSameExerciseAcrossSessionsOldestFirst() {
        let a = session("a", daysAgo: 9, sets: [set("a", 0, "Curl", .biceps, kg: 10, reps: 10)])
        let b = session("b", daysAgo: 2, sets: [set("b", 0, "Curl", .biceps, kg: 12, reps: 10)])
        let text = CoachLiftContext.summary(sessions: [b, a], programs: [], now: now)
        // Epley: 10 × (1 + 10/30) = 13.3, 12 × (1 + 10/30) = 16
        XCTAssertTrue(text.contains("Curl: 13.3 → 16 (+20%)"), text)
    }

    func testProgramsCarryTheirTargetsSupersetTagsAndTheLikelyNextDay() {
        let done = session("s", daysAgo: 1, program: "pa", name: "Superset A",
                           sets: [set("s", 0, "Curl", .biceps, kg: 12, reps: 10)])
        let a = program("pa", "Superset A", [
            item("1", 0, "Curl", sets: 3, reps: 10, kg: 12, rest: 0, group: "A"),
            item("2", 1, "Extension", sets: 3, reps: 12, kg: 20, rest: 125, group: "A"),
        ])
        let b = program("pb", "Superset B", [item("3", 0, "Bench", sets: 3, reps: 8, kg: 60, rest: 120)])
        let text = CoachLiftContext.summary(sessions: [done], programs: [a, b], now: now)
        XCTAssertTrue(text.contains("Superset A (last done "), text)
        XCTAssertTrue(text.contains("A1 Curl: 3×10 @ 12, max RPE 8, no rest, straight to the next exercise"), text)
        XCTAssertTrue(text.contains("A2 Extension: 3×12 @ 20, max RPE 8, rest 125 after the round"), text)
        XCTAssertTrue(text.contains("Superset B (not done recently):"), text)
        XCTAssertTrue(text.contains("Bench: 3×8 @ 60, max RPE 8, rest 120"), text)
        XCTAssertTrue(text.contains("Likely next in the rotation (done least recently): Superset B"), text)
    }

    func testImperialUsersReadPounds() {
        let s = session("s1", daysAgo: 1, sets: [set("s1", 0, "Curl", .biceps, kg: 10, reps: 10)])
        let text = CoachLiftContext.summary(sessions: [s], programs: [], now: now, system: .imperial)
        XCTAssertTrue(text.contains("22×10"), text)
    }

    func testMuscleNamesAreReadableTokens() {
        XCTAssertEqual(CoachLiftContext.muscleName(.frontDelts), "front delts")
        XCTAssertEqual(CoachLiftContext.muscleName(.chest), "chest")
    }
}
