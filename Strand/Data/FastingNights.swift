import Foundation
import WhoopStore

// Personal fork, chantier 15 PR C: « Nuits de jeûne », the nights spent inside a fast of 12 h or more
// against the other nights of the last 30 days, for HRV, resting heart rate and sleep. PURE: inputs are
// plain arrays (the nights the Carte already selects, `PlaceMapReader.nightsForPlaces`, and the fasts), so
// the rule is tested on its own (`FastingNightsTests`).
//
// The rule of the Carte's « Ce qui ressort » (`PlaceStandouts`): a difference is shown only when it is a
// verdict (past the « proche » band of `PlaceMetrics`) AND larger than its margin of error; « — » otherwise.
// Here two groups are compared, so the margin is the 95 % interval of the difference of two means,
// 1.96 × √(s₁²/n₁ + s₂²/n₂). Under 5 nights on either side, the card says it is waiting. Never a cause.

/// One night, with the three figures compared.
struct FastingNightSample: Equatable {
    var day: String
    /// Unix seconds: the middle of the sleep. The night is a fasting night when it falls inside a fast.
    var midSleep: Int
    var hrvMs: Double?
    var restingHR: Double?
    var sleepMin: Double?
}

/// The figure a tile is about.
enum FastingNightMetric: String, CaseIterable {
    case hrv, restingHR, sleep
}

/// One tile: the two means, their difference, its margin, and whether it is shown.
struct FastingNightFigure: Equatable {
    var metric: FastingNightMetric
    /// Mean of the fasting nights, nil without one.
    var fastingMean: Double?
    var otherMean: Double?
    /// fastingMean − otherMean.
    var delta: Double?
    var margin: Double?
    /// Better, worse, close, or too few nights for this figure.
    var verdict: PlaceVerdict
    /// Shown only past the band and past the margin; « — » otherwise.
    var shown: Bool { (verdict == .better || verdict == .worse) && delta != nil && margin != nil
        && abs(delta ?? 0) > (margin ?? .infinity) }
}

struct FastingNightsResult: Equatable {
    var fastingCount: Int
    var otherCount: Int
    var figures: [FastingNightFigure]
    /// Under `FastingNights.minNightsEachSide` on either side: the card waits.
    var waiting: Bool
}

enum FastingNights {

    /// The window, days.
    static let windowDays = 30
    /// A fast counts from 12 h (the owner's choice, 8 Nov 2026).
    static let minFastMinutes = 720
    /// Nights needed on each side before any difference is read.
    static let minNightsEachSide = 5

    /// Whether `night` falls inside a fast of `minFastMinutes` or more (a running fast counts up to `now`).
    static func isFastingNight(_ night: FastingNightSample, fasts: [FastRow], now: Int) -> Bool {
        fasts.contains { fast in
            let end = fast.endedAt ?? now
            return end - fast.startedAt >= minFastMinutes * 60 && fast.startedAt <= night.midSleep && night.midSleep < end
        }
    }

    /// The « proche » band and the direction of each figure: the Carte's (HRV ±3 ms, heart rate ±3 bpm,
    /// sleep ±20 min).
    static func nightBand(_ metric: FastingNightMetric) -> (band: Double, higherIsBetter: Bool) {
        switch metric {
        case .hrv: return (PlaceMetrics.closeBand(.hrv), true)
        case .restingHR: return (PlaceMetrics.closeBand(.heartRate), false)
        case .sleep: return (PlaceMetrics.sleepCloseBandMin, true)
        }
    }

    /// The 95 % margin of the difference of two means; nil under two values on either side.
    static func marginOfDifference(_ a: [Double], _ b: [Double]) -> Double? {
        guard a.count >= 2, b.count >= 2 else { return nil }
        func varianceOverN(_ v: [Double]) -> Double {
            let n = Double(v.count)
            let mean = v.reduce(0, +) / n
            return v.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / (n - 1) / n
        }
        return 1.96 * (varianceOverN(a) + varianceOverN(b)).squareRoot()
    }

    static func nightValue(_ night: FastingNightSample, _ metric: FastingNightMetric) -> Double? {
        switch metric {
        case .hrv: return night.hrvMs
        case .restingHR: return night.restingHR
        case .sleep: return night.sleepMin
        }
    }

    /// The comparison of the nights given (already limited to the window) against the fasts.
    static func compareFastingNights(_ nights: [FastingNightSample], fasts: [FastRow], now: Int) -> FastingNightsResult {
        var fasting: [FastingNightSample] = []
        var other: [FastingNightSample] = []
        for night in nights {
            if isFastingNight(night, fasts: fasts, now: now) { fasting.append(night) } else { other.append(night) }
        }
        let figures = FastingNightMetric.allCases.map { metric -> FastingNightFigure in
            let a = fasting.compactMap { nightValue($0, metric) }
            let b = other.compactMap { nightValue($0, metric) }
            let meanA = a.isEmpty ? nil : a.reduce(0, +) / Double(a.count)
            let meanB = b.isEmpty ? nil : b.reduce(0, +) / Double(b.count)
            guard let meanA, let meanB else {
                return FastingNightFigure(metric: metric, fastingMean: meanA, otherMean: meanB, delta: nil,
                                          margin: nil, verdict: .none)
            }
            let delta = meanA - meanB
            let margin = marginOfDifference(a, b)
            guard a.count >= minNightsEachSide, b.count >= minNightsEachSide else {
                return FastingNightFigure(metric: metric, fastingMean: meanA, otherMean: meanB, delta: delta,
                                          margin: margin, verdict: .tooFew)
            }
            let rule = nightBand(metric)
            return FastingNightFigure(metric: metric, fastingMean: meanA, otherMean: meanB, delta: delta, margin: margin,
                                      verdict: PlaceMetrics.placeVerdict(delta: delta, band: rule.band,
                                                                         higherIsBetter: rule.higherIsBetter))
        }
        return FastingNightsResult(fastingCount: fasting.count, otherCount: other.count, figures: figures,
                                   waiting: fasting.count < minNightsEachSide || other.count < minNightsEachSide)
    }

    // MARK: Loading

    /// The nights of the last `windowDays` days (the Carte's selection: the longest sleep ending each day,
    /// with that day's scores and resting heart rate) against the fasts that overlap them.
    @MainActor
    static func loadFastingNights(repo: Repository, now: Date = Date()) async -> FastingNightsResult? {
        guard let store = await repo.storeHandle() else { return nil }
        let nowSec = Int(now.timeIntervalSince1970)
        let cutoff = Calendar.current.date(byAdding: .day, value: -windowDays, to: now) ?? now
        let cutoffKey = MealJournal.mealDayKey(cutoff)
        let blocks = await repo.allSleepSessions(days: windowDays + 1)
        let nights = await PlaceMapReader.nightsForPlaces(repo: repo, blocks: blocks).filter { $0.day > cutoffKey }
        var restingByDay: [String: Double] = [:]
        if let first = nights.first?.day, let last = nights.last?.day {
            for metric in await repo.dailyMetrics(fromDay: first, toDay: last) {
                if let bpm = metric.restingHr, restingByDay[metric.day] == nil { restingByDay[metric.day] = Double(bpm) }
            }
        }
        let samples = nights.map { night in
            FastingNightSample(day: night.day, midSleep: night.sleepStart + Int(((night.durationMin ?? 0) * 30).rounded()),
                               hrvMs: night.hrvMs, restingHR: restingByDay[night.day], sleepMin: night.durationMin)
        }
        // A fast that began up to 36 h before the window can still cover its first night.
        let fasts = await FastingLog.fasts(store, from: cutoff.addingTimeInterval(-36 * 3_600),
                                           to: now.addingTimeInterval(1))
        return compareFastingNights(samples, fasts: fasts, now: nowSec)
    }
}
