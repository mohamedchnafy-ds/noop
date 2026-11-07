import Foundation
import WhoopStore

// Personal fork, chantier 14 step 2: the place layers and the points layer of the Map (mockup v1 screens
// 3, 4 and 7). PURE: inputs are plain arrays (visits, nights, heart-rate buckets, stress windows), so
// the rules are tested on their own (`PlaceMetricsTests`). What is shown is an ÉCART to the wearer's own
// normal, never a raw value alone, and never a cause.

/// The metric a place layer colours by.
enum PlaceLayer: String, CaseIterable, Identifiable {
    case heartRate, stress, hrv, recovery
    var id: String { rawValue }
}

/// How a place (or a point) compares to the wearer's normal.
enum PlaceVerdict: String, Codable, Equatable {
    /// Better than the normal (light blue).
    case better
    /// Within the band around the normal (grey).
    case close
    /// Worse than the normal (orange).
    case worse
    /// Not enough data for a difference (hollow).
    case tooFew
    /// Nothing to compare (no night there, only workouts…).
    case none
}

/// One night, already scored, with where it began.
struct PlaceNight: Equatable {
    /// The logical day the night belongs to ("yyyy-MM-dd").
    var day: String
    /// Unix seconds: when the sleep began.
    var sleepStart: Int
    var durationMin: Double?
    var hrvMs: Double?
    var recoveryPct: Double?
}

/// One five-minute heart-rate bucket.
struct PlaceHRBucket: Codable, Equatable {
    var ts: Int
    var bpm: Double
}

/// One scored stress window.
struct PlaceStressWindow: Codable, Equatable {
    var start: Int
    var end: Int
    /// 0 calm … 3; nil when unscored.
    var level: Double?
    /// Left unscored because the wearer was moving.
    var moving: Bool = false
}

/// A place's figures for one layer.
struct PlaceFigure: Codable, Equatable {
    /// The place's own value (bpm, % of time in High stress, ms, % recovery).
    var value: Double?
    /// The wearer's normal for the same thing (same hours elsewhere for heart rate).
    var normal: Double?
    /// value − normal.
    var delta: Double?
    var verdict: PlaceVerdict
    /// Visits (heart rate, stress) or nights (HRV, recovery, sleep) behind the value.
    var count: Int
    /// Half-width of the 95 % interval of the place's mean (same unit as `value`), from the spread of its
    /// nights or visits; nil under two of them (Carte v2, « Ce qui ressort »).
    var margin: Double? = nil
}

enum PlaceMetrics {

    /// Nights needed before a difference is shown (HRV, recovery, sleep): « au moins 3 nuits ».
    static let minNights = 3
    /// Visits with heart rate needed before a difference is shown (heart rate, stress).
    static let minVisits = 3
    /// The band around the normal read as « proche ». Heart rate ±3 bpm (the Points rule), stress ±3
    /// points of time in High, HRV ±3 ms, recovery ±5 points, sleep ±20 min.
    static func closeBand(_ layer: PlaceLayer) -> Double {
        switch layer {
        case .heartRate: return 3
        case .stress: return 3
        case .hrv: return 3
        case .recovery: return 5
        }
    }
    static let sleepCloseBandMin = 20.0

    /// Higher is better for HRV, recovery and sleep; lower is better for heart rate and stress.
    static func higherIsBetter(_ layer: PlaceLayer) -> Bool {
        layer == .hrv || layer == .recovery
    }

    /// The half-width of the 95 % interval of a mean: 1.96 × the sample standard deviation / √n, nil
    /// under two values.
    static func marginOfPlaceMean(_ values: [Double]) -> Double? {
        guard values.count >= 2 else { return nil }
        let n = Double(values.count)
        let mean = values.reduce(0, +) / n
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / (n - 1)
        return 1.96 * variance.squareRoot() / n.squareRoot()
    }

    /// The verdict of a difference.
    static func placeVerdict(delta: Double, band: Double, higherIsBetter: Bool) -> PlaceVerdict {
        if abs(delta) < band { return .close }
        return (delta > 0) == higherIsBetter ? .better : .worse
    }

    // MARK: Nights

    /// The place a night belongs to: the stay going on when the sleep began (the place of the bedtime),
    /// else the last stay that began in the 12 hours before.
    static func nightPlace(_ night: PlaceNight, visits: [PlaceVisitRow]) -> String? {
        let t = night.sleepStart
        if let during = visits.last(where: { $0.arrivedAt <= t && ($0.departedAt ?? Int.max) > t }) {
            return during.placeId
        }
        return visits.last(where: { $0.arrivedAt <= t && t - $0.arrivedAt <= 12 * 3_600 })?.placeId
    }

    /// The nights of each place.
    static func nightsByPlace(_ nights: [PlaceNight], visits: [PlaceVisitRow]) -> [String: [PlaceNight]] {
        let ordered = visits.sorted { $0.arrivedAt < $1.arrivedAt }
        var out: [String: [PlaceNight]] = [:]
        for night in nights {
            guard let place = nightPlace(night, visits: ordered) else { continue }
            out[place, default: []].append(night)
        }
        return out
    }

    /// A night-based figure: the mean at the place against the mean of every night of the period.
    static func nightFigure(_ placeNights: [PlaceNight], all: [PlaceNight], value: (PlaceNight) -> Double?,
                            band: Double, higherIsBetter: Bool) -> PlaceFigure {
        let here = placeNights.compactMap(value)
        let everywhere = all.compactMap(value)
        guard !here.isEmpty else { return PlaceFigure(value: nil, normal: nil, delta: nil, verdict: .none, count: 0) }
        let mean = here.reduce(0, +) / Double(here.count)
        let normal = everywhere.isEmpty ? nil : everywhere.reduce(0, +) / Double(everywhere.count)
        guard let normal else { return PlaceFigure(value: mean, normal: nil, delta: nil, verdict: .none, count: here.count) }
        let delta = mean - normal
        let margin = marginOfPlaceMean(here)
        guard here.count >= minNights else {
            return PlaceFigure(value: mean, normal: normal, delta: delta, verdict: .tooFew, count: here.count,
                               margin: margin)
        }
        return PlaceFigure(value: mean, normal: normal, delta: delta,
                           verdict: placeVerdict(delta: delta, band: band, higherIsBetter: higherIsBetter),
                           count: here.count, margin: margin)
    }

    // MARK: Awake time

    /// The awake time of a stay: its span minus the sleeps and the workouts, as unix-second spans.
    static func awakeSpans(of visit: PlaceVisitRow, until now: Int, excluding: [(start: Int, end: Int)])
        -> [(start: Int, end: Int)] {
        var spans = [(start: visit.arrivedAt, end: min(visit.departedAt ?? now, now))]
        for cut in excluding {
            spans = spans.flatMap { span -> [(start: Int, end: Int)] in
                guard cut.end > span.start, cut.start < span.end else { return [span] }
                var pieces: [(start: Int, end: Int)] = []
                if cut.start > span.start { pieces.append((span.start, cut.start)) }
                if cut.end < span.end { pieces.append((cut.end, span.end)) }
                return pieces
            }
        }
        return spans.filter { $0.end > $0.start }
    }

    /// The index of the first bucket at or after `ts` in `buckets` (sorted by time).
    static func firstBucket(atOrAfter ts: Int, in buckets: [PlaceHRBucket]) -> Int {
        var lo = 0, hi = buckets.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if buckets[mid].ts < ts { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    /// Heart rate at a place: the mean of its awake buckets against the wearer's mean at the SAME HOURS of
    /// the day everywhere else, weighted by the place's minutes in each hour (a place visited in the
    /// evening is compared to evenings). `buckets` sorted by time.
    static func heartRateFigure(placeId: String, visits: [PlaceVisitRow], buckets: [PlaceHRBucket],
                                excluding: [(start: Int, end: Int)], now: Int,
                                hourOf: (Int) -> Int) -> PlaceFigure {
        var hereByHour = [Int: (sum: Double, n: Int)]()
        var elseByHour = [Int: (sum: Double, n: Int)]()
        var visitsWithHR = 0
        var visitMeans: [Double] = []
        for visit in visits {
            let isHere = visit.placeId == placeId
            var any = false
            var visitSum = 0.0
            var visitN = 0
            for span in awakeSpans(of: visit, until: now, excluding: excluding) {
                var k = firstBucket(atOrAfter: span.start, in: buckets)
                while k < buckets.count, buckets[k].ts < span.end {
                    let hour = hourOf(buckets[k].ts)
                    if isHere {
                        hereByHour[hour, default: (0, 0)].sum += buckets[k].bpm
                        hereByHour[hour, default: (0, 0)].n += 1
                        visitSum += buckets[k].bpm
                        visitN += 1
                    } else {
                        elseByHour[hour, default: (0, 0)].sum += buckets[k].bpm
                        elseByHour[hour, default: (0, 0)].n += 1
                    }
                    any = true
                    k += 1
                }
            }
            if isHere && any {
                visitsWithHR += 1
                visitMeans.append(visitSum / Double(visitN))
            }
        }
        let hereN = hereByHour.values.reduce(0) { $0 + $1.n }
        guard hereN > 0 else { return PlaceFigure(value: nil, normal: nil, delta: nil, verdict: .none, count: 0) }
        let value = hereByHour.values.reduce(0) { $0 + $1.sum } / Double(hereN)
        var weighted = 0.0
        var weight = 0
        for (hour, h) in hereByHour {
            guard let e = elseByHour[hour], e.n > 0 else { continue }
            weighted += Double(h.n) * (e.sum / Double(e.n))
            weight += h.n
        }
        let margin = marginOfPlaceMean(visitMeans)
        guard weight > 0 else {
            return PlaceFigure(value: value, normal: nil, delta: nil, verdict: .none, count: visitsWithHR,
                               margin: margin)
        }
        let normal = weighted / Double(weight)
        let delta = value - normal
        let verdictNow: PlaceVerdict = visitsWithHR < minVisits
            ? .tooFew : placeVerdict(delta: delta, band: closeBand(.heartRate), higherIsBetter: false)
        return PlaceFigure(value: value, normal: normal, delta: delta, verdict: verdictNow, count: visitsWithHR,
                           margin: margin)
    }

    /// Stress at a place: the share of its scored awake time in the High band (level ≥ 2), in percent,
    /// against the same share over every scored window of the period. Moving windows are left out.
    static func stressFigure(placeId: String, visits: [PlaceVisitRow], windows: [PlaceStressWindow],
                             excluding: [(start: Int, end: Int)], now: Int) -> PlaceFigure {
        let here = visits.filter { $0.placeId == placeId }
        let spans = here.flatMap { awakeSpans(of: $0, until: now, excluding: excluding) }
        var hereHigh = 0, hereAll = 0, allHigh = 0, allAll = 0
        var visitsWithStress = Set<String>()
        var perVisit: [String: (high: Int, all: Int)] = [:]
        for window in windows {
            guard let level = window.level else { continue }
            let mid = (window.start + window.end) / 2
            let high = level >= 2
            allAll += 1
            if high { allHigh += 1 }
            if spans.contains(where: { mid >= $0.start && mid < $0.end }) {
                hereAll += 1
                if high { hereHigh += 1 }
                if let v = here.first(where: { mid >= $0.arrivedAt && mid < ($0.departedAt ?? now) }) {
                    visitsWithStress.insert(v.id)
                    perVisit[v.id, default: (0, 0)].all += 1
                    if high { perVisit[v.id, default: (0, 0)].high += 1 }
                }
            }
        }
        guard hereAll > 0 else { return PlaceFigure(value: nil, normal: nil, delta: nil, verdict: .none, count: 0) }
        let value = 100 * Double(hereHigh) / Double(hereAll)
        let normal = allAll > 0 ? 100 * Double(allHigh) / Double(allAll) : nil
        let margin = marginOfPlaceMean(perVisit.values.filter { $0.all > 0 }
                                        .map { 100 * Double($0.high) / Double($0.all) })
        guard let normal else {
            return PlaceFigure(value: value, normal: nil, delta: nil, verdict: .none, count: visitsWithStress.count,
                               margin: margin)
        }
        let delta = value - normal
        let verdictNow: PlaceVerdict = visitsWithStress.count < minVisits
            ? .tooFew : placeVerdict(delta: delta, band: closeBand(.stress), higherIsBetter: false)
        return PlaceFigure(value: value, normal: normal, delta: delta, verdict: verdictNow,
                           count: visitsWithStress.count, margin: margin)
    }

    // MARK: Points

    /// The wearer's habitual heart rate at each hour of the day (mean of the buckets of that hour).
    static func habitualHeartRateByHour(_ buckets: [PlaceHRBucket], hourOf: (Int) -> Int) -> [Int: Double] {
        var acc = [Int: (sum: Double, n: Int)]()
        for b in buckets {
            let h = hourOf(b.ts)
            acc[h, default: (0, 0)].sum += b.bpm
            acc[h, default: (0, 0)].n += 1
        }
        return acc.mapValues { $0.sum / Double($0.n) }
    }

    /// The heart rate at a point: the five-minute bucket nearest its time, within 5 minutes of the
    /// bucket's middle. `buckets` sorted by time.
    static func heartRateAt(_ ts: Int, buckets: [PlaceHRBucket]) -> Double? {
        var best: (bpm: Double, gap: Int)?
        var k = firstBucket(atOrAfter: ts - 450, in: buckets)
        while k < buckets.count, buckets[k].ts <= ts + 150 {
            let gap = abs(buckets[k].ts + 150 - ts)
            if gap <= 300, best.map({ gap < $0.gap }) ?? true { best = (buckets[k].bpm, gap) }
            k += 1
        }
        return best?.bpm
    }

    /// A point's heart-rate verdict: ±3 bpm of the habitual value at that hour is normal.
    static func pointVerdict(bpm: Double?, habitual: Double?) -> PlaceVerdict {
        guard let bpm else { return .none }
        guard let habitual else { return .tooFew }
        return placeVerdict(delta: bpm - habitual, band: closeBand(.heartRate), higherIsBetter: false)
    }
}
