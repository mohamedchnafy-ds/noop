import SwiftUI
import Charts
import StrandDesign

/// Titles and figures of a Coach chart, worded through the catalogue (fork chantier 9).
enum CoachChartText {
    /// "Heart Rate Variability · 30 days", "HRV & Asleep Time · 30 days", "Heart rate · 3 Nov".
    static func title(_ spec: CoachChartSpec) -> String {
        switch spec.kind {
        case .day:
            let date = CoachChart.dayDate(spec.day, calendar: .current)
                .map { $0.formatted(.dateTime.day().month(.abbreviated)) } ?? spec.day
            let what = spec.series == .stress ? String(localized: "Stress") : String(localized: "Heart rate")
            return what + " · " + date
        case .line, .bars:
            return (CoachChart.descriptor(spec.metric)?.title ?? "") + " · " + period(spec.days ?? 30)
        case .pair:
            let first = CoachChart.descriptor(spec.metric)?.title ?? ""
            let second = CoachChart.descriptor(spec.second)?.title ?? ""
            return first + " & " + second + " · " + period(spec.days ?? 30)
        }
    }

    /// "30 days", "1 year".
    static func period(_ days: Int) -> String {
        days == 365 ? String(localized: "1 year") : String(localized: "\(days) days")
    }
}

/// A chart under a Coach reply (fork chantier 9, Coach mockup « Conversation »): its title in the metric's
/// colour and « Analyses › » (the same series in Explore), the value in large — the last one with the mean,
/// or the touched point's — the chart itself, the first, middle and last dates, then the usual range and the
/// mean. The points are read by the screen (`AICoachEngine.chartPoints`), never written by the model.
struct CoachChartCard: View {
    let spec: CoachChartSpec
    /// Reads the points: the metric's (or the day's), and a pair's second metric's.
    let load: () async -> (first: [CoachChartPoint], second: [CoachChartPoint])

    @State private var first: [CoachChartPoint] = []
    @State private var second: [CoachChartPoint] = []
    @State private var loaded = false
    @State private var selected: Date?

    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.temperatureKey) private var temperatureRaw = ""
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue

    init(spec: CoachChartSpec, load: @escaping () async -> (first: [CoachChartPoint], second: [CoachChartPoint])) {
        self.spec = spec
        self.load = load
    }

    private var descriptor: MetricDescriptor? { CoachChart.descriptor(spec.metric) }
    private var secondDescriptor: MetricDescriptor? { CoachChart.descriptor(spec.second) }

    private var tint: Color {
        if spec.kind == .day {
            return spec.series == .stress ? StrandPalette.stressModerate : StrandPalette.liquidHeart
        }
        return descriptor.map(metricAccent) ?? StrandPalette.accent
    }

    private var secondTint: Color {
        let color = secondDescriptor.map(metricAccent) ?? StrandPalette.textSecondary
        return color == tint ? StrandPalette.textSecondary : color
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if !loaded {
                Color.clear.frame(height: 130)
            } else if first.isEmpty {
                Text("Nothing measured in this period.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            } else {
                readout
                chart.frame(height: 130)
                legend
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NoopPanelSurface(cornerRadius: NoopMetrics.cardRadius))
        .task(id: spec) {
            let points = await load()
            first = points.first
            second = points.second
            loaded = true
        }
    }

    // MARK: Header and readout

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: CoachChartText.title(spec))
                .font(StrandFont.subhead.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            if spec.kind != .day, let descriptor {
                NavigationLink {
                    MetricDetailView(metric: descriptor)
                } label: {
                    HStack(spacing: 3) {
                        Text("Analysis")
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                    }
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.accent)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// The touched point's value and date, or the last value with the mean.
    @ViewBuilder private var readout: some View {
        let point = selected.flatMap { CoachChart.nearest(first, to: $0) } ?? first.last
        if let point {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: format(point.value, descriptor))
                    .font(StrandFont.number(28, weight: .bold))
                    .foregroundStyle(StrandPalette.textPrimary)
                if spec.kind == .pair, let other = CoachChart.nearest(second, to: point.date) {
                    Text(verbatim: "· " + format(other.value, secondDescriptor))
                        .font(StrandFont.number(20, weight: .semibold))
                        .foregroundStyle(secondTint)
                }
                Text(verbatim: readoutLabel(point))
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    private func readoutLabel(_ point: CoachChartPoint) -> String {
        if selected != nil { return dateText(point.date) }
        guard let stats = CoachChart.stats(first.map(\.value)) else { return "" }
        return String(localized: "last · mean \(format(stats.mean, descriptor))")
    }

    // MARK: Chart

    private var chart: some View {
        let stats = CoachChart.stats(first.map(\.value))
        let pairFirst = spec.kind == .pair ? CoachChart.normalized(first) : first
        let pairSecond = spec.kind == .pair ? CoachChart.normalized(second) : []
        let axisFormat: Date.FormatStyle = spec.kind == .day ? .dateTime.hour().minute()
            : .dateTime.day().month(.abbreviated)
        return Chart {
            if spec.kind == .line, let stats, let start = first.first?.date, let end = first.last?.date, start < end {
                RectangleMark(xStart: .value("Start", start), xEnd: .value("End", end),
                              yStart: .value("Low", stats.low), yEnd: .value("High", stats.high))
                    .foregroundStyle(tint.opacity(0.16))
            }
            if spec.kind == .line || spec.kind == .bars, let stats {
                RuleMark(y: .value("Mean", stats.mean))
                    .foregroundStyle(StrandPalette.textSecondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            ForEach(Array(pairFirst.enumerated()), id: \.offset) { _, point in
                if spec.kind == .bars {
                    BarMark(x: .value("Day", point.date, unit: .day), y: .value("Value", point.value))
                        .foregroundStyle(tint)
                } else {
                    LineMark(x: .value("Day", point.date), y: .value("Value", point.value),
                             series: .value("Series", "first"))
                        .foregroundStyle(tint)
                        .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.monotone)
                }
            }
            ForEach(Array(pairSecond.enumerated()), id: \.offset) { _, point in
                LineMark(x: .value("Day", point.date), y: .value("Value", point.value),
                         series: .value("Series", "second"))
                    .foregroundStyle(secondTint)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }
            if let selected, let point = CoachChart.nearest(pairFirst, to: selected) {
                RuleMark(x: .value("Selected", point.date))
                    .foregroundStyle(StrandPalette.hairline)
                PointMark(x: .value("Selected", point.date), y: .value("Value", point.value))
                    .foregroundStyle(tint)
                    .symbolSize(60)
            }
        }
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisValueLabel(format: axisFormat)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                let plot = proxy.plotRectCompat(in: geo)
                // A tap reads the nearest point; tapping it again goes back to the last value. A tap, not a
                // drag, so the conversation still scrolls over the chart.
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { value in
                        guard let date: Date = proxy.value(atX: value.location.x - plot.minX) else { return }
                        let touched = CoachChart.nearest(first, to: date)?.date
                        let current = selected.flatMap { CoachChart.nearest(first, to: $0) }?.date
                        selected = touched == current ? nil : date
                    })
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: CoachChartText.title(spec)))
        .accessibilityValue(Text(verbatim: accessibilitySummary(stats)))
    }

    // MARK: Legend

    @ViewBuilder private var legend: some View {
        let stats = CoachChart.stats(first.map(\.value))
        HStack(spacing: 14) {
            switch spec.kind {
            case .line:
                if let stats {
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2).fill(tint.opacity(0.16)).frame(width: 12, height: 8)
                        Text("usual \(format(stats.low, descriptor, unit: false))–\(format(stats.high, descriptor, unit: false))")
                    }
                    Text("– – mean \(format(stats.mean, descriptor, unit: false))")
                }
            case .bars:
                if let stats { Text("– – mean \(format(stats.mean, descriptor, unit: false))") }
            case .pair:
                legendDot(tint, descriptor?.title ?? "")
                legendDot(secondTint, secondDescriptor?.title ?? "")
            case .day:
                if let stats {
                    Text("mean \(format(stats.mean, descriptor, unit: false)) · peak \(format(stats.highest, descriptor, unit: false))")
                }
            }
        }
        .font(StrandFont.caption)
        .foregroundStyle(StrandPalette.textSecondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private func legendDot(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(verbatim: title)
        }
    }

    // MARK: Formatting

    /// A value as Analyses writes it (units converted, Effort on its scale); a one-day chart's bpm or stress.
    private func format(_ value: Double, _ metric: MetricDescriptor?, unit: Bool = true) -> String {
        guard let metric else {
            if spec.series == .stress { return value.formatted(.number.precision(.fractionLength(1))) }
            let bpm = Int(value.rounded())
            return unit ? String(localized: "\(bpm) bpm") : "\(bpm)"
        }
        let system = UnitSystem(rawValue: unitSystemRaw) ?? .metric
        let temperature = UnitPrefs.resolveTemperature(system: system, override: temperatureRaw)
        let text = metric.format(value, system: system, temperature: temperature,
                                 effortScale: UnitPrefs.resolveEffortScale(effortScaleRaw))
        guard !unit else { return text }
        return text.split(separator: " ").first.map(String.init) ?? text
    }

    private func dateText(_ date: Date) -> String {
        spec.kind == .day ? AppClock.hourMinuteFormatter().string(from: date)
            : date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    private func accessibilitySummary(_ stats: CoachChart.Stats?) -> String {
        guard let stats else { return "" }
        return String(localized: "last \(format(stats.last, descriptor)), mean \(format(stats.mean, descriptor))")
    }
}
