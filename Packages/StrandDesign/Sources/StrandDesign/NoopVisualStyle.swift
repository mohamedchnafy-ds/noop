import SwiftUI

// MARK: - NOOP visual foundation
//
// These tokens describe the visual treatment used by NOOP's existing views. They deliberately
// contain no navigation, state, or domain semantics: screens keep their current hierarchy and data
// bindings, while cards, gauges, typography, and chrome share one maintainable source of truth.

public enum NoopVisualStyle {
    // Apple Fitness + Health direction (fork chantier 7): pure black canvas, flat #1C1C1E cards with no
    // border, hairlines at white 9 %, white primary text and system grey secondary text.
    public static let canvas = Color(light: "#F2F2F7", dark: "#000000")
    public static let surface = Color(light: "#FFFFFF", dark: "#1C1C1E")
    public static let surfaceTop = Color(light: "#FFFFFF", dark: "#2C2C2E")
    public static let surfaceBottom = Color(light: "#FFFFFF", dark: "#1C1C1E")
    public static let inset = Color(light: "#E5E5EA", dark: "#2C2C2E")
    /// The selected segment of a pill control (#3A3A3C on dark).
    public static let control = Color(light: "#FFFFFF", dark: "#3A3A3C")

    public static let border = Color(light: "#0000001A", dark: "#FFFFFF17")
    public static let borderHighlight = Color(light: "#00000024", dark: "#FFFFFF24")
    public static let divider = Color(light: "#0000001A", dark: "#FFFFFF17")

    public static let primaryText = Color(light: "#000000", dark: "#FFFFFF")
    public static let secondaryText = Color(light: "#6C6C70", dark: "#8E8E93")
    public static let tertiaryText = Color(light: "#8E8E93", dark: "#636366")

    // The former mint accent now resolves to the system blue: links and actions are blue, colour is
    // carried by the metrics only. The names stay so existing call sites keep compiling.
    public static let mint = Color(light: "#007AFF", dark: "#0A84FF")
    public static let mintDeep = Color(light: "#0062CC", dark: "#0A84FF")
    public static let mintGlow = Color(light: "#409CFF", dark: "#409CFF")

    public static let cardRadius: CGFloat = 20
    public static let compactRadius: CGFloat = 14
    public static let pillRadius: CGFloat = 999
    public static let pagePadding: CGFloat = 16
    public static let cardPadding: CGFloat = 16
    public static let itemGap: CGFloat = 12
    public static let sectionGap: CGFloat = 26
}

/// Shared card/panel treatment: one flat surface fill, no border and no shadow.
public struct NoopPanelSurface: View {
    public var tint: Color?
    public var cornerRadius: CGFloat
    public var elevated: Bool
    public var surfaceOpacity: Double

    public init(
        tint: Color? = nil,
        cornerRadius: CGFloat = NoopVisualStyle.cardRadius,
        elevated: Bool = false,
        surfaceOpacity: Double = 1
    ) {
        self.tint = tint
        self.cornerRadius = cornerRadius
        self.elevated = elevated
        self.surfaceOpacity = surfaceOpacity
    }

    public var body: some View {
        // One flat fill, no border, no shadow, on every platform: the cards separate from the black
        // canvas by their fill alone. `tint` and `elevated` are kept for source compatibility.
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(NoopVisualStyle.surface)
            .opacity(surfaceOpacity)
    }
}

/// Shared edge-to-edge chrome for sheet and split-view headers. Unlike a card it has no
/// rounded outline, but it uses the same flat surface and divider token.
public struct NoopChromeSurface: View {
    public init() {}

    public var body: some View {
        NoopVisualStyle.surface
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(NoopVisualStyle.divider)
                .frame(height: 0.5)
        }
    }
}

public extension View {
    func noopPanel(
        tint: Color? = nil,
        cornerRadius: CGFloat = NoopVisualStyle.cardRadius,
        elevated: Bool = false,
        surfaceOpacity: Double = 1
    ) -> some View {
        background {
            NoopPanelSurface(
                tint: tint,
                cornerRadius: cornerRadius,
                elevated: elevated,
                surfaceOpacity: surfaceOpacity
            )
        }
    }
}
