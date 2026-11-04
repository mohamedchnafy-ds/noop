import SwiftUI
import StrandDesign

// MARK: - « Customize Training » (personal fork, chantier 9)

/// The Training page's arrange sheet: Progression, Programs and Other activities, reordered by dragging and
/// hidden or shown again — the same `EditableLayoutList` as Today and Sleep, so the gestures are theirs. The
/// week and the day card stay on top and are not offered. At least one block stays shown. Saves to
/// `TrainingLayoutPrefs`; the page reads the same `@AppStorage` keys.
struct TrainingCustomizeSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding private var sectionOrderRaw: String
    @Binding private var hiddenSectionsRaw: String
    private let initialDraft: EditableLayoutDraft<TrainingSection>
    @State private var draft: EditableLayoutDraft<TrainingSection>

    init(sectionOrderRaw: Binding<String>, hiddenSectionsRaw: Binding<String>) {
        _sectionOrderRaw = sectionOrderRaw
        _hiddenSectionsRaw = hiddenSectionsRaw
        let order = TrainingLayoutPrefs.decodeSectionOrder(sectionOrderRaw.wrappedValue)
        let hidden = TrainingLayoutPrefs.decodeHiddenSections(hiddenSectionsRaw.wrappedValue)
        var visible = order.filter { !hidden.contains($0) }
        var hiddenList = order.filter { hidden.contains($0) }
        // Everything hidden (an edited store): the first block comes back, the list needs one.
        if visible.isEmpty, let first = hiddenList.first {
            visible = [first]
            hiddenList.removeFirst()
        }
        let start = EditableLayoutDraft(visible: visible, hidden: hiddenList)
        initialDraft = start
        _draft = State(initialValue: start)
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
                    draft = EditableLayoutDraft(visible: TrainingSection.defaultOrder,
                                                allItems: TrainingSection.defaultOrder)
                }
            ) {
                EmptyView()
            }
            .navigationTitle("Customize Training")
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
        .interactiveDismissDisabled(draft != initialDraft)
        .tint(StrandPalette.accent)
        #if os(macOS)
        .frame(
            minWidth: NoopMetrics.editorSheetMinWidth,
            minHeight: NoopMetrics.editorSheetMinHeight
        )
        #endif
    }

    /// The full order (shown, then hidden, so a hidden block keeps its place) and the hidden set.
    private func save() {
        sectionOrderRaw = TrainingLayoutPrefs.encodeSections(draft.visible + draft.hidden)
        hiddenSectionsRaw = TrainingLayoutPrefs.encodeSections(draft.hidden)
        dismiss()
    }
}

extension TrainingSection {
    /// SF Symbol beside the block's name in the sheet.
    var customizationIcon: String {
        switch self {
        case .progression: return "chart.line.uptrend.xyaxis"
        case .programs: return "list.bullet.rectangle"
        case .otherActivities: return "figure.run"
        }
    }

    /// The icon's tint: Effort blue for the lifting blocks, the activity green for the others.
    var customizationTint: Color {
        switch self {
        case .progression: return StrandPalette.statusPositive
        case .programs: return StrandPalette.effortColor
        case .otherActivities: return StrandPalette.chargeColor
        }
    }
}
