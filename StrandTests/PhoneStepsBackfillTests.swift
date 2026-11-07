import XCTest
import WhoopStore
@testable import Strand

/// The iPhone's daily steps copied before the pedometer forgets them (personal fork, 7 Nov.).
final class PhoneStepsBackfillTests: XCTestCase {

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    func testSevenCalendarDaysNewestFirstTodayEndingNow() {
        // 7 Nov. 2026, 10:00 UTC.
        let now = Date(timeIntervalSince1970: 1_794_045_600)
        let windows = PhoneStepsBackfill.phoneStepDayWindows(now: now, calendar: utc)
        XCTAssertEqual(windows.map(\.day), ["2026-11-07", "2026-11-06", "2026-11-05", "2026-11-04",
                                            "2026-11-03", "2026-11-02", "2026-11-01"])
        XCTAssertEqual(windows[0].start, utc.startOfDay(for: now))
        XCTAssertEqual(windows[0].end, now)
        XCTAssertEqual(windows[1].end.timeIntervalSince(windows[1].start), 86_400)
    }

    private func row(_ day: String, steps: Int?, kcal: Double? = nil, weight: Double? = nil) -> AppleDaily {
        AppleDaily(day: day, steps: steps, activeKcal: kcal, basalKcal: nil, vo2max: nil,
                   avgHr: nil, maxHr: nil, walkingHr: nil, weightKg: weight)
    }

    func testMergeKeepsTheOtherImportedValuesAndTheLargerCount() {
        let existing = [row("2026-11-05", steps: 9000), row("2026-11-06", steps: 3000, kcal: 420, weight: 74.5)]
        let phone = ["2026-11-04": 6000, "2026-11-05": 8000, "2026-11-06": 5000, "2026-11-07": 0]
        let rows = PhoneStepsBackfill.mergedPhoneStepRows(existing: existing, phone: phone)
        // 4 Nov. is new, 5 Nov. already holds more (Apple Health counts the Watch too), 6 Nov. keeps its
        // energy and weight, 7 Nov. counted nothing.
        XCTAssertEqual(rows, [row("2026-11-04", steps: 6000),
                              row("2026-11-06", steps: 5000, kcal: 420, weight: 74.5)])
    }
}
