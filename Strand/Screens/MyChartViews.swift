import SwiftUI
import StrandDesign
import Foundation

// MARK: - My chart, the views (fork chantier 17, step 3)
//
// Mockup « Mon graphique » (validated 10 Nov.): one engine (`MyChart.swift`) behind three surfaces — the
// card under Stress on Today (`MyChartCard`), the full-screen editor (`MyChartView`) and, in a later step,
// the metric sheet. The plot is a `Canvas`: every measure is drawn on its own axis (left or right, flipped
// or not, auto / from zero / fixed), each at a height already resolved by the engine, so the same code
// draws one curve, four mixed kinds, or four shapes compared on 0–100 %.

// MARK: Colours

/// One colour per measure, the same on Today, in Trends, in the Coach's charts and in this editor. Measures
/// without a colour of their own keep the category tint `metricAccent` gives them.
enum MeasureColor {
    static func tint(for metric: MetricDescriptor) -> Color? {
        switch metric.key {
        case "recovery": return StrandPalette.chargeColor
        case "strain": return StrandPalette.effortColor
        case "sleep_performance", "sleep_total_min", "sleep_deep_min", "sleep_rem_min", "sleep_light_min",
             "sleep_efficiency", "sleep_consistency", "restorative_pct", "restorative_min",
             "hours_vs_needed_pct", "in_bed_min", "sleep_need_min":
            return StrandPalette.restRing
        case "hrv": return StrandPalette.metricCyan
        case "rhr": return StrandPalette.liquidHeart
        case "stress": return StrandPalette.stressModerate
        case "weight": return StrandPalette.elanSand
        case "calories_in": return StrandPalette.caloriesResting
        case "protein_g": return StrandPalette.macroProtein
        case "carbs_g": return StrandPalette.macroCarbs
        case "fat_g": return StrandPalette.macroFat
        case "steps", "steps_est": return StrandPalette.caloriesActivity
        default: return nil
        }
    }
}

// MARK: Catalogue, data and formatting

enum MyChartCatalog {
    static func metric(_ id: String) -> MetricDescriptor? {
        MetricCatalog.all.first { $0.id == id }
    }

    /// The name a measure carries on the chart (the short heart-metric names of the Coach's cards).
    static func name(_ id: String) -> String {
        guard let metric = metric(id) else { return id }
        return CoachChartText.name(metric)
    }

    /// The colour of every measure of a chart; a second measure that lands on a colour already used takes a
    /// lighter shade of it.
    static func colors(_ items: [MyChartItem]) -> [String: Color] {
        var out: [String: Color] = [:]
        var used: [Color] = []
        for item in items {
            var color = metric(item.metricID).map(metricAccent) ?? StrandPalette.accent
            if used.contains(color) { color = color.opacity(0.6) }
            used.append(color)
            out[item.metricID] = color
        }
        return out
    }
}

/// Reads the daily series a chart draws, once per data refresh.
@MainActor
final class MyChartData: ObservableObject {
    @Published private(set) var series: [String: [MyChartDayValue]] = [:]
    private var loadedIDs: Set<String> = []
    private var loadedSeq = -1

    func load(_ ids: [String], repo: Repository) async {
        if loadedSeq != repo.refreshSeq {
            loadedIDs = []
            loadedSeq = repo.refreshSeq
        }
        var next = series
        var changed = false
        for id in ids where !loadedIDs.contains(id) {
            guard let metric = MyChartCatalog.metric(id) else { continue }
            let rows = await repo.exploreSeries(key: metric.key, source: metric.source, fullHistory: true)
            guard !Task.isCancelled else { return }
            var readings: [MyChartDayValue] = []
            for row in rows {
                if let day = MyChartEngine.dayNumber(row.day) { readings.append((day: day, value: row.value)) }
            }
            readings.sort { $0.day < $1.day }
            next[id] = readings
            loadedIDs.insert(id)
            changed = true
        }
        if changed || series.isEmpty { series = next }
    }
}

/// A value written as Analyses writes it: units converted, Effort on its scale.
struct MyChartFormat {
    let system: UnitSystem
    let temperature: TemperatureUnit
    let effortScale: EffortScale

    init(systemRaw: String, temperatureRaw: String, effortRaw: String) {
        let system = UnitSystem(rawValue: systemRaw) ?? .metric
        self.system = system
        self.temperature = UnitPrefs.resolveTemperature(system: system, override: temperatureRaw)
        self.effortScale = UnitPrefs.resolveEffortScale(effortRaw)
    }

    func text(_ value: Double, metricID: String) -> String {
        guard let metric = MyChartCatalog.metric(metricID) else {
            return value.formatted(.number.precision(.fractionLength(1)))
        }
        return metric.format(value, system: system, temperature: temperature, effortScale: effortScale)
    }

    /// An axis label: the number alone, on the Effort scale chosen.
    func tick(_ value: Double, step: Double, metricID: String) -> String {
        if MyChartCatalog.metric(metricID)?.key == "strain" {
            return UnitFormatter.effortDisplay(value, scale: effortScale)
        }
        let digits = step < 1 ? 1 : 0
        return value.formatted(.number.precision(.fractionLength(digits)).locale(AppLanguage.activeLocale))
    }
}

/// Dates on the chart, in the app's language.
enum MyChartDates {
    private static var formatters: [String: DateFormatter] = [:]

    private static func formatter(_ template: String) -> DateFormatter {
        let locale = AppLanguage.activeLocale
        let key = locale.identifier + "|" + template
        if let cached = formatters[key] { return cached }
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = TimeZone(identifier: "UTC")
        f.setLocalizedDateFormatFromTemplate(template)
        formatters[key] = f
        return f
    }

    /// « 9 Nov », or « Nov 25 » over a long span.
    static func axis(_ day: Double, wide: Bool) -> String {
        formatter(wide ? "MMM yy" : "d MMM").string(from: MyChartEngine.dateOfDay(day: day))
    }

    /// « Mon, 9 Nov ».
    static func full(_ day: Double) -> String {
        formatter("EEE d MMM").string(from: MyChartEngine.dateOfDay(day: day))
    }

    /// « 12 Aug – 9 Nov ».
    static func range(_ lower: Int, _ upper: Int) -> String {
        axis(Double(lower), wide: false) + " – " + axis(Double(upper), wide: false)
    }
}

extension MyChartPeriod {
    var label: String {
        switch self {
        case .week: return String(localized: "W")
        case .month: return String(localized: "M")
        case .quarter: return String(localized: "3M")
        case .half: return String(localized: "6M")
        case .year: return String(localized: "1Y")
        case .all: return String(localized: "ALL")
        }
    }
}

extension MyChartKind {
    var label: String {
        switch self {
        case .line: return String(localized: "Line")
        case .bars: return String(localized: "Bars")
        case .area: return String(localized: "Area")
        case .points: return String(localized: "Points")
        }
    }
}

extension MyChartAxis {
    var label: String {
        switch self {
        case .left: return String(localized: "Left axis")
        case .right: return String(localized: "Right axis")
        }
    }
}

extension MyChartScale {
    var label: String {
        switch self {
        case .auto: return String(localized: "Auto")
        case .zero: return String(localized: "From 0")
        case .fixed: return String(localized: "Fixed")
        }
    }
}

/// What a chart draws once its items, period, zoom and the data are known.
struct MyChartModel {
    let window: MyChartWindow
    let series: [MyChartResolved]
    let left: MyChartAxisDomain?
    let right: MyChartAxisDomain?
    let bucket: Int
    let colors: [String: Color]
    let normalized: Bool

    var hasData: Bool { series.contains { !$0.points.isEmpty } }

    init(items: [MyChartItem], period: MyChartPeriod, offset: Int = 0, zoom: ClosedRange<Double> = 0...1,
         normalized: Bool, data: [String: [MyChartDayValue]]) {
        let today = MyChartEngine.dayNumber(Repository.logicalDayKey(Date())) ?? 0
        let earliest = items.compactMap { data[$0.metricID]?.first?.day }.min()
        let w = MyChartEngine.periodWindow(period: period, offset: offset, zoom: zoom, today: today, earliest: earliest)
        let r = MyChartEngine.resolveSeries(items: items, data: data, lower: w.lower, upper: w.upper,
                                            normalized: normalized)
        self.window = w
        self.series = r.series
        self.left = r.left
        self.right = r.right
        self.bucket = r.bucket
        self.colors = MyChartCatalog.colors(items)
        self.normalized = normalized
    }
}

// MARK: Plot

/// The chart itself: a grid, the axes' numbers, the dates, and each measure in its kind. A press and a slide
/// reads a day (`cursor`); lifting the finger puts the last values back.
struct MyChartPlot: View {
    let model: MyChartModel
    let format: MyChartFormat
    var showsAxes = true
    var holdDuration = 0.18
    /// The wearer's normal band (a measure's sheet): drawn behind the curve, with the mean dashed.
    var band: (low: Double, high: Double, mean: Double)?
    @Binding var cursor: Double?

    init(model: MyChartModel, format: MyChartFormat, showsAxes: Bool = true, holdDuration: Double = 0.18,
         band: (low: Double, high: Double, mean: Double)? = nil, cursor: Binding<Double?>) {
        self.model = model
        self.format = format
        self.showsAxes = showsAxes
        self.holdDuration = holdDuration
        self.band = band
        self._cursor = cursor
    }

    private let top: CGFloat = 8
    private let bottom: CGFloat = 20
    private var side: CGFloat { showsAxes ? 36 : 4 }

    var body: some View {
        let lower = model.window.lower
        let upper = model.window.upper
        let wide = upper - lower > 200
        let dates = (MyChartDates.axis(Double(lower), wide: wide),
                     MyChartDates.axis(Double(lower + upper) / 2, wide: wide),
                     MyChartDates.axis(Double(upper), wide: wide))
        GeometryReader { geo in
            Canvas { context, size in
                drawPlot(&context, size, dates: dates)
            }
            .contentShape(Rectangle())
            .gesture(readGesture(width: geo.size.width))
        }
    }

    // MARK: Drawing

    private func drawPlot(_ context: inout GraphicsContext, _ size: CGSize, dates: (String, String, String)) {
        let plot = CGRect(x: side, y: top, width: max(1, size.width - 2 * side),
                          height: max(1, size.height - top - bottom))
        let lower = Double(model.window.lower)
        let span = Double(max(1, model.window.upper - model.window.lower))
        func px(_ day: Double) -> CGFloat { plot.minX + CGFloat((day - lower) / span) * plot.width }
        func py(_ fraction: Double) -> CGFloat { plot.maxY - CGFloat(fraction) * plot.height }

        // Grid: the first axis' ticks, or quarters when the shapes are compared.
        var gridFractions: [Double] = [0, 0.25, 0.5, 0.75, 1]
        if !model.normalized, let domain = model.left ?? model.right {
            let ticks = MyChartEngine.axisTicks(lower: domain.lower, upper: domain.upper)
            gridFractions = ticks.values.map { domain.height($0) }
        } else if model.normalized {
            gridFractions = [0, 0.5, 1]
        }
        for fraction in gridFractions {
            var line = Path()
            line.move(to: CGPoint(x: plot.minX, y: py(fraction)))
            line.addLine(to: CGPoint(x: plot.maxX, y: py(fraction)))
            context.stroke(line, with: .color(StrandPalette.hairline), lineWidth: 1)
        }

        // Axis numbers, tinted by the measure that leads each axis.
        if showsAxes {
            if model.normalized {
                drawLabel(&context, MyChartPlot.percent(100), at: CGPoint(x: plot.minX - 6, y: py(1)), anchor: .trailing,
                          color: StrandPalette.textTertiary)
                drawLabel(&context, MyChartPlot.percent(0), at: CGPoint(x: plot.minX - 6, y: py(0)), anchor: .trailing,
                          color: StrandPalette.textTertiary)
            } else {
                for (domain, isLeft) in [(model.left, true), (model.right, false)] {
                    guard let domain else { continue }
                    let ticks = MyChartEngine.axisTicks(lower: domain.lower, upper: domain.upper)
                    let color = (model.colors[domain.leadMetricID] ?? StrandPalette.textSecondary).opacity(0.9)
                    for value in ticks.values {
                        let text = format.tick(value, step: ticks.step, metricID: domain.leadMetricID)
                        let point = CGPoint(x: isLeft ? plot.minX - 6 : plot.maxX + 6, y: py(domain.height(value)))
                        drawLabel(&context, text, at: point, anchor: isLeft ? .trailing : .leading, color: color)
                    }
                }
            }
        }

        // The dates, first / middle / last.
        let dateY = size.height - 8
        drawLabel(&context, dates.0, at: CGPoint(x: plot.minX, y: dateY), anchor: .leading, color: StrandPalette.textTertiary)
        drawLabel(&context, dates.1, at: CGPoint(x: plot.midX, y: dateY), anchor: .center, color: StrandPalette.textTertiary)
        drawLabel(&context, dates.2, at: CGPoint(x: plot.maxX, y: dateY), anchor: .trailing, color: StrandPalette.textTertiary)

        if let band, let domain = model.left ?? model.right {
            let tint = model.colors[domain.leadMetricID] ?? StrandPalette.accent
            let yHigh = py(domain.height(band.high))
            let yLow = py(domain.height(band.low))
            let rect = CGRect(x: plot.minX, y: min(yHigh, yLow), width: plot.width, height: max(2, abs(yLow - yHigh)))
            context.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(tint.opacity(0.12)))
            var mean = Path()
            mean.move(to: CGPoint(x: plot.minX, y: py(domain.height(band.mean))))
            mean.addLine(to: CGPoint(x: plot.maxX, y: py(domain.height(band.mean))))
            context.stroke(mean, with: .color(tint.opacity(0.45)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
        }
        for series in model.series {
            drawSeries(&context, series, plot: plot, px: px, py: py)
        }
        drawCursor(&context, plot: plot, px: px, py: py)
    }

    private func drawSeries(_ context: inout GraphicsContext, _ series: MyChartResolved, plot: CGRect,
                            px: (Double) -> CGFloat, py: (Double) -> CGFloat) {
        let color = model.colors[series.item.metricID] ?? StrandPalette.accent
        let points = series.points.map { CGPoint(x: px($0.day), y: py($0.fraction)) }
        guard let first = points.first, let last = points.last else { return }
        switch series.item.kind {
        case .bars:
            let width = min(14, max(1.6, plot.width / CGFloat(points.count) * 0.58))
            let base = py(series.baseFraction)
            for point in points {
                let rect = CGRect(x: point.x - width / 2, y: min(point.y, base), width: width,
                                  height: max(1, abs(base - point.y)))
                context.fill(Path(roundedRect: rect, cornerRadius: min(2.5, width / 2)), with: .color(color.opacity(0.92)))
            }
        case .points:
            let radius: CGFloat = points.count > 80 ? 2.2 : 3
            for point in points {
                let rect = CGRect(x: point.x - radius, y: point.y - radius, width: 2 * radius, height: 2 * radius)
                context.fill(Path(ellipseIn: rect), with: .color(color.opacity(0.9)))
            }
        case .line, .area:
            var line = Path()
            line.move(to: first)
            for point in points.dropFirst() { line.addLine(to: point) }
            if series.item.kind == .area {
                var area = line
                area.addLine(to: CGPoint(x: last.x, y: plot.maxY))
                area.addLine(to: CGPoint(x: first.x, y: plot.maxY))
                area.closeSubpath()
                context.fill(area, with: .linearGradient(
                    Gradient(colors: [color.opacity(0.34), color.opacity(0)]),
                    startPoint: CGPoint(x: 0, y: plot.minY), endPoint: CGPoint(x: 0, y: plot.maxY)))
            }
            context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            let dot = CGRect(x: last.x - 3.6, y: last.y - 3.6, width: 7.2, height: 7.2)
            context.fill(Path(ellipseIn: dot), with: .color(color))
            context.stroke(Path(ellipseIn: dot), with: .color(StrandPalette.surfaceBase), lineWidth: 1.5)
        }
    }

    private func drawCursor(_ context: inout GraphicsContext, plot: CGRect,
                            px: (Double) -> CGFloat, py: (Double) -> CGFloat) {
        guard let cursor, let anchor = model.series.first(where: { !$0.points.isEmpty }),
              let snapped = MyChartEngine.nearestPoint(anchor, to: cursor) else { return }
        var line = Path()
        line.move(to: CGPoint(x: px(snapped.day), y: plot.minY))
        line.addLine(to: CGPoint(x: px(snapped.day), y: plot.maxY))
        context.stroke(line, with: .color(StrandPalette.textTertiary), lineWidth: 1)
        for series in model.series {
            guard let point = MyChartEngine.nearestPoint(series, to: snapped.day) else { continue }
            let color = model.colors[series.item.metricID] ?? StrandPalette.accent
            let rect = CGRect(x: px(point.day) - 4.2, y: py(point.fraction) - 4.2, width: 8.4, height: 8.4)
            context.fill(Path(ellipseIn: rect), with: .color(color))
            context.stroke(Path(ellipseIn: rect), with: .color(StrandPalette.surfaceBase), lineWidth: 1.8)
        }
    }

    private func drawLabel(_ context: inout GraphicsContext, _ text: String, at point: CGPoint,
                           anchor: UnitPoint, color: Color) {
        let label = Text(verbatim: text).font(StrandFont.caption).foregroundColor(color)
        context.draw(label, at: point, anchor: anchor)
    }

    /// « 100 % ».
    private static func percent(_ value: Int) -> String { "\(value) %" }

    // MARK: Reading

    private func readGesture(width: CGFloat) -> some Gesture {
        LongPressGesture(minimumDuration: holdDuration)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                guard case .second(true, let drag?) = value else { return }
                let inner = max(1, width - 2 * side)
                let t = min(1, max(0, Double((drag.location.x - side) / inner)))
                cursor = Double(model.window.lower) + t * Double(max(1, model.window.upper - model.window.lower))
            }
            .onEnded { _ in cursor = nil }
    }
}

// MARK: Plot block (readout + plot)

/// The readout above the plot: the touched day's values, or the latest ones.
struct MyChartReadout: View {
    let model: MyChartModel
    let format: MyChartFormat
    let cursor: Double?

    var body: some View {
        let anchor = model.series.first { !$0.points.isEmpty }
        let day: Double? = cursor.flatMap { c in anchor.flatMap { MyChartEngine.nearestPoint($0, to: c)?.day } }
        VStack(alignment: .leading, spacing: 2) {
            if let day {
                Text(verbatim: MyChartDates.full(day))
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
            } else {
                Text("Latest")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.space3) {
                ForEach(model.series, id: \.item.metricID) { series in
                    if let reading = reading(series, day: day) {
                        HStack(spacing: 5) {
                            Circle().fill(model.colors[series.item.metricID] ?? StrandPalette.accent)
                                .frame(width: 8, height: 8)
                            Text(verbatim: format.text(reading, metricID: series.item.metricID))
                                .font(StrandFont.number(20, weight: .bold))
                                .foregroundStyle(model.colors[series.item.metricID] ?? StrandPalette.accent)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                }
            }
            .frame(minHeight: 28, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func reading(_ series: MyChartResolved, day: Double?) -> Double? {
        guard let day else { return series.points.last?.value }
        return MyChartEngine.nearestPoint(series, to: day)?.value
    }
}

/// Readout, plot and the trace-in entrance, with the cursor kept here so a slide redraws only this block.
struct MyChartPlotBlock: View {
    let model: MyChartModel
    let format: MyChartFormat
    let entranceKey: String
    let animated: Bool
    var height: CGFloat = 150
    var showsAxes = true
    var holdDuration = 0.18
    var accessibilityName = ""
    var band: (low: Double, high: Double, mean: Double)?

    init(model: MyChartModel, format: MyChartFormat, entranceKey: String, animated: Bool, height: CGFloat = 150,
         showsAxes: Bool = true, holdDuration: Double = 0.18, accessibilityName: String = "",
         band: (low: Double, high: Double, mean: Double)? = nil) {
        self.band = band
        self.model = model
        self.format = format
        self.entranceKey = entranceKey
        self.animated = animated
        self.height = height
        self.showsAxes = showsAxes
        self.holdDuration = holdDuration
        self.accessibilityName = accessibilityName
    }

    @State private var cursor: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space1) {
            MyChartReadout(model: model, format: format, cursor: cursor)
            NoopFirstDraw(key: entranceKey, armed: animated) { phase in
                MyChartPlot(model: model, format: format, showsAxes: showsAxes,
                            holdDuration: holdDuration, band: band, cursor: $cursor)
                    .frame(height: height)
                    .mask(alignment: .leading) {
                        Rectangle()
                            .scaleEffect(x: phase.drawn ? 1 : 0.001, y: 1, anchor: .leading)
                            .animation(phase.motion(NoopMotion.curveDraw), value: phase.drawn)
                    }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: accessibilityName))
            .accessibilityValue(Text(verbatim: accessibilitySummary))
        }
    }

    private var accessibilitySummary: String {
        model.series.compactMap { series -> String? in
            guard let last = series.points.last else { return nil }
            return MyChartCatalog.name(series.item.metricID) + " " + format.text(last.value, metricID: series.item.metricID)
        }.joined(separator: ", ")
    }
}

// MARK: Today card

/// The card under Stress on Today: the saved chart (the pinned one first), a pill per saved chart, a slide
/// to read a value, and the way into the editor.
struct MyChartCard: View {
    @EnvironmentObject var repo: Repository
    @AppStorage(MyChartStore.key) private var savedRaw = ""
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.temperatureKey) private var temperatureRaw = ""
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    @StateObject private var data = MyChartData()
    @State private var shownID: String?

    var animated = false

    init(animated: Bool = false) {
        self.animated = animated
    }

    private var specs: [MyChartSpec] { MyChartStore.decodeSaved(savedRaw) }

    private var shown: MyChartSpec? {
        let all = specs
        if let shownID, let match = all.first(where: { $0.id == shownID }) { return match }
        return all.isEmpty ? nil : all[MyChartStore.pinnedIndex(all)]
    }

    private var format: MyChartFormat {
        MyChartFormat(systemRaw: unitSystemRaw, temperatureRaw: temperatureRaw, effortRaw: effortScaleRaw)
    }

    private var loadKey: String {
        (shown?.items.map(\.metricID).joined(separator: ",") ?? "") + "|\(repo.refreshSeq)"
    }

    var body: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.cardInnerSpacing) {
                header
                if let spec = shown {
                    pills(spec)
                    chart(spec)
                } else {
                    firstTime
                }
            }
        }
        .task(id: loadKey) {
            guard let spec = shown else { return }
            await data.load(spec.items.map(\.metricID), repo: repo)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.space2) {
            Text("My chart")
                .font(StrandFont.sectionTitle)
                .foregroundStyle(StrandPalette.textPrimary)
            Spacer(minLength: 0)
            TrendsInfoButton(
                label: "About My chart",
                text: "A chart you compose from your own measures. Press and hold on it, then slide, to read a value. Edit opens the full editor.")
        }
    }

    private func pills(_ spec: MyChartSpec) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: NoopMetrics.space2) {
                ForEach(specs) { item in
                    Button {
                        StrandHaptic.selection.play()
                        shownID = item.id
                    } label: {
                        Text(verbatim: item.name)
                            .font(StrandFont.subhead.weight(.medium))
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .foregroundStyle(item.id == spec.id ? StrandPalette.surfaceBase : StrandPalette.textSecondary)
                            .background(Capsule().fill(item.id == spec.id ? StrandPalette.textPrimary : StrandPalette.surfaceOverlay))
                    }
                    .buttonStyle(.plain)
                }
                NavigationLink {
                    MyChartView()
                } label: {
                    Image(systemName: "plus")
                        .font(StrandFont.subhead.weight(.semibold))
                        .foregroundStyle(StrandPalette.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().strokeBorder(StrandPalette.hairlineStrong, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New chart")
            }
        }
    }

    @ViewBuilder private func chart(_ spec: MyChartSpec) -> some View {
        let model = MyChartModel(items: spec.items, period: spec.period, normalized: spec.normalized,
                                 data: data.series)
        if model.hasData {
            MyChartPlotBlock(model: model, format: format, entranceKey: "today.myChart.\(spec.id)",
                             animated: animated, height: 150, showsAxes: false, holdDuration: 0.2,
                             accessibilityName: spec.name)
        } else {
            Text("Nothing measured in this period.")
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textTertiary)
                .frame(maxWidth: .infinity, minHeight: 90, alignment: .leading)
        }
        HStack {
            Text(verbatim: footerText(model))
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            NavigationLink {
                MyChartView(startWith: spec.id)
            } label: {
                HStack(spacing: 3) {
                    Text("Edit")
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                }
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.accent)
            }
            .buttonStyle(.plain)
        }
        legend(spec)
    }

    private func footerText(_ model: MyChartModel) -> String {
        var text = MyChartDates.range(model.window.lower, model.window.upper)
        if model.bucket > 1 { text += " · " + String(localized: "avg. over \(model.bucket) days") }
        return text
    }

    private func legend(_ spec: MyChartSpec) -> some View {
        let colors = MyChartCatalog.colors(spec.items)
        return HStack(spacing: NoopMetrics.space3) {
            ForEach(spec.items) { item in
                HStack(spacing: 5) {
                    Circle().fill(colors[item.metricID] ?? StrandPalette.accent).frame(width: 8, height: 8)
                    Text(verbatim: MyChartCatalog.name(item.metricID))
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var firstTime: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space3) {
            Text("Compose your chart: up to 4 measures, your curve type, your axes.")
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            NavigationLink {
                MyChartView()
            } label: {
                Text("Create a chart")
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.surfaceBase)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(StrandPalette.textPrimary))
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: Zoom window

/// The whole period as a thin outline, with the zoomed range as a window to drag and to resize.
struct MyChartMiniMap: View {
    let model: MyChartModel
    @Binding var lo: Double
    @Binding var hi: Double

    init(model: MyChartModel, lo: Binding<Double>, hi: Binding<Double>) {
        self.model = model
        self._lo = lo
        self._hi = hi
    }

    private enum Mode { case move, lower, upper }
    @State private var anchor: (lo: Double, hi: Double)?
    private let minSpan = 0.06

    var body: some View {
        GeometryReader { geo in
            let width = max(1, geo.size.width)
            ZStack(alignment: .leading) {
                Canvas { context, size in drawOutline(&context, size) }
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(StrandPalette.textPrimary.opacity(0.1))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(StrandPalette.textPrimary, lineWidth: 1.5))
                    .frame(width: max(24, width * CGFloat(hi - lo)))
                    .offset(x: width * CGFloat(lo))
                    .gesture(drag(width: width, mode: .move))
                handle.offset(x: width * CGFloat(lo) - 8).gesture(drag(width: width, mode: .lower))
                handle.offset(x: width * CGFloat(hi) - 8).gesture(drag(width: width, mode: .upper))
            }
        }
        .frame(height: 38)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Zoom"))
    }

    private var handle: some View {
        Capsule().fill(StrandPalette.textPrimary).frame(width: 3, height: 16)
            .frame(width: 16, height: 38)
            .contentShape(Rectangle())
    }

    private func drawOutline(_ context: inout GraphicsContext, _ size: CGSize) {
        guard let series = model.series.first, series.points.count > 1 else { return }
        let lower = Double(model.window.start)
        let span = Double(max(1, model.window.end - model.window.start))
        var path = Path()
        for (index, point) in series.points.enumerated() {
            let x = CGFloat((point.day - lower) / span) * size.width
            let y = size.height - 4 - CGFloat(point.fraction) * (size.height - 8)
            if index == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        let color = model.colors[series.item.metricID] ?? StrandPalette.accent
        context.stroke(path, with: .color(color.opacity(0.6)), lineWidth: 1.3)
    }

    private func drag(width: CGFloat, mode: Mode) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let start = anchor ?? (lo: lo, hi: hi)
                anchor = start
                let dx = Double(value.translation.width / width)
                switch mode {
                case .move:
                    let span = start.hi - start.lo
                    let newLo = min(max(0, start.lo + dx), 1 - span)
                    lo = newLo
                    hi = newLo + span
                case .lower:
                    lo = min(max(0, start.lo + dx), start.hi - minSpan)
                case .upper:
                    hi = max(min(1, start.hi + dx), start.lo + minSpan)
                }
            }
            .onEnded { _ in anchor = nil }
    }
}

// MARK: Editor

/// The full-screen editor: measures, kind, period, zoom, axes, scale, saved charts.
struct MyChartView: View {
    @EnvironmentObject var repo: Repository
    @AppStorage(MyChartStore.key) private var savedRaw = ""
    @AppStorage(MyChartStore.showOnTodayKey) private var showOnToday = true
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.temperatureKey) private var temperatureRaw = ""
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    @StateObject private var data = MyChartData()

    private let startID: String?
    private let preset: MyChartSpec?

    /// - Parameters:
    ///   - startWith: the saved chart to open (a new one when nil).
    ///   - preset: a chart to open unsaved (the metric sheet opens two measures together).
    init(startWith id: String? = nil, preset: MyChartSpec? = nil) {
        self.startID = id
        self.preset = preset
    }

    @State private var draft = MyChartSpec.fresh(name: "", metricID: "my-whoop:recovery")
    @State private var draftIndex: Int?
    @State private var dirty = false
    @State private var started = false
    @State private var offset = 0
    @State private var zoomLo = 0.0
    @State private var zoomHi = 1.0
    @State private var selectedID: String?
    @State private var showPicker = false
    @State private var showSaved = false
    @State private var nonEmpty: Set<String>?

    private var specs: [MyChartSpec] { MyChartStore.decodeSaved(savedRaw) }

    private var format: MyChartFormat {
        MyChartFormat(systemRaw: unitSystemRaw, temperatureRaw: temperatureRaw, effortRaw: effortScaleRaw)
    }

    private var model: MyChartModel {
        MyChartModel(items: draft.items, period: draft.period, offset: offset, zoom: zoomLo...zoomHi,
                     normalized: draft.normalized, data: data.series)
    }

    private var fullModel: MyChartModel {
        MyChartModel(items: draft.items, period: draft.period, offset: offset, normalized: draft.normalized,
                     data: data.series)
    }

    private var selectedItem: MyChartItem? {
        draft.items.first { $0.metricID == selectedID } ?? draft.items.first
    }

    var body: some View {
        ScreenScaffold(title: "My chart") {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                topBar
                chartCard
                periodRow
                linkLine
                measuresSection
                if let item = selectedItem { settingsSection(item) }
                optionsSection
            }
        }
        .noopEntranceRoot()
        .onAppear(perform: start)
        .task(id: draft.items.map(\.metricID).joined(separator: ",") + "|\(repo.refreshSeq)") {
            await data.load(draft.items.map(\.metricID), repo: repo)
        }
        .task { nonEmpty = await repo.nonEmptyMetricIDs(MetricCatalog.all) }
        .sheet(isPresented: $showPicker) {
            MyChartPickerSheet(chosen: Set(draft.items.map(\.metricID)), nonEmpty: nonEmpty,
                               atLimit: draft.items.count >= MyChartSpec.maxItems,
                               onToggle: toggleMetric, onClose: { showPicker = false })
        }
        .sheet(isPresented: $showSaved) {
            MyChartSavedSheet(specs: specs, currentID: draftIndex.flatMap { specs.indices.contains($0) ? specs[$0].id : nil },
                              name: nameBinding, onSelect: select, onPin: pin, onDelete: delete,
                              onNew: newChart, onClose: { showSaved = false })
        }
    }

    // MARK: Start

    private func start() {
        guard !started else { return }
        started = true
        if let preset {
            draft = preset
            draftIndex = nil
            dirty = true
            selectedID = preset.items.first?.metricID
            return
        }
        let all = specs
        if let startID, let index = all.firstIndex(where: { $0.id == startID }) {
            load(index)
        } else if startID == nil, !all.isEmpty {
            load(MyChartStore.pinnedIndex(all))
        } else {
            draft = MyChartSpec.fresh(name: String(localized: "Untitled"), metricID: "my-whoop:recovery")
            draftIndex = nil
            dirty = false
        }
    }

    private func load(_ index: Int) {
        let all = specs
        guard all.indices.contains(index) else { return }
        draft = all[index]
        draftIndex = index
        dirty = false
        offset = 0
        zoomLo = 0
        zoomHi = 1
        selectedID = draft.items.first?.metricID
    }

    // MARK: Top bar

    private var nameBinding: Binding<String> {
        Binding(get: { draft.name },
                set: { draft.name = $0.isEmpty ? String(localized: "Untitled") : $0; dirty = true })
    }

    private var topBar: some View {
        HStack(spacing: NoopMetrics.space2) {
            Button { showSaved = true } label: {
                HStack(spacing: 6) {
                    Text(verbatim: draft.name)
                        .font(StrandFont.headline)
                        .lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(StrandPalette.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(StrandPalette.surfaceOverlay))
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            Button(action: save) {
                Text(verbatim: dirty ? String(localized: "Save") : String(localized: "Saved"))
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(dirty ? StrandPalette.surfaceBase : StrandPalette.textTertiary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(dirty ? StrandPalette.textPrimary : StrandPalette.surfaceOverlay))
            }
            .buttonStyle(.plain)
            .disabled(!dirty)
        }
    }

    private func save() {
        var all = specs
        if let index = draftIndex, all.indices.contains(index) {
            all[index] = draft
        } else {
            all.append(draft)
            draftIndex = all.count - 1
        }
        savedRaw = MyChartStore.encodeSaved(all)
        dirty = false
        StrandHaptic.selection.play()
    }

    // MARK: Chart card

    private var chartCard: some View {
        let current = model
        return NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.cardInnerSpacing) {
                if current.hasData {
                    MyChartPlotBlock(model: current, format: format, entranceKey: "myChart.editor",
                                     animated: true, height: 240, showsAxes: true, holdDuration: 0.12,
                                     accessibilityName: draft.name)
                    MyChartMiniMap(model: fullModel, lo: $zoomLo, hi: $zoomHi)
                    zoomRow(current)
                } else {
                    Text("Nothing measured in this period.")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .frame(maxWidth: .infinity, minHeight: 160, alignment: .center)
                }
            }
        }
    }

    private func zoomRow(_ current: MyChartModel) -> some View {
        HStack(spacing: NoopMetrics.space2) {
            zoomButton("plus", label: "Zoom in") { rescale(0.55) }
            zoomButton("minus", label: "Zoom out") { rescale(1.8) }
            zoomButton("arrow.up.left.and.arrow.down.right", label: "Whole period") { zoomLo = 0; zoomHi = 1 }
            Spacer(minLength: 0)
            Text(verbatim: MyChartDates.range(current.window.lower, current.window.upper)
                 + (current.bucket > 1 ? " · " + String(localized: "avg. over \(current.bucket) days") : ""))
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private func zoomButton(_ symbol: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button {
            StrandHaptic.selection.play()
            action()
        } label: {
            Image(systemName: symbol)
                .font(StrandFont.subhead.weight(.semibold))
                .foregroundStyle(StrandPalette.textPrimary)
                .frame(width: 34, height: 30)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(StrandPalette.surfaceOverlay))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// Zooms the window around its middle by `factor` (below 1 in, above 1 out), keeping it inside the period.
    private func rescale(_ factor: Double) {
        let centre = (zoomLo + zoomHi) / 2
        let width = min(1, max(0.06, (zoomHi - zoomLo) * factor))
        var lo = centre - width / 2
        var hi = centre + width / 2
        if lo < 0 { hi -= lo; lo = 0 }
        if hi > 1 { lo -= hi - 1; hi = 1 }
        zoomLo = max(0, lo)
        zoomHi = min(1, hi)
    }

    // MARK: Period

    private var periodBinding: Binding<MyChartPeriod> {
        Binding(get: { draft.period },
                set: { newValue in
                    draft.period = newValue
                    offset = 0
                    zoomLo = 0
                    zoomHi = 1
                    dirty = true
                })
    }

    private var periodRow: some View {
        let canStepBack = draft.period != .all && fullModel.window.start > (data.series.values.compactMap { $0.first?.day }.min() ?? 0)
        return VStack(spacing: NoopMetrics.space2) {
            SegmentedPillControl(MyChartPeriod.allCases, selection: periodBinding,
                                 adaptsToAvailableWidth: true, fillsAvailableWidth: true) { $0.label }
            if draft.period != .all {
                HStack {
                    stepButton("chevron.left", label: "Previous period", enabled: canStepBack) { offset += 1; zoomLo = 0; zoomHi = 1 }
                    Spacer(minLength: 0)
                    Text(verbatim: MyChartDates.range(fullModel.window.start, fullModel.window.end))
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                    Spacer(minLength: 0)
                    stepButton("chevron.right", label: "Next period", enabled: offset > 0) { offset -= 1; zoomLo = 0; zoomHi = 1 }
                }
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

    // MARK: Link between the first two measures

    @ViewBuilder private var linkLine: some View {
        if draft.items.count >= 2 {
            let a = draft.items[0].metricID
            let b = draft.items[1].metricID
            let current = model
            if let r = MyChartEngine.correlation(data.series[a] ?? [], data.series[b] ?? [],
                                                 lower: current.window.lower, upper: current.window.upper) {
                let nameA = MyChartCatalog.name(a)
                let nameB = MyChartCatalog.name(b)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: sentence(r, nameA, nameB))
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: correlationDetail(r))
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
                .padding(NoopMetrics.space3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(NoopPanelSurface(cornerRadius: 14))
            }
        }
    }

    private func sentence(_ r: Double, _ a: String, _ b: String) -> String {
        switch MyChartEngine.link(r) {
        case .negligible: return String(localized: "No clear link between \(a) and \(b) over this period.")
        default:
            return r > 0 ? String(localized: "When \(a) rises, \(b) rises too.")
                : String(localized: "When \(a) rises, \(b) falls.")
        }
    }

    private func strength(_ r: Double) -> String {
        switch MyChartEngine.link(r) {
        case .negligible: return String(localized: "No link")
        case .weak: return String(localized: "Weak link")
        case .moderate: return String(localized: "Moderate link")
        case .strong: return String(localized: "Strong link")
        case .veryStrong: return String(localized: "Very strong link")
        }
    }

    /// « Strong link (r = +0.62) ».
    private func correlationDetail(_ r: Double) -> String {
        let value = signed(r)
        return "\(strength(r)) (r = \(value))"
    }

    private func signed(_ r: Double) -> String {
        (r >= 0 ? "+" : "−") + abs(r).formatted(.number.precision(.fractionLength(2)).locale(AppLanguage.activeLocale))
    }

    // MARK: Measures

    private var measuresSection: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            SectionHeader("Measures", trailing: "\(draft.items.count) / \(MyChartSpec.maxItems)")
            ForEach(draft.items) { item in measureRow(item) }
            if draft.items.count < MyChartSpec.maxItems {
                Button { showPicker = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                        Text("Add a measure")
                    }
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(NoopPanelSurface(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func measureRow(_ item: MyChartItem) -> some View {
        let color = model.colors[item.metricID] ?? StrandPalette.accent
        let isSelected = item.metricID == (selectedItem?.metricID ?? "")
        return HStack(spacing: NoopMetrics.space3) {
            Circle().fill(color).frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: MyChartCatalog.name(item.metricID))
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(verbatim: item.kind.label + " · " + item.axis.label)
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            Spacer(minLength: 0)
            if draft.items.count > 1 {
                Button { remove(item.metricID) } label: {
                    Image(systemName: "xmark")
                        .font(StrandFont.subhead.weight(.semibold))
                        .foregroundStyle(StrandPalette.textTertiary)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove")
            }
        }
        .padding(NoopMetrics.space3)
        .background(NoopPanelSurface(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(isSelected ? color : Color.clear, lineWidth: 1.5))
        .contentShape(Rectangle())
        .onTapGesture {
            StrandHaptic.selection.play()
            selectedID = item.metricID
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private func remove(_ id: String) {
        guard draft.items.count > 1 else { return }
        draft.items.removeAll { $0.metricID == id }
        if selectedID == id { selectedID = draft.items.first?.metricID }
        dirty = true
    }

    private func toggleMetric(_ metric: MetricDescriptor) {
        if draft.items.contains(where: { $0.metricID == metric.id }) {
            remove(metric.id)
            return
        }
        guard draft.items.count < MyChartSpec.maxItems else { return }
        // A second measure goes on the other axis unless it shares the unit of one already drawn.
        let sameUnit = draft.items.contains { MyChartCatalog.metric($0.metricID)?.unit == metric.unit }
        let rightTaken = draft.items.contains { $0.axis == .right }
        let axis: MyChartAxis = (draft.items.isEmpty || sameUnit || rightTaken) ? .left : .right
        draft.items.append(MyChartItem(metricID: metric.id, kind: .line, axis: axis))
        selectedID = metric.id
        dirty = true
    }

    // MARK: Settings of the selected measure

    private func binding<T>(_ id: String, _ path: WritableKeyPath<MyChartItem, T>, fallback: T) -> Binding<T> {
        Binding(
            get: { draft.items.first { $0.metricID == id }?[keyPath: path] ?? fallback },
            set: { newValue in
                guard let index = draft.items.firstIndex(where: { $0.metricID == id }) else { return }
                draft.items[index][keyPath: path] = newValue
                dirty = true
            })
    }

    private func scaleBinding(_ id: String) -> Binding<MyChartScale> {
        Binding(
            get: { draft.items.first { $0.metricID == id }?.scale ?? .auto },
            set: { newValue in
                guard let index = draft.items.firstIndex(where: { $0.metricID == id }) else { return }
                draft.items[index].scale = newValue
                if newValue == .fixed {
                    // Start from the measure's own range, rounded outwards.
                    let values = (data.series[id] ?? []).map(\.value)
                    if let low = values.min(), let high = values.max() {
                        draft.items[index].fixedMin = low.rounded(.down)
                        draft.items[index].fixedMax = max(high.rounded(.up), low.rounded(.down) + 1)
                    }
                }
                dirty = true
            })
    }

    private func stepSize(_ item: MyChartItem) -> Double {
        let range = max(1, item.fixedMax - item.fixedMin)
        return pow(10, floor(log10(range / 10)))
    }

    private func settingsSection(_ item: MyChartItem) -> some View {
        let id = item.metricID
        return VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            SectionHeader("Settings", trailing: MyChartCatalog.name(id))
            NoopCard {
                VStack(alignment: .leading, spacing: NoopMetrics.cardInnerSpacing) {
                    labelled("Chart type") {
                        SegmentedPillControl(MyChartKind.allCases, selection: binding(id, \.kind, fallback: .line),
                                             adaptsToAvailableWidth: true, fillsAvailableWidth: true) { $0.label }
                    }
                    labelled("Axis") {
                        SegmentedPillControl(MyChartAxis.allCases, selection: binding(id, \.axis, fallback: .left),
                                             adaptsToAvailableWidth: true, fillsAvailableWidth: true) { $0.label }
                    }
                    labelled("Scale") {
                        SegmentedPillControl(MyChartScale.allCases, selection: scaleBinding(id),
                                             adaptsToAvailableWidth: true, fillsAvailableWidth: true) { $0.label }
                    }
                    if item.scale == .fixed {
                        Stepper(value: binding(id, \.fixedMin, fallback: 0), step: stepSize(item)) {
                            HStack {
                                Text("Min")
                                Spacer()
                                Text(verbatim: item.fixedMin.formatted(.number.precision(.fractionLength(0...1)).locale(AppLanguage.activeLocale)))
                                    .foregroundStyle(StrandPalette.textSecondary)
                            }
                        }
                        Stepper(value: binding(id, \.fixedMax, fallback: 100), step: stepSize(item)) {
                            HStack {
                                Text("Max")
                                Spacer()
                                Text(verbatim: item.fixedMax.formatted(.number.precision(.fractionLength(0...1)).locale(AppLanguage.activeLocale)))
                                    .foregroundStyle(StrandPalette.textSecondary)
                            }
                        }
                    }
                    Toggle("Invert axis", isOn: binding(id, \.inverted, fallback: false))
                        .tint(StrandPalette.chargeColor)
                }
            }
        }
    }

    private func labelled<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space1) {
            Text(title)
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textSecondary)
            content()
        }
    }

    // MARK: Options for the whole chart

    private var optionsSection: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.cardInnerSpacing) {
                VStack(alignment: .leading, spacing: 2) {
                    Toggle("Compare shapes", isOn: Binding(get: { draft.normalized },
                                                           set: { draft.normalized = $0; dirty = true }))
                        .tint(StrandPalette.chargeColor)
                    Text("Each measure on its own range, from lowest to highest")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
                Divider().overlay(StrandPalette.hairline)
                Toggle("Show on Today", isOn: $showOnToday)
                    .tint(StrandPalette.chargeColor)
            }
        }
    }

    // MARK: Saved charts

    private func select(_ index: Int) {
        load(index)
        showSaved = false
    }

    private func pin(_ index: Int) {
        savedRaw = MyChartStore.encodeSaved(MyChartStore.pinning(specs, at: index))
    }

    private func delete(_ index: Int) {
        var all = specs
        guard all.count > 1, all.indices.contains(index) else { return }
        let deletedCurrent = draftIndex == index
        all.remove(at: index)
        savedRaw = MyChartStore.encodeSaved(all)
        if deletedCurrent {
            load(0)
        } else if let current = draftIndex, current > index {
            draftIndex = current - 1
        }
    }

    private func newChart() {
        draft = MyChartSpec.fresh(name: String(localized: "Untitled"), metricID: "my-whoop:recovery")
        draftIndex = nil
        dirty = true
        offset = 0
        zoomLo = 0
        zoomHi = 1
        selectedID = draft.items.first?.metricID
        showSaved = false
    }
}

// MARK: Sheets

/// The measures to choose from: the catalogue by category, without the ones that have no reading.
struct MyChartPickerSheet: View {
    let chosen: Set<String>
    let nonEmpty: Set<String>?
    let atLimit: Bool
    let onToggle: (MetricDescriptor) -> Void
    let onClose: () -> Void
    @State private var query = ""

    init(chosen: Set<String>, nonEmpty: Set<String>?, atLimit: Bool,
         onToggle: @escaping (MetricDescriptor) -> Void, onClose: @escaping () -> Void) {
        self.chosen = chosen
        self.nonEmpty = nonEmpty
        self.atLimit = atLimit
        self.onToggle = onToggle
        self.onClose = onClose
    }

    private var duplicatedKeys: Set<String> {
        var seen = Set<String>()
        var dupes = Set<String>()
        for metric in MetricCatalog.all where !seen.insert(metric.key).inserted { dupes.insert(metric.key) }
        return dupes
    }

    private func visible(_ category: String) -> [MetricDescriptor] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        return MetricCatalog.inCategory(category).filter { metric in
            if let nonEmpty, !nonEmpty.contains(metric.id) { return false }
            return needle.isEmpty || MyChartCatalog.name(metric.id).lowercased().contains(needle)
        }
    }

    var body: some View {
        let dupes = duplicatedKeys
        VStack(spacing: 0) {
            HStack {
                Text("Add a measure")
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                Spacer()
                Button("Done", action: onClose)
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.accent)
            }
            .padding(NoopMetrics.cardPadding)
            TextField("Search", text: $query)
                .textFieldStyle(.plain)
                .padding(10)
                .background(NoopPanelSurface(cornerRadius: 12))
                .padding(.horizontal, NoopMetrics.cardPadding)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(MetricCatalog.categories, id: \.self) { category in
                        let metrics = visible(category)
                        if !metrics.isEmpty {
                            Text(verbatim: MetricCatalog.categoryDisplayName(category))
                                .font(StrandFont.footnote.weight(.semibold))
                                .foregroundStyle(StrandPalette.textSecondary)
                                .padding(.top, NoopMetrics.space4)
                                .padding(.bottom, NoopMetrics.space1)
                            ForEach(metrics) { metric in row(metric, showsSource: dupes.contains(metric.key)) }
                        }
                    }
                    if atLimit {
                        Text("4 measures at most")
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textTertiary)
                            .padding(.top, NoopMetrics.space4)
                    }
                }
                .padding(.horizontal, NoopMetrics.cardPadding)
                .padding(.bottom, NoopMetrics.space6)
            }
        }
        .background(StrandPalette.surfaceBase.ignoresSafeArea())
    }

    private func row(_ metric: MetricDescriptor, showsSource: Bool) -> some View {
        let on = chosen.contains(metric.id)
        let color = metricAccent(metric)
        let detail = [metric.unit.isEmpty ? nil : metric.unit, showsSource ? metric.sourceLabel : nil]
            .compactMap { $0 }.joined(separator: " · ")
        return Button { onToggle(metric) } label: {
            HStack(spacing: NoopMetrics.space3) {
                Circle().fill(color).frame(width: 12, height: 12)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: MyChartCatalog.name(metric.id))
                        .font(StrandFont.body)
                        .foregroundStyle(StrandPalette.textPrimary)
                    if !detail.isEmpty {
                        Text(verbatim: detail)
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(on ? StrandPalette.textPrimary : StrandPalette.textTertiary)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!on && atLimit)
        .opacity(!on && atLimit ? 0.4 : 1)
    }
}

/// The saved charts: name the current one, pin the one Today opens on, start a new one, delete.
struct MyChartSavedSheet: View {
    let specs: [MyChartSpec]
    let currentID: String?
    @Binding var name: String
    let onSelect: (Int) -> Void
    let onPin: (Int) -> Void
    let onDelete: (Int) -> Void
    let onNew: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("My charts")
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                Spacer()
                Button("Done", action: onClose)
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.accent)
            }
            .padding(NoopMetrics.cardPadding)
            TextField("Name", text: $name)
                .textFieldStyle(.plain)
                .padding(10)
                .background(NoopPanelSurface(cornerRadius: 12))
                .padding(.horizontal, NoopMetrics.cardPadding)
            ScrollView {
                VStack(spacing: NoopMetrics.space2) {
                    ForEach(Array(specs.enumerated()), id: \.element.id) { index, spec in
                        HStack(spacing: NoopMetrics.space2) {
                            Button { onSelect(index) } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(verbatim: spec.name)
                                        .font(StrandFont.headline)
                                        .foregroundStyle(StrandPalette.textPrimary)
                                    Text(verbatim: spec.items.map { MyChartCatalog.name($0.metricID) }.joined(separator: " · "))
                                        .font(StrandFont.footnote)
                                        .foregroundStyle(StrandPalette.textSecondary)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Button { onPin(index) } label: {
                                Image(systemName: spec.pinned ? "pin.fill" : "pin")
                                    .foregroundStyle(spec.pinned ? StrandPalette.stressModerate : StrandPalette.textTertiary)
                                    .frame(width: 34, height: 34)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(spec.pinned ? String(localized: "Unpin") : String(localized: "Pin"))
                            if specs.count > 1 {
                                Button { onDelete(index) } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(StrandPalette.textTertiary)
                                        .frame(width: 34, height: 34)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Delete")
                            }
                        }
                        .padding(NoopMetrics.space3)
                        .background(NoopPanelSurface(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(spec.id == currentID ? StrandPalette.hairlineStrong : Color.clear, lineWidth: 1.5))
                    }
                    Button(action: onNew) {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                            Text("New chart")
                        }
                        .font(StrandFont.headline)
                        .foregroundStyle(StrandPalette.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, NoopMetrics.cardPadding)
                .padding(.top, NoopMetrics.space3)
                .padding(.bottom, NoopMetrics.space6)
            }
        }
        .background(StrandPalette.surfaceBase.ignoresSafeArea())
    }
}
