import Foundation
import StrandAnalytics
import WhoopProtocol

// MARK: - Phone steps during an outdoor workout, and the route's colours (personal fork, chantier 14)
//
// A WHOOP 4.0 sends no step count over Bluetooth, so the steps of a walk, a run or a hike come from the
// iPhone's pedometer (`WorkoutStepRecorder`), read every five seconds while the workout runs. Everything
// below is pure, so the rules are pinned by tests: the cadence of the moment and the per-minute curve
// come from ONE function each, the steps of each kilometre from the same crossings as the splits, and the
// colour of each stretch of the route from the heart rate (or the cadence) at the time it was walked.

/// One reading of the phone's pedometer during a workout.
struct WorkoutStepSample: Equatable, Codable {
    /// Unix milliseconds.
    var tMs: Int64
    /// Steps since the start of the workout, paused spans left out.
    var steps: Int
}

enum WorkoutStepMath {
    /// The recorder keeps one reading every this many seconds.
    static let sampleSeconds = 5
    /// Two readings further apart than this are not one stretch (a pause, the app killed): no cadence is
    /// read across them.
    static let maxGapSeconds = 15
    /// The cadence of the moment is measured over this many seconds.
    static let cadenceWindowSeconds = 30

    /// The sports whose steps are recorded: the outdoor on-foot sports of the catalogue.
    static let stepSports: Set<String> = ["Running", "Walking", "Hiking"]

    static func recordsSteps(sport: String) -> Bool {
        let name = sport.trimmingCharacters(in: .whitespaces)
        return stepSports.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Steps per minute over the last `window` seconds of one unbroken stretch, nil until the stretch is at
    /// least half the window long (no absurd cadence from two readings).
    static func stepCadenceNow(_ samples: [WorkoutStepSample], window: Int = cadenceWindowSeconds) -> Int? {
        guard let last = samples.last else { return nil }
        var start = last
        var index = samples.count - 1
        while index > 0 {
            let previous = samples[index - 1]
            if samples[index].tMs - previous.tMs > Int64(maxGapSeconds) * 1000 { break }
            start = previous
            if last.tMs - previous.tMs >= Int64(window) * 1000 { break }
            index -= 1
        }
        let seconds = Double(last.tMs - start.tMs) / 1000
        guard seconds >= Double(window) / 2 else { return nil }
        let steps = max(0, last.steps - start.steps)
        return Int((Double(steps) / seconds * 60).rounded())
    }

    /// Steps per minute for each minute of the workout since `startMs` (index 0 = the first minute), nil
    /// for a minute with less than twenty seconds of readings (paused, or no phone).
    static func stepCadenceByMinute(_ samples: [WorkoutStepSample], startMs: Int64) -> [Int?] {
        guard let last = samples.last, last.tMs > startMs else { return [] }
        let count = Int((last.tMs - startMs - 1) / 60_000) + 1
        var steps = Array(repeating: 0, count: count)
        var seconds = Array(repeating: 0.0, count: count)
        for (a, b) in zip(samples, samples.dropFirst()) {
            let gap = b.tMs - a.tMs
            guard gap > 0, gap <= Int64(maxGapSeconds) * 1000, b.tMs > startMs else { continue }
            let minute = min(count - 1, Int((b.tMs - startMs - 1) / 60_000))
            steps[minute] += max(0, b.steps - a.steps)
            seconds[minute] += Double(gap) / 1000
        }
        return (0..<count).map { seconds[$0] >= 20 ? Int((Double(steps[$0]) / seconds[$0] * 60).rounded()) : nil }
    }

    /// The step count at `tMs`, interpolated between the readings either side of it (clamped to the first
    /// and last reading).
    static func stepsAtTime(_ samples: [WorkoutStepSample], tMs: Int64) -> Double {
        guard let first = samples.first, let last = samples.last else { return 0 }
        if tMs <= first.tMs { return Double(first.steps) }
        if tMs >= last.tMs { return Double(last.steps) }
        var low = 0
        var high = samples.count - 1
        while high - low > 1 {
            let mid = (low + high) / 2
            if samples[mid].tMs <= tMs { low = mid } else { high = mid }
        }
        let a = samples[low], b = samples[high]
        guard b.tMs > a.tMs else { return Double(b.steps) }
        let fraction = Double(tMs - a.tMs) / Double(b.tMs - a.tMs)
        return Double(a.steps) + Double(b.steps - a.steps) * fraction
    }

    /// The steps of each whole `unitMeters` covered (a kilometre, or a mile): the same crossings as
    /// `LiveWorkoutMath.splits`, the steps read at each crossing instant.
    static func stepsPerSplit(_ samples: [WorkoutStepSample], route: [LiveWorkoutMath.RoutePoint],
                              unitMeters: Double = 1000) -> [Int] {
        guard let first = route.first, !samples.isEmpty, unitMeters > 0 else { return [] }
        var out: [Int] = []
        var lastSteps = stepsAtTime(samples, tMs: first.tMs)
        var next = unitMeters
        for (a, b) in zip(route, route.dropFirst()) where b.meters > a.meters {
            while b.meters >= next {
                let fraction = (next - a.meters) / (b.meters - a.meters)
                let crossing = a.tMs + Int64((Double(b.tMs - a.tMs) * fraction).rounded())
                let atCrossing = stepsAtTime(samples, tMs: crossing)
                out.append(max(0, Int((atCrossing - lastSteps).rounded())))
                lastSteps = atCrossing
                next += unitMeters
            }
        }
        return out
    }

    /// The cadence around `tMs`: steps per minute between the readings within `halfWindow` seconds either
    /// side, nil when they span less than ten seconds or are broken by a gap.
    static func stepCadenceAround(_ samples: [WorkoutStepSample], tMs: Int64, halfWindow: Int = 15) -> Int? {
        let from = tMs - Int64(halfWindow) * 1000
        let to = tMs + Int64(halfWindow) * 1000
        var a: WorkoutStepSample?
        var b: WorkoutStepSample?
        var previous: WorkoutStepSample?
        for sample in samples where sample.tMs >= from && sample.tMs <= to {
            if let previous, sample.tMs - previous.tMs > Int64(maxGapSeconds) * 1000 { return nil }
            if a == nil { a = sample }
            b = sample
            previous = sample
        }
        guard let a, let b, b.tMs - a.tMs >= 10_000 else { return nil }
        let seconds = Double(b.tMs - a.tMs) / 1000
        return Int((Double(max(0, b.steps - a.steps)) / seconds * 60).rounded())
    }
}

// MARK: - The route's colours

/// One stretch of a route drawn in one colour: its points and its band (a heart-rate zone 1…5, or a
/// cadence band 1…5; 0 = no value, drawn grey).
struct RouteBandSegment: Equatable {
    var points: [RouteMath.LatLng]
    var band: Int
}

enum RouteColoring {
    /// A route point with no heart-rate sample this close in time gets no zone.
    static let maxHrGapSeconds = 30

    /// The cadence bands' lower edges, steps per minute: band 1 below the first, band 5 from the last
    /// (a slow walk, a brisk walk, a fast walk, a jog, a run).
    static let cadenceBandFloors: [Int] = [90, 110, 130, 160]

    static func cadenceBand(_ stepsPerMinute: Int) -> Int {
        1 + cadenceBandFloors.filter { stepsPerMinute >= $0 }.count
    }

    /// For each point, the zone of the nearest heart-rate sample (within `maxHrGapSeconds`), 0 without one.
    /// `hr` sorted by time.
    static func zoneBandsForRoute(_ points: [WorkoutRoutePoint], hr: [HRSample], zoneSet: HRZoneSet) -> [Int] {
        guard !hr.isEmpty else { return points.map { _ in 0 } }
        return points.map { point in
            let ts = Int(point.tMs / 1000)
            var low = 0
            var high = hr.count - 1
            while high - low > 1 {
                let mid = (low + high) / 2
                if hr[mid].ts <= ts { low = mid } else { high = mid }
            }
            let nearest = abs(hr[low].ts - ts) <= abs(hr[high].ts - ts) ? hr[low] : hr[high]
            guard abs(nearest.ts - ts) <= maxHrGapSeconds else { return 0 }
            return zoneSet.zoneNumber(forBPM: Double(nearest.bpm))
        }
    }

    /// For each point, the cadence band around its time, 0 without a cadence.
    static func cadenceBandsForRoute(_ points: [WorkoutRoutePoint], steps: [WorkoutStepSample]) -> [Int] {
        points.map { point in
            WorkoutStepMath.stepCadenceAround(steps, tMs: point.tMs).map(cadenceBand) ?? 0
        }
    }

    /// The route cut into runs of one band. Two neighbouring segments share their boundary point, so the
    /// line has no hole where the colour changes.
    static func routeBandSegments(_ points: [WorkoutRoutePoint], bands: [Int]) -> [RouteBandSegment] {
        guard points.count >= 2, bands.count == points.count else { return [] }
        var out: [RouteBandSegment] = []
        var current = RouteBandSegment(points: [RouteMath.LatLng(points[0].lat, points[0].lon)], band: bands[0])
        for index in 1..<points.count {
            let point = RouteMath.LatLng(points[index].lat, points[index].lon)
            current.points.append(point)
            if index < points.count - 1, bands[index] != current.band {
                out.append(current)
                current = RouteBandSegment(points: [point], band: bands[index])
            }
        }
        out.append(current)
        return out.filter { $0.points.count >= 2 }
    }

    /// The whole route in one band, for a route saved without its point times.
    static func plainSegments(_ points: [RouteMath.LatLng]) -> [RouteBandSegment] {
        points.count >= 2 ? [RouteBandSegment(points: points, band: 0)] : []
    }
}

// MARK: - Storage (on the iPhone only)

/// A finished workout's step readings, one `UserDefaults` key per workout under the route's natural key
/// (`RouteStore.key`), like `RoutePointStore`. Never leaves the device.
enum WorkoutStepStore {
    static func defaultsKey(for mapKey: String) -> String { "noop.workoutSteps." + mapKey }

    static func encode(_ samples: [WorkoutStepSample]) -> Data? { try? JSONEncoder().encode(samples) }

    static func decode(_ data: Data?) -> [WorkoutStepSample]? {
        guard let data, !data.isEmpty,
              let samples = try? JSONDecoder().decode([WorkoutStepSample].self, from: data),
              !samples.isEmpty else { return nil }
        return samples
    }

    static func load(startTs: Int, sport: String, from defaults: UserDefaults = .standard) -> [WorkoutStepSample]? {
        decode(defaults.data(forKey: defaultsKey(for: RouteStore.key(startTs: startTs, sport: sport))))
    }

    static func store(_ samples: [WorkoutStepSample], startTs: Int, sport: String,
                      into defaults: UserDefaults = .standard) {
        let key = defaultsKey(for: RouteStore.key(startTs: startTs, sport: sport))
        guard !samples.isEmpty, let data = encode(samples) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }
}

/// The readings of the workout in progress, written every minute so an OS kill does not lose them (the
/// same reason as `ActiveRouteStore`).
enum ActiveStepStore {
    static let defaultsKey = "noop.activeWorkoutSteps"
    /// Readings between two writes: one minute at one reading every five seconds.
    static let samplesPerWrite = 12

    static func store(_ samples: [WorkoutStepSample], into defaults: UserDefaults = .standard) {
        guard !samples.isEmpty, let data = WorkoutStepStore.encode(samples) else { return }
        defaults.set(data, forKey: defaultsKey)
    }

    static func load(from defaults: UserDefaults = .standard) -> [WorkoutStepSample]? {
        WorkoutStepStore.decode(defaults.data(forKey: defaultsKey))
    }

    static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
    }
}
