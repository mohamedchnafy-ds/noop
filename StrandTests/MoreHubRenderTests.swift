import XCTest
import SwiftUI
import AppKit
@testable import Strand
import StrandDesign

/// Renders the More sheet (fork chantier 9: the profile row, then the four groups that are not tabs) to PNG
/// at iPhone width, in dark mode — the visual check against the « NOOP – Chantier 9 · Navigation » mockup
/// before an .ipa is built (personal fork). The page title is drawn as `ScreenScaffold` draws it (the
/// scaffold's scroll view does not render to an image). PNGs are written only when `NOOP_RENDER_DIR` is set.
@MainActor
final class MoreHubRenderTests: XCTestCase {

    private let width: CGFloat = 390

    func testRenderMoreHub() throws {
        XCTAssertEqual(MoreHubGroup.allCases.count, 6)
        // Training and Nutrition are tabs: the sheet lists the four others, in this order.
        XCTAssertEqual(MoreHubGroup.sheetGroups, [.healthRecovery, .analysis, .data, .appSettings])
        let hub = VStack(alignment: .leading, spacing: 22) {
            Text("More")
                .font(StrandFont.title1)
                .foregroundStyle(StrandPalette.textPrimary)
            VStack(spacing: NoopMetrics.space3) {
                MoreProfileRowLabel(avatarImageData: nil)
                MoreHubCard(groups: MoreHubGroup.sheetGroups) { group, isLast in
                    MoreHubRowLabel(group: group, showsDivider: !isLast)
                }
            }
        }
        try render(AnyView(hub), name: "1-plus")
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
            try png.write(to: folder.appendingPathComponent("entrainement-\(name).png"))
        }
    }
}
