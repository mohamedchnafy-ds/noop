import SwiftUI
import StrandDesign

// MARK: - Élan · Lectures (personal fork, chantier 10, PR B)
//
// The readings tab: the daily reading at the head (it arrives with PR D; until then the card says so),
// the theme filters, then « Les essentiels », nine readings written once, offline, in French and English
// (`ElanEssentials.bundled`). A row pushes `ElanRoute.reading(id)`; an opened reading is marked read.

struct ElanReadTabView: View {
    let readings: [ElanReading]
    @Binding var filter: ElanReadingTheme?
    let readIds: Set<String>

    private var shown: [ElanReading] { ElanEssentials.essentials(readings, theme: filter) }
    private var language: String { ElanFormat.languageCode }

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.itemGap) {
            dailyCard
            filters
            Text("The essentials · readable offline")
                .font(StrandFont.footnote.weight(.medium))
                .foregroundStyle(StrandPalette.textSecondary)
                .padding(.horizontal, 4)
                .padding(.top, 4)
            essentialsCard
            Text("Written once from verified sources, kept on \(Platform.deviceNounPhrase). Not medical advice.")
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
    }

    // MARK: Daily reading (PR D)

    private var dailyCard: some View {
        NoopCard(padding: 18) {
            VStack(alignment: .leading, spacing: 6) {
                ElanSandLabel(text: Text("Daily reading"))
                Text("Coming with the next update")
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                Text("A reading chosen from your own data, written by the Coach from reliable sources, each one linked. Until then, the essentials below are yours.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Filters

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(Text("All"), selected: filter == nil) { filter = nil }
                ForEach(ElanReadingTheme.allCases, id: \.self) { theme in
                    chip(Text(verbatim: ElanFormat.themeName(theme)), selected: filter == theme) {
                        filter = filter == theme ? nil : theme
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func chip(_ label: Text, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(NoopMotion.value) { action() }
        } label: {
            label
                .font(StrandFont.subhead.weight(.semibold))
                .foregroundStyle(selected ? StrandPalette.surfaceBase : StrandPalette.textPrimary)
                .padding(.horizontal, 12)
                .frame(minHeight: 32)
                .background(selected ? StrandPalette.textPrimary : StrandPalette.surfaceInset, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(LiquidPressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Essentials

    @ViewBuilder
    private var essentialsCard: some View {
        NoopCard(padding: 0) {
            if shown.isEmpty {
                Group {
                    if readings.isEmpty {
                        Text("The essentials are missing from this build.")
                    } else {
                        Text("No essential on this theme yet.")
                    }
                }
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
                .padding(16)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, reading in
                        NavigationLink(value: ElanRoute.reading(reading.id)) {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(ElanFormat.themeColor(reading.theme))
                                    .frame(width: 10, height: 10)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: reading.title.text(languageCode: language))
                                        .font(StrandFont.body)
                                        .foregroundStyle(StrandPalette.textPrimary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    HStack(spacing: 4) {
                                        Text(verbatim: ElanFormat.themeName(reading.theme))
                                        Text(verbatim: "·")
                                        Text("\(reading.minutes) min")
                                        if readIds.contains(reading.id) {
                                            Text(verbatim: "·")
                                            Text("read")
                                        }
                                    }
                                    .font(StrandFont.footnote)
                                    .foregroundStyle(StrandPalette.textSecondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                if !readIds.contains(reading.id) {
                                    Circle().fill(StrandPalette.accent).frame(width: 8, height: 8)
                                        .accessibilityLabel(Text("unread"))
                                }
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(StrandPalette.textTertiary)
                                    .accessibilityHidden(true)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)
                            .frame(minHeight: 52)
                            .overlay(alignment: .bottom) {
                                if index < shown.count - 1 {
                                    Rectangle().fill(StrandPalette.hairline).frame(height: NoopMetrics.hairlineWidth)
                                        .padding(.leading, 38)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .staggeredAppear(index: index)
                    }
                }
            }
        }
    }
}
