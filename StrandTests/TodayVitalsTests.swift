import XCTest
@testable import Strand
import StrandAnalytics
import StrandDesign
import WhoopProtocol
import WhoopStore

/// The arithmetic behind the redesigned Today screen (personal fork): the 30-night ranges and normal
/// bands, the calorie split and its goal, the heart-rate thresholds and the 3-minute rule, the usual wake
/// time, the Lift Log rotation and the one-time layout move.
final class TodayVitalsTests: XCTestCase {

    private let utc = TimeZone(identifier: "UTC")!

    // MARK: Vital ranges

    func testGaugeSpansTheLastThirtyNightsAndAlwaysHoldsTheValue() {
        let days = (1...30).map { (day: String(format: "2026-10-%02d", $0), value: Double(55 + $0 % 5)) }
        let g = TodayVitalRange.gauge(value: 70, history: days, throughDay: "2026-10-30", normal: nil)
        XCTAssertEqual(g?.low, 55)
        XCTAssertEqual(g?.high, 70, "the shown value widens its own range")
        XCTAssertEqual(g?.fraction(70) ?? 0, 1, accuracy: 1e-9)
    }

    func testGaugeIgnoresNightsAfterTheDayShownAndOlderThanThirtyNights() {
        var days: [(day: String, value: Double)] = [(day: "2026-08-01", value: 40)]   // too old once 30 newer exist
        days += (1...30).map { (day: String(format: "2026-10-%02d", $0), value: 60) }
        days.append((day: "2026-11-02", value: 90))                                    // after the day shown
        let g = TodayVitalRange.gauge(value: 61, history: days, throughDay: "2026-10-31", normal: nil)
        XCTAssertEqual(g?.low, 60)
        XCTAssertEqual(g?.high, 61)
    }

    func testNoValueMeansNoGauge() {
        XCTAssertNil(TodayVitalRange.gauge(value: nil, history: [(day: "2026-10-01", value: 60)],
                                           throughDay: "2026-10-31", normal: nil))
    }

    func testNormalBandIsOneRobustSigmaAndOnlyOnceUsable() {
        let calibrating = BaselineState(baseline: 60, spread: 2, nValid: 2, nightsSinceUpdate: 0, status: .calibrating)
        XCTAssertNil(TodayVitalRange.normalBand(calibrating))
        let trusted = BaselineState(baseline: 60, spread: 2, nValid: 10, nightsSinceUpdate: 0, status: .trusted)
        let band = TodayVitalRange.normalBand(trusted)
        XCTAssertEqual(band?.lowerBound ?? 0, 60 - 2.506, accuracy: 1e-9)
        XCTAssertEqual(band?.upperBound ?? 0, 60 + 2.506, accuracy: 1e-9)
    }

    func testNormalBandIsClampedToTheRange() {
        let days = (1...10).map { (day: String(format: "2026-10-%02d", $0), value: Double(58 + $0 % 3)) }
        let g = TodayVitalRange.gauge(value: 59, history: days, throughDay: "2026-10-31", normal: 50...70)
        XCTAssertEqual(g?.normal, 58...60)
    }

    // MARK: Energy

    func testSplitAddsUpToTheStoredTotal() {
        let body = UserProfile(weightKg: 80, heightCm: 180, age: 35, sex: "male")
        let hr = (0..<3600).map { HRSample(ts: 1_000_000 + $0, bpm: $0 < 1800 ? 62 : 150) }
        let split = TodayEnergy.split(hr: hr, profile: body, hrmax: 185, restingHR: 60)
        let total = Calories.estimateDayCalories(hr, profile: body, hrmax: 185, restingHR: 60)
        XCTAssertNotNil(split)
        XCTAssertEqual(split!.totalKcal, total, accuracy: 1e-6)
        XCTAssertGreaterThan(split!.activityKcal, 0)
        XCTAssertNil(TodayEnergy.split(hr: [], profile: body, hrmax: 185, restingHR: 60))
    }

    func testDefaultGoalNeedsThreeDaysWithActivity() {
        XCTAssertNil(TodayEnergy.defaultGoal(activityByDay: [400, 0, 500]))
        XCTAssertEqual(TodayEnergy.defaultGoal(activityByDay: [400, 500, 600, 0]) ?? 0, 500, accuracy: 1e-9)
    }

    func testSettingWinsOverTheDefaultGoal() {
        XCTAssertEqual(TodayEnergy.goal(setting: 450, defaultGoal: 300), 450)
        XCTAssertEqual(TodayEnergy.goal(setting: 0, defaultGoal: 300), 300)
        XCTAssertNil(TodayEnergy.goal(setting: 0, defaultGoal: nil))
    }

    func testArcIsFullExactlyAtTheGoalAndMarksItOncePassed() {
        let atGoal = TodayEnergy.arc(.init(restingKcal: 600, activityKcal: 400), goal: 400)
        XCTAssertEqual(atGoal.resting + atGoal.activity, 1, accuracy: 1e-9)
        XCTAssertNil(atGoal.goalMark)

        let early = TodayEnergy.arc(.init(restingKcal: 600, activityKcal: 100), goal: 400)
        XCTAssertEqual(early.resting, 0.6, accuracy: 1e-9)
        XCTAssertEqual(early.activity, 0.1, accuracy: 1e-9)

        let past = TodayEnergy.arc(.init(restingKcal: 600, activityKcal: 600), goal: 400)
        XCTAssertEqual(past.resting + past.activity, 1, accuracy: 1e-9)
        XCTAssertEqual(past.goalMark ?? 0, 1000.0 / 1200.0, accuracy: 1e-9)
    }

    func testArcWithoutAGoalSharesTheGauge() {
        let a = TodayEnergy.arc(.init(restingKcal: 300, activityKcal: 100), goal: nil)
        XCTAssertEqual(a.resting, 0.75, accuracy: 1e-9)
        XCTAssertEqual(a.activity, 0.25, accuracy: 1e-9)
        XCTAssertNil(a.goalMark)
    }

    // MARK: Heart-rate alert

    private func samples(from start: Int, seconds: Int, bpm: Double) -> [(ts: Int, bpm: Double)] {
        (0...seconds).map { (ts: start + $0, bpm: bpm) }
    }

    func testThresholdsAreUsualPlusTwentyAndTheAwakeFloor() {
        let t = TodayHRAlert.thresholds(usualNow: 71, awakeFloor: 52)
        XCTAssertEqual(t.high, 91)
        XCTAssertEqual(t.low, 52)
    }

    func testHighCrossingCountsOnlyAfterThreeMinutes() {
        let t = TodayHRAlert.Thresholds(high: 91, low: nil)
        let short = samples(from: 1_000, seconds: 120, bpm: 98)
        XCTAssertNil(TodayHRAlert.crossing(samples: short, thresholds: t, now: 1_120))
        let long = samples(from: 1_000, seconds: 240, bpm: 98)
        let c = TodayHRAlert.crossing(samples: long, thresholds: t, now: 1_240)
        XCTAssertEqual(c?.side, .high)
        XCTAssertEqual(c?.sinceTs, 1_000)
        XCTAssertEqual(c?.minutes(now: 1_240), 4)
    }

    func testARunIsBrokenByADipOrADropout() {
        let t = TodayHRAlert.Thresholds(high: 91, low: nil)
        var s = samples(from: 1_000, seconds: 100, bpm: 98)
        s.append((ts: 1_101, bpm: 80))                              // back inside the range
        s += samples(from: 1_102, seconds: 150, bpm: 98)
        XCTAssertNil(TodayHRAlert.crossing(samples: s, thresholds: t, now: 1_252))
        var gap = samples(from: 1_000, seconds: 60, bpm: 98)
        gap += samples(from: 1_100, seconds: 150, bpm: 98)         // 40 s with no sample
        XCTAssertNil(TodayHRAlert.crossing(samples: gap, thresholds: t, now: 1_250))
    }

    func testLowCrossingUsesTheAwakeFloor() {
        let t = TodayHRAlert.Thresholds(high: 91, low: 50)
        let c = TodayHRAlert.crossing(samples: samples(from: 0, seconds: 200, bpm: 46), thresholds: t, now: 200)
        XCTAssertEqual(c?.side, .low)
        XCTAssertEqual(c?.threshold, 50)
    }

    func testAlertNeedsNoSessionAndAStillPhone() {
        let c = TodayHRAlert.Crossing(side: .high, threshold: 91, sinceTs: 0)
        XCTAssertEqual(TodayHRAlert.alert(crossing: c, sessionRunning: false, phoneStill: true), c)
        XCTAssertNil(TodayHRAlert.alert(crossing: c, sessionRunning: true, phoneStill: true))
        XCTAssertNil(TodayHRAlert.alert(crossing: c, sessionRunning: false, phoneStill: false))
        XCTAssertNil(TodayHRAlert.alert(crossing: c, sessionRunning: false, phoneStill: nil),
                     "no motion data never turns the curve orange")
    }

    func testAwakeFloorSkipsSleepAndNeedsThreeDays() {
        let day = 86_400
        func b(_ ts: Int, _ bpm: Double) -> HRBucket { HRBucket(ts: ts, bpm: bpm, minBpm: bpm, maxBpm: bpm) }
        var buckets = [b(2 * 3600, 44)]                               // asleep at 02:00
        for d in 0..<3 { buckets.append(b(d * day + 10 * 3600, 58 - Double(d))) }
        let sleep = [0...(6 * 3600)]
        XCTAssertEqual(TodayHRAlert.awakeFloor(buckets: buckets, sleep: sleep, zone: utc), 56)
        XCTAssertNil(TodayHRAlert.awakeFloor(buckets: Array(buckets.prefix(3)), sleep: sleep, zone: utc))
    }

    // MARK: Usual wake and bedtime

    func testUsualWakeIsTheMedianOfTheRecentNights() {
        let day = 86_400
        let wakes = [6 * 60, 6 * 60 + 10, 7 * 60, 6 * 60 + 4].enumerated().map { $0.offset * day + $0.element * 60 }
        XCTAssertEqual(HabitualWake.minutes(wakeTimestamps: wakes, zone: utc), 6 * 60 + 7)
        XCTAssertNil(HabitualWake.minutes(wakeTimestamps: Array(wakes.prefix(2)), zone: utc))
    }

    func testUsualWakeAcrossMidnightStaysNearMidnight() {
        let day = 86_400
        let wakes = [23 * 60 + 50, 10, 20].enumerated().map { $0.offset * day + $0.element * 60 }
        XCTAssertEqual(HabitualWake.minutes(wakeTimestamps: wakes, zone: utc), 10)
    }

    func testBedtimeIsTheNeedBeforeTheWakeWrappingMidnight() {
        XCTAssertEqual(HabitualWake.bedtime(wakeMinutes: 6 * 60 + 4, needMinutes: 480), 22 * 60 + 4)
        XCTAssertEqual(HabitualWake.bedtime(wakeMinutes: 7 * 60, needMinutes: 495), 22 * 60 + 45)
    }

    // MARK: Lift Log rotation

    func testRotationPicksTheProgramDoneLeastRecentlyNeverDoneFirst() {
        let ids = ["A", "B", "C"]
        XCTAssertEqual(LiftRotation.next(programIds: ids, lastDone: ["A": 30, "B": 10, "C": 20]), "B")
        XCTAssertEqual(LiftRotation.next(programIds: ids, lastDone: ["A": 30, "C": 20]), "B")
        XCTAssertEqual(LiftRotation.next(programIds: ids, lastDone: [:]), "A", "ties keep the stored order")
        XCTAssertNil(LiftRotation.next(programIds: [], lastDone: [:]))
    }

    func testLastDoneKeepsTheLatestStartPerProgram() {
        let done = LiftRotation.lastDone([(programId: "A", startTs: 5), (programId: "A", startTs: 9),
                                          (programId: nil, startTs: 12), (programId: "B", startTs: 7)])
        XCTAssertEqual(done, ["A": 9, "B": 7])
    }

    func testShapeCountsSupersetsAndSingleLines() {
        let s = LiftRotation.shape(labels: ["A", "A", "B", "B", nil, "C", "C", "D", "D"])
        XCTAssertEqual(s.supersets, 4)
        XCTAssertEqual(s.singles, 1)
    }

    func testTypicalMinutesIsTheMeanOfFinishedSessions() {
        XCTAssertEqual(LiftRotation.typicalMinutes([(startTs: 0, endTs: 3000), (startTs: 0, endTs: 3600)]), 55)
        XCTAssertNil(LiftRotation.typicalMinutes([]))
    }

    // MARK: Layout v2

    func testLayoutV2MovesHeartRateThenSynthesisUnderTheHeroOnce() {
        let moved = TodayLayoutPrefs.decodeOrder(TodayLayoutPrefs.liquidV2Order(""))
        XCTAssertEqual(Array(moved.prefix(4)), [.hero, .heartRate, .synthesis, .liveSession])
        let custom = "keyMetrics,hero,yourCards,heartRate,synthesis,workouts"
        let movedCustom = TodayLayoutPrefs.decodeOrder(TodayLayoutPrefs.liquidV2Order(custom))
        // decodeOrder first places the missing sections; the move then keeps everything else in place.
        XCTAssertEqual(Array(movedCustom.prefix(5)), [.liveSession, .keyMetrics, .hero, .heartRate, .synthesis])
        XCTAssertEqual(Set(movedCustom), Set(TodaySection.allCases), "every section token survives")
    }

    func testLiquidOrderNeverDrawsRecoveryVitalsButKeepsItStored() {
        let raw = TodayLayoutPrefs.liquidV2Order("")
        XCTAssertTrue(raw.contains("recoveryVitals"))
        XCTAssertFalse(TodayLayoutPrefs.liquidVisibleOrder(orderRaw: raw, hiddenRaw: "").contains(.recoveryVitals))
    }

    // MARK: Heart-rate card

    func testDayChartPlacesBucketsByTimeAndBreaksTheUsualDayOnGaps() {
        let start = 1_000_000 - 1_000_000 % 86_400
        let day = TodayHRDayInput(
            bucketTs: [start, start + 300, start + 3 * 3600], bucketBpm: [60, 62, 70],
            segments: hrGapSegments(bucketTs: [start, start + 300, start + 3 * 3600], bucketSeconds: 300),
            dayStart: start, domainEnd: start + 6 * 3600, isToday: true,
            habitual: [0: 58, 1: 59, 3: 61], restingHR: 55, awakeFloor: nil, sleep: [start + 3600...start + 2 * 3600])
        let chart = TodayHRCardLogic.dayChart(day, zone: utc)
        XCTAssertEqual(chart.points.map(\.x), [0, 300.0 / 21_600, 0.5])
        XCTAssertNotEqual(chart.points[1].run, chart.points[2].run, "a 3-hour hole is a break, not a climb")
        XCTAssertEqual(chart.habitual.count, 3)
        XCTAssertNotEqual(chart.habitual[1].run, chart.habitual[2].run)
        XCTAssertEqual(chart.sleep.first?.lowerBound ?? 0, 1.0 / 6, accuracy: 1e-9)
        XCTAssertEqual(chart.axis.map(\.x), [0, 2.0 / 6, 4.0 / 6])
    }

    func testLiveBandRunsFromRestingToUsualInEitherOrder() {
        XCTAssertEqual(TodayHRCardLogic.band(resting: 62, usual: 71), 62...71)
        XCTAssertEqual(TodayHRCardLogic.band(resting: 62, usual: 58), 58...62)
        XCTAssertNil(TodayHRCardLogic.band(resting: nil, usual: 71))
    }

    // MARK: Synthesis copy

    func testSessionLineNamesBlocksAndUsualLength() {
        let row = TodaySynthesisLogic.sessionRow(
            .init(name: "Full body A", state: .next, supersets: 4, singles: 1, typicalMinutes: 50), route: nil)
        XCTAssertEqual(row.value, "Full body A")
        XCTAssertNotNil(row.subtitle)
        let none = TodaySynthesisLogic.sessionRow(nil, route: nil)
        XCTAssertNil(none.subtitle)
    }

    func testBedtimeRowWithoutAUsualWakeSaysNoData() {
        let row = TodaySynthesisLogic.bedtimeRow(wakeMinutes: nil, needMinutes: 480) { "\($0)" }
        XCTAssertNil(row.subtitle)
        let known = TodaySynthesisLogic.bedtimeRow(wakeMinutes: 364, needMinutes: 480) { "\($0)" }
        XCTAssertEqual(known.value, "\(22 * 60 + 4)")
    }
}
