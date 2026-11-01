import SwiftUI
import StrandDesign

// MARK: - Nutrition goals (personal fork, Nutrition mockup 3)
//
// Every goal spelled out with its formula and the wearer's own numbers: the basal metabolic rate, the
// expenditure the strap measured on the last complete days, the intake goal from the chosen percentage,
// protein and fat from grams per kilogram, carbohydrates from what is left. The numbers come from
// `NutritionGoals`; this screen only writes them out and moves the three settings.

struct NutritionGoalsView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore

    @AppStorage(NutritionGoals.proteinTenthsKey) private var proteinTenthsRaw = NutritionGoals.defaultProteinTenths
    @AppStorage(NutritionGoals.fatTenthsKey) private var fatTenthsRaw = NutritionGoals.defaultFatTenths
    @AppStorage(NutritionGoals.goalPercentKey) private var goalPercentRaw = NutritionGoals.defaultGoalPercent

    var body: some View {
        ScreenScaffold(title: "Goals",
                       subtitle: "Calculated from your profile and the energy the strap measured.") {
            NutritionGoalsContent(
                wearer: NutritionGoals.Body(sex: profile.sex, weightKg: profile.weightKg, heightCm: profile.heightCm,
                                            age: Double(profile.age)),
                age: profile.age, weightKg: profile.weightKg,
                reference: NutritionDayReader.referenceBefore(repo),
                proteinTenthsRaw: $proteinTenthsRaw, fatTenthsRaw: $fatTenthsRaw, goalPercentRaw: $goalPercentRaw)
        }
    }
}

/// The Goals screen's content, from the profile, the reference expenditure and the three settings.
struct NutritionGoalsContent: View {
    let wearer: NutritionGoals.Body
    let age: Int
    /// The profile's weight as stored, which the macro goals multiply.
    let weightKg: Double
    let reference: NutritionGoals.Reference?
    @Binding var proteinTenthsRaw: Int
    @Binding var fatTenthsRaw: Int
    @Binding var goalPercentRaw: Int

    private enum Direction: Hashable { case lose, maintain, gain }

    private var proteinTenths: Int {
        NutritionGoals.clampedTenths(proteinTenthsRaw, range: NutritionGoals.proteinTenthsRange,
                                     fallback: NutritionGoals.defaultProteinTenths)
    }
    private var fatTenths: Int {
        NutritionGoals.clampedTenths(fatTenthsRaw, range: NutritionGoals.fatTenthsRange,
                                     fallback: NutritionGoals.defaultFatTenths)
    }
    private var goalPercent: Int { NutritionGoals.clampedPercent(goalPercentRaw) }

    private var plan: NutritionGoals.Plan {
        NutritionGoals.intakePlan(weightKg: weightKg, proteinTenths: proteinTenths, fatTenths: fatTenths,
                                  goalPercent: goalPercent, reference: reference)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
            goalsSection("Your profile") { profileRow }
            goalsSection("Calories") { caloriesCard }
            goalsSection("Macros") { macrosCard }
            Text("Calories per gram: 4 for protein and carbs, 9 for fat. Everything is recalculated when your weight or your average expenditure changes.")
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
    }

    private func goalsSection<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).strandOverline()
            content()
        }
    }

    // MARK: Profile

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

    private var profileRow: some View {
        NavigationLink {
            SettingsView()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "person")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(StrandPalette.onDarkSecondary)
                    .frame(width: 34, height: 34)
                    .background(StrandPalette.onDarkSecondary.opacity(0.14), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: profileSummary)
                        .font(StrandFont.body)
                        .foregroundStyle(StrandPalette.textPrimary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text("Profile, the same one the calories burned use")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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
    }

    // MARK: Calories

    private var caloriesCard: some View {
        let basal = NutritionGoals.basalKcalPerDay(wearer)
        let formula = NutritionGoals.basalFormula(sex: wearer.sex)
        return VStack(alignment: .leading, spacing: 0) {
            goalsLine(title: "Basal metabolic rate",
                 value: NutritionFormat.kcalUnit(Int(basal.rounded())),
                 detail: String(localized: "Revised Harris-Benedict: \(basalFormulaText(formula))"))
            divider
            if let reference {
                goalsLine(title: "Average expenditure",
                     value: NutritionFormat.kcalUnit(Int(reference.kcal.rounded())),
                     detail: String(localized: "measured over the last \(reference.days) complete days: resting (formula above) + activity (Keytel 2005, from your heart rate)"))
            } else {
                goalsLine(title: "Average expenditure", value: nil,
                     detail: String(localized: "Needs at least \(NutritionGoals.referenceMinDays) complete days measured by the strap."))
            }
            divider
            goalPicker
            resultBox
                .padding(.top, 4)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 16)
        .background(NoopPanelSurface(cornerRadius: 26))
    }

    /// "88,362 + 13,397 × 80 + 4,799 × 178 − 5,677 × 30".
    private func basalFormulaText(_ f: NutritionGoals.BasalFormula) -> String {
        let c = NutritionFormat.coefficient
        return "\(c(f.alpha)) + \(c(f.perKg)) × \(NutritionFormat.editable(wearer.weightKg)) + \(c(f.perCm)) × \(NutritionFormat.whole(Int(wearer.heightCm.rounded()))) \u{2212} \(c(f.perYear)) × \(NutritionFormat.whole(Int(wearer.age.rounded())))"
    }

    private var divider: some View {
        Rectangle().fill(StrandPalette.hairline).frame(height: NoopMetrics.hairlineWidth)
    }

    private func goalsLine(title: LocalizedStringKey, value: String?, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.textPrimary)
                Spacer(minLength: 8)
                if let value {
                    Text(verbatim: value)
                        .font(StrandFont.number(16))
                        .foregroundStyle(StrandPalette.textPrimary)
                        .monospacedDigit()
                } else {
                    Text("no data")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
            }
            Text(verbatim: detail)
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private var direction: Direction {
        goalPercent < 0 ? .lose : (goalPercent > 0 ? .gain : .maintain)
    }

    private var directionBinding: Binding<Direction> {
        Binding(get: { direction }, set: { next in
            switch next {
            case .lose: goalPercentRaw = goalPercent < 0 ? goalPercent : -10
            case .maintain: goalPercentRaw = 0
            case .gain: goalPercentRaw = goalPercent > 0 ? goalPercent : 10
            }
        })
    }

    private var goalPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Goal")
                .font(StrandFont.body)
                .foregroundStyle(StrandPalette.textPrimary)
            SegmentedPillControl([Direction.lose, .maintain, .gain], selection: directionBinding,
                                 fillsAvailableWidth: true) { item in
                switch item {
                case .lose:
                    return String(localized: "Lose \(NutritionFormat.signedPercent(goalPercent < 0 ? goalPercent : -10))")
                case .maintain:
                    return String(localized: "Maintenance")
                case .gain:
                    return String(localized: "Gain \(NutritionFormat.signedPercent(goalPercent > 0 ? goalPercent : 10))")
                }
            }
            if goalPercent != 0 {
                HStack(spacing: 8) {
                    Text("Deficit or surplus")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                    Spacer()
                    goalsStepper(value: NutritionFormat.signedPercent(goalPercent), unit: nil,
                            minus: "Decrease the percentage", plus: "Increase the percentage",
                            canMinus: abs(goalPercent) > NutritionGoals.goalPercentStep,
                            canPlus: abs(goalPercent) < NutritionGoals.goalPercentRange.upperBound) { up in
                        let magnitude = abs(goalPercent) + (up ? 1 : -1) * NutritionGoals.goalPercentStep
                        goalPercentRaw = NutritionGoals.clampedPercent(goalPercent < 0 ? -magnitude : magnitude)
                    }
                }
            }
            Text("percentage adjustable in steps of \(NutritionFormat.percentText(NutritionGoals.goalPercentStep))")
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
        }
        .padding(.vertical, 12)
    }

    private var resultBox: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Intake goal")
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                Spacer(minLength: 8)
                if let intake = plan.intakeKcal {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(verbatim: NutritionFormat.whole(intake))
                            .font(StrandFont.number(24, weight: .bold))
                            .foregroundStyle(StrandPalette.textPrimary)
                            .monospacedDigit()
                        Text(verbatim: "kcal")
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                } else {
                    Text("no data")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
            }
            if let reference, plan.intakeKcal != nil {
                let raw = reference.kcal * (1 + Double(goalPercent) / 100)
                Text(verbatim: String(localized: "\(NutritionFormat.whole(Int(reference.kcal.rounded()))) × \(NutritionFormat.factor(goalPercent)) = \(NutritionFormat.whole(Int(raw.rounded()))), rounded to 10"))
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(StrandPalette.surfaceInset, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(StrandPalette.hairline, lineWidth: NoopMetrics.hairlineWidth))
        .accessibilityElement(children: .combine)
    }

    // MARK: Macros

    private var macrosCard: some View {
        let plan = plan
        let weight = NutritionFormat.editable(weightKg)
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
            if let intake = plan.intakeKcal, intake > 0, let carbsKcal = plan.carbsKcal {
                shareBar(plan, carbsKcal: carbsKcal)
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
        let detail: String = {
            guard let intake = plan.intakeKcal, let carbsKcal = plan.carbsKcal else {
                return String(localized: "the energy left once the intake goal is known")
            }
            return "(\(NutritionFormat.whole(intake)) \u{2212} \(NutritionFormat.whole(plan.proteinKcal)) \u{2212} \(NutritionFormat.whole(plan.fatKcal))) ÷ 4 · \(NutritionFormat.whole(carbsKcal)) kcal"
        }()
        return HStack(spacing: 12) {
            NutritionMacroDot(macro: .carbs, size: 10)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: NutritionMacro.carbs.title)
                        .font(StrandFont.body)
                        .foregroundStyle(StrandPalette.textPrimary)
                    if let carbs = plan.carbsG {
                        Text(verbatim: NutritionFormat.gramsUnit(carbs))
                            .font(StrandFont.number(16))
                            .foregroundStyle(StrandPalette.textPrimary)
                            .monospacedDigit()
                    }
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

    private func shareBar(_ plan: NutritionGoals.Plan, carbsKcal: Int) -> some View {
        let parts = [SharePart(macro: .protein, kcal: plan.proteinKcal), SharePart(macro: .fat, kcal: plan.fatKcal),
                     SharePart(macro: .carbs, kcal: carbsKcal)]
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
                if let unit {
                    Text(verbatim: unit)
                        .font(StrandFont.overlineScaled(10))
                        .foregroundStyle(StrandPalette.textSecondary)
                }
            }
            .frame(width: 58)
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
