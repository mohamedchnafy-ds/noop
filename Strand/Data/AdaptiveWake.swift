import Foundation

// Personal fork, chantier 25 — the overnight half of the adaptive wake: the detector, the session that drives
// it through one window, and the learning from the wake question. Pure: no BLE, no notification, no clock of
// its own, so every decision is testable with a fixed `Date`.

/// The light-sleep heuristic, ported from Android's `SleepWindowWatcher` (#207).
///
/// During deep sleep the heart rate sits near its nightly trough and is steady; in a lighter phase or on an
/// arousal it lifts above it. The detector keeps the lowest smoothed reading of the night (the trough) and
/// fires once the reading has stayed `riseBpm` above it for `sustainSamples` samples in a row. A coarse
/// "you are stirring" signal, not a sleep-stage classifier, and it claims nothing clinical. With no heart rate
/// (strap off, link down) it never fires, and the strap's alarm at the deadline wakes the wearer.
///
/// Differences from the Android twin, both deliberate: the reading must hold for `sustainSamples` (one
/// smoothed spike is not a phase), and the trough is gathered before the window opens (`feed(_:inWindow:)`),
/// because a trough taken only inside a 30-minute window is not the night's.
struct AdaptiveWakeDetector: Equatable {
    /// How far above the trough (bpm) counts as a lighter phase. Learned from the wake question.
    var riseBpm: Int
    /// Samples needed before the trough is trusted.
    var minSamples = 30
    /// Consecutive in-window samples above the threshold before it fires.
    var sustainSamples = 3
    /// Readings above this are never a trough candidate (the wearer got up for a moment).
    var troughCeilingBpm = 90

    private(set) var trough: Int?
    private(set) var samples = 0
    private(set) var above = 0
    private(set) var fired = false

    init(riseBpm: Int) { self.riseBpm = riseBpm }

    /// Folds one smoothed reading in. Returns true exactly once: the first time, inside the window, the reading
    /// has held a lighter phase for long enough. Readings before the window only build the trough.
    mutating func feed(_ bpm: Int, inWindow: Bool) -> Bool {
        guard bpm > 0 else { return false }
        samples += 1
        if bpm <= troughCeilingBpm, bpm < (trough ?? Int.max) { trough = bpm }
        guard !fired else { return false }
        guard inWindow, samples >= minSamples, let floor = trough else {
            above = 0
            return false
        }
        if bpm >= floor + riseBpm {
            above += 1
            if above >= sustainSamples {
                fired = true
                return true
            }
        } else {
            above = 0
        }
        return false
    }
}

/// One window's night: when to sample, when to buzz, when to buzz again.
///
/// Fed every live heart-rate tick by the app (`AdaptiveWakeController`). It samples at most every
/// `sampleInterval`, from `observeLead` before the window opens; the detector's first firing is the wake, and a
/// sleeper who missed it gets up to `buzzCount` buzzes `rebuzzInterval` apart, never past the deadline. The
/// deadline itself belongs to the strap's firmware alarm, which this never touches.
struct AdaptiveWakeSession: Equatable {
    static let observeLead: TimeInterval = 3 * 3600
    static let sampleInterval: TimeInterval = 10
    static let rebuzzInterval: TimeInterval = 45
    static let buzzCount = 3

    /// What the app does after a tick.
    enum Step: Equatable {
        case none
        /// The detector fired: first buzz, the notification, the journal entry.
        case wake
        /// A repeat buzz for a sleeper who did not stir at the first.
        case rebuzz
    }

    let window: WakeWindow
    private(set) var detector: AdaptiveWakeDetector
    private(set) var lastSampleAt: Date?
    private(set) var firedAt: Date?
    private(set) var firedBpm: Int?
    private(set) var buzzes = 0
    private(set) var lastBuzzAt: Date?
    /// Set when the wearer says they are up: no more buzzes.
    private(set) var stopped = false

    init(window: WakeWindow, riseBpm: Int) {
        self.window = window
        self.detector = AdaptiveWakeDetector(riseBpm: riseBpm)
    }

    /// True from `observeLead` before the window to its deadline: the span the app listens to the heart over.
    func isObserving(at now: Date) -> Bool {
        window.adaptive && now >= window.start.addingTimeInterval(-Self.observeLead) && now < window.deadline
    }

    mutating func stop() { stopped = true }

    /// One tick: `bpm` is the app's smoothed live heart rate (nil when none is streaming).
    mutating func observe(bpm: Int?, at now: Date) -> Step {
        guard !stopped, now < window.deadline else { return .none }
        if firedAt != nil {
            guard buzzes < Self.buzzCount, let last = lastBuzzAt,
                  now.timeIntervalSince(last) >= Self.rebuzzInterval else { return .none }
            buzzes += 1
            lastBuzzAt = now
            return .rebuzz
        }
        guard isObserving(at: now), let bpm else { return .none }
        if let last = lastSampleAt, now.timeIntervalSince(last) < Self.sampleInterval { return .none }
        lastSampleAt = now
        guard detector.feed(bpm, inWindow: window.contains(now)) else { return .none }
        firedAt = now
        firedBpm = bpm
        buzzes = 1
        lastBuzzAt = now
        return .wake
    }
}

/// The one-tap answer after a wake.
enum WakeFeeling: String, Codable, Equatable {
    case tired
    case fresh
}

/// One morning's wake, kept for the question and for the learning.
struct WakeEvent: Codable, Equatable {
    /// The window's id (`WakeWindow.id`): one entry per morning per alarm.
    var id: String
    var kind: WakeAlarmKind
    var windowStart: Date
    var deadline: Date
    var wokeAt: Date
    /// True when the adaptive buzz woke the wearer, false for the deadline.
    var adaptive: Bool
    var trough: Int?
    var bpmAtWake: Int?
    /// The threshold the detector ran with that night.
    var riseBpm: Int?
    var feeling: WakeFeeling?
    var answeredAt: Date?
}

/// The learning, by replay: the threshold is a pure function of the answered wakes, so it is the same
/// whichever screen or process asks, and a deleted journal simply starts again from the default.
enum WakeLearning {
    static let defaultRiseBpm = 6
    static let minRiseBpm = 4
    static let maxRiseBpm = 12
    /// The answers a decision looks at.
    static let lookback = 5
    /// Tired answers among the last `lookback` that make the detector stricter (+1 bpm).
    static let tiredToRaise = 3
    /// Fresh answers among the last `lookback` that make it more sensitive again (−1 bpm).
    static let freshToLower = 4

    /// The threshold for `kind`'s next night.
    ///
    /// Only adaptive wakes count: a deadline wake says nothing about the detector. Walking the answers in
    /// order, three tired among the last five raise the rise by 1 bpm (wait for a clearer lighter phase), four
    /// fresh lower it by 1; either decision starts a new count, so one bad week moves it once, not five times.
    static func riseBpm(history: [WakeEvent], kind: WakeAlarmKind) -> Int {
        var rise = defaultRiseBpm
        var recent: [WakeFeeling] = []
        let answered = history
            .filter { $0.kind == kind && $0.adaptive && $0.feeling != nil }
            .sorted { $0.wokeAt < $1.wokeAt }
        for event in answered {
            guard let feeling = event.feeling else { continue }
            recent.append(feeling)
            let window = recent.suffix(lookback)
            if window.filter({ $0 == .tired }).count >= tiredToRaise {
                rise = min(maxRiseBpm, rise + 1)
                recent = []
            } else if window.filter({ $0 == .fresh }).count >= freshToLower {
                rise = max(minRiseBpm, rise - 1)
                recent = []
            }
        }
        return rise
    }

    /// How many answers the threshold of `kind` stands on.
    static func answeredCount(history: [WakeEvent], kind: WakeAlarmKind) -> Int {
        history.filter { $0.kind == kind && $0.adaptive && $0.feeling != nil }.count
    }

    /// The wake still waiting for its answer: the latest unanswered one, up to `maxAge` after it.
    static func pendingQuestion(history: [WakeEvent], now: Date, maxAge: TimeInterval = 12 * 3600) -> WakeEvent? {
        history
            .filter { $0.feeling == nil && $0.wokeAt <= now && now.timeIntervalSince($0.wokeAt) <= maxAge }
            .max { $0.wokeAt < $1.wokeAt }
    }

    /// `history` with `event` in it: an entry of the same id is replaced, keeping an answer it already had and
    /// the earlier of the two wake times (the adaptive buzz, not the deadline that followed). The newest
    /// `limit` stay.
    static func upserting(_ event: WakeEvent, into history: [WakeEvent], limit: Int = 90) -> [WakeEvent] {
        var out = history
        if let index = out.firstIndex(where: { $0.id == event.id }) {
            var merged = event
            let old = out[index]
            if old.wokeAt < merged.wokeAt {
                merged.wokeAt = old.wokeAt
                merged.adaptive = old.adaptive
                merged.trough = old.trough ?? merged.trough
                merged.bpmAtWake = old.bpmAtWake ?? merged.bpmAtWake
                merged.riseBpm = old.riseBpm ?? merged.riseBpm
            }
            if merged.feeling == nil {
                merged.feeling = old.feeling
                merged.answeredAt = old.answeredAt
            }
            out[index] = merged
        } else {
            out.append(event)
        }
        out.sort { $0.wokeAt < $1.wokeAt }
        return Array(out.suffix(limit))
    }
}
