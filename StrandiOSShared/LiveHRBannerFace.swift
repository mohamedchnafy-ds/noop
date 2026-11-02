import SwiftUI
import StrandDesign

/// The live heart-rate banner's Lock Screen face (personal fork, chantier 6): the heart rate with its zone, and
/// beside it the one figure the wearer picked in the Live HR screen — the day's Effort with its bar, the morning's
/// Charge as a ring with the night's HRV, or the night's sleep with the debt and the suggested bedtime.
///
/// Plain values in, no ActivityKit: the widget extension draws it from the Live Activity's content, and
/// `StrandTests` compiles this same file to render it to PNG on macOS (`LiveHRBannerRenderTests`) — the check
/// against the mockup before an .ipa. Every word arrives already localized: the extension has no catalog.
struct LiveHRBannerFace: View {
    struct Side: Equatable {
        enum Kind: String {
            case effort, charge, sleep
        }

        var kind: Kind
        /// "Effort", "Charge", "Sleep".
        var label: String
        /// "38", "72", "6h 48m". Nil draws the dash.
        var value: String?
        /// "HRV 46 ms", "debt 1h 12m · bedtime 23:10".
        var detail: String?
        /// Effort's bar, 0…1.
        var fraction: Double?
        /// Charge's ring, 0…100.
        var score: Int?
    }

    /// "Live HR · zone 1".
    let subtitle: String
    let bpm: Int?
    let side: Side?

    /// The width of Effort's column and its bar, as drawn in the mockup.
    private static let effortWidth: CGFloat = 104

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "waveform.path.ecg")
                .font(.title2)
                .foregroundStyle(StrandPalette.statusCritical)
            VStack(alignment: .leading, spacing: 1) {
                Text(subtitle)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(bpm.map(String.init) ?? "–")
                        .font(StrandFont.rounded(26, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text("bpm")
                        .font(StrandFont.rounded(15, weight: .semibold))
                        .foregroundStyle(StrandPalette.textSecondary)
                }
            }
            Spacer(minLength: 8)
            if let side {
                sideView(side)
            }
        }
    }

    @ViewBuilder
    private func sideView(_ side: Side) -> some View {
        switch side.kind {
        case .effort:
            VStack(alignment: .trailing, spacing: 5) {
                overline(side.label)
                Text(side.value ?? "–")
                    .font(StrandFont.rounded(22, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(StrandPalette.effortBright)
                ZStack(alignment: .leading) {
                    Capsule().fill(StrandPalette.effortColor.opacity(0.22))
                    Capsule().fill(StrandPalette.effortColor)
                        .frame(width: Self.effortWidth * CGFloat(min(1, max(0, side.fraction ?? 0))))
                }
                .frame(width: Self.effortWidth, height: 6)
            }
            .frame(width: Self.effortWidth, alignment: .trailing)
        case .charge:
            HStack(spacing: 10) {
                VStack(alignment: .trailing, spacing: 2) {
                    overline(side.label)
                    if let detail = side.detail {
                        Text(detail)
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .lineLimit(1)
                    }
                }
                ZStack {
                    Circle()
                        .stroke(StrandPalette.chargeColor.opacity(0.18), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: CGFloat(min(100, max(0, side.score ?? 0))) / 100)
                        .stroke(StrandPalette.chargeColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(side.value ?? "–")
                        .font(StrandFont.rounded(15, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(StrandPalette.textPrimary)
                }
                .padding(3)
                .frame(width: 52, height: 52)
            }
        case .sleep:
            VStack(alignment: .trailing, spacing: 2) {
                overline(side.label)
                Text(side.value ?? "–")
                    .font(StrandFont.rounded(22, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(StrandPalette.restColor)
                if let detail = side.detail {
                    Text(detail)
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
    }

    private func overline(_ text: String) -> some View {
        Text(text)
            .font(StrandFont.rounded(11, weight: .regular))
            .tracking(1)
            .textCase(.uppercase)
            .foregroundStyle(StrandPalette.textSecondary)
            .lineLimit(1)
    }
}
