import SwiftUI
import StrandDesign
import WhoopStore

/// The meal the Coach proposes, as a card under its reply (personal fork, Nutrition mockups 5 and 6),
/// built on the session card's template: the foods with their quantity and energy, the meal's total in a
/// boxed row, then "Add to journal" and "Edit". Every figure comes from the card's lines through
/// `MealJournal` (Ciqual values for 100 g × the quantity); nothing is stored until a tap.
struct CoachMealCard: View {
    let proposal: CoachMealProposal
    /// Running an action (the journal write): the buttons wait.
    let busy: Bool
    let onAdd: () -> Void
    let onEdit: () -> Void

    var body: some View {
        let rows = proposal.itemRows
        VStack(alignment: .leading, spacing: 0) {
            header
            Text(proposal.name)
                .font(StrandFont.headline)
                .foregroundStyle(StrandPalette.textPrimary)
                .padding(.top, 6)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: summary)
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textSecondary)
                .padding(.top, 2)
                .fixedSize(horizontal: false, vertical: true)
            if proposal.isLabelProduct, let per100 = proposal.lines.first?.per100 {
                labelPer100Row(per100)
                    .padding(.top, 10)
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    lineRow(row)
                }
            }
            .padding(.top, 10)
            totalBox(MealMath.totals(rows.map(\.nutrients)))
                .padding(.top, 10)
            actions
                .padding(.top, 14)
        }
        .padding(16)
        .background(NoopPanelSurface(cornerRadius: 24))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(proposal.isLabelProduct ? Text("Product read from the label: \(proposal.name)")
                                                    : Text("Proposed meal: \(proposal.name)"))
    }

    // MARK: Parts

    private var header: some View {
        HStack {
            Label {
                headerTitle
                    .font(StrandFont.overline)
                    .tracking(2)
                    .textCase(.uppercase)
                    .foregroundStyle(StrandPalette.textSecondary)
            } icon: {
                Image(systemName: proposal.isLabelProduct ? "barcode" : "fork.knife")
                    .font(StrandFont.caption.weight(.semibold))
                    .foregroundStyle(StrandPalette.metricCyan)
            }
            Spacer(minLength: 8)
            Text(verbatim: NutritionFormat.mealClock(Date(timeIntervalSince1970: TimeInterval(proposal.eatenAt))))
                .font(StrandFont.captionNumber)
                .foregroundStyle(StrandPalette.textSecondary)
        }
    }

    private var headerTitle: Text {
        proposal.isLabelProduct ? Text("Product read from the label") : Text("Proposed meal")
    }

    /// The label's values for 100 g, as the Coach read them (Nutrition 4d): "PER 100 G 63 kcal · P 11 · …".
    private func labelPer100Row(_ per100: MealPer100) -> some View {
        HStack(spacing: 8) {
            Text("Per 100 g")
                .font(StrandFont.overlineScaled(11))
                .tracking(1.5)
                .textCase(.uppercase)
                .foregroundStyle(StrandPalette.textSecondary)
            Text(verbatim: NutritionFormat.per100Line(per100))
                .font(StrandFont.footnote.monospacedDigit())
                .foregroundStyle(StrandPalette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
    }

    /// "3 foods · quantities estimated from the photo · Ciqual"; for a product read from its label,
    /// "barcode 3017620422003 · label values".
    private var summary: String {
        if proposal.isLabelProduct {
            let values = String(localized: "label values")
            guard let barcode = proposal.barcode else { return values }
            return [NutritionFormat.barcodeLine(barcode), values].joined(separator: " · ")
        }
        let count = proposal.lines.count
        let foods = count == 1 ? String(localized: "1 food") : String(localized: "\(count) foods")
        let how: String
        if proposal.hasEstimate {
            how = String(localized: "quantities estimated from the photo")
        } else if proposal.origin == .voice {
            how = String(localized: "dictated quantities")
        } else {
            how = String(localized: "quantities you gave")
        }
        return [foods, how, "Ciqual"].joined(separator: " · ")
    }

    private func lineRow(_ row: MealItemRow) -> some View {
        HStack(spacing: 10) {
            Circle()
                .strokeBorder(StrandPalette.textTertiary, lineWidth: 1.5)
                .frame(width: 7, height: 7)
                .frame(width: 28)
                .accessibilityHidden(true)
            Text(verbatim: row.name)
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            quantityText(row) + Text(verbatim: NutritionFormat.kcalUnit(row.nutrients.kcal)).fontWeight(.semibold)
        }
        .font(StrandFont.subhead.monospacedDigit())
        .foregroundStyle(StrandPalette.textPrimary)
        .frame(minHeight: 30)
        .accessibilityElement(children: .combine)
    }

    /// "≈ 180 g · " for an estimated quantity, "180 g · " otherwise.
    private func quantityText(_ row: MealItemRow) -> Text {
        guard let grams = row.grams else { return Text(verbatim: "") }
        return Text(verbatim: NutritionFormat.portionGrams(grams, estimated: row.gramsEstimated) + " · ")
            .foregroundColor(StrandPalette.textSecondary)
    }

    private func totalBox(_ total: MealNutrients) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Meal total")
                .font(StrandFont.overline)
                .tracking(2)
                .textCase(.uppercase)
                .foregroundStyle(StrandPalette.textSecondary)
            MealTotalsRow(total: total)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(StrandPalette.surfaceInset, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(StrandPalette.hairline, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: 8) {
            if proposal.mealId == nil {
                NoopButton("Add to journal", systemImage: "plus", kind: .primary, fullWidth: true, action: onAdd)
                    .disabled(busy)
            } else {
                Label("In your journal", systemImage: "checkmark")
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(StrandPalette.accent)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            // Edit keeps its label at its own width; "Add to journal" takes the rest.
            NoopButton("Edit", systemImage: "pencil", kind: .secondary, fullWidth: true, action: onEdit)
                .disabled(busy)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}

/// A meal's energy and macros in four columns: kcal, protein, carbs, fat (the meal card, the barcode
/// scanner's product panel).
struct MealTotalsRow: View {
    let total: MealNutrients

    var body: some View {
        HStack(spacing: 4) {
            mealTotalValue(title: "kcal", value: NutritionFormat.whole(total.kcal), tint: StrandPalette.onDarkSecondary)
            // Short labels: four columns share the card's width ("PROTÉINES" would be cut).
            mealTotalValue(title: "Prot.", value: NutritionFormat.totalGramsText(total.proteinG),
                       tint: NutritionMacro.protein.tint)
            mealTotalValue(title: "Carb.", value: NutritionFormat.totalGramsText(total.carbsG),
                       tint: NutritionMacro.carbs.tint)
            mealTotalValue(title: "Fat", value: NutritionFormat.totalGramsText(total.fatG),
                       tint: NutritionMacro.fat.tint)
        }
    }

    private func mealTotalValue(title: LocalizedStringKey, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Circle().fill(tint).frame(width: 6, height: 6).accessibilityHidden(true)
                Text(title)
                    .font(StrandFont.overlineScaled(10))
                    .tracking(1)
                    .textCase(.uppercase)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .lineLimit(1)
            }
            Text(verbatim: value)
                .font(StrandFont.number(16))
                .foregroundStyle(StrandPalette.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
