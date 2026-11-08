import SwiftUI
import StrandDesign
import WhoopStore

// MARK: - Élan · Poids (personal fork, chantier 10, PR B)
//
// The weight page and the morning weigh-in sheet. The fear of the scale (fiche, 2 Nov.) sets the rules:
// only the smoothed TREND is ever stated (`ElanWeight.weightSummary`, after five weigh-ins), never the gap
// between two mornings; the first weigh-in is a starting point; a weigh-in above the trend gets the message
// written in advance. The curve has no point per weigh-in. « Le profil suit la tendance » writes the trend
// into the profile the Coach and the Nutrition goals read.

struct ElanWeightView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    let state: ElanState
    let bestGain: ElanLiftGain?
    let unitSystem: UnitSystem
    let defaultKg: Double
    let onChanged: () -> Void
    var animated: Bool = true

    private enum Period: Hashable, CaseIterable { case fourWeeks, twelveWeeks, all }

    @State private var period: Period = .twelveWeeks
    @State private var showWeighIn = false
    @State private var profileFollows = ElanWeight.profileFollowsTrend()
    @State private var targetKg: Double? = ElanWeight.targetKg()

    private var summary: ElanWeightSummary { state.weight }
    private var today: String { TrainingCalendar.trainingDayKey(Date(), calendar: .current) }
    private var unit: String { UnitFormatter.massUnit(unitSystem) }

    private var shownTrend: [ElanWeightTrendPoint] {
        guard let last = summary.trend.last else { return [] }
        let days: Int?
        switch period {
        case .fourWeeks: days = 28
        case .twelveWeeks: days = 84
        case .all: days = nil
        }
        guard let days else { return summary.trend }
        let floor = ElanDays.elanDay(last.day, adding: -days)
        return summary.trend.filter { $0.day >= floor }
    }

    var body: some View {
        ScreenScaffold(title: "Weight", subtitle: "Only your trend counts.") {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                trendCard
                ElanSectionTitle("Nutrition days held")
                nutritionCard
                if let bestGain, bestGain.gainKg > 0 {
                    NoopCard(padding: 14) {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "dumbbell.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(StrandPalette.effortColor)
                            Text("Your body changes even when the scale barely moves: \(bestGain.name) \(ElanFormat.signedWeight(bestGain.gainKg, system: unitSystem)) in \(bestGain.weeks) weeks.")
                                .font(StrandFont.subhead)
                                .foregroundStyle(StrandPalette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                settingsCard
                if summary.latest?.day == today {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(StrandPalette.intakeColor)
                        Text("Weigh-in logged this morning").foregroundStyle(StrandPalette.textSecondary)
                    }
                    .font(StrandFont.subhead.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                } else {
                    ElanActionButton(title: Text("Log this morning's weigh-in"), look: .primary) { showWeighIn = true }
                }
            }
        }
        .noopEntranceRoot()
        .sheet(isPresented: $showWeighIn, onDismiss: onChanged) {
            ElanWeighInSheet(summary: summary, unitSystem: unitSystem, defaultKg: defaultKg)
                .environmentObject(repo)
                .environmentObject(profile)
        }
    }

    // MARK: Trend

    private var trendCard: some View {
        NoopCard(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Trend")
                            .font(StrandFont.footnote.weight(.semibold))
                            .foregroundStyle(StrandPalette.textSecondary)
                        if let trend = summary.trendKg {
                            HStack(alignment: .firstTextBaseline, spacing: 5) {
                                NoopRollingNumber(value: LiftFormat.display(fromKilograms: trend, system: unitSystem),
                                                  format: { ElanFormat.oneDecimal($0) },
                                                  font: StrandFont.rounded(40), color: StrandPalette.textPrimary,
                                                  entrance: .slam, armed: animated, launchKey: "elan.weight.page.trend")
                                Text(verbatim: unit)
                                    .font(StrandFont.headline)
                                    .foregroundStyle(StrandPalette.textSecondary)
                            }
                            if let change = summary.changeSinceStartKg, let first = summary.first {
                                Text("\(ElanFormat.signedWeight(change, system: unitSystem)) since your start, \(ElanFormat.dayLabel(first.day))")
                                    .font(StrandFont.subhead)
                                    .foregroundStyle(StrandPalette.textSecondary)
                            }
                        } else {
                            Text("\(summary.count) / \(ElanWeight.trendMinimumCount) weigh-ins")
                                .font(StrandFont.rounded(28))
                                .foregroundStyle(StrandPalette.textPrimary)
                            Text("Your trend appears after five weigh-ins. Until then, no comparison at all.")
                                .font(StrandFont.subhead)
                                .foregroundStyle(StrandPalette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 8)
                }
                if summary.hasTrend {
                    SegmentedPillControl([Period.fourWeeks, .twelveWeeks, .all], selection: $period,
                                         fillsAvailableWidth: true) { period in
                        switch period {
                        case .fourWeeks: return String(localized: "4 wk")
                        case .twelveWeeks: return String(localized: "12 wk")
                        case .all: return String(localized: "All")
                        }
                    }
                    ElanTrendChart(points: shownTrend, targetKg: targetKg, system: unitSystem, height: 150,
                                   animated: animated, launchKey: "elan.weight.page.curve.\(period)")
                    HStack {
                        if let first = shownTrend.first {
                            Text(verbatim: ElanFormat.dayLabel(first.day))
                        }
                        Spacer()
                        if let targetKg {
                            Text("target \(ElanFormat.weight(targetKg, system: unitSystem))")
                        }
                        Spacer()
                        Text("today")
                    }
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                    Rectangle().fill(StrandPalette.hairline).frame(height: NoopMetrics.hairlineWidth)
                    HStack(alignment: .top, spacing: 10) {
                        figure(Text("Pace"), summary.ratePerWeekKg.map { ElanFormat.signedWeight($0, system: unitSystem) },
                               summary.ratePerWeekKg == nil ? nil : Text("per week"))
                        figure(Text("Left"), summary.remainingKg.map { ElanFormat.weight(abs($0), system: unitSystem) },
                               summary.remainingKg.map { $0 > 0 ? Text("to lose") : Text("to gain") })
                        figure(Text("Around"), summary.etaDay.map { ElanFormat.dayLabel($0) }, nil)
                    }
                }
                Text("The curve is smoothed: no point per weigh-in, never the gap between two mornings.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func figure(_ title: Text, _ value: String?, _ unitText: Text?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            title
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textSecondary)
            Text(verbatim: value ?? "—")
                .font(StrandFont.rounded(17))
                .foregroundStyle(value == nil ? StrandPalette.textTertiary : StrandPalette.textPrimary)
            if value != nil, let unitText {
                unitText
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Nutrition days held

    private var nutritionCard: some View {
        let held = state.nutritionWeek.filter { $0.status == .held }.count
        return NoopCard(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        NoopRollingNumber(value: Double(held), format: { String(Int($0.rounded())) },
                                          font: StrandFont.rounded(28), color: StrandPalette.textPrimary,
                                          armed: animated, launchKey: "elan.weight.page.held")
                        Text("/ 7")
                            .font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                    Spacer()
                    Text("the last 7 days")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
                NoopFirstDraw(key: "elan.weight.page.nutrition", armed: animated) { phase in
                    HStack(spacing: 4) {
                        ForEach(Array(state.nutritionWeek.enumerated()), id: \.offset) { index, day in
                            VStack(spacing: 6) {
                                ElanNutritionDayMark(status: day.status)
                                    .opacity(phase.drawn ? 1 : 0)
                                    .scaleEffect(phase.drawn ? 1 : 0.6)
                                    .animation(phase.motion(NoopMotion.valueChange.delay(Double(index) * NoopMotion.ringStagger)),
                                               value: phase.drawn)
                                Text(verbatim: ElanFormat.weekdayLetter(day.day))
                                    .font(StrandFont.caption)
                                    .foregroundStyle(StrandPalette.textSecondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                HStack(spacing: 14) {
                    legend(Text("held")) { Circle().fill(StrandPalette.intakeColor).frame(width: 10, height: 10) }
                    legend(Text("not held")) { Circle().strokeBorder(StrandPalette.textSecondary, lineWidth: 1.5).frame(width: 10, height: 10) }
                    legend(Text("no meal logged")) { Rectangle().fill(StrandPalette.surfaceInset).frame(width: 10, height: 2) }
                }
                Text("Held: what you ate is within ten per cent of your intake goal (Nutrition → Goals).")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func legend<Mark: View>(_ label: Text, @ViewBuilder mark: () -> Mark) -> some View {
        HStack(spacing: 5) {
            mark()
            label
        }
        .font(StrandFont.caption)
        .foregroundStyle(StrandPalette.textSecondary)
    }

    // MARK: Settings

    private var settingsCard: some View {
        NoopCard(padding: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text("Target weight")
                        .font(StrandFont.body)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Spacer()
                    if let targetKg {
                        stepButton("minus", label: Text("Lower the target")) { setTarget(targetKg - stepKg) }
                        Text(verbatim: ElanFormat.weight(targetKg, system: unitSystem))
                            .font(StrandFont.rounded(17))
                            .foregroundStyle(StrandPalette.textPrimary)
                            .monospacedDigit()
                            .frame(minWidth: 72)
                        stepButton("plus", label: Text("Raise the target")) { setTarget(targetKg + stepKg) }
                        Button {
                            setTarget(nil)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 17))
                                .foregroundStyle(StrandPalette.textTertiary)
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Clear the target"))
                    } else {
                        Button {
                            setTarget(((summary.trendKg ?? summary.latest?.kg ?? defaultKg) * 2).rounded() / 2)
                        } label: {
                            Text("Choose")
                                .font(StrandFont.subhead.weight(.semibold))
                                .foregroundStyle(StrandPalette.accent)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 50)
                Rectangle().fill(StrandPalette.hairline).frame(height: NoopMetrics.hairlineWidth).padding(.leading, 16)
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("The profile follows the trend")
                            .font(StrandFont.body)
                            .foregroundStyle(StrandPalette.textPrimary)
                        Text("the weight the Coach and the Goals read")
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                    Spacer()
                    Toggle("", isOn: $profileFollows)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(StrandPalette.switchOn)
                        .accessibilityLabel(Text("The profile follows the trend"))
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 62)
            }
        }
        .onChangeCompat(of: profileFollows) { on in
            ElanWeight.setProfileFollowsTrend(on)
            if on { ElanWeight.syncProfileWeight(summary, profile: profile) }
            onChanged()
        }
    }

    /// Half a kilogram, or a pound.
    private var stepKg: Double { unitSystem == .imperial ? 1 / UnitFormatter.poundsPerKilogram : 0.5 }

    private func setTarget(_ kg: Double?) {
        let clamped = kg.flatMap { ElanWeight.kgRange.contains($0) ? $0 : nil }
        targetKg = clamped
        ElanWeight.setTargetKg(clamped)
        onChanged()
    }

    private func stepButton(_ symbol: String, label: Text, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(StrandPalette.textPrimary)
                .frame(width: 36, height: 36)
                .background(StrandPalette.surfaceInset, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - The morning weigh-in

/// « Pesée du matin »: one number, typed or stepped by a tenth, then the words that fit the case (the
/// starting point, the trend still building, logged, logged above the trend). Saved once per day; a second
/// save the same morning replaces the first.
struct ElanWeighInSheet: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @Environment(\.dismiss) private var dismiss
    let summary: ElanWeightSummary
    let unitSystem: UnitSystem

    @State private var text: String
    @State private var outcome: ElanWeight.WeighInOutcome?
    @State private var trendAfter: Double?
    @State private var saving = false
    @State private var invalid = false

    init(summary: ElanWeightSummary, unitSystem: UnitSystem, defaultKg: Double) {
        self.summary = summary
        self.unitSystem = unitSystem
        let start = summary.latest?.kg ?? defaultKg
        _text = State(initialValue: ElanFormat.oneDecimal(LiftFormat.display(fromKilograms: start, system: unitSystem)))
    }

    /// The typed number in display units.
    private var shown: Double? {
        Double(text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
    }

    private var kgValue: Double? {
        shown.map { unitSystem == .imperial ? $0 / UnitFormatter.poundsPerKilogram : $0 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let outcome {
                        outcomeCard(outcome)
                    } else {
                        entry
                    }
                }
                .padding(NoopVisualStyle.pagePadding)
            }
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .navigationTitle(Text("Morning weigh-in"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if outcome == nil {
                        Button("Cancel") { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if outcome != nil {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
        .tint(StrandPalette.accent)
    }

    // MARK: Entry

    private var entry: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your weight this morning")
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
                .frame(maxWidth: .infinity)
            HStack(spacing: 16) {
                step("minus", label: Text("Less"), delta: -0.1)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    TextField("", text: $text)
                        .font(StrandFont.rounded(54))
                        .foregroundStyle(StrandPalette.textPrimary)
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.plain)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .frame(width: 150)
                        .accessibilityLabel(Text("Weight"))
                    Text(verbatim: UnitFormatter.massUnit(unitSystem))
                        .font(StrandFont.headline)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
                step("plus", label: Text("More"), delta: 0.1)
            }
            .frame(maxWidth: .infinity)
            Text("In the morning, before eating.")
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textSecondary)
                .frame(maxWidth: .infinity)
            if invalid {
                Text("Between 20 and 400 kg.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.statusWarning)
                    .frame(maxWidth: .infinity)
            }
            NoopCard(padding: 14) {
                Text("From one day to the next, weight moves by one to two kilograms with water, salt and carbs. With a weigh-in every morning, a single one hardly counts any more.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ElanActionButton(title: saving ? Text("Saving…") : Text("Save"), look: .primary) {
                Task { await save() }
            }
            .disabled(saving || kgValue == nil)
            .padding(.top, 6)
        }
    }

    private func step(_ symbol: String, label: Text, delta: Double) -> some View {
        Button {
            let value = ((shown ?? 0) + delta)
            text = ElanFormat.oneDecimal(max(0, value))
            invalid = false
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(StrandPalette.textPrimary)
                .frame(width: 48, height: 48)
                .background(StrandPalette.surfaceInset, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: After the save

    @ViewBuilder
    private func outcomeCard(_ outcome: ElanWeight.WeighInOutcome) -> some View {
        NoopCard(padding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(StrandPalette.intakeColor)
                    switch outcome {
                    case .startingPoint:
                        Text("This is your starting point.")
                            .font(StrandFont.headline)
                            .foregroundStyle(StrandPalette.textPrimary)
                    default:
                        Text("Weigh-in logged.")
                            .font(StrandFont.headline)
                            .foregroundStyle(StrandPalette.textPrimary)
                    }
                }
                switch outcome {
                case .startingPoint:
                    Text("No comparison today. Your trend appears after five weigh-ins.")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    progressBar(1, of: ElanWeight.trendMinimumCount)
                case .buildingTrend(let count, let needed):
                    Text("\(count) / \(needed) weigh-ins before your trend appears.")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                    progressBar(count, of: needed)
                case .noted:
                    Text("Your trend goes on. One weigh-in alone changes little.")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    trendRow
                case .notedHigher:
                    Text("A single weigh-in moves mostly with water: salt, carbs, yesterday's session. Your trend keeps its own course.")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    trendRow
                }
            }
        }
        .transition(.softCard(reduced: false))
    }

    @ViewBuilder
    private var trendRow: some View {
        if let trendAfter {
            Rectangle().fill(StrandPalette.hairline).frame(height: NoopMetrics.hairlineWidth)
            HStack(alignment: .firstTextBaseline) {
                Text("Trend")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                Spacer()
                Text(verbatim: ElanFormat.weight(trendAfter, system: unitSystem))
                    .font(StrandFont.rounded(22))
                    .foregroundStyle(StrandPalette.textPrimary)
            }
        }
    }

    private func progressBar(_ count: Int, of total: Int) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 5) {
                ForEach(0..<max(1, total), id: \.self) { index in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(index < count ? StrandPalette.textPrimary : StrandPalette.surfaceInset)
                        .frame(height: 6)
                }
            }
            Text(verbatim: "\(count) / \(total)")
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(count) of \(total) weigh-ins"))
    }

    @MainActor
    private func save() async {
        guard let kg = kgValue, ElanWeight.kgRange.contains(kg) else {
            invalid = true
            return
        }
        saving = true
        let day = TrainingCalendar.trainingDayKey(Date(), calendar: .current)
        let before = await repo.elanWeighIns(days: 400)
        let saved = ElanWeighIn(day: day, kg: (kg * 10).rounded() / 10)
        let result = ElanWeight.weighInOutcome(before: before, saved: saved)
        guard await repo.saveElanWeighIn(day: day, kg: saved.kg) else {
            saving = false
            invalid = true
            return
        }
        let after = ElanWeight.weightSummary(weighIns: before.filter { $0.day != day } + [saved],
                                             targetKg: ElanWeight.targetKg())
        ElanWeight.syncProfileWeight(after, profile: profile)
        trendAfter = after.trendKg
        saving = false
        withAnimation(NoopMotion.card) { outcome = result }
    }
}
