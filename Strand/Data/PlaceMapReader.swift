import Foundation
import WhoopStore

// Personal fork, chantier 14 step 2: what the Map's Lieux and Points views, a place's screen and the
// Coach read. The rules are `PlaceMetrics` (pure); this file only fetches the inputs and assembles them,
// so the three readers can never compute one fact two ways.

/// One place as the Lieux view lists it.
struct PlaceSummary: Identifiable, Equatable {
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
struct PlaceNightBar: Equatable {
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

    /// The hourly stress windows of the last `days` days (today up to now).
    @MainActor
    static func stressWindows(repo: Repository, days: Int, now: Date) async -> [PlaceStressWindow] {
        var out: [PlaceStressWindow] = []
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        for back in stride(from: days - 1, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -back, to: today),
                  let scored = await StressDayCurve.day(repo: repo, dayStart: day, now: now,
                                                        personalBaseline: PuffinExperiment.stressPersonalBaselineEnabled)
            else { continue }
            for hour in scored.result.hours {
                out.append(PlaceStressWindow(start: hour.startTs, end: hour.startTs + 3_600,
                                             level: hour.maskedForActivity ? nil : hour.level,
                                             moving: hour.maskedForActivity))
            }
        }
        return out
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
        let buckets = await repo.hrBuckets(from: Int(from.timeIntervalSince1970), to: nowTs, bucketSeconds: 300)
            .map { PlaceHRBucket(ts: $0.ts, bpm: $0.bpm) }
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

    /// The Points view: the points of the last `days` days with their heart rate and stress.
    @MainActor
    static func loadPointMarks(repo: Repository, days: Int, now: Date = Date()) async -> [PlacePointMark] {
        guard let store = await repo.storeHandle() else { return [] }
        let from = now.addingTimeInterval(-Double(days) * 86_400)
        let points = await PlaceLog.points(store, from: from, to: now)
        guard !points.isEmpty else { return [] }
        let places = await PlaceLog.places(store)
        // The habitual heart rate per hour comes from the last 30 days whatever the view's period.
        let habitFrom = now.addingTimeInterval(-30 * 86_400)
        let buckets = await repo.hrBuckets(from: Int(min(habitFrom, from).timeIntervalSince1970),
                                           to: Int(now.timeIntervalSince1970), bucketSeconds: 300)
            .map { PlaceHRBucket(ts: $0.ts, bpm: $0.bpm) }
        let calendar = Calendar.current
        let hourOf: (Int) -> Int = { calendar.component(.hour, from: Date(timeIntervalSince1970: TimeInterval($0))) }
        let habitual = PlaceMetrics.habitualHeartRateByHour(
            buckets.filter { $0.ts >= Int(habitFrom.timeIntervalSince1970) }, hourOf: hourOf)
        let windows = await stressWindows(repo: repo, days: min(days, stressDays), now: now)
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
}
