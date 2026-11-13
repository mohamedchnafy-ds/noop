import XCTest
@testable import Strand
import WhoopProtocol

/// Fork chantier 18, lot A2: the heart rate of a strength session — curve, recovery between sets, the
/// comparison aligned on elapsed time, the average per exercise.
final class LiftHeartRateMathTests: XCTestCase {

    private let t0 = 1_800_000_000

    /// One sample a second from `from` to `to`, at `bpm(ts)`.
    private func samples(_ from: Int, _ to: Int, _ bpm: (Int) -> Int) -> [HRSample] {
        (from...to).map { HRSample(ts: $0, bpm: bpm($0)) }
    }

    func testTheCurveAveragesEachBucketAndLeavesGapsEmpty() {
        let hr = [HRSample(ts: t0 + 1, bpm: 100), HRSample(ts: t0 + 5, bpm: 110), HRSample(ts: t0 + 25, bpm: 130)]
        let curve = LiftHeartRateMath.bucketCurve(hr, from: t0, to: t0 + 30, bucket: 10)
        XCTAssertEqual(curve, [105, nil, 130])
    }

    /// A set peaking at 150 and a rest coming down to 110: a recovery of 40. The peak is looked for a few
    /// seconds past the set's end, where it lands.
    func testRecoveryIsThePeakOfTheSetMinusTheLowOfItsRest() {
        let hr = samples(t0, t0 + 200) { ts in
            if ts <= t0 + 45 { return 120 + (ts - t0) / 2 }       // rising through the set to ~142
            if ts <= t0 + 48 { return 150 }                        // the late peak
            return max(110, 150 - (ts - t0 - 48))                  // coming down to 110
        }
        let set = LiftHeartRateMath.SetSpan(start: t0, end: t0 + 45, restSec: 120)
        XCTAssertEqual(LiftHeartRateMath.recovery(after: set, samples: hr, now: t0 + 200), 40)
    }

    func testARestTooShortOrWithoutSamplesHasNoRecovery() {
        let hr = samples(t0, t0 + 60) { _ in 120 }
        XCTAssertNil(LiftHeartRateMath.recovery(after: .init(start: t0, end: t0 + 40, restSec: 10),
                                                samples: hr, now: t0 + 60))
        XCTAssertNil(LiftHeartRateMath.recovery(after: .init(start: t0, end: t0 + 40, restSec: 90),
                                                samples: [], now: t0 + 200))
        XCTAssertNil(LiftHeartRateMath.recovery(after: .init(start: t0, end: t0 + 30, restSec: 30),
                                                samples: hr, now: t0 + 60), "a flat heart rate did not come down")
    }

    /// A rest still running reads up to now.
    func testTheRunningRestReadsUpToNow() {
        let hr = samples(t0, t0 + 90) { ts in ts <= t0 + 40 ? 140 : 140 - (ts - t0 - 40) }
        let set = LiftHeartRateMath.SetSpan(start: t0, end: t0 + 40, restSec: nil)
        XCTAssertEqual(LiftHeartRateMath.recovery(after: set, samples: hr, now: t0 + 70), 30)
    }

    /// An earlier session's curve is laid on this one's elapsed time, not on the clock.
    func testTheComparisonIsAlignedOnElapsedTime() {
        let earlier = t0 - 7 * 86_400
        let hr = [HRSample(ts: earlier + 305, bpm: 120), HRSample(ts: earlier + 315, bpm: 140)]
        let curve = LiftHeartRateMath.alignedCurve(hr, sessionStart: earlier, fromElapsed: 300, toElapsed: 320,
                                                   bucket: 10)
        XCTAssertEqual(curve, [120, 140])
    }

    func testRestsAreClippedToTheWindow() {
        let sets = [LiftHeartRateMath.SetSpan(start: t0, end: t0 + 50, restSec: 100),
                    LiftHeartRateMath.SetSpan(start: t0 + 150, end: t0 + 190, restSec: nil)]
        let spans = LiftHeartRateMath.restSpans(sets, from: t0 + 100, to: t0 + 200, now: t0 + 200)
        XCTAssertEqual(spans, [0.0...0.5, 0.9...1.0])
    }

    func testTheAveragePerExerciseFollowsTheOrderOfTheSession() {
        let hr = samples(t0, t0 + 300) { ts in ts < t0 + 150 ? 120 : 140 }
        let rows = LiftHeartRateMath.averageByExercise(
            [("Squat", t0, t0 + 40), ("Bench", t0 + 160, t0 + 200), ("Squat", t0 + 80, t0 + 120)], samples: hr)
        XCTAssertEqual(rows.map { $0.exercise }, ["Squat", "Bench"])
        XCTAssertEqual(rows.map { $0.average }, [120, 140])
    }
}
