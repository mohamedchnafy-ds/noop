import WidgetKit
import SwiftUI
import ActivityKit
import StrandDesign

/// Live Activity for an active live-HR session — shown on the Lock Screen and in the Dynamic Island.
struct NOOPLiveActivity: Widget {
    /// The heart rate to draw: none once iOS has marked the banner stale. Each push is fresh for 30 s
    /// (`LiveActivityController.staleAfter`) and NOOP re-pushes a steady number well inside that, so a stale banner
    /// means the readings stopped — the strap off the wrist, or out of reach — even while NOOP itself is asleep and
    /// cannot say so: iOS redraws the banner at the stale date on its own.
    static func shownBpm(_ context: ActivityViewContext<NOOPActivityAttributes>) -> Int? {
        context.isStale ? nil : context.state.bpm
    }

    /// The figure beside the bpm, for the face (personal fork). Nil for a banner started by an older build.
    static func side(_ state: NOOPActivityAttributes.ContentState) -> LiveHRBannerFace.Side? {
        guard let raw = state.sideKind, let kind = LiveHRBannerFace.Side.Kind(rawValue: raw),
              let label = state.sideLabel else { return nil }
        return LiveHRBannerFace.Side(kind: kind, label: label, value: state.sideValue, detail: state.sideDetail,
                                     fraction: state.effort.map { Double($0) / 100 }, score: state.recovery)
    }

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NOOPActivityAttributes.self) { context in
            // Lock Screen / banner presentation: the face the wearer chose the side of (personal fork), or the
            // original layout for a banner an older build started.
            if let side = Self.side(context.state) {
                LiveHRBannerFace(subtitle: context.state.subtitle ?? context.attributes.title,
                                 bpm: Self.shownBpm(context), side: side)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .activityBackgroundTint(StrandPalette.surfaceBase)
                    .activitySystemActionForegroundColor(StrandPalette.textPrimary)
            } else {
                legacyBanner(context)
                    .padding()
                    .activityBackgroundTint(StrandPalette.surfaceBase)
                    .activitySystemActionForegroundColor(StrandPalette.textPrimary)
            }
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("\(Self.shownBpm(context).map(String.init) ?? "–")", systemImage: "heart.fill")
                        .foregroundStyle(StrandPalette.statusCritical)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    // The figure the wearer chose (personal fork); Charge + Effort (#446) for an older banner.
                    if let side = Self.side(context.state) {
                        statColumn(label: side.label, value: side.value ?? "–")
                    } else {
                        HStack(spacing: 10) {
                            if let r = context.state.recovery {
                                statColumn(label: "Charge", value: "\(r)%")
                            }
                            if let e = context.state.effort {
                                statColumn(label: "Effort", value: "\(e)")
                            }
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.subtitle ?? context.attributes.title)
                        .font(.caption).foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: "heart.fill").foregroundStyle(StrandPalette.statusCritical)
            } compactTrailing: {
                Text("\(Self.shownBpm(context).map(String.init) ?? "–")")
            } minimal: {
                Image(systemName: "heart.fill").foregroundStyle(StrandPalette.statusCritical)
            }
        }
    }

    /// The banner as it was before the wearer could choose its side: Charge and Effort beside the bpm.
    private func legacyBanner(_ context: ActivityViewContext<NOOPActivityAttributes>) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "waveform.path.ecg")
                .font(.title2)
                .foregroundStyle(StrandPalette.statusCritical)
            VStack(alignment: .leading, spacing: 2) {
                Text(context.attributes.title)
                    .font(.caption).foregroundStyle(StrandPalette.textSecondary)
                Text("\(Self.shownBpm(context).map(String.init) ?? "–") bpm")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(StrandPalette.textPrimary)
            }
            Spacer()
            // Charge + Effort (#446) on the banner, mirroring the Dynamic Island expanded stats.
            HStack(spacing: 12) {
                if let r = context.state.recovery {
                    bannerStat(label: "Charge", value: "\(r)%")
                }
                if let e = context.state.effort {
                    bannerStat(label: "Effort", value: "\(e)")
                }
            }
        }
    }
}

/// Lock-Screen banner stat column (label over value). File-scope because the `ActivityConfiguration`
/// content closure isn't a method of `NOOPLiveActivity`.
///
/// #759 - the label and value are CENTRE-aligned so each value sits directly under its own label. The
/// old `.trailing` alignment right-pinned both to the column's edge: when the value was narrower than
/// the label (e.g. "12" under "Effort") it drifted to the label's right edge instead of under it, which
/// read as "the number doesn't line up with its label". `fixedSize` stops either line truncating so the
/// pairing is never clipped at narrow widths.
@ViewBuilder
private func bannerStat(label: String, value: String) -> some View {
    VStack(alignment: .center, spacing: 2) {
        Text(label).font(.caption2).foregroundStyle(StrandPalette.textSecondary)
        Text(value).font(.headline).foregroundStyle(StrandPalette.textPrimary)
    }
    .multilineTextAlignment(.center)
    .fixedSize()
}

/// Dynamic Island expanded-region stat column (label over value). File-scope for the same reason as
/// `bannerStat`. #759 - centre-aligned + `fixedSize` for the same value-under-its-label fix as the banner.
@ViewBuilder
private func statColumn(label: String, value: String) -> some View {
    VStack(alignment: .center, spacing: 1) {
        Text(label).font(.caption2).foregroundStyle(.secondary)
        Text(value).font(.headline)
    }
    .multilineTextAlignment(.center)
    .fixedSize()
}
