import Foundation
import WhoopStore

// Personal fork, chantier 15 PR C: « Nights of fasting », the strap's figures of the nights spent fasting
// against the other nights (mockup board 4 « Autour »), with the Map's « Ce qui ressort » rule: a
// difference is shown only beyond its margin of error, « — » otherwise, and the card waits under five
// nights on either side. PURE: nights and fasts in, figures out; tested in `FastingNightsTests`. The
// nights are built as the Map builds them (the longest sleep block of three hours or more ending each
// day, with that day's scores), over the last 90 days (Mohamed, 8 Nov.).

/// One night with the figures the card compares.
struct FastingNight: Equatable {
    /// The logical day the night belongs to ("yyyy-MM-dd").
    var day: String
    /// Unix seconds: when the sleep began.
    var sleepStart: Int
    var durationMin: Double?
    var hrvMs: Double?
    var restingHr: Double?
}

enum FastingNightMetric: String, CaseIterable, Identifiable {
    case hrv, restingHr, sleep
    var id: String { rawValue }

    /// Higher is better for HRV and sleep; lower is better for the resting heart rate.
    var higherIsBetter: Bool { self != .restingHr }

    func value(_ night: FastingNight) -> Double? {
        switch self {
        case .hrv: return night.hrvMs
        case .restingHr: return night.restingHr
        case .sleep: return night.durationMin
        }
    }
}

/// How the fasting nights compare to the others on one figure.
enum FastingNightVerdict: Equatable {
    /// The difference is larger than its margin, in the good direction.
    case better
    /// Larger than its margin, in the bad direction.
    case worse
    /// Within its margin: nothing to show.
    case close
    /// Fewer than `FastingNights.minNightsEachSide` nights on one side.
    case tooFew
}

struct FastingNightFigure: Equatable, Identifiable {
    var metric: FastingNightMetric
    /// Mean over the fasting nights, in the figure's unit (ms, bpm, minutes).
    var fastingMean: Double?
    /// Mean over the other nights.
    var otherMean: Double?
    /// fasting − other.
    var delta: Double?
    /// Half-width of the 95 % interval of the difference of the two means; nil under two values on a side.
    var margin: Double?
    var fastingCount: Int
    var otherCount: Int
    var verdict: FastingNightVerdict

    var id: String { metric.rawValue }
}

enum FastingNights {

    /// The period, as the Map's: « 90 derniers jours ».
    static let days = 90
    /// Nights needed on EACH side before a difference is shown.
    static let minNightsEachSide = 5
    /// A night counts as a fasting night when a fast at least this long was running at bedtime.
    static let minFastMinutes = 720
    /// A sleep block shorter than this is a nap, not a night (the Map's rule).
    static let minNightSeconds = 3 * 3_600

    // MARK: Nights

    /// Every night of the period: the longest sleep block of three hours or more ending each day, with that
    /// day's resting heart rate, HRV and sleep. `dayKey` is injected so the rule is tested without a calendar.
    static func fastingNightsFromBlocks(_ blocks: [CachedSleepSession], metricsByDay: [String: DailyMetric],
                                        dayKey: (Int) -> String) -> [FastingNight] {
        var longest: [String: CachedSleepSession] = [:]
        for block in blocks where block.endTs - block.effectiveStartTs >= minNightSeconds {
            let key = dayKey(block.endTs)
            if let kept = longest[key], kept.endTs - kept.effectiveStartTs >= block.endTs - block.effectiveStartTs {
                continue
            }
            longest[key] = block
        }
        return longest.keys.sorted().compactMap { key in
            guard let block = longest[key] else { return nil }
            let metric = metricsByDay[key]
            return FastingNight(day: key, sleepStart: block.effectiveStartTs,
                                durationMin: metric?.totalSleepMin ?? Double(block.endTs - block.effectiveStartTs) / 60,
                                hrvMs: metric?.avgHrv ?? block.avgHrv,
                                restingHr: (metric?.restingHr ?? block.restingHr).map(Double.init))
        }
    }

    /// Whether a fast of `minFastMinutes` or more (a running one counts up to `now`) was running at the
    /// night's bedtime.
    static func isFastingNight(_ night: FastingNight, fasts: [FastRow], now: Int) -> Bool {
        fasts.contains { fast in
            let end = fast.endedAt ?? now
            return end - fast.startedAt >= minFastMinutes * 60
                && fast.startedAt <= night.sleepStart && night.sleepStart < end
        }
    }

    static func splitFastingNights(_ nights: [FastingNight], fasts: [FastRow],
                                   now: Int) -> (fasting: [FastingNight], others: [FastingNight]) {
        var fasting: [FastingNight] = []
        var others: [FastingNight] = []
        for night in nights {
            if isFastingNight(night, fasts: fasts, now: now) { fasting.append(night) } else { others.append(night) }
        }
        return (fasting, others)
    }

    // MARK: Figures

    /// The half-width of the 95 % interval of the difference of two means (Welch): 1.96 × √(s₁²/n₁ + s₂²/n₂),
    /// from the sample variances; nil under two values on either side.
    static func marginOfDifference(_ a: [Double], _ b: [Double]) -> Double? {
        guard a.count >= 2, b.count >= 2 else { return nil }
        func variance(_ values: [Double]) -> Double {
            let n = Double(values.count)
            let mean = values.reduce(0, +) / n
            return values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / (n - 1)
        }
        return 1.96 * (variance(a) / Double(a.count) + variance(b) / Double(b.count)).squareRoot()
    }

    /// One figure: the fasting nights' mean against the others', with the « Ce qui ressort » verdict.
    static func fastingNightFigure(_ metric: FastingNightMetric, fasting: [FastingNight],
                                   others: [FastingNight]) -> FastingNightFigure {
        let a = fasting.compactMap(metric.value)
        let b = others.compactMap(metric.value)
        let meanA = a.isEmpty ? nil : a.reduce(0, +) / Double(a.count)
        let meanB = b.isEmpty ? nil : b.reduce(0, +) / Double(b.count)
        var figure = FastingNightFigure(metric: metric, fastingMean: meanA, otherMean: meanB, delta: nil, margin: nil,
                                        fastingCount: a.count, otherCount: b.count, verdict: .tooFew)
        guard let meanA, let meanB else { return figure }
        figure.delta = meanA - meanB
        figure.margin = marginOfDifference(a, b)
        guard a.count >= minNightsEachSide, b.count >= minNightsEachSide else { return figure }
        if let delta = figure.delta, let margin = figure.margin, abs(delta) > margin {
            figure.verdict = (delta > 0) == metric.higherIsBetter ? .better : .worse
        } else {
            figure.verdict = .close
        }
        return figure
    }

    /// The three figures, HRV · resting HR · sleep.
    static func fastingNightFigures(fasting: [FastingNight], others: [FastingNight]) -> [FastingNightFigure] {
        FastingNightMetric.allCases.map { fastingNightFigure($0, fasting: fasting, others: others) }
    }

    /// What the card shows.
    struct Report: Equatable {
        var figures: [FastingNightFigure]
        var fastingCount: Int
        var otherCount: Int
        /// Nights still missing on each side before a difference can show (0 when enough).
        var missingFasting: Int { max(0, FastingNights.minNightsEachSide - fastingCount) }
        var missingOthers: Int { max(0, FastingNights.minNightsEachSide - otherCount) }
        var waiting: Bool { missingFasting > 0 || missingOthers > 0 }
    }

    static func fastingNightsReport(nights: [FastingNight], fasts: [FastRow], now: Int) -> Report {
        let split = splitFastingNights(nights, fasts: fasts, now: now)
        return Report(figures: fastingNightFigures(fasting: split.fasting, others: split.others),
                      fastingCount: split.fasting.count, otherCount: split.others.count)
    }

    // MARK: Loading

    /// The report over the last `days` days, from the sleep blocks and day scores the Map reads and the
    /// fasts of the period.
    @MainActor
    static func loadFastingNights(repo: Repository, now: Date = Date()) async -> Report {
        guard let store = await repo.storeHandle() else { return Report(figures: [], fastingCount: 0, otherCount: 0) }
        let from = now.addingTimeInterval(-Double(days) * 86_400)
        let blocks = await repo.allSleepSessions(days: days + 1).filter { $0.endTs >= Int(from.timeIntervalSince1970) }
        let dayKey: (Int) -> String = { MealJournal.mealDayKey(Date(timeIntervalSince1970: TimeInterval($0))) }
        var metricsByDay: [String: DailyMetric] = [:]
        if let first = blocks.map({ dayKey($0.endTs) }).min(), let last = blocks.map({ dayKey($0.endTs) }).max() {
            let metrics = await repo.dailyMetrics(fromDay: first, toDay: last)
            metricsByDay = Dictionary(metrics.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        }
        let nights = fastingNightsFromBlocks(blocks, metricsByDay: metricsByDay, dayKey: dayKey)
        let fasts = await FastingLog.fasts(store, from: from.addingTimeInterval(-36 * 3600), to: now.addingTimeInterval(1))
        return fastingNightsReport(nights: nights, fasts: fasts, now: Int(now.timeIntervalSince1970))
    }
}
