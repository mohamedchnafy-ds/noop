import Foundation
import WhoopStore

// Personal fork, chantier 14 step 2: what the Map's Lieux and Points views, a place's screen and the
// Coach read. The rules are `PlaceMetrics` (pure); this file only fetches the inputs and assembles them,
// so the three readers can never compute one fact two ways.

/// One place as the Lieux view lists it.
struct PlaceSummary: Identifiable, Codable, Equatable {
    var place: PlaceRow
    var name: String
    /// Stays in the period.
    var visits: Int
    /// Nights begun there in the period.
    var nights: Int
    /// Unix seconds of the last arrival.
    var lastArrival: Int?
    var heartRate: PlaceFigure
    var stress: PlaceFigure
    var hrv: PlaceFigure
    var recovery: PlaceFigure
    var sleep: PlaceFigure
    /// HRV of each night there, oldest first (the « Nuits ici » bars).
    var nightBars: [PlaceNightBar]

    var id: String { place.id }

    func figure(_ layer: PlaceLayer) -> PlaceFigure {
        switch layer {
        case .heartRate: return heartRate
        case .stress: return stress
        case .hrv: return hrv
        case .recovery: return recovery
        }
    }
}

/// One night of a place: its day and its HRV.
struct PlaceNightBar: Codable, Equatable {
    var day: String
    var hrv: Double?
}

/// One point as the Points view draws it.
struct PlacePointMark: Identifiable, Equatable {
    var ts: Int64
    var lat: Double
    var lon: Double
    /// Heart rate at that time, nil when the strap had none (drawn hollow).
    var bpm: Double?
    /// The habitual heart rate at that hour.
    var habitual: Double?
    var hrVerdict: PlaceVerdict
    /// Stress of that hour (0–3), nil when unscored.
    var stressLevel: Double?
    /// True when the hour was left unscored because the wearer was moving.
    var moving: Bool
    /// The place the point falls in, if any.
    var placeName: String?
    var steps: Int?

    var id: Int64 { ts }
}

/// One day of the Map's frise (Carte v2).
struct PlaceDayTimeline: Equatable {
    /// Unix seconds: local midnight and the next one.
    var dayStart: Int
    var dayEnd: Int
    var heartRate: [PlaceHRBucket]
    /// Empty until stress is asked for.
    var stress: [PlaceStressWindow]
}

enum PlaceMapReader {

    /// The period the Lieux view and a place's screen read (« 90 derniers jours »).
    static let placeDays = 90
    /// Stress is scored day by day (each day is a pass over its heart rate), so the place layer and the
    /// points read the last 14 days of it.
    static let stressDays = 14

    /// The local day of a time, "yyyy-MM-dd" (the journal's key format).
    private static func dayKey(_ ts: Int) -> String {
        MealJournal.mealDayKey(Date(timeIntervalSince1970: TimeInterval(ts)))
    }

    /// Every night of the period: the longest sleep block ending on each day, with that day's scores.
    @MainActor
    static func nightsForPlaces(repo: Repository, blocks: [CachedSleepSession]) async -> [PlaceNight] {
        var longest: [String: CachedSleepSession] = [:]
        for block in blocks where block.endTs - block.effectiveStartTs >= 3 * 3_600 {
            let key = dayKey(block.endTs)
            if let kept = longest[key], kept.endTs - kept.effectiveStartTs >= block.endTs - block.effectiveStartTs {
                continue
            }
            longest[key] = block
        }
        guard let first = longest.keys.min(), let last = longest.keys.max() else { return [] }
        let metrics = await repo.dailyMetrics(fromDay: first, toDay: last)
        let byDay = Dictionary(metrics.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        return longest.keys.sorted().compactMap { key in
            guard let block = longest[key] else { return nil }
            let metric = byDay[key]
            return PlaceNight(day: key, sleepStart: block.effectiveStartTs,
                              durationMin: metric?.totalSleepMin ?? Double(block.endTs - block.effectiveStartTs) / 60,
                              hrvMs: metric?.avgHrv ?? block.avgHrv, recoveryPct: metric?.recovery)
        }
    }

    /// The hourly stress windows of the last `days` days (today up to now). A day over for more than
    /// `PlaceMapFreeze.frozenAfterSeconds` is read from the day store once it has been scored, so only
    /// today and yesterday are scored again at each opening.
    @MainActor
    static func stressWindows(repo: Repository, days: Int, now: Date) async -> [PlaceStressWindow] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        var store = loadPlaceDayStore()
        var changed = false
        var out: [PlaceStressWindow] = []
        for back in stride(from: days - 1, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -back, to: today) else { continue }
            out += await stressOfPlaceDay(repo: repo, dayStart: day, now: now, store: &store, changed: &changed)
        }
        if changed { saveTrimmedDayStore(store, now: now) }
        return out
    }

    /// The day store, emptied of the stress scored with another baseline setting.
    @MainActor
    private static func loadPlaceDayStore() -> PlaceMapDayStore {
        var store = PlaceMapCacheFiles.loadDayStore()
        let baseline = PuffinExperiment.stressPersonalBaselineEnabled
        if store.personalBaseline != baseline {
            store.stress = [:]
            store.personalBaseline = baseline
        }
        return store
    }

    /// The stress windows of the local day starting at `dayStart`: from the store when the day is frozen
    /// and already scored, else scored now (and kept when frozen).
    @MainActor
    private static func stressOfPlaceDay(repo: Repository, dayStart: Date, now: Date,
                                         store: inout PlaceMapDayStore, changed: inout Bool) async -> [PlaceStressWindow] {
        let calendar = Calendar.current
        let key = dayKey(Int(dayStart.timeIntervalSince1970))
        let end = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
        let frozen = PlaceMapFreeze.isFrozenDay(dayEnd: end, now: now)
        if frozen, let kept = store.stress[key] { return kept }
        var windows: [PlaceStressWindow] = []
        if let scored = await StressDayCurve.day(repo: repo, dayStart: dayStart, now: now,
                                                 personalBaseline: store.personalBaseline) {
            for hour in scored.result.hours {
                windows.append(PlaceStressWindow(start: hour.startTs, end: hour.startTs + 3_600,
                                                 level: hour.maskedForActivity ? nil : hour.level,
                                                 moving: hour.maskedForActivity))
            }
        }
        if frozen {
            store.stress[key] = windows
            changed = true
        }
        return windows
    }

    /// The five-minute heart-rate buckets from `from` to `to` (default and at most `now`), oldest first,
    /// read day by day: a day over for long enough comes from the day store, the others from the strap's
    /// samples.
    @MainActor
    static func placeHeartRateBuckets(repo: Repository, from: Date, to: Date? = nil, now: Date) async -> [PlaceHRBucket] {
        let calendar = Calendar.current
        var store = loadPlaceDayStore()
        var changed = false
        var out: [PlaceHRBucket] = []
        let upper = min(to ?? now, now)
        var day = calendar.startOfDay(for: from)
        let fromTs = Int(from.timeIntervalSince1970)
        let upperTs = Int(upper.timeIntervalSince1970)
        let nowTs = Int(now.timeIntervalSince1970)
        while day < upper {
            let end = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
            let startTs = Int(day.timeIntervalSince1970)
            let endTs = Int(end.timeIntervalSince1970)
            let key = dayKey(startTs)
            let frozen = PlaceMapFreeze.isFrozenDay(dayEnd: end, now: now)
            let dayBuckets: [PlaceHRBucket]
            if frozen, let kept = store.heartRate[key] {
                dayBuckets = kept
            } else {
                dayBuckets = await repo.hrBuckets(from: startTs, to: min(endTs, nowTs), bucketSeconds: 300)
                    .filter { $0.ts >= startTs && $0.ts < endTs }
                    .map { PlaceHRBucket(ts: $0.ts, bpm: $0.bpm) }
                    .sorted { $0.ts < $1.ts }
                if frozen {
                    store.heartRate[key] = dayBuckets
                    changed = true
                }
            }
            out += dayBuckets.filter { $0.ts >= fromTs && $0.ts <= upperTs }
            day = end
        }
        if changed { saveTrimmedDayStore(store, now: now) }
        return out
    }

    /// Write the day store without the days past `PlaceMapFreeze.keepDays`.
    @MainActor
    private static func saveTrimmedDayStore(_ store: PlaceMapDayStore, now: Date) {
        let oldest = dayKey(Int(now.timeIntervalSince1970) - PlaceMapFreeze.keepDays * 86_400)
        PlaceMapCacheFiles.saveDayStore(PlaceMapFreeze.prunedDayStore(store, oldestKey: oldest,
                                                                      personalBaseline: store.personalBaseline))
    }

    /// The Lieux view: every place with its figures over the last `placeDays` days, those with a stay in
    /// the period only. `includeStress` false skips the day-by-day stress scoring (the Coach's block
    /// leaves stress out).
    @MainActor
    static func loadPlaceSummaries(repo: Repository, includeStress: Bool = true,
                                   now: Date = Date()) async -> [PlaceSummary] {
        guard let store = await repo.storeHandle() else { return [] }
        let from = now.addingTimeInterval(-Double(placeDays) * 86_400)
        let places = await PlaceLog.places(store)
        guard !places.isEmpty else { return [] }
        let visits = await PlaceLog.visits(store, from: from, to: now)
        guard !visits.isEmpty else { return [] }
        let nowTs = Int(now.timeIntervalSince1970)
        let blocks = await repo.allSleepSessions(days: placeDays + 1)
        let nights = await nightsForPlaces(repo: repo, blocks: blocks)
        let nightsAt = PlaceMetrics.nightsByPlace(nights, visits: visits)
        // Workouts and sleeps are left out of a place's awake time.
        let workouts = await repo.workoutRows(days: placeDays + 1)
        var excluded: [(start: Int, end: Int)] = workouts.map { (start: $0.startTs, end: $0.endTs) }
        excluded += blocks.map { (start: $0.effectiveStartTs, end: $0.endTs) }
        let buckets = await placeHeartRateBuckets(repo: repo, from: from, now: now)
        var windows: [PlaceStressWindow] = []
        if includeStress { windows = await stressWindows(repo: repo, days: stressDays, now: now) }
        let calendar = Calendar.current
        let hourOf: (Int) -> Int = { calendar.component(.hour, from: Date(timeIntervalSince1970: TimeInterval($0))) }

        var out: [PlaceSummary] = []
        for place in places {
            let stays = visits.filter { $0.placeId == place.id }
            guard !stays.isEmpty else { continue }
            let here = nightsAt[place.id] ?? []
            let hrv = PlaceMetrics.nightFigure(here, all: nights, value: { $0.hrvMs },
                                               band: PlaceMetrics.closeBand(.hrv), higherIsBetter: true)
            let recovery = PlaceMetrics.nightFigure(here, all: nights, value: { $0.recoveryPct },
                                                    band: PlaceMetrics.closeBand(.recovery), higherIsBetter: true)
            let sleep = PlaceMetrics.nightFigure(here, all: nights, value: { $0.durationMin },
                                                 band: PlaceMetrics.sleepCloseBandMin, higherIsBetter: true)
            let heartRate = PlaceMetrics.heartRateFigure(placeId: place.id, visits: visits, buckets: buckets,
                                                         excluding: excluded, now: nowTs, hourOf: hourOf)
            let stress = PlaceMetrics.stressFigure(placeId: place.id, visits: visits, windows: windows,
                                                   excluding: excluded, now: nowTs)
            out.append(PlaceSummary(place: place, name: PlaceNaming.placeName(place, in: places),
                                    visits: stays.count, nights: here.count,
                                    lastArrival: stays.map(\.arrivedAt).max(),
                                    heartRate: heartRate, stress: stress, hrv: hrv, recovery: recovery,
                                    sleep: sleep, nightBars: here.map { PlaceNightBar(day: $0.day, hrv: $0.hrvMs) }))
        }
        return out
    }

    /// The points of the last `days` days with their heart rate, and their stress when asked for
    /// (`includeStress`; stress covers `stressDays` at most).
    @MainActor
    static func loadPointMarks(repo: Repository, days: Int, includeStress: Bool, now: Date = Date()) async -> [PlacePointMark] {
        await loadPointMarks(repo: repo, from: now.addingTimeInterval(-Double(days) * 86_400), to: now,
                             includeStress: includeStress, now: now)
    }

    /// The points from `from` to `to` with their heart rate (against the habitual heart rate of the same
    /// hour over the last 30 days) and, when asked for, the stress of their hour.
    @MainActor
    static func loadPointMarks(repo: Repository, from: Date, to: Date, includeStress: Bool,
                               now: Date = Date()) async -> [PlacePointMark] {
        guard let store = await repo.storeHandle() else { return [] }
        let upper = min(to, now)
        let points = await PlaceLog.points(store, from: from, to: upper)
        guard !points.isEmpty else { return [] }
        let places = await PlaceLog.places(store)
        // The habitual heart rate per hour comes from the last 30 days whatever the view's period.
        let habitFrom = now.addingTimeInterval(-30 * 86_400)
        let buckets = await placeHeartRateBuckets(repo: repo, from: min(habitFrom, from), now: now)
        let calendar = Calendar.current
        let hourOf: (Int) -> Int = { calendar.component(.hour, from: Date(timeIntervalSince1970: TimeInterval($0))) }
        let habitual = PlaceMetrics.habitualHeartRateByHour(
            buckets.filter { $0.ts >= Int(habitFrom.timeIntervalSince1970) }, hourOf: hourOf)
        var windows: [PlaceStressWindow] = []
        if includeStress {
            let spanDays = Int((now.timeIntervalSince(calendar.startOfDay(for: from)) / 86_400).rounded(.up))
            windows = await stressWindows(repo: repo, days: min(max(spanDays, 1), stressDays), now: now)
        }
        return points.map { point in
            let ts = Int(point.ts / 1000)
            let bpm = PlaceMetrics.heartRateAt(ts, buckets: buckets)
            let usual = habitual[hourOf(ts)]
            let window = windows.first { ts >= $0.start && ts < $0.end }
            let place = PlaceVisitPlan.matchingPlace(lat: point.lat, lon: point.lon, in: places)
            return PlacePointMark(ts: point.ts, lat: point.lat, lon: point.lon, bpm: bpm, habitual: usual,
                                  hrVerdict: PlaceMetrics.pointVerdict(bpm: bpm, habitual: usual),
                                  stressLevel: window?.level, moving: window?.moving ?? false,
                                  placeName: place.map { PlaceNaming.placeName($0, in: places) },
                                  steps: point.steps)
        }
    }

    /// One day of the Map's frise: its heart rate and, when asked for, its hourly stress.
    @MainActor
    static func loadDayTimeline(repo: Repository, dayStart: Date, includeStress: Bool,
                                now: Date = Date()) async -> PlaceDayTimeline {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: dayStart)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        let heartRate = await placeHeartRateBuckets(repo: repo, from: start, to: end, now: now)
        var stress: [PlaceStressWindow] = []
        if includeStress {
            var store = loadPlaceDayStore()
            var changed = false
            stress = await stressOfPlaceDay(repo: repo, dayStart: start, now: now, store: &store, changed: &changed)
            if changed { saveTrimmedDayStore(store, now: now) }
        }
        return PlaceDayTimeline(dayStart: Int(start.timeIntervalSince1970), dayEnd: Int(end.timeIntervalSince1970),
                                heartRate: heartRate, stress: stress)
    }
}
