import Foundation

// Personal fork, chantier 10 (Élan), PR A: « Mon pourquoi », the wearer's own words, written on a motivated
// day and shown back on the days without (fiche: raisons personnelles > citations génériques).
//
// UserDefaults under the canonical key `elan.why`, which is also its `.noopbak` key: the text is the one
// Élan value worth restoring on a new phone (choice of 5 Nov.), so it is on the `BackupSettings` whitelist
// on both platforms (String kind, same key). The « Le Coach peut le lire » switch stays a device setting
// (off by default, the `places.coachCanRead` precedent): the Coach's context gains the block only when the
// text exists AND the switch is on. Nothing here touches the interface.

enum ElanWhy {

    /// UserDefaults AND `.noopbak` key of the text (`BackupSettings.whitelist`).
    static let textKey = "elan.why"

    /// UserDefaults: the Coach may read the text. Off by default; not in `.noopbak`.
    static let coachReadsKey = "elan.why.coachCanRead"

    /// Longer texts are cut at save: the card shows a few lines, the Coach needs no essay.
    static let maxLength = 600

    /// The text as written, trimmed; nil when empty.
    static func text(_ d: UserDefaults = .standard) -> String? {
        normalized(d.string(forKey: textKey))
    }

    /// Save the text (trimmed, cut at `maxLength`); an empty text removes it.
    static func setText(_ text: String?, _ d: UserDefaults = .standard) {
        if let kept = normalized(text) {
            d.set(kept, forKey: textKey)
        } else {
            d.removeObject(forKey: textKey)
        }
    }

    /// Trimmed and cut at `maxLength`; nil when nothing is left.
    static func normalized(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maxLength))
    }

    /// Off by default.
    static func coachCanRead(_ d: UserDefaults = .standard) -> Bool { d.bool(forKey: coachReadsKey) }

    static func setCoachCanRead(_ on: Bool, _ d: UserDefaults = .standard) { d.set(on, forKey: coachReadsKey) }

    /// The block the Coach's fiche carries (wired with the switch in PR B), or nil when there is no text or
    /// the wearer keeps it private. The instruction is part of the block so the model never recites the
    /// words back as a slogan.
    static func coachBlock(text: String?, allowed: Bool) -> String? {
        guard allowed, let text = normalized(text) else { return nil }
        return "WHY (the wearer's own reason for training, written on a motivated day; bring it up gently and "
            + "only when motivation is the subject, never as a slogan):\n" + text
    }
}
