import XCTest
import GRDB
@testable import WhoopStore

/// Personal fork: the Coach conversation history (migration v50). The single pre-v50 conversation is
/// copied over, every conversation is kept, and a rename or a pin made from the history survives the
/// engine saving its own copy of the conversation afterwards.
final class CoachConversationStoreTests: XCTestCase {

    private func message(_ id: String, _ role: String, _ text: String, at index: Int) -> CoachMessageRow {
        CoachMessageRow(id: id, role: role, text: text, provider: "anthropic",
                        createdAt: 1_000 + index, orderIndex: index)
    }

    // MARK: - Automatic title

    func testTitleIsTheFirstLineOfTheQuestion() {
        XCTAssertEqual(CoachConversationTitle.make(fromQuestion: "Je fais ma séance ?"), "Je fais ma séance ?")
        XCTAssertEqual(CoachConversationTitle.make(fromQuestion: "  J'ai   mal dormi \n et alors ?"), "J'ai mal dormi")
        XCTAssertEqual(CoachConversationTitle.make(fromQuestion: "\n\nCombien de séries ?"), "Combien de séries ?")
        XCTAssertEqual(CoachConversationTitle.make(fromQuestion: "   \n "), "")
    }

    func testLongTitleIsCutAtAWordAndFitsTheLimit() {
        let question = "Combien de séries de biceps je fais par semaine sur les quatre dernières semaines ?"
        let title = CoachConversationTitle.make(fromQuestion: question)
        XCTAssertEqual(title, "Combien de séries de biceps je fais par semaine…")
        XCTAssertLessThanOrEqual(title.count, CoachConversationTitle.maxLength)
    }

    func testOneOverlongWordIsCutMidWord() {
        let title = CoachConversationTitle.make(fromQuestion: String(repeating: "a", count: 80))
        XCTAssertEqual(title, String(repeating: "a", count: CoachConversationTitle.maxLength - 1) + "…")
    }

    // MARK: - Migration v50

    func testV50CreatesBothTables() async throws {
        let store = try await WhoopStore.inMemory()
        let tables = try await store.tableNames()
        XCTAssertTrue(tables.contains("coachConversation"))
        XCTAssertTrue(tables.contains("coachConversationMessage"))
        XCTAssertTrue(tables.contains("coachMessage"), "the legacy table is left in place")
    }

    func testV50CopiesTheLegacyConversationAndLeavesItInPlace() async throws {
        let dbQueue = try DatabaseQueue()
        try WhoopStore.makeMigrator().migrate(dbQueue, upTo: "v49-lift-superset-group")
        try await dbQueue.write { db in
            for (index, row) in [("a", "assistant", "Today's brief\n\nGo."), ("b", "user", "Je fais ma séance ?"),
                                 ("c", "assistant", "Oui, allégée.")].enumerated() {
                try db.execute(sql: """
                    INSERT INTO coachMessage (id, role, text, provider, createdAt, orderIndex)
                    VALUES (?, ?, ?, 'anthropic', ?, ?)
                    """, arguments: [row.0, row.1, row.2, 2_000 + index * 60, index])
            }
        }

        try WhoopStore.makeMigrator().migrate(dbQueue)

        try await dbQueue.read { db in
            let conversations = try Row.fetchAll(db, sql: "SELECT * FROM coachConversation")
                .map(CoachConversationRow.decode)
            XCTAssertEqual(conversations.count, 1)
            let conversation = try XCTUnwrap(conversations.first)
            XCTAssertEqual(conversation.title, "Je fais ma séance ?", "titled from the first QUESTION, not the brief")
            XCTAssertEqual(conversation.createdAt, 2_000)
            XCTAssertEqual(conversation.updatedAt, 2_120)
            XCTAssertFalse(conversation.pinned)
            XCTAssertFalse(conversation.titleEdited)

            let copied = try String.fetchAll(db, sql: """
                SELECT text FROM coachConversationMessage WHERE conversationId = ? ORDER BY orderIndex
                """, arguments: [conversation.id])
            XCTAssertEqual(copied, ["Today's brief\n\nGo.", "Je fais ma séance ?", "Oui, allégée."])
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM coachMessage"), 3,
                           "copied, never moved")
        }
    }

    func testV50WithNoLegacyConversationCreatesNone() async throws {
        let store = try await WhoopStore.inMemory()
        let conversations = try await store.coachConversations()
        XCTAssertTrue(conversations.isEmpty)
    }

    // MARK: - Store

    func testSavedConversationReadsBackInOrder() async throws {
        let store = try await WhoopStore.inMemory()
        let conversation = CoachConversationRow(id: "c1", title: "Séance", createdAt: 10, updatedAt: 20)
        try await store.saveCoachConversation(conversation, messages: [
            message("m2", "assistant", "Oui.", at: 1),
            message("m1", "user", "Je fais ma séance ?", at: 0),
        ])

        let conversations = try await store.coachConversations()
        XCTAssertEqual(conversations, [conversation])
        let texts = try await store.coachConversationMessages(conversationId: "c1").map(\.text)
        XCTAssertEqual(texts, ["Je fais ma séance ?", "Oui."])
    }

    func testSavingAgainReplacesTheTurnsAndKeepsTheFirstTitle() async throws {
        let store = try await WhoopStore.inMemory()
        var conversation = CoachConversationRow(id: "c1", title: "", createdAt: 10, updatedAt: 10)
        try await store.saveCoachConversation(conversation, messages: [message("b", "assistant", "Brief", at: 0)])

        conversation.title = "Je fais ma séance ?"
        conversation.updatedAt = 20
        try await store.saveCoachConversation(conversation, messages: [
            message("b", "assistant", "Brief", at: 0), message("q", "user", "Je fais ma séance ?", at: 1),
        ])
        conversation.title = "Autre chose"
        conversation.updatedAt = 30
        try await store.saveCoachConversation(conversation, messages: [message("q", "user", "Je fais ma séance ?", at: 0)])

        let saved = try await store.coachConversations()
        XCTAssertEqual(saved.map(\.title), ["Je fais ma séance ?"], "an empty title fills once, then stays")
        XCTAssertEqual(saved.map(\.updatedAt), [30])
        let count = try await store.coachConversationMessages(conversationId: "c1").count
        XCTAssertEqual(count, 1, "a save replaces the conversation's turns")
    }

    func testRenameAndPinSurviveTheEnginesNextSave() async throws {
        let store = try await WhoopStore.inMemory()
        let engineCopy = CoachConversationRow(id: "c1", title: "Je fais ma séance ?", createdAt: 10, updatedAt: 10)
        try await store.saveCoachConversation(engineCopy, messages: [message("q", "user", "Je fais ma séance ?", at: 0)])
        try await store.renameCoachConversation(id: "c1", title: "Séance du lundi")
        try await store.setCoachConversationPinned(id: "c1", pinned: true)

        var later = engineCopy
        later.updatedAt = 50
        try await store.saveCoachConversation(later, messages: [message("q", "user", "Je fais ma séance ?", at: 0)])

        let stored = try await store.coachConversations()
        let saved = try XCTUnwrap(stored.first)
        XCTAssertEqual(saved.title, "Séance du lundi")
        XCTAssertTrue(saved.titleEdited)
        XCTAssertTrue(saved.pinned)
        XCTAssertEqual(saved.updatedAt, 50)
    }

    func testHistoryListsPinnedFirstThenMostRecent() async throws {
        let store = try await WhoopStore.inMemory()
        for (id, updatedAt) in [("old", 10), ("new", 30), ("mid", 20)] {
            try await store.saveCoachConversation(
                CoachConversationRow(id: id, title: id, createdAt: updatedAt, updatedAt: updatedAt),
                messages: [message("\(id)-q", "user", id, at: 0)])
        }
        try await store.setCoachConversationPinned(id: "old", pinned: true)

        let order = try await store.coachConversations().map(\.id)
        XCTAssertEqual(order, ["old", "new", "mid"])
    }

    func testDeleteRemovesTheConversationAndOnlyItsTurns() async throws {
        let store = try await WhoopStore.inMemory()
        for id in ["keep", "drop"] {
            try await store.saveCoachConversation(
                CoachConversationRow(id: id, title: id, createdAt: 1, updatedAt: 1),
                messages: [message("\(id)-q", "user", id, at: 0), message("\(id)-a", "assistant", "ok", at: 1)])
        }

        try await store.deleteCoachConversation(id: "drop")

        let remaining = try await store.coachConversations().map(\.id)
        XCTAssertEqual(remaining, ["keep"])
        let dropped = try await store.coachConversationMessages(conversationId: "drop")
        XCTAssertTrue(dropped.isEmpty)
        let kept = try await store.coachConversationMessages(conversationId: "keep")
        XCTAssertEqual(kept.count, 2)
    }
}
