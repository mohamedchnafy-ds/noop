import XCTest
import WhoopStore
@testable import Strand

/// Personal fork (13 Nov 2026): the Sleep tab's « Consistency » tile (bedtime regularity) read a fake
/// « 0 % ». Its approximate score took every stored session as a bedtime, and the merged sessions keep
/// naps and split fragments (#715), so one afternoon nap among the nights pushed the spread past the
/// 2 h floor. These pin one bedtime per night (`SleepModel.bedtimeOnsetsByNight`) and the score on it.
final class SleepConsistencyNightsTests: XCTestCase {

    private func at(_ day: Int, _ hour: Int, _ minute: Int) -> Int {
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: day,
                                                              hour: hour, minute: minute))
        return Int((date ?? Date(timeIntervalSince1970: 1_800_000_000)).timeIntervalSince1970)
    }

    private func block(_ start: Int, minutes: Int) -> CachedSleepSession {
        CachedSleepSession(startTs: start, endTs: start + minutes * 60, efficiency: nil,
                           restingHr: nil, avgHrv: nil, stagesJSON: nil)
    }

    private func consistency(_ sessions: [CachedSleepSession]) -> SleepModel.Metric {
        SleepModel.consistencySeries(days: [], navDays: SleepModel.navDays(navSessions: sessions),
                                     habitualMidsleepSec: nil, importedSleep: [:])
    }

    func testANapAmongRegularNightsNoLongerReadsZero() {
        let nights = (1...4).map { block(at($0, 23, 30), minutes: 450) }
        let nap = block(at(3, 14, 0), minutes: 40)
        let sessions = (nights + [nap]).sorted { $0.startTs < $1.startTs }
        XCTAssertEqual(SleepModel.bedtimeOnsetsByNight(navDays: SleepModel.navDays(navSessions: sessions),
                                                       habitualMidsleepSec: nil),
                       nights.map(\.startTs), "one bedtime per night, oldest first, the nap left out")
        XCTAssertEqual(consistency(sessions).latest ?? -1, 100, accuracy: 1e-9,
                       "four bedtimes at 23:30: perfectly regular, not 0 %")
    }

    func testTwoNightsAndANapAreNotEnough() {
        let sessions = [block(at(1, 23, 30), minutes: 450), block(at(2, 23, 30), minutes: 450),
                        block(at(3, 14, 0), minutes: 40)]
        XCTAssertNil(consistency(sessions).latest, "three sessions are not three nights: « from 3 nights »")
    }

    func testARealSpreadIsStillScored() {
        // Bedtimes 22:00, 23:00, 00:00: a 49 min spread.
        let sessions = [block(at(1, 22, 0), minutes: 420), block(at(2, 23, 0), minutes: 420),
                        block(at(4, 0, 0), minutes: 420)]
        let expected = 100 * (1 - 2_400.0.squareRoot() / 120)
        XCTAssertEqual(consistency(sessions).latest ?? -1, expected, accuracy: 1e-9)
    }
}
