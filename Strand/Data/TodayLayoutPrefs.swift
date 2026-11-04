import Foundation
import SwiftUI

// MARK: - Reorderable Today sections (#today-layout)
//
// The liquid Today's sections — the Charge/Effort/Rest hero, the Start-session entry, Synthesis, Key
// Metrics, Workouts, Heart Rate, Recovery Vitals, Your Cards — rendered in one fixed order. This lets the
// user REORDER or HIDE them, with the default being the original order so nothing changes for anyone who
// never customizes Today. Display-only — no metric is computed or stored differently; this only decides
// which already-built sections render and in what sequence.
//
// Stored as a single comma-joined string of section keys in @AppStorage("today.sectionOrder"), the same
// mechanism KeyMetricPrefs uses. The Android side mirrors this byte-identically in TodayLayoutPrefs.kt
// (SharedPreferences "today.sectionOrder"). Every known section stays in the ORDER registry: unknown tokens
// are dropped, and any known section missing from the saved order is INSERTED at its default-order position
// relative to the saved sections — so a section added in a later version surfaces where users expect it
// rather than teleporting to the bottom of an existing saved order.
//
// User visibility is stored separately in "today.hiddenSections". Keeping order and visibility separate is
// intentional: hiding is reversible, a hidden section keeps its stable identity, and a section introduced by
// a future version defaults to visible because it is absent from the explicit hidden set.

/// One reorderable Today section. The rawValue is the stable persisted identifier — keep it byte-identical
/// to the Android `TodaySection` enum so a backup/restore reads the same layout on either OS.
enum TodaySection: String, CaseIterable, Identifiable {
    case hero
    case liveSession
    case synthesis
    case keyMetrics
    case workouts
    case heartRate
    case recoveryVitals
    case yourCards
    case menstrualCycle
    case journal
    /// Cards hosted from the Trends / Sleep tabs (#today-hosted-cards). Renders the `HostedCardPrefs`
    /// selection in order; empty (and effectively invisible) until the user adds a card in Customise.
    /// Appended LAST so `decodeOrder`'s back-fill lands it predictably for existing saved orders.
    case addedCards
    /// The hour-by-hour stress card the Liquid Today draws under the heart-rate card (personal fork,
    /// chantier 9). Appended LAST like `addedCards`; the Kotlin twin keeps the token and draws nothing.
    case stress

    var id: String { rawValue }

    /// The section's display label in the Arrange sheet — matches the Android `TodaySection.title`.
    var title: String {
        switch self {
        case .hero:           return String(localized: "Charge / Effort / Rest")
        case .liveSession:    return String(localized: "Start session")
        case .synthesis:      return String(localized: "Synthesis")
        case .keyMetrics:     return String(localized: "Key Metrics")
        case .workouts:       return String(localized: "Workouts")
        case .heartRate:      return String(localized: "Heart Rate")
        case .recoveryVitals: return String(localized: "Recovery Vitals")
        case .yourCards:      return String(localized: "Your Cards")
        case .menstrualCycle: return String(localized: "Menstrual Cycle")
        case .journal:        return String(localized: "Journal")
        case .addedCards:     return String(localized: "Added Cards")
        case .stress:         return String(localized: "Stress")
        }
    }

    /// The original, hard-coded section order — the default when the layout isn't customised. The journal
    /// widget (#656) is last by default, where it was first added, above the data-sources card.
    static let defaultOrder: [TodaySection] = [
        .hero, .liveSession, .synthesis, .keyMetrics, .workouts, .heartRate, .recoveryVitals, .yourCards,
        .menstrualCycle, .journal, .addedCards, .stress,
    ]
}

/// Display-only persistence for the Today section order and visibility. The order registry always contains
/// every known section; `hiddenKey` stores the explicit reversible hidden set. Mirrors Android byte-for-byte.
enum TodayLayoutPrefs {
    /// UserDefaults key — a comma-joined list of `TodaySection` rawValues in display order.
    static let orderKey = "today.sectionOrder"
    /// UserDefaults key — a comma-joined list of explicitly hidden `TodaySection` rawValues.
    static let hiddenKey = "today.hiddenSections"

    /// Encode an ordered section list into the stored comma-joined string.
    static func encode(_ sections: [TodaySection]) -> String {
        sections.map(\.rawValue).joined(separator: ",")
    }

    /// Encode the explicit hidden set in stable list order. The editor passes its Hidden-section order;
    /// rendering treats the decoded value as a set.
    static func encodeHidden(_ sections: [TodaySection]) -> String {
        sections.map(\.rawValue).joined(separator: ",")
    }

    /// Decode the stored string into the FULL ordered section list. An empty/unset string yields the
    /// default order. Unknown tokens are ignored, duplicates collapsed, and any known section missing from
    /// the saved order is INSERTED at its default-order position relative to the saved sections (before the
    /// first saved section that follows it in the default order; appended when none does) — so every
    /// section always renders, and one added in a later app version surfaces where users expect it instead
    /// of teleporting to the bottom of an existing saved order. Twin of the Kotlin `decodeOrder`.
    static func decodeOrder(_ raw: String) -> [TodaySection] {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return TodaySection.defaultOrder }
        var saved: [TodaySection] = []
        for token in trimmed.split(separator: ",") {
            if let s = TodaySection(rawValue: token.trimmingCharacters(in: .whitespaces)), !saved.contains(s) {
                saved.append(s)
            }
        }
        guard !saved.isEmpty else { return TodaySection.defaultOrder }
        // Iterate allCases (not defaultOrder) so a future case accidentally left out of defaultOrder can
        // never be silently hidden; a section without a default index sorts after everything (no crash —
        // the Kotlin twin's indexOf(-1) degrades the same way). defaultOrder covering allCases is pinned
        // by TodayLayoutPrefsTests on both platforms.
        func defIdx(_ s: TodaySection) -> Int {
            TodaySection.defaultOrder.firstIndex(of: s) ?? TodaySection.defaultOrder.count
        }
        for missing in TodaySection.allCases where !saved.contains(missing) {
            let insertAt = saved.firstIndex { defIdx($0) > defIdx(missing) }
            if let insertAt { saved.insert(missing, at: insertAt) } else { saved.append(missing) }
        }
        return saved
    }

    /// Decode explicitly hidden sections. Empty/unset means nothing is hidden. Unknown tokens are ignored
    /// and duplicates collapsed; unlike `decodeOrder`, missing cases are NOT inserted because absence here
    /// means visible (including a section introduced by a future app version).
    static func decodeHidden(_ raw: String) -> [TodaySection] {
        var seen = Set<TodaySection>()
        var hidden: [TodaySection] = []
        for token in raw.split(separator: ",") {
            if let section = TodaySection(rawValue: token.trimmingCharacters(in: .whitespaces)),
               seen.insert(section).inserted {
                hidden.append(section)
            }
        }
        return hidden
    }

    /// The sections Today should render, preserving the full saved order while filtering only the user's
    /// explicit hidden set. At least one visible section is enforced by the editor, not the decoder.
    static func visibleOrder(orderRaw: String, hiddenRaw: String) -> [TodaySection] {
        let hidden = Set(decodeHidden(hiddenRaw))
        return decodeOrder(orderRaw).filter { !hidden.contains($0) }
    }
}

// MARK: - Liquid Today, layout v2 (personal fork)
//
// The redesigned Liquid Today draws Heart Rate then Synthesis directly under the hero and no longer draws
// the Recovery Vitals card (its three numbers moved into the hero). The stored order keeps its wire format
// and every section token, so Android and the classic Today read it unchanged: the removed section is
// filtered at display, and the move is applied to the saved order once.

extension TodayLayoutPrefs {
    /// Set once the saved order has been moved to the v2 layout, so a later rearrangement is never undone.
    static let liquidLayoutV2Key = "today.liquidLayoutV2"

    /// Sections the Liquid Today no longer draws in the saved order. Kept in the enum and in the stored
    /// order for parity. Start session and Last workouts left the page in chantier 9: they come back
    /// through `TodayRestoredBlock`, under the Metrics, rather than at a place in the order.
    static let liquidRemovedSections: Set<TodaySection> = [.recoveryVitals, .liveSession, .workouts]

    /// `raw` with Heart Rate then Synthesis moved directly under the hero, every other section keeping its
    /// relative place (an empty order starts from the default one).
    static func liquidV2Order(_ raw: String) -> String {
        var order = decodeOrder(raw)
        order.removeAll { $0 == .heartRate || $0 == .synthesis }
        let at = order.firstIndex(of: .hero).map { $0 + 1 } ?? 0
        order.insert(contentsOf: [.heartRate, .synthesis], at: at)
        return encode(order)
    }

    /// What the Liquid Today renders: the saved visible order without the sections it no longer draws.
    static func liquidVisibleOrder(orderRaw: String, hiddenRaw: String) -> [TodaySection] {
        visibleOrder(orderRaw: orderRaw, hiddenRaw: hiddenRaw).filter { !liquidRemovedSections.contains($0) }
    }
}

// MARK: - Liquid Today, layout v3 (personal fork, chantier 9)
//
// The page reads rings → Synthesis → heart rate → stress → Metrics. The move is applied to the saved order
// once, like v2; a later rearrangement is the wearer's own and is never undone.

extension TodayLayoutPrefs {
    /// Set once the saved order has been moved to the v3 layout.
    static let liquidLayoutV3Key = "today.liquidLayoutV3"

    /// The head of the v3 page, in this order.
    static let liquidV3Head: [TodaySection] = [.hero, .synthesis, .heartRate, .stress, .keyMetrics]

    /// `raw` with the v3 head first, every other section keeping its relative place after it.
    static func liquidV3Order(_ raw: String) -> String {
        let rest = decodeOrder(raw).filter { !liquidV3Head.contains($0) }
        return encode(liquidV3Head + rest)
    }
}

/// The blocks that left the Liquid Today in chantier 9, each still at its new home, and which the wearer
/// can put back under the Metrics from « Customize Today ». Off by default. iPhone display preference only:
/// stored on the device under `storageKey`, outside the `.noopbak` whitelist, with no Android twin.
enum TodayRestoredBlock: String, CaseIterable, Identifiable {
    case fitnessAge
    case vitality
    case liveSession
    case workouts
    case dataSources
    case emptyTiles

    var id: String { rawValue }

    /// UserDefaults key: a comma-joined list of the blocks switched back on.
    static let storageKey = "today.restoredBlocks"

    var title: String {
        switch self {
        case .fitnessAge:  return String(localized: "Fitness Age")
        case .vitality:    return String(localized: "Vitality")
        case .liveSession: return String(localized: "Start session")
        case .workouts:    return String(localized: "Last workouts")
        case .dataSources: return String(localized: "Data sources")
        case .emptyTiles:  return String(localized: "Tiles without a value")
        }
    }

    /// Where the block lives now.
    var home: String {
        switch self {
        case .fitnessAge, .vitality: return String(localized: "More → Health and recovery")
        case .liveSession:           return String(localized: "Training → Other activities")
        case .workouts:              return String(localized: "Training")
        case .dataSources:           return String(localized: "More → Data")
        case .emptyTiles:            return String(localized: "Metrics → All")
        }
    }

    /// Decode the stored list. Unknown tokens are dropped, duplicates collapsed; empty means all off.
    static func decode(_ raw: String) -> Set<TodayRestoredBlock> {
        Set(raw.split(separator: ",").compactMap {
            TodayRestoredBlock(rawValue: $0.trimmingCharacters(in: .whitespaces))
        })
    }

    /// Encode in the stable `allCases` order.
    static func encode(_ blocks: Set<TodayRestoredBlock>) -> String {
        allCases.filter { blocks.contains($0) }.map(\.rawValue).joined(separator: ",")
    }
}

/// The Key-Metrics tiles and Your-Cards cards the Liquid Today hides (personal fork): the hero shows the
/// same number, or (chantier 9) the card has its own place — the stress card replaces the Stress row, and
/// Fitness Age and Vitality come back only through `TodayRestoredBlock`. Hidden at display and in its
/// editors only: the stored selections are untouched, so Android and the classic Today keep them.
enum LiquidTodayDuplicates {
    static let keyMetrics: Set<KeyMetric> = [.charge, .effort, .rest, .hrv, .restingHr, .calories]
    static let cards: Set<DashboardCard> = [.hrv, .restingHr, .calories, .stress, .fitnessAge, .vitality]
}
