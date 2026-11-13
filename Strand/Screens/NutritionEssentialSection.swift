import SwiftUI
import StrandDesign

// MARK: - Nutrition, essential mode (personal fork, chantier 20)
//
// The day's four rings in the middle, their centre filling like a glass (the share of the intake goal
// eaten), what is left to eat in calories and in each macro, and one action: add a meal. Every figure is the
// day card's own (`NutritionBalanceModel`, `intakeRings`), so the two layouts cannot disagree.

struct NutritionEssentialSection: View {
    let model: NutritionBalanceModel
    /// The day, as the day picker writes it.
    var dayLine: String
    var animated: Bool
    var onAdd: () -> Void

    private static let ringsDiameter: CGFloat = 286
    private static let ringsLine: CGFloat = 20
    private static let ringsSpacing: CGFloat = 5

    /// The centre left free by the innermost ring.
    private var coreDiameter: CGFloat {
        let inner = Self.ringsDiameter - Self.ringsLine - 6 * (Self.ringsLine + Self.ringsSpacing)
        return max(40, inner - Self.ringsLine - 10)
    }

    /// The calories left to eat against the intake goal; negative past it; nil without a goal.
    private var kcalLeft: Int? {
        model.goalKcal.map { $0 - model.eaten.kcal }
    }

    var body: some View {
        VStack(spacing: 0) {
            EssentialHeader(caption: dayLine)
            Spacer(minLength: NoopMetrics.space3)
            ZStack {
                TodayConcentricRings(rings: model.intakeRings, diameter: Self.ringsDiameter,
                                     lineWidth: Self.ringsLine, spacing: Self.ringsSpacing,
                                     animated: animated, drawKey: "essential.nutrition.rings",
                                     allowsOverflow: true)
                EssentialGlassCore(diameter: coreDiameter, fill: model.intakeFill, tint: StrandPalette.intakeColor)
                centre
            }
            .frame(width: Self.ringsDiameter, height: Self.ringsDiameter)
            HStack(spacing: 4) {
                ForEach(NutritionMacro.allCases, id: \.self) { macro in
                    EssentialFigure(label: macro.title, tint: macro.tint, value: macroLeft(macro),
                                    unit: model.goal(macro) == nil ? nil : String(localized: "g to eat"))
                }
            }
            .padding(.top, NoopMetrics.space4)
            EssentialActionButton(title: "Add a meal", symbol: "plus", action: onAdd)
                .padding(.top, NoopMetrics.space4)
            Spacer(minLength: NoopMetrics.space3)
        }
        .frame(maxWidth: .infinity, minHeight: 600)
    }

    @ViewBuilder private var centre: some View {
        VStack(spacing: 0) {
            if let left = kcalLeft {
                Text(verbatim: NutritionFormat.whole(abs(left)))
                    .font(StrandFont.number(24, weight: .bold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .contentTransition(.numericText())
                Text(left >= 0 ? String(localized: "kcal left") : String(localized: "kcal over"))
                    .font(StrandFont.caption.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
            } else {
                Text(verbatim: NutritionFormat.whole(model.eaten.kcal))
                    .font(StrandFont.number(24, weight: .bold))
                    .foregroundStyle(StrandPalette.textPrimary)
                Text("kcal eaten")
                    .font(StrandFont.caption.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .frame(width: coreDiameter - 8)
        .accessibilityElement(children: .combine)
    }

    /// The grams of a macro left to eat against its goal (0 once reached), else the grams eaten.
    private func macroLeft(_ macro: NutritionMacro) -> String {
        let eaten = macro.grams(model.eaten)
        guard let goal = model.goal(macro) else { return NutritionFormat.grams(eaten) }
        return NutritionFormat.grams(max(0, Double(goal) - eaten))
    }
}
