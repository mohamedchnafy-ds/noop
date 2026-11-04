import Foundation
import SwiftUI

// MARK: - Reorderable Sleep sections (#sleep-layout)
//
// The Sleep tab's analytical cards — Sleep marks, the Stages hypnogram, Naps, Night detail, the Sleep-debt
// ledger, Stages-vs-typical, and the Asleep-duration trend — render in one fixed order below the pinned
// Sleep-performance hero + date navigator. This lets the user REORDER or HIDE those cards, mirroring the
// Today tab's Arrange sheet (see `TodayLayoutPrefs`), with the default being the original order so nothing
// changes for anyone who never customises Sleep. Display-only — no metric is computed or stored
// differently; this only decides which already-built cards render and in what sequence.
//
// Stored as a single comma-joined string of section keys in @AppStorage("sleep.sectionOrder"), the same
// mechanism `TodayLayoutPrefs`/`KeyMetricPrefs` use. The Android side mirrors this byte-identically in
// SleepLayoutPrefs.kt (SharedPreferences "sleep.sectionOrder"). Every known section stays in the ORDER
// registry: unknown tokens are dropped, and any known section missing from the saved order is INSERTED at
// its default-order position relative to the saved sections — so a card added in a later version surfaces
// where users expect it rather than teleporting to the bottom of an existing saved order.
//
// User visibility is stored separately in "sleep.hiddenSections". Keeping order and visibility separate is
// intentional: hiding is reversible, a hidden card keeps its stable identity, and a card introduced by a
// future version defaults to visible because it is absent from the explicit hidden set.
//
// The Sleep-performance hero and the date navigator are NOT reorderable — they are the fixed frame of the
// tab, exactly as the Today hero is pinned above its arrangeable sections.

/// One reorderable Sleep card. The rawValue is the stable persisted identifier — keep it byte-identical to
/// the Android `SleepSection` enum so a backup/restore reads the same layout on either OS.
enum SleepSection: String, CaseIterable, Identifiable {
    case sleepMarks
    case stages
    case bodyClock
    case nightDetail
    case sleepDebt
    case stagesVsTypical
    case asleepDuration

    var id: String { rawValue }

    /// The card's display label in the Arrange sheet — matches the Android `SleepSection.title`.
    var title: String {
        switch self {
        case .sleepMarks:      return String(localized: "Sleep marks")
        case .stages:          return String(localized: "Stages")
        case .bodyClock:       return String(localized: "Body clock")
        case .nightDetail:     return String(localized: "Night detail")
        case .sleepDebt:       return String(localized: "Sleep-debt ledger")
        case .stagesVsTypical: return String(localized: "Stages vs typical")
        case .asleepDuration:  return String(localized: "Asleep duration")
        }
    }

    /// The original, hard-coded card order — the default when the layout isn't customised. Matches the
    /// pre-customisation render order in `SleepView` below the pinned Sleep-performance hero. (Naps rides
    /// with Stages for now — it's drawn inside the stages hero; making it an independently arrangeable
    /// card is a follow-up that requires hoisting the hero's edit/delete callbacks.)
    static let defaultOrder: [SleepSection] = [
        .sleepMarks, .stages, .bodyClock, .nightDetail, .sleepDebt, .stagesVsTypical, .asleepDuration,
    ]
}

/// Display-only persistence for the Sleep card order and visibility. The order registry always contains
/// every known card; `hiddenKey` stores the explicit reversible hidden set. Mirrors Android byte-for-byte,
/// and is a direct twin of `TodayLayoutPrefs` with a `sleep.` key namespace.
enum SleepLayoutPrefs {
    /// UserDefaults key — a comma-joined list of `SleepSection` rawValues in display order.
    static let orderKey = "sleep.sectionOrder"
    /// UserDefaults key — a comma-joined list of explicitly hidden `SleepSection` rawValues.
    static let hiddenKey = "sleep.hiddenSections"

    /// Encode an ordered card list into the stored comma-joined string.
    static func encode(_ sections: [SleepSection]) -> String {
        sections.map(\.rawValue).joined(separator: ",")
    }

    /// Encode the explicit hidden set in stable list order. The editor passes its Hidden-card order;
    /// rendering treats the decoded value as a set.
    static func encodeHidden(_ sections: [SleepSection]) -> String {
        sections.map(\.rawValue).joined(separator: ",")
    }

    /// Decode the stored string into the FULL ordered card list. An empty/unset string yields the default
    /// order. Unknown tokens are ignored, duplicates collapsed, and any known card missing from the saved
    /// order is INSERTED at its default-order position relative to the saved cards (before the first saved
    /// card that follows it in the default order; appended when none does) — so every card always renders,
    /// and one added in a later app version surfaces where users expect it instead of teleporting to the
    /// bottom of an existing saved order. Twin of the Kotlin `decodeOrder`.
    static func decodeOrder(_ raw: String) -> [SleepSection] {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return SleepSection.defaultOrder }
        var saved: [SleepSection] = []
        for token in trimmed.split(separator: ",") {
            if let s = SleepSection(rawValue: token.trimmingCharacters(in: .whitespaces)), !saved.contains(s) {
                saved.append(s)
            }
        }
        guard !saved.isEmpty else { return SleepSection.defaultOrder }
        // Iterate allCases (not defaultOrder) so a future case accidentally left out of defaultOrder can
        // never be silently hidden; a card without a default index sorts after everything. defaultOrder
        // covering allCases is pinned by SleepLayoutPrefsTests on both platforms.
        func defIdx(_ s: SleepSection) -> Int {
            SleepSection.defaultOrder.firstIndex(of: s) ?? SleepSection.defaultOrder.count
        }
        for missing in SleepSection.allCases where !saved.contains(missing) {
            let insertAt = saved.firstIndex { defIdx($0) > defIdx(missing) }
            if let insertAt { saved.insert(missing, at: insertAt) } else { saved.append(missing) }
        }
        return saved
    }

    /// Decode explicitly hidden cards. Empty/unset means nothing is hidden. Unknown tokens are ignored and
    /// duplicates collapsed; unlike `decodeOrder`, missing cases are NOT inserted because absence here means
    /// visible (including a card introduced by a future app version).
    static func decodeHidden(_ raw: String) -> [SleepSection] {
        var seen = Set<SleepSection>()
        var hidden: [SleepSection] = []
        for token in raw.split(separator: ",") {
            if let section = SleepSection(rawValue: token.trimmingCharacters(in: .whitespaces)),
               seen.insert(section).inserted {
                hidden.append(section)
            }
        }
        return hidden
    }

    /// The cards Sleep should render, preserving the full saved order while filtering only the user's
    /// explicit hidden set. At least one visible card is enforced by the editor, not the decoder.
    static func visibleOrder(orderRaw: String, hiddenRaw: String) -> [SleepSection] {
        let hidden = Set(decodeHidden(hiddenRaw))
        return decodeOrder(orderRaw).filter { !hidden.contains($0) }
    }
}

// MARK: - The Sleep tab page, chantier 9 (personal fork)
//
// The page reads: the night card (pinned in the top section, with the day's naps under it), Indicators,
// Your nights, then « Customize Sleep ». Four blocks left it and come back, under Your nights, only when
// switched on in « Customize Sleep » (`SleepRestoredBlock`). The stored order and hidden set are untouched
// and keep every token, so Android and a backup read the same layout.

extension SleepLayoutPrefs {
    /// Sections the iPhone Sleep page does not draw from the saved order: the stages (the night card is
    /// pinned at the top now), the marks and the body clock (switched back on through `SleepRestoredBlock`),
    /// the usual-night comparison (inside the curves view now) and the hours trend (the debt card's
    /// « 30 days »). They stay in the order and are left out of the editor.
    static let pageFoldedSections: Set<SleepSection> = [
        .stages, .sleepMarks, .bodyClock, .stagesVsTypical, .asleepDuration,
    ]

    /// The sections the page draws, in saved order minus the hidden set and the folded sections.
    static func pageSections(orderRaw: String, hiddenRaw: String) -> [SleepSection] {
        visibleOrder(orderRaw: orderRaw, hiddenRaw: hiddenRaw).filter { !pageFoldedSections.contains($0) }
    }
}

/// The blocks that left the Sleep page in chantier 9 and that « Customize Sleep » can put back, under
/// Your nights. Off by default. iPhone display preference only: stored on the device under `storageKey`,
/// outside the `.noopbak` whitelist, with no Android twin.
enum SleepRestoredBlock: String, CaseIterable, Identifiable {
    case tonight
    case whySleep
    case bodyClock
    case sleepMarks

    var id: String { rawValue }

    /// UserDefaults key: a comma-joined list of the blocks switched back on.
    static let storageKey = "sleep.restoredBlocks"

    var title: String {
        switch self {
        case .tonight:    return String(localized: "Tonight, aim for…")
        case .whySleep:   return String(localized: "Why this sleep?")
        case .bodyClock:  return String(localized: "Body clock")
        case .sleepMarks: return String(localized: "Sleep marks")
        }
    }

    /// One line on what the block is, under its switch.
    var detail: String {
        switch self {
        case .tonight:    return String(localized: "Your need plus the sleep debt. The suggested bedtime stays on Today.")
        case .whySleep:   return String(localized: "Why this block was taken as your main sleep.")
        case .bodyClock:  return String(localized: "Your rhythm's estimate against last night's bed and wake times.")
        case .sleepMarks: return String(localized: "Manual marks: they do not change the detected sleep.")
        }
    }

    /// Decode the stored list. Unknown tokens are dropped, duplicates collapsed; empty means all off.
    static func decodeRestored(_ raw: String) -> Set<SleepRestoredBlock> {
        Set(raw.split(separator: ",").compactMap {
            SleepRestoredBlock(rawValue: $0.trimmingCharacters(in: .whitespaces))
        })
    }

    /// Encode in the stable `allCases` order.
    static func encodeRestored(_ blocks: Set<SleepRestoredBlock>) -> String {
        allCases.filter { blocks.contains($0) }.map(\.rawValue).joined(separator: ",")
    }
}
