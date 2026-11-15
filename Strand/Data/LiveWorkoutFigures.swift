import Foundation
import StrandAnalytics
import WhoopProtocol

// MARK: - The in-progress workout screen's figures (personal fork, chantier 8)
//
// The live workout screen (`LiveWorkoutView`, design A of the fork's canvas) shows one figure per fact:
// the time once, the heart rate with its zone, Effort in one format, calories, the pace of the moment,
// the distance with the time of each kilometre, the time spent in each zone and the last ten minutes of
// heart rate. Everything below is pure — samples, route points and pauses go in, values come out — so
// the rules are pinned by tests and the view only lays them out.

/// One reading of the screen, built every second from the workout in progress.
struct LiveWorkoutFigures: Equatable {
    /// Cardio (a distance sport, or a GPS route being recorded): distance, pace and splits are shown.
    /// Strength (any other sport): average · max heart rate instead, and the curve before the zones.
    enum Layout: Equatable { case cardio, strength }

    var layout: Layout
    /// The sport as shown (`WorkoutSource.displaySport`).
    var sportName: String
    var isPaused: Bool
    var elapsedSeconds: Int
    var bpm: Int?
    /// 1…5, or 0 below Zone 1 (`HRZoneSet.zoneNumber`).
    var zone: Int
    /// Effort on the wearer's scale, in the one format every Effort read-out uses
    /// (`UnitFormatter.effortDisplay`).
    var effort: String
    /// Effort's intensity word (`StrainGauge.stateLabel`).
    var effortState: String
    /// The same estimate the saved workout will carry (`Calories.estimateBoutCalories`, measured resting
    /// heart rate), nil before two samples.
    var kcal: Int?
    var averageHr: Int?
    var peakHr: Int?
    /// Metres, nil without a GPS route.
    var distanceM: Double?
    /// Seconds per kilometre over the last stretch (`LiveWorkoutMath.currentPace`), nil at the start.
    var currentPaceSecPerKm: Double?
    /// Seconds of each whole kilometre (or mile) covered, pauses left out.
    var splits: [Int]
    /// Seconds in Zone 1…5.
    var zoneSeconds: [Int]
    /// The last ten minutes of heart rate, one average per 10-second bucket (nil = no sample).
    var curve: [Double?]
    /// The phone's steps since the start (chantier 14), nil when the workout records no steps.
    var steps: Int? = nil
    /// Steps per minute of the moment (`WorkoutStepMath.stepCadenceNow`), nil at the start.
    var cadence: Int? = nil
    /// Fork chantier 18: the last two workouts of the same sport over the same ten minutes of their own
    /// elapsed time (`LiftHeartRateMath.alignedCurve`), in the curve's buckets; empty when there are none.
    var comparisonCurves: [[Double?]] = []
}

enum LiveWorkoutMath {
    /// The curve's span and bucket, in seconds.
    static let curveWindow = 600
    static let curveBucket = 10

    /// Seconds in Zone 1…5, by the same rule as the Workouts detail (`HRZones.timeInZone`).
    static func zoneSeconds(_ samples: [HRSample], zoneSet: HRZoneSet) -> [Int] {
        let time = HRZones.timeInZone(samples, zoneSet: zoneSet)
        return (1...5).map { Int(time.seconds(inZone: $0).rounded()) }
    }

    /// The last `curveWindow` seconds before `now`, averaged per `curveBucket`, oldest first.
    static func recentCurve(_ samples: [HRSample], now: Int) -> [Double?] {
        let count = curveWindow / curveBucket
        let from = now - curveWindow
        var sums = Array(repeating: 0, count: count)
        var counts = Array(repeating: 0, count: count)
        for sample in samples where sample.ts > from && sample.ts <= now {
            let index = min(count - 1, (sample.ts - from - 1) / curveBucket)
            sums[index] += sample.bpm
            counts[index] += 1
        }
        return (0..<count).map { counts[$0] > 0 ? Double(sums[$0]) / Double(counts[$0]) : nil }
    }

    /// A point of the route: when (unix ms) and how far from the start (metres).
    struct RoutePoint: Equatable {
        var tMs: Int64
        var meters: Double
    }

    /// The route as cumulative distance, from consecutive points.
    static func cumulative(_ points: [WorkoutRoutePoint]) -> [RoutePoint] {
        var out: [RoutePoint] = []
        var total = 0.0
        var previous: WorkoutRoutePoint?
        for point in points {
            if let previous {
                total += RouteMath.haversineMeters(.init(previous.lat, previous.lon), .init(point.lat, point.lon))
            }
            out.append(RoutePoint(tMs: point.tMs, meters: total))
            previous = point
        }
        return out
    }

    /// Active seconds between two instants: wall time minus the paused spans that overlap it.
    static func activeSeconds(from: Int64, to: Int64, pauses: [(start: Int64, end: Int64)]) -> Double {
        guard to > from else { return 0 }
        let paused = pauses.reduce(Int64(0)) { total, pause in
            total + max(0, min(to, pause.end) - max(from, pause.start))
        }
        return Double(to - from - paused) / 1000
    }

    /// The time of each whole `unitMeters` covered (a kilometre, or a mile), pauses left out. The crossing
    /// instant is interpolated between the two points either side of it.
    static func splits(_ route: [RoutePoint], unitMeters: Double = 1000,
                       pauses: [(start: Int64, end: Int64)] = []) -> [Int] {
        guard let first = route.first, unitMeters > 0 else { return [] }
        var out: [Int] = []
        var lastCrossing = first.tMs
        var next = unitMeters
        for (a, b) in zip(route, route.dropFirst()) where b.meters > a.meters {
            while b.meters >= next {
                let fraction = (next - a.meters) / (b.meters - a.meters)
                let crossing = a.tMs + Int64((Double(b.tMs - a.tMs) * fraction).rounded())
                out.append(Int(activeSeconds(from: lastCrossing, to: crossing, pauses: pauses).rounded()))
                lastCrossing = crossing
                next += unitMeters
            }
        }
        return out
    }

    /// Pace of the moment, seconds per kilometre, over the last `window` seconds of active time before
    /// the latest point. Nil until there is a real stretch to measure (at least `minimumMeters` and
    /// `minimumSeconds`), so the start never shows an absurd pace from a few metres.
    static func currentPace(_ route: [RoutePoint], pauses: [(start: Int64, end: Int64)] = [],
                            window: Double = 30, minimumMeters: Double = 50,
                            minimumSeconds: Double = 15) -> Double? {
        guard let last = route.last else { return nil }
        var start = last
        for point in route.reversed() {
            start = point
            if activeSeconds(from: point.tMs, to: last.tMs, pauses: pauses) >= window { break }
        }
        let meters = last.meters - start.meters
        let seconds = activeSeconds(from: start.tMs, to: last.tMs, pauses: pauses)
        guard meters >= minimumMeters, seconds >= minimumSeconds else { return nil }
        return seconds / (meters / 1000)
    }

    /// The screen's layout for a sport: cardio for a distance sport of the catalogue, or whenever a GPS
    /// route is being recorded; strength otherwise.
    static func layout(sport: String, recordingRoute: Bool) -> LiveWorkoutFigures.Layout {
        if recordingRoute { return .cardio }
        return WorkoutCatalog.sport(named: sport)?.isDistanceSport == true ? .cardio : .strength
    }

    /// "5:12" for a number of seconds (minutes:seconds; hours roll over as `ActiveWorkoutClock` does).
    static func splitText(_ seconds: Int) -> String {
        ActiveWorkoutClock.clock(seconds)
    }
}
