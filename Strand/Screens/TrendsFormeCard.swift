import SwiftUI
import Charts
import StrandDesign
import StrandAnalytics
import WhoopStore

// MARK: - Forme: fitness · fatigue · form (fork chantier 16)
//
// The Banister fitness–fatigue read of the wearer's daily Effort: chronic load over 42 days
// ("fitness", what the body is used to), acute load over 7 ("fatigue", what it just did), and their
// difference ("form"). The page's only line chart. Below it, the acute / chronic workload ratio with its
// 0.8–1.3 zone and Foster's training monotony, both from `ReadinessEngine`, which already computes them.
//
// Descriptive only, like the card it replaces: nothing here feeds a score. The model runs over the FULL
// history (chronic load is a 42-day horizon by nature) and the chart frames the chosen period; below the
// engine's 14 contiguous days the card stays compact and says how many days are still needed.
struct TrendsFormeCard: View {
    let days: [DailyMetric]
    let window: TrendsOverview.Window?

    /// Cached model + readiness, keyed on the same fingerprint `TrainingLoadCard` used: a full-history
    /// EWMA and the Readiness synthesis must not re-run on every redraw.
    @State private var cacheKey = ""
    @State private var result = TrainingLoadEngine.evaluate(days: [])
    @State private var acwr: Double?
    @State private var monotony: Double?

    private static let minimumDays = TrainingLoadEngine.Configuration.standard.minimumDays

    var body: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.cardInnerSpacing) {
                TrendsCardHeader(
                    title: "Form", overline: "Fitness · Fatigue · Form",
                    infoLabel: "How it is computed",
                    infoText: "Fitness is your Effort averaged over 42 days (what you can absorb); fatigue over 7 days (what you just did). Form is fitness minus fatigue. The acute / chronic ratio compares the last 7 days with the last 28: between 0.8 and 1.3 the load builds without outrunning you.")
                if result.isAvailable {
                    tiles
                    chart
                        .frame(height: 190)
                    Divider().overlay(StrandPalette.hairline)
                    ratioRows
                } else {
                    tilesPlaceholder
                    building
                }
            }
        }
        .onAppear(perform: refresh)
        .onChange(of: TrainingLoadCard.modelKey(for: days)) { _ in refresh() }
        .accessibilityElement(children: .contain)
    }

    private func refresh() {
        let key = TrainingLoadCard.modelKey(for: days)
        guard key != cacheKey else { return }
        cacheKey = key
        let loads = days.map { TrainingLoadEngine.DailyLoad(day: $0.day, load: $0.strain) }
        result = TrainingLoadEngine.evaluate(days: loads)
        let readiness = ReadinessEngine.evaluate(days: days)
        acwr = readiness.acwr
        monotony = readiness.monotony
    }

    // MARK: Tiles

    private var tiles: some View {
        HStack(spacing: NoopMetrics.space2) {
            tile(title: "Fitness", swatch: StrandPalette.effortColor,
                 value: result.ctl.map(TrendsFormat.int) ?? "—", caption: String(localized: "42 days"))
            tile(title: "Fatigue", swatch: StrandPalette.metricAmber,
                 value: result.atl.map(TrendsFormat.int) ?? "—", caption: String(localized: "7 days"))
            tile(title: "Form", swatch: formColor.opacity(0.5),
                 value: result.tsb.map { TrendsFormat.signed($0) } ?? "—",
                 caption: formCaption, valueColor: formColor)
        }
    }

    private var tilesPlaceholder: some View {
        HStack(spacing: NoopMetrics.space2) {
            tile(title: "Fitness", swatch: StrandPalette.textTertiary, value: "—",
                 caption: String(localized: "42 days"), valueColor: StrandPalette.textTertiary)
            tile(title: "Fatigue", swatch: StrandPalette.textTertiary, value: "—",
                 caption: String(localized: "7 days"), valueColor: StrandPalette.textTertiary)
            tile(title: "Form", swatch: StrandPalette.textTertiary, value: "—",
                 caption: String(localized: "the gap"), valueColor: StrandPalette.textTertiary)
        }
    }

    private func tile(title: LocalizedStringKey, swatch: Color, value: String, caption: String,
                      valueColor: Color = StrandPalette.textPrimary) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.spaceHalf) {
            HStack(spacing: NoopMetrics.space1 + 2) {
                Capsule().fill(swatch).frame(width: 10, height: 3)
                Text(title).font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
            }
            Text(value)
                .font(StrandFont.number(28, weight: .bold))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(caption).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary).lineLimit(1)
        }
        .padding(NoopMetrics.space3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NoopPanelSurface(cornerRadius: 14))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text("\(value), \(caption)"))
    }

    /// Form reads in the load's own units: ten points under is fresh fatigue, ten over is fresh legs.
    private static let formBand = 10.0

    private var formColor: Color {
        guard let tsb = result.tsb else { return StrandPalette.textTertiary }
        if tsb <= -Self.formBand { return StrandPalette.metricAmber }
        if tsb >= Self.formBand { return StrandPalette.chargeColor }
        return StrandPalette.textPrimary
    }

    private var formCaption: String {
        guard let tsb = result.tsb else { return String(localized: "the gap") }
        if tsb <= -Self.formBand { return String(localized: "fresh fatigue") }
        if tsb >= Self.formBand { return String(localized: "fresh legs") }
        return String(localized: "balanced")
    }

    // MARK: Chart

    private struct Row: Identifiable {
        let date: Date
        let ctl: Double
        let atl: Double
        var id: Date { date }
        var low: Double { min(ctl, atl) }
        var high: Double { max(ctl, atl) }
        var positive: Bool { ctl >= atl }
    }

    /// The modelled points inside the period (all of the last 42 when the period holds fewer than two).
    private var rows: [Row] {
        let inWindow = result.points.filter { p in
            guard let w = window else { return true }
            return p.day >= w.start && p.day <= w.end
        }
        let chosen = inWindow.count >= 2 ? inWindow : Array(result.points.suffix(42))
        return chosen.compactMap { p in
            guard let d = TrendsFormat.date(p.day) else { return nil }
            return Row(date: d, ctl: p.chronicLoad, atl: p.acuteLoad)
        }
    }

    private var chart: some View {
        let rs = rows
        let maxY = max(rs.map(\.high).max() ?? 1, 1)
        return Chart {
            // Form as the area between the two lines: green where condition leads, amber where fatigue
            // does. Two series so each keeps its colour; the seam at a crossing is a one-day gap.
            ForEach(rs.filter(\.positive)) { r in
                AreaMark(x: .value("Day", r.date), yStart: .value("Low", r.low), yEnd: .value("High", r.high),
                         series: .value("Form", "positive"))
                    .foregroundStyle(StrandPalette.chargeColor.opacity(0.18))
                    .interpolationMethod(.monotone)
            }
            ForEach(rs.filter { !$0.positive }) { r in
                AreaMark(x: .value("Day", r.date), yStart: .value("Low", r.low), yEnd: .value("High", r.high),
                         series: .value("Form", "negative"))
                    .foregroundStyle(StrandPalette.metricAmber.opacity(0.26))
                    .interpolationMethod(.monotone)
            }
            ForEach(rs) { r in
                LineMark(x: .value("Day", r.date), y: .value("Condition", r.ctl), series: .value("Series", "ctl"))
                    .foregroundStyle(StrandPalette.effortColor)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.monotone)
            }
            ForEach(rs) { r in
                LineMark(x: .value("Day", r.date), y: .value("Fatigue", r.atl), series: .value("Series", "atl"))
                    .foregroundStyle(StrandPalette.metricAmber)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.monotone)
            }
            if let last = rs.last {
                PointMark(x: .value("Day", last.date), y: .value("Condition", last.ctl))
                    .foregroundStyle(StrandPalette.effortColor).symbolSize(50)
                PointMark(x: .value("Day", last.date), y: .value("Fatigue", last.atl))
                    .foregroundStyle(StrandPalette.metricAmber).symbolSize(50)
            }
        }
        .chartYScale(domain: 0...(maxY * 1.1))
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(StrandPalette.hairline)
                AxisValueLabel().foregroundStyle(StrandPalette.textTertiary)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated)).foregroundStyle(StrandPalette.textTertiary)
            }
        }
        .accessibilityLabel(Text("Fitness and fatigue over the period; the form is the gap between them"))
    }

    // MARK: Ratio and monotony

    /// Axis 0…2 for the acute / chronic ratio; the green zone 0.8–1.3 as the band.
    private static let ratioAxisMax = 2.0
    private static let ratioZone = 0.8...1.3

    private var ratioRows: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            HStack(alignment: .firstTextBaseline) {
                Text("Acute / chronic ratio")
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                Spacer(minLength: NoopMetrics.space2)
                Text(acwr.map { UnitFormatter.decimal($0, places: 2) } ?? "—")
                    .font(StrandFont.number(17, weight: .bold))
                    .foregroundStyle(ratioColor)
            }
            if let acwr {
                TrendsBandTrack(position: min(0.97, max(0.03, acwr / Self.ratioAxisMax)),
                                bandRange: (Self.ratioZone.lowerBound / Self.ratioAxisMax)...(Self.ratioZone.upperBound / Self.ratioAxisMax),
                                bandTint: StrandPalette.chargeColor, dotColor: ratioColor, height: 22)
                GeometryReader { geo in
                    let w = geo.size.width
                    Text(verbatim: UnitFormatter.decimal(Self.ratioZone.lowerBound, places: 1))
                        .position(x: w * Self.ratioZone.lowerBound / Self.ratioAxisMax, y: 6)
                    Text(verbatim: UnitFormatter.decimal(Self.ratioZone.upperBound, places: 1))
                        .position(x: w * Self.ratioZone.upperBound / Self.ratioAxisMax, y: 6)
                }
                .frame(height: 12)
                .font(StrandFont.caption2)
                .foregroundStyle(StrandPalette.textTertiary)
                .accessibilityHidden(true)
            }
            Text(ratioSentence)
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var ratioColor: Color {
        guard let acwr else { return StrandPalette.textTertiary }
        return Self.ratioZone.contains(acwr) ? StrandPalette.chargeColor : StrandPalette.metricAmber
    }

    private var ratioSentence: String {
        var parts: [String] = []
        if let acwr {
            if acwr < Self.ratioZone.lowerBound {
                parts.append(String(localized: "Below the green zone (0.8–1.3): the load is light against your base."))
            } else if acwr > Self.ratioZone.upperBound {
                parts.append(String(localized: "Above the green zone (0.8–1.3): the acute load is outrunning your base."))
            } else {
                parts.append(String(localized: "In the green zone (0.8–1.3)."))
            }
        } else {
            parts.append(String(localized: "The ratio needs 14 days of Effort."))
        }
        if let monotony {
            let m = UnitFormatter.decimal(monotony, places: 1)
            if monotony < 1.5 {
                parts.append(String(localized: "Monotony \(m): varied weeks."))
            } else if monotony < 2.0 {
                parts.append(String(localized: "Monotony \(m): fairly repetitive weeks."))
            } else {
                parts.append(String(localized: "Monotony \(m): repetitive weeks, vary the days."))
            }
        }
        return parts.joined(separator: " ")
    }

    // MARK: Building state

    private var building: some View {
        let have = min(result.contiguousDays, Self.minimumDays)
        let need = Self.minimumDays
        return VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            HStack(alignment: .firstTextBaseline) {
                Text("Building")
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                Spacer(minLength: NoopMetrics.space2)
                Text("\(have) / \(need) days")
                    .font(StrandFont.captionNumber)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            HStack(spacing: NoopMetrics.space1) {
                ForEach(0..<need, id: \.self) { i in
                    Capsule()
                        .fill(i < have ? StrandPalette.effortColor : StrandPalette.surfaceOverlay)
                        .frame(height: 8)
                }
            }
            .accessibilityHidden(true)
            Text(buildingSentence(remaining: need - have))
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func buildingSentence(remaining: Int) -> String {
        let more = remaining == 1
            ? String(localized: "1 more consecutive day of Effort.")
            : String(localized: "\(remaining) more consecutive days of Effort.")
        return more + " " + String(localized: "Then: your fitness over 42 days, your fatigue over 7, and the form between them, with the acute / chronic ratio.")
    }
}
