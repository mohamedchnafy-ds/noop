import XCTest
import SwiftUI
import AppKit
@testable import Strand
import StrandDesign
import WhoopStore

/// Renders the Lift Log's Progression to PNG at iPhone width, in dark mode — the visual check against the
/// « NOOP – Progression (Carnet de force) » mockups before an .ipa is built (personal fork).
///
/// Twelve weeks of a Full body A / B / C rotation are generated with the patterns the mockups show: a
/// squat climbing the double-progression ladder, a lateral raise and a military press that stall, a
/// Romanian deadlift that declines, two exercises too new for a verdict. The screens, their rules and
/// their tokens are the real ones. PNGs are written only when `NOOP_RENDER_DIR` is set.
@MainActor
final class LiftProgressRenderTests: XCTestCase {

    private let width: CGFloat = 390
    private let day = 86_400
    private lazy var now = Int(Date().timeIntervalSince1970)

    // MARK: Fixture

    private typealias Week = (kg: Double, reps: [Int])

    private struct Plan {
        let program: String
        let offsetDays: Int
        let exercises: [(name: String, primary: LiftMuscle, secondary: [LiftMuscle], weeks: [Week?])]
    }

    /// Twelve entries, oldest week first; nil = not done that week.
    private func ladder(_ steps: [(Double, [Int])]) -> [Week?] { steps.map { Optional((kg: $0.0, reps: $0.1)) } }

    private func flat(_ kg: Double, _ reps: [Int], from: Int = 0) -> [Week?] {
        (0..<12).map { week -> Week? in week < from ? nil : (kg: kg, reps: reps) }
    }

    private func climbing(_ kg: Double, step: Double, start: Int = 9) -> [Week?] {
        // Reps climb 9 → 12 at one weight, then the weight goes up and reps restart.
        (0..<12).map { week -> Week? in
            let level = week / 4
            let reps = start + week % 4
            return (kg: kg + Double(level) * step, reps: [reps, reps, reps - 1])
        }
    }

    /// Two sets of 12, two kilos more every three weeks.
    private var shrug: [Week?] {
        (0..<12).map { week -> Week? in (kg: 24 + Double(week / 3) * 2, reps: [12, 12]) }
    }

    private var plans: [Plan] {
        [
            Plan(program: "Full body A", offsetDays: 5, exercises: [
                ("Squat barre", .quads, [.glutes, .adductors], ladder([
                    (32.5, [11, 11, 11]), (32.5, [12, 12, 12]), (35, [10, 10, 10]), (35, [11, 11, 10]),
                    (35, [12, 12, 12]), (37.5, [10, 10, 9]), (37.5, [11, 11, 10]), (37.5, [12, 12, 12]),
                    (40, [10, 10, 9]), (40, [11, 11, 10]), (40, [11, 11, 11]), (40, [12, 12, 12])])),
                ("Leg curl allongé", .hamstrings, [.calves], ladder([
                    (50, [10, 10, 10]), (50, [11, 11, 11]), (50, [12, 12, 12]), (52.5, [10, 10, 10]),
                    (52.5, [12, 12, 11]), (55, [10, 10, 10]), (55, [12, 12, 12]), (57.5, [10, 10, 10]),
                    (57.5, [12, 12, 12]), (60, [10, 10, 10]), (60, [11, 11, 11]), (60, [12, 12, 12])])),
                ("Développé couché haltères", .chest, [.frontDelts, .triceps], climbing(20, step: 2)),
                ("Élévations latérales", .sideDelts, [], ladder([
                    (6, [12, 12, 12]), (7, [10, 10, 10]), (7, [12, 11, 11]), (7, [12, 12, 12]),
                    (8, [10, 10, 9]), (8, [11, 11, 10]), (8, [12, 11, 10]), (8, [12, 11, 10]),
                    (8, [12, 11, 10]), (8, [11, 11, 10]), (8, [12, 11, 10]), (8, [12, 10, 10])])),
                ("Tirage vertical", .lats, [.biceps, .rearDelts], climbing(48, step: 4)),
                ("Curl incliné", .biceps, [], climbing(10, step: 1)),
            ]),
            Plan(program: "Full body B", offsetDays: 3, exercises: [
                ("Presse à cuisses", .quads, [.glutes], climbing(110, step: 10)),
                ("Soulevé de terre roumain", .hamstrings, [.glutes, .lowerBack], ladder([
                    (45, [10, 10, 10]), (45, [11, 11, 10]), (45, [12, 12, 11]), (47.5, [10, 10, 10]),
                    (47.5, [11, 11, 11]), (47.5, [12, 12, 12]), (50, [10, 10, 10]), (50, [11, 11, 11]),
                    (50, [12, 11, 11]), (50, [11, 10, 10]), (50, [9, 9, 8]), (50, [8, 8, 8])])),
                ("Développé militaire", .frontDelts, [.sideDelts, .triceps], ladder([
                    (25, [10, 10, 9]), (25, [11, 11, 10]), (25, [12, 12, 12]), (27.5, [9, 9, 8]),
                    (27.5, [10, 10, 10]), (27.5, [12, 12, 11]), (30, [8, 8, 7]), (30, [9, 8, 8]),
                    (30, [8, 8, 7]), (30, [9, 8, 7]), (30, [8, 8, 8]), (30, [8, 8, 7])])),
                ("Rowing barre", .upperBack, [.lats, .rearDelts, .biceps], climbing(40, step: 5)),
                ("Shrug haltères", .traps, [], shrug),
            ]),
            Plan(program: "Full body C", offsetDays: 1, exercises: [
                ("Pompes lestées", .chest, [.triceps, .frontDelts], climbing(5, step: 2.5)),
                ("Tractions", .lats, [.biceps, .upperBack], climbing(0, step: 2.5, start: 6)),
                ("Fentes bulgares", .quads, [.glutes, .adductors], flat(16, [10, 10, 10], from: 10)),
                ("Face pull", .rearDelts, [.upperBack, .traps], flat(20, [12, 12, 12], from: 10)),
            ]),
        ]
    }

    private func fixture(weeks: Int = 12) -> LiftProgressData {
        var sessions: [LiftProgress.Session] = []
        var lines: [String: LiftProgress.ProgramLine] = [:]
        for plan in plans {
            for exercise in plan.exercises where lines[exercise.name] == nil {
                let reps = exercise.name == "Shrug haltères" ? (12, 15) : (10, 12)
                lines[exercise.name] = LiftProgress.ProgramLine(
                    item: LiftPlanItem(exercise: exercise.name, primaryMuscle: exercise.primary,
                                       secondaryMuscles: exercise.secondary,
                                       targetSets: exercise.name == "Shrug haltères" ? 2 : 3,
                                       targetRepsLow: reps.0, targetRepsHigh: reps.1),
                    programName: plan.program)
            }
            for week in (12 - weeks)..<12 {
                let start = now - (11 - week) * 7 * day - plan.offsetDays * day + 18 * 3_600 - now % day
                let id = "\(plan.program)-\(week)"
                var rows: [LiftSetRow] = []
                for exercise in plan.exercises {
                    guard let done = exercise.weeks[week] else { continue }
                    for reps in done.reps {
                        rows.append(LiftSetRow(id: "\(id)-\(rows.count)", deviceId: "d", sessionId: id, ord: rows.count,
                                               exercise: exercise.name, primaryMuscle: exercise.primary,
                                               secondaryMuscles: exercise.secondary, setIndex: rows.count + 1,
                                               weightKg: done.kg > 0 ? done.kg : nil, reps: reps, rpe: nil,
                                               isWarmup: false, startTs: nil, endTs: nil, restSec: nil, note: nil))
                    }
                }
                let row = LiftSessionRow(id: id, deviceId: "d", startTs: start, endTs: start + 3_000, sport: "lift",
                                         programId: plan.program, programName: plan.program, sessionRpe: nil, note: nil)
                sessions.append(LiftProgress.Session(row: row, sets: rows))
            }
        }
        let exercises = LiftProgress.exercises(sessions: sessions, lines: lines, stepKg: LiftProgression.metricStepKg)

        // Charge and sleep that line up with how each session went, so the Form charts read as designed.
        var charge: [String: Double] = [:]
        var sleep: [String: Double] = [:]
        for (index, form) in LiftProgress.formSessions(exercises).enumerated() {
            let key = Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval(form.startTs)))
            let wobble = Double((index * 37) % 11) - 5
            charge[key] = min(98, max(8, 55 + form.percent * 6 + wobble * 3))
            sleep[key] = min(520, max(300, 405 + form.percent * 12 + wobble * 6))
        }
        return LiftProgressData(sessions: sessions, lines: lines, exercises: exercises,
                                charge: charge, sleep: sleep, now: now)
    }

    // MARK: Renders

    func testRendersTheProgressionScreens() throws {
        let data = fixture()
        let padded = { (view: AnyView) in
            AnyView(view.padding(.horizontal, NoopMetrics.screenPadding).padding(.vertical, 24))
        }

        try render(padded(AnyView(LiftProgressCard(data: data, unitSystem: .metric))), name: "1-carte-carnet")
        try render(padded(AnyView(LiftProgressExercisesTab(data: data, unitSystem: .metric,
                                                           period: .constant(.fourWeeks)))), name: "2-exercices")
        let squat = try XCTUnwrap(data.exercise(named: "Squat barre"))
        try render(padded(AnyView(LiftExerciseProgressContent(exercise: squat, now: data.now, unitSystem: .metric))),
                   name: "3-detail-squat")
        try render(padded(AnyView(LiftProgressMusclesTab(data: data, period: .constant(.fourWeeks), open: { _ in }))),
                   name: "4-muscles")
        try render(AnyView(LiftMuscleProgressSheet(muscle: .sideDelts, data: data, period: .fourWeeks,
                                                   unitSystem: .metric, scrolls: false)), name: "5-muscle-epaules")
        try render(padded(AnyView(LiftProgressFormTab(data: data))), name: "6-forme")
        try render(padded(AnyView(LiftProgressFormTab(data: fixture(weeks: 7)))), name: "7-forme-verrouillee")

        // The statuses the mockups show, from the generated history.
        XCTAssertEqual(squat.status, .ready(fromKg: 40, toKg: 42.5))
        XCTAssertEqual(data.exercise(named: "Élévations latérales")?.status.rank, 0)
        XCTAssertEqual(data.exercise(named: "Soulevé de terre roumain")?.status.rank, 1)
        XCTAssertEqual(data.exercise(named: "Fentes bulgares")?.status, .notEnough(sessions: 2))
        XCTAssertGreaterThanOrEqual(LiftProgress.formSessions(data.exercises).count, LiftProgress.formMinimumSessions)
    }

    private func render(_ content: AnyView, name: String) throws {
        let screen = content
            .frame(width: width, alignment: .top)
            .fixedSize(horizontal: false, vertical: true)
            .background(StrandPalette.surfaceBase)
            .environment(\.colorScheme, .dark)
            .environment(\.locale, Locale(identifier: "fr_FR"))

        let renderer = ImageRenderer(content: screen)
        renderer.scale = 3
        var image: NSImage?
        // The palette's light/dark pairs resolve through the drawing appearance, not the SwiftUI scheme.
        (NSAppearance(named: .darkAqua) ?? NSAppearance.currentDrawing()).performAsCurrentDrawingAppearance {
            image = renderer.nsImage
        }
        let rendered = try XCTUnwrap(image, "\(name) did not render")
        let cg = try XCTUnwrap(rendered.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let png = try XCTUnwrap(NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(png.count, 10_000, "\(name) rendered next to nothing")

        if let dir = ProcessInfo.processInfo.environment["NOOP_RENDER_DIR"], !dir.isEmpty {
            let folder = URL(fileURLWithPath: dir, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try png.write(to: folder.appendingPathComponent("progression-\(name).png"))
        }
    }
}
