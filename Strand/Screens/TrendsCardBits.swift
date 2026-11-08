import SwiftUI
import StrandDesign

// MARK: - Small pieces shared by the Trends cards (fork chantier 16)

/// The ⓘ in a card header: a popover with one short paragraph on how the card is computed.
struct TrendsInfoButton: View {
    let label: LocalizedStringKey
    let text: LocalizedStringKey
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: {
            Image(systemName: "info.circle")
                .font(StrandFont.headline)
                .foregroundStyle(StrandPalette.textTertiary)
                .frame(width: NoopMetrics.compactControlSize, height: NoopMetrics.compactControlSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .popover(isPresented: $showing, arrowEdge: .top) {
            Text(text)
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(NoopMetrics.cardInnerPadding)
                .frame(maxWidth: 320)
                .background(NoopPanelSurface(cornerRadius: NoopVisualStyle.compactRadius, elevated: true))
                .trendsPopoverAdaptation()
        }
    }
}

/// A card header: overline + title on the left, the ⓘ on the right.
struct TrendsCardHeader: View {
    let title: LocalizedStringKey
    let overline: LocalizedStringKey
    var infoLabel: LocalizedStringKey? = nil
    var infoText: LocalizedStringKey? = nil

    var body: some View {
        HStack(alignment: .top, spacing: NoopMetrics.space2) {
            SectionHeader(title, overline: overline)
            Spacer(minLength: 0)
            if let infoLabel, let infoText {
                TrendsInfoButton(label: infoLabel, text: infoText)
            }
        }
    }
}

/// A row's track: the grey axis, the personal normal band as a tinted segment, and the period's reading
/// as a dot. Positions are 0…1 along the track (`TrendsOverview.axisPosition`); `bandRange` nil draws
/// the bare axis with the dot centred and grey, for a signal whose band is not yet claimable.
struct TrendsBandTrack: View {
    let position: Double
    let bandRange: ClosedRange<Double>?
    let bandTint: Color
    let dotColor: Color
    var height: CGFloat = 28

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(StrandPalette.surfaceOverlay)
                    .frame(height: 4)
                if let band = bandRange {
                    Capsule()
                        .fill(bandTint.opacity(0.22))
                        .frame(width: max(6, w * (band.upperBound - band.lowerBound)), height: 10)
                        .offset(x: w * band.lowerBound)
                }
                Circle()
                    .fill(dotColor)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().strokeBorder(StrandPalette.surfaceRaised, lineWidth: 2))
                    .offset(x: w * position - 7)
            }
            .frame(height: geo.size.height)
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// A heat cell of the day-by-day grid.
struct TrendsGridCell: View {
    let color: Color
    var selected = false

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(color)
            .frame(height: 26)
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(StrandPalette.textPrimary, lineWidth: 2)
                }
            }
    }
}

extension View {
    /// Keep a popover a popover in compact width (iOS 16.4+); a no-op on macOS where popovers never adapt.
    @ViewBuilder func trendsPopoverAdaptation() -> some View {
        #if os(iOS)
        if #available(iOS 16.4, *) { self.presentationCompactAdaptation(.popover) } else { self }
        #else
        self
        #endif
    }
}
