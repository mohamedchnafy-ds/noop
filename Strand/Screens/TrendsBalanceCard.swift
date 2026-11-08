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
//
// Motion: the quadrants and axes are a Swift Chart; the points are drawn OVER it (positioned through the
// chart's proxy) so each one can pop in on its own day's turn, oldest first, under one `NoopFirstDraw`.
// The tally chips and the sentence fade in once the last point has landed.
struct TrendsBalanceCard: View {
    let data: TrendsPeriodData

    private var points: [TrendsOverview.BalancePoint] { TrendsOverview.balancePoints(data.current) }

    var body: some View {
        let pts = points
        let tally = TrendsOverview.tally(pts)
        NoopFirstDraw(key: "\(data.entranceKey).balance", armed: data.animated) { phase in
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
                        chart(pts, phase: phase)
                            .frame(height: 250)
                    }
                    Group {
                        chips(tally)
                        Text(sentence(TrendsOverview.reading(pts)))
                            .font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .opacity(phase.drawn ? 1 : 0)
                    .animation(phase.motion(NoopMotion.strongEaseOut(0.5).delay(Self.pointsDuration(pts.count) + 0.1)),
                               value: phase.drawn)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: Entrance timing

    /// The gap between two points' entrances: 50 ms for a week, compressed so a quarter's 90 points still
    /// land inside about a second.
    private static func pointStagger(_ count: Int) -> Double {
        min(0.05, 1.0 / Double(max(count, 1)))
    }

    /// When the last point has landed.
    private static func pointsDuration(_ count: Int) -> Double {
        Double(max(count - 1, 0)) * pointStagger(count) + 0.45
    }

    // MARK: Chart

    private func chart(_ pts: [TrendsOverview.BalancePoint], phase: NoopDrawPhase) -> some View {
        let dense = pts.count > 31
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
        // The points, over the plot. Positioned by the chart's own scales so they land exactly where a
        // PointMark would, and animated as plain views so each pops in on its turn.
        .chartOverlay { proxy in
            GeometryReader { geo in
                let plot = proxy.plotRectCompat(in: geo)
                let stagger = Self.pointStagger(pts.count)
                ZStack(alignment: .topLeading) {
                    ForEach(Array(pts.enumerated()), id: \.element.day) { i, p in
                        if let x = proxy.position(forX: p.charge), let y = proxy.position(forY: p.effort) {
                            let isLatest = i == pts.count - 1
                            let size: CGFloat = isLatest ? 16 : (dense ? 8 : 12)
                            Circle()
                                .fill(StrandPalette.recoveryColor(p.charge).opacity(dense && !isLatest ? 0.75 : 1))
                                .overlay {
                                    if isLatest {
                                        Circle().strokeBorder(StrandPalette.textPrimary, lineWidth: 2.5)
                                    }
                                }
                                .frame(width: size, height: size)
                                .scaleEffect(phase.drawn ? 1 : 0.2)
                                .opacity(phase.drawn ? 1 : 0)
                                .animation(phase.motion(NoopMotion.strongEaseOut(0.45).delay(Double(i) * stagger)),
                                           value: phase.drawn)
                                .position(x: x + plot.minX, y: y + plot.minY)
                            if isLatest {
                                Text(latestLabel(p))
                                    .font(StrandFont.caption.weight(.semibold))
                                    .foregroundStyle(StrandPalette.textPrimary)
                                    .fixedSize()
                                    .opacity(phase.drawn ? 1 : 0)
                                    .animation(phase.motion(NoopMotion.strongEaseOut(0.4).delay(Double(i) * stagger + 0.25)),
                                               value: phase.drawn)
                                    .position(x: x + plot.minX + (p.charge < 60 ? 14 + labelHalfWidth(p) : -(14 + labelHalfWidth(p))),
                                              y: y + plot.minY)
                            }
                        }
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                .allowsHitTesting(false)
            }
        }
        .accessibilityLabel(Text("Charge and Effort of each day, as points in four quadrants"))
    }

    /// Half the label's width, estimated from its length so the label clears the ring without a layout pass.
    private func labelHalfWidth(_ p: TrendsOverview.BalancePoint) -> CGFloat {
        CGFloat(latestLabel(p).count) * 3.4
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
