import XCTest
import SwiftUI
import AppKit
@testable import Strand
import StrandDesign
import WhoopStore

/// Renders the Coach's action cards (personal fork, chantier 8) to PNG at iPhone width, in dark mode: a nap to
/// confirm, a set correction confirmed (with Undo), a workout correction and a fact to remember already undone.
/// The lines come from the real parsers. PNGs are written only when `NOOP_RENDER_DIR` is set.
@MainActor
final class CoachCardsRenderTests: XCTestCase {

    private let width: CGFloat = 390

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }()

    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 16))! }

    private func input(_ json: String) -> [String: Any] { CoachTools.input(fromJSON: json) }

    func testRendersTheActionCards() throws {
        let nap = try XCTUnwrap(CoachActionProposal.nap(from: input(#"{"start": "13:20", "end": "13:50"}"#),
                                                        now: now, calendar: calendar).proposal)
        let start = Int(calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 18))!.timeIntervalSince1970)
        func set(_ id: String, _ exercise: String, _ index: Int, _ ord: Int, _ kg: Double, _ reps: Int) -> LiftSetRow {
            LiftSetRow(id: id, deviceId: "d", sessionId: "s1", ord: ord, exercise: exercise, primaryMuscle: nil,
                       secondaryMuscles: [], setIndex: index, weightKg: kg, reps: reps, rpe: nil, isWarmup: false,
                       startTs: nil, endTs: nil, restSec: nil, note: nil)
        }
        let session = CoachActionProposal.LiftSession(
            row: LiftSessionRow(id: "s1", deviceId: "d", startTs: start, endTs: start + 3600, sport: "Strength Training",
                                programId: nil, programName: "Full body A", sessionRpe: nil, note: nil),
            sets: [set("a", "Squat barre", 1, 0, 80, 5), set("b", "Squat barre", 2, 1, 80, 5),
                   set("c", "Curl incliné", 1, 2, 12, 10)])
        var lift = try XCTUnwrap(CoachActionProposal.liftFix(
            from: input(#"{"date": "2026-11-02", "changes": [{"exercise": "Squat barre", "set": 2, "weight": 85},"#
                        + #"{"exercise": "Curl incliné", "weight": 12, "reps": 8}]}"#),
            sessions: [session], system: .metric, now: now, calendar: calendar).proposal)
        lift.state = .applied
        let row = WorkoutRow(startTs: start, endTs: start + 2700, sport: "Running", source: "manual", durationS: 2700,
                             energyKcal: 400, avgHr: 140, maxHr: nil, strain: nil, distanceM: 5000, zonesJSON: nil,
                             notes: nil, steps: nil)
        let workout = try XCTUnwrap(CoachActionProposal.workoutFix(
            from: input(#"{"date": "2026-11-02", "start": "18:00", "distance_km": 6.2, "new_end": "18:50"}"#),
            rows: [row], now: now, calendar: calendar, distance: { String(format: "%.1f km", $0 / 1000) }).proposal)
        var remember = try XCTUnwrap(CoachActionProposal.rememberCard(
            from: input(#"{"fact": "Douleur au genou dans les escaliers depuis octobre", "kind": "constraint"}"#),
            profile: CoachProfile()).proposal)
        remember.state = .undone

        let cards = VStack(alignment: .leading, spacing: 16) {
            ForEach(Array([nap, lift, workout, remember].enumerated()), id: \.offset) { _, proposal in
                CoachActionCard(proposal: proposal, busy: false, onConfirm: {}, onUndo: {})
            }
        }
        try render(AnyView(cards), name: "1-actions")
    }

    private func render(_ content: AnyView, name: String) throws {
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
            try png.write(to: folder.appendingPathComponent("coach-\(name).png"))
        }
    }
}
