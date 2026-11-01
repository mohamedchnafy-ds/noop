import SwiftUI
import StrandDesign

// MARK: - Liquid Today pieces (personal fork)
//
// The header, the start-session row, the Key-Metrics tile and the Your-Cards row of the Liquid Today as
// pure views: the screen wraps them in its links and buttons, and the render test draws the same views
// with the same tokens.

/// The header: the date on the left and the round controls on one line, then the day title, then the NOOP
/// wordmark. The controls are passed in (the screen's real ones, or stand-ins in the render test).
struct TodayHeaderLayout<Controls: View>: View {
    var date: String
    var title: String
    var onTitleTap: () -> Void
    @ViewBuilder var controls: Controls

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: NoopMetrics.space2) {
                Text(date)
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .shadow(color: .black.opacity(0.35), radius: 8, y: 1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .layoutPriority(-1)
                Spacer(minLength: NoopMetrics.space2)
                controls
                    .fixedSize()
                    .zIndex(1)
            }
            Button(action: onTitleTap) {
                Text(title)
                    .font(StrandFont.rounded(34))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .shadow(color: .black.opacity(0.4), radius: 10, y: 1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentShape(Rectangle())
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.top, NoopMetrics.space1)
            .accessibilityLabel("\(title). Tap to pick a day, swipe to change day.")
            // Subtle NOOP wordmark between header and hero, with a tap easter egg.
            LiquidWordmark()
                .padding(.top, 18)
                .padding(.bottom, 14)
        }
    }
}

/// The heart-rate section head: the overline and the Live | Day selector (the Sleep tab's control).
struct TodayHRSectionHead: View {
    @Binding var mode: TodayHRMode
    var liveEnabled: Bool

    var body: some View {
        HStack(alignment: .center) {
            Text("HEART RATE").font(StrandFont.overline).tracking(1.6)
                .foregroundStyle(StrandPalette.textTertiary)
            Spacer()
            SegmentedPillControl([TodayHRMode.live, TodayHRMode.day], selection: $mode,
                                 isEnabled: { $0 == .day || liveEnabled }) {
                $0 == .live ? String(localized: "Live") : String(localized: "Whole day")
            }
            .fixedSize()
        }
        .padding(.horizontal, 2)
        .padding(.top, 4)
    }
}

/// The one-tap Live Session entry (silent guardian, beta), as a label for the screen's button.
struct LiquidSessionStartRow: View {
    var surfaceOpacity: Double = 1

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(StrandPalette.metricCyan)
            // Theme-aware session-start chrome (#1160 parity): NoopPanelSurface + normal text tokens.
            Text("Start session")
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textPrimary)
            Text("BETA")
                .font(StrandFont.overlineScaled(8.5)).tracking(1.2)
                .foregroundStyle(StrandPalette.textSecondary)
                .padding(.horizontal, 8).padding(.vertical, 2.5)
                .background(Capsule().fill(StrandPalette.surfaceInset.opacity(0.72))
                    .overlay(Capsule().strokeBorder(
                        StrandPalette.hairline,
                        lineWidth: NoopMetrics.hairlineWidth
                    )))
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                .foregroundStyle(StrandPalette.textTertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(NoopPanelSurface(cornerRadius: 18, surfaceOpacity: surfaceOpacity))
    }
}

/// One Your-Cards row: a small vessel, the title and subtitle, the value (or "no data") and a chevron.
struct LiquidCardRow: View {
    var title: String
    var sub: String
    var value: String
    var tint: Color
    var frac: Double?
    var surfaceOpacity: Double = 1

    var body: some View {
        HStack(spacing: 12) {
            // tapPassesThrough: the vessel's splash gesture would otherwise swallow the enclosing
            // Button's tap, leaving a dead 30pt disc on the leading edge of a tappable card row.
            LiquidVessel(value: frac, tint: tint, animated: false, tapPassesThrough: true)
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(title.uppercased()).font(StrandFont.overlineScaled(11)).tracking(1.0)
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(sub).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
            }
            Spacer(minLength: 8)
            // Today v2: an absent value says so in words rather than as a dash.
            if LiquidTodayView.isNoValue(value) {
                Text("no data").font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
            } else {
                Text(value).font(StrandFont.number(17)).foregroundStyle(StrandPalette.textPrimary)
            }
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                .foregroundStyle(StrandPalette.textTertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(NoopPanelSurface(tint: tint, cornerRadius: 20, surfaceOpacity: surfaceOpacity))
    }
}

/// One Key-Metrics tile: icon and caps label, the value with its unit (or "no data"), an optional caveat,
/// the fill bar and, in the detailed mode, the windowed trend.
struct LiquidKeyMetricTile: View {
    var label: String
    var icon: String
    var value: String
    var unit: String
    var tint: Color
    var frac: Double?
    var caption: String? = nil
    var detailed: Bool = false
    var spark: [Double] = []
    var surfaceOpacity: Double = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint.opacity(0.72))
                    .frame(width: 14)
                Text(label.uppercased())
                    .font(StrandFont.overlineScaled(10))
                    .tracking(1.0)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            // Today v2: an absent value says so in words rather than as a dash.
            if LiquidTodayView.isNoValue(value) {
                Text("no data")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .lineLimit(1)
                    .frame(minHeight: 29, alignment: .leading)
            } else {
                Text(verbatim: LiquidTodayView.tileDisplayValue(value, unit: unit))
                    .font(StrandFont.number(24))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            // Optional sub-value caveat (queue 11a): only ever set for an unvalidated candidate fallback.
            if let caption {
                Text(caption)
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            LiquidTube(frac: frac ?? 0, tint: tint, height: 9, animated: false,
                       showsHighlight: false, usesCleanFill: true)
            // #430 parity: DETAILED tiles grow the trend graph under the bar; a metric with no windowed
            // series keeps a clear placeholder of the same height so every tile in a row stays level.
            if detailed {
                if spark.count >= 2 {
                    Sparkline(values: spark,
                              gradient: Gradient(colors: [tint.opacity(0.5), tint]))
                        .frame(height: 22)
                        .padding(.top, 6)
                        .accessibilityHidden(true)
                } else {
                    Color.clear.frame(height: 22).padding(.top, 6)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: detailed ? 154 : 116, alignment: .topLeading)
        .background(NoopPanelSurface(tint: tint, cornerRadius: 18, surfaceOpacity: surfaceOpacity))
    }
}
