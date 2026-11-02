import XCTest
import SwiftUI
import AppKit
@testable import Strand
import StrandDesign

/// Renders the live heart-rate banner's Lock Screen face with each of its three sides, and the Live HR screen's
/// choice card, to PNG in dark mode — the visual check against the mockup ("NOOP – Bannières et widgets",
/// artboards 5 and 6) before an .ipa is built (personal fork). The face is the widget extension's own
/// (`StrandiOSShared/LiveHRBannerFace.swift`, compiled into this bundle); the values are the mockup's.
///
/// Always rendered, so a face that cannot be drawn fails here. The PNGs are written only when `NOOP_RENDER_DIR`
/// is set — by the fork's render workflow, which publishes them.
@MainActor
final class LiveHRBannerRenderTests: XCTestCase {

    private let width: CGFloat = 390

    func testRendersTheBannerSidesAndTheChoice() throws {
        let subtitle = LiveHRBannerFigures.subtitle(zone: 1)
        let sides: [LiveHRBannerFace.Side] = [
            .init(kind: .effort, label: LiveHRBannerSide.effort.title, value: "38.0", detail: nil,
                  fraction: 0.38, score: 72),
            .init(kind: .charge, label: LiveHRBannerSide.charge.title, value: "72",
                  detail: LiveHRBannerFigures.hrvText(46), fraction: 0.38, score: 72),
            .init(kind: .sleep, label: LiveHRBannerSide.sleep.title, value: SleepDurationText.format(408),
                  detail: [String(localized: "debt \(SleepDurationText.format(72))"),
                           String(localized: "bedtime \(TodaySynthesisLogic.clock(23 * 60 + 10))")]
                      .joined(separator: " · "),
                  fraction: 0.38, score: 72),
        ]
        let banners = VStack(spacing: 12) {
            ForEach(Array(sides.enumerated()), id: \.offset) { _, side in
                LiveHRBannerFace(subtitle: subtitle, bpm: 92, side: side)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(StrandPalette.surfaceRaised, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
        }
        .padding(12)
        try render(banners, name: "fc-1-bannieres")

        let card = LiveHRBannerSideCard(selection: .effort) { _ in }
            .padding(20)
        try render(card, name: "fc-2-reglage")
    }

    private func render<Content: View>(_ content: Content, name: String) throws {
        let view = content
            .frame(width: width)
            .background(StrandPalette.surfaceBase)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        var image: NSImage?
        // The palette's light/dark pairs resolve through the drawing appearance, not the SwiftUI scheme.
        (NSAppearance(named: .darkAqua) ?? NSAppearance.currentDrawing()).performAsCurrentDrawingAppearance {
            image = renderer.nsImage
        }
        let rendered = try XCTUnwrap(image, "\(name) did not render")
        let cg = try XCTUnwrap(rendered.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let png = try XCTUnwrap(NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(png.count, 5_000, "\(name) rendered next to nothing")

        if let dir = ProcessInfo.processInfo.environment["NOOP_RENDER_DIR"], !dir.isEmpty {
            let folder = URL(fileURLWithPath: dir, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try png.write(to: folder.appendingPathComponent("\(name).png"))
        }
    }
}
