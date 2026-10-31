import XCTest
import SwiftUI
import AppKit
@testable import Strand
import StrandDesign
import WhoopStore

/// Renders the three guided superset screens to PNG, the size of an iPhone screen, in dark mode — the
/// visual check against the mockups before an .ipa is built (personal fork).
///
/// Everything live or editable is replaced by a fixed stand-in (a number for a text field, fixed tiles
/// for the live row), which is exactly what `LiftSupersetScreen` takes from outside; the screen itself,
/// its layout and its tokens are the real ones. The clocks are real too, anchored so they read what the
/// mockups show (0:38 into a round, 1:15 left of a 2:00 rest).
///
/// Always rendered, so a screen that cannot be drawn fails here. The PNGs are written only when
/// `NOOP_RENDER_DIR` is set — by the fork's render workflow, which publishes them.
@MainActor
final class LiftSupersetRenderTests: XCTestCase {

    private let size = CGSize(width: 390, height: 844)

    /// Superset A as drawn — squat barre then leg curl allongé, 3 rounds, 2:00 — between a line on its
    /// own before and two after, so the block is "1 / 4" once the line before is dropped.
    private func plan() -> [LiftPlanItem] {
        [
            LiftPlanItem(exercise: "Squat barre", primaryMuscle: .quads, secondaryMuscles: [.glutes, .adductors],
                         targetSets: 3, restSec: 120, targetRepsLow: 10, targetWeightKg: 40, supersetGroup: "A"),
            LiftPlanItem(exercise: "Leg curl allongé", primaryMuscle: .hamstrings, secondaryMuscles: [.calves],
                         targetSets: 3, restSec: 120, targetRepsLow: 10, targetWeightKg: 60, supersetGroup: "A"),
            LiftPlanItem(exercise: "Développé couché", primaryMuscle: .chest, targetSets: 3,
                         supersetGroup: "B"),
            LiftPlanItem(exercise: "Rowing barre", primaryMuscle: .upperBack, targetSets: 3, supersetGroup: "B"),
            LiftPlanItem(exercise: "Mollets debout", primaryMuscle: .calves, targetSets: 3),
            LiftPlanItem(exercise: "Gainage", primaryMuscle: .abs, targetSets: 2),
        ]
    }

    private var now: Int { Int(Date().timeIntervalSince1970) }

    func testRendersTheThreeScreens() throws {
        // Ready: the session's first block.
        let ready = LiftSessionEngine(plan: plan(), startTs: now)
        try render(ready, name: "1-bloc-pret")

        // Set in progress: round 2, 0:38 in, 12:40 into the session.
        var working = LiftSessionEngine(plan: plan(), startTs: now - 760)
        working.advance(now: now - 700)               // round 1 starts
        working.advance(now: now - 650)               // round 1 done
        working.advance(now: now - 38)                // rest skipped: round 2 starts
        try render(working, name: "2-serie-en-cours")

        // Rest: after round 2 (which took 0:52), 1:15 left of 2:00, 14:02 into the session.
        var resting = LiftSessionEngine(plan: plan(), startTs: now - 842)
        resting.advance(now: now - 780)
        resting.advance(now: now - 730)               // round 1 done
        resting.advance(now: now - 97)                // round 2 starts
        resting.advance(now: now - 45)                // round 2 done: rest until now + 75
        try render(resting, name: "3-repos")
    }

    private func render(_ engine: LiftSessionEngine, name: String) throws {
        let guide = try XCTUnwrap(LiftSupersetGuide.make(engine, now: now), name)
        let last = LiftSupersetGuide.LastTime(
            date: Date(timeIntervalSince1970: TimeInterval(now - 4 * 86_400)), rounds: 3,
            numbers: [LiftSetCarry(weightKg: 40, reps: 10), LiftSetCarry(weightKg: 60, reps: 10)],
            restSec: 120, durationSec: 540)
        let screen = LiftSupersetScreen(
            guide: guide,
            sessionStart: engine.startTs,
            lastTime: last,
            unitSystem: .metric,
            canUndo: true,
            field: { slot, kind in
                let values = slot.exerciseIndex == 0 ? (40, 10) : (60, 10)
                return AnyView(Text(verbatim: kind == .weight ? "\(values.0)" : "\(values.1)"))
            },
            vitals: { vitals in
                switch vitals {
                case .working:
                    return AnyView(HStack(spacing: 10) {
                        LiftGuideTile(label: String(localized: "HR"), value: "142", tint: StrandPalette.metricRose,
                                      caption: String(localized: "bpm · zone \(4)"))
                        LiftGuideTile(label: String(localized: "Effort"), value: "9.4", caption: String(localized: "live"))
                        LiftGuideTile(label: String(localized: "kcal"), value: "186",
                                      caption: String(localized: "Avg HR \(128)"))
                    })
                case .resting(let lastRoundSec):
                    return AnyView(HStack(spacing: 10) {
                        LiftGuideTile(label: String(localized: "HR"), value: "118", tint: StrandPalette.metricRose,
                                      caption: String(localized: "↓ recovering"))
                        LiftGuideTile(label: String(localized: "Last round"),
                                      value: lastRoundSec.map(ActiveWorkoutClock.clock) ?? "—",
                                      caption: String(localized: "set length"))
                        LiftGuideTile(label: String(localized: "Effort"), value: "10.1", caption: String(localized: "live"))
                    })
                }
            },
            strapCard: { AnyView(LiftStrapCardContent(bpm: 72)) },
            preview: { $0.exerciseIndex == 0 ? "40 kg × 10" : "60 kg × 10" },
            suggestion: { _ in nil },
            actions: LiftSupersetScreen.Actions(start: {}, roundDone: {}, skipRest: {}, addRest: {},
                                                changeRounds: { _ in }, setRest: { _ in }, endBlock: {},
                                                showSession: {}, undo: {}, finish: {}),
            scrolls: false)
            .frame(width: size.width, height: size.height)
            .background(StrandPalette.surfaceBase)
            .environment(\.colorScheme, .dark)

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
            try png.write(to: folder.appendingPathComponent("\(name).png"))
        }
    }
}
