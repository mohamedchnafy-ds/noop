import XCTest
@testable import Strand
import WhoopStore

/// The heart-rate line over the stepped hypnogram (personal fork): where the buckets land.
final class SleepHROverlayTests: XCTestCase {

    private func bucket(_ ts: Int, _ bpm: Double) -> HRBucket {
        HRBucket(ts: ts, bpm: bpm, minBpm: bpm, maxBpm: bpm)
    }

    func testBucketsOutsideTheWindowAreDroppedAndXFollowsTheAxis() {
        let night = 1_000_000.0
        let buckets = [bucket(999_000, 70), bucket(1_000_000, 60), bucket(1_003_600, 50), bucket(1_007_200, 55),
                       bucket(1_010_000, 80)]
        let layout = SleepHROverlayMath.layout(buckets: buckets, nightStartTs: night, origin: 0, span: 7_200)!
        XCTAssertEqual(layout.points.count, 3)
        XCTAssertEqual(layout.points[0].xFrac, 0)
        XCTAssertEqual(layout.points[1].xFrac, 0.5)
        XCTAssertEqual(layout.points[2].xFrac, 1)
    }

    func testScaleIsPaddedAndTheLowestRateIsMarked() {
        let buckets = [bucket(100, 60), bucket(160, 48), bucket(220, 48), bucket(280, 70)]
        let layout = SleepHROverlayMath.layout(buckets: buckets, nightStartTs: 100, origin: 0, span: 180)!
        XCTAssertEqual(layout.lo, 48 - SleepHROverlayMath.pad)
        XCTAssertEqual(layout.hi, 70 + SleepHROverlayMath.pad)
        XCTAssertEqual(layout.minIndex, 1, "the first lowest reading")
        // Highest rate sits at the top inset, lowest at the bottom inset.
        XCTAssertGreaterThan(layout.points[1].yFrac, layout.points[3].yFrac)
        XCTAssertLessThan(layout.points[3].yFrac, 0.5)
    }

    func testFewerThanTwoVisibleBucketsDrawNothing() {
        XCTAssertNil(SleepHROverlayMath.layout(buckets: [bucket(100, 60)], nightStartTs: 100, origin: 0, span: 600))
        XCTAssertNil(SleepHROverlayMath.layout(buckets: [], nightStartTs: 100, origin: 0, span: 600))
    }
}
