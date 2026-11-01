import XCTest
@testable import Strand
import WhoopStore

/// The session card (personal fork, step 6b): how `create_program` is read and bounded, how the card
/// lays out supersets, the text written out for the model and for sharing, and the Lift Log lines.
final class CoachSessionProposalTests: XCTestCase {

    private func parse(_ json: String) -> CoachSessionProposal? {
        CoachSessionProposal.fromToolInput(CoachTools.input(fromJSON: json))
    }

    private var upperBody: CoachSessionProposal {
        parse(#"""
        {"name": "Haut du corps · genou épargné", "estimated_minutes": 45, "lines": [
          {"exercise": "Développé couché barre", "sets": 4, "reps_low": 6, "weight_kg": 60, "rest_sec": 150},
          {"exercise": "Rowing poulie basse", "sets": 3, "reps_low": 10, "weight_kg": 55, "superset": "A1"},
          {"exercise": "Développé militaire", "sets": 3, "reps_low": 10, "weight_kg": 16, "superset": "A2", "rest_sec": 120},
          {"exercise": "Curl incliné", "sets": 3, "reps_low": 12, "weight_kg": 10, "superset": "B"},
          {"exercise": "Extension triceps", "sets": 3, "reps_low": 12, "weight_kg": 25, "superset": "B", "rest_sec": 90},
          {"exercise": "Crunch poulie", "sets": 3, "reps_low": 15, "weight_kg": 30, "rest_sec": 60}
        ]}
        """#)!
    }

    // MARK: Reading the tool

    func testTheMockupSessionLaysOutAsTwoSinglesAndTwoSupersets() {
        let session = upperBody
        XCTAssertEqual(session.minutes, 45)
        XCTAssertEqual(session.blocks, [.single(0), .superset(label: "A", lines: 1..<3),
                                        .superset(label: "B", lines: 3..<5), .single(5)])
        let counts = session.counts
        XCTAssertEqual(counts.singles, 2)
        XCTAssertEqual(counts.supersets, 2)
        XCTAssertEqual(counts.sets, 19)
        XCTAssertEqual(session.position(of: 2), "A2")
        XCTAssertNil(session.position(of: 0))
    }

    func testInputsAreBounded() throws {
        let session = try XCTUnwrap(parse(#"""
        {"name": "  ", "estimated_minutes": 1000, "lines": [
          {"exercise": "Squat", "sets": 40, "reps_low": 12, "reps_high": 8, "weight_kg": 82.4, "rest_sec": 9000},
          {"exercise": "Pompes", "sets": "2", "reps_high": 15, "weight_kg": 0},
          {"exercise": "   ", "sets": 3},
          {"sets": 3}
        ]}
        """#))
        XCTAssertEqual(session.name, String(localized: "Coach session"))
        XCTAssertEqual(session.minutes, CoachSessionProposal.minuteRange.upperBound)
        XCTAssertEqual(session.lines.count, 2, "lines without an exercise are left out")
        let squat = session.lines[0]
        XCTAssertEqual(squat.sets, CoachSessionProposal.setRange.upperBound)
        XCTAssertEqual(squat.repsLow, 8)
        XCTAssertEqual(squat.repsHigh, 12)
        XCTAssertEqual(squat.weightKg, 82.5, "weights round to a quarter kilo")
        XCTAssertEqual(squat.restSec, CoachSessionProposal.restRange.upperBound)
        let pushUps = session.lines[1]
        XCTAssertEqual(pushUps.sets, 2)
        XCTAssertEqual(pushUps.repsLow, 15, "a lone top of range is the target")
        XCTAssertNil(pushUps.repsHigh)
        XCTAssertNil(pushUps.weightKg, "no weight for a bodyweight line")
        XCTAssertNil(pushUps.restSec)
    }

    func testARangeOfOneRepIsASingleTarget() throws {
        let line = try XCTUnwrap(parse(#"{"name": "x", "lines": [{"exercise": "Squat", "sets": 3, "reps_low": 8, "reps_high": 8}]}"#)?.lines.first)
        XCTAssertEqual(line.repsLow, 8)
        XCTAssertNil(line.repsHigh)
    }

    func testASessionWithoutAnyExerciseIsRefused() {
        XCTAssertNil(parse(#"{"name": "Empty", "lines": []}"#))
        XCTAssertNil(parse(#"{"name": "Empty"}"#))
    }

    func testAtMostTwentyLines() throws {
        let lines = (1...30).map { #"{"exercise": "E\#($0)", "sets": 3}"# }.joined(separator: ",")
        let session = try XCTUnwrap(parse(#"{"name": "Long", "lines": [\#(lines)]}"#))
        XCTAssertEqual(session.lines.count, CoachSessionProposal.maxLines)
    }

    // MARK: Text

    func testTheTextForTheModelUsesTheCoachFormat() {
        let text = upperBody.wireText(system: .metric)
        let expected = """
        [Session shown to the user as a card]
        **Haut du corps · genou épargné** · ≈ 45 min
        Développé couché barre — 4 × 6 · 60 kg
        rest 2:30
        A1 Rowing poulie basse — 3 × 10 · 55 kg
        A2 Développé militaire — 3 × 10 · 16 kg
        rest 2:00 after A2
        B1 Curl incliné — 3 × 12 · 10 kg
        B2 Extension triceps — 3 × 12 · 25 kg
        rest 1:30 after B2
        Crunch poulie — 3 × 15 · 30 kg
        rest 1:00
        """
        XCTAssertEqual(text, expected)
    }

    func testAnAddedSessionSaysSoToTheModel() {
        var session = upperBody
        session.programId = "p"
        XCTAssertTrue(session.wireText(system: .metric).hasPrefix("[Session shown to the user as a card, added to their Lift Log]"))
    }

    // MARK: Lift Log

    func testProgramLinesKeepTheOrderTheSupersetsAndTheLiftLogNames() {
        let items = upperBody.programItems(programId: "p", deviceId: "d") {
            CoachSessionProposal.liftLogName($0, known: ["Developpe couche barre", "Curl incliné"])
        }
        XCTAssertEqual(items.map(\.ord), Array(0..<6))
        XCTAssertEqual(items[0].exercise, "Developpe couche barre", "the Lift Log's spelling wins")
        XCTAssertEqual(items[1].exercise, "Rowing poulie basse")
        XCTAssertEqual(items.map(\.supersetGroup), [nil, "A", "A", "B", "B", nil])
        XCTAssertEqual(items[2].restSec, 120)
        XCTAssertEqual(items[0].targetWeightKg, 60)
        XCTAssertEqual(items[0].targetRepsLow, 6)
        XCTAssertNil(items[0].targetRepsHigh)
        XCTAssertTrue(items.allSatisfy { $0.programId == "p" && $0.deviceId == "d" })
        XCTAssertEqual(LiftSuperset.groups(items.map(\.supersetGroup)), [1..<3, 3..<5])
    }

    // MARK: Stored with the reply

    func testTheCardTravelsWithTheReplyAndIsWrittenOutForTheModel() throws {
        let stored = CoachReplyMeta.join(body: "Sans jambes, avec tes charges du Carnet :",
                                         meta: CoachReplyMeta(consulted: [], session: upperBody))
        let split = CoachReplyMeta.split(stored)
        XCTAssertEqual(split.body, "Sans jambes, avec tes charges du Carnet :")
        XCTAssertEqual(split.meta?.session, upperBody)
        let forModel = CoachReplyMeta.forModel(stored, system: .metric)
        XCTAssertTrue(forModel.hasPrefix("Sans jambes, avec tes charges du Carnet :\n\n[Session shown"))
        XCTAssertFalse(forModel.contains("noop-coach"))
    }

    func testABlockWrittenBeforeSessionsStillReads() {
        let old = "Answer." + CoachReplyMeta.fenceOpen + #"{"consulted":["HRV since 3 Sept"]}"# + CoachReplyMeta.fenceClose
        XCTAssertEqual(CoachReplyMeta.split(old).meta, CoachReplyMeta(consulted: ["HRV since 3 Sept"]))
        let onlySession = "x" + CoachReplyMeta.fenceOpen + #"{"session":{"name":"S","lines":[{"exercise":"Squat","sets":3}]}}"#
            + CoachReplyMeta.fenceClose
        XCTAssertEqual(CoachReplyMeta.split(onlySession).meta?.session?.lines.first?.exercise, "Squat")
        XCTAssertEqual(CoachReplyMeta.split(onlySession).meta?.consulted, [])
    }
}
