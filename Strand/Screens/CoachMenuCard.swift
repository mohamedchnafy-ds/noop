import SwiftUI
import StrandDesign
import WhoopStore

/// The menu the Coach proposes for a day (personal fork, chantier 8, lot 3), on the meal card's template:
/// one row per meal (time, name, energy), the day's total in a boxed row, then "Add as planned"; once added,
/// "Planned in your journal" with "Undo". The meals go to the journal as planned, greyed and counted nowhere
/// until marked eaten. Every figure comes from the card's lines (Ciqual values for 100 g × the quantity).
struct CoachMenuCard: View {
    let proposal: CoachMenuProposal
    /// Running an action (the journal write): the buttons wait.
    let busy: Bool
    let onAdd: () -> Void
    let onUndo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Text(verbatim: NutritionFormat.longDay(proposal.dayDate))
                .font(StrandFont.sectionTitle)
                .foregroundStyle(StrandPalette.textPrimary)
                .padding(.top, 8)
                .fixedSize(horizontal: false, vertical: true)
            Text("Planned meals count nowhere until you mark them eaten.")
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textSecondary)
                .padding(.top, 2)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(proposal.meals.enumerated()), id: \.offset) { _, meal in
                    mealRow(meal)
                }
            }
            .padding(.top, 10)
            totalBox
                .padding(.top, 10)
            actions
                .padding(.top, 14)
        }
        .padding(16)
        .background(NoopPanelSurface(cornerRadius: NoopMetrics.cardRadius))
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        Label {
            Text("Proposed menu")
                .font(StrandFont.overline)
        } icon: {
            Image(systemName: "list.bullet.rectangle")
                .font(StrandFont.subhead.weight(.semibold))
        }
        .foregroundStyle(StrandPalette.accent)
    }

    private func mealRow(_ meal: CoachMealProposal) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(verbatim: NutritionFormat.mealClock(Date(timeIntervalSince1970: TimeInterval(meal.eatenAt))))
                .font(StrandFont.footnote.monospacedDigit())
                .foregroundStyle(StrandPalette.textSecondary)
                .frame(width: 44, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: meal.name)
                    .font(StrandFont.subhead.weight(.medium))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: NutritionFormat.macroLine(meal.totals))
                    .font(StrandFont.footnote.monospacedDigit())
                    .foregroundStyle(StrandPalette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: NutritionFormat.kcalUnit(meal.totals.kcal))
                .font(StrandFont.subhead.weight(.semibold).monospacedDigit())
                .foregroundStyle(StrandPalette.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }

    private var totalBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Day total")
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
            MealTotalsRow(total: proposal.totals)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StrandPalette.surfaceInset,
                    in: RoundedRectangle(cornerRadius: NoopVisualStyle.compactRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        HStack(spacing: 8) {
            if proposal.isAdded {
                Label("Planned in your journal", systemImage: "checkmark")
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(StrandPalette.accent)
                    .frame(maxWidth: .infinity, minHeight: 44)
                NoopButton("Undo", systemImage: "arrow.uturn.backward", kind: .secondary, fullWidth: true, action: onUndo)
                    .disabled(busy)
                    .fixedSize(horizontal: true, vertical: false)
            } else {
                NoopButton("Add as planned", systemImage: "calendar.badge.plus", kind: .primary, fullWidth: true,
                           action: onAdd)
                    .disabled(busy)
            }
        }
    }
}
