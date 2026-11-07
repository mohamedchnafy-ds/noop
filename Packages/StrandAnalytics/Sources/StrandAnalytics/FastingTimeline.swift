import Foundation

// FastingTimeline.swift — pure arithmetic of an intermittent fast (personal fork, chantier 15).
//
// A fast is three stored values (start, end, goal in minutes; `FastRow` in WhoopStore). Everything the
// screens, the lock-screen banner, the notification and the Coach say about it comes from here, so they
// cannot disagree: the phase reached, the progress, what remains, where the phase markers sit on the
// ring, and the history figures. Integer minutes in, integers out; no clock, no store, no strings (the
// phase names and explanations are the app's, keyed by `phaseIds`).
//
// BYTE-IDENTICAL to the Android twin (com.noop.analytics.FastingTimeline): same thresholds, same integer
// division, same clamps. `FastingTimelineTests` and `FastingTimelineTest` check one shared expected block.
//
// The phases are the usual indicative landmarks of the fasting literature (hours since the last meal),
// NOT a measurement and NOT medical advice: 0 digestion · 4 insulin drop · 8 glycogen running low ·
// 12 fat burning · 16 ketosis · 24 autophagy (mostly animal data; beyond 24 h the app points to a doctor).
public enum FastingTimeline {

    // MARK: - Constants (mirror these EXACTLY in the Kotlin twin)

    /// Hour at which each phase starts, in the order of `phaseIds`.
    public static let phaseStartHours: [Int] = [0, 4, 8, 12, 16, 24]

    /// Stable identifiers of the phases: the app maps them to localized names and explanations.
    public static let phaseIds: [String] = ["digestion", "insulinDrop", "glycogen", "fatBurn", "ketosis", "autophagy"]

    /// Goal bounds, minutes: 12 h to 36 h, to the hour; 16 h the first time.
    public static let minGoalMinutes = 720
    public static let maxGoalMinutes = 2160
    public static let defaultGoalMinutes = 960

    /// The quick picks offered next to the wheel, hours.
    public static let quickGoalHours: [Int] = [14, 16, 18, 20]

    // MARK: - Types

    /// Where a phase starts on the ring: `permille` of the goal (0…1000).
    public struct Marker: Equatable, Sendable {
        public let phaseIndex: Int
        public let permille: Int
        public init(phaseIndex: Int, permille: Int) {
            self.phaseIndex = phaseIndex
            self.permille = permille
        }
    }

    /// The history figures over a run of days (one duration per day, 0 = no fast that day).
    public struct Summary: Equatable, Sendable {
        /// Mean length of the days with a fast, minutes (0 when none).
        public let averageMinutes: Int
        /// Days whose fast reached the goal.
        public let keptCount: Int
        /// Days with a fast at all.
        public let fastedCount: Int
        /// Consecutive days, ending with the newest, whose fast reached the goal.
        public let streak: Int
        public init(averageMinutes: Int, keptCount: Int, fastedCount: Int, streak: Int) {
            self.averageMinutes = averageMinutes
            self.keptCount = keptCount
            self.fastedCount = fastedCount
            self.streak = streak
        }
    }

    // MARK: - Pieces

    /// Index in `phaseIds` of the phase reached after `elapsedMinutes` (negative counts as 0).
    public static func fastingPhaseIndex(elapsedMinutes: Int) -> Int {
        let elapsed = max(elapsedMinutes, 0)
        var index = 0
        for (i, hour) in phaseStartHours.enumerated() where elapsed >= hour * 60 { index = i }
        return index
    }

    /// Progress toward the goal in permille, 0…1000 (integer division, so 999 until the goal is met);
    /// 0 for a goal of 0 or less.
    public static func fastingProgressPermille(elapsedMinutes: Int, goalMinutes: Int) -> Int {
        guard goalMinutes > 0 else { return 0 }
        let elapsed = max(elapsedMinutes, 0)
        return min(1000, (elapsed * 1000) / goalMinutes)
    }

    /// Minutes left before the goal, never negative.
    public static func fastingRemainingMinutes(elapsedMinutes: Int, goalMinutes: Int) -> Int {
        max(0, goalMinutes - max(elapsedMinutes, 0))
    }

    /// The phase starts that fall inside the goal (the first phase starts at 0 and has no marker), as
    /// permille of the goal, in phase order. The goal itself is a marker when a phase starts exactly there.
    public static func fastingMarkers(goalMinutes: Int) -> [Marker] {
        guard goalMinutes > 0 else { return [] }
        var out: [Marker] = []
        for i in 1..<phaseStartHours.count {
            let start = phaseStartHours[i] * 60
            if start <= goalMinutes { out.append(Marker(phaseIndex: i, permille: (start * 1000) / goalMinutes)) }
        }
        return out
    }

    /// History figures over `durationsMinutes`, one per day oldest first (0 = no fast). A goal of 0 or
    /// less keeps nothing.
    public static func fastingSummary(durationsMinutes: [Int], goalMinutes: Int) -> Summary {
        let fasted = durationsMinutes.filter { $0 > 0 }
        let average = fasted.isEmpty ? 0 : fasted.reduce(0, +) / fasted.count
        let kept = goalMinutes > 0 ? durationsMinutes.filter { $0 >= goalMinutes }.count : 0
        var streak = 0
        for duration in durationsMinutes.reversed() {
            if goalMinutes > 0 && duration >= goalMinutes { streak += 1 } else { break }
        }
        return Summary(averageMinutes: average, keptCount: kept, fastedCount: fasted.count, streak: streak)
    }

    /// A goal kept within the bounds, minutes.
    public static func clampGoalMinutes(_ minutes: Int) -> Int {
        min(maxGoalMinutes, max(minGoalMinutes, minutes))
    }
}
