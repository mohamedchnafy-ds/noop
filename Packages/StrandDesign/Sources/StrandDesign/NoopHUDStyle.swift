import SwiftUI

// MARK: - HUD style (personal fork, chantier 13)
//
// The tokens of the optional "holographic HUD" look of the Today screen: a chrome colour for the instrument
// lines (cyan on dark, slate blue on the light "blueprint"), the panel and canvas tones, the technical label
// font, the chamfered panel shape and its corner brackets. The metric colours stay `StrandPalette`'s: the HUD
// changes the instrument around the numbers, never what a colour means. Every glow is drawn (a wider,
// translucent copy of a stroke, or a radial gradient), never a blur or a shadow, so a scrolling page carries
// no filter at rest.

/// Colours and measures of the Today HUD.
public enum NoopHUDStyle {
    /// The instrument lines: graduations, panel edges, brackets, the status line.
    public static let chrome = Color(light: "#0B5E86", dark: "#5FE3FF")
    /// The fine light line drawn along a lit ring.
    public static let sheen = Color(light: "#FFFFFF", dark: "#FFFFFF")
    /// A panel's one-point edge.
    public static let frame = Color(light: "#0B5E866B", dark: "#5FE3FF61")
    /// A quieter edge (the small vital panels) and the round header controls.
    public static let frameSoft = Color(light: "#0B5E864D", dark: "#5FE3FF47")
    /// The wash behind a cell, and the unlit segments of a bar.
    public static let wash = Color(light: "#0B5E860F", dark: "#5FE3FF0F")
    public static let segmentOff = Color(light: "#0B5E8624", dark: "#5FE3FF24")
    /// The track a range bar sits on.
    public static let track = Color(light: "#0B5E8638", dark: "#5FE3FF33")
    /// A rule between list rows and above a footer.
    public static let rule = Color(light: "#0B5E8629", dark: "#5FE3FF24")

    /// Reading text on the HUD (a cool white on dark, a deep slate on light).
    public static let text = Color(light: "#0A1B26", dark: "#EAF6FF")
    /// Secondary text, units and technical labels (≥ 4.5:1 on both panels).
    public static let textSecondary = Color(light: "#4E6878", dark: "#7FA3B5")
    /// The heart-rate label colour: the FC rose, darkened on light so a small label keeps its contrast.
    public static let heartLabel = Color(light: "#C7002F", dark: "#FF375F")

    /// The page behind the panels: a deep blue-black lit from the top on dark, a pale blue sheet on light.
    public static let canvasTop = Color(light: "#E6F0F6", dark: "#0A2230")
    public static let canvasMid = Color(light: "#F3F8FB", dark: "#04111A")
    public static let canvasBottom = Color(light: "#F8FBFD", dark: "#02070B")
    /// A panel's fill, top to bottom.
    public static let panelTop = Color(light: "#FFFFFF", dark: "#0A2230EB")
    public static let panelBottom = Color(light: "#F4F9FC", dark: "#030A10F5")
    /// The flat fill of a small panel or a readout box.
    public static let panelFlat = Color(light: "#FFFFFF", dark: "#04111A")

    /// How strongly a drawn glow (the wide translucent copy of a stroke) shows.
    public static func glowOpacity(_ scheme: ColorScheme) -> Double { scheme == .dark ? 0.22 : 0.12 }

    /// The cut of a panel's chamfered corners, large and small.
    public static let cut: CGFloat = 16
    public static let cutSmall: CGFloat = 10
    /// The length and width of a corner bracket.
    public static let bracketLength: CGFloat = 14
    public static let bracketWidth: CGFloat = 2
    /// The letter spacing of a technical label.
    public static let labelTracking: CGFloat = 1.2

    /// The page gradient (static: no filter, drawn once per frame like any fill).
    public static var canvas: LinearGradient {
        LinearGradient(colors: [canvasTop, canvasMid, canvasBottom], startPoint: .top, endPoint: .bottom)
    }

    /// A panel's fill.
    public static var panel: LinearGradient {
        LinearGradient(colors: [panelTop, panelBottom], startPoint: .top, endPoint: .bottom)
    }
}

public extension StrandFont {
    /// The HUD's technical label (SF Mono, follows Dynamic Type from the caption-2 size). Pair it with
    /// `noopHUDLabel()` for the capitals and the letter spacing.
    static let hudLabel = Font.system(.caption2, design: .monospaced, weight: .medium)
    /// The HUD's technical caption, one step larger (status line, units, times).
    static let hudCaption = Font.system(.caption, design: .monospaced, weight: .regular).monospacedDigit()
    /// A HUD cell's value (SF Rounded, tabular, follows Dynamic Type from the title-2 size).
    static let hudValue = Font.system(.title2, design: .rounded, weight: .semibold).monospacedDigit()
    /// A small HUD panel's value, one step smaller.
    static let hudValueSmall = Font.system(.title3, design: .rounded, weight: .semibold).monospacedDigit()
    /// The number in the middle of the reticle (fixed: it sits inside a drawing of fixed size).
    static let hudCenter = Font.system(size: 40, weight: .semibold, design: .rounded).monospacedDigit()
}

public extension View {
    /// A HUD label: capitals and the HUD letter spacing (the font is the caller's, usually `hudLabel`).
    func noopHUDLabel() -> some View {
        textCase(.uppercase).tracking(NoopHUDStyle.labelTracking)
    }

    /// A HUD panel behind the content: the chamfered shape filled with the panel gradient, its one-point edge,
    /// and the two corner brackets on the uncut corners, in `accent` (the chrome by default).
    func noopHUDPanel(cut: CGFloat = NoopHUDStyle.cut, edge: Color = NoopHUDStyle.frame,
                      accent: Color = NoopHUDStyle.chrome, flat: Bool = false) -> some View {
        modifier(NoopHUDPanelModifier(cut: cut, edge: edge, accent: accent, flat: flat))
    }
}

/// A rectangle with its top-leading and bottom-trailing corners cut at 45°.
public struct NoopChamferShape: InsettableShape {
    public var cut: CGFloat
    private var inset: CGFloat = 0

    public init(cut: CGFloat = NoopHUDStyle.cut) {
        self.cut = cut
    }

    public func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        let c = max(0, min(cut, min(r.width, r.height) / 2))
        var p = Path()
        p.move(to: CGPoint(x: r.minX + c, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - c))
        p.addLine(to: CGPoint(x: r.maxX - c, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + c))
        p.closeSubpath()
        return p
    }

    public func inset(by amount: CGFloat) -> NoopChamferShape {
        var shape = self
        shape.inset += amount
        return shape
    }
}

/// The two brackets on a panel's uncut corners (top-trailing and bottom-leading), sitting just outside it.
public struct NoopHUDBrackets: Shape {
    public var length: CGFloat
    public var overhang: CGFloat

    public init(length: CGFloat = NoopHUDStyle.bracketLength, overhang: CGFloat = 4) {
        self.length = length
        self.overhang = overhang
    }

    public func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: -overhang, dy: -overhang)
        var p = Path()
        p.move(to: CGPoint(x: r.maxX - length, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + length))
        p.move(to: CGPoint(x: r.minX, y: r.maxY - length))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + length, y: r.maxY))
        return p
    }
}

/// `noopHUDPanel` itself.
struct NoopHUDPanelModifier: ViewModifier {
    let cut: CGFloat
    let edge: Color
    let accent: Color
    let flat: Bool

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    if flat {
                        NoopChamferShape(cut: cut).fill(NoopHUDStyle.panelFlat)
                    } else {
                        NoopChamferShape(cut: cut).fill(NoopHUDStyle.panel)
                    }
                    NoopChamferShape(cut: cut).strokeBorder(edge, lineWidth: 1)
                }
            }
            .overlay {
                NoopHUDBrackets()
                    .stroke(accent, style: StrokeStyle(lineWidth: NoopHUDStyle.bracketWidth, lineCap: .square))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
    }
}
