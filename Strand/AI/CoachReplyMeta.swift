import Foundation

/// What a Coach reply carries besides its text (personal fork): what the coach looked at with its read
/// tools, shown under the reply, and the session it proposed as a card (`create_program`).
///
/// Stored at the very end of the message text, as one fenced block (`noop-coach`) holding JSON. The
/// conversation table therefore needs no new column, and a build that does not know the block shows
/// it as code instead of losing it. Everything that reads a reply for its words (the screen, copy,
/// share, the Journal, the history preview and search, what is sent back to the model) goes through
/// `body(_:)`, so the block is never read as part of the answer.
struct CoachReplyMeta: Codable, Equatable {
    /// What the coach looked at, as the screen names it ("HRV since 3 Sept"), in call order.
    var consulted: [String] = []
    /// The session card, with the program it was added as once "Add to Lift Log" was tapped.
    var session: CoachSessionProposal?

    init(consulted: [String] = [], session: CoachSessionProposal? = nil) {
        self.consulted = consulted
        self.session = session
    }

    /// Every field optional on the way in, so a block written before a field existed still reads.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        consulted = try container.decodeIfPresent([String].self, forKey: .consulted) ?? []
        session = try container.decodeIfPresent(CoachSessionProposal.self, forKey: .session)
    }

    var isEmpty: Bool { consulted.isEmpty && session == nil }

    static let fenceOpen = "\n\n```noop-coach\n"
    static let fenceClose = "\n```"

    /// The reply's words and its extras. A text with no valid block at its end is all words.
    static func split(_ text: String) -> (body: String, meta: CoachReplyMeta?) {
        guard text.hasSuffix(fenceClose),
              let open = text.range(of: fenceOpen, options: .backwards) else { return (text, nil) }
        let closeStart = text.index(text.endIndex, offsetBy: -fenceClose.count)
        guard open.upperBound <= closeStart else { return (text, nil) }
        let json = String(text[open.upperBound..<closeStart])
        guard let data = json.data(using: .utf8),
              let meta = try? JSONDecoder().decode(CoachReplyMeta.self, from: data) else { return (text, nil) }
        return (String(text[..<open.lowerBound]), meta)
    }

    /// The reply's words alone.
    static func body(_ text: String) -> String { split(text).body }

    /// The reply as the model reads it back in a later turn: its words, then the session it showed as
    /// a card, written out, so a follow-up ("make it shorter") knows what it refers to.
    static func forModel(_ text: String, system: UnitSystem) -> String {
        let (body, meta) = split(text)
        guard let session = meta?.session else { return body }
        let words = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return (words.isEmpty ? "" : words + "\n\n") + session.wireText(system: system)
    }

    /// The text to store: the words, then the block when there is anything in it.
    static func join(body: String, meta: CoachReplyMeta?) -> String {
        guard let meta, !meta.isEmpty else { return body }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(meta), let json = String(data: data, encoding: .utf8) else {
            return body
        }
        return body + fenceOpen + json + fenceClose
    }
}
