import Foundation

/// What a Coach message carries besides its text (personal fork). On a reply: what the coach looked at
/// with its read tools, shown under the reply, the session it proposed as a card (`create_program`) and
/// the meal it proposed as a card (`log_meal`, `read_label`). On a question: the photos sent with it,
/// whether it was dictated, and the barcode of a product whose label it sends.
///
/// Stored at the very end of the message text, as one fenced block (`noop-coach`) holding JSON. The
/// conversation table therefore needs no new column, and a build that does not know the block shows
/// it as code instead of losing it. Everything that reads a message for its words (the screen, copy,
/// share, the Journal, the history title, preview and search, what is sent back to the model) goes
/// through `body(_:)`, so the block is never read as part of the text.
struct CoachReplyMeta: Codable, Equatable {
    /// What the coach looked at, as the screen names it ("HRV since 3 Sept"), in call order.
    var consulted: [String] = []
    /// The session card, with the program it was added as once "Add to Lift Log" was tapped.
    var session: CoachSessionProposal?
    /// The meal card, with the journal meal it was saved as once "Add to journal" was tapped.
    var meal: CoachMealProposal?
    /// On a question: the photos sent with it, by their file names in `CoachPhotoStore`.
    var photos: [String] = []
    /// On a question: true when it was dictated (a meal it describes goes to the journal as dictated).
    var dictated: Bool = false
    /// On a question: the barcode of the product whose label it sends (Nutrition 4d, `read_label`).
    var barcode: String?
    /// The action card (chantier 8: a nap, a correction, a fact to remember), with its Confirm / Undo state.
    var action: CoachActionProposal?

    init(consulted: [String] = [], session: CoachSessionProposal? = nil, meal: CoachMealProposal? = nil,
         photos: [String] = [], dictated: Bool = false, barcode: String? = nil, action: CoachActionProposal? = nil) {
        self.consulted = consulted
        self.session = session
        self.meal = meal
        self.photos = photos
        self.dictated = dictated
        self.barcode = barcode
        self.action = action
    }

    private enum CodingKeys: String, CodingKey {
        case consulted, session, meal, photos, dictated, barcode, action
    }

    /// Every field optional on the way in, so a block written before a field existed still reads.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        consulted = try container.decodeIfPresent([String].self, forKey: .consulted) ?? []
        session = try container.decodeIfPresent(CoachSessionProposal.self, forKey: .session)
        meal = try container.decodeIfPresent(CoachMealProposal.self, forKey: .meal)
        photos = try container.decodeIfPresent([String].self, forKey: .photos) ?? []
        dictated = try container.decodeIfPresent(Bool.self, forKey: .dictated) ?? false
        barcode = try container.decodeIfPresent(String.self, forKey: .barcode)
        action = try container.decodeIfPresent(CoachActionProposal.self, forKey: .action)
    }

    /// Only what is set is written, so a reply's block stays as short as it was before photos.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if !consulted.isEmpty { try container.encode(consulted, forKey: .consulted) }
        try container.encodeIfPresent(session, forKey: .session)
        try container.encodeIfPresent(meal, forKey: .meal)
        if !photos.isEmpty { try container.encode(photos, forKey: .photos) }
        if dictated { try container.encode(dictated, forKey: .dictated) }
        try container.encodeIfPresent(barcode, forKey: .barcode)
        try container.encodeIfPresent(action, forKey: .action)
    }

    var isEmpty: Bool {
        consulted.isEmpty && session == nil && meal == nil && photos.isEmpty && !dictated && barcode == nil
            && action == nil
    }

    static let fenceOpen = "\n\n```noop-coach\n"
    static let fenceClose = "\n```"

    /// The message's words and its extras. A text with no valid block at its end is all words.
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

    /// The message's words alone.
    static func body(_ text: String) -> String { split(text).body }

    /// A reply as the model reads it back in a later turn: its words, then the session and the meal it
    /// showed as cards, written out, so a follow-up ("make it shorter", "add 50 g of rice") knows what it
    /// refers to.
    static func forModel(_ text: String, system: UnitSystem) -> String {
        let (body, meta) = split(text)
        guard meta?.session != nil || meta?.meal != nil || meta?.action != nil else { return body }
        var parts: [String] = []
        let words = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if !words.isEmpty { parts.append(words) }
        if let session = meta?.session { parts.append(session.wireText(system: system)) }
        if let meal = meta?.meal { parts.append(meal.wireText()) }
        if let action = meta?.action { parts.append(action.wireText()) }
        return parts.joined(separator: "\n\n")
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
