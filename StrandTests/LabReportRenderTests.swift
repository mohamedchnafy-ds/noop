import XCTest
import SwiftUI
import AppKit
@testable import Strand
import StrandDesign
import WhoopStore

/// Renders the review of a lab report read by the Coach (personal fork, chantier 8) to PNG at iPhone width, in
/// dark mode: four values from the real parser, one already in the Lab Book that day (flagged, unticked), and
/// two markers suggested for Nutrition. PNGs are written only when `NOOP_RENDER_DIR` is set.
@MainActor
final class LabReportRenderTests: XCTestCase {

    private let width: CGFloat = 390

    func testRendersTheReview() throws {
        let json = """
        {"date": "2026-10-28", "values": [
          {"name": "Ferritine", "marker_key": "ferritin", "value": 42, "unit": "µg/L", "reference": "30 - 400"},
          {"name": "25-OH Vitamine D", "marker_key": "vitamin_d", "value": 61.5, "unit": "nmol/L", "reference": "75 - 250"},
          {"name": "Vitamine B12", "marker_key": "vitamin_b12", "value": 412, "unit": "pg/mL"},
          {"name": "Antigène HBs", "value_text": "négatif", "unit": ""}
        ], "nutrition_markers": ["ldl", "folate"]}
        """
        let existing = [LabMarkerRow(id: "x", deviceId: "d", markerKey: "vitamin_b12", category: "blood_panel",
                                     day: "2026-10-28", takenAt: LabBookFormat.noonEpoch("2026-10-28"), value: 410,
                                     valueText: nil, unit: "pg/mL", source: "manual", note: nil, referenceText: nil)]
        let report = try XCTUnwrap(CoachLabReport.fromToolInput(CoachTools.input(fromJSON: json), existing: existing,
                                                                existingSource: AICoachEngine.labSourceName).report)
        let content = LabReportReviewContent(report: .constant(report), nutrition: .constant(["ldl"]))
        try render(AnyView(content), name: "1-verification")
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
            try png.write(to: folder.appendingPathComponent("labo-\(name).png"))
        }
    }
}
