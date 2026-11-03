import XCTest
import SwiftUI
import AppKit
@testable import Strand
import StrandDesign

/// Renders the in-progress workout screen (personal fork, chantier 8 — design A) to PNG at iPhone width,
/// in dark mode: a run (cardio: distance, splits, pace) and a strength session (average · max heart
/// rate, the curve before the zones). PNGs are written only when `NOOP_RENDER_DIR` is set.
@MainActor
final class LiveWorkoutRenderTests: XCTestCase {

    private let width: CGFloat = 390

    /// Ten minutes of 10-second buckets: a steady climb for the run, sets and rests for strength.
    private func runCurve() -> [Double?] {
        (0..<60).map { 138 + Double($0) * 0.4 + (Double($0 % 7) - 3) }
    }

    private func strengthCurve() -> [Double?] {
        (0..<60).map { index -> Double? in
            let phase = index % 12
            return phase < 4 ? 100 + Double(phase) * 14 : 156 - Double(phase - 4) * 7
        }
    }

    func testRendersTheRun() throws {
        let figures = LiveWorkoutFigures(
            layout: .cardio, sportName: "Course à pied", isPaused: false, elapsedSeconds: 24 * 60 + 18,
            bpm: 152, zone: 3, effort: "9,4", effortState: "Modéré", kcal: 286, averageHr: 146, peakHr: 161,
            distanceM: 4_620, currentPaceSecPerKm: 312, splits: [320, 315, 309, 310],
            zoneSeconds: [190, 520, 605, 143, 0], curve: runCurve())
        try render(LiveWorkoutDashboard(figures: figures), name: "1-cardio")
    }

    func testRendersTheStrengthSession() throws {
        let figures = LiveWorkoutFigures(
            layout: .strength, sportName: "Musculation", isPaused: false, elapsedSeconds: 38 * 60 + 42,
            bpm: 118, zone: 2, effort: "7,1", effortState: "Léger", kcal: 214, averageHr: 112, peakHr: 156,
            distanceM: nil, currentPaceSecPerKm: nil, splits: [],
            zoneSeconds: [1_025, 880, 330, 87, 0], curve: strengthCurve())
        try render(LiveWorkoutDashboard(figures: figures), name: "2-muscu")
    }

    /// At the start: no pace yet (« — »), no split, a paused state.
    func testRendersTheStartPaused() throws {
        let figures = LiveWorkoutFigures(
            layout: .cardio, sportName: "Course à pied", isPaused: true, elapsedSeconds: 12,
            bpm: nil, zone: 0, effort: "0,0", effortState: "Repos", kcal: nil, averageHr: nil, peakHr: nil,
            distanceM: 8, currentPaceSecPerKm: nil, splits: [], zoneSeconds: [0, 0, 0, 0, 0],
            curve: Array(repeating: nil, count: 60))
        try render(LiveWorkoutDashboard(figures: figures), name: "3-depart")
    }

    private func render<V: View>(_ content: V, name: String) throws {
        let screen = content
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
            try png.write(to: folder.appendingPathComponent("seance-\(name).png"))
        }
    }
}
