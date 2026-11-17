import XCTest
import WhoopStore
@testable import Strand

/// Personal fork, chantier 24: the Coach's `get_habits` tool — offered with « Use my data » only, and its
/// result (every session with its note, the day it started, a running one, a habit asked by name).
final class CoachHabitsToolTests: XCTestCase {

    private let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Int {
        Int(utc.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
            .timeIntervalSince1970)
    }

    private let reading = HabitRow(id: "r", name: "Lecture", colorKey: "cyan", symbol: "book.fill", createdAt: 0, updatedAt: 0)
    private let meditation = HabitRow(id: "m", name: "Méditation", colorKey: "violet", symbol: "figure.mind.and.body",
                                      createdAt: 1, updatedAt: 1)

    private func session(_ id: String, _ habit: String, _ start: Int, _ end: Int?, note: String? = nil,
                         manual: Bool = false) -> HabitSessionRow {
        HabitSessionRow(id: id, habitId: habit, startedAt: start, endedAt: end, note: note, isManual: manual,
                        createdAt: start, updatedAt: start)
    }

    private func names(_ tools: [[String: Any]]) -> [String] { tools.compactMap { $0["name"] as? String } }

    func testOfferedWithMyDataOnly() {
        XCTAssertTrue(names(CoachTools.definitions(dataConsent: true, labBook: false)).contains("get_habits"))
        XCTAssertFalse(names(CoachTools.definitions(dataConsent: false, labBook: true)).contains("get_habits"))
    }

    func testTheRoleKeepsHabitsForTheQuestionsAboutThem() {
        let role = AICoachEngine.toolsRole(readTools: true)
        XCTAssertTrue(role.contains("get_habits"))
        XCTAssertTrue(role.contains("N'en parle jamais de toi-même"))
        XCTAssertFalse(AICoachEngine.toolsRole(readTools: false).contains("get_habits"))
    }

    func testEverySessionWithItsNoteAndTheDayItStarted() {
        let now = Date(timeIntervalSince1970: TimeInterval(at(15, 22, 1)))
        let sessions = [
            session("a", "r", at(12, 23, 10), at(13, 0, 5), note: "Lu trop tard, du mal à décrocher."),
            session("b", "r", at(11, 13), at(11, 13, 18), manual: true),
            session("c", "m", at(14, 7, 10), at(14, 7, 25)),
            session("run", "r", at(15, 21, 48), nil),
        ]
        let text = CoachTools.habitsResult([reading, meditation], sessions: sessions, days: 30, habitName: nil,
                                           now: now, calendar: utc)
        XCTAssertTrue(text.contains("Lecture: 2 session(s), 1h 13m in total."), text)
        XCTAssertTrue(text.contains("  2026-11-12 23:10-00:05 (55m) note: \"Lu trop tard, du mal à décrocher.\""), text)
        XCTAssertTrue(text.contains("  2026-11-11 13:00-13:18 (18m) [added by hand]"), text)
        XCTAssertTrue(text.contains("  2026-11-15 21:48 running now (13m so far)"), text)
        XCTAssertTrue(text.contains("Méditation: 1 session(s), 15m in total."), text)
    }

    func testOneHabitByNameAndTheEmptyCases() {
        let now = Date(timeIntervalSince1970: TimeInterval(at(15, 12)))
        let sessions = [session("c", "m", at(14, 7, 10), at(14, 7, 25))]
        let one = CoachTools.habitsResult([reading, meditation], sessions: sessions, days: 7, habitName: "méditation",
                                          now: now, calendar: utc)
        XCTAssertTrue(one.contains("Méditation: 1 session(s)"))
        XCTAssertFalse(one.contains("Lecture"))
        let unknown = CoachTools.habitsResult([reading], sessions: [], days: 7, habitName: "Guitare", now: now,
                                              calendar: utc)
        XCTAssertTrue(unknown.contains("No habit named \"Guitare\""))
        XCTAssertTrue(unknown.contains("Lecture"))
        let none = CoachTools.habitsResult([], sessions: [], days: 7, habitName: nil, now: now, calendar: utc)
        XCTAssertTrue(none.contains("no habit yet"))
    }
}
