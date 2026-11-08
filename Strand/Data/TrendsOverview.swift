import Foundation
import StrandAnalytics
import WhoopStore

// MARK: - Trends overview (fork chantier 16)
//
// The pure half of the redesigned Trends screen: which days a period covers, how the period compares
// with the one before it, which quadrant a day falls in on the Charge / Effort plane, the personal
// normal band a signal is read against, and the columns the day-by-day grid is bucketed into.
//
// Everything here is deterministic and framework-free so `StrandTests` pins it without rendering a
// view. Day keys are the banked `yyyy-MM-dd` strings; calendar arithmetic goes through the weekly
// digest engine's civil-day helpers so a week here is the same Monday–Sunday week the digest uses.
// App-side only (no stored data, no Kotlin twin): Android keeps its own Trends screen.
enum TrendsOverview {

    // MARK: Periods

    /// An inclusive day span, both bounds `yyyy-MM-dd`.
    struct Window: Equatable {
        let start: String
        let end: String

        /// Calendar days covered, inclusive. Degenerate spans count as one day.
        var dayCount: Int {
            max(1, (TrendsOverview.civilDaysBetween(start, end) ?? 0) + 1)
        }
    }

    /// The window a range selects, stepped back `offset` whole periods from `today` (0 = the period
    /// containing today). Weeks are Monday–Sunday like the digest, so "this week" can end in the future;
    /// every other range is a trailing block of `range.days` ending today. `.all` has no window: the
    /// caller reads the whole history.
    static func window(range: TrendsView.Range, offset: Int, today: String) -> Window? {
        guard let n = range.days else { return nil }
        let back = max(0, offset)
        if range == .week {
            guard let monday = WeeklyDigestEngine.mondayOfWeek(containing: today) else { return nil }
            let start = WeeklyDigestEngine.addDays(monday, -7 * back)
            return Window(start: start, end: WeeklyDigestEngine.addDays(start, 6))
        }
        let end = WeeklyDigestEngine.addDays(today, -n * back)
        return Window(start: WeeklyDigestEngine.addDays(end, -(n - 1)), end: end)
    }

    /// The period immediately before `window`, of the same length: what the Bilan compares against.
    static func previous(_ window: Window) -> Window {
        let n = window.dayCount
        return Window(start: WeeklyDigestEngine.addDays(window.start, -n),
                      end: WeeklyDigestEngine.addDays(window.end, -n))
    }

    /// The banked days inside `window` (all of `days` when the window is nil), in their stored order.
    static func days(_ days: [DailyMetric], in window: Window?) -> [DailyMetric] {
        guard let w = window else { return days }
        return days.filter { $0.day >= w.start && $0.day <= w.end }
    }

    /// How many whole periods back the stepper may go before it would pass the earliest banked day.
    /// 0 when history is empty or the earliest day is already inside the current period.
    static func maxOffset(range: TrendsView.Range, earliestDay: String?, today: String) -> Int {
        guard let earliest = earliestDay else { return 0 }
        var offset = 0
        while offset < 520, let w = window(range: range, offset: offset, today: today), w.start > earliest {
            offset += 1
        }
        return offset
    }

    // MARK: Means and changes

    static func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Period mean of one metric over `days`, skipping nil readings.
    static func mean(_ days: [DailyMetric], _ value: (DailyMetric) -> Double?) -> Double? {
        mean(days.compactMap(value))
    }

    /// Signed change of a period mean against the previous period's, as points and as a percentage of the
    /// previous mean (nil when the previous mean is zero). nil when either side has no reading.
    struct Change: Equatable {
        let delta: Double
        let percent: Double?
    }

    static func change(current: Double?, previous: Double?) -> Change? {
        guard let c = current, let p = previous else { return nil }
        let delta = c - p
        let percent: Double? = abs(p) > 0.0001 ? delta / p * 100 : nil
        return Change(delta: delta, percent: percent)
    }

    // MARK: Charge / Effort quadrants

    /// Where a day sits on the Charge / Effort plane. Both axes are the stored 0–100 scales, split at
    /// their midpoints: `overreaching` is a hard day on a low Charge, `underused` a green Charge left
    /// unspent, `optimal` effort placed on recovery, `recovering` a quiet day on a low Charge.
    enum Quadrant: CaseIterable, Equatable {
        case optimal, overreaching, recovering, underused
    }

    static let chargeThreshold = 50.0
    static let effortThreshold = 50.0

    static func quadrant(charge: Double, effort: Double) -> Quadrant {
        let highCharge = charge >= chargeThreshold
        let highEffort = effort >= effortThreshold
        switch (highCharge, highEffort) {
        case (true, true):   return .optimal
        case (false, true):  return .overreaching
        case (false, false): return .recovering
        case (true, false):  return .underused
        }
    }

    /// One plotted day: both readings present.
    struct BalancePoint: Equatable {
        let day: String
        let charge: Double
        let effort: Double
        var quadrant: Quadrant { TrendsOverview.quadrant(charge: charge, effort: effort) }
    }

    static func balancePoints(_ days: [DailyMetric]) -> [BalancePoint] {
        days.compactMap { d in
            guard let c = d.recovery, let e = d.strain else { return nil }
            return BalancePoint(day: d.day, charge: c, effort: e)
        }
    }

    static func tally(_ points: [BalancePoint]) -> [Quadrant: Int] {
        var t: [Quadrant: Int] = [:]
        for q in Quadrant.allCases { t[q] = 0 }
        for p in points { t[p.quadrant, default: 0] += 1 }
        return t
    }

    /// The one-line reading of a tally. Thresholds are deliberately coarse: half the days in one
    /// quadrant is a pattern, under three plotted days is nothing yet.
    enum BalanceReading: Equatable {
        case tooFew
        case overreaching(days: Int, of: Int)
        case underused(days: Int, of: Int)
        case optimal(days: Int, of: Int)
        case mixed
    }

    static func reading(_ points: [BalancePoint]) -> BalanceReading {
        let n = points.count
        guard n >= 3 else { return .tooFew }
        let t = tally(points)
        let over = t[.overreaching] ?? 0
        let under = t[.underused] ?? 0
        let opt = t[.optimal] ?? 0
        if over * 2 >= n { return .overreaching(days: over, of: n) }
        if under * 5 >= n * 2 { return .underused(days: under, of: n) }
        if opt * 2 >= n { return .optimal(days: opt, of: n) }
        return .mixed
    }

    // MARK: Bilan sentence

    /// The one line under the Bilan's three gauges: how Charge and Effort moved together against the
    /// previous period. A thin previous period is named as such rather than read as a trend.
    enum BilanReading: Equatable {
        case noPrevious
        case sparsePrevious(days: Int)
        case bothUp
        case loadUpChargeDown
        case loadDownChargeUp
        case bothDown
        case steady
    }

    /// Fewer banked days than this in the previous period and the comparison is called rough.
    static let bilanMinimumPreviousDays = 3
    /// Points (on the 0–100 scales) a period mean must move before it counts as a move.
    static let bilanMoveThreshold = 3.0

    static func bilanReading(chargeDelta: Double?, effortDelta: Double?, previousDays: Int) -> BilanReading {
        guard previousDays > 0, chargeDelta != nil || effortDelta != nil else { return .noPrevious }
        if previousDays < bilanMinimumPreviousDays { return .sparsePrevious(days: previousDays) }
        let c = chargeDelta ?? 0
        let e = effortDelta ?? 0
        let t = bilanMoveThreshold
        let chargeUp = c >= t, chargeDown = c <= -t
        let effortUp = e >= t, effortDown = e <= -t
        if chargeUp && effortUp { return .bothUp }
        if chargeDown && effortUp { return .loadUpChargeDown }
        if chargeUp && effortDown { return .loadDownChargeUp }
        if chargeDown && effortDown { return .bothDown }
        return .steady
    }

    // MARK: Personal normal band

    /// A signal's personal normal: its mean over the band window ± half a standard deviation, the
    /// "smallest worthwhile change" band the HRV readiness experiment reads nightly HRV against.
    struct Band: Equatable {
        let mean: Double
        let sd: Double
        var low: Double { mean - 0.5 * sd }
        var high: Double { mean + 0.5 * sd }
    }

    /// Fewer readings than this and no band is claimed: a band from three nights is noise with edges.
    static let bandMinimumReadings = 7

    static func band(_ values: [Double]) -> Band? {
        guard values.count >= bandMinimumReadings, let m = mean(values) else { return nil }
        let variance = values.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(values.count)
        let sd = variance.squareRoot()
        guard sd.isFinite, m.isFinite else { return nil }
        return Band(mean: m, sd: sd)
    }

    /// Days the band is folded over, counted back from the period's end. Longer than the period itself,
    /// so a week is read against a month and a quarter against a year.
    static func bandDays(for range: TrendsView.Range) -> Int {
        switch range {
        case .week: return 30
        case .month: return 90
        case .quarter: return 180
        case .half, .year, .all: return 365
        }
    }

    /// The window the band is folded over: `bandDays` ending where the period ends.
    static func bandWindow(for period: Window, range: TrendsView.Range) -> Window {
        Window(start: WeeklyDigestEngine.addDays(period.end, -(bandDays(for: range) - 1)), end: period.end)
    }

    enum Deviation: Equatable { case below, inside, above }

    static func deviation(_ value: Double, band: Band) -> Deviation {
        if value < band.low { return .below }
        if value > band.high { return .above }
        return .inside
    }

    /// Where a value sits on the row's axis, 0…1. The axis spans the mean ± 2 SD, so the band itself
    /// occupies 0.375…0.625 of the row and a reading well outside it still lands on the track.
    static func axisPosition(_ value: Double, band: Band) -> Double {
        guard band.sd > 0.0001 else { return 0.5 }
        let z = (value - band.mean) / band.sd
        return min(0.97, max(0.03, 0.5 + z / 4))
    }

    // MARK: Grid columns

    enum Bucket: Equatable { case day, week, month }

    /// One column per day for a week, per Monday-aligned week up to a quarter, per calendar month beyond.
    static func bucket(for range: TrendsView.Range) -> Bucket {
        switch range {
        case .week: return .day
        case .month, .quarter: return .week
        case .half, .year, .all: return .month
        }
    }

    struct Column: Equatable {
        let start: String
        let end: String
        /// True for the first column of a month (week buckets) — where the month label is printed.
        var isMonthStart: Bool {
            guard let (_, sm, _) = WeeklyDigestEngine.parseYMD(start),
                  let (_, em, _) = WeeklyDigestEngine.parseYMD(end) else { return false }
            if start.hasSuffix("-01") { return true }
            return sm != em
        }
    }

    /// The columns covering `window`, clipped to it at both ends.
    static func columns(window: Window, bucket: Bucket) -> [Column] {
        switch bucket {
        case .day:
            var out: [Column] = []
            var d = window.start
            while d <= window.end, out.count < 400 {
                out.append(Column(start: d, end: d))
                d = WeeklyDigestEngine.addDays(d, 1)
            }
            return out
        case .week:
            guard let firstMonday = WeeklyDigestEngine.mondayOfWeek(containing: window.start) else { return [] }
            var out: [Column] = []
            var monday = firstMonday
            while monday <= window.end, out.count < 120 {
                let sunday = WeeklyDigestEngine.addDays(monday, 6)
                out.append(Column(start: max(monday, window.start), end: min(sunday, window.end)))
                monday = WeeklyDigestEngine.addDays(monday, 7)
            }
            return out
        case .month:
            guard let (y0, m0, _) = WeeklyDigestEngine.parseYMD(window.start) else { return [] }
            var out: [Column] = []
            var y = y0, m = m0
            while out.count < 60 {
                let first = String(format: "%04d-%02d-01", y, m)
                guard first <= window.end else { break }
                let (ny, nm) = m == 12 ? (y + 1, 1) : (y, m + 1)
                let last = WeeklyDigestEngine.addDays(String(format: "%04d-%02d-01", ny, nm), -1)
                out.append(Column(start: max(first, window.start), end: min(last, window.end)))
                y = ny; m = nm
            }
            return out
        }
    }

    /// Mean of one metric over the days a column covers, nil when none of them carry it.
    static func columnMean(_ days: [DailyMetric], column: Column, _ value: (DailyMetric) -> Double?) -> Double? {
        mean(days.filter { $0.day >= column.start && $0.day <= column.end }, value)
    }
}

extension TrendsOverview {
    /// Civil days from `a` to `b` (negative when `b` is earlier), via the digest engine's pure parse.
    static func civilDaysBetween(_ a: String, _ b: String) -> Int? {
        guard let (ya, ma, da) = WeeklyDigestEngine.parseYMD(a),
              let (yb, mb, db) = WeeklyDigestEngine.parseYMD(b) else { return nil }
        return civilDayNumber(yb, mb, db) - civilDayNumber(ya, ma, da)
    }

    /// Days since 1970-01-01 for a proleptic Gregorian date (the standard civil-day algorithm).
    private static func civilDayNumber(_ y: Int, _ m: Int, _ d: Int) -> Int {
        let yy = m <= 2 ? y - 1 : y
        let era = (yy >= 0 ? yy : yy - 399) / 400
        let yoe = yy - era * 400
        let mp = (m + 9) % 12
        let doy = (153 * mp + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }
}
