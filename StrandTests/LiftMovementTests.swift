import XCTest
import CoreGraphics
@testable import Strand
import WhoopStore

/// Fork chantier 21: the execution figure — the movement an exercise's name reads as, the user's own
/// choice over it, and a figure whose segments keep their length through every frame.
final class LiftMovementTests: XCTestCase {

    // MARK: - Recognising a movement from the name

    func testFrenchAndEnglishNamesAreRecognised() {
        let cases: [(String, LiftMovement?)] = [
            ("Squat barre", .squat),
            ("Front squat", .squat),
            ("Goblet squat", .squat),
            ("Squat bulgare", .lunge),
            ("Fentes haltères", .lunge),
            ("Soulevé de terre", .deadlift),
            ("SDT", .deadlift),
            ("Soulevé de terre roumain", .romanianDeadlift),
            ("RDL", .romanianDeadlift),
            ("Développé couché", .benchPress),
            ("Bench press", .benchPress),
            ("Développé haltères incliné", .inclinePress),
            ("Développé militaire", .overheadPress),
            ("OHP", .overheadPress),
            ("Rowing barre", .row),
            ("Barbell row", .row),
            ("Tirage vertical", .latPulldown),
            ("Lat pulldown", .latPulldown),
            ("Tractions", .pullUp),
            ("Pull-up", .pullUp),
            ("Dips", .dips),
            ("Pompes", .pushUp),
            ("Curl haltères", .curl),
            ("Curl marteau", .curl),
            ("Extension triceps poulie", .tricepsPushdown),
            ("Hip thrust", .hipThrust),
            ("Élévations latérales", .lateralRaise),
            ("Leg extension", .legExtension),
            ("Leg curl", .legCurl),
            ("Curl ischios", .legCurl),
            ("Mollets debout", .calfRaise),
            ("Crunch", .crunch),
            ("Gainage", .plank),
            ("Presse à cuisses", nil),
            ("Écarté poulie", nil),
            ("Extension lombaire", nil),
            ("Arrow", nil),
            ("", nil)
        ]
        for (name, expected) in cases {
            XCTAssertEqual(LiftMovement.recognize(exerciseName: name), expected, name)
        }
    }

    func testFoldedNameIsLowercaseWithoutAccentsAndPunctuation() {
        XCTAssertEqual(LiftMovement.foldedExerciseName("Élévations  LATÉRALES (haltères)"),
                       " elevations laterales halteres")
    }

    // MARK: - The user's choice

    func testAChoiceOverridesTheNameAndChoosingTheRecognisedOneClearsIt() {
        var raw = ""
        XCTAssertEqual(LiftMovementChoice.resolveMovement(exercise: "Squat barre", choices: raw).movement, .squat)
        XCTAssertFalse(LiftMovementChoice.resolveMovement(exercise: "Squat barre", choices: raw).chosen)

        raw = LiftMovementChoice.choosingMovement(.lunge, for: "Squat barre", in: raw)
        let picked = LiftMovementChoice.resolveMovement(exercise: "Squat barre", choices: raw)
        XCTAssertEqual(picked.movement, .lunge)
        XCTAssertTrue(picked.chosen)

        raw = LiftMovementChoice.choosingMovement(.squat, for: "Squat barre", in: raw)
        XCTAssertEqual(raw, "")
        XCTAssertFalse(LiftMovementChoice.resolveMovement(exercise: "Squat barre", choices: raw).chosen)
    }

    func testAnUnknownNameHasNoMovementUntilOneIsChosen() {
        var raw = ""
        XCTAssertNil(LiftMovementChoice.resolveMovement(exercise: "Presse à cuisses", choices: raw).movement)
        raw = LiftMovementChoice.choosingMovement(.squat, for: "Presse à cuisses", in: raw)
        XCTAssertEqual(LiftMovementChoice.resolveMovement(exercise: "Presse à cuisses", choices: raw).movement, .squat)
        // Other exercises keep their own reading.
        XCTAssertEqual(LiftMovementChoice.resolveMovement(exercise: "Curl haltères", choices: raw).movement, .curl)
    }

    func testUnreadableStorageMeansNoChoice() {
        XCTAssertEqual(LiftMovementChoice.decodeChoices("not json"), [:])
        XCTAssertEqual(LiftMovementChoice.decodeChoices(#"{"Curl":"nope"}"#), ["Curl": "nope"])
        XCTAssertEqual(LiftMovementChoice.resolveMovement(exercise: "Curl", choices: #"{"Curl":"nope"}"#).movement,
                       .curl)
    }

    // MARK: - Texts

    func testEveryMovementHasALabelThreeCuesAndATempo() {
        for movement in LiftMovement.allCases {
            XCTAssertFalse(movement.label.isEmpty, movement.rawValue)
            XCTAssertEqual(movement.cues.count, 3, movement.rawValue)
            XCTAssertFalse(movement.tempoLine.isEmpty, movement.rawValue)
        }
    }

    // MARK: - The figure

    private func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        hypot(Double(a.x - b.x), Double(a.y - b.y))
    }

    func testSegmentsKeepTheirLengthThroughEveryFrame() {
        typealias L = LiftFigureLength
        for movement in LiftMovement.allCases {
            let spec = movement.figure
            for i in 0...40 {
                let pose = spec.figurePose(at: spec.cycleSeconds * Double(i) / 40).pose
                let j = LiftFigureSolver.solve(spec, pose)
                let name = "\(movement.rawValue) frame \(i)"
                XCTAssertEqual(distance(j.ankle, j.knee), L.shin, accuracy: 0.05, name)
                XCTAssertEqual(distance(j.knee, j.hipNear), L.thigh, accuracy: 0.05, name)
                XCTAssertEqual(distance(j.hip, j.shoulder), L.torso, accuracy: 0.05, name)
                XCTAssertEqual(distance(j.shoulderNear, j.elbow), L.upperArm, accuracy: 0.05, name)
                XCTAssertEqual(distance(j.elbow, j.hand), L.forearm, accuracy: 0.05, name)
                XCTAssertEqual(distance(j.hipFar, j.knee2), L.thigh, accuracy: 0.05, name)
                XCTAssertEqual(distance(j.knee2, j.ankle2), L.shin, accuracy: 0.05, name)
            }
        }
    }

    func testWhatMustNotSlideStaysPut() {
        // The lunge's back foot and the pull-up's hands are reached for, not driven: they hold still.
        for (movement, fixed) in [(LiftMovement.lunge, \LiftFigureJoints.ankle2),
                                  (.pullUp, \LiftFigureJoints.hand), (.pushUp, \LiftFigureJoints.hand)] {
            let spec = movement.figure
            let first = LiftFigureSolver.solve(spec, spec.start)[keyPath: fixed]
            for i in 0...20 {
                let j = LiftFigureSolver.solve(spec, spec.figurePose(at: spec.cycleSeconds * Double(i) / 20).pose)
                XCTAssertLessThan(distance(j[keyPath: fixed], first), 1.5, "\(movement.rawValue) frame \(i)")
            }
        }
    }

    func testEveryMovementFitsAFiniteBoxAndDrawsShapes() {
        for movement in LiftMovement.allCases {
            let spec = movement.figure
            let box = LiftFigureDrawing.bounds(spec)
            XCTAssertTrue(box.width > 60 && box.height > 60 && box.width.isFinite && box.height.isFinite,
                          movement.rawValue)
            let shapes = LiftFigureDrawing.shapes(spec, spec.stillPose, in: box)
            XCTAssertGreaterThan(shapes.count, 10, movement.rawValue)
            XCTAssertTrue(shapes.contains { $0.role == .highlight }, movement.rawValue)
        }
    }

    func testTheLoopWalksThroughItsPhasesInOrder() {
        let spec = LiftMovement.squat.figure
        XCTAssertEqual(spec.cycleSeconds, 3.8, accuracy: 0.0001)
        XCTAssertEqual(spec.figurePose(at: 0.2).phase, .ready)
        XCTAssertEqual(spec.figurePose(at: 1.0).phase, .lowering)
        XCTAssertEqual(spec.figurePose(at: 2.6).phase, .pausing)
        XCTAssertEqual(spec.figurePose(at: 3.2).phase, .lifting)
        XCTAssertEqual(spec.figurePose(at: 3.8 + 0.2).phase, .ready)
        XCTAssertEqual(spec.figurePose(at: 2.6).pose, spec.end)
        XCTAssertEqual(spec.figurePose(at: 0).pose, spec.start)
    }

    func testAHoldNeverMoves() {
        let spec = LiftMovement.plank.figure
        XCTAssertNil(spec.end)
        XCTAssertEqual(spec.figurePose(at: 12.3).pose, spec.start)
        XCTAssertEqual(spec.figurePose(at: 12.3).phase, .holding)
        XCTAssertEqual(spec.stillPose, spec.start)
    }
}
