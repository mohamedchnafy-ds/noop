import XCTest
@testable import Strand
import StrandAnalytics
import WhoopProtocol

/// The in-progress workout screen's figures (personal fork, chantier 8): splits and the pace of the
/// moment with pauses left out, the curve of the last ten minutes, time in zones and the layout.
final class LiveWorkoutMathTests: XCTestCase {

    /// A straight route at `metersPerSecond`, one point every `every` seconds from `t0` (unix ms).
    private func route(seconds: Int, every: Int = 5, metersPerSecond: Double, t0: Int64 = 1_000_000) -> [LiveWorkoutMath.RoutePoint] {
        stride(from: 0, through: seconds, by: every).map {
            LiveWorkoutMath.RoutePoint(tMs: t0 + Int64($0) * 1000, meters: Double($0) * metersPerSecond)
        }
    }

    func testSplitsAreTheTimeOfEachWholeKilometre() {
        // 4 m/s = 250 s per km; 1 100 s covers 4.4 km.
        let splits = LiveWorkoutMath.splits(route(seconds: 1_100, metersPerSecond: 4))
        XCTAssertEqual(splits, [250, 250, 250, 250])
        XCTAssertEqual(LiveWorkoutMath.splits(route(seconds: 200, metersPerSecond: 4)), [], "under a kilometre")
        XCTAssertEqual(LiveWorkoutMath.splits([]), [])
        // A mile at 4 m/s: 402 s.
        XCTAssertEqual(LiveWorkoutMath.splits(route(seconds: 900, metersPerSecond: 4), unitMeters: 1609.344), [402, 402])
    }

    func testAPauseIsLeftOutOfTheSplitItFallsIn() {
        // 300 s at 4 m/s (1.2 km), a 120-s pause, then on at the same speed.
        let t0: Int64 = 1_000_000
        var points = route(seconds: 300, metersPerSecond: 4, t0: t0)
        let resume = t0 + 420_000
        points += stride(from: 5, through: 300, by: 5).map {
            LiveWorkoutMath.RoutePoint(tMs: resume + Int64($0) * 1000, meters: 1_200 + Double($0) * 4)
        }
        let pauses = [(start: t0 + 300_000, end: resume)]
        XCTAssertEqual(LiveWorkoutMath.splits(points, pauses: pauses), [250, 250])
        XCTAssertEqual(LiveWorkoutMath.splits(points), [250, 370], "without the pause it would count")
        XCTAssertEqual(LiveWorkoutMath.activeSeconds(from: t0, to: t0 + 600_000, pauses: pauses), 480)
    }

    func testThePaceOfTheMomentWaitsForARealStretch() {
        // The bug it replaces: 1:39 /km after a metre. Nothing until 50 m over 15 s.
        XCTAssertNil(LiveWorkoutMath.currentPace(route(seconds: 10, every: 1, metersPerSecond: 4)))
        XCTAssertNil(LiveWorkoutMath.currentPace([LiveWorkoutMath.RoutePoint(tMs: 0, meters: 1)]))
        XCTAssertNil(LiveWorkoutMath.currentPace([]))
        let pace = try? XCTUnwrap(LiveWorkoutMath.currentPace(route(seconds: 120, metersPerSecond: 4)))
        XCTAssertEqual(pace ?? 0, 250, accuracy: 0.5, "4 m/s = 4:10 /km")
        // It follows the last 30 s, not the average: 2 min slow then 1 min fast.
        var points = route(seconds: 120, metersPerSecond: 2)
        let last = points.last!
        points += stride(from: 5, through: 60, by: 5).map {
            LiveWorkoutMath.RoutePoint(tMs: last.tMs + Int64($0) * 1000, meters: last.meters + Double($0) * 5)
        }
        XCTAssertEqual(LiveWorkoutMath.currentPace(points) ?? 0, 200, accuracy: 0.5, "5 m/s = 3:20 /km")
    }

    func testTheCurveKeepsTheLastTenMinutesInTenSecondBuckets() {
        let now = 10_000
        let samples = [HRSample(ts: now - 700, bpm: 90),      // too old
                       HRSample(ts: now - 595, bpm: 120), HRSample(ts: now - 592, bpm: 124),
                       HRSample(ts: now, bpm: 150)]
        let curve = LiveWorkoutMath.recentCurve(samples, now: now)
        XCTAssertEqual(curve.count, 60)
        XCTAssertEqual(curve[0], 122)
        XCTAssertNil(curve[1], "no sample: a gap, never 0")
        XCTAssertEqual(curve[59], 150)
    }

    func testZonesAndLayout() {
        let zoneSet = HRZones.zones(maxHR: 190)
        let start = 1_000
        let samples = (0..<120).map { HRSample(ts: start + $0, bpm: $0 < 60 ? 120 : 160) }
        let seconds = LiveWorkoutMath.zoneSeconds(samples, zoneSet: zoneSet)
        XCTAssertEqual(seconds.count, 5)
        XCTAssertEqual(seconds.reduce(0, +), 120)
        XCTAssertEqual(seconds[zoneSet.zoneNumber(forBPM: 160) - 1], 60)

        XCTAssertEqual(LiveWorkoutMath.layout(sport: "Running", recordingRoute: false), .cardio)
        XCTAssertEqual(LiveWorkoutMath.layout(sport: "cycling", recordingRoute: false), .cardio)
        XCTAssertEqual(LiveWorkoutMath.layout(sport: "Strength Training", recordingRoute: false), .strength)
        XCTAssertEqual(LiveWorkoutMath.layout(sport: "Yoga", recordingRoute: false), .strength)
        XCTAssertEqual(LiveWorkoutMath.layout(sport: "Other", recordingRoute: true), .cardio,
                       "a GPS route being recorded shows the distance whatever the sport")
        XCTAssertEqual(LiveWorkoutMath.splitText(312), "5:12")
    }
}
