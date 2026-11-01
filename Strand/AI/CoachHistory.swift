import Foundation
import WhoopStore

/// What the history screen shows and searches for one stored conversation (personal fork): whether it
/// is a brief, a one-line preview of its latest answer, and its whole text for the search.
struct CoachConversationDigest: Equatable {
    let isBrief: Bool
    let preview: String
    let searchText: String

    /// Longest preview, in characters, before it is cut with "…".
    static let previewLength = 90

    init(messages: [(role: ChatMessage.Role, text: String)], briefPrefix: String) {
        isBrief = messages.first.map { $0.role == .assistant && $0.text.hasPrefix(briefPrefix) } ?? false
        let latest = messages.last(where: { $0.role == .assistant }) ?? messages.last
        var text = latest?.text ?? ""
        if text.hasPrefix(briefPrefix) { text.removeFirst(briefPrefix.count) }
        preview = Self.plain(text, limit: Self.previewLength)
        searchText = messages.map(\.text).joined(separator: "\n")
    }

    /// Markdown reduced to its words on one line: markers dropped, whitespace collapsed, cut at `limit`.
    static func plain(_ markdown: String, limit: Int) -> String {
        let stripped = markdown.filter { !"*#_`>|".contains($0) }
        let collapsed = stripped.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard collapsed.count > limit else { return collapsed }
        return String(collapsed.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }
}

/// The history screen's rules (personal fork): which group a conversation is listed under, its time
/// label, and the search. Pure, so the boundaries are tested with a fixed clock and calendar.
enum CoachHistory {

    enum Group: CaseIterable, Equatable, Hashable {
        case pinned, today, yesterday, thisWeek, earlier
    }

    /// One titled group of the list.
    struct Section: Identifiable, Equatable {
        let group: Group
        let rows: [CoachConversationRow]
        var id: Group { group }
    }

    /// Conversations grouped for the list: pinned ones first, then by the day they were last written.
    /// Most recent first inside each group; empty groups are left out.
    static func sections(_ rows: [CoachConversationRow], now: Date,
                         calendar: Calendar = .current) -> [Section] {
        var buckets: [Group: [CoachConversationRow]] = [:]
        for row in rows {
            buckets[groupOf(row, now: now, calendar: calendar), default: []].append(row)
        }
        return Group.allCases.compactMap { group in
            guard let rows = buckets[group], !rows.isEmpty else { return nil }
            return Section(group: group, rows: rows.sorted { $0.updatedAt > $1.updatedAt })
        }
    }

    static func groupOf(_ row: CoachConversationRow, now: Date, calendar: Calendar = .current) -> Group {
        if row.pinned { return .pinned }
        let days = dayDistance(from: row.updatedAt, to: now, calendar: calendar)
        switch days {
        case ..<1: return .today
        case 1: return .yesterday
        case 2..<7: return .thisWeek
        default: return .earlier
        }
    }

    /// Whole local days between the day of `timestamp` and the day of `now` (0 = same day).
    static func dayDistance(from timestamp: Int, to now: Date, calendar: Calendar = .current) -> Int {
        let then = calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(timestamp)))
        return calendar.dateComponents([.day], from: then, to: calendar.startOfDay(for: now)).day ?? 0
    }

    /// Whether a conversation matches the search: every word of `query` in its title or its messages,
    /// ignoring case and accents. A blank query matches everything.
    static func matches(title: String, text: String?, query: String) -> Bool {
        let words = query.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return true }
        let haystack = title + "\n" + (text ?? "")
        return words.allSatisfy { haystack.localizedStandardContains($0) }
    }
}
