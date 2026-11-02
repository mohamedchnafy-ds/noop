import SwiftUI
import StrandDesign

/// « Plan the week » (personal fork): one Lift Log program per weekday, or rest. Saved on the iPhone
/// (`TrainingWeekPlan`, UserDefaults); nothing is written before Save.
struct TrainingPlanSheet: View {
    let programs: [TrainingProgramSummary]
    let onSave: (TrainingWeekPlan) -> Void
    @State private var draft: TrainingWeekPlan
    @Environment(\.dismiss) private var dismiss

    init(programs: [TrainingProgramSummary], plan: TrainingWeekPlan, onSave: @escaping (TrainingWeekPlan) -> Void) {
        self.programs = programs
        self.onSave = onSave
        _draft = State(initialValue: plan)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                TrainingPlanForm(programs: programs, draft: $draft)
                    .padding(.horizontal, NoopMetrics.screenHPadding)
                    .padding(.vertical, 16)
            }
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .navigationTitle(Text("Plan the week"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(draft)
                        dismiss()
                    }
                }
            }
        }
    }
}

/// The form of the planning sheet: what the plan drives, a row per weekday, and what happens to a missed
/// day. Pure, so the render test draws it.
struct TrainingPlanForm: View {
    let programs: [TrainingProgramSummary]
    @Binding var draft: TrainingWeekPlan
    var calendar: Calendar = .current

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("One program per day. The calendar follows this plan.")
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            NoopCard(padding: 0) {
                VStack(spacing: 0) {
                    let names = TrainingText.fullWeekdays(calendar)
                    ForEach(1...7, id: \.self) { weekday in
                        dayRow(weekday: weekday, name: names[weekday - 1], isLast: weekday == 7)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("If you miss a day")
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                Text("The session stays on its day, marked “missed”. A session done on another day of the week still counts for the week.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(StrandPalette.surfaceRaised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(StrandPalette.hairline, lineWidth: 1))
        }
    }

    private func dayRow(weekday: Int, name: String, isLast: Bool) -> some View {
        let chosen = draft.plannedProgramId(weekday: weekday).flatMap { id in programs.first { $0.id == id } }
        return HStack(spacing: 10) {
            Text(verbatim: name)
                .font(StrandFont.body)
                .foregroundStyle(StrandPalette.textPrimary)
                .frame(width: 96, alignment: .leading)
            Menu {
                Button { draft.assignProgram(nil, weekday: weekday) } label: { Text("Rest") }
                ForEach(programs) { program in
                    Button { draft.assignProgram(program.id, weekday: weekday) } label: { Text(verbatim: program.name) }
                }
            } label: {
                HStack {
                    Group {
                        if let chosen { Text(verbatim: chosen.name) } else { Text("Rest") }
                    }
                    .lineLimit(1)
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                }
                .font(StrandFont.subhead)
                .foregroundStyle(chosen == nil ? StrandPalette.textSecondary : StrandPalette.effortBright)
                .padding(.horizontal, 10)
                .frame(height: 36)
                .background(chosen == nil ? StrandPalette.surfaceOverlay : StrandPalette.effortColor.opacity(0.16),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(Rectangle())
            }
            .menuIndicator(.hidden)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
        .overlay(alignment: .bottom) {
            if !isLast { Rectangle().fill(StrandPalette.hairline).frame(height: 1) }
        }
    }
}
