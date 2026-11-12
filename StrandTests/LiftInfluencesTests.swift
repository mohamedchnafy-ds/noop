import XCTest
@testable import Strand

/// Fork chantier 18, lot C: « What shapes my sessions » — groups, thresholds, the clear-difference rule.
final class LiftInfluencesTests: XCTestCase {

    private func facts(sleep: Double?, volume: Double, hr: Double? = nil) -> LiftInfluences.SessionFacts {
        var measures: [LiftInfluences.Measure: Double] = [.volume: volume]
        if let hr { measures[.averageHr] = hr }
        return LiftInfluences.SessionFacts(startTs: 0, sleepMin: sleep, waterMl: nil, sessionDayBefore: false,
                                           measures: measures)
    }

    func testNothingIsShownBeforeSixSessionsInEachGroupAndTwelveInAll() {
        let sessions = (0..<6).map { _ in facts(sleep: 480, volume: 5400) }
            + (0..<5).map { _ in facts(sleep: 400, volume: 5100) }
        let c = LiftInfluences.liftInfluenceComparison(sessions, factor: .sleep, measure: .volume)
        XCTAssertEqual(c.withCount, 6)
        XCTAssertEqual(c.withoutCount, 5)
        XCTAssertFalse(c.isEnough)
        XCTAssertNil(c.difference)
        XCTAssertEqual(c.smallerGroup, 5)
    }

    func testAClearAndFavorableDifference() {
        let sessions = (0..<6).map { _ in facts(sleep: 480, volume: 5400, hr: 118) }
            + (0..<6).map { _ in facts(sleep: 400, volume: 5100, hr: 124) }
        let volume = LiftInfluences.liftInfluenceComparison(sessions, factor: .sleep, measure: .volume)
        XCTAssertTrue(volume.isEnough)
        XCTAssertEqual(volume.difference, 300)
        XCTAssertTrue(volume.isClearDifference)
        XCTAssertTrue(volume.isFavorable)
        let hr = LiftInfluences.liftInfluenceComparison(sessions, factor: .sleep, measure: .averageHr)
        XCTAssertTrue(hr.isFavorable, "a lower average heart rate reads better")
    }

    func testASmallDifferenceIsNoClearDifference() {
        let sessions = (0..<6).map { _ in facts(sleep: 480, volume: 5150) }
            + (0..<6).map { _ in facts(sleep: 400, volume: 5100) }
        let c = LiftInfluences.liftInfluenceComparison(sessions, factor: .sleep, measure: .volume)
        XCTAssertFalse(c.isClearDifference, "50 kg on 5 100 is under 3 %")
    }

    func testUnknownFactsLeaveTheSessionOut() {
        let sessions = [facts(sleep: nil, volume: 9999)] + (0..<6).map { _ in facts(sleep: 480, volume: 5400) }
        let c = LiftInfluences.liftInfluenceComparison(sessions, factor: .sleep, measure: .volume)
        XCTAssertEqual(c.withCount + c.withoutCount, 6)
    }

    func testWaterCountsFromThreeHoursBeforeToTheEnd() {
        let start = 1_800_000_000
        let entries = [HydrationEntry(amountMl: 250, loggedAt: Date(timeIntervalSince1970: TimeInterval(start - 4 * 3600))),
                       HydrationEntry(amountMl: 500, loggedAt: Date(timeIntervalSince1970: TimeInterval(start - 3600))),
                       HydrationEntry(amountMl: 250, loggedAt: Date(timeIntervalSince1970: TimeInterval(start + 1200)))]
        XCTAssertEqual(LiftInfluences.liftSessionWater(entries, start: start, end: start + 3600), 750)
        XCTAssertNil(LiftInfluences.liftSessionWater([], start: start, end: start + 3600),
                     "no water logged that day is not known, rather than none")
    }

    func testASessionTheDayBefore() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        let monday = Int(calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 18))!.timeIntervalSince1970)
        let sunday = monday - 86_400
        XCTAssertTrue(LiftInfluences.liftHadSessionDayBefore(monday, among: [sunday, monday], calendar: calendar))
        XCTAssertFalse(LiftInfluences.liftHadSessionDayBefore(monday, among: [monday, sunday - 86_400], calendar: calendar))
    }
}
