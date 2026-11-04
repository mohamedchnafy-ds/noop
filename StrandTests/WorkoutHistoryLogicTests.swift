import XCTest
@testable import Strand
import WhoopStore

/// The history screen's summary card and « By sport » bars (personal fork, mockup « Historique »).
final class WorkoutHistoryLogicTests: XCTestCase {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Paris")!
        cal.firstWeekday = 1  // Sunday first on purpose: the weeks must still start on Monday
        return cal
    }

    private func ts(_ day: Int, _ hour: Int = 18, month: Int = 11) -> Int {
        Int(calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!.timeIntervalSince1970)
    }

    private func row(_ sport: String, start: Int, minutes: Int, source: String = "manual", kcal: Double? = nil,
                     durationS: Double? = nil) -> WorkoutRow {
        WorkoutRow(startTs: start, endTs: start + minutes * 60, sport: sport, source: source,
                   durationS: durationS ?? Double(minutes * 60), energyKcal: kcal, avgHr: nil, maxHr: nil,
                   strain: nil, distanceM: nil, zonesJSON: nil, notes: nil, steps: nil)
    }

    func testKindsFollowTheSportWhateverItsSpelling() {
        XCTAssertEqual(WorkoutHistoryLogic.workoutKind(sport: "Elliptical", source: "manual"), .cardio)
        XCTAssertEqual(WorkoutHistoryLogic.workoutKind(sport: "treadmill walk", source: "apple-health"), .cardio)
        XCTAssertEqual(WorkoutHistoryLogic.workoutKind(sport: "Strength Training", source: "manual"), .lift)
        XCTAssertEqual(WorkoutHistoryLogic.workoutKind(sport: "TraditionalStrengthTraining", source: "whoop"), .lift)
        XCTAssertEqual(WorkoutHistoryLogic.workoutKind(sport: "Bench day", source: "lifting"), .lift)
        XCTAssertEqual(WorkoutHistoryLogic.workoutKind(sport: "Yoga", source: "manual"), .other)
        XCTAssertEqual(WorkoutHistoryLogic.workoutKind(sport: "detected", source: "my-whoop-noop"), .other)
    }

    func testMinutesReadTheStoredDurationFirst() {
        XCTAssertEqual(WorkoutHistoryLogic.workoutMinutes(row("Running", start: ts(2), minutes: 50, durationS: 1_800)), 30)
        XCTAssertEqual(WorkoutHistoryLogic.workoutMinutes(row("Running", start: ts(2), minutes: 50, durationS: 0)), 50)
    }

    func testBarUnitByWindow() {
        XCTAssertEqual(WorkoutHistoryLogic.barUnit(days: 7), .day)
        XCTAssertEqual(WorkoutHistoryLogic.barUnit(days: 30), .day)
        XCTAssertEqual(WorkoutHistoryLogic.barUnit(days: 90), .week)
        XCTAssertEqual(WorkoutHistoryLogic.barUnit(days: 365), .month)
        XCTAssertEqual(WorkoutHistoryLogic.barUnit(days: nil), .month)
    }

    func testSevenDayBarsEndOnTheLatestSessionAndStackByKind() {
        let rows = [
            row("Elliptical", start: ts(4, 18), minutes: 21),
            row("Indoor cycle", start: ts(4, 7), minutes: 15),
            row("Yoga", start: ts(4, 12), minutes: 15),
            row("Strength Training", start: ts(2), minutes: 51),
            row("Treadmill walk", start: ts(3), minutes: 36),
            // Outside the seven days.
            row("Running", start: ts(28, month: 10), minutes: 40),
        ]
        let bars = WorkoutHistoryLogic.historyBars(rows, days: 7, anchorTs: ts(4, 18), calendar: calendar)
        XCTAssertEqual(bars.count, 7)
        XCTAssertEqual(bars.first?.start, calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(ts(29, month: 10)))))
        XCTAssertEqual(bars.last?.start, calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(ts(4)))))
        XCTAssertEqual(bars[6], WorkoutHistoryBar(start: bars[6].start, cardioMinutes: 36, liftMinutes: 0, otherMinutes: 15))
        XCTAssertEqual(bars[5].cardioMinutes, 36)
        XCTAssertEqual(bars[4].liftMinutes, 51)
        XCTAssertEqual(bars.prefix(4).map(\.totalMinutes), [0, 0, 0, 0])
    }

    func testQuarterBarsAreMondayWeeks() {
        let rows = [row("Running", start: ts(4), minutes: 30), row("Running", start: ts(2, 8), minutes: 20)]
        let bars = WorkoutHistoryLogic.historyBars(rows, days: 90, anchorTs: ts(4), calendar: calendar)
        XCTAssertEqual(bars.count, 13)
        // 4 Nov 2026 is a Wednesday: its week starts on Monday 2 Nov, and both runs fall in it.
        XCTAssertEqual(bars.last?.start, calendar.date(from: DateComponents(year: 2026, month: 11, day: 2)))
        XCTAssertEqual(bars.last?.cardioMinutes, 50)
    }

    func testAllTimeBarsAreMonthsFromTheOldestRowCapped() {
        let rows = [row("Running", start: ts(4), minutes: 30), row("Yoga", start: ts(10, month: 8), minutes: 60)]
        let bars = WorkoutHistoryLogic.historyBars(rows, days: nil, anchorTs: ts(4), calendar: calendar)
        XCTAssertEqual(bars.count, 4)
        XCTAssertEqual(bars.first?.otherMinutes, 60)
        XCTAssertEqual(bars.last?.cardioMinutes, 30)
        let old = row("Running", start: Int(calendar.date(from: DateComponents(year: 2020, month: 1, day: 5))!
            .timeIntervalSince1970), minutes: 30)
        XCTAssertEqual(WorkoutHistoryLogic.historyBars(rows + [old], days: nil, anchorTs: ts(4), calendar: calendar).count,
                       WorkoutHistoryLogic.maxMonthBars)
    }

    func testSportsAreSortedByMinutesThenSessions() {
        let rows = [
            row("Elliptical", start: ts(4), minutes: 21, kcal: 176),
            row("Elliptical", start: ts(2), minutes: 21, kcal: 183.4),
            row("Strength Training", start: ts(2, 19), minutes: 51, kcal: 363),
            row("Indoor cycle", start: ts(4, 7), minutes: 15),
        ]
        let lines = WorkoutHistoryLogic.historySports(rows)
        XCTAssertEqual(lines.map(\.sport), ["Strength Training", "Elliptical", "Indoor cycle"])
        XCTAssertEqual(lines[1], WorkoutHistorySport(sport: "Elliptical", kind: .cardio, sessions: 2, minutes: 42, kcal: 359))
        XCTAssertEqual(lines[0].kind, .lift)
        XCTAssertEqual(lines[2].kcal, 0)
    }
}
