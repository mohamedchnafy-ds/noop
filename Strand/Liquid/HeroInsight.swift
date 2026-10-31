import Foundation

// MARK: - Hero insight (personal fork)
//
// The pure arithmetic behind the lines drawn UNDER each Today hero bubble (Charge / Effort / Rest): the
// gap between the day shown and its own recent past, and the short trend that gap sits in. The view
// only formats; everything that can be wrong lives here, where `HeroInsightTests` can see it.

enum HeroInsight {
    /// Days of history one bubble compares itself against.
    static let windowDays = 7
    /// Fewer prior readings than this and the mean is noise, so no gap is claimed.
    static let minPriorPoints = 3

    struct Trend: Equatable {
        /// `value` minus the mean of the prior window, on the same scale as `value`. Nil when the day has
        /// no value or the window holds fewer than `minPriorPoints` readings.
        var delta: Double?
        /// One slot per calendar day of the window, oldest first and ending on the day shown. A nil slot
        /// is a day nothing was recorded, drawn as a gap rather than as zero.
        var bars: [Double?]
    }

    /// Day keys are the store's `YYYY-MM-DD` strings. Arithmetic runs on a fixed UTC calendar so the
    /// same keys yield the same window whatever the device's zone or DST state.
    private static let utc: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    private static func date(fromDayKey key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return utc.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    private static func dayKey(_ date: Date) -> String {
        let c = utc.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// The `count` consecutive day keys ending on `day` (inclusive), oldest first.
    static func dayKeys(endingOn day: String, count: Int) -> [String] {
        guard count > 0, let end = date(fromDayKey: day) else { return [] }
        return (0..<count).reversed().compactMap { back in
            utc.date(byAdding: .day, value: -back, to: end).map(dayKey)
        }
    }

    /// The gap and trend for one bubble.
    /// - Parameters:
    ///   - value: what the bubble shows for `day` (which may be a live or carried number, not the stored
    ///     row), already on the display scale.
    ///   - series: stored values by day key, on the SAME scale as `value`.
    ///   - day: the day shown.
    static func trend(value: Double?, series: [String: Double], day: String,
                      windowDays: Int = windowDays) -> Trend {
        let barKeys = dayKeys(endingOn: day, count: windowDays)
        var bars: [Double?] = barKeys.map { series[$0] }
        // The last slot is the day shown: the bubble's own number, so the bar and the number agree.
        if !bars.isEmpty { bars[bars.count - 1] = value ?? bars[bars.count - 1] }

        let prior = dayKeys(endingOn: day, count: windowDays + 1).dropLast().compactMap { series[$0] }
        guard let value, prior.count >= minPriorPoints else {
            return Trend(delta: nil, bars: bars)
        }
        let mean = prior.reduce(0, +) / Double(prior.count)
        return Trend(delta: value - mean, bars: bars)
    }

    /// "+6" / "−4" / "0" at `decimals` places, with a true minus sign. The arrow glyph is the view's job
    /// (it carries colour); this is only the number.
    static func deltaText(_ delta: Double, decimals: Int, locale: Locale) -> String {
        let rounded = (delta * pow(10, Double(decimals))).rounded() / pow(10, Double(decimals))
        if rounded == 0 { return decimals > 0 ? String(format: "%.\(decimals)f", locale: locale, 0.0) : "0" }
        let magnitude = String(format: "%.\(decimals)f", locale: locale, abs(rounded))
        return (rounded > 0 ? "+" : "−") + magnitude
    }

    /// Which way the arrow points: nil when the gap rounds to zero.
    static func direction(_ delta: Double, decimals: Int) -> Bool? {
        let scale = pow(10, Double(decimals))
        let rounded = (delta * scale).rounded() / scale
        if rounded == 0 { return nil }
        return rounded > 0
    }

    /// "7 h 20" style hours-and-minutes for a sleep duration, or nil when there is nothing to say.
    static func sleepParts(minutes: Double?) -> (hours: Int, minutes: Int)? {
        guard let minutes, minutes > 0 else { return nil }
        let total = Int(minutes.rounded())
        return (total / 60, total % 60)
    }
}
