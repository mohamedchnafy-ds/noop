import SwiftUI
import StrandDesign
import WhoopStore

// MARK: - Bilan (fork chantier 16)
//
// The three scores — Charge, Effort, Rest — once, as period means in their gauges, each with its change
// against the previous period, and one sentence on how Charge and Effort moved together. Replaces the
// old digest gauges AND the "Week in review" pip card, which printed the same three numbers twice.
struct TrendsBilanCard: View {
    let data: TrendsPeriodData
    /// "vs previous week" — what the deltas are measured against.
    let comparisonLabel: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var drawn = false

    private var charge: Double? { TrendsOverview.mean(data.current) { $0.recovery } }
    private var effort: Double? { TrendsOverview.mean(data.current) { $0.strain } }
    private var rest: Double? { TrendsOverview.mean(data.current) { data.rest($0) } }
    private var previousCharge: Double? { TrendsOverview.mean(data.previous) { $0.recovery } }
    private var previousEffort: Double? { TrendsOverview.mean(data.previous) { $0.strain } }
    private var previousRest: Double? { TrendsOverview.mean(data.previous) { data.rest($0) } }

    var body: some View {
        let chargeChange = TrendsOverview.change(current: charge, previous: previousCharge)
        let effortChange = TrendsOverview.change(current: effort, previous: previousEffort)
        let restChange = TrendsOverview.change(current: rest, previous: previousRest)
        let reading = TrendsOverview.bilanReading(chargeDelta: chargeChange?.delta,
                                                  effortDelta: effortChange?.delta,
                                                  previousDays: data.previous.count)
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.cardInnerSpacing) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Summary · period means").strandOverline()
                    Spacer(minLength: NoopMetrics.space2)
                    if !comparisonLabel.isEmpty {
                        Text(comparisonLabel)
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textTertiary)
                            .lineLimit(1)
                    }
                }
                HStack(alignment: .top, spacing: NoopMetrics.space2) {
                    gauge(title: "Charge", domain: .charge, value: charge, change: chargeChange,
                          higherIsBetter: true, number: { TrendsFormat.int($0) })
                    gauge(title: "Effort", domain: .effort, value: effort, change: effortChange,
                          higherIsBetter: nil, number: { UnitFormatter.effortDisplay($0, scale: data.effortScale) })
                    gauge(title: "Rest", domain: .rest, value: rest, change: restChange,
                          higherIsBetter: true, number: { TrendsFormat.int($0) })
                }
                Divider().overlay(StrandPalette.hairline)
                HStack(alignment: .top, spacing: NoopMetrics.space3) {
                    Image(systemName: "sparkles")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.accent)
                        .accessibilityHidden(true)
                    Text(sentence(reading))
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onAppear {
            withAnimation(StrandMotion.drawIn(reduced: reduceMotion)) { drawn = true }
        }
        .accessibilityElement(children: .contain)
    }

    /// One score: its gauge (the stored 0–100 value as the fill), the domain-coloured name, and the
    /// change chip. The gauge's number follows the Effort scale toggle; its fill does not, so the three
    /// arcs read against the same scale (#268).
    @ViewBuilder
    private func gauge(title: LocalizedStringKey, domain: DomainTheme, value: Double?,
                       change: TrendsOverview.Change?, higherIsBetter: Bool?,
                       number: (Double) -> String) -> some View {
        let fraction = min(max((value ?? 0) / 100, 0), 1)
        let diameter: CGFloat = dynamicTypeSize.isAccessibilitySize ? 104 : 84
        VStack(spacing: NoopMetrics.space2) {
            BevelGauge(fraction: fraction,
                       stops: domain.gradient.stops,
                       tipColor: domain.bright,
                       numberText: value.map(number) ?? "—",
                       diameter: diameter,
                       lineWidth: NoopMetrics.space2,
                       showsLabel: value != nil,
                       animatedFraction: drawn ? fraction : 0)
            Text(title)
                .font(StrandFont.subhead.weight(.semibold))
                .foregroundStyle(domain.color)
                .lineLimit(1)
            if let change, let percent = change.percent {
                TrendChip(text: TrendsFormat.signedPercent(percent),
                          color: TrendsFormat.changeColor(change.delta, higherIsBetter: higherIsBetter))
            } else {
                // Keep the three columns the same height when one score has no previous period to
                // compare with: an empty chip-sized slot, not a jump in the row.
                Color.clear.frame(height: 22)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(accessibilityValue(value: value, change: change, number: number)))
    }

    private func accessibilityValue(value: Double?, change: TrendsOverview.Change?,
                                    number: (Double) -> String) -> String {
        guard let value else { return String(localized: "No reading") }
        guard let change, let percent = change.percent else { return number(value) }
        return "\(number(value)), \(TrendsFormat.signedPercent(percent)) \(comparisonLabel)"
    }

    private func sentence(_ reading: TrendsOverview.BilanReading) -> String {
        switch reading {
        case .noPrevious:
            return String(localized: "No earlier period to compare with yet.")
        case .sparsePrevious(let days):
            return days == 1
                ? String(localized: "The previous period only has 1 day of data, so the changes are rough, not a trend.")
                : String(localized: "The previous period only has \(days) days of data, so the changes are rough, not a trend.")
        case .bothUp:
            return String(localized: "Charge and Effort both rose: you are absorbing the extra training.")
        case .loadUpChargeDown:
            return String(localized: "Effort rose while Charge fell: recovery is lagging behind the load.")
        case .loadDownChargeUp:
            return String(localized: "Less Effort, more Charge: you recovered.")
        case .bothDown:
            return String(localized: "Charge and Effort both fell: a quieter stretch.")
        case .steady:
            return String(localized: "Steady against the previous period.")
        }
    }
}
