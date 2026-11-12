import SwiftUI
import StrandDesign
import WhoopStore

// Add an exercise to the running session (Utku, 21 Sep 2026): one done before, picked from the user's own
// exercise names, or a new one, typed and given its muscles — and remembered, like a name typed into the
// program editor. It joins the session at the end of the sheet as one set planned at 0 kg × 0 reps; ⊕/⊖
// change its sets like any other line, and finishing asks whether the program keeps it. Sets, rest and
// max RPE are not asked here: they belong to the program editor, later.

struct LiftSessionExerciseSheet: View {
    /// Where the exercise goes (fork chantier 18): the running session, or today's program from the
    /// Training screen's day card. The same sheet either way; only its note and button say which.
    enum Destination { case session, today }

    var destination: Destination = .session
    /// Handed the exercise once it is remembered; the session (or today's list) adds it.
    let onAdd: (_ name: String, _ primary: LiftMuscle?, _ secondaries: [LiftMuscle]) -> Void
    /// Fork chantier 18 (today only): « Superset » ticks 2 or 3 exercises done before, handed over at once
    /// in the order of the round.
    var onAddSuperset: (_ exercises: [LiftExerciseRow]) -> Void = { _ in }

    @EnvironmentObject var repo: Repository
    @Environment(\.dismiss) private var dismiss

    @State private var exercise = ""
    @State private var primary: LiftMuscle?
    @State private var secondaries: Set<LiftMuscle> = []
    /// The user's own exercise names, most recently used first.
    @State private var vocabulary: [LiftExerciseRow] = []
    /// Set when the vocabulary is full, so the refusal is explained rather than silent.
    @State private var vocabularyFullLimit: Int?
    @State private var adding = false
    /// Fork chantier 18: the exercises done before, narrowed to one primary muscle; nil shows them all.
    @State private var muscleFilter: LiftMuscle?
    /// Fork chantier 18: « One exercise | Superset » (today only), and the exercises ticked for the superset.
    @State private var supersetMode = false
    @State private var picks: [LiftExerciseRow] = []

    @FocusState private var focused: Field?
    private enum Field: Hashable { case exercise }

    private var trimmedExercise: String {
        exercise.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var canAdd: Bool { !trimmedExercise.isEmpty && !adding }

    var body: some View {
        ScreenScaffold(title: "Add exercise",
                       subtitle: "Pick one you have done before, or type a new name.") {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                if destination == .today {
                    SegmentedPillControl([false, true], selection: $supersetMode, fillsAvailableWidth: true) {
                        $0 ? String(localized: "Superset") : String(localized: "One exercise")
                    }
                }
                exerciseSection
                if !supersetMode {
                    LiftMusclePicker(primary: $primary, secondaries: $secondaries)
                }
                Group {
                    if supersetMode {
                        Text("For today only: tick 2 or 3 exercises in the order of the round. They join today's session linked, as one block, after the program, with 1:30 of rest after the round. The program does not change; finishing the session asks whether it keeps them.")
                    } else {
                        switch destination {
                        case .session:
                            Text("It joins this session with one set, its weight and reps at 0 until you type what you lift. Finishing asks whether the program keeps it.")
                        case .today:
                            Text("For today only: it joins today's session with as many sets as last time, at last time's numbers. The program does not change; finishing the session asks whether it keeps it.")
                        }
                    }
                }
                .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                if supersetMode { supersetFooter } else { footer }
            }
        }
        #if os(iOS)
        .presentationDragIndicator(.visible)
        #else
        .frame(width: 520, height: 640)
        #endif
        .background(StrandPalette.surfaceBase)
        .keyboardDoneToolbar($focused)
        .dismissesKeyboardOnTap($focused)
        .task { await load() }
        // A name typed out in full that is already known brings its muscles with it, as picking it from
        // the list does — unless muscles were already chosen here.
        .onChange(of: exercise) { _ in
            guard primary == nil, secondaries.isEmpty,
                  let known = vocabulary.first(where: { $0.name == trimmedExercise }) else { return }
            primary = known.primaryMuscle
            secondaries = Set(known.secondaryMuscles)
        }
        .alert("You've saved the most exercises NOOP remembers",
               isPresented: Binding(get: { vocabularyFullLimit != nil },
                                    set: { if !$0 { vocabularyFullLimit = nil } })) {
            Button("OK", role: .cancel) { vocabularyFullLimit = nil }
        } message: {
            Text("Forget one you no longer use and this one will save. Your logged sessions are never affected.")
        }
    }

    private var exerciseSection: some View {
        let narrowed = muscleFilter.map { muscle in vocabulary.filter { $0.primaryMuscle == muscle } } ?? vocabulary
        let suggestions = LiftExerciseVocabulary.suggestions(narrowed, matching: exercise,
                                                             limit: muscleFilter == nil ? 8 : 20)
        return VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            SectionHeader("Exercise", overline: "Movement")
            NoopCard {
                VStack(alignment: .leading, spacing: NoopMetrics.gap) {
                    TextField("Incline dumbbell press", text: $exercise)
                        .textFieldStyle(.plain)
                        .font(StrandFont.body)
                        .foregroundStyle(StrandPalette.textPrimary)
                        .focused($focused, equals: .exercise)
                    muscleChips
                    if !suggestions.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Used before").strandOverline()
                            ForEach(suggestions, id: \.id) { row in
                                if supersetMode {
                                    Button { togglePick(row) } label: { pickLabel(row) }
                                        .buttonStyle(.plain)
                                } else {
                                    Button { adopt(row) } label: { LiftExerciseSuggestionLabel(row: row) }
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                    } else if supersetMode {
                        Text("A superset takes exercises you have done before: add a new one on its own first.")
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// The primary muscles of the exercises done before, as chips: one tap narrows the list to it, a
    /// second shows them all again (fork chantier 18).
    @ViewBuilder
    private var muscleChips: some View {
        let muscles = LiftMuscle.allCases.filter { muscle in vocabulary.contains { $0.primaryMuscle == muscle } }
        if muscles.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: NoopMetrics.space2) {
                    ForEach(muscles, id: \.self) { muscle in
                        let on = muscleFilter == muscle
                        Button { muscleFilter = on ? nil : muscle } label: {
                            Text(verbatim: muscle.displayName)
                                .font(StrandFont.caption.weight(.semibold))
                                .foregroundStyle(on ? StrandPalette.surfaceBase : StrandPalette.textPrimary)
                                .padding(.horizontal, NoopMetrics.space3)
                                .frame(minHeight: 32)
                                .background(on ? StrandPalette.textPrimary : StrandPalette.surfaceInset, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .buttonStyle(.plain)
                .font(StrandFont.body)
                .foregroundStyle(StrandPalette.textSecondary)
            Spacer()
            Button { Task { await add() } } label: {
                if destination == .today { Text("Add for today") } else { Text("Add to session") }
            }
                .buttonStyle(.noopPrimary)
                .frame(maxWidth: 200)
                .disabled(!canAdd)
                .opacity(canAdd ? 1 : NoopButtonMetrics.disabledOpacity)
        }
    }

    /// A suggestion in Superset mode: ticked with its place in the round (A1, A2…), or an empty circle.
    private func pickLabel(_ row: LiftExerciseRow) -> some View {
        let index = picks.firstIndex { $0.id == row.id }
        return HStack(spacing: 10) {
            Image(systemName: index == nil ? "circle" : "checkmark.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(index == nil ? StrandPalette.textTertiary : StrandPalette.accent)
                .accessibilityHidden(true)
            LiftExerciseSuggestionLabel(row: row)
            if let index {
                Text(verbatim: LiftSuperset.letter(0) + String(index + 1))
                    .font(StrandFont.caption.weight(.bold))
                    .foregroundStyle(StrandPalette.accent)
            }
        }
        .contentShape(Rectangle())
        .accessibilityAddTraits(index == nil ? AccessibilityTraits() : .isSelected)
    }

    /// Tick or untick an exercise for the superset; past the cap (3), a tick is ignored.
    private func togglePick(_ row: LiftExerciseRow) {
        if let at = picks.firstIndex(where: { $0.id == row.id }) {
            picks.remove(at: at)
        } else if picks.count < LiftProgramBlocks.maxSupersetPicks {
            picks.append(row)
        }
    }

    /// What is ticked, A1 · A2 …, then Cancel and « Add the superset (n) ».
    private var supersetFooter: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.rowSpacing) {
            Group {
                if picks.isEmpty {
                    Text("No exercise ticked")
                } else {
                    Text(verbatim: picks.enumerated()
                        .map { LiftSuperset.letter(0) + String($0.offset + 1) + " " + $0.element.name }
                        .joined(separator: " · "))
                }
            }
            .font(StrandFont.footnote)
            .foregroundStyle(StrandPalette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.textSecondary)
                Spacer()
                Button {
                    onAddSuperset(picks)
                    dismiss()
                } label: {
                    if picks.count >= 2 {
                        Text(String(localized: "Add the superset (\(picks.count))"))
                    } else {
                        Text("Tick at least 2 exercises")
                    }
                }
                .buttonStyle(.noopPrimary)
                .frame(maxWidth: 240)
                .disabled(picks.count < 2)
                .opacity(picks.count >= 2 ? 1 : NoopButtonMetrics.disabledOpacity)
            }
        }
    }

    /// Take a known exercise, with the muscles it is already known by.
    private func adopt(_ row: LiftExerciseRow) {
        exercise = row.name
        primary = row.primaryMuscle
        secondaries = Set(row.secondaryMuscles)
        focused = nil
    }

    private func load() async {
        guard let store = await repo.storeHandle() else { return }
        vocabulary = (try? await store.liftExercises(deviceId: repo.deviceId)) ?? []
    }

    /// Remember the exercise — a new name is saved to the vocabulary, a known one is marked used — then
    /// hand it to the session.
    private func add() async {
        guard canAdd else { return }
        adding = true
        defer { adding = false }
        let name = trimmedExercise
        let ordered = LiftExerciseVocabulary.ordered(secondaries, excluding: primary)
        if let store = await repo.storeHandle() {
            do {
                try await LiftExerciseVocabulary.remember(name, primary: primary, secondaries: ordered,
                                                          known: vocabulary, deviceId: repo.deviceId,
                                                          in: store)
            } catch let full as WhoopStore.LiftExerciseVocabularyFull {
                vocabularyFullLimit = full.limit
                return
            } catch {
                // Still added: every set the session saves carries its own copy of the name and muscles,
                // so a name the vocabulary could not take this once costs nothing that is logged.
            }
        }
        onAdd(name, primary, ordered)
        dismiss()
    }
}
