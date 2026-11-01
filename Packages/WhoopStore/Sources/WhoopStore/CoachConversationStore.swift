import Foundation
import GRDB

// MARK: - v50 store: Coach conversation history (personal fork, iOS only)
//
// CoachConversationStore.swift — GRDB CRUD over `coachConversation` + `coachConversationMessage`
// (migration v50). Where `coachMessage` (v43) held ONE conversation that was retired at midnight,
// these keep every conversation so it can be reopened from the history. Same idiom as
// CoachMessageStore: plain Codable rows, raw `Row` fetch + manual decode, all GRDB work through the
// actor's `syncWrite` / `syncRead`. Messages reuse `CoachMessageRow`; the conversation they belong to
// is passed alongside rather than duplicated into every row.
//
// Like `coachMessage`, these tables carry only the questions and the coach's text replies (never raw
// readings) and are NOT part of the `.noopbak` settings whitelist. The Android app has no twin: it
// keeps its single `coachMessage` conversation (declared `ios_only` in schema_oracle.json).

/// The automatic title of a conversation: its first question, shortened for the history list.
public enum CoachConversationTitle {

    /// Longest automatic title, in characters, before it is cut at a word and ends with "…".
    public static let maxLength = 48

    /// The first line of `question`, whitespace collapsed, cut at the last word that fits in
    /// `maxLength` (or mid-word when one word alone is longer). Empty for a blank question.
    public static func make(fromQuestion question: String) -> String {
        let firstLine = question.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let words = firstLine.split(whereSeparator: \.isWhitespace)
        let collapsed = words.joined(separator: " ")
        guard collapsed.count > maxLength else { return collapsed }
        var title = ""
        for word in words {
            let next = title.isEmpty ? String(word) : title + " " + String(word)
            if next.count > maxLength - 1 { break }
            title = next
        }
        if title.isEmpty { title = String(collapsed.prefix(maxLength - 1)) }
        return title + "…"
    }
}

/// One conversation in the Coach history.
public struct CoachConversationRow: Equatable, Codable, Sendable {
    public var id: String
    /// Automatic (first question) or the wearer's own; empty until the first question is asked.
    public var title: String
    public var createdAt: Int        // epoch seconds
    public var updatedAt: Int        // epoch seconds; the history lists the most recent first
    public var pinned: Bool
    /// True once the wearer renamed it: the automatic title then never replaces theirs.
    public var titleEdited: Bool

    public init(id: String, title: String, createdAt: Int, updatedAt: Int,
                pinned: Bool = false, titleEdited: Bool = false) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.pinned = pinned
        self.titleEdited = titleEdited
    }

    /// The conversation that carries the single pre-v50 `coachMessage` transcript over: titled from its
    /// first question, dated from its first and last turns.
    static func carryingOver(_ messages: [CoachMessageRow]) -> CoachConversationRow {
        let firstQuestion = messages.first(where: { $0.role == "user" })?.text ?? ""
        let times = messages.map(\.createdAt)
        return CoachConversationRow(id: UUID().uuidString,
                                    title: CoachConversationTitle.make(fromQuestion: firstQuestion),
                                    createdAt: times.min() ?? 0, updatedAt: times.max() ?? 0)
    }

    static func decode(_ row: Row) -> CoachConversationRow {
        CoachConversationRow(id: row["id"], title: row["title"], createdAt: row["createdAt"],
                             updatedAt: row["updatedAt"], pinned: (row["pinned"] as Int) != 0,
                             titleEdited: (row["titleEdited"] as Int) != 0)
    }
}

extension WhoopStore {

    /// Every conversation, pinned ones first, then the most recently updated.
    public func coachConversations() async throws -> [CoachConversationRow] {
        try syncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM coachConversation ORDER BY pinned DESC, updatedAt DESC, createdAt DESC
                """).map(CoachConversationRow.decode)
        }
    }

    /// One conversation's turns, oldest first (by `orderIndex`).
    public func coachConversationMessages(conversationId: String) async throws -> [CoachMessageRow] {
        try syncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT id, role, text, provider, createdAt, orderIndex FROM coachConversationMessage
                WHERE conversationId = ? ORDER BY orderIndex ASC
                """, arguments: [conversationId]).map(CoachMessageRow.decode)
        }
    }

    /// Save `conversation` with ALL of its turns, in one transaction: called once per settled reply,
    /// never per streamed chunk (the same full-replace reasoning as `replaceCoachMessages`).
    ///
    /// An existing conversation keeps its pin and its title: the title only fills in while it is
    /// still empty and the wearer has not renamed it, so a rename or a pin made meanwhile from the
    /// history is never overwritten by the engine's copy.
    public func saveCoachConversation(_ conversation: CoachConversationRow,
                                      messages: [CoachMessageRow]) async throws {
        try syncWrite { db in
            try Self.writeCoachConversation(conversation, messages: messages, in: db)
        }
    }

    /// Rename a conversation; the automatic title stops applying to it.
    public func renameCoachConversation(id: String, title: String) async throws {
        try syncWrite { db in
            try db.execute(sql: "UPDATE coachConversation SET title = ?, titleEdited = 1 WHERE id = ?",
                           arguments: [title, id])
        }
    }

    /// Pin or unpin a conversation (pinned ones head the history).
    public func setCoachConversationPinned(id: String, pinned: Bool) async throws {
        try syncWrite { db in
            try db.execute(sql: "UPDATE coachConversation SET pinned = ? WHERE id = ?",
                           arguments: [pinned ? 1 : 0, id])
        }
    }

    /// Delete a conversation and its turns.
    public func deleteCoachConversation(id: String) async throws {
        try syncWrite { db in
            try db.execute(sql: "DELETE FROM coachConversationMessage WHERE conversationId = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM coachConversation WHERE id = ?", arguments: [id])
        }
    }

    /// Upsert the conversation row (see `saveCoachConversation` for what an existing row keeps) and
    /// replace its turns. Shared with migration v50, which carries the legacy transcript over.
    static func writeCoachConversation(_ conversation: CoachConversationRow,
                                       messages: [CoachMessageRow], in db: Database) throws {
        try db.execute(sql: """
            INSERT INTO coachConversation (id, title, createdAt, updatedAt, pinned, titleEdited)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                updatedAt = excluded.updatedAt,
                title = CASE WHEN coachConversation.titleEdited = 0 AND coachConversation.title = ''
                             THEN excluded.title ELSE coachConversation.title END
            """, arguments: [conversation.id, conversation.title, conversation.createdAt,
                             conversation.updatedAt, conversation.pinned ? 1 : 0,
                             conversation.titleEdited ? 1 : 0])
        try db.execute(sql: "DELETE FROM coachConversationMessage WHERE conversationId = ?",
                       arguments: [conversation.id])
        for message in messages {
            try db.execute(sql: """
                INSERT INTO coachConversationMessage
                    (id, conversationId, role, text, provider, createdAt, orderIndex)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """, arguments: [message.id, conversation.id, message.role, message.text,
                                 message.provider, message.createdAt, message.orderIndex])
        }
    }
}
