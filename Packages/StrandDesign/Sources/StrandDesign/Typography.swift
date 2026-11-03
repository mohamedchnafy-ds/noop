import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Strand Typography (§9.2)
//
// Fork chantier 7 (Apple Fitness + Health direction): SF Pro (`.default`) for all text, SF Rounded only
// for numbers (`display`, `rounded`, `number`, `bodyNumber`, `captionNumber`). Tabular digits keep live
// metrics stable, while named text styles retain Dynamic Type scaling. SF Mono remains reserved for logs.
//
// All numeric styles use `.monospacedDigit()` so live values don't reflow.

public enum StrandFont {

    // MARK: Family

    private static func roundedSystem(_ size: CGFloat, weight: Font.Weight) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    private static func textSystem(_ size: CGFloat, weight: Font.Weight) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    // MARK: Scale (§9.2)

    /// Display 64–80 / Bold — the gauge score number. Helvetica Neue 700 with tight
    /// tracking (≈ -0.04em), tabular digits so a changing value never reflows.
    public static func display(_ size: CGFloat = 72) -> Font {
        roundedSystem(size, weight: .bold).monospacedDigit()
    }

    /// The tight tracking for big display numbers (≈ -0.04em). Apply alongside
    /// `display(_:)` at the use site, e.g. `.tracking(StrandFont.displayTracking(72))`.
    public static func displayTracking(_ size: CGFloat = 72) -> CGFloat {
        -size * 0.04
    }

    /// A Helvetica-Neue numeric style at an arbitrary size/weight — the house
    /// numeral. Tabular so live values align. Use anywhere a score/number is shown.
    public static func rounded(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        roundedSystem(size, weight: weight).monospacedDigit()
    }

    /// Title1 28 / Bold. Scales with Dynamic Type.
    public static let title1 = Font.system(.title, design: .default, weight: .bold)

    /// Title2 22 / Semibold. Scales with Dynamic Type.
    public static let title2 = Font.system(.title2, design: .default, weight: .semibold)

    /// Screen title 34 / Bold (large title). Scales with Dynamic Type.
    public static let screenTitle = Font.system(.largeTitle, design: .default, weight: .bold)

    /// Section title 20 / Bold, sentence case ("Métriques", "Synthèse"). Scales with Dynamic Type.
    public static let sectionTitle = Font.system(.title3, design: .default, weight: .bold)

    /// Headline 17 / Semibold. Scales with Dynamic Type.
    public static let headline = Font.system(.headline, design: .default, weight: .semibold)

    /// Body 15 / Regular. Scales with Dynamic Type.
    public static let body = Font.system(.body, design: .default, weight: .regular)

    /// Subhead 13. Scales with Dynamic Type.
    public static let subhead = Font.system(.subheadline, design: .default, weight: .regular)

    /// Caption 12. Scales with Dynamic Type.
    public static let caption = Font.system(.caption, design: .default, weight: .regular)

    /// Footnote 11. Scales with Dynamic Type.
    public static let footnote = Font.system(.footnote, design: .default, weight: .regular)

    /// Small label 13 / Semibold, sentence case (fork chantier 7: the spaced ALL-CAPS overline was
    /// retired). Scales with Dynamic Type relative to `.footnote` (13 pt on iOS).
    ///
    /// Also the face for compact status copy in constrained chrome (the Today header's sync capsule).
    public static let overline = Font.system(.footnote, design: .default, weight: .semibold)

    /// `overline` at a custom point size — same SF Pro face, weight and Dynamic-Type scaling
    /// (relativeTo `.footnote`). Lets a caller shrink a label to fit a small container without losing
    /// accessibility text-scaling.
    public static func overlineScaled(_ size: CGFloat) -> Font {
        #if canImport(UIKit)
        let base = UIFont.systemFont(ofSize: size, weight: .semibold)
        return Font(UIFontMetrics(forTextStyle: .footnote).scaledFont(for: base))
        #elseif canImport(AppKit)
        return Font(NSFont.systemFont(ofSize: size, weight: .semibold))
        #else
        return textSystem(size, weight: .semibold)
        #endif
    }

    /// Mono 13 (SF Mono) — raw / log views. Tabular by nature.
    public static let mono = Font.system(size: 13, weight: .regular, design: .monospaced)

    // MARK: Numeric variants (tabular digits)

    /// A numeric style at an arbitrary size/weight, for live values — Helvetica
    /// Neue, tabular digits. This is the tile/value numeral.
    public static func number(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        roundedSystem(size, weight: weight).monospacedDigit()
    }

    /// Helvetica-Neue body number — for inline live values that should align. Scales with Dynamic
    /// Type alongside its sibling `body`/`caption` labels so a value and its label stay matched.
    public static let bodyNumber = Font.system(.body, design: .rounded, weight: .medium).monospacedDigit()

    /// Helvetica-Neue caption number — for small live values (sparklines, chips). Scales with Dynamic Type.
    public static let captionNumber = Font.system(.caption, design: .rounded, weight: .medium).monospacedDigit()

    /// Mono at an arbitrary size.
    public static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// Tracking for overline text. Zero since the spaced ALL-CAPS overline was retired (fork chantier 7);
    /// kept so existing call sites compile and pick up the new look.
    public static let overlineTracking: CGFloat = 0
}

// MARK: - Text helpers

public extension Text {
    /// Style as a small label: 13 pt semibold, sentence case, secondary grey (fork chantier 7).
    func strandOverline() -> some View {
        self.font(StrandFont.overline)
            .foregroundStyle(StrandPalette.textSecondary)
    }
}

public extension View {
    /// Convenience: an overline-styled label string.
    static func strandOverline(_ string: String) -> some View {
        Text(string).strandOverline()
    }
}

#if DEBUG
#Preview("Typography") {
    ScrollView {
        VStack(alignment: .leading, spacing: 18) {
            Text("88").font(StrandFont.display(72)).tracking(StrandFont.displayTracking(72)).foregroundStyle(StrandPalette.textPrimary)
            Text("Title 1 / Bold 28").font(StrandFont.title1).foregroundStyle(StrandPalette.textPrimary)
            Text("Title 2 / Semibold 22").font(StrandFont.title2).foregroundStyle(StrandPalette.textPrimary)
            Text("Headline / Semibold 17").font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
            Text("Body / Regular 15 — the thread of you, read in full.")
                .font(StrandFont.body).foregroundStyle(StrandPalette.textPrimary)
            Text("Subhead 13").font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
            Text("Caption 12").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            Text("Footnote 11").font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
            Text("Overline").strandOverline()
            Text("0xAA 41 00 1c crc32=f3a1  mono 13").font(StrandFont.mono).foregroundStyle(StrandPalette.textSecondary)
            HStack(spacing: 4) {
                Text("HRV").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                Text("62").font(StrandFont.bodyNumber).foregroundStyle(StrandPalette.textPrimary)
                Text("ms").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(width: 520, height: 620)
    .background(StrandPalette.surfaceBase)
    .preferredColorScheme(.dark)
}
#endif
