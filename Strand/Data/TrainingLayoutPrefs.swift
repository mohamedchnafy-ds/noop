import Foundation

// MARK: - Training page layout (personal fork, chantier 9)
//
// « Customize Training »: the blocks under the week and the day card — Progression, Programs, Other
// activities — can be reordered and hidden. The week (strip or month) and the day card stay on top: they are
// the frame of the screen, as Today's rings are. Display-only and kept on the iPhone (UserDefaults, outside
// the `.noopbak`); Android has no twin of this screen, so there is nothing to mirror.
//
// Stored like `SleepLayoutPrefs`: a comma-joined order and a comma-joined hidden set. Unknown tokens are
// dropped, and a known block missing from a saved order is inserted at its default position, so a block
// added later appears where it belongs.

/// One block of the Training page below the day card. The rawValue is the stored token.
enum TrainingSection: String, CaseIterable, Identifiable {
    case progression
    case programs
    case otherActivities

    var id: String { rawValue }

    /// The block's name in « Customize Training ».
    var title: String {
        switch self {
        case .progression: return String(localized: "Progression")
        case .programs: return String(localized: "Programs")
        case .otherActivities: return String(localized: "Other activities")
        }
    }

    /// The mockup's order (chantier 9, section 5): Progression, Programs, Other activities.
    static let defaultOrder: [TrainingSection] = [.progression, .programs, .otherActivities]
}

enum TrainingLayoutPrefs {
    /// UserDefaults key: the `TrainingSection` tokens in display order.
    static let orderKey = "training.sectionOrder"
    /// UserDefaults key: the hidden `TrainingSection` tokens.
    static let hiddenKey = "training.hiddenSections"

    static func encodeSections(_ sections: [TrainingSection]) -> String {
        sections.map(\.rawValue).joined(separator: ",")
    }

    /// The stored order with every known block once: unknown and repeated tokens dropped, a missing block
    /// inserted after the block that precedes it in the default order (first when none does).
    static func decodeSectionOrder(_ raw: String) -> [TrainingSection] {
        var order: [TrainingSection] = []
        for token in raw.split(separator: ",") {
            let trimmed = token.trimmingCharacters(in: .whitespaces)
            if let section = TrainingSection(rawValue: trimmed), !order.contains(section) {
                order.append(section)
            }
        }
        for (index, section) in TrainingSection.defaultOrder.enumerated() where !order.contains(section) {
            let before = TrainingSection.defaultOrder[..<index].last { order.contains($0) }
            let at = before.flatMap { order.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
            order.insert(section, at: at)
        }
        return order
    }

    /// The hidden blocks; unknown tokens dropped.
    static func decodeHiddenSections(_ raw: String) -> Set<TrainingSection> {
        Set(raw.split(separator: ",").compactMap {
            TrainingSection(rawValue: $0.trimmingCharacters(in: .whitespaces))
        })
    }

    /// What the page draws, in order: the stored order without the hidden blocks.
    static func shownSections(orderRaw: String, hiddenRaw: String) -> [TrainingSection] {
        let hidden = decodeHiddenSections(hiddenRaw)
        return decodeSectionOrder(orderRaw).filter { !hidden.contains($0) }
    }
}
