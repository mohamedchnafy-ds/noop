import SwiftUI
import StrandDesign
import Foundation

// MARK: - The sheet of a measure (fork chantier 17, step 3)
//
// Opened by every tile of Today, every row of Signals in Trends and « Analysis › » in the Coach. Same engine
// and same period control as « My chart »: the number of the day, one sentence against the wearer's own band,
// the curve with that band behind it, three figures against the previous period, the three measures that
// move with this one, and the way into the editor. The measures with a screen of their own logic — steps,
// the estimated VO₂ max, skin temperature, Fitness Age — keep their former sheet (`MetricDetailLegacyView`).

/// Which measures keep the former sheet.
enum MetricDetailRouting {
    static let legacyKeys: Set<String> = ["steps", "steps_est", "skin_temp", "vo2max_est", "fitness_age"]

    static func usesLegacySheet(_ metric: MetricDescriptor) -> Bool {
        legacyKeys.contains(metric.key)
    }
}

/// The sheet every tap on a measure opens.
struct MetricDetailView: View {
    let metric: MetricDescriptor

    var body: some View {
        if MetricDetailRouting.usesLegacySheet(metric) {
            MetricDetailLegacyView(metric: metric)
        } else {
            MetricSheetView(metric: metric)
        }
    }
}

/// The measures a sheet offers as « what moves with this one », by `MetricDescriptor.id`.
private let metricSheetNeighbours = [
    "my-whoop:recovery", "my-whoop:hrv", "my-whoop:rhr", "my-whoop:sleep_total_min", "my-whoop:strain",
    "my-whoop:stress", "my-whoop:sleep_performance",
]

/// A neighbour measure and how strongly it moves with the one shown.
private struct RelatedRow: Identifiable {
    let metric: MetricDescriptor
    let r: Double
    var id: String { metric.id }
}

struct MetricSheetView: View {
    let metric: MetricDescriptor
    @EnvironmentObject var repo: Repository
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.temperatureKey) private var temperatureRaw = ""
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    @StateObject private var data = MyChartData()
    @State private var period: MyChartPeriod = .quarter
    @State private var offset = 0
    @State private var showReadings = false

    private var format: MyChartFormat {
        MyChartFormat(systemRaw: unitSystemRaw, temperatureRaw: temperatureRaw, effortRaw: effortScaleRaw)
    }

    private var color: Color { metricAccent(metric) }

    private var neighbours: [MetricDescriptor] {
        metricSheetNeighbours.filter { $0 != metric.id }.compactMap { MyChartCatalog.metric($0) }
    }

    private var model: MyChartModel {
        MyChartModel(items: [MyChartItem(metricID: metric.id)], period: period, offset: offset,
                     normalized: false, data: data.series)
    }

    private var periodBinding: Binding<MyChartPeriod> {
        Binding(get: { period }, set: { period = $0; offset = 0 })
    }

    /// The readings of the shown period, day by day.
    private func windowReadings(_ window: MyChartWindow) -> [MyChartDayValue] {
        (data.series[metric.id] ?? []).filter { $0.day >= window.start && $0.day <= window.end }
    }

    var body: some View {
        let current = model
        let readings = windowReadings(current.window)
        ScreenScaffold(title: nil) {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                header(readings)
                periodRow(current)
                chartCard(current, readings: readings)
                figures(current, readings: readings)
                related(current)
                actions
            }
        }
        .noopEntranceRoot()
        .task(id: metric.id + "|\(repo.refreshSeq)") {
            await data.load([metric.id] + metricSheetNeighbours, repo: repo)
        }
    }

    // MARK: Header

    private func header(_ readings: [MyChartDayValue]) -> some View {
        let band = MyChartEngine.personalBand(readings.map(\.value))
        let latest = readings.last
        return VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: MyChartCatalog.name(metric.id))
                    .font(StrandFont.screenTitle)
                    .foregroundStyle(color)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                TrendsInfoButton(
                    label: "About this measure",
                    text: "Your usual band is your average give or take half a standard deviation over the period. Press and hold the chart, then slide, to read a day.")
            }
            if let latest {
                Text(verbatim: format.text(latest.value, metricID: metric.id))
                    .font(StrandFont.number(48, weight: .bold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(verbatim: phrase(latest, band: band))
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
            } else {
                Text("Nothing measured in this period.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
        }
    }

    private func phrase(_ latest: MyChartDayValue, band: (mean: Double, low: Double, high: Double)?) -> String {
        let date = MyChartDates.axis(Double(latest.day), wide: false)
        guard let band else { return date }
        if latest.value > band.high { return String(localized: "\(date) · above your usual band") }
        if latest.value < band.low { return String(localized: "\(date) · below your usual band") }
        return String(localized: "\(date) · within your usual band")
    }

    // MARK: Period

    private func periodRow(_ current: MyChartModel) -> some View {
        let earliest = data.series[metric.id]?.first?.day ?? 0
        let canStepBack = current.window.start > earliest
        return VStack(spacing: NoopMetrics.space2) {
            SegmentedPillControl(MyChartPeriod.allCases.filter { $0 != .all }, selection: periodBinding,
                                 adaptsToAvailableWidth: true, fillsAvailableWidth: true) { $0.label }
            HStack {
                stepButton("chevron.left", label: "Previous period", enabled: canStepBack) { offset += 1 }
                Spacer(minLength: 0)
                Text(verbatim: MyChartDates.range(current.window.start, current.window.end))
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                Spacer(minLength: 0)
                stepButton("chevron.right", label: "Next period", enabled: offset > 0) { offset -= 1 }
            }
        }
    }

    private func stepButton(_ symbol: String, label: LocalizedStringKey, enabled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button {
            StrandHaptic.selection.play()
            action()
        } label: {
            Image(systemName: symbol)
                .font(StrandFont.headline.weight(.semibold))
                .frame(width: NoopMetrics.controlHeight - 4, height: NoopMetrics.controlHeight - 4)
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? StrandPalette.accent : StrandPalette.textTertiary)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    // MARK: Chart

    private func chartCard(_ current: MyChartModel, readings: [MyChartDayValue]) -> some View {
        let band = MyChartEngine.personalBand(readings.map(\.value))
        return NoopCard {
            if current.hasData {
                MyChartPlotBlock(model: current, format: format, entranceKey: "sheet.\(metric.id)",
                                 animated: true, height: 210, showsAxes: true, holdDuration: 0.12,
                                 accessibilityName: MyChartCatalog.name(metric.id),
                                 band: band.map { (low: $0.low, high: $0.high, mean: $0.mean) })
            } else {
                Text("Nothing measured in this period.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            }
        }
    }

    // MARK: Figures

    private func figures(_ current: MyChartModel, readings: [MyChartDayValue]) -> some View {
        let values = readings.map(\.value)
        let span = current.window.end - current.window.start + 1
        let before = (data.series[metric.id] ?? []).filter {
            $0.day >= current.window.start - span && $0.day < current.window.start
        }.map(\.value)
        let mean = values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        let previous = before.count >= 5 ? before.reduce(0, +) / Double(before.count) : nil
        return NoopCard {
            VStack(spacing: 0) {
                if let mean {
                    figureRow("Average", value: format.text(mean, metricID: metric.id), delta: delta(mean, previous))
                }
                if let low = values.min() {
                    Divider().overlay(StrandPalette.hairline)
                    figureRow("Lowest", value: format.text(low, metricID: metric.id), delta: nil)
                }
                if let high = values.max() {
                    Divider().overlay(StrandPalette.hairline)
                    figureRow("Highest", value: format.text(high, metricID: metric.id), delta: nil)
                }
                if previous != nil {
                    Text("Against the previous period")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, NoopMetrics.space2)
                }
            }
        }
    }

    private func delta(_ now: Double, _ previous: Double?) -> (text: String, color: Color)? {
        guard let previous else { return nil }
        let diff = now - previous
        guard abs(diff) > 1e-9 else { return nil }
        let shown = metric.formatDelta(abs(diff), system: format.system, temperature: format.temperature,
                                       effortScale: format.effortScale)
        let number = shown.split(separator: " ").first.map(String.init) ?? shown
        var tint = StrandPalette.textSecondary
        if let better = metric.higherIsBetter {
            tint = ((diff > 0) == better) ? StrandPalette.statusPositive : StrandPalette.statusCritical
        }
        return (text: (diff > 0 ? "+" : "−") + number, color: tint)
    }

    private func figureRow(_ title: LocalizedStringKey, value: String, delta: (text: String, color: Color)?) -> some View {
        HStack {
            Text(title)
                .font(StrandFont.body)
                .foregroundStyle(StrandPalette.textPrimary)
            Spacer(minLength: 8)
            Text(verbatim: value)
                .font(StrandFont.number(17, weight: .semibold))
                .foregroundStyle(StrandPalette.textPrimary)
            if let delta {
                Text(verbatim: delta.text)
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(delta.color)
            }
        }
        .padding(.vertical, 11)
    }

    // MARK: What moves with it

    private func relatedRows(_ current: MyChartModel) -> [RelatedRow] {
        let mine = data.series[metric.id] ?? []
        var found: [RelatedRow] = []
        for other in neighbours {
            if let r = MyChartEngine.correlation(mine, data.series[other.id] ?? [],
                                                 lower: current.window.start, upper: current.window.end) {
                found.append(RelatedRow(metric: other, r: r))
            }
        }
        return Array(found.sorted { abs($0.r) > abs($1.r) }.prefix(3))
    }

    @ViewBuilder private func related(_ current: MyChartModel) -> some View {
        let rows = relatedRows(current)
        if !rows.isEmpty {
            NoopCard {
                VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                    Text(verbatim: String(localized: "What moves with \(MyChartCatalog.name(metric.id))"))
                        .font(StrandFont.headline)
                        .foregroundStyle(StrandPalette.textPrimary)
                    ForEach(rows) { row in
                        NavigationLink {
                            MyChartView(preset: pair(with: row.metric))
                        } label: {
                            relatedRow(row.metric, r: row.r)
                        }
                        .buttonStyle(.plain)
                    }
                    Text("Tap a line to see both together.")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
            }
        }
    }

    private func relatedRow(_ other: MetricDescriptor, r: Double) -> some View {
        let tint = metricAccent(other)
        return HStack(spacing: NoopMetrics.space3) {
            Text(verbatim: MyChartCatalog.name(other.id))
                .font(StrandFont.body)
                .foregroundStyle(StrandPalette.textPrimary)
                .frame(width: 110, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            GeometryReader { geo in
                let half = geo.size.width / 2
                ZStack(alignment: .leading) {
                    Capsule().fill(StrandPalette.surfaceOverlay).frame(height: 6)
                    Capsule().fill(tint)
                        .frame(width: max(3, half * CGFloat(min(1, abs(r)))), height: 6)
                        .offset(x: r >= 0 ? half : half - half * CGFloat(min(1, abs(r))))
                    Rectangle().fill(StrandPalette.textTertiary).frame(width: 1, height: 10).offset(x: half)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 18)
            Text(verbatim: signed(r))
                .font(StrandFont.number(15, weight: .semibold))
                .foregroundStyle(StrandPalette.textSecondary)
                .frame(width: 48, alignment: .trailing)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private func signed(_ r: Double) -> String {
        (r >= 0 ? "+" : "−") + abs(r).formatted(.number.precision(.fractionLength(2)).locale(AppLanguage.activeLocale))
    }

    /// This measure and another, on the editor's two axes, over the period shown here.
    private func pair(with other: MetricDescriptor) -> MyChartSpec {
        let sameUnit = other.unit == metric.unit
        var spec = MyChartSpec.fresh(name: MyChartCatalog.name(metric.id) + " · " + MyChartCatalog.name(other.id),
                                     metricID: metric.id)
        spec.items.append(MyChartItem(metricID: other.id, kind: .line, axis: sameUnit ? .left : .right))
        spec.period = period
        return spec
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: NoopMetrics.space3) {
            NavigationLink {
                MyChartView(preset: single)
            } label: {
                Text("Open in My chart")
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.surfaceBase)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(StrandPalette.textPrimary))
            }
            .buttonStyle(.plain)
            DisclosureGroup(isExpanded: $showReadings) {
                readingsList
            } label: {
                Text("Readings")
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
            }
            .tint(StrandPalette.textSecondary)
        }
    }

    private var single: MyChartSpec {
        var spec = MyChartSpec.fresh(name: MyChartCatalog.name(metric.id), metricID: metric.id)
        spec.period = period
        return spec
    }

    private var readingsList: some View {
        let rows = Array((data.series[metric.id] ?? []).suffix(30).reversed())
        return VStack(spacing: 0) {
            ForEach(rows, id: \.day) { row in
                HStack {
                    Text(verbatim: MyChartDates.full(Double(row.day)))
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                    Spacer()
                    Text(verbatim: format.text(row.value, metricID: metric.id))
                        .font(StrandFont.number(15, weight: .semibold))
                        .foregroundStyle(StrandPalette.textPrimary)
                }
                .padding(.vertical, 8)
                Divider().overlay(StrandPalette.hairline)
            }
        }
    }
}
