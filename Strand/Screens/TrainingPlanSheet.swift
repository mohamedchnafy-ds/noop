import SwiftUI
import StrandDesign

/// « Plan the week » (personal fork): up to three items per weekday — Lift Log programs or cardio (fork
/// chantier 8, lot 4) —, or rest. Saved on the iPhone (`TrainingWeekPlan`, UserDefaults); nothing is
/// written before Save.
struct TrainingPlanSheet: View {
    let programs: [TrainingProgramSummary]
    let onSave: (TrainingWeekPlan) -> Void
    @State private var draft: TrainingWeekPlan
    /// The weekday whose cardio is being chosen.
    @State private var cardioDay: TrainingCardioDay?
    @Environment(\.dismiss) private var dismiss

    init(programs: [TrainingProgramSummary], plan: TrainingWeekPlan, onSave: @escaping (TrainingWeekPlan) -> Void) {
        self.programs = programs
        self.onSave = onSave
        _draft = State(initialValue: plan)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                TrainingPlanForm(programs: programs, draft: $draft,
                                 onAddCardio: { cardioDay = TrainingCardioDay(weekday: $0) })
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
            .sheet(item: $cardioDay) { target in
                TrainingCardioSheet { sport, minutes in
                    draft.addItem(.cardio(sport: sport, minutes: minutes), weekday: target.weekday)
                }
            }
        }
    }
}

/// The weekday the cardio sheet adds to.
struct TrainingCardioDay: Identifiable {
    let weekday: Int
    var id: Int { weekday }
}

/// The form of the planning sheet: what the plan drives, a row per weekday with its items, and what
/// happens to a missed day. Pure, so the render test draws it.
struct TrainingPlanForm: View {
    let programs: [TrainingProgramSummary]
    @Binding var draft: TrainingWeekPlan
    var calendar: Calendar = .current
    /// « Add cardio… » in a day's + menu: the sheet that chooses the sport and the length.
    var onAddCardio: (Int) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Up to 3 per day: Lift Log programs or cardio. The calendar, Today's Synthesis and the Coach follow this plan.")
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
        let items = draft.plannedItems(weekday: weekday)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(verbatim: name)
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.textPrimary)
                if items.isEmpty {
                    Text("Rest")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
                Spacer(minLength: 6)
                if items.count < TrainingWeekPlan.maxItemsPerDay {
                    addMenu(weekday: weekday)
                }
            }
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                itemChip(item) { draft.removeItem(at: index, weekday: weekday) }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 52)
        .overlay(alignment: .bottom) {
            if !isLast { Rectangle().fill(StrandPalette.hairline).frame(height: 1) }
        }
    }

    /// « + »: the programs of the Lift Log, then « Add cardio… ».
    private func addMenu(weekday: Int) -> some View {
        TrainingMenu {
            ForEach(programs) { program in
                Button { draft.addItem(.program(program.id), weekday: weekday) } label: { Text(verbatim: program.name) }
            }
            Button { onAddCardio(weekday) } label: { Text("Add cardio…") }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(StrandPalette.textPrimary)
                .frame(width: 32, height: 32)
                .background(StrandPalette.surfaceOverlay, in: Circle())
                .contentShape(Circle())
                .accessibilityLabel(Text("Add"))
        }
    }

    /// One planned item: a program in blue, cardio in pink with its length, and × to take it off.
    private func itemChip(_ item: TrainingPlanItem, onRemove: @escaping () -> Void) -> some View {
        let tint = item.isCardio ? StrandPalette.metricRose : StrandPalette.effortColor
        return HStack(spacing: 8) {
            Image(systemName: item.isCardio ? "figure.run" : "dumbbell.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Group {
                switch item {
                case .program(let id):
                    if let program = programs.first(where: { $0.id == id }) {
                        Text(verbatim: program.name)
                    } else {
                        Text("Session")
                    }
                case .cardio(let sport, let minutes):
                    Text(verbatim: TodaySessionResolver.cardioName(sport, minutes: minutes))
                }
            }
            .font(StrandFont.subhead)
            .foregroundStyle(StrandPalette.textPrimary)
            .lineLimit(1)
            Spacer(minLength: 6)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(StrandPalette.textSecondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Remove"))
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .frame(height: 36)
        .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// « Add cardio… »: a sport of the catalogue and a target length, added to the day on Add.
struct TrainingCardioSheet: View {
    let onAdd: (String, Int) -> Void
    @State private var sport = WorkoutCatalog.all.first?.name ?? WorkoutCatalog.defaultSportName
    @State private var minutes = 30
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                TrainingCardioForm(sport: $sport, minutes: $minutes)
                    .padding(.horizontal, NoopMetrics.screenHPadding)
                    .padding(.vertical, 16)
            }
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .navigationTitle(Text("Add cardio"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(sport, minutes)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// The cardio form: the sport (shown in the app's language, stored in English) and the target length in
/// steps of 5 minutes. Pure, so the render test draws it.
struct TrainingCardioForm: View {
    @Binding var sport: String
    @Binding var minutes: Int

    static let minuteStep = 5
    static let minuteRange = 5...300

    var body: some View {
        NoopCard(padding: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Text("Sport")
                        .font(StrandFont.body)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Spacer(minLength: 6)
                    TrainingMenu {
                        ForEach(WorkoutCatalog.all) { option in
                            Button { sport = option.name } label: {
                                Text(verbatim: WorkoutCatalog.shownSportName(option.name))
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(verbatim: WorkoutCatalog.shownSportName(sport)).lineLimit(1)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.metricRose)
                        .padding(.horizontal, 10)
                        .frame(height: 36)
                        .background(StrandPalette.metricRose.opacity(0.16),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .contentShape(Rectangle())
                    }
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 52)
                Rectangle().fill(StrandPalette.hairline).frame(height: 1)
                HStack(spacing: 10) {
                    Text("Target length")
                        .font(StrandFont.body)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Spacer(minLength: 6)
                    stepButton("minus", label: "Less") { minutes = max(Self.minuteRange.lowerBound, minutes - Self.minuteStep) }
                    Text("\(minutes) min")
                        .font(StrandFont.headline.monospacedDigit())
                        .foregroundStyle(StrandPalette.textPrimary)
                        .frame(minWidth: 64)
                    stepButton("plus", label: "More") { minutes = min(Self.minuteRange.upperBound, minutes + Self.minuteStep) }
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 52)
            }
            .clipShape(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
        }
    }

    private func stepButton(_ symbol: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(StrandPalette.textPrimary)
                .frame(width: 32, height: 32)
                .background(StrandPalette.surfaceOverlay, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}
