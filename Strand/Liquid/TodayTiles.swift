import SwiftUI
import StrandDesign

// MARK: - Liquid Today pieces (personal fork)
//
// The header, the start-session row, the Key-Metrics tile and the Your-Cards row of the Liquid Today as
// pure views: the screen wraps them in its links and buttons, and the render test draws the same views
// with the same tokens.

/// The header: the date on the left and the round controls on one line, then the day title (fork chantier 7:
/// no wordmark, no shadows). The controls are passed in (the screen's real ones, or stand-ins in the render
/// test).
struct TodayHeaderLayout<Controls: View>: View {
    var date: String
    var title: String
    var onTitleTap: () -> Void
    @ViewBuilder var controls: Controls

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: NoopMetrics.space2) {
                // The date is the one capitalised line the retained design keeps.
                Text(date)
                    .font(StrandFont.overline)
                    .textCase(.uppercase)
                    .foregroundStyle(StrandPalette.textSecondary)
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
                    .font(StrandFont.screenTitle)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentShape(Rectangle())
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.top, NoopMetrics.space1)
            .padding(.bottom, NoopMetrics.space1)
            .accessibilityLabel("\(title). Tap to pick a day, swipe to change day.")
        }
    }
}

/// The heart-rate card head (fork chantier 7): the rose title with its heart and chevron, then the Live |
/// Day selector, both inside the card. With `titleRoute` the title taps through (the selector stays a
/// separate control, never inside a link).
struct TodayHRSectionHead: View {
    @Binding var mode: TodayHRMode
    var liveEnabled: Bool
    var tint: Color = StrandPalette.liquidHeart
    var titleRoute: TabRoute? = nil

    private var title: some View {
        HStack(spacing: 6) {
            Image(systemName: "heart.fill")
                .font(.system(size: 15, weight: .semibold))
                .accessibilityHidden(true)
            Text("Heart rate")
                .font(StrandFont.headline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(StrandPalette.textSecondary)
                .accessibilityHidden(true)
        }
        .foregroundStyle(tint)
    }

    /// The title, as a link when the card has a route.
    @ViewBuilder
    private var titleLink: some View {
        if let titleRoute {
            NavigationLink(value: titleRoute) { title }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the full-day heart rate timeline")
        } else {
            title
        }
    }

    private var selector: some View {
        SegmentedPillControl([TodayHRMode.live, TodayHRMode.day], selection: $mode,
                             isEnabled: { $0 == .day || liveEnabled }) {
            $0 == .live ? String(localized: "Live") : String(localized: "Whole day")
        }
        .fixedSize()
    }

    var body: some View {
        // The whole title, never « Fréquence cardia… » (5 Nov.): beside the selector when both fit, else
        // the selector goes under it.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: NoopMetrics.space2) {
                titleLink.fixedSize()
                Spacer(minLength: NoopMetrics.space2)
                selector
            }
            VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                titleLink
                selector
            }
        }
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
            Text("Beta")
                .font(StrandFont.overlineScaled(11))
                .foregroundStyle(StrandPalette.textSecondary)
                .padding(.horizontal, 8).padding(.vertical, 2.5)
                .background(Capsule().fill(StrandPalette.surfaceInset))
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                .foregroundStyle(StrandPalette.textTertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(NoopPanelSurface(cornerRadius: NoopMetrics.cardRadius, surfaceOpacity: surfaceOpacity))
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
                Text(title).font(StrandFont.body.weight(.medium))
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(sub).font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
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
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(NoopPanelSurface(cornerRadius: NoopMetrics.cardRadius, surfaceOpacity: surfaceOpacity))
    }
}

/// One Key-Metrics tile (fork chantier 7): the coloured label with its icon, the value in SF Rounded with
/// its unit (or "no data"), an optional caveat and, in the detailed mode, the windowed trend.
struct LiquidKeyMetricTile: View {
    var label: String
    var icon: String
    var value: String
    var unit: String
    var tint: Color
    /// Kept for the callers; the retained design draws no fill bar.
    var frac: Double?
    var caption: String? = nil
    var detailed: Bool = false
    var spark: [Double] = []
    var surfaceOpacity: Double = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .accessibilityHidden(true)
                Text(label)
                    .font(StrandFont.overline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(tint)
            // Today v2: an absent value says so in words rather than as a dash.
            if LiquidTodayView.isNoValue(value) {
                Text("no data")
                    .font(StrandFont.body.weight(.medium))
                    .foregroundStyle(StrandPalette.textSecondary)
                    .lineLimit(1)
                    .frame(minHeight: 30, alignment: .leading)
            } else {
                Text(verbatim: LiquidTodayView.tileDisplayValue(value, unit: unit))
                    .font(StrandFont.rounded(24))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(minHeight: 30, alignment: .leading)
            }
            // Optional sub-value caveat (queue 11a): only ever set for an unvalidated candidate fallback.
            if let caption {
                Text(caption)
                    .font(StrandFont.caption2)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            // #430 parity: DETAILED tiles grow the trend graph; a metric with no windowed series keeps a
            // clear placeholder of the same height so every tile in a row stays level.
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
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: detailed ? 128 : 92, alignment: .topLeading)
        .background(NoopPanelSurface(cornerRadius: NoopMetrics.cardRadius, surfaceOpacity: surfaceOpacity))
    }
}
