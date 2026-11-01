import Foundation
import WhoopStore

// MARK: - Habitual day (personal fork)
//
// The "usual day" under the Today heart-rate curve (a light area in Day mode, the top of the band in Live
// mode): for each five-minute slot of the day, the mean heart rate the wearer had in that slot over the
// previous fourteen days. Pure arithmetic over banked `HRBucket`s so `HabitualHRTests` can pin it without a
// store; the view only draws.

enum HabitualHR {
    /// Days of history the profile averages over.
    static let windowDays = 14
    /// The bucket width the profile and today's trace share, in seconds.
    static let bucketSeconds = 300
    /// A slot seen on fewer days than this is left empty: one odd afternoon is not a habit.
    static let minDaysPerSlot = 3

    /// Seconds into the local day of `ts`, in `zone`.
    static func secondsIntoDay(_ ts: Int, zone: TimeZone) -> Int {
        let local = ts + zone.secondsFromGMT(for: Date(timeIntervalSince1970: TimeInterval(ts)))
        return ((local % 86_400) + 86_400) % 86_400
    }

    /// The slot index of `ts` in a day of `bucketSeconds`-wide slots.
    static func slot(_ ts: Int, bucketSeconds: Int = bucketSeconds, zone: TimeZone) -> Int {
        secondsIntoDay(ts, zone: zone) / bucketSeconds
    }

    /// Slot → mean bpm across the days in `buckets`, keeping only slots that `minDaysPerSlot` or more
    /// days contributed to. Each bucket counts once; a day is whatever local day its bucket falls on.
    static func profile(buckets: [HRBucket], bucketSeconds: Int = bucketSeconds,
                        zone: TimeZone, minDays: Int = minDaysPerSlot) -> [Int: Double] {
        var sum: [Int: Double] = [:]
        var count: [Int: Int] = [:]
        for b in buckets {
            let s = slot(b.ts, bucketSeconds: bucketSeconds, zone: zone)
            sum[s, default: 0] += b.bpm
            count[s, default: 0] += 1
        }
        var out: [Int: Double] = [:]
        for (s, n) in count where n >= minDays { out[s] = sum[s]! / Double(n) }
        return out
    }

    /// The usual heart rate for the slot `ts` falls in: the top of the live card's band.
    static func usual(at ts: Int, profile: [Int: Double], bucketSeconds: Int = bucketSeconds,
                      zone: TimeZone) -> Double? {
        profile[slot(ts, bucketSeconds: bucketSeconds, zone: zone)]
    }
}
