import Foundation

// MARK: - My chart (fork chantier 17, step 3)
//
// The pure half of « My chart »: the saved-chart model, its on-device store and the engine that turns daily
// series into what the chart draws (windows, bucket averages, axis domains, ticks, the link between two
// measures). No SwiftUI and no database in here, so it is covered by tests that need no strap. The views
// are in `MyChartViews.swift`; the series are read by `MyChartData`.
//
// Stored on the device only (UserDefaults, outside the `.noopbak` whitelist), iPhone/macOS only: Android has
// no twin screen.

/// How one measure is drawn.
enum MyChartKind: String, Codable, CaseIterable, Identifiable {
    case line, bars, area, points
    var id: String { rawValue }
}

/// Which side's axis a measure reads against.
enum MyChartAxis: String, Codable, CaseIterable, Identifiable {
    case left, right
    var id: String { rawValue }
}

/// How an axis scale is chosen for a measure.
enum MyChartScale: String, Codable, CaseIterable, Identifiable {
    /// The measure's own range, with a little room.
    case auto
    /// From zero up.
    case zero
    /// The wearer's own minimum and maximum.
    case fixed
    var id: String { rawValue }
}

/// The one period of the whole editor: a week to a year, or all the history.
enum MyChartPeriod: String, Codable, CaseIterable, Identifiable {
    case week, month, quarter, half, year, all
    var id: String { rawValue }

    /// Days in the period; nil for « all » (from the first reading).
    var days: Int? {
        switch self {
        case .week: return 7
        case .month: return 30
        case .quarter: return 90
        case .half: return 180
        case .year: return 365
        case .all: return nil
        }
    }
}

/// One measure of a chart: which one, and how it is drawn.
struct MyChartItem: Codable, Equatable, Identifiable {
    /// `MetricDescriptor.id` (« source:key »).
    var metricID: String
    var kind: MyChartKind = .line
    var axis: MyChartAxis = .left
    var scale: MyChartScale = .auto
    /// Flips its axis (lower is up). An axis flips when any measure on it asks.
    var inverted = false
    var fixedMin: Double = 0
    var fixedMax: Double = 100

    var id: String { metricID }
}

/// A chart the wearer composed and saved.
struct MyChartSpec: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var items: [MyChartItem]
    var period: MyChartPeriod
    /// « Compare shapes »: each measure on 0–100 % of its own range, axes hidden.
    var normalized = false
    /// The chart the Today card opens on.
    var pinned = false

    /// The most measures one chart holds.
    static let maxItems = 4

    static func fresh(name: String, metricID: String) -> MyChartSpec {
        MyChartSpec(id: UUID().uuidString, name: name, items: [MyChartItem(metricID: metricID)],
                    period: .quarter, normalized: false, pinned: false)
    }
}

/// The saved charts, in a UserDefaults JSON list. Empty until the wearer saves a first one.
enum MyChartStore {
    static let key = "myChart.saved.v1"
    /// Whether the card shows on Today (a display preference, on by default).
    static let showOnTodayKey = "myChart.showOnToday"

    static func decodeSaved(_ raw: String) -> [MyChartSpec] {
        guard let data = raw.data(using: .utf8),
              let specs = try? JSONDecoder().decode([MyChartSpec].self, from: data) else { return [] }
        return specs
    }

    static func encodeSaved(_ specs: [MyChartSpec]) -> String {
        guard let data = try? JSONEncoder().encode(specs),
              let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }

    /// The pinned chart's position (the first when none is pinned).
    static func pinnedIndex(_ specs: [MyChartSpec]) -> Int {
        specs.firstIndex(where: \.pinned) ?? 0
    }

    /// `specs` with exactly the chart at `index` pinned (a second tap on the pinned one unpins it).
    static func pinning(_ specs: [MyChartSpec], at index: Int) -> [MyChartSpec] {
        guard specs.indices.contains(index) else { return specs }
        let wasPinned = specs[index].pinned
        var out = specs
        for i in out.indices { out[i].pinned = (i == index) && !wasPinned }
        return out
    }
}

/// One daily reading: a day number (days since 1970-01-01) and its value.
typealias MyChartDayValue = (day: Int, value: Double)

/// A point on the chart: the day it sits on (the middle of its bucket), its value, and its height as a
/// fraction of the plot (0 bottom, 1 top) once the axis is applied.
struct MyChartPoint: Equatable {
    var day: Double
    var value: Double
    var fraction: Double
}

/// What one measure draws.
struct MyChartResolved: Equatable {
    var item: MyChartItem
    var points: [MyChartPoint]
    /// Where bars start, as a fraction of the plot.
    var baseFraction: Double
}

/// An axis domain: the values at its bottom and top, and whether it is flipped.
struct MyChartAxisDomain: Equatable {
    var lower: Double
    var upper: Double
    var inverted: Bool
    /// The measure whose colour tints the axis' labels.
    var leadMetricID: String

    /// The height (0 bottom, 1 top) of `value`.
    func height(_ value: Double) -> Double {
        let t = upper > lower ? (value - lower) / (upper - lower) : 0.5
        return inverted ? 1 - t : t
    }
}

/// The window the chart shows, in day numbers.
struct MyChartWindow: Equatable {
    /// The first day of the period (before any zoom).
    var start: Int
    /// The last day of the period.
    var end: Int
    /// The zoomed range actually drawn.
    var lower: Int
    var upper: Int
}

enum MyChartEngine {
    // MARK: Days

    /// Days since 1970-01-01 of a « yyyy-MM-dd » day, nil when it does not parse.
    static func dayNumber(_ day: String) -> Int? {
        let parts = day.split(separator: "-")
        guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d) else { return nil }
        // Howard Hinnant's days-from-civil.
        let yy = m <= 2 ? y - 1 : y
        let era = (yy >= 0 ? yy : yy - 399) / 400
        let yoe = yy - era * 400
        let mp = (m + 9) % 12
        let doy = (153 * mp + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    /// The reverse of `dayNumber`: the date at 12:00 UTC of that day (noon keeps it on the same calendar day
    /// in every time zone).
    static func dateOfDay(day: Double) -> Date {
        Date(timeIntervalSince1970: day * 86_400 + 43_200)
    }

    // MARK: Window

    /// The period ending `offset` periods before `today` (0 = now), then narrowed to the zoom fractions
    /// `zoom` (0…1 of the period). « All » starts at `earliest` and ignores `offset`. A window is never
    /// shorter than a week.
    static func periodWindow(period: MyChartPeriod, offset: Int, zoom: ClosedRange<Double>,
                       today: Int, earliest: Int?) -> MyChartWindow {
        let minSpan = 6
        var start: Int
        var end: Int
        if let days = period.days {
            end = today - max(0, offset) * days
            start = end - days + 1
        } else {
            end = today
            start = min(earliest ?? today - 365, today - minSpan)
        }
        if end < start + minSpan { end = start + minSpan }
        let length = Double(end - start)
        var lower = start + Int((zoom.lowerBound * length).rounded())
        var upper = start + Int((zoom.upperBound * length).rounded())
        if upper - lower < minSpan {
            upper = min(end, lower + minSpan)
            lower = upper - minSpan
        }
        return MyChartWindow(start: start, end: end, lower: lower, upper: upper)
    }

    /// The days one point averages: a day up to 4 months, three days up to 8, a week beyond.
    static func bucketSize(span: Int) -> Int {
        span > 240 ? 7 : (span > 120 ? 3 : 1)
    }

    // MARK: Buckets

    /// `series` between `lower` and `upper`, averaged by `bucket` days. A bucket sits on the middle of the
    /// days it covers; a bucket with no reading has no point.
    static func bucketed(_ series: [MyChartDayValue], lower: Int, upper: Int, bucket: Int) -> [(day: Double, value: Double)] {
        let size = max(1, bucket)
        var sums: [Int: (sum: Double, count: Int)] = [:]
        for reading in series where reading.day >= lower && reading.day <= upper {
            let index = (reading.day - lower) / size
            let current = sums[index] ?? (0, 0)
            sums[index] = (current.sum + reading.value, current.count + 1)
        }
        return sums.keys.sorted().compactMap { index -> (day: Double, value: Double)? in
            guard let entry = sums[index], entry.count > 0 else { return nil }
            let first = lower + index * size
            let last = min(first + size - 1, upper)
            return (day: Double(first + last) / 2, value: entry.sum / Double(entry.count))
        }
    }

    // MARK: Axes

    /// Round tick values inside `lower…upper`, about `count` of them, with their step.
    static func axisTicks(lower: Double, upper: Double, count: Int = 4) -> (values: [Double], step: Double) {
        guard upper > lower, count > 0 else { return ([], 1) }
        let step = niceStep((upper - lower) / Double(count))
        var values: [Double] = []
        var v = (lower / step - 1e-9).rounded(.up) * step
        while v <= upper + 1e-9 {
            values.append((v * 1e6).rounded() / 1e6)
            v += step
        }
        return (values, step)
    }

    private static func niceStep(_ raw: Double) -> Double {
        let exponent = pow(10, floor(log10(raw)))
        let f = raw / exponent
        let nice: Double = f < 1.5 ? 1 : (f < 3 ? 2 : (f < 7 ? 5 : 10))
        return nice * exponent
    }

    /// What every measure draws, and its axes. `data` is the daily series by `MetricDescriptor.id`.
    static func resolveSeries(items: [MyChartItem], data: [String: [MyChartDayValue]], lower: Int, upper: Int,
                        normalized: Bool) -> (series: [MyChartResolved], left: MyChartAxisDomain?,
                                              right: MyChartAxisDomain?, bucket: Int) {
        let span = max(1, upper - lower)
        let bucket = bucketSize(span: span)

        struct Draft {
            var item: MyChartItem
            var raw: [(day: Double, value: Double)]
            var lo: Double
            var hi: Double
        }
        var drafts: [Draft] = []
        for item in items {
            let raw = bucketed(data[item.metricID] ?? [], lower: lower, upper: upper, bucket: bucket)
            let values = raw.map(\.value)
            let mn = values.min() ?? 0
            let mx = values.max() ?? 1
            var a: Double
            var b: Double
            if normalized {
                a = mn; b = mx
            } else if item.scale == .fixed {
                a = item.fixedMin; b = item.fixedMax
            } else if item.scale == .zero || item.kind == .bars {
                a = min(0, mn)
                b = mx > 0 ? mx * 1.1 : max(mx, 0) + 1
            } else {
                let pad = (mx - mn) * 0.14
                let room = pad > 0 ? pad : 1
                a = mn - room; b = mx + room
            }
            if b <= a { b = a + 1 }
            drafts.append(Draft(item: item, raw: raw, lo: a, hi: b))
        }

        // One domain per side: the union of the measures on it; it flips when any of them asks.
        var left: MyChartAxisDomain?
        var right: MyChartAxisDomain?
        if !normalized {
            for d in drafts {
                var domain = d.item.axis == .left ? left : right
                if var existing = domain {
                    existing.lower = min(existing.lower, d.lo)
                    existing.upper = max(existing.upper, d.hi)
                    existing.inverted = existing.inverted || d.item.inverted
                    domain = existing
                } else {
                    domain = MyChartAxisDomain(lower: d.lo, upper: d.hi, inverted: d.item.inverted,
                                               leadMetricID: d.item.metricID)
                }
                if d.item.axis == .left { left = domain } else { right = domain }
            }
        }

        let series: [MyChartResolved] = drafts.map { d in
            let domain: MyChartAxisDomain
            if normalized {
                domain = MyChartAxisDomain(lower: d.lo, upper: d.hi, inverted: d.item.inverted,
                                           leadMetricID: d.item.metricID)
            } else {
                domain = (d.item.axis == .left ? left : right) ?? MyChartAxisDomain(
                    lower: d.lo, upper: d.hi, inverted: false, leadMetricID: d.item.metricID)
            }
            let points = d.raw.map { MyChartPoint(day: $0.day, value: $0.value, fraction: domain.height($0.value)) }
            let base = normalized ? domain.height(d.lo) : domain.height(min(max(0, domain.lower), domain.upper))
            return MyChartResolved(item: d.item, points: points, baseFraction: base)
        }
        return (series, left, right, bucket)
    }

    // MARK: Cursor

    /// The point of `series` nearest to `day`, nil for an empty one.
    static func nearestPoint(_ series: MyChartResolved, to day: Double) -> MyChartPoint? {
        series.points.min { abs($0.day - day) < abs($1.day - day) }
    }

    // MARK: Link between two measures

    /// How strong a link is, from |r|.
    enum Link: Equatable {
        case negligible, weak, moderate, strong, veryStrong
    }

    static func link(_ r: Double) -> Link {
        let a = abs(r)
        if a < 0.2 { return .negligible }
        if a < 0.4 { return .weak }
        if a < 0.6 { return .moderate }
        if a < 0.8 { return .strong }
        return .veryStrong
    }

    /// Pearson's r over the days both series have a reading between `lower` and `upper`; nil under 7 shared
    /// days or when one series does not vary.
    static func correlation(_ a: [MyChartDayValue], _ b: [MyChartDayValue], lower: Int, upper: Int) -> Double? {
        var byDay: [Int: Double] = [:]
        for reading in b where reading.day >= lower && reading.day <= upper { byDay[reading.day] = reading.value }
        var xs: [Double] = []
        var ys: [Double] = []
        for reading in a where reading.day >= lower && reading.day <= upper {
            if let y = byDay[reading.day] { xs.append(reading.value); ys.append(y) }
        }
        let n = Double(xs.count)
        guard xs.count >= 7 else { return nil }
        let mx = xs.reduce(0, +) / n
        let my = ys.reduce(0, +) / n
        var sxy = 0.0, sxx = 0.0, syy = 0.0
        for i in xs.indices {
            sxy += (xs[i] - mx) * (ys[i] - my)
            sxx += (xs[i] - mx) * (xs[i] - mx)
            syy += (ys[i] - my) * (ys[i] - my)
        }
        guard sxx > 0, syy > 0 else { return nil }
        return sxy / (sxx * syy).squareRoot()
    }

    // MARK: Personal band

    /// The mean and half a standard deviation either side of it (the band Trends' Signals uses); nil under
    /// 7 readings.
    static func personalBand(_ values: [Double]) -> (mean: Double, low: Double, high: Double)? {
        guard values.count >= 7 else { return nil }
        let n = Double(values.count)
        let mean = values.reduce(0, +) / n
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / n
        let half = variance.squareRoot() / 2
        return (mean, mean - half, mean + half)
    }
}
