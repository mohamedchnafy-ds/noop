import SwiftUI
import StrandDesign

// MARK: - Nutrition goals (personal fork, Nutrition mockup 3; redone in fork chantier 9, mockup 4 screen 3)
//
// The intake goal in large at the top with its whole calculation written out, then the four steps in the
// order they are applied: the basal metabolic rate (the profile), the activity level it is multiplied by
// (the strap's measured expenditure shown beside it for information only), the goal as a percentage or in
// typed kcal, and the split into protein, fat and carbohydrates. The numbers come from `NutritionGoals`;
// this screen only writes them out and moves the settings.

struct NutritionGoalsView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore

    @AppStorage(NutritionGoals.proteinTenthsKey) private var proteinTenthsRaw = NutritionGoals.defaultProteinTenths
    @AppStorage(NutritionGoals.fatTenthsKey) private var fatTenthsRaw = NutritionGoals.defaultFatTenths
    @AppStorage(NutritionGoals.goalPercentKey) private var goalPercentRaw = NutritionGoals.defaultGoalPercent
    @AppStorage(NutritionGoals.activityLevelKey) private var activityRaw = NutritionGoals.ActivityLevel.defaultLevel.rawValue
    @AppStorage(NutritionGoals.goalModeKey) private var goalModeRaw = NutritionGoals.GoalMode.percent.rawValue
    @AppStorage(NutritionGoals.manualKcalKey) private var manualKcalRaw = 0
    /// Personal fork: a new barcode is looked up on Open Food Facts (`OpenFoodFacts`).
    @AppStorage(OpenFoodFacts.enabledKey) private var openFoodFactsOn = true
    /// Personal fork, chantier 8: the meal reminders (`MealReminder`), off by default.
    @AppStorage(MealReminder.enabledKey) private var remindersOn = false
    @AppStorage(MealReminder.minutesKey) private var reminderMinutes = MealReminder.defaultMinutes
    @State private var remindersDenied = false

    var body: some View {
        ScreenScaffold(title: "Goals") {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                NutritionGoalsContent(
                    wearer: NutritionDayReader.goalBody(profile), age: profile.age,
                    reference: NutritionDayReader.referenceBefore(repo),
                    activityRaw: $activityRaw, goalModeRaw: $goalModeRaw, goalPercentRaw: $goalPercentRaw,
                    manualKcalRaw: $manualKcalRaw, proteinTenthsRaw: $proteinTenthsRaw, fatTenthsRaw: $fatTenthsRaw)
                barcodeSection
                remindersSection
            }
        }
    }

    /// The meal reminders: the switch (asking for notifications when it turns on) and the training-day time.
    private var remindersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Reminders").strandOverline()
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: Binding(get: { remindersOn }, set: { on in
                    MealReminder.setMealRemindersEnabled(on, repo: repo) { granted in
                        remindersDenied = on && !granted
                    }
                })) {
                    Text("Remind me to log my meals")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textPrimary)
                }
                .toggleStyle(.switch)
                .tint(StrandPalette.accent)
                if remindersOn {
                    DatePicker("On a training day, at", selection: reminderTime, displayedComponents: .hourAndMinute)
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textPrimary)
                }
                Text("At most one a day: on a day the week plan sets a session, at this time if no meal is logged yet; an hour after a session if no meal is logged since. Nothing is sent: the reminders are planned on the phone.")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if remindersDenied {
                    Text("Notifications are off for NOOP: turn them on in the Settings app.")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.statusWarning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .background(NoopPanelSurface(cornerRadius: 26))
        }
    }

    /// The training-day time as a date today, written back as minutes since midnight.
    private var reminderTime: Binding<Date> {
        Binding(get: {
            let minutes = min(max(reminderMinutes, 0), 24 * 60 - 1)
            return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
        }, set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            reminderMinutes = (parts.hour ?? 12) * 60 + (parts.minute ?? 30)
            Task { await MealReminder.refreshMealReminders(repo: repo) }
        })
    }

    private var barcodeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Barcodes").strandOverline()
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $openFoodFactsOn) {
                    Text("Look new products up on Open Food Facts")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textPrimary)
                }
                .toggleStyle(.switch)
                .tint(StrandPalette.accent)
                Text("Only the barcode is sent, to the open food database (no account). The product you add stays in your journal, so the next scan needs no network. Off, or when the product is missing, the Coach reads the label from a photo.")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .background(NoopPanelSurface(cornerRadius: 26))
        }
    }
}

/// The Goals screen's content, from the profile, the measured expenditure (information only) and the settings.
struct NutritionGoalsContent: View {
    let wearer: NutritionGoals.Body
    let age: Int
    let reference: NutritionGoals.Reference?
    @Binding var activityRaw: String
    @Binding var goalModeRaw: String
    @Binding var goalPercentRaw: Int
    @Binding var manualKcalRaw: Int
    @Binding var proteinTenthsRaw: Int
    @Binding var fatTenthsRaw: Int

    private typealias Level = NutritionGoals.ActivityLevel
    private typealias Mode = NutritionGoals.GoalMode

    /// The settings as every reader clamps them (`NutritionGoals.Settings.settingsFromStored`).
    private var settings: NutritionGoals.Settings {
        .settingsFromStored(activity: activityRaw, mode: goalModeRaw, goalPercent: goalPercentRaw,
                            manualKcal: manualKcalRaw, proteinTenths: proteinTenthsRaw, fatTenths: fatTenthsRaw)
    }

    private var plan: NutritionGoals.Plan { NutritionGoals.intakePlan(body: wearer, settings: settings) }

    var body: some View {
        let plan = plan
        return VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
            resultCard(plan)
            goalsSection("1 · Basal metabolic rate") { profileRow(plan) }
            goalsSection("2 · Activity level") {
                activityCard
                expenditureLines(plan)
            }
            goalsSection("3 · Goal") { goalCard(plan) }
            goalsSection("4 · Split") { macrosCard(plan) }
            Text("Calories per gram: 4 for protein and carbs, 9 for fat.")
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
    }

    private func goalsSection<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .strandOverline()
                .padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private var divider: some View {
        Rectangle().fill(StrandPalette.hairline).frame(height: NoopMetrics.hairlineWidth)
    }

    // MARK: The result

    /// "2 238 × 1,375 = 3 077 · −20 % → 2 460", or the typed goal beside the estimated expenditure.
    private func chainText(_ plan: NutritionGoals.Plan) -> String {
        let basal = NutritionFormat.whole(plan.basalKcal)
        let factor = NutritionFormat.coefficient(plan.settings.activity.factor)
        let expenditure = NutritionFormat.whole(plan.expenditureKcal)
        if plan.isTyped {
            return String(localized: "typed by you · your estimated expenditure: \(expenditure)")
        }
        return "\(basal) × \(factor) = \(expenditure) · \(NutritionFormat.signedPercent(plan.settings.goalPercent)) → "
            + NutritionFormat.whole(plan.intakeKcal)
    }

    private func resultCard(_ plan: NutritionGoals.Plan) -> some View {
        VStack(spacing: 6) {
            Text("Your intake goal")
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: NutritionFormat.whole(plan.intakeKcal))
                    .font(StrandFont.number(44, weight: .bold))
                    .foregroundStyle(StrandPalette.intakeColor)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("kcal / day")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            Text(verbatim: chainText(plan))
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textSecondary)
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if plan.isBelowBasal {
                Text("Below your basal metabolic rate (\(NutritionFormat.whole(plan.basalKcal)) kcal): not advised without supervision.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.statusWarning)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(NoopPanelSurface(cornerRadius: NoopMetrics.cardRadius))
        .accessibilityElement(children: .combine)
    }

    // MARK: 1 · Basal metabolic rate

    private var sexLabel: String {
        switch wearer.sex.lowercased() {
        case "male": return String(localized: "Man")
        case "female": return String(localized: "Woman")
        default: return String(localized: "Non-binary")
        }
    }

    /// "Homme · 30 ans · 178 cm · 80 kg".
    private var profileSummary: String {
        let height = NutritionFormat.whole(Int(wearer.heightCm.rounded())) + " cm"
        let weight = NutritionFormat.editable(wearer.weightKg) + " kg"
        return [sexLabel, String(localized: "\(age) years"), height, weight].joined(separator: " · ")
    }

    private func profileRow(_ plan: NutritionGoals.Plan) -> some View {
        NavigationLink {
            SettingsView()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: profileSummary)
                        .font(StrandFont.body)
                        .foregroundStyle(StrandPalette.textPrimary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text("Revised Harris-Benedict")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(verbatim: NutritionFormat.whole(plan.basalKcal))
                    .font(StrandFont.number(20, weight: .bold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .monospacedDigit()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(StrandPalette.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 64)
            .background(NoopPanelSurface(cornerRadius: 26))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Opens the profile, the same one the calories burned use"))
    }

    // MARK: 2 · Activity level

    private var activityCard: some View {
        let selected = settings.activity
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(Level.allCases.enumerated()), id: \.offset) { index, level in
                if index > 0 { divider }
                Button {
                    activityRaw = level.rawValue
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: level.levelTitle)
                                .font(StrandFont.body)
                                .foregroundStyle(StrandPalette.textPrimary)
                            Text(verbatim: level.levelHint)
                                .font(StrandFont.caption)
                                .foregroundStyle(StrandPalette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(verbatim: "× " + NutritionFormat.coefficient(level.factor))
                            .font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .monospacedDigit()
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(StrandPalette.accent)
                            .frame(width: 18)
                            .opacity(level == selected ? 1 : 0)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(level == selected ? .isSelected : [])
            }
        }
        .padding(.horizontal, 16)
        .background(NoopPanelSurface(cornerRadius: 26))
    }

    /// The daily expenditure, then how it is calculated and what the strap measured beside it.
    private func expenditureLines(_ plan: NutritionGoals.Plan) -> some View {
        let calculation = "\(NutritionFormat.whole(plan.basalKcal)) × \(NutritionFormat.coefficient(plan.settings.activity.factor))."
        let measured = reference.map {
            " " + String(localized: "The strap measured \(NutritionFormat.whole(Int($0.kcal.rounded()))) kcal on average (\($0.days) complete days): for information only, it under-counts when it is not worn all the time.")
        } ?? ""
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("Daily expenditure")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                Spacer(minLength: 8)
                Text(verbatim: NutritionFormat.kcalUnit(plan.expenditureKcal))
                    .font(StrandFont.number(16, weight: .bold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .monospacedDigit()
            }
            Text(verbatim: calculation + measured)
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }

    // MARK: 3 · Goal

    private var modeBinding: Binding<Mode> {
        Binding(get: { settings.mode }, set: { next in
            // The first switch to kcal starts from the goal the percentage gave, on its 50 kcal step.
            if next == .kcal, settings.manualKcal == 0 {
                manualKcalRaw = NutritionGoals.clampedManualKcal(plan.intakeKcal)
            }
            goalModeRaw = next.rawValue
        })
    }

    private func goalCard(_ plan: NutritionGoals.Plan) -> some View {
        let percent = plan.settings.goalPercent
        return VStack(alignment: .leading, spacing: 12) {
            SegmentedPillControl([Mode.percent, .kcal], selection: modeBinding, fillsAvailableWidth: true) { mode in
                switch mode {
                case .percent: return String(localized: "In \("%")")
                case .kcal: return String(localized: "In kcal")
                }
            }
            if plan.settings.mode == .percent {
                HStack(spacing: 6) {
                    presetChip("Lose", value: NutritionGoals.losePresetPercent, active: percent < 0)
                    presetChip("Maintenance", value: 0, active: percent == 0)
                    presetChip("Gain", value: NutritionGoals.gainPresetPercent, active: percent > 0)
                }
                HStack(spacing: 8) {
                    Text("Deficit or surplus")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                    Spacer(minLength: 8)
                    goalsStepper(value: NutritionFormat.signedPercent(percent), unit: nil,
                                 minus: "Decrease the percentage", plus: "Increase the percentage",
                                 canMinus: percent > NutritionGoals.goalPercentRange.lowerBound,
                                 canPlus: percent < NutritionGoals.goalPercentRange.upperBound) { up in
                        goalPercentRaw = NutritionGoals.clampedPercent(percent + (up ? 1 : -1) * NutritionGoals.goalPercentStep)
                    }
                }
                Text(verbatim: String(localized: "In steps of \(NutritionFormat.percentText(NutritionGoals.goalPercentStep)), from \(NutritionFormat.signedPercent(NutritionGoals.goalPercentRange.lowerBound)) to \(NutritionFormat.signedPercent(NutritionGoals.goalPercentRange.upperBound)). Lose = \(NutritionFormat.signedPercent(NutritionGoals.losePresetPercent)), Maintenance = 0, Gain = \(NutritionFormat.signedPercent(NutritionGoals.gainPresetPercent)) to start."))
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                let manual = plan.intakeKcal
                HStack(spacing: 8) {
                    Text("My goal")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                    Spacer(minLength: 8)
                    goalsStepper(value: NutritionFormat.whole(manual), unit: "kcal",
                                 minus: "Decrease by 50 kcal", plus: "Increase by 50 kcal",
                                 canMinus: manual > NutritionGoals.manualKcalRange.lowerBound,
                                 canPlus: manual < NutritionGoals.manualKcalRange.upperBound) { up in
                        manualKcalRaw = NutritionGoals.clampedManualKcal(manual + (up ? 1 : -1) * NutritionGoals.manualKcalStep)
                    }
                }
                Text("In steps of 50 kcal. The goal no longer moves when your weight or your activity changes.")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(NoopPanelSurface(cornerRadius: 26))
    }

    /// A preset: white when the goal points its way, tap = its starting percentage.
    private func presetChip(_ title: LocalizedStringKey, value: Int, active: Bool) -> some View {
        Button {
            goalPercentRaw = value
        } label: {
            Text(title)
                .font(StrandFont.subhead.weight(.semibold))
                .foregroundStyle(active ? StrandPalette.surfaceBase : StrandPalette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(Capsule().fill(active ? StrandPalette.textPrimary : StrandPalette.surfaceOverlay))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    // MARK: 4 · Split

    private func macrosCard(_ plan: NutritionGoals.Plan) -> some View {
        let weight = NutritionFormat.editable(wearer.weightKg)
        let proteinTenths = plan.settings.proteinTenths
        let fatTenths = plan.settings.fatTenths
        return VStack(alignment: .leading, spacing: 0) {
            macroRow(.protein, grams: plan.proteinG,
                     detail: "\(NutritionFormat.oneDecimalText(Double(proteinTenths) / 10)) × \(weight) kg · \(NutritionFormat.whole(plan.proteinKcal)) kcal") {
                goalsStepper(value: NutritionFormat.oneDecimalText(Double(proteinTenths) / 10), unit: "g/kg",
                        minus: "Decrease by 0.1 g per kg", plus: "Increase by 0.1 g per kg",
                        canMinus: proteinTenths > NutritionGoals.proteinTenthsRange.lowerBound,
                        canPlus: proteinTenths < NutritionGoals.proteinTenthsRange.upperBound) { up in
                    proteinTenthsRaw = proteinTenths + (up ? 1 : -1)
                }
            }
            divider
            macroRow(.fat, grams: plan.fatG,
                     detail: "\(NutritionFormat.oneDecimalText(Double(fatTenths) / 10)) × \(weight) kg · \(NutritionFormat.whole(plan.fatKcal)) kcal") {
                goalsStepper(value: NutritionFormat.oneDecimalText(Double(fatTenths) / 10), unit: "g/kg",
                        minus: "Decrease by 0.1 g per kg", plus: "Increase by 0.1 g per kg",
                        canMinus: fatTenths > NutritionGoals.fatTenthsRange.lowerBound,
                        canPlus: fatTenths < NutritionGoals.fatTenthsRange.upperBound) { up in
                    fatTenthsRaw = fatTenths + (up ? 1 : -1)
                }
            }
            divider
            carbsRow(plan)
            if plan.intakeKcal > 0 {
                shareBar(plan)
                    .padding(.top, 10)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 16)
        .background(NoopPanelSurface(cornerRadius: 26))
    }

    private func macroRow<Control: View>(_ macro: NutritionMacro, grams: Int, detail: String,
                                         @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 12) {
            NutritionMacroDot(macro: macro, size: 10)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: macro.title)
                        .font(StrandFont.body)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text(verbatim: NutritionFormat.gramsUnit(grams))
                        .font(StrandFont.number(16))
                        .foregroundStyle(StrandPalette.textPrimary)
                        .monospacedDigit()
                }
                Text(verbatim: detail)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control()
        }
        .frame(minHeight: 72)
    }

    private func carbsRow(_ plan: NutritionGoals.Plan) -> some View {
        let detail = "(\(NutritionFormat.whole(plan.intakeKcal)) \u{2212} \(NutritionFormat.whole(plan.proteinKcal)) \u{2212} \(NutritionFormat.whole(plan.fatKcal))) ÷ 4 · \(NutritionFormat.whole(plan.carbsKcal)) kcal"
        return HStack(spacing: 12) {
            NutritionMacroDot(macro: .carbs, size: 10)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: NutritionMacro.carbs.title)
                        .font(StrandFont.body)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text(verbatim: NutritionFormat.gramsUnit(plan.carbsG))
                        .font(StrandFont.number(16))
                        .foregroundStyle(StrandPalette.textPrimary)
                        .monospacedDigit()
                }
                Text(verbatim: detail)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .monospacedDigit()
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("the rest")
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(StrandPalette.surfaceInset, in: Capsule())
                .overlay(Capsule().strokeBorder(StrandPalette.hairline, lineWidth: NoopMetrics.hairlineWidth))
        }
        .frame(minHeight: 72)
    }

    /// One part of the calorie split bar.
    private struct SharePart: Identifiable {
        let macro: NutritionMacro
        let kcal: Int
        var id: NutritionMacro { macro }
    }

    private func shareBar(_ plan: NutritionGoals.Plan) -> some View {
        let parts = [SharePart(macro: .protein, kcal: plan.proteinKcal), SharePart(macro: .fat, kcal: plan.fatKcal),
                     SharePart(macro: .carbs, kcal: plan.carbsKcal)]
        let total = max(1, parts.map(\.kcal).reduce(0, +))
        return VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                let gap: CGFloat = 3
                let usable = max(0, geo.size.width - gap * CGFloat(parts.count - 1))
                HStack(spacing: gap) {
                    ForEach(parts) { part in
                        Capsule()
                            .fill(part.macro.tint)
                            .frame(width: usable * CGFloat(part.kcal) / CGFloat(total))
                    }
                }
            }
            .frame(height: 10)
            HStack {
                ForEach(parts) { part in
                    HStack(spacing: 5) {
                        NutritionMacroDot(macro: part.macro, size: 7)
                        Text(verbatim: "\(part.macro.title.lowercased()) \(NutritionFormat.percentText(plan.shareOfIntake(part.kcal) ?? 0))")
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    if part.macro != .carbs { Spacer(minLength: 4) }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func goalsStepper(value: String, unit: String?, minus: LocalizedStringKey, plus: LocalizedStringKey,
                         canMinus: Bool, canPlus: Bool, step: @escaping (Bool) -> Void) -> some View {
        HStack(spacing: 2) {
            goalsStepButton(symbol: "minus", label: minus, enabled: canMinus) { step(false) }
            VStack(spacing: 0) {
                Text(verbatim: value)
                    .font(StrandFont.number(16))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let unit {
                    Text(verbatim: unit)
                        .font(StrandFont.overlineScaled(10))
                        .foregroundStyle(StrandPalette.textSecondary)
                }
            }
            .frame(width: 64)
            goalsStepButton(symbol: "plus", label: plus, enabled: canPlus) { step(true) }
        }
    }

    private func goalsStepButton(symbol: String, label: LocalizedStringKey, enabled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(StrandPalette.textPrimary)
                .frame(width: 44, height: 44)
                .background(StrandPalette.surfaceOverlay, in: Circle())
                .overlay(Circle().strokeBorder(StrandPalette.hairlineStrong, lineWidth: NoopMetrics.hairlineWidth))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(Text(label))
    }
}

extension NutritionGoals.ActivityLevel {
    /// "Lightly active".
    var levelTitle: String {
        switch self {
        case .sedentary: return String(localized: "Sedentary")
        case .light: return String(localized: "Lightly active")
        case .moderate: return String(localized: "Moderately active")
        case .active: return String(localized: "Very active")
        case .extreme: return String(localized: "Extremely active")
        }
    }

    /// "1 to 3 sessions a week".
    var levelHint: String {
        switch self {
        case .sedentary: return String(localized: "desk job, little or no sport")
        case .light: return String(localized: "1 to 3 sessions a week")
        case .moderate: return String(localized: "3 to 5 sessions a week")
        case .active: return String(localized: "6 to 7 sessions a week")
        case .extreme: return String(localized: "twice a day, or physical work")
        }
    }
}
