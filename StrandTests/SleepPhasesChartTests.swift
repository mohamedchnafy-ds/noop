import XCTest
@testable import Strand
import StrandDesign
import WhoopStore

/// The Sleep tab's stage chart (personal fork): which curve rides over the lanes, the round scales
/// printed beside each curve, and what a touch reads.
final class SleepPhasesChartTests: XCTestCase {

    private func assertClose(_ a: [Double], _ b: [Double], accuracy: Double,
                                file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(a.count == b.count && zip(a, b).allSatisfy { abs($0 - $1) <= accuracy },
                      "\(a) != \(b)", file: file, line: line)
    }

    // MARK: Where the curves go

    func testHeartRateAndHRVShareTheLanesAndTheTemperatureDropsBelow() {
        let split = SleepCurveLayout.split(heartRate: true, hrv: true, skinTemp: true)
        XCTAssertEqual(split.onStages, [.heartRate, .hrv])
        XCTAssertEqual(split.below, [.skinTemp])
    }

    func testTheTemperatureAloneRidesOverTheLanes() {
        let split = SleepCurveLayout.split(heartRate: false, hrv: false, skinTemp: true)
        XCTAssertEqual(split.onStages, [.skinTemp])
        XCTAssertEqual(split.below, [])
    }

    func testOneLineCurveTakesTheLanesAndTheTemperatureGoesUnderIt() {
        XCTAssertEqual(SleepCurveLayout.split(heartRate: false, hrv: true, skinTemp: true).onStages, [.hrv])
        XCTAssertEqual(SleepCurveLayout.split(heartRate: false, hrv: true, skinTemp: true).below, [.skinTemp])
        XCTAssertEqual(SleepCurveLayout.split(heartRate: true, hrv: false, skinTemp: false).onStages, [.heartRate])
        XCTAssertEqual(SleepCurveLayout.split(heartRate: false, hrv: false, skinTemp: false).onStages, [])
    }

    // MARK: Scales

    func testHeartRateScaleTicksEveryTwentyBeats() throws {
        let scale = try XCTUnwrap(SleepCurveScale.make([57, 70, 104]))
        XCTAssertEqual(scale.ticks, [60, 80, 100])
        XCTAssertEqual(scale.decimals, 0)
        XCTAssertLessThan(scale.lo, 57)
        XCTAssertGreaterThan(scale.hi, 104)
    }

    func testTemperatureScaleTicksEveryHalfDegreeWithOneDecimal() throws {
        let scale = try XCTUnwrap(SleepCurveScale.make([32.9, 33.6, 34.5]))
        XCTAssertEqual(scale.ticks, [33.0, 33.5, 34.0, 34.5])
        XCTAssertEqual(scale.decimals, 1)
    }

    func testNeverMoreThanFiveTicks() throws {
        for values in [[27.0, 73], [0.0, 1000], [12.0, 13], [33.1, 34.0], [41.0, 129]] {
            let scale = try XCTUnwrap(SleepCurveScale.make(values))
            XCTAssertGreaterThanOrEqual(scale.ticks.count, 2, "\(values)")
            XCTAssertLessThanOrEqual(scale.ticks.count, 5, "\(values)")
            for tick in scale.ticks {
                XCTAssertTrue(tick >= scale.lo && tick <= scale.hi, "\(tick) outside \(values)")
            }
        }
    }

    func testAFlatSeriesStillGetsAScale() throws {
        let scale = try XCTUnwrap(SleepCurveScale.make([60, 60, 60]))
        XCTAssertLessThan(scale.lo, 60)
        XCTAssertGreaterThan(scale.hi, 60)
        XCTAssertEqual(scale.y(60), 0.5, accuracy: 1e-9)
        XCTAssertNil(SleepCurveScale.make([]))
    }

    func testHigherValuesSitHigher() throws {
        let scale = try XCTUnwrap(SleepCurveScale.make([50, 100]))
        XCTAssertLessThan(scale.y(100), scale.y(50))
        XCTAssertGreaterThan(scale.y(50), 0)
        XCTAssertLessThan(scale.y(100), 1)
    }

    // MARK: Temperature as its gap to the night

    func testTemperatureReadsAsItsGapToTheNightsMedian() {
        // A strap whose provisional mapping reads ~40 °C still shows the night's own rise and dip.
        assertClose(SleepPhasesChartMath.gapToMedian([39.5, 40.0, 40.4, 41.0]), [-0.7, -0.2, 0.2, 0.8], accuracy: 1e-9)
        XCTAssertEqual(SleepPhasesChartMath.gapToMedian([33.0, 34.0, 35.0]), [-1, 0, 1])
        XCTAssertEqual(SleepPhasesChartMath.gapToMedian([]), [])
    }

    // MARK: Reading the chart

    func testReadingTakesTheNearestValueWithinFiveMinutes() {
        let points: [(t: TimeInterval, v: Double)] = [(0, 60), (120, 58), (600, 70)]
        XCTAssertEqual(SleepPhasesChartMath.value(at: 100, in: points), 58)
        XCTAssertEqual(SleepPhasesChartMath.value(at: 590, in: points), 70)
        XCTAssertNil(SleepPhasesChartMath.value(at: 3_000, in: points))
    }

    func testReadingNamesTheStageUnderTheTouch() {
        let intervals = [SleepInterval(stage: .light, start: 0, end: 600),
                         SleepInterval(stage: .rem, start: 600, end: 900)]
        XCTAssertEqual(SleepPhasesChartMath.stage(at: 599, in: intervals), .light)
        XCTAssertEqual(SleepPhasesChartMath.stage(at: 600, in: intervals), .rem)
        XCTAssertNil(SleepPhasesChartMath.stage(at: 900, in: intervals))
    }

    func testHeartRateBucketsOutsideTheNightAreDropped() {
        let night = Date(timeIntervalSince1970: 1_000_000)
        let buckets = [HRBucket(ts: 999_000, bpm: 70, minBpm: 70, maxBpm: 70),
                       HRBucket(ts: 1_000_000, bpm: 60, minBpm: 60, maxBpm: 60),
                       HRBucket(ts: 1_007_200, bpm: 55, minBpm: 55, maxBpm: 55),
                       HRBucket(ts: 1_010_000, bpm: 80, minBpm: 80, maxBpm: 80)]
        let points = SleepPhasesChartMath.points(buckets, nightStart: night, origin: 0, span: 7_200)
        XCTAssertEqual(points.map(\.t), [0, 7_200])
        XCTAssertEqual(points.map(\.v), [60, 55])
    }
}
