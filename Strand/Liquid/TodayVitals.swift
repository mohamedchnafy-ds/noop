import Foundation
import StrandAnalytics
import WhoopProtocol
import WhoopStore

// MARK: - Today vitals (personal fork)
//
// The pure arithmetic behind the redesigned Today screen: the 30-night ranges and personal normal zones
// under the rings, the resting/activity calorie split and its goal, the heart-rate card's thresholds and
// its "away from your range while still" rule, and the usual wake time behind the suggested bedtime.
// Nothing here reads a store, a clock or a sensor; the view passes everything in, so every rule is pinned
// by `TodayVitalsTests` without a strap. Nothing here is stored either: each value is recomputed for
// display from data the app already keeps.

/// The half-gauge under the rings for a nightly vital (resting heart rate, HRV): where last night sits
/// between the lowest and highest of the recent nights, and the wearer's own normal band.
enum TodayVitalRange {
    /// Nights the range spans: the most recent nights that recorded the vital, up to the day shown.
    static let windowNights = 30
    /// σ multiplier for the normal band: the same robust spread the Charge baseline scores against
    /// (`RecoveryScorer.zScore` divides by 1.253 × spread), so "normal" here is |z| ≤ 1 there.
    static let spreadToSigma = 1.253

    struct Gauge: Equatable {
        let value: Double
        let low: Double
        let high: Double
        /// The personal normal band, clamped to `low...high`. Nil while the baseline is calibrating.
        let normal: ClosedRange<Double>?

        /// Where `v` sits between `low` and `high`, 0…1.
        func fraction(_ v: Double) -> Double {
            guard high > low else { return 0.5 }
            return min(1, max(0, (v - low) / (high - low)))
        }
    }

    /// The personal normal band from the baseline the Charge score uses, or nil while it is not usable
    /// (calibration), so the gauge shows no band rather than a guessed one.
    static func normalBand(_ state: BaselineState?) -> ClosedRange<Double>? {
        guard let state, state.usable, state.baseline.isFinite, state.spread.isFinite else { return nil }
        let sigma = spreadToSigma * state.spread
        return (state.baseline - sigma)...(state.baseline + sigma)
    }

    /// The gauge for `value`, ranged over the last `windowNights` nights on or before `throughDay` that
    /// recorded the vital. The shown value is always inside its own range. Nil when there is no value.
    static func gauge(value: Double?, history: [(day: String, value: Double)], throughDay: String,
                      normal: ClosedRange<Double>?) -> Gauge? {
        guard let value, value.isFinite else { return nil }
        let recent = history
            .filter { $0.day <= throughDay && $0.value.isFinite }
            .sorted { $0.day < $1.day }
            .suffix(windowNights)
            .map(\.value)
        let lowest = min(recent.min() ?? value, value)
        let highest = max(recent.max() ?? value, value)
        let clamped = normal.flatMap { band -> ClosedRange<Double>? in
            let lo = max(lowest, band.lowerBound), hi = min(highest, band.upperBound)
            return lo <= hi ? lo...hi : nil
        }
        return Gauge(value: value, low: lowest, high: highest, normal: clamped)
    }
}

/// Today's energy split into resting and activity calories, and the activity goal the half-gauge fills
/// toward. Recomputed from the day's heart rate with the SAME estimator and inputs the stored daily total
/// comes from (`Calories.estimateDayEnergy`), so the two parts always add up to that total.
enum TodayEnergy {
    /// Complete days the default goal averages over.
    static let goalWindowDays = 14
    /// Fewer complete days with activity than this and there is no default goal (an empty gauge beats a
    /// goal made up from one day).
    static let minGoalDays = 3
    /// UserDefaults key for the goal set in Settings, in kcal; 0 (or unset) means the default.
    static let goalKey = "today.activityKcalGoal"

    struct Split: Equatable {
        let restingKcal: Double
        let activityKcal: Double
        var totalKcal: Double { restingKcal + activityKcal }
    }

    /// The day's split from its heart rate, or nil when there is none.
    static func split(hr: [HRSample], profile: UserProfile, hrmax: Double?, restingHR: Double?) -> Split? {
        guard !hr.isEmpty else { return nil }
        let e = Calories.estimateDayEnergy(hr, profile: profile, hrmax: hrmax, restingHR: restingHR)
        return Split(restingKcal: e.restingKcal, activityKcal: e.activeKcal)
    }

    /// The default goal: the mean activity of the recent complete days that recorded any, or nil when
    /// fewer than `minGoalDays` did.
    static func defaultGoal(activityByDay: [Double]) -> Double? {
        let days = activityByDay.filter { $0.isFinite && $0 > 0 }
        guard days.count >= minGoalDays else { return nil }
        return days.reduce(0, +) / Double(days.count)
    }

    /// The goal shown: the one set in Settings when there is one, else the default.
    static func goal(setting: Int, defaultGoal: Double?) -> Double? {
        setting > 0 ? Double(setting) : defaultGoal
    }

    /// How the half-gauge is filled, left to right: resting, then activity.
    struct Arc: Equatable {
        let resting: Double
        let activity: Double
        /// Where the goal sits once it has been passed (the scale stretches past it), else nil.
        let goalMark: Double?
    }

    /// The scale is resting-so-far plus the activity goal, so the gauge is full exactly when the goal is
    /// met; past it the scale stretches to the activity done and a mark keeps the goal visible. With no
    /// goal the two parts simply share the gauge.
    static func arc(_ split: Split, goal: Double?) -> Arc {
        let rest = max(0, split.restingKcal), act = max(0, split.activityKcal)
        guard let goal, goal > 0 else {
            let total = rest + act
            guard total > 0 else { return Arc(resting: 0, activity: 0, goalMark: nil) }
            return Arc(resting: rest / total, activity: act / total, goalMark: nil)
        }
        let scale = rest + max(goal, act)
        guard scale > 0 else { return Arc(resting: 0, activity: 0, goalMark: nil) }
        return Arc(resting: rest / scale, activity: act / scale,
                   goalMark: act > goal ? (rest + goal) / scale : nil)
    }
}

/// The heart-rate card's "away from your range while still" rule: when the live curve turns orange.
enum TodayHRAlert {
    /// The high threshold sits this far above the wearer's usual rate for the time of day.
    static let highMarginBpm = 20.0
    /// The live rate must stay beyond a threshold this long, and the phone must have been still as long.
    static let minDurationSec = 180
    /// A gap between live samples longer than this breaks a run (the strap dropped out).
    static let maxGapSec = 15
    /// Days of 5-minute averages the awake floor looks back over, and how many must contribute.
    static let floorWindowDays = 14
    static let floorMinDays = 3

    enum Side: Equatable { case high, low }

    struct Thresholds: Equatable {
        let high: Double?
        let low: Double?
    }

    struct Crossing: Equatable {
        let side: Side
        let threshold: Double
        /// When the rate first went past the threshold in the current run.
        let sinceTs: Int
        func minutes(now: Int) -> Int { max(0, now - sinceTs) / 60 }
    }

    /// High = usual at this time + `highMarginBpm`; low = the awake floor.
    static func thresholds(usualNow: Double?, awakeFloor: Double?) -> Thresholds {
        Thresholds(high: usualNow.map { $0 + highMarginBpm }, low: awakeFloor)
    }

    /// The run of the latest samples beyond one threshold, when it has lasted `minDurationSec`. Samples
    /// are oldest first. Only the heart rate is judged here; the caller adds the activity gates.
    static func crossing(samples: [(ts: Int, bpm: Double)], thresholds: Thresholds, now: Int) -> Crossing? {
        guard let last = samples.last else { return nil }
        let side: Side
        let threshold: Double
        if let high = thresholds.high, last.bpm > high {
            side = .high; threshold = high
        } else if let low = thresholds.low, last.bpm < low {
            side = .low; threshold = low
        } else {
            return nil
        }
        func beyond(_ bpm: Double) -> Bool { side == .high ? bpm > threshold : bpm < threshold }
        var start = last.ts
        var next = last.ts
        for s in samples.reversed().dropFirst() {
            guard beyond(s.bpm), next - s.ts <= maxGapSec else { break }
            start = s.ts
            next = s.ts
        }
        guard now - last.ts <= maxGapSec, now - start >= minDurationSec else { return nil }
        return Crossing(side: side, threshold: threshold, sinceTs: start)
    }

    /// The full rule: a crossing counts only with no session running and the phone still. `phoneStill`
    /// nil (no motion data, or no permission) never shows an alert.
    static func alert(crossing: Crossing?, sessionRunning: Bool, phoneStill: Bool?) -> Crossing? {
        guard let crossing, !sessionRunning, phoneStill == true else { return nil }
        return crossing
    }

    /// The lowest 5-minute average while awake: every bucket outside `sleep` (sleep blocks and naps, as
    /// unix-second ranges), over buckets spanning at least `floorMinDays` days. Nil when too few days.
    static func awakeFloor(buckets: [HRBucket], sleep: [ClosedRange<Int>], zone: TimeZone) -> Double? {
        var days = Set<Int>()
        var lowest: Double?
        for b in buckets where b.bpm.isFinite && b.bpm > 0 {
            guard !sleep.contains(where: { $0.contains(b.ts) }) else { continue }
            let local = b.ts + zone.secondsFromGMT(for: Date(timeIntervalSince1970: TimeInterval(b.ts)))
            days.insert(Int((Double(local) / 86_400).rounded(.down)))
            lowest = min(lowest ?? b.bpm, b.bpm)
        }
        return days.count >= floorMinDays ? lowest : nil
    }
}

/// The usual wake time behind the suggested bedtime: the median wake of the recent main nights.
enum HabitualWake {
    static let windowNights = 14
    static let minNights = 3

    /// The usual wake as minutes after local midnight, from the main nights' end times (oldest first).
    /// Circular, so wakes either side of midnight average sensibly. Nil when fewer than `minNights`.
    static func minutes(wakeTimestamps: [Int], zone: TimeZone) -> Int? {
        let recent = wakeTimestamps.suffix(windowNights)
        guard recent.count >= minNights else { return nil }
        let mins = recent.map { ts -> Double in
            let local = ts + zone.secondsFromGMT(for: Date(timeIntervalSince1970: TimeInterval(ts)))
            return Double(((local % 86_400) + 86_400) % 86_400) / 60
        }
        // Rotate so the circular mean sits at noon, take the plain median there, rotate back.
        let angles = mins.map { $0 / 1440 * 2 * Double.pi }
        let meanAngle = atan2(angles.map(sin).reduce(0, +), angles.map(cos).reduce(0, +))
        let meanMin = (meanAngle < 0 ? meanAngle + 2 * .pi : meanAngle) / (2 * .pi) * 1440
        let shift = 720 - meanMin
        let shifted = mins.map { ($0 + shift + 1440).truncatingRemainder(dividingBy: 1440) }.sorted()
        let mid = shifted.count / 2
        let median = shifted.count.isMultiple(of: 2) ? (shifted[mid - 1] + shifted[mid]) / 2 : shifted[mid]
        let back = (median - shift + 1440).truncatingRemainder(dividingBy: 1440)
        return Int(back.rounded()) % 1440
    }

    /// The bedtime that leaves `needMinutes` of sleep before `wakeMinutes`, as minutes after midnight.
    static func bedtime(wakeMinutes: Int, needMinutes: Double) -> Int {
        let raw = wakeMinutes - Int(needMinutes.rounded())
        return ((raw % 1440) + 1440) % 1440
    }
}
