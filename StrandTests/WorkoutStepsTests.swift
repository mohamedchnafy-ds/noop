import XCTest
import StrandAnalytics
import WhoopProtocol
@testable import Strand

/// The phone's steps during an outdoor workout and the route's colours (personal fork, chantier 14).
final class WorkoutStepsTests: XCTestCase {

    /// A steady walk: one reading every 5 s, 10 steps each time (120 steps per minute), from t = 0.
    private func steadyWalk(readings: Int, stepsEach: Int = 10, startMs: Int64 = 0) -> [WorkoutStepSample] {
        (0..<readings).map { WorkoutStepSample(tMs: startMs + Int64($0) * 5000, steps: $0 * stepsEach) }
    }

    func testRecordsStepsOnlyForTheOutdoorOnFootSports() {
        XCTAssertTrue(WorkoutStepMath.recordsSteps(sport: "Walking"))
        XCTAssertTrue(WorkoutStepMath.recordsSteps(sport: "running"))
        XCTAssertTrue(WorkoutStepMath.recordsSteps(sport: " Hiking "))
        XCTAssertFalse(WorkoutStepMath.recordsSteps(sport: "Cycling"))
        XCTAssertFalse(WorkoutStepMath.recordsSteps(sport: "Strength"))
    }

    func testCadenceOfTheMomentNeedsHalfAWindow() {
        XCTAssertNil(WorkoutStepMath.stepCadenceNow([]))
        // 10 s of readings: below half the 30 s window.
        XCTAssertNil(WorkoutStepMath.stepCadenceNow(steadyWalk(readings: 3)))
        // 15 s: 30 steps in 15 s = 120 per minute.
        XCTAssertEqual(WorkoutStepMath.stepCadenceNow(steadyWalk(readings: 4)), 120)
        // A long walk is read over the last 30 s only.
        var samples = steadyWalk(readings: 20, stepsEach: 5)
        let last = samples.last!
        for index in 1...6 {
            samples.append(WorkoutStepSample(tMs: last.tMs + Int64(index) * 5000, steps: last.steps + index * 10))
        }
        XCTAssertEqual(WorkoutStepMath.stepCadenceNow(samples), 120)
    }

    func testCadenceIsNotReadAcrossAPause() {
        // 20 s of walking, a 60 s gap (paused), then 10 s: the stretch after the gap is too short.
        var samples = steadyWalk(readings: 5)
        samples.append(WorkoutStepSample(tMs: 80_000, steps: 50))
        samples.append(WorkoutStepSample(tMs: 85_000, steps: 60))
        samples.append(WorkoutStepSample(tMs: 90_000, steps: 70))
        XCTAssertNil(WorkoutStepMath.stepCadenceNow(samples))
    }

    func testCadenceByMinute() {
        // Two minutes at 120 per minute, then a paused minute, then half a minute at 60 per minute.
        var samples = steadyWalk(readings: 25)                       // 0 … 120 s, 240 steps
        let base = samples.last!.steps
        for index in 0...6 {                                           // 180 … 210 s, 5 steps each
            samples.append(WorkoutStepSample(tMs: 180_000 + Int64(index) * 5000, steps: base + index * 5))
        }
        XCTAssertEqual(WorkoutStepMath.stepCadenceByMinute(samples, startMs: 0), [120, 120, nil, 60])
    }

    func testStepsAtTimeInterpolates() {
        let samples = [WorkoutStepSample(tMs: 0, steps: 0), WorkoutStepSample(tMs: 10_000, steps: 20)]
        XCTAssertEqual(WorkoutStepMath.stepsAtTime(samples, tMs: 5000), 10, accuracy: 0.001)
        XCTAssertEqual(WorkoutStepMath.stepsAtTime(samples, tMs: -1), 0, accuracy: 0.001)
        XCTAssertEqual(WorkoutStepMath.stepsAtTime(samples, tMs: 99_000), 20, accuracy: 0.001)
    }

    func testStepsOfEachKilometre() {
        // 2.5 km at a steady 4 m/s (625 s), 2 steps per second: 500 steps per kilometre.
        let route = (0...125).map { LiveWorkoutMath.RoutePoint(tMs: Int64($0) * 5000, meters: Double($0) * 20) }
        let samples = (0...125).map { WorkoutStepSample(tMs: Int64($0) * 5000, steps: $0 * 10) }
        XCTAssertEqual(WorkoutStepMath.stepsPerSplit(samples, route: route), [500, 500])
        XCTAssertEqual(WorkoutStepMath.stepsPerSplit([], route: route), [])
    }

    func testCadenceBands() {
        XCTAssertEqual(RouteColoring.cadenceBand(60), 1)
        XCTAssertEqual(RouteColoring.cadenceBand(90), 2)
        XCTAssertEqual(RouteColoring.cadenceBand(120), 3)
        XCTAssertEqual(RouteColoring.cadenceBand(140), 4)
        XCTAssertEqual(RouteColoring.cadenceBand(175), 5)
    }

    func testZoneOfEachRoutePointFromTheNearestHeartRate() {
        // Max HR 200: Zone 1 from 100, Zone 3 from 140, Zone 5 from 180.
        let zoneSet = HRZones.zones(maxHR: 200)
        let points = [0, 10, 20, 100].map { WorkoutRoutePoint(lat: 48, lon: 2, accuracyM: 5, tMs: Int64($0) * 1000) }
        let hr = [HRSample(ts: 0, bpm: 105), HRSample(ts: 12, bpm: 150), HRSample(ts: 22, bpm: 185)]
        // The last point is 78 s from any sample: no zone.
        XCTAssertEqual(RouteColoring.zoneBandsForRoute(points, hr: hr, zoneSet: zoneSet), [1, 3, 5, 0])
        XCTAssertEqual(RouteColoring.zoneBandsForRoute(points, hr: [], zoneSet: zoneSet), [0, 0, 0, 0])
    }

    func testRouteIsCutIntoRunsThatShareTheirEnds() {
        let points = (0..<5).map { WorkoutRoutePoint(lat: Double($0), lon: 0, accuracyM: 5, tMs: Int64($0) * 1000) }
        let segments = RouteColoring.routeBandSegments(points, bands: [2, 2, 4, 4, 4])
        XCTAssertEqual(segments.map(\.band), [2, 4])
        XCTAssertEqual(segments.map { $0.points.map(\.lat) }, [[0, 1, 2], [2, 3, 4]])
        // A change of band on the last point does not leave a one-point segment.
        XCTAssertEqual(RouteColoring.routeBandSegments(points, bands: [1, 1, 1, 1, 3]).map(\.band), [1])
        XCTAssertEqual(RouteColoring.routeBandSegments(points, bands: [1, 1]), [])
    }

    func testStepStoreRoundTrip() {
        let defaults = UserDefaults(suiteName: "WorkoutStepsTests")!
        defaults.removePersistentDomain(forName: "WorkoutStepsTests")
        let samples = steadyWalk(readings: 3)
        WorkoutStepStore.store(samples, startTs: 100, sport: "Walking", into: defaults)
        XCTAssertEqual(WorkoutStepStore.load(startTs: 100, sport: "Walking", from: defaults), samples)
        WorkoutStepStore.store([], startTs: 100, sport: "Walking", into: defaults)
        XCTAssertNil(WorkoutStepStore.load(startTs: 100, sport: "Walking", from: defaults))
    }

    func testRouteMapKeepsThePeriodNewestFirst() {
        let now = Date(timeIntervalSince1970: 100 * 86_400)
        let keys = ["\(99 * 86_400)|Walking", "\(50 * 86_400)|Running", "\(80 * 86_400)|Hiking", "bad"]
        let month = RouteMapReader.routeKeysInPeriod(keys, period: .days30, now: now)
        XCTAssertEqual(month.map(\.sport), ["Walking", "Hiking"])
        XCTAssertEqual(RouteMapReader.routeKeysInPeriod(keys, period: .all, now: now).map(\.sport),
                       ["Walking", "Hiking", "Running"])
        XCTAssertEqual(RouteMapReader.zoneShares([1, 1, 3, 0]), [0.5, 0, 0.25, 0, 0])
    }
}
