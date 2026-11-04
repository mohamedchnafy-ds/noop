import SwiftUI
import StrandDesign
import WhoopStore

// The program editor's body map (personal fork, chantier 8, lot 5): the Progression silhouette
// (`LiftBodyMap`) reused as a FILTER for adding exercises. A tap on a muscle lists the exercises of the
// user's own vocabulary (`liftExercise`) that work it, direct ones first; "+" opens the line editor with
// that exercise and its muscles filled in. Typing a free name with "Add exercise" stays the main path.
//
// The map colours what the program being edited already works, from the classification the vocabulary
// holds for each line's exercise. It is not a set count: that is Progression's, per week, from what was
// actually logged.

/// What the body map in the program editor reads: a pure function of the vocabulary and the lines.
enum LiftMuscleFilter {

    /// The value handed to `LiftBodyMap` for a muscle a line works directly: it lands in the map's
    /// 4–8 band, the full Effort blue.
    static let directShade: Double = 5
    /// For a muscle a line only works indirectly: the map's "< 2" band, the deep blue at 60 %.
    static let indirectShade: Double = 1

    /// The exercises of the vocabulary that work `muscle`: those it is the primary of, then those that
    /// list it as a secondary, each group in the vocabulary's order (most recently used first).
    static func exercisesWorking(_ muscle: LiftMuscle,
                                 in vocabulary: [LiftExerciseRow]) -> (direct: [LiftExerciseRow], indirect: [LiftExerciseRow]) {
        let direct = vocabulary.filter { $0.primaryMuscle == muscle }
        let indirect = vocabulary.filter { $0.primaryMuscle != muscle && $0.secondaryMuscles.contains(muscle) }
        return (direct, indirect)
    }

    /// What the program's lines work, as the map's shades: a muscle some line works directly reads
    /// `directShade`, one only worked indirectly `indirectShade`; an unclassified exercise claims nothing.
    static func programCoverage(exercises: [String], vocabulary: [LiftExerciseRow]) -> [LiftMuscle: Double] {
        var shades: [LiftMuscle: Double] = [:]
        for name in exercises {
            guard let known = vocabulary.first(where: { $0.name == name }) else { continue }
            for muscle in known.secondaryMuscles where shades[muscle] == nil {
                shades[muscle] = indirectShade
            }
            if let primary = known.primaryMuscle { shades[primary] = directShade }
        }
        return shades
    }
}

/// The "Add by muscle" section of the program editor: front and back views, a legend, and the
/// exercises of the muscle that was touched. Supersets et blocs (4 Nov.): « One exercise | Superset »
/// on top. In Superset mode a row ticks the exercise instead of adding it (A1, A2… in the order of the
/// ticks, kept across muscles), and « Add the superset (n) » hands the ticked exercises over at once.
struct LiftProgramMuscleFilter: View {
    /// The user's exercise vocabulary.
    let vocabulary: [LiftExerciseRow]
    /// The exercise names of the program's lines, in order.
    let programExercises: [String]
    @Binding var selected: LiftMuscle?
    /// Whether the map adds a superset rather than one exercise.
    @Binding var supersetMode: Bool
    /// The exercises ticked for the superset, in the order of the round.
    @Binding var picks: [LiftExerciseRow]
    /// "+" on a known exercise.
    let onAdd: (LiftExerciseRow) -> Void
    /// "New exercise for …": the line editor with this muscle as the primary.
    let onNew: (LiftMuscle) -> Void
    /// « Add the superset »: the ticked exercises, two or more.
    let onAddSuperset: ([LiftExerciseRow]) -> Void

    init(vocabulary: [LiftExerciseRow], programExercises: [String], selected: Binding<LiftMuscle?>,
         supersetMode: Binding<Bool> = .constant(false), picks: Binding<[LiftExerciseRow]> = .constant([]),
         onAdd: @escaping (LiftExerciseRow) -> Void, onNew: @escaping (LiftMuscle) -> Void,
         onAddSuperset: @escaping ([LiftExerciseRow]) -> Void = { _ in }) {
        self.vocabulary = vocabulary
        self.programExercises = programExercises
        _selected = selected
        _supersetMode = supersetMode
        _picks = picks
        self.onAdd = onAdd
        self.onNew = onNew
        self.onAddSuperset = onAddSuperset
    }

    private var coverage: [LiftMuscle: Double] {
        LiftMuscleFilter.programCoverage(exercises: programExercises, vocabulary: vocabulary)
    }

    private var highlightedMuscles: Set<LiftMuscle> {
        guard let selected else { return [] }
        return [selected]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            SectionHeader("Add by muscle")
            NoopCard {
                VStack(alignment: .leading, spacing: NoopMetrics.gap) {
                    SegmentedPillControl([false, true], selection: $supersetMode, fillsAvailableWidth: true) {
                        $0 ? String(localized: "Superset") : String(localized: "One exercise")
                    }
                    Group {
                        if supersetMode {
                            Text("Tap several muscles and tick 2 or 3 exercises in the order of the round: they arrive linked, as one block, at the end of the program.")
                        } else {
                            Text("Tap a muscle to see the exercises from your Lift Log that work it.")
                        }
                    }
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(alignment: .top, spacing: NoopMetrics.gap) {
                        figure(.front, String(localized: "Front view"))
                        figure(.back, String(localized: "Back view"))
                    }
                    legend
                }
            }
            if let muscle = selected {
                exerciseList(muscle)
            }
            if supersetMode {
                supersetBar
            }
        }
    }

    /// What is ticked, A1 · A2 …, and the button that adds them as one superset.
    private var supersetBar: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.rowSpacing) {
                if picks.isEmpty {
                    Text("No exercise ticked")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                } else {
                    Text(verbatim: picks.enumerated().map { pickTag($0.offset) + " " + $0.element.name }
                        .joined(separator: " · "))
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button {
                    onAddSuperset(picks)
                } label: {
                    Group {
                        if picks.count >= 2 {
                            Text(String(localized: "Add the superset (\(picks.count))"))
                        } else {
                            Text("Tick at least 2 exercises")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.noopPrimary)
                .disabled(picks.count < 2)
                .opacity(picks.count >= 2 ? 1 : NoopButtonMetrics.disabledOpacity)
            }
        }
    }

    /// « A1 », « A2 »… — the place in the round of the `n`th tick (0-based), as the editor tags it.
    private func pickTag(_ n: Int) -> String { LiftSuperset.letter(0) + String(n + 1) }

    /// Tick or untick an exercise for the superset; past the cap, a tick is ignored.
    private func togglePick(_ row: LiftExerciseRow) {
        if let at = picks.firstIndex(where: { $0.id == row.id }) {
            picks.remove(at: at)
        } else if picks.count < LiftProgramBlocks.maxSupersetPicks {
            picks.append(row)
        }
    }

    private func figure(_ side: LiftBodyMap.Side, _ label: String) -> some View {
        VStack(spacing: NoopMetrics.space2) {
            LiftBodyMap(side: side, sets: coverage,
                        highlighted: highlightedMuscles,
                        highlightColor: StrandPalette.textPrimary,
                        onTap: { muscle in selected = selected == muscle ? nil : muscle })
                .frame(maxWidth: 130)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: label))
            Text(verbatim: label)
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var legend: some View {
        HStack(spacing: NoopMetrics.space3) {
            legendItem(LiftBodyMapStyle.color(LiftMuscleFilter.directShade), "Worked in this program")
            legendItem(LiftBodyMapStyle.color(LiftMuscleFilter.indirectShade), "Indirectly")
        }
        .font(StrandFont.caption)
        .foregroundStyle(StrandPalette.textSecondary)
        .accessibilityHidden(true)
    }

    private func legendItem(_ color: Color, _ label: LocalizedStringKey) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 10, height: 10)
            Text(label)
        }
    }

    private func exerciseList(_ muscle: LiftMuscle) -> some View {
        let found = LiftMuscleFilter.exercisesWorking(muscle, in: vocabulary)
        return NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.rowSpacing) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: muscle.displayName)
                        .font(StrandFont.headline)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Spacer()
                    Button("Clear selection") { selected = nil }
                        .buttonStyle(.plain)
                        .font(StrandFont.body)
                        .foregroundStyle(StrandPalette.accent)
                }
                if found.direct.isEmpty && found.indirect.isEmpty {
                    Text("No exercise in your Lift Log works this muscle yet.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(found.direct, id: \.id) { row in addRow(row) }
                if !found.indirect.isEmpty {
                    LiftDivider()
                    Text("Indirectly")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                    ForEach(found.indirect, id: \.id) { row in addRow(row) }
                }
                if !supersetMode {
                LiftDivider()
                Button {
                    onNew(muscle)
                } label: {
                    Text(String(localized: "New exercise for \(muscle.displayName)…"))
                        .font(StrandFont.body)
                        .foregroundStyle(StrandPalette.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Text("Added from here, an exercise opens with its muscles filled in: only the targets are left to enter.")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func addRow(_ row: LiftExerciseRow) -> some View {
        let pick = picks.firstIndex(where: { $0.id == row.id })
        return Button {
            if supersetMode { togglePick(row) } else { onAdd(row) }
        } label: {
            HStack(spacing: NoopMetrics.space3) {
                if supersetMode {
                    pickMark(pick)
                } else {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(StrandPalette.accent)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: row.name)
                        .font(StrandFont.body)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text(verbatim: LiftMuscleSummary.line(primary: row.primaryMuscle, secondaries: row.secondaryMuscles))
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
                Spacer(minLength: 0)
                if programExercises.contains(row.name) {
                    Text("In this program")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(supersetMode ? Text(verbatim: row.name) : Text(String(localized: "Add \(row.name)")))
        .accessibilityAddTraits(supersetMode && pick != nil ? .isSelected : [])
    }

    /// The tick of a row in Superset mode: its place in the round (A1, A2…) once ticked, an empty box before.
    private func pickMark(_ pick: Int?) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(pick == nil ? Color.clear : StrandPalette.effortColor)
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(pick == nil ? StrandPalette.textTertiary : StrandPalette.effortColor, lineWidth: 2)
            if let pick {
                Text(verbatim: pickTag(pick))
                    .font(StrandFont.caption.weight(.bold))
                    .foregroundStyle(StrandPalette.surfaceBase)
            }
        }
        .frame(width: 28, height: 28)
        .accessibilityHidden(true)
    }
}
