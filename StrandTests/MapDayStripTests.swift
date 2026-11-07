import XCTest
import SwiftUI
@testable import Strand

/// Personal fork, chantier 14 (Carte v2): the day's frise under the Map and the points' thin line
/// (`MapDayStripMath`, `LayeredMapGeometry`).
final class MapDayStripTests: XCTestCase {

    private func point(_ ts: Int, _ lat: Double, _ lon: Double) -> MapStripPoint {
        MapStripPoint(ts: ts, lat: lat, lon: lon)
    }

    func testAPositionOnTheFriseIsATimeOfTheDay() {
        XCTAssertEqual(MapDayStripMath.stripTime(x: 0, width: 240, dayStart: 0, dayEnd: 86_400), 0)
        XCTAssertEqual(MapDayStripMath.stripTime(x: 120, width: 240, dayStart: 0, dayEnd: 86_400), 43_200)
        XCTAssertEqual(MapDayStripMath.stripTime(x: 400, width: 240, dayStart: 0, dayEnd: 86_400), 86_400, "clamped")
        XCTAssertEqual(MapDayStripMath.stripShare(21_600, dayStart: 0, dayEnd: 86_400), 0.25)
    }

    func testTheCursorFollowsTheLineBetweenTwoPoints() {
        let points = [point(1_000, 48.0, 2.0), point(1_900, 48.2, 2.4)]
        let middle = MapDayStripMath.cursorPosition(at: 1_450, points: points)
        XCTAssertEqual(middle?.lat ?? 0, 48.1, accuracy: 1e-9)
        XCTAssertEqual(middle?.lon ?? 0, 2.2, accuracy: 1e-9)
        XCTAssertEqual(MapDayStripMath.cursorPosition(at: 1_000, points: points), LayeredMapCursor(lat: 48.0, lon: 2.0))
    }

    func testTheCursorStaysNearAPointOrDisappears() {
        let points = [point(10_000, 1, 1), point(30_000, 2, 2)]   // 5 h 33 apart: no line between them
        XCTAssertEqual(MapDayStripMath.cursorPosition(at: 11_000, points: points), LayeredMapCursor(lat: 1, lon: 1))
        XCTAssertNil(MapDayStripMath.cursorPosition(at: 20_000, points: points), "far from both")
        XCTAssertEqual(MapDayStripMath.cursorPosition(at: 31_000, points: points), LayeredMapCursor(lat: 2, lon: 2))
        XCTAssertNil(MapDayStripMath.cursorPosition(at: 40_000, points: points), "long after the last point")
        XCTAssertNil(MapDayStripMath.cursorPosition(at: 5_000, points: []))
    }

    func testTheHeartRateLineBreaksAtAGap() {
        let buckets = [0, 300, 600, 3_000, 3_300].map { PlaceHRBucket(ts: $0, bpm: 60) }
        XCTAssertEqual(MapDayStripMath.heartRateRuns(buckets).map(\.count), [3, 2])
    }

    func testThePointsLineBreaksBetweenDistantPoints() {
        let points = [0, 900, 1_800, 20_000, 20_900, 50_000].map {
            LayeredMapPoint(ts: Int64($0) * 1000, lat: 0, lon: 0, color: .gray, hollow: false)
        }
        XCTAssertEqual(LayeredMapGeometry.pointPathRuns(points).map(\.count), [3, 2], "a lone point draws no line")
    }

    func testAxisLabels() {
        XCTAssertEqual(MapDayStrip.axisHourLabel(6), "06:00")
        XCTAssertEqual(MapDayStrip.axisHourLabel(24), "24:00")
    }
}
