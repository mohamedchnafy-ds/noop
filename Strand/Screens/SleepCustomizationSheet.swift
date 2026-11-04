import SwiftUI
import StrandDesign

// MARK: - Sleep card customization (#sleep-layout)

/// The Sleep tab's "Arrange" sheet — reorder / show-hide the analytical cards. A single-page twin of
/// `TodayCustomizationSheet` (Sleep has no nested editors), driven by the SAME generic `EditableLayoutList`
/// so the reorder/hide UX is byte-for-byte Today's. Persists via `SleepLayoutPrefs`; the render side
/// (`SleepView`) reads the same `@AppStorage` keys and re-lays-out on save.
///
/// Fork chantier 9: under the lists, « Put back on the page » (one switch per `SleepRestoredBlock`, off by
/// default) and the « Add a nap » action, which left the page with « Tonight ».
struct SleepCustomizationSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let initialDraft: EditableLayoutDraft<SleepSection>

    @Binding private var sectionOrderRaw: String
    @Binding private var hiddenSectionsRaw: String
    @Binding private var restoredBlocksRaw: String
    private let initialRestored: Set<SleepRestoredBlock>
    /// Saves, closes the sheet and asks the Sleep tab to open the nap editor once it is gone; nil hides it.
    private let onAddNap: (() -> Void)?

    @State private var draft: EditableLayoutDraft<SleepSection>
    @State private var restored: Set<SleepRestoredBlock>
    /// The folded sections that were hidden when the sheet opened, so saving keeps them hidden.
    private let foldedHidden: [SleepSection]

    /// The sections the iPhone page no longer draws from the order are not offered here. Their stored
    /// slot and hidden flag are kept as they were.
    static let foldedSections: Set<SleepSection> = SleepLayoutPrefs.pageFoldedSections

    private var isDirty: Bool { draft != initialDraft || restored != initialRestored }

    init(sectionOrderRaw: Binding<String>, hiddenSectionsRaw: Binding<String>,
         restoredBlocksRaw: Binding<String>, onAddNap: (() -> Void)? = nil) {
        _sectionOrderRaw = sectionOrderRaw
        _hiddenSectionsRaw = hiddenSectionsRaw
        _restoredBlocksRaw = restoredBlocksRaw
        self.onAddNap = onAddNap
        let restoredNow = SleepRestoredBlock.decodeRestored(restoredBlocksRaw.wrappedValue)
        initialRestored = restoredNow
        _restored = State(initialValue: restoredNow)

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
                    restored = []
                },
                bottom: AnyView(SleepRestoredBlocksSection(restored: $restored, onAddNap: addNapAction))
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

    /// « Add a nap »: keep what was changed here, close, then let the Sleep tab open the nap editor.
    private var addNapAction: (() -> Void)? {
        guard let onAddNap else { return nil }
        return {
            save()
            onAddNap()
        }
    }

    private func save() {
        // Store the FULL order (shown ++ hidden, so a hidden card keeps a stable slot) + the hidden set,
        // matching SleepLayoutPrefs and the Android SleepArrangeSheet. Folded sections keep their slot.
        let folded = SleepLayoutPrefs.decodeOrder(sectionOrderRaw).filter { Self.foldedSections.contains($0) }
        sectionOrderRaw = SleepLayoutPrefs.encode(draft.visible + draft.hidden + folded)
        hiddenSectionsRaw = SleepLayoutPrefs.encodeHidden(draft.hidden + foldedHidden)
        restoredBlocksRaw = SleepRestoredBlock.encodeRestored(restored)
        dismiss()
    }
}

/// « Put back on the page » (fork chantier 9): one switch per block that left the Sleep page, off by
/// default, then the « Add a nap » action.
private struct SleepRestoredBlocksSection: View {
    @Binding var restored: Set<SleepRestoredBlock>
    let onAddNap: (() -> Void)?

    var body: some View {
        Section {
            ForEach(SleepRestoredBlock.allCases) { block in
                Toggle(isOn: Binding(
                    get: { restored.contains(block) },
                    set: { on in
                        if on { restored.insert(block) } else { restored.remove(block) }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(block.title)
                            .font(StrandFont.body)
                            .foregroundStyle(StrandPalette.textPrimary)
                        Text(block.detail)
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                }
                .tint(StrandPalette.switchOn)
            }
        } header: {
            Text("Put back on the page")
                .strandOverline()
        } footer: {
            Text("Off by default. Switched on, the block appears under Your nights.")
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textTertiary)
        }
        if let onAddNap {
            Section {
                Button(action: onAddNap) {
                    Label("Add a nap", systemImage: "plus.circle")
                        .font(StrandFont.body)
                        .foregroundStyle(StrandPalette.accent)
                }
            } footer: {
                Text("Saves your changes, then opens the nap editor.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
        }
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
