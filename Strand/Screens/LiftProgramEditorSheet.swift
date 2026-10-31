import SwiftUI
import StrandDesign
import WhoopStore

// Build or edit a program: a name and an ordered list of exercise lines carrying the TARGETS —
// working sets, reps, weight, rest and the user's own technique note.
//
// Lines are edited as local drafts and written in one go on Save, through
// `replaceLiftProgramItems`, which swaps the whole list transactionally. Editing a program never
// rewrites history: a session snapshots the program's NAME when it runs, so renaming "Upper A" or
// deleting it entirely leaves every past session reading exactly as it did.

struct LiftProgramEditorSheet: View {
    /// The program being edited, or nil to create a new one.
    let program: LiftProgramRow?
    /// Called after a successful save or delete, so the caller can reload.
    let onSaved: () async -> Void

    @EnvironmentObject var repo: Repository
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var note: String = ""
    /// The exercise lines, in display order. `ord` is assigned from the array index on save, so
    /// reordering is just moving an element.
    @State private var items: [LiftProgramItemRow] = []
    @State private var loaded = false
    @State private var saving = false

    /// The line being added or edited (nil = that sheet is closed).
    @State private var editingItem: ItemEditTarget?
    @State private var confirmingDelete = false

    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    private var unitSystem: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }

    @FocusState private var focused: Field?
    private enum Field: Hashable { case name, note }

    private var isNew: Bool { program == nil }
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !saving
    }

    var body: some View {
        ScreenScaffold(
            title: isNew ? "New program" : "Edit program",
            subtitle: "Your targets for each exercise. What you actually lift is recorded when you run it."
        ) {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                detailsSection
                exercisesSection
                if !isNew { deleteSection }
                footer
            }
        }
        #if os(iOS)
        .presentationDragIndicator(.visible)
        #else
        // A fixed frame, for the reason the other editor sheets document: a macOS sheet hosting a
        // ScrollView needs a definite height or every row collapses to the top.
        .frame(width: 520, height: 720)
        #endif
        .background(StrandPalette.surfaceBase)
        .keyboardDoneToolbar($focused)
        .dismissesKeyboardOnTap($focused)
        .task { await loadIfNeeded() }
        .sheet(item: $editingItem) { target in
            LiftProgramItemSheet(item: target.item) { saved in
                apply(saved, replacing: target.item)
            }
        }
    }

    // MARK: - Name + note

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            SectionHeader("Program", overline: "Details")
            NoopCard {
                VStack(alignment: .leading, spacing: 14) {
                    field("Name") {
                        TextField("Upper A", text: $name)
                            .textFieldStyle(.plain)
                            .font(StrandFont.body)
                            .foregroundStyle(StrandPalette.textPrimary)
                            .focused($focused, equals: .name)
                    }
                    field("Note (optional)") {
                        TextField("Anything you want to remember", text: $note)
                            // Capped at what the hub can actually show (two caption lines). A field
                            // that silently discards the end is worse than one that stops.
                            .onChange(of: note) { new in
                                if new.count > WhoopStore.maxProgramNoteLength {
                                    note = String(new.prefix(WhoopStore.maxProgramNoteLength))
                                }
                            }
                            .textFieldStyle(.plain)
                            .font(StrandFont.body)
                            .foregroundStyle(StrandPalette.textPrimary)
                            .focused($focused, equals: .note)
                    }
                }
            }
        }
    }

    // MARK: - Exercise lines

    private var exercisesSection: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            SectionHeader("Exercises", overline: "In order")

            if items.isEmpty {
                NoopCard {
                    Text("No exercises yet. Add the first one below — you can type any name you like; NOOP remembers it for next time.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    itemRow(item, index: index)
                    if index < items.count - 1 { supersetLink(after: index) }
                }
            }

            Button {
                editingItem = ItemEditTarget(id: "new", item: nil)
            } label: {
                Label("Add exercise", systemImage: "plus")
            }
            .buttonStyle(NoopButtonStyle(.secondary))
        }
    }

    private func itemRow(_ item: LiftProgramItemRow, index: Int) -> some View {
        NoopCard {
            HStack(alignment: .top, spacing: NoopMetrics.gap) {
                Button {
                    editingItem = ItemEditTarget(id: item.id, item: item)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        if let tag = LiftSuperset.tag(of: index, in: labels) {
                            Text(String(localized: "Superset \(tag)"))
                                .strandOverline()
                                .foregroundStyle(StrandPalette.effortColor)
                        }
                        Text(item.exercise)
                            .font(StrandFont.headline)
                            .foregroundStyle(StrandPalette.textPrimary)
                        Text(targetSummary(item, index: index))
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textSecondary)
                        if let note = item.note, !note.isEmpty {
                            Text(note)
                                .font(StrandFont.caption)
                                .foregroundStyle(StrandPalette.textTertiary)
                                .lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                VStack(spacing: NoopMetrics.rowSpacing) {
                    Button {
                        move(from: index, by: -1)
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .disabled(index == 0)
                    .accessibilityLabel("Move up")

                    Button {
                        move(from: index, by: 1)
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .disabled(index == items.count - 1)
                    .accessibilityLabel("Move down")

                    Button(role: .destructive) {
                        items.removeAll { $0.id == item.id }
                        relabel()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("Remove exercise")
                }
                .font(.system(size: 12, weight: .semibold))
                .buttonStyle(.plain)
                .foregroundStyle(StrandPalette.textSecondary)
            }
        }
    }

    // MARK: - Supersets

    /// Every line's superset label, in display order — what `LiftSuperset` groups.
    private var labels: [String?] { items.map(\.supersetGroup) }

    /// Whether the line at `index` and the one after it are in the same superset.
    private func isLinked(_ index: Int) -> Bool {
        guard items.indices.contains(index + 1) else { return false }
        return LiftSuperset.group(of: index, in: labels)?.contains(index + 1) == true
    }

    /// The link between two consecutive lines: one tap puts them in the same superset, another splits
    /// it there. Sitting BETWEEN the two cards, because a superset is a relation between neighbours.
    private func supersetLink(after index: Int) -> some View {
        let linked = isLinked(index)
        return Button {
            toggleLink(after: index)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: linked ? "link.circle.fill" : "link")
                    .font(.system(size: 13, weight: .semibold))
                Text(linked ? String(localized: "Superset · tap to unlink")
                            : String(localized: "Link as superset"))
                    .font(StrandFont.caption)
            }
            .foregroundStyle(linked ? StrandPalette.effortColor : StrandPalette.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(linked
                            ? String(localized: "Unlink \(items[index].exercise) and \(items[index + 1].exercise)")
                            : String(localized: "Link \(items[index].exercise) and \(items[index + 1].exercise) as a superset"))
    }

    /// Link the line at `index` to the next one, or split their superset there.
    ///
    /// Linking joins whatever groups the two lines are already in. Unlinking gives the lines after the
    /// split a group of their own, so A1-A2-A3 split after A1 leaves A2-A3 together. Labels are then
    /// rewritten A, B, C… in order (`LiftSuperset.relabeled`), and a line left alone loses its label.
    private func toggleLink(after index: Int) {
        guard items.indices.contains(index + 1) else { return }
        var raw = labels
        if isLinked(index) {
            let fresh = "~split"
            var i = index + 1
            let old = raw[i]
            while i < raw.count, raw[i] == old { raw[i] = fresh; i += 1 }
        } else {
            let joined = raw[index] ?? raw[index + 1] ?? "~new"
            // The whole run each side belongs to joins, not just the two lines touching.
            let left = raw[index], right = raw[index + 1]
            var i = index
            while i >= 0, raw[i] == left, left != nil || i == index { raw[i] = joined; i -= 1 }
            i = index + 1
            while i < raw.count, raw[i] == right, right != nil || i == index + 1 { raw[i] = joined; i += 1 }
        }
        apply(labels: LiftSuperset.relabeled(raw))
    }

    /// Re-letter the supersets after the list changed shape, so the badges always read A, B, C…
    private func relabel() {
        apply(labels: LiftSuperset.relabeled(labels))
    }

    private func apply(labels new: [String?]) {
        for i in items.indices where items[i].supersetGroup != new[i] {
            items[i].supersetGroup = new[i]
        }
    }

    /// "4 × 8 · 60 kg · 2:00 rest" — only the parts that were actually filled in.
    ///
    /// In a superset only the LAST line's rest is used, after the round; the others say so instead of
    /// showing a rest the session will not run.
    private func targetSummary(_ item: LiftProgramItemRow, index: Int) -> String {
        var parts: [String] = []
        if let sets = item.targetSets {
            if let reps = item.targetRepsLow {
                parts.append("\(sets) × \(reps)")
            } else {
                parts.append(String(localized: "\(sets) sets"))
            }
        }
        if let kg = item.targetWeightKg {
            parts.append(LiftFormat.weight(kg, system: unitSystem))
        }
        if let rpe = item.targetRpe {
            parts.append(String(localized: "max RPE \(LiftFormat.trim(rpe))"))
        }
        if let group = LiftSuperset.group(of: index, in: labels) {
            if index == group.upperBound - 1 {
                let rest = item.restSec ?? LiftPlanItem.defaultRestSec
                parts.append(String(localized: "\(LiftFormat.duration(rest)) rest after the superset"))
            } else {
                parts.append(String(localized: "no rest, then the next exercise"))
            }
        } else if let rest = item.restSec {
            parts.append(String(localized: "\(LiftFormat.duration(rest)) rest"))
        }
        return parts.isEmpty ? String(localized: "No targets set") : parts.joined(separator: " · ")
    }

    // MARK: - Delete

    private var deleteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(role: .destructive) {
                confirmingDelete = true
            } label: {
                Label("Delete program", systemImage: "trash")
            }
            .buttonStyle(NoopButtonStyle(.secondary))
            .confirmationDialog("Delete this program?",
                                isPresented: $confirmingDelete,
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) { Task { await deleteProgram() } }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Sessions you already logged from it are kept.")
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .buttonStyle(.plain)
                .font(StrandFont.body)
                .foregroundStyle(StrandPalette.textSecondary)
            Spacer()
            Button("Save") { Task { await save() } }
                .buttonStyle(.noopPrimary)
                .frame(maxWidth: 160)
                .disabled(!canSave)
                .opacity(canSave ? 1 : NoopButtonMetrics.disabledOpacity)
                .accessibilityLabel("Save program")
        }
    }

    // MARK: - Helpers

    private func field<Content: View>(_ label: LocalizedStringKey,
                                      @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).strandOverline()
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func move(from index: Int, by offset: Int) {
        let target = index + offset
        guard items.indices.contains(index), items.indices.contains(target) else { return }
        items.swapAt(index, target)
        relabel()
    }

    /// Insert a new line, or replace an edited one in place so its position is kept.
    private func apply(_ saved: LiftProgramItemRow, replacing old: LiftProgramItemRow?) {
        guard let old, let index = items.firstIndex(where: { $0.id == old.id }) else {
            items.append(saved)
            return
        }
        items[index] = saved
    }

    // MARK: - Load / save

    private func loadIfNeeded() async {
        guard !loaded else { return }
        loaded = true
        guard let program else { return }
        name = program.name
        note = program.note ?? ""
        guard let store = await repo.storeHandle() else { return }
        items = (try? await store.liftProgramItems(programId: program.id)) ?? []
    }

    private func save() async {
        guard canSave, let store = await repo.storeHandle() else { return }
        saving = true
        defer { saving = false }

        let now = Int(Date().timeIntervalSince1970)
        let id = program?.id ?? UUID().uuidString
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

        let row = LiftProgramRow(
            id: id,
            deviceId: repo.deviceId,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            note: trimmedNote.isEmpty ? nil : trimmedNote,
            createdAt: program?.createdAt ?? now,
            updatedAt: now,
            archived: program?.archived ?? false
        )
        _ = try? await store.upsertLiftPrograms([row])

        // `ord` is the array index: reordering the list is all it takes to reorder the program.
        let canonical = LiftSuperset.relabeled(labels)
        let ordered = items.enumerated().map { index, item in
            LiftProgramItemRow(
                id: item.id,
                deviceId: repo.deviceId,
                programId: id,
                ord: index,
                exercise: item.exercise,
                targetSets: item.targetSets,
                targetRepsLow: item.targetRepsLow,
                targetRepsHigh: item.targetRepsHigh,
                targetRpe: item.targetRpe,
                targetWeightKg: item.targetWeightKg,
                restSec: item.restSec,
                note: item.note,
                supersetGroup: canonical[index]
            )
        }
        _ = try? await store.replaceLiftProgramItems(programId: id, items: ordered)

        await onSaved()
        dismiss()
    }

    private func deleteProgram() async {
        guard let program, let store = await repo.storeHandle() else { return }
        _ = try? await store.deleteLiftProgram(id: program.id)
        await onSaved()
        dismiss()
    }
}

/// What the line editor is editing — a wrapper so "new line" has an identity to present on.
private struct ItemEditTarget: Identifiable {
    let id: String
    let item: LiftProgramItemRow?
}
