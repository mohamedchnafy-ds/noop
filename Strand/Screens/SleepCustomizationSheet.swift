import SwiftUI
import StrandDesign

// MARK: - Sleep card customization (#sleep-layout)

/// The Sleep tab's "Arrange" sheet — reorder / show-hide the analytical cards. A single-page twin of
/// `TodayCustomizationSheet` (Sleep has no nested editors), driven by the SAME generic `EditableLayoutList`
/// so the reorder/hide UX is byte-for-byte Today's. Persists via `SleepLayoutPrefs`; the render side
/// (`SleepView`) reads the same `@AppStorage` keys and re-lays-out on save.
struct SleepCustomizationSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let initialDraft: EditableLayoutDraft<SleepSection>

    @Binding private var sectionOrderRaw: String
    @Binding private var hiddenSectionsRaw: String

    @State private var draft: EditableLayoutDraft<SleepSection>
    /// The folded sections that were hidden when the sheet opened, so saving keeps them hidden.
    private let foldedHidden: [SleepSection]

    /// Personal fork: on the Sleep tab the 30-day hours trend is the "30 days" view of the debt card, so
    /// its own card is not offered here. Its stored slot and hidden flag are kept as they were.
    static let foldedSections: Set<SleepSection> = [.asleepDuration]

    private var isDirty: Bool { draft != initialDraft }

    init(sectionOrderRaw: Binding<String>, hiddenSectionsRaw: Binding<String>) {
        _sectionOrderRaw = sectionOrderRaw
        _hiddenSectionsRaw = hiddenSectionsRaw

        let fullOrder = SleepLayoutPrefs.decodeOrder(sectionOrderRaw.wrappedValue)
            .filter { !Self.foldedSections.contains($0) }
        let storedHidden = SleepLayoutPrefs.decodeHidden(hiddenSectionsRaw.wrappedValue)
        let hiddenSet = Set(storedHidden)
        foldedHidden = storedHidden.filter { Self.foldedSections.contains($0) }
        let d = EditableLayoutDraft(
            visible: fullOrder.filter { !hiddenSet.contains($0) },
            hidden: fullOrder.filter { hiddenSet.contains($0) }
        )
        initialDraft = d
        _draft = State(initialValue: d)
    }

    var body: some View {
        NavigationStack {
            EditableLayoutList(
                draft: $draft,
                shownTitle: String(localized: "Shown"),
                hiddenTitle: String(localized: "Hidden"),
                title: \.title,
                subtitle: { _ in nil },
                icon: \.customizationIcon,
                tint: \.customizationTint,
                configurationLabel: { _ in nil },
                onConfigure: { _ in },
                onReset: {
                    let offered = SleepSection.defaultOrder.filter { !Self.foldedSections.contains($0) }
                    draft = EditableLayoutDraft(visible: offered, allItems: offered)
                }
            ) {
                EmptyView()
            }
            .navigationTitle("Customize Sleep")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
        }
        .interactiveDismissDisabled(isDirty)
        .tint(StrandPalette.accent)
        #if os(macOS)
        .frame(
            minWidth: NoopMetrics.editorSheetMinWidth,
            minHeight: NoopMetrics.editorSheetMinHeight
        )
        #endif
    }

    private func save() {
        // Store the FULL order (shown ++ hidden, so a hidden card keeps a stable slot) + the hidden set,
        // matching SleepLayoutPrefs and the Android SleepArrangeSheet.
        let folded = SleepSection.defaultOrder.filter { Self.foldedSections.contains($0) }
        sectionOrderRaw = SleepLayoutPrefs.encode(draft.visible + draft.hidden + folded)
        hiddenSectionsRaw = SleepLayoutPrefs.encodeHidden(draft.hidden + foldedHidden)
        dismiss()
    }
}

// MARK: - Per-card Arrange-sheet metadata (icon + tint), mirroring TodaySection's

extension SleepSection {
    /// SF Symbol shown beside the card's name in the Arrange sheet.
    var customizationIcon: String {
        switch self {
        case .sleepMarks:      return "bed.double"
        case .stages:          return "chart.bar.xaxis"
        case .bodyClock:       return "clock.badge.checkmark"
        case .nightDetail:     return "square.grid.2x2"
        case .sleepDebt:       return "arrow.down.right.circle"
        case .stagesVsTypical: return "chart.bar"
        case .asleepDuration:  return "clock"
        }
    }

    /// Tint for the card's Arrange-sheet icon. Sleep cards live in the Rest world, so they lean on the
    /// rest palette with the accent for the log/marks entry.
    var customizationTint: Color {
        switch self {
        case .sleepMarks:      return StrandPalette.accent
        case .stages:          return StrandPalette.restColor
        case .bodyClock:       return StrandPalette.restColor
        case .nightDetail:     return StrandPalette.restBright
        case .sleepDebt:       return StrandPalette.effortColor
        case .stagesVsTypical: return StrandPalette.restColor
        case .asleepDuration:  return StrandPalette.restBright
        }
    }
}
