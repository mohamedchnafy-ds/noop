import SwiftUI
import StrandDesign
import WhoopStore

// MARK: - Day by day (fork chantier 16)
//
// A heat grid: one column per day (week), per week (month, quarter) or per month (longer), one row per
// measure. Charge and Effort keep their own colours; HRV, resting HR and sleep are coloured by where the
// column's mean sits against the wearer's normal band (green better, grey inside, amber worse), so a
// bad stretch reads as an amber column without a curve. Replaces the single-metric year calendar.
// Tapping a column prints its values above the grid; the row labels say what each cell is.
struct TrendsGridCard: View {
    let data: TrendsPeriodData

    @State private var selected: Int?

    private var columns: [TrendsOverview.Column] {
        guard let w = data.window else {
            // All history: bucket by month over what is banked.
            guard let first = data.current.first?.day, let last = data.current.last?.day else { return [] }
            return TrendsOverview.columns(window: TrendsOverview.Window(start: first, end: last), bucket: .month)
        }
        return TrendsOverview.columns(window: w, bucket: TrendsOverview.bucket(for: data.range))
    }

    private var bucket: TrendsOverview.Bucket {
        data.window == nil ? .month : TrendsOverview.bucket(for: data.range)
    }

    private struct Line {
        let title: LocalizedStringKey
        /// The same word as `title`, already localized, for the composed selection line.
        let name: String
        let value: (DailyMetric) -> Double?
        let format: (Double) -> String
        /// nil: coloured by the value itself (Charge, Effort); else by deviation against the band.
        let higherIsBetter: Bool?
        let kind: Kind
        enum Kind { case charge, effort, signal }
    }

    private var lines: [Line] {
        [
            Line(title: "Charge", name: String(localized: "Charge"), value: { $0.recovery },
                 format: TrendsFormat.int, higherIsBetter: nil, kind: .charge),
            Line(title: "Effort", name: String(localized: "Effort"), value: { $0.strain },
                 format: { UnitFormatter.effortDisplay($0, scale: data.effortScale) }, higherIsBetter: nil, kind: .effort),
            Line(title: "HRV", name: String(localized: "HRV"), value: { $0.avgHrv },
                 format: { "\(TrendsFormat.int($0)) ms" }, higherIsBetter: true, kind: .signal),
            Line(title: "Resting HR", name: String(localized: "Resting HR"), value: { $0.restingHr.map(Double.init) },
                 format: { "\(TrendsFormat.int($0)) bpm" }, higherIsBetter: false, kind: .signal),
            Line(title: "Sleep", name: String(localized: "Sleep"), value: { $0.totalSleepMin },
                 format: { SleepDurationText.format($0) }, higherIsBetter: true, kind: .signal),
        ]
    }

    var body: some View {
        let cols = columns
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.cardInnerSpacing) {
                TrendsCardHeader(title: gridTitle, overline: "Tap a column to read it")
                if let i = selected, cols.indices.contains(i) {
                    selectionLine(cols[i])
                }
                if cols.isEmpty {
                    Text("Not enough data for this window.")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textTertiary)
                } else {
                    grid(cols)
                }
                Divider().overlay(StrandPalette.hairline)
                legend
            }
        }
        .onChange(of: data.window) { _ in selected = nil }
        .accessibilityElement(children: .contain)
    }

    private var gridTitle: LocalizedStringKey {
        switch bucket {
        case .day: return "Day by day"
        case .week: return "Week by week"
        case .month: return "Month by month"
        }
    }

    // MARK: Grid

    private func grid(_ cols: [TrendsOverview.Column]) -> some View {
        let bands = lines.map { line in
            line.kind == .signal ? TrendsOverview.band(data.bandDays.compactMap(line.value)) : nil
        }
        return Grid(alignment: .center, horizontalSpacing: cols.count > 13 ? 2 : 4, verticalSpacing: 4) {
            GridRow {
                Color.clear.frame(width: 1, height: 1)
                ForEach(cols.indices, id: \.self) { i in
                    Text(header(cols[i], index: i))
                        .font(StrandFont.caption2.weight(cols[i].end == data.today ? .bold : .semibold))
                        .foregroundStyle(cols[i].end == data.today ? StrandPalette.textPrimary : StrandPalette.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            ForEach(Array(lines.enumerated()), id: \.offset) { li, line in
                GridRow {
                    Text(line.title)
                        .font(StrandFont.footnote.weight(.semibold))
                        .foregroundStyle(StrandPalette.textPrimary)
                        .lineLimit(1)
                        .frame(width: 72, alignment: .leading)
                        .gridColumnAlignment(.leading)
                    ForEach(cols.indices, id: \.self) { ci in
                        let mean = TrendsOverview.columnMean(data.current, column: cols[ci], line.value)
                        Button { selected = selected == ci ? nil : ci } label: {
                            TrendsGridCell(color: cellColor(mean, line: line, band: bands[li]), selected: selected == ci)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(line.title))
                        .accessibilityValue(Text(mean.map(line.format) ?? String(localized: "No reading")))
                    }
                }
            }
        }
    }

    /// Column header: the weekday letter for days; the month, on the first week of each month; the month
    /// for months.
    private func header(_ col: TrendsOverview.Column, index: Int) -> String {
        switch bucket {
        case .day: return TrendsFormat.weekdayLetter(col.start)
        case .week: return (index == 0 || col.isMonthStart) ? TrendsFormat.shortMonth(col.end) : ""
        case .month: return TrendsFormat.shortMonth(col.start)
        }
    }

    private func cellColor(_ mean: Double?, line: Line, band: TrendsOverview.Band?) -> Color {
        guard let mean else { return StrandPalette.surfaceOverlay.opacity(0.5) }
        switch line.kind {
        case .charge:
            return StrandPalette.recoveryColor(mean)
        case .effort:
            return StrandPalette.effortColor.opacity(0.3 + 0.7 * min(max(mean / 100, 0), 1))
        case .signal:
            guard let band else { return StrandPalette.surfaceOverlay }
            switch TrendsOverview.deviation(mean, band: band) {
            case .inside: return StrandPalette.surfaceOverlay
            case .above: return (line.higherIsBetter ?? true) ? Self.better : Self.worse
            case .below: return (line.higherIsBetter ?? true) ? Self.worse : Self.better
            }
        }
    }

    private static var better: Color { StrandPalette.statusPositive.opacity(0.4) }
    private static var worse: Color { StrandPalette.metricAmber.opacity(0.45) }

    // MARK: Selection and legend

    /// The tapped column's values on one line: "Mon 2 Nov · Charge 92 · Effort 60 · …".
    private func selectionLine(_ col: TrendsOverview.Column) -> some View {
        let label: String = {
            switch bucket {
            case .day: return TrendsFormat.longDay(col.start)
            case .week, .month: return TrendsFormat.dateRange(TrendsOverview.Window(start: col.start, end: col.end))
            }
        }()
        let values = lines.compactMap { line -> String? in
            guard let m = TrendsOverview.columnMean(data.current, column: col, line.value) else { return nil }
            return "\(line.name) \(line.format(m))"
        }
        return Text(([label] + values).joined(separator: " · "))
            .font(StrandFont.captionNumber)
            .foregroundStyle(StrandPalette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            HStack(spacing: NoopMetrics.space4) {
                legendItem(Self.better, "better than your normal")
                legendItem(StrandPalette.surfaceOverlay, "inside")
                legendItem(Self.worse, "worse")
            }
            Group {
                if bucket == .day {
                    Text("Charge and Effort keep their colours; the three signals read against your normal. From a month on, a column is a week.")
                } else {
                    Text("Charge and Effort keep their colours; the three signals read against your normal.")
                }
            }
            .font(StrandFont.footnote)
            .foregroundStyle(StrandPalette.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func legendItem(_ color: Color, _ text: LocalizedStringKey) -> some View {
        HStack(spacing: NoopMetrics.space1 + 2) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 12, height: 12)
            Text(text)
        }
        .font(StrandFont.footnote)
        .foregroundStyle(StrandPalette.textTertiary)
    }
}
