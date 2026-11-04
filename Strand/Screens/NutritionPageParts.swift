import SwiftUI
import StrandDesign
import WhoopStore

// MARK: - Nutrition by moment: the parts of the page (fork chantier 9, mockup 4)
//
// The search field at the top, the header of each moment (its total, macros, share of the day and "+"),
// the week card that opens the History screen, and « Customize Nutrition ». Pure views fed by the screen
// (and the render test); the figures come from `NutritionSlots`, `NutritionHistoryModel` and the plan.

/// The search field at the top of Nutrition: a tap opens the add sheet with the keyboard up; the barcode
/// button opens the scanner. A nil scan hides the button (no camera on the Mac).
struct NutritionSearchBar: View {
    let onSearch: () -> Void
    var onScan: (() -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onSearch) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(StrandFont.subhead.weight(.semibold))
                        .accessibilityHidden(true)
                    Text("Search a food")
                        .font(StrandFont.body)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .foregroundStyle(StrandPalette.textSecondary)
                .frame(height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if let onScan {
                Button(action: onScan) {
                    Image(systemName: "barcode.viewfinder")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(StrandPalette.accent)
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Scan a barcode"))
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .background(NoopVisualStyle.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// The head of one moment: a grey dot, its name, its total, a "+"; with meals, the macros and its share of
/// the day on a band under it. A tap on the name unfolds the meals (rows of their own under it).
struct NutritionSlotHeader: View {
    let group: NutritionSlotGroup
    let goalKcal: Int?
    /// The meals are unfolded under it: the card goes on below, so its bottom corners stay square.
    let expanded: Bool
    let onToggle: () -> Void
    let onAdd: () -> Void

    private static let radius = NoopMetrics.cardRadius

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: Self.radius, bottomLeadingRadius: expanded ? 0 : Self.radius,
                               bottomTrailingRadius: expanded ? 0 : Self.radius, topTrailingRadius: Self.radius,
                               style: .continuous)
    }

    /// What a tap on the name does, for VoiceOver.
    private var toggleHint: Text {
        if !group.hasMeals { return Text(verbatim: "") }
        if expanded { return Text("Folds the meals") }
        return Text("Shows the meals")
    }

    var body: some View {
        let totals = group.totals
        let title = NutritionSlot.slotTitle(group.slot)
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Circle()
                    .fill(StrandPalette.textTertiary)
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
                Button(action: onToggle) {
                    HStack(spacing: 8) {
                        Text(verbatim: title)
                            .font(StrandFont.body.weight(.semibold))
                            .foregroundStyle(StrandPalette.textPrimary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if group.hasMeals {
                            VStack(alignment: .trailing, spacing: 0) {
                                Text(verbatim: NutritionFormat.whole(totals.kcal))
                                    .font(StrandFont.rounded(18, weight: .bold))
                                    .foregroundStyle(StrandPalette.textPrimary)
                                    .monospacedDigit()
                                Text(verbatim: "kcal")
                                    .font(StrandFont.caption)
                                    .foregroundStyle(StrandPalette.textSecondary)
                            }
                            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(StrandPalette.textTertiary)
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(minHeight: 58)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!group.hasMeals)
                .accessibilityElement(children: .combine)
                .accessibilityHint(toggleHint)
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(StrandPalette.intakeColor)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Add to \(title)"))
            }
            .padding(.leading, 14)
            .padding(.trailing, 6)
            if group.hasMeals {
                HStack(spacing: 8) {
                    Text(verbatim: NutritionFormat.macroLine(totals))
                        .foregroundStyle(StrandPalette.textPrimary.opacity(0.8))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 4)
                    if let share = group.shareOfGoal(goalKcal) {
                        Text(verbatim: String(localized: "\(NutritionFormat.percentText(share)) of the day"))
                            .foregroundStyle(StrandPalette.textSecondary)
                            .lineLimit(1)
                    }
                }
                .font(StrandFont.footnote)
                .monospacedDigit()
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(StrandPalette.surfaceOverlay)
            }
        }
        .background(NoopVisualStyle.surface)
        .clipShape(shape)
    }
}

/// « This week »: the average of the logged days and a bar per day (the 7 complete days before today)
/// against the intake goal (dashed); a day with no meal stays a grey stub, never a 0. A tap opens History.
struct NutritionWeekCard: View {
    let model: NutritionHistoryModel
    var loading = false
    let onOpen: () -> Void

    private static let barsHeight: CGFloat = 56

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("This week")
                        .font(StrandFont.body.weight(.semibold))
                        .foregroundStyle(StrandPalette.textPrimary)
                    Spacer(minLength: 8)
                    (Text("History") + Text(verbatim: " ›"))
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.accent)
                }
                HStack(alignment: .bottom, spacing: 16) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Average")
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textSecondary)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(verbatim: model.averageKcal.map(NutritionFormat.whole) ?? "\u{2014}")
                                .font(StrandFont.number(26, weight: .bold))
                                .foregroundStyle(StrandPalette.textPrimary)
                                .monospacedDigit()
                            Text(verbatim: "kcal")
                                .font(StrandFont.footnote)
                                .foregroundStyle(StrandPalette.textSecondary)
                        }
                    }
                    .fixedSize()
                    bars
                }
                if !loading, model.loggedDays.isEmpty {
                    Text("No meal written down over these days.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NoopPanelSurface(cornerRadius: NoopMetrics.cardRadius))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Opens the history"))
    }

    /// The scale of the bars: the goal or the biggest day, whichever is higher.
    private var scale: Double {
        let biggest = model.days.compactMap { $0.eaten?.kcal }.max() ?? 0
        return Double(max(model.goalKcal ?? 0, biggest, 1))
    }

    private var bars: some View {
        let height = Self.barsHeight
        return HStack(alignment: .bottom, spacing: 6) {
            ForEach(model.days) { day in
                if let eaten = day.eaten {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(StrandPalette.intakeColor)
                        .frame(height: max(4, height * CGFloat(Double(eaten.kcal) / scale)))
                } else {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(StrandPalette.surfaceOverlay)
                        .frame(height: 4)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height, alignment: .bottom)
        .overlay(alignment: .bottom) {
            if let goal = model.goalKcal, goal > 0 {
                NutritionDashLine()
                    .stroke(StrandPalette.textSecondary, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .frame(height: 1)
                    .offset(y: -height * CGFloat(Double(goal) / scale))
            }
        }
        .accessibilityHidden(true)
    }
}

/// A horizontal line across its frame, for a dashed goal.
struct NutritionDashLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

/// The History screen: the card of chantier 8 (eaten, macros, balance) over 7 or 30 complete days.
struct NutritionHistoryScreen: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @AppStorage(MealJournal.revisionKey) private var mealRevision = 0

    @State private var range: NutritionHistoryRange = .week
    @State private var loaded: (range: NutritionHistoryRange, days: [NutritionHistoryDay])?

    var body: some View {
        ScreenScaffold(title: "History") {
            NutritionHistoryCard(model: NutritionHistoryModel(days: loaded?.days ?? [],
                                                              plan: NutritionDayReader.currentPlan(profile: profile)),
                                 range: range, onRange: { range = $0 }, loading: loaded?.range != range)
        }
        .task(id: "\(range.rawValue)-\(mealRevision)-\(Repository.localDayKey(Date()))") {
            let asked = range
            let days = await NutritionHistory.loadNutritionHistory(repo, profile: profile, range: asked)
            if !Task.isCancelled { loaded = (asked, days) }
        }
    }
}

/// « Customize Nutrition »: what is put back on the page. The Blood markers card (off by default) stays
/// in More → Health → Lab Book whatever the switch.
struct NutritionCustomizeSheet: View {
    @Binding var labCardShown: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: $labCardShown) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Blood markers")
                                .font(StrandFont.body)
                            Text("Your latest Lab Book values, under the week.")
                                .font(StrandFont.caption)
                                .foregroundStyle(StrandPalette.textSecondary)
                        }
                    }
                    .tint(StrandPalette.switchOn)
                } header: {
                    Text("Put back on the page")
                } footer: {
                    Text("It is always in More → Health and recovery → Lab Book.")
                }
            }
            .navigationTitle(Text("Customize Nutrition"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #endif
    }
}
