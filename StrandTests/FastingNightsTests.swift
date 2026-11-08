import XCTest
import WhoopStore
@testable import Strand

/// Personal fork, chantier 15 PR C: « Fasting nights », the Carte's « Ce qui ressort » rule applied to the
/// nights inside a fast of 12 h or more against the others.
final class FastingNightsTests: XCTestCase {

    private let day = 86_400

    private func fast(start: Int, hours: Int) -> FastRow {
        FastRow(id: "f\(start)", startedAt: start, endedAt: start + hours * 3_600, goalMinutes: 960, createdAt: 0, updatedAt: 0)
    }

    /// Night `i` sleeps around 03:00 of day `i`; a fast from 20:00 the evening before covers it.
    private func night(_ i: Int, hrv: Double, rhr: Double, sleep: Double) -> FastingNightSample {
        FastingNightSample(day: "d\(i)", midSleep: i * day + 3 * 3_600, hrvMs: hrv, restingHR: rhr, sleepMin: sleep)
    }

    private func eveningFast(before i: Int, hours: Int = 16) -> FastRow { fast(start: i * day - 4 * 3_600, hours: hours) }

    func testANightCountsOnlyInsideAFastOfTwelveHoursOrMore() {
        let n = night(10, hrv: 60, rhr: 55, sleep: 420)
        XCTAssertTrue(FastingNights.isFastingNight(n, fasts: [eveningFast(before: 10)], now: 20 * day))
        XCTAssertFalse(FastingNights.isFastingNight(n, fasts: [eveningFast(before: 10, hours: 11)], now: 20 * day),
                       "an 11 h fast is not a fasting night")
        let running = FastRow(id: "r", startedAt: 10 * day - 4 * 3_600, endedAt: nil, goalMinutes: 960, createdAt: 0, updatedAt: 0)
        XCTAssertTrue(FastingNights.isFastingNight(n, fasts: [running], now: 10 * day + 9 * 3_600), "13 h so far")
        XCTAssertFalse(FastingNights.isFastingNight(n, fasts: [running], now: 10 * day + 4 * 3_600), "8 h so far")
        XCTAssertFalse(FastingNights.isFastingNight(n, fasts: [eveningFast(before: 11)], now: 20 * day))
    }

    func testUnderFiveNightsOnEitherSideTheCardWaits() {
        let nights = (1...8).map { night($0, hrv: 60, rhr: 55, sleep: 420) }
        let fasts = (1...4).map { eveningFast(before: $0) }
        let result = FastingNights.compareFastingNights(nights, fasts: fasts, now: 30 * day)
        XCTAssertEqual(result.fastingCount, 4)
        XCTAssertEqual(result.otherCount, 4)
        XCTAssertTrue(result.waiting)
        XCTAssertTrue(result.figures.allSatisfy { !$0.shown })
        XCTAssertTrue(result.figures.allSatisfy { $0.verdict == .tooFew })
    }

    func testAClearDifferenceShowsAndOneInsideTheMarginOrTheBandDoesNot() {
        // Fasting nights: HRV 66–70, RHR 52–53; other nights: HRV 59–63, RHR 53–55; sleep alike and noisy.
        let fastingHRV: [Double] = [66, 68, 70, 67, 69, 68]
        let otherHRV: [Double] = [61, 59, 63, 60, 62, 61]
        let fastingRHR: [Double] = [52, 53, 52, 53, 52, 53]
        let otherRHR: [Double] = [54, 55, 53, 54, 55, 54]
        let fastingSleep: [Double] = [400, 460, 430, 380, 470, 420]
        let otherSleep: [Double] = [410, 450, 440, 390, 460, 430]
        var nights: [FastingNightSample] = []
        var fasts: [FastRow] = []
        for i in 0..<6 {
            nights.append(night(i + 1, hrv: fastingHRV[i], rhr: fastingRHR[i], sleep: fastingSleep[i]))
            fasts.append(eveningFast(before: i + 1))
            nights.append(night(i + 11, hrv: otherHRV[i], rhr: otherRHR[i], sleep: otherSleep[i]))
        }
        let result = FastingNights.compareFastingNights(nights, fasts: fasts, now: 30 * day)
        XCTAssertFalse(result.waiting)
        XCTAssertEqual(result.fastingCount, 6)
        XCTAssertEqual(result.otherCount, 6)
        let hrv = result.figures.first { $0.metric == .hrv }!
        XCTAssertEqual(hrv.delta!, 7, accuracy: 0.001)
        XCTAssertEqual(hrv.verdict, .better)
        XCTAssertTrue(hrv.shown, "7 ms is past the 3 ms band and past its margin")
        let rhr = result.figures.first { $0.metric == .restingHR }!
        XCTAssertEqual(rhr.delta!, -1.5, accuracy: 0.001)
        XCTAssertEqual(rhr.verdict, .close, "1.5 bpm is inside the 3 bpm band")
        XCTAssertFalse(rhr.shown)
        let sleep = result.figures.first { $0.metric == .sleep }!
        XCTAssertFalse(sleep.shown, "a 3-minute difference is inside the band and the margin")
    }

    func testTheMarginOfADifferenceNeedsTwoValuesOnEachSide() {
        XCTAssertNil(FastingNights.marginOfDifference([1], [1, 2]))
        // Two groups of spread 1 (variance 1, n 2): 1.96 × √(1/2 + 1/2) = 1.96.
        XCTAssertEqual(FastingNights.marginOfDifference([0, 1.414_213_562], [5, 6.414_213_562])!, 1.96, accuracy: 0.001)
    }
}
