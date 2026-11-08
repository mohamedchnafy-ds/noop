import SwiftUI
import Charts
import StrandDesign
import WhoopStore

// MARK: - Charge / Effort balance (fork chantier 16)
//
// Each day of the period as one point on the Charge (x) / Effort (y) plane, both on their stored 0–100
// scales, split at the midpoints into four quadrants. This is the relationship the two old line charts
// never showed side by side: did the hard days land on recovered days? Legible from a week of data,
// which is what a new wearer has. Points are coloured by Charge (the recovery ramp); the latest day
// carries a white ring and its date.
struct TrendsBalanceCard: View {
    let data: TrendsPeriodData

    private var points: [TrendsOverview.BalancePoint] { TrendsOverview.balancePoints(data.current) }

    var body: some View {
        let pts = points
        let tally = TrendsOverview.tally(pts)
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.cardInnerSpacing) {
                TrendsCardHeader(
                    title: "Charge / Effort balance", overline: "One point per day",
                    infoLabel: "How to read this chart",
                    infoText: "Each day is a point: Charge across, Effort up, both on their 0–100 scale and split at 50. Overreaching is a hard day on a low Charge; underused is a green Charge left unspent.")
                if pts.isEmpty {
                    Text("No day with both a Charge and an Effort in this period.")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
                        .background(NoopPanelSurface(cornerRadius: 12))
                } else {
                    chart(pts)
                        .frame(height: 250)
                }
                chips(tally)
                Text(sentence(TrendsOverview.reading(pts)))
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: Chart

    private func chart(_ pts: [TrendsOverview.BalancePoint]) -> some View {
        let dense = pts.count > 31
        let last = pts.last
        return Chart {
            quadrant(x: 0...50, y: 50...100, color: StrandPalette.metricRose, label: "Overreaching", alignment: .topLeading)
            quadrant(x: 50...100, y: 50...100, color: StrandPalette.chargeColor, label: "Optimal", alignment: .topTrailing)
            quadrant(x: 0...50, y: 0...50, color: StrandPalette.textSecondary, label: "Recovering", alignment: .bottomLeading)
            quadrant(x: 50...100, y: 0...50, color: StrandPalette.effortColor, label: "Underused", alignment: .bottomTrailing)
            RuleMark(x: .value("Charge", TrendsOverview.chargeThreshold))
                .foregroundStyle(StrandPalette.hairlineStrong)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
            RuleMark(y: .value("Effort", TrendsOverview.effortThreshold))
                .foregroundStyle(StrandPalette.hairlineStrong)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
            ForEach(pts, id: \.day) { p in
                PointMark(x: .value("Charge", p.charge), y: .value("Effort", p.effort))
                    .foregroundStyle(StrandPalette.recoveryColor(p.charge).opacity(dense ? 0.75 : 1))
                    .symbolSize(dense ? 36 : 90)
            }
            if let last {
                PointMark(x: .value("Charge", last.charge), y: .value("Effort", last.effort))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .symbolSize(190)
                PointMark(x: .value("Charge", last.charge), y: .value("Effort", last.effort))
                    .foregroundStyle(StrandPalette.recoveryColor(last.charge))
                    .symbolSize(100)
                    .annotation(position: last.charge < 60 ? .trailing : .leading, spacing: NoopMetrics.space2) {
                        Text(latestLabel(last))
                            .font(StrandFont.caption.weight(.semibold))
                            .foregroundStyle(StrandPalette.textPrimary)
                    }
            }
        }
        .chartXScale(domain: 0...100)
        .chartYScale(domain: 0...100)
        .chartXAxis {
            AxisMarks(values: [0.0, 50.0, 100.0]) { _ in
                AxisGridLine().foregroundStyle(StrandPalette.hairline)
                AxisValueLabel().foregroundStyle(StrandPalette.textTertiary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: [0.0, 50.0, 100.0]) { value in
                AxisGridLine().foregroundStyle(StrandPalette.hairline)
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(UnitFormatter.effortDisplay(v, scale: data.effortScale))
                            .foregroundStyle(StrandPalette.textTertiary)
                    }
                }
            }
        }
        .chartXAxisLabel(position: .bottom, alignment: .center) {
            Text("Charge").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
        }
        .chartYAxisLabel(position: .leading, alignment: .center) {
            Text("Effort").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
        }
        .accessibilityLabel(Text("Charge and Effort of each day, as points in four quadrants"))
    }

    @ChartContentBuilder
    private func quadrant(x: ClosedRange<Double>, y: ClosedRange<Double>, color: Color,
                          label: LocalizedStringKey, alignment: Alignment) -> some ChartContent {
        RectangleMark(xStart: .value("Charge", x.lowerBound), xEnd: .value("Charge", x.upperBound),
                      yStart: .value("Effort", y.lowerBound), yEnd: .value("Effort", y.upperBound))
            .foregroundStyle(color.opacity(0.10))
            .cornerRadius(8)
            .annotation(position: .overlay, alignment: alignment) {
                Text(label)
                    .font(StrandFont.caption2.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(color)
                    .padding(NoopMetrics.space2)
            }
    }

    /// "Today" for the current day, else the latest day's short date.
    private func latestLabel(_ p: TrendsOverview.BalancePoint) -> String {
        p.day == data.today ? String(localized: "Today") : TrendsFormat.longDay(p.day)
    }

    // MARK: Tally and sentence

    private func chips(_ tally: [TrendsOverview.Quadrant: Int]) -> some View {
        let cols = [GridItem(.adaptive(minimum: 150), spacing: NoopMetrics.space2)]
        return LazyVGrid(columns: cols, alignment: .leading, spacing: NoopMetrics.space2) {
            TrendChip(text: String(localized: "Optimal · \(tally[.optimal] ?? 0)"), color: StrandPalette.chargeColor)
            TrendChip(text: String(localized: "Overreaching · \(tally[.overreaching] ?? 0)"), color: StrandPalette.metricRose)
            TrendChip(text: String(localized: "Recovering · \(tally[.recovering] ?? 0)"), color: StrandPalette.textSecondary)
            TrendChip(text: String(localized: "Underused · \(tally[.underused] ?? 0)"), color: StrandPalette.effortColor)
        }
    }

    private func sentence(_ reading: TrendsOverview.BalanceReading) -> String {
        switch reading {
        case .tooFew:
            return String(localized: "Needs a few more days with both a Charge and an Effort.")
        case .overreaching(let days, let of):
            return String(localized: "\(days) of \(of) days pushed with a Charge under 50: a stretch to watch, not yet a habit.")
        case .underused(let days, let of):
            return String(localized: "\(days) of \(of) days left a green Charge unspent: room for one more session a week.")
        case .optimal(let days, let of):
            return String(localized: "\(days) of \(of) days placed the effort on a green Charge: the right reflex.")
        case .mixed:
            return String(localized: "Days are spread across the quadrants: no single pattern yet.")
        }
    }
}
