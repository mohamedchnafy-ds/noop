import Foundation

// MARK: - `get_series`: every series of the app, read when the Coach needs it (personal fork, chantier 9 PR C)
//
// One read tool over everything Analyses lists (`MetricCatalog`, by the same `source:key` ids as
// `show_chart`), plus the sleep stages of each night and the macros of each day (`CoachChartSpec.Stack`).
// The values are read by `AICoachEngine.chartPoints`, the reader of the charts, so a series the Coach reads
// and the chart it then shows cannot differ. Nothing is sent until the model asks for it.
//
// PURE: the wording and the limits, tested without a strap.

extension CoachTools {
    /// The periods `get_series` reads, in days: a day to a year.
    static let seriesDayRange = 1...365
    /// Up to this many days the values go day by day; beyond, by 7-day blocks, so a year stays short.
    static let seriesDailyLimit = 92

    static var seriesDefinition: [String: Any] {
        ["name": Name.series.rawValue,
         "description": "Daily values of any series of the app over the last N days (oldest first): every metric "
            + "of Analyses by its id (source:key, the ids show_chart takes), "
            + "\(CoachChartSpec.Stack.sleepStages.rawValue) (deep, REM and light minutes of each night) or "
            + "\(CoachChartSpec.Stack.macros.rawValue) (protein, carbs and fat grams of each day). With how many "
            + "days have a value, the mean, the lowest and the highest; beyond \(seriesDailyLimit) days, by "
            + "7-day blocks. Use it when the fiche and get_metric_history do not carry the series.",
         "input_schema": [
            "type": "object",
            "properties": [
                "metric": ["type": "string", "enum": CoachChart.seriesIds],
                "days": ["type": "integer", "minimum": seriesDayRange.lowerBound,
                         "maximum": seriesDayRange.upperBound],
            ] as [String: Any],
            "required": ["metric", "days"],
         ] as [String: Any]]
    }

    /// The chart spec a `get_series` input reads through (a line, or a stacked chart for a stack), ending on
    /// `today` ("yyyy-MM-dd"); nil for an unknown id.
    static func seriesSpec(_ input: [String: Any], today: String) -> CoachChartSpec? {
        guard let id = text(input, "metric"),
              CoachChart.stack(id) != nil || CoachChart.descriptor(id) != nil else { return nil }
        let days = integer(input, "days", fallback: 30, in: seriesDayRange)
        return CoachChartSpec(kind: CoachChart.stack(id) != nil ? .stacked : .line, metric: id, days: days, day: today)
    }

    /// What `get_series` answers: the summary, then the days (or 7-day blocks) with their values.
    static func seriesResult(_ spec: CoachChartSpec, points: [CoachChartPoint], calendar: Calendar) -> String {
        let days = spec.days ?? 30
        let what = "\(CoachChart.wireName(spec.metric)), last \(days) days to \(spec.day)"
        guard !points.isEmpty else { return "\(what): no value in that period." }
        var lines: [String] = []
        let stack = CoachChart.stack(spec.metric)
        if stack != nil {
            lines.append(CoachChart.stackedSummary(spec, points))
        } else if let stats = CoachChart.stats(points.map(\.value)) {
            lines.append("\(what): \(points.count) of \(days) days with a value; mean \(CoachChart.number(stats.mean)), "
                         + "lowest \(CoachChart.number(stats.lowest)), highest \(CoachChart.number(stats.highest)).")
        }
        func valueText(_ value: Double, _ parts: [Double]) -> String {
            guard let stack else { return CoachChart.number(value) }
            let names = CoachChart.stackPartNames(stack)
            return names.indices.map { index in
                "\(names[index]) \(CoachChart.number(index < parts.count ? parts[index] : 0))"
            }.joined(separator: ", ")
        }
        if days <= seriesDailyLimit {
            lines.append("Day by day:")
            for point in points {
                lines.append("\(CoachChart.dayKey(point.date, calendar: calendar)): \(valueText(point.value, point.parts))")
            }
        } else {
            lines.append("By 7-day blocks (mean of the days with a value):")
            let window = CoachChart.windowDays(endingOn: spec.day, days: days, calendar: calendar)
            let byDay = Dictionary(points.map { (CoachChart.dayKey($0.date, calendar: calendar), $0) },
                                   uniquingKeysWith: { _, last in last })
            for start in stride(from: 0, to: window.count, by: 7) {
                let block = Array(window[start..<min(start + 7, window.count)])
                let inBlock = block.compactMap { byDay[$0] }
                guard let first = block.first, let last = block.last, !inBlock.isEmpty else { continue }
                let count = Double(inBlock.count)
                let mean = inBlock.map(\.value).reduce(0, +) / count
                let partCount = inBlock.map(\.parts.count).max() ?? 0
                let parts = (0..<partCount).map { index in
                    inBlock.map { index < $0.parts.count ? $0.parts[index] : 0 }.reduce(0, +) / count
                }
                lines.append("\(first) to \(last) (\(inBlock.count) days): \(valueText(mean, parts))")
            }
        }
        return lines.joined(separator: "\n")
    }
}
