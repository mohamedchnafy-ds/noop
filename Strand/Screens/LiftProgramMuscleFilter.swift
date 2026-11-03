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
/// exercises of the muscle that was touched.
struct LiftProgramMuscleFilter: View {
    /// The user's exercise vocabulary.
    let vocabulary: [LiftExerciseRow]
    /// The exercise names of the program's lines, in order.
    let programExercises: [String]
    @Binding var selected: LiftMuscle?
    /// "+" on a known exercise.
    let onAdd: (LiftExerciseRow) -> Void
    /// "New exercise for …": the line editor with this muscle as the primary.
    let onNew: (LiftMuscle) -> Void

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
                    Text("Tap a muscle to see the exercises from your Lift Log that work it.")
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

    private func addRow(_ row: LiftExerciseRow) -> some View {
        Button {
            onAdd(row)
        } label: {
            HStack(spacing: NoopMetrics.space3) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(StrandPalette.accent)
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
        .accessibilityLabel(Text(String(localized: "Add \(row.name)")))
    }
}
