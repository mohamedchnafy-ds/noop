import XCTest
import SwiftUI
import AppKit
@testable import Strand
import StrandDesign
import WhoopStore

/// The program editor's body map (personal fork, chantier 8, lot 5): what `LiftMuscleFilter` reads from
/// the vocabulary, and the section rendered to PNG at iPhone width, in dark mode. PNGs are written only
/// when `NOOP_RENDER_DIR` is set.
@MainActor
final class LiftProgramMuscleRenderTests: XCTestCase {

    private let width: CGFloat = 390

    private func exercise(_ name: String, _ primary: LiftMuscle?, _ secondaries: [LiftMuscle] = []) -> LiftExerciseRow {
        LiftExerciseRow(id: name, deviceId: "d", name: name, primaryMuscle: primary,
                        secondaryMuscles: secondaries, createdAt: 0, lastUsedTs: nil)
    }

    private var vocabulary: [LiftExerciseRow] {
        [exercise("Squat barre", .quads, [.glutes, .adductors]),
         exercise("Développé couché", .chest, [.frontDelts, .triceps]),
         exercise("Rowing barre", .upperBack, [.lats, .biceps, .rearDelts]),
         exercise("Développé incliné haltères", .chest, [.frontDelts]),
         exercise("Pompes", .chest, [.triceps]),
         exercise("Dips", .triceps, [.chest]),
         exercise("Gainage", nil)]
    }

    private let program = ["Squat barre", "Développé couché", "Rowing barre"]

    // MARK: Reading

    func testTheExercisesOfAMuscleAreTheDirectOnesThenTheIndirectOnes() {
        let found = LiftMuscleFilter.exercisesWorking(.chest, in: vocabulary)
        XCTAssertEqual(found.direct.map(\.name), ["Développé couché", "Développé incliné haltères", "Pompes"])
        XCTAssertEqual(found.indirect.map(\.name), ["Dips"])
        let neck = LiftMuscleFilter.exercisesWorking(.neck, in: vocabulary)
        XCTAssertTrue(neck.direct.isEmpty && neck.indirect.isEmpty)
    }

    func testTheProgramCoverageKeepsDirectOverIndirect() {
        // Triceps: indirect in the bench press; chest: direct in the bench press and indirect in dips.
        let coverage = LiftMuscleFilter.programCoverage(exercises: program + ["Dips"], vocabulary: vocabulary)
        XCTAssertEqual(coverage[.chest], LiftMuscleFilter.directShade)
        XCTAssertEqual(coverage[.triceps], LiftMuscleFilter.directShade, "Dips work it directly")
        XCTAssertEqual(coverage[.lats], LiftMuscleFilter.indirectShade)
        XCTAssertNil(coverage[.hamstrings])
        // An unclassified or unknown exercise claims nothing.
        XCTAssertTrue(LiftMuscleFilter.programCoverage(exercises: ["Gainage", "Inconnu"], vocabulary: vocabulary).isEmpty)
    }

    func testTheShadesLandInTwoDifferentBandsOfTheMap() {
        XCTAssertNotEqual(LiftBodyMapStyle.color(LiftMuscleFilter.directShade),
                          LiftBodyMapStyle.color(LiftMuscleFilter.indirectShade))
        XCTAssertNotEqual(LiftBodyMapStyle.color(LiftMuscleFilter.indirectShade), LiftBodyMapStyle.color(0))
    }

    // MARK: Rendering

    func testRendersTheChestSelected() throws {
        try render(selected: .chest, name: "1-pectoraux")
    }

    func testRendersAMuscleWithNoExercise() throws {
        try render(selected: .neck, name: "2-aucun-exercice")
    }

    /// Supersets et blocs: the Superset mode with two exercises ticked, A1 and A2.
    func testRendersTheSupersetModeWithTwoTicks() throws {
        let picks = Array(vocabulary.prefix(2))
        try render(selected: .chest, name: "3-superset", supersetMode: true, picks: picks)
    }

    private func render(selected: LiftMuscle?, name: String, supersetMode: Bool = false,
                        picks: [LiftExerciseRow] = []) throws {
        let screen = LiftProgramMuscleFilter(
            vocabulary: vocabulary, programExercises: program,
            selected: .constant(selected), supersetMode: .constant(supersetMode), picks: .constant(picks),
            onAdd: { _ in }, onNew: { _ in })
            .padding(.horizontal, NoopMetrics.screenPadding)
            .padding(.vertical, 24)
            .frame(width: width, alignment: .top)
            .fixedSize(horizontal: false, vertical: true)
            .background(StrandPalette.surfaceBase)
            .environment(\.colorScheme, .dark)
            .environment(\.locale, Locale(identifier: "fr_FR"))

        let renderer = ImageRenderer(content: screen)
        renderer.scale = 3
        var image: NSImage?
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
            try png.write(to: folder.appendingPathComponent("programme-corps-\(name).png"))
        }
    }
}
