import XCTest
@testable import Strand
import WhoopStore

/// The Coach history screen's rules (personal fork): groups and their day boundaries, the order inside a
/// group, the time style per group, the search, and the preview of a conversation. All pure, with a fixed
/// clock and a fixed calendar, so a run at midnight or in another time zone gives the same answer.
final class CoachHistoryTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }

    /// Sunday 1 November 2026, 17:30 in Paris.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 17, minute: 30))!
    }

    private func epoch(day: Int, month: Int = 11, hour: Int, minute: Int = 0) -> Int {
        let date = calendar.date(from: DateComponents(year: 2026, month: month, day: day,
                                                      hour: hour, minute: minute))!
        return Int(date.timeIntervalSince1970)
    }

    private func row(_ id: String, updatedAt: Int, pinned: Bool = false) -> CoachConversationRow {
        CoachConversationRow(id: id, title: id, createdAt: updatedAt, updatedAt: updatedAt, pinned: pinned)
    }

    // MARK: Groups

    func testDayBoundariesFollowTheLocalCalendarDay() {
        func group(_ timestamp: Int) -> CoachHistory.Group {
            CoachHistory.groupOf(row("x", updatedAt: timestamp), now: now, calendar: calendar)
        }
        XCTAssertEqual(group(epoch(day: 1, hour: 0, minute: 0)), .today)
        XCTAssertEqual(group(epoch(day: 1, hour: 17, minute: 29)), .today)
        XCTAssertEqual(group(epoch(day: 31, month: 10, hour: 23, minute: 59)), .yesterday)
        XCTAssertEqual(group(epoch(day: 31, month: 10, hour: 0, minute: 0)), .yesterday)
        XCTAssertEqual(group(epoch(day: 30, month: 10, hour: 23, minute: 59)), .thisWeek)
        XCTAssertEqual(group(epoch(day: 26, month: 10, hour: 9)), .thisWeek)
        XCTAssertEqual(group(epoch(day: 25, month: 10, hour: 23, minute: 59)), .earlier)
        XCTAssertEqual(group(epoch(day: 1, month: 9, hour: 12)), .earlier)
    }

    func testAPinnedConversationIsPinnedWhateverItsDay() {
        let old = row("old", updatedAt: epoch(day: 1, month: 9, hour: 12), pinned: true)
        let today = row("today", updatedAt: epoch(day: 1, hour: 9), pinned: true)
        XCTAssertEqual(CoachHistory.groupOf(old, now: now, calendar: calendar), .pinned)
        XCTAssertEqual(CoachHistory.groupOf(today, now: now, calendar: calendar), .pinned)
    }

    /// A conversation written "after now" (a clock moved back) is listed under today, not lost.
    func testAConversationFromTheFutureIsListedUnderToday() {
        let future = row("f", updatedAt: epoch(day: 3, hour: 8))
        XCTAssertEqual(CoachHistory.groupOf(future, now: now, calendar: calendar), .today)
    }

    func testSectionsComeInFixedOrderMostRecentFirstAndSkipEmptyGroups() {
        let rows = [
            row("week", updatedAt: epoch(day: 28, month: 10, hour: 10)),
            row("today-early", updatedAt: epoch(day: 1, hour: 7, minute: 30)),
            row("pinned", updatedAt: epoch(day: 28, month: 10, hour: 9), pinned: true),
            row("today-late", updatedAt: epoch(day: 1, hour: 9, minute: 20)),
            row("old", updatedAt: epoch(day: 1, month: 9, hour: 12)),
        ]
        let sections = CoachHistory.sections(rows, now: now, calendar: calendar)
        XCTAssertEqual(sections.map(\.group), [.pinned, .today, .thisWeek, .earlier])
        XCTAssertEqual(sections[1].rows.map(\.id), ["today-late", "today-early"])
        XCTAssertEqual(sections.flatMap(\.rows).count, rows.count)
    }

    func testNoConversationsGiveNoSections() {
        XCTAssertTrue(CoachHistory.sections([], now: now, calendar: calendar).isEmpty)
    }

    func testDayDistanceCountsCalendarDaysNotHours() {
        // 23:59 the day before is one day away, though only 18 hours separate them.
        XCTAssertEqual(CoachHistory.dayDistance(from: epoch(day: 31, month: 10, hour: 23, minute: 59),
                                                to: now, calendar: calendar), 1)
        XCTAssertEqual(CoachHistory.dayDistance(from: epoch(day: 1, hour: 0), to: now, calendar: calendar), 0)
        XCTAssertEqual(CoachHistory.dayDistance(from: epoch(day: 25, month: 10, hour: 12),
                                                to: now, calendar: calendar), 7)
    }

    // MARK: Time style

    func testTimeStylePerGroup() {
        XCTAssertEqual(CoachHistory.timeStyle(for: .today), .hourMinute)
        XCTAssertEqual(CoachHistory.timeStyle(for: .yesterday), .hourMinute)
        XCTAssertEqual(CoachHistory.timeStyle(for: .thisWeek), .weekday)
        XCTAssertEqual(CoachHistory.timeStyle(for: .pinned), .dayMonth)
        XCTAssertEqual(CoachHistory.timeStyle(for: .earlier), .dayMonth)
    }

    // MARK: Search

    func testABlankQueryMatchesEverything() {
        XCTAssertTrue(CoachHistory.matches(title: "Séance du jour", text: nil, query: ""))
        XCTAssertTrue(CoachHistory.matches(title: "Séance du jour", text: nil, query: "   "))
    }

    func testEveryWordMustAppearInTheTitleOrTheMessages() {
        let text = "Garde Full body A, avec 1 à 2 répétitions en réserve."
        XCTAssertTrue(CoachHistory.matches(title: "Séance du jour", text: text, query: "séance réserve"))
        XCTAssertFalse(CoachHistory.matches(title: "Séance du jour", text: text, query: "séance squat"))
    }

    func testSearchIgnoresCaseAndAccents() {
        XCTAssertTrue(CoachHistory.matches(title: "Séance du jour", text: nil, query: "SEANCE"))
        XCTAssertTrue(CoachHistory.matches(title: "Genou au squat", text: "Réduis l’amplitude",
                                           query: "reduis"))
    }

    func testSearchWithoutLoadedMessagesStillMatchesTitles() {
        XCTAssertTrue(CoachHistory.matches(title: "Analyse de ma nuit", text: nil, query: "nuit"))
        XCTAssertFalse(CoachHistory.matches(title: "Analyse de ma nuit", text: nil, query: "protéines"))
    }

    // MARK: Digest

    private let prefix = "Today's brief\n\n"

    func testABriefIsRecognisedAndItsHeadingLeftOutOfThePreview() {
        let digest = CoachConversationDigest(
            messages: [(role: .assistant, text: prefix + "**Charge 66**, short night: moderate session.")],
            briefPrefix: prefix)
        XCTAssertTrue(digest.isBrief)
        XCTAssertEqual(digest.preview, "Charge 66, short night: moderate session.")
    }

    func testAQuestionIsNotABriefAndThePreviewIsTheLatestAnswer() {
        let digest = CoachConversationDigest(
            messages: [(role: .user, text: "Can I train hard today?"),
                       (role: .assistant, text: "Yes."),
                       (role: .user, text: "And tomorrow?"),
                       (role: .assistant, text: "# Tomorrow\n\n- keep *2 reps* in reserve")],
            briefPrefix: prefix)
        XCTAssertFalse(digest.isBrief)
        XCTAssertEqual(digest.preview, "Tomorrow - keep 2 reps in reserve")
        XCTAssertTrue(digest.searchText.contains("And tomorrow?"))
        XCTAssertTrue(digest.searchText.contains("Can I train hard today?"))
    }

    func testAQuestionWithoutAnAnswerYetPreviewsTheQuestion() {
        let digest = CoachConversationDigest(messages: [(role: .user, text: "How was my night?")],
                                             briefPrefix: prefix)
        XCTAssertEqual(digest.preview, "How was my night?")
    }

    func testALongPreviewIsCutWithAnEllipsisWithinTheLimit() {
        let long = String(repeating: "word ", count: 60)
        let digest = CoachConversationDigest(messages: [(role: .assistant, text: long)], briefPrefix: prefix)
        XCTAssertLessThanOrEqual(digest.preview.count, CoachConversationDigest.previewLength)
        XCTAssertTrue(digest.preview.hasSuffix("…"))
        XCTAssertFalse(digest.preview.dropLast().hasSuffix(" "))
    }

    func testAnEmptyConversationHasAnEmptyPreview() {
        let digest = CoachConversationDigest(messages: [], briefPrefix: prefix)
        XCTAssertFalse(digest.isBrief)
        XCTAssertEqual(digest.preview, "")
        XCTAssertEqual(digest.searchText, "")
    }
}
