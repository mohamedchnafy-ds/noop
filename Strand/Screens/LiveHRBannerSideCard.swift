import SwiftUI
import StrandDesign

/// The Live HR screen's choice of what the Lock Screen banner shows beside the bpm, outside a gym session
/// (personal fork, chantier 6): Effort, Charge or Sleep, one row each with what it shows. Pure — the choice and
/// what to do with a tap come in — so it renders to PNG for the visual check (`LiveHRBannerRenderTests`).
struct LiveHRBannerSideCard: View {
    let selection: LiveHRBannerSide
    let onPick: (LiveHRBannerSide) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Beside the bpm").strandOverline()
                Text("Lock Screen banner, outside a session")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            VStack(spacing: 0) {
                ForEach(Array(LiveHRBannerSide.allCases.enumerated()), id: \.element) { index, side in
                    Button { onPick(side) } label: { row(side) }
                        .buttonStyle(.plain)
                    if index < LiveHRBannerSide.allCases.count - 1 {
                        Rectangle()
                            .fill(StrandPalette.hairline)
                            .frame(height: 0.5)
                            .padding(.leading, 16)
                    }
                }
            }
            .background(StrandPalette.surfaceRaised,
                        in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
        }
    }

    private func row(_ side: LiveHRBannerSide) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(side.title)
                    .font(StrandFont.rounded(17, weight: .semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(side.explanation)
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if side == selection {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(StrandPalette.accent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .accessibilityAddTraits(side == selection ? [.isSelected] : [])
    }
}

/// The card with its choice stored (`LiveHRBannerSide.defaultsKey`), where the banner reads it.
struct LiveHRBannerSideSetting: View {
    @AppStorage(LiveHRBannerSide.defaultsKey) private var sideRaw = LiveHRBannerSide.effort.rawValue

    var body: some View {
        LiveHRBannerSideCard(selection: LiveHRBannerSide(rawValue: sideRaw) ?? .effort) { sideRaw = $0.rawValue }
    }
}
