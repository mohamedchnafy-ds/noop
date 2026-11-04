import Foundation

// MARK: - Charts in the Coach's replies (personal fork, chantier 9, section 6 PR B)
//
// The Coach never draws a figure itself. It calls `show_chart` with WHAT to show — a metric of the Explore
// catalogue (`MetricCatalog`, by its `source:key` id), a period of the Explore ranges, a kind — and the app
// draws the card from its own data, with the reader Analyses uses (`Repository.exploreSeries`), so the
// card and Analyses › show the same series. Only the request is stored with the reply (`CoachReplyMeta`),
// with the day the window ends on, so the card shows the same days when the conversation is read again.
//
// PURE: no store, no SwiftUI. The engine reads the points (`AICoachEngine.chartPoints`) and the card draws
// them; the input rules, the summary sent back to the model and the figures under the chart are here, so
// they are tested without a strap.

/// What a chart shows, as `show_chart` asked for it.
struct CoachChartSpec: Codable, Equatable, Hashable {
    enum Kind: String, Codable, CaseIterable {
        /// One metric over the period, a point per day.
        case line
        /// One metric over the period, a bar per day.
        case bars
        /// Two metrics over the same period, each on its own scale and colour.
        case pair
        /// One day, hour by hour: the heart rate (5-minute averages) or the daytime stress.
        case day
        /// A bar per day split into its parts (PR C): the sleep stages of each night, or the macros of each day.
        case stacked
    }

    /// What a stacked chart (and `get_series`) splits into parts, by an id beside the catalogue's.
    enum Stack: String, Codable, CaseIterable {
        /// Deep, REM and light minutes of each night, as « Your nights » on the Sleep screen reads them.
        case sleepStages = "sleep:stages"
        /// Protein, carbs and fat grams of each day, as the meal journal adds them up.
        case macros = "nutrition:macros"
    }

    /// What a one-day chart shows.
    enum DaySeries: String, Codable, CaseIterable {
        case heartRate = "heart_rate"
        case stress
    }

    var kind: Kind
    /// The metric's catalogue id ("my-whoop:hrv"), or a `Stack` id for a stacked chart; nil for a one-day chart.
    var metric: String?
    /// The second metric of a pair.
    var second: String?
    /// The period in days, one of `CoachChart.periods`; nil for a one-day chart.
    var days: Int?
    /// The last day of the period ("yyyy-MM-dd", the day the reply was written), or the day of a one-day chart.
    var day: String
    /// What a one-day chart shows.
    var series: DaySeries?
}

/// One point of a chart: a day (local midnight) or an instant of a one-day chart.
struct CoachChartPoint: Equatable {
    var date: Date
    /// The value; for a stacked chart, the sum of its parts.
    var value: Double
    /// A stacked chart's parts, bottom to top (deep, REM, light; protein, carbs, fat); empty otherwise.
    var parts: [Double] = []
}

enum CoachChart {
    static let toolName = "show_chart"
    /// Mohamed's choice (4 Nov.): up to three charts in one reply.
    static let maxPerReply = 3
    /// The Explore ranges (Mohamed's choice, 4 Nov.): 7 days to a year.
    static let periods = [7, 14, 30, 90, 180, 365]
    /// How far back a one-day chart may go: the days the heart-rate tool reads.
    static var dayLookback: Int { CoachTools.dayHeartRateLookbackDays }

    /// Every catalogue id, in catalogue order, once each (the tool's `enum`).
    static var metricIds: [String] {
        var seen: Set<String> = []
        return MetricCatalog.all.map(\.id).filter { seen.insert($0).inserted }
    }

    /// Every id `get_series` and a stacked chart accept: the catalogue's, then the stacks'.
    static var seriesIds: [String] { metricIds + CoachChartSpec.Stack.allCases.map(\.rawValue) }

    /// The stack of an id, nil for a catalogue id.
    static func stack(_ id: String?) -> CoachChartSpec.Stack? {
        id.flatMap(CoachChartSpec.Stack.init(rawValue:))
    }

    /// The catalogue entry of an id.
    static func descriptor(_ id: String?) -> MetricDescriptor? {
        guard let id else { return nil }
        return MetricCatalog.all.first { $0.id == id }
    }

    /// The period of the Explore ranges nearest to `days` (the longer one on a tie).
    static func nearestPeriod(_ days: Int) -> Int {
        periods.min { a, b in
            let da = abs(a - days), db = abs(b - days)
            return da == db ? a > b : da < db
        } ?? 30
    }

    // MARK: The tool

    static var definition: [String: Any] {
        ["name": toolName,
         "description": "Show the user a chart under your reply, drawn by the app from its own data (the same "
            + "series as Analyses), so you never write the numbers it shows. kind: line or bars = one metric over "
            + "the period; pair = two metrics over the same period, each on its own scale; day = one day hour by "
            + "hour (series heart_rate or stress); stacked = a bar per day split into its parts, metric "
            + "\(CoachChartSpec.Stack.sleepStages.rawValue) (deep, REM and light minutes of each night) or "
            + "\(CoachChartSpec.Stack.macros.rawValue) (protein, carbs and fat grams of each day). At most "
            + "\(maxPerReply) charts in a reply. The result gives the figures the chart shows: comment on them in "
            + "one or two sentences, do not list them.",
         "input_schema": [
            "type": "object",
            "properties": [
                "kind": ["type": "string", "enum": CoachChartSpec.Kind.allValues],
                "metric": ["type": "string", "enum": seriesIds,
                           "description": "The metric's id (source:key) for line, bars and pair; a stack id for stacked."],
                "second_metric": ["type": "string", "enum": metricIds, "description": "The second metric of a pair."],
                "days": ["type": "integer", "enum": periods,
                         "description": "The period, for line, bars, pair and stacked."],
                "series": ["type": "string", "enum": CoachChartSpec.DaySeries.allValues, "description": "For kind day."],
                "date": ["type": "string",
                         "description": "YYYY-MM-DD, for kind day: at most \(dayLookback) days ago; today when left out."],
            ] as [String: Any],
            "required": ["kind"],
         ] as [String: Any]]
    }

    /// The chart a `show_chart` input asks for, or why it cannot be drawn. `today` is the reply's day
    /// ("yyyy-MM-dd"); `daysBack` says how many days before today a "yyyy-MM-dd" is (nil when unreadable).
    static func fromToolInput(_ input: [String: Any], today: String,
                              daysBack: (String) -> Int?) -> (spec: CoachChartSpec?, problem: String?) {
        guard let kind = CoachTools.text(input, "kind").flatMap(CoachChartSpec.Kind.init(rawValue:)) else {
            return (nil, "Give kind: line, bars, pair, day or stacked.")
        }
        if kind == .day {
            let series = CoachTools.text(input, "series").flatMap(CoachChartSpec.DaySeries.init(rawValue:)) ?? .heartRate
            let day = CoachTools.text(input, "date") ?? today
            guard let back = daysBack(day) else { return (nil, "Give the day as YYYY-MM-DD.") }
            guard back >= 0 else { return (nil, "That day has not happened yet.") }
            guard back <= dayLookback else { return (nil, "That day is more than \(dayLookback) days ago.") }
            return (CoachChartSpec(kind: .day, day: day, series: series), nil)
        }
        let days = nearestPeriod(CoachTools.integer(input, "days", fallback: 30, in: 1...3650))
        if kind == .stacked {
            guard let id = CoachTools.text(input, "metric"), stack(id) != nil else {
                return (nil, "A stacked chart needs metric \(CoachChartSpec.Stack.sleepStages.rawValue) or "
                        + "\(CoachChartSpec.Stack.macros.rawValue).")
            }
            return (CoachChartSpec(kind: .stacked, metric: id, days: days, day: today), nil)
        }
        guard let metric = CoachTools.text(input, "metric"), descriptor(metric) != nil else {
            if stack(CoachTools.text(input, "metric")) != nil {
                return (nil, "That id is drawn as kind stacked.")
            }
            return (nil, "Give metric: one of the ids listed in the tool.")
        }
        var spec = CoachChartSpec(kind: kind, metric: metric, days: days, day: today)
        if kind == .pair {
            guard let second = CoachTools.text(input, "second_metric"), descriptor(second) != nil, second != metric else {
                return (nil, "A pair needs second_metric, another id listed in the tool.")
            }
            spec.second = second
        }
        return (spec, nil)
    }

    /// What `show_chart` answers once the card is shown: the figures it draws, for the model to comment on.
    /// Effort goes on the scale the card writes it on (`effortScale`, 0-100 or 0-21), so the reply and the
    /// card under it cannot give two numbers for one day.
    static func shownResult(_ spec: CoachChartSpec, first: [CoachChartPoint], second: [CoachChartPoint],
                            effortScale: EffortScale = .hundred) -> String {
        func line(_ name: String, _ points: [CoachChartPoint], _ id: String? = nil) -> String {
            let isEffort = descriptor(id)?.key == "strain"
            let values = points.map { isEffort ? UnitFormatter.effortValue($0.value, scale: effortScale) : $0.value }
            guard let stats = stats(values) else { return "\(name): no value in that period." }
            return "\(name): \(points.count) values, mean \(number(stats.mean)), usual range "
                + "\(number(stats.low))-\(number(stats.high)), lowest \(number(stats.lowest)), highest "
                + "\(number(stats.highest)), last \(number(stats.last))."
        }
        let head = "The chart is shown under your reply."
        switch spec.kind {
        case .day:
            let what = spec.series == .stress ? "Stress (0-3, hour by hour)" : "Heart rate (bpm, 5-minute averages)"
            return head + " " + line("\(what) on \(spec.day)", first)
        case .stacked:
            return head + " " + stackedSummary(spec, first)
        case .line, .bars, .pair:
            let period = "last \(spec.days ?? 30) days to \(spec.day)"
            var text = head + " " + line("\(wireName(spec.metric, effortScale: effortScale)) (\(period))",
                                         first, spec.metric)
            if spec.kind == .pair {
                text += " " + line(wireName(spec.second, effortScale: effortScale), second, spec.second)
            }
            return text
        }
    }

    /// A stacked series as the model reads it: what each day or night holds, part by part, with the means.
    /// Shared by `show_chart` and `get_series`, so both say the same of one period.
    static func stackedSummary(_ spec: CoachChartSpec, _ points: [CoachChartPoint]) -> String {
        let which = Self.stack(spec.metric) ?? .sleepStages
        let names = stackPartNames(which)
        let what = "\(wireName(spec.metric)), last \(spec.days ?? 30) days to \(spec.day)"
        guard !points.isEmpty else { return "\(what): no value in that period." }
        let means = names.indices.map { index -> String in
            let values = points.compactMap { index < $0.parts.count ? $0.parts[index] : nil }
            return "\(names[index]) \(number(values.reduce(0, +) / Double(max(values.count, 1))))"
        }
        let unit = which == .sleepStages ? "nights" : "days logged"
        return "\(what): \(points.count) \(unit); mean " + means.joined(separator: ", ") + "."
    }

    /// The parts of a stack, bottom to top, as the model reads them.
    static func stackPartNames(_ stack: CoachChartSpec.Stack) -> [String] {
        switch stack {
        case .sleepStages: return ["deep", "REM", "light"]
        case .macros: return ["protein", "carbs", "fat"]
        }
    }

    /// A metric as the model reads it: "Heart Rate Variability (ms)"; Effort with the scale the user reads it on.
    static func wireName(_ id: String?, effortScale: EffortScale = .hundred) -> String {
        switch stack(id) {
        case .sleepStages: return "Sleep stages (minutes asleep per night, the Sleep screen's nights)"
        case .macros: return "Macros (grams eaten per day, from the meal journal; a day without a meal logged is "
            + "not a day without food)"
        case nil: break
        }
        guard let descriptor = descriptor(id) else { return id ?? "?" }
        let unit = descriptor.displayUnit(effortScale: effortScale)
        return unit.isEmpty ? descriptor.title : "\(descriptor.title) (\(unit))"
    }

    /// A chart as a later turn reads it back: "[Chart shown: HRV, last 30 days to 2026-11-04]".
    static func wireText(_ spec: CoachChartSpec) -> String {
        switch spec.kind {
        case .day:
            return "[Chart shown: \(spec.series == .stress ? "stress" : "heart rate") on \(spec.day)]"
        case .line, .bars, .stacked:
            return "[Chart shown: \(wireName(spec.metric)), last \(spec.days ?? 30) days to \(spec.day)]"
        case .pair:
            return "[Chart shown: \(wireName(spec.metric)) and \(wireName(spec.second)), last \(spec.days ?? 30) days to \(spec.day)]"
        }
    }

    /// A figure as the model reads it: whole when it is, else one decimal.
    static func number(_ value: Double) -> String {
        abs(value - value.rounded()) < 0.05 ? String(Int(value.rounded())) : String(format: "%.1f", value)
    }

    // MARK: Figures

    /// What the card writes under a chart: the mean, the usual range (the middle half of the values: from
    /// the first to the third quartile), the lowest, the highest and the last value.
    struct Stats: Equatable {
        var mean: Double
        var low: Double
        var high: Double
        var lowest: Double
        var highest: Double
        var last: Double
    }

    /// The figures of `values` (in time order); nil when there is none.
    static func stats(_ values: [Double]) -> Stats? {
        guard let last = values.last else { return nil }
        let sorted = values.sorted()
        return Stats(mean: values.reduce(0, +) / Double(values.count),
                     low: quantile(sorted, 0.25), high: quantile(sorted, 0.75),
                     lowest: sorted[0], highest: sorted[sorted.count - 1], last: last)
    }

    /// The `q` quantile of sorted values, interpolated between the two nearest.
    static func quantile(_ sorted: [Double], _ q: Double) -> Double {
        guard sorted.count > 1 else { return sorted.first ?? 0 }
        let position = q * Double(sorted.count - 1)
        let below = Int(position.rounded(.down))
        let above = min(below + 1, sorted.count - 1)
        return sorted[below] + (sorted[above] - sorted[below]) * (position - Double(below))
    }

    /// The day keys of a period ending on `day` ("yyyy-MM-dd"), oldest first; empty when `day` is unreadable.
    static func windowDays(endingOn day: String, days: Int, calendar: Calendar) -> [String] {
        guard let end = dayDate(day, calendar: calendar) else { return [] }
        return (0..<max(1, days)).reversed().compactMap { back in
            calendar.date(byAdding: .day, value: -back, to: end).map { dayKey($0, calendar: calendar) }
        }
    }

    /// Local midnight of a "yyyy-MM-dd".
    static func dayDate(_ day: String, calendar: Calendar) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// "yyyy-MM-dd" of `date` in `calendar` (no formatter: stable whatever the locale).
    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let p = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", p.year ?? 0, p.month ?? 0, p.day ?? 0)
    }

    /// The days of a period with their values, oldest first; a day without one is left out.
    static func dailyPoints(_ values: [(day: String, value: Double)], window: [String],
                            calendar: Calendar) -> [CoachChartPoint] {
        let byDay = Dictionary(values.map { ($0.day, $0.value) }, uniquingKeysWith: { _, last in last })
        return window.compactMap { day in
            guard let value = byDay[day], let date = dayDate(day, calendar: calendar) else { return nil }
            return CoachChartPoint(date: date, value: value)
        }
    }

    /// The point nearest to `date` (the card's tap), nil without points.
    static func nearest(_ points: [CoachChartPoint], to date: Date) -> CoachChartPoint? {
        points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    /// A pair's points on a 0-1 scale of their own lowest and highest, so both lines share the chart.
    static func normalized(_ points: [CoachChartPoint]) -> [CoachChartPoint] {
        guard let lowest = points.map(\.value).min(), let highest = points.map(\.value).max() else { return [] }
        let span = highest - lowest
        return points.map { CoachChartPoint(date: $0.date, value: span > 0 ? ($0.value - lowest) / span : 0.5) }
    }
}

private extension CaseIterable where Self: RawRepresentable, Self.RawValue == String {
    static var allValues: [String] { allCases.map(\.rawValue) }
}
