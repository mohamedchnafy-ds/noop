import Foundation
import WhoopProtocol

// The heart rate of a strength session (fork chantier 18, maquette 3 « FC en musculation »): the curve of
// the last minutes with its rests and the end of each set, the average and the max, the recovery between
// sets, and the curves of the previous sessions of the same program, aligned on the time elapsed since
// their start. Pure: samples and instants in, figures out, so a test can drive it with no strap.
//
// Display only. Nothing here is stored or feeds a score: Effort stays what the strap measured over the
// session's window (`StrainScorer`), and the zone is the one every live tile shows (`HRZoneSet`).

enum LiftHeartRateMath {

    /// The live curve's span and bucket, the same as the live workout's (`LiveWorkoutMath`).
    static let liveWindowSec = LiveWorkoutMath.curveWindow
    static let liveBucketSec = LiveWorkoutMath.curveBucket
    /// How many earlier sessions the comparison draws.
    static let comparedSessions = 2
    /// A rest shorter than this says nothing about recovery: the heart rate has not had time to fall.
    static let minRecoveryRestSec = 20
    /// The heart rate keeps rising for a few seconds after the last rep, so a set's peak is looked for
    /// up to this long after it ended.
    static let peakLagSec = 10

    /// A done set as the heart rate reads it: when it ran, and the rest taken after it (nil while that
    /// rest is still running).
    struct SetSpan: Equatable {
        var start: Int
        var end: Int
        var restSec: Int?
    }

    /// `samples` between `from` (excluded) and `to` (included), averaged per `bucket` seconds, oldest
    /// first; nil for a bucket with no sample.
    static func bucketCurve(_ samples: [HRSample], from: Int, to: Int, bucket: Int) -> [Double?] {
        guard bucket > 0, to > from else { return [] }
        let count = Int((Double(to - from) / Double(bucket)).rounded(.up))
        var sums = Array(repeating: 0, count: count)
        var counts = Array(repeating: 0, count: count)
        for sample in samples where sample.ts > from && sample.ts <= to {
            let index = min(count - 1, (sample.ts - from - 1) / bucket)
            sums[index] += sample.bpm
            counts[index] += 1
        }
        return (0..<count).map { counts[$0] > 0 ? Double(sums[$0]) / Double(counts[$0]) : nil }
    }

    /// A previous session's curve laid on this one's clock: its samples between `fromElapsed` and
    /// `toElapsed` seconds after ITS start, in the same buckets. Pauses are not taken out of either side,
    /// so the two curves can drift by the length of a pause; the comparison is a guide, not a measure.
    static func alignedCurve(_ samples: [HRSample], sessionStart: Int,
                             fromElapsed: Int, toElapsed: Int, bucket: Int) -> [Double?] {
        bucketCurve(samples, from: sessionStart + fromElapsed, to: sessionStart + toElapsed, bucket: bucket)
    }

    /// Average and highest heart rate of `samples`, nil without any.
    static func averageAndPeak(_ samples: [HRSample]) -> (average: Int, peak: Int)? {
        guard !samples.isEmpty, let peak = samples.map(\.bpm).max() else { return nil }
        let average = Int((Double(samples.map(\.bpm).reduce(0, +)) / Double(samples.count)).rounded())
        return (average, peak)
    }

    /// How far the heart rate came down after one set: its highest point from the set's start to
    /// `peakLagSec` after its end, minus its lowest point during the rest that followed (up to `now` for
    /// the rest still running). Nil when either side has no sample, the rest is shorter than
    /// `minRecoveryRestSec`, or the heart rate did not come down.
    static func recovery(after set: SetSpan, samples: [HRSample], now: Int) -> Int? {
        let restEnd = set.restSec.map { set.end + $0 } ?? now
        guard restEnd - set.end >= minRecoveryRestSec else { return nil }
        let peakEnd = min(restEnd, set.end + peakLagSec)
        let peak = samples.filter { $0.ts >= set.start && $0.ts <= peakEnd }.map(\.bpm).max()
        let low = samples.filter { $0.ts > set.end && $0.ts <= restEnd }.map(\.bpm).min()
        guard let peak, let low, peak > low else { return nil }
        return peak - low
    }

    /// The recovery after each set that has one, in the order of `sets`.
    static func recoveries(_ sets: [SetSpan], samples: [HRSample], now: Int) -> [Int] {
        sets.compactMap { recovery(after: $0, samples: samples, now: now) }
    }

    /// The average of `values`, rounded; nil when empty.
    static func mean(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        return Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
    }

    /// Each exercise's average heart rate over its own sets, in the order the exercises first appear.
    static func averageByExercise(_ sets: [(exercise: String, start: Int, end: Int)],
                                  samples: [HRSample]) -> [(exercise: String, average: Int)] {
        var order: [String] = []
        var values: [String: [Int]] = [:]
        for set in sets where set.end > set.start {
            if values[set.exercise] == nil { order.append(set.exercise) }
            values[set.exercise, default: []] += samples
                .filter { $0.ts >= set.start && $0.ts <= set.end }.map(\.bpm)
        }
        return order.compactMap { name in mean(values[name] ?? []).map { (name, $0) } }
    }

    /// Where `ts` falls in the window `[from, to]`, as a fraction 0…1; nil outside it.
    static func fraction(_ ts: Int, from: Int, to: Int) -> Double? {
        guard to > from, ts >= from, ts <= to else { return nil }
        return Double(ts - from) / Double(to - from)
    }

    /// The rests of `sets` inside the window, as fractions of it, clipped to its edges. A rest still
    /// running reaches `now`.
    static func restSpans(_ sets: [SetSpan], from: Int, to: Int, now: Int) -> [ClosedRange<Double>] {
        guard to > from else { return [] }
        return sets.compactMap { set in
            let restEnd = set.restSec.map { set.end + $0 } ?? now
            let lo = max(set.end, from), hi = min(restEnd, to)
            guard hi > lo else { return nil }
            return (Double(lo - from) / Double(to - from))...(Double(hi - from) / Double(to - from))
        }
    }
}
