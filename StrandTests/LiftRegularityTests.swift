import XCTest
@testable import Strand
import WhoopStore

/// Fork chantier 18, lot B3: working sets per week over 12 weeks, the days trained, the run of weeks.
final class LiftRegularityTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris")!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 18) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    private func session(_ day: Date, working: Int, warmups: Int = 0) -> LiftProgress.Session {
        let ts = Int(day.timeIntervalSince1970)
        let row = LiftSessionRow(id: "\(ts)", deviceId: "d", startTs: ts, endTs: ts + 3600, sport: "Strength",
                                 programId: nil, programName: nil, sessionRpe: nil, note: nil)
        func set(_ i: Int, warm: Bool) -> LiftSetRow {
            LiftSetRow(id: "\(ts)-\(i)", deviceId: "d", sessionId: row.id, ord: i, exercise: "Squat",
                       primaryMuscle: .quads, setIndex: i, weightKg: 60, reps: 8, rpe: nil, isWarmup: warm,
                       startTs: nil, endTs: nil, restSec: nil, note: nil)
        }
        let sets = (0..<warmups).map { set($0, warm: true) } + (0..<working).map { set(warmups + $0, warm: false) }
        return LiftProgress.Session(row: row, sets: sets)
    }

    func testSetsAndDaysAreCountedPerMondayWeek() {
        // Thursday 12 Nov 2026: this week starts Monday 9 Nov.
        let now = date(2026, 11, 12)
        let sessions = [session(date(2026, 11, 9), working: 12, warmups: 2),
                        session(date(2026, 11, 11), working: 10),
                        session(date(2026, 11, 3), working: 15)]
        let weeks = LiftRegularity.liftRegularityWeeks(sessions, now: now, calendar: calendar)
        XCTAssertEqual(weeks.count, 12)
        XCTAssertEqual(weeks.last?.workingSets, 22, "warm-ups are not working sets")
        XCTAssertEqual(weeks.last?.sessions, 2)
        XCTAssertEqual(weeks.last?.days, [true, false, true, false, false, false, false])
        XCTAssertEqual(weeks[10].workingSets, 15)
        XCTAssertEqual(weeks[10].days[1], true, "Tuesday 3 Nov")
    }

    func testAnEmptyCurrentWeekDoesNotBreakTheRun() {
        let now = date(2026, 11, 9, 8)   // Monday morning, nothing yet
        let sessions = [session(date(2026, 11, 4), working: 10), session(date(2026, 10, 28), working: 10),
                        session(date(2026, 10, 14), working: 10)]
        let weeks = LiftRegularity.liftRegularityWeeks(sessions, now: now, calendar: calendar)
        XCTAssertEqual(LiftRegularity.liftWeekStreak(weeks), 2, "two weeks in a row, then a gap")
        XCTAssertEqual(LiftRegularity.liftAverageSessions(weeks), 3.0 / 11.0, accuracy: 0.0001)
    }
}
