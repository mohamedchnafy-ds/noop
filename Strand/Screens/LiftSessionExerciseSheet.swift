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
                exerciseSection
                LiftMusclePicker(primary: $primary, secondaries: $secondaries)
                Group {
                    switch destination {
                    case .session:
                        Text("It joins this session with one set, its weight and reps at 0 until you type what you lift. Finishing asks whether the program keeps it.")
                    case .today:
                        Text("For today only: it joins today's session with as many sets as last time, at last time's numbers. The program does not change; finishing the session asks whether it keeps it.")
                    }
                }
                .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                footer
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
                                Button { adopt(row) } label: { LiftExerciseSuggestionLabel(row: row) }
                                    .buttonStyle(.plain)
                            }
                        }
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
