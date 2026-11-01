import SwiftUI
import StrandDesign
import WhoopStore

// MARK: - Nutrition (personal fork, Nutrition mockup 1)
//
// One day of the meal journal: what was eaten against the intake goal, what the strap measured as spent,
// the balance, the three macros against their goals, then the meals in the order eaten. ‹ › moves a day;
// a meal opens its editor; a swipe to the left deletes it after a confirmation. Every number comes from
// `NutritionDaySummary` and `NutritionGoals`: nothing here computes a figure of its own.

struct NutritionView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore

    @AppStorage(MealJournal.revisionKey) private var mealRevision = 0
    @AppStorage(NutritionGoals.proteinTenthsKey) private var proteinTenths = NutritionGoals.defaultProteinTenths
    @AppStorage(NutritionGoals.fatTenthsKey) private var fatTenths = NutritionGoals.defaultFatTenths
    @AppStorage(NutritionGoals.goalPercentKey) private var goalPercent = NutritionGoals.defaultGoalPercent

    /// Days back from today (0 = today).
    @State private var dayOffset = 0
    @State private var summary: NutritionDaySummary?
    @State private var editor: NutritionEditorTarget?
    @State private var pendingDelete: MealEntry?
    @State private var showGoals = false

    /// How far back ‹ goes.
    private static let maxDaysBack = 730

    private var day: Date {
        let today = Calendar.current.startOfDay(for: Date())
        return Calendar.current.date(byAdding: .day, value: -dayOffset, to: today) ?? today
    }

    private var dayKey: String { Repository.localDayKey(day) }

    /// The summary of the day shown, or an empty one while it loads.
    private var shown: NutritionDaySummary {
        if let summary, summary.dayKey == dayKey { return summary }
        return NutritionDaySummary(dayKey: dayKey, meals: [], spent: nil)
    }

    private var plan: NutritionGoals.Plan {
        NutritionGoals.intakePlan(
            weightKg: profile.weightKg,
            proteinTenths: NutritionGoals.clampedTenths(proteinTenths, range: NutritionGoals.proteinTenthsRange,
                                                        fallback: NutritionGoals.defaultProteinTenths),
            fatTenths: NutritionGoals.clampedTenths(fatTenths, range: NutritionGoals.fatTenthsRange,
                                                    fallback: NutritionGoals.defaultFatTenths),
            goalPercent: NutritionGoals.clampedPercent(goalPercent),
            reference: NutritionDayReader.referenceBefore(repo))
    }

    var body: some View {
        let current = shown
        let meals = current.meals
        List {
            Group {
                header
                dayNavigator
                NutritionBalanceCard(model: NutritionBalanceModel(summary: current, plan: plan),
                                     onGoals: { showGoals = true })
                mealsTitle(count: meals.count)
            }
            .nutritionListRow()

            if meals.isEmpty {
                NutritionEmptyMeals()
                    .nutritionListRow()
            } else {
                ForEach(Array(meals.enumerated()), id: \.element.meal.id) { index, entry in
                    Button {
                        editor = .edit(entry)
                    } label: {
                        NutritionMealRow(entry: entry, isFirst: index == 0, isLast: index == meals.count - 1)
                    }
                    .buttonStyle(.plain)
                    .nutritionListRow(vertical: 0)
                    // No destructive role: the row stays until the deletion is confirmed.
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            pendingDelete = entry
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .tint(StrandPalette.statusCritical)
                    }
                    .contextMenu {
                        Button {
                            editor = .edit(entry)
                        } label: {
                            Label("Edit meal", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            pendingDelete = entry
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                Text("Swipe a meal to the left to delete it. “estimate” = quantities estimated from a photo; calories and macros are always calculated by the app.")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .nutritionListRow()
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 1)
        .background(StrandPalette.surfaceBase.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            NoopButton("Add a meal", systemImage: "plus", kind: .primary, fullWidth: true) {
                editor = .add
            }
            .padding(.horizontal, NoopMetrics.screenHPadding)
            .padding(.bottom, NoopMetrics.space2)
        }
        .navigationDestination(isPresented: $showGoals) { NutritionGoalsView() }
        .task(id: "\(dayKey)-\(mealRevision)-\(repo.refreshSeq)") {
            let read = await NutritionDayReader.readDay(repo, profile: profile, day: day)
            if read.dayKey == dayKey { self.summary = read }
        }
        .sheet(item: $editor) { target in
            NutritionMealEditor(target: target, day: day)
        }
        .confirmationDialog("Delete this meal?",
                            isPresented: Binding(get: { pendingDelete != nil },
                                                 set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible,
                            presenting: pendingDelete) { entry in
            Button("Delete", role: .destructive) { delete(entry) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("It is removed from your journal.")
        }
    }

    // MARK: Parts

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Nutrition")
                .font(StrandFont.rounded(28))
                .foregroundStyle(StrandPalette.textPrimary)
            Spacer(minLength: 0)
            Button { showGoals = true } label: {
                Image(systemName: "target")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(StrandPalette.surfaceRaised, in: Circle())
                    .overlay(Circle().strokeBorder(StrandPalette.hairline, lineWidth: NoopMetrics.hairlineWidth))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Nutrition goals"))
        }
        .padding(.top, 8)
    }

    private var dayNavigator: some View {
        HStack {
            journalDayButton(symbol: "chevron.left", label: "Previous day", enabled: dayOffset < Self.maxDaysBack) {
                dayOffset += 1
            }
            Spacer(minLength: 4)
            Text(verbatim: dayLabel)
                .font(StrandFont.subhead.weight(.semibold))
                .foregroundStyle(StrandPalette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            journalDayButton(symbol: "chevron.right", label: "Next day", enabled: dayOffset > 0) {
                dayOffset -= 1
            }
        }
    }

    private var dayLabel: String {
        let date = NutritionFormat.longDay(day)
        switch dayOffset {
        case 0: return String(localized: "Today · \(date)")
        case 1: return String(localized: "Yesterday · \(date)")
        default: return date
        }
    }

    private func journalDayButton(symbol: String, label: LocalizedStringKey, enabled: Bool,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(StrandPalette.textSecondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(Text(label))
    }

    private func mealsTitle(count: Int) -> some View {
        HStack {
            Text("Meals").strandOverline()
            Spacer()
            if count > 0 {
                Text(count == 1 ? String(localized: "1 meal") : String(localized: "\(count) meals"))
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
        }
        .padding(.top, 14)
        .padding(.horizontal, 4)
    }

    private func delete(_ entry: MealEntry) {
        Task {
            guard let store = await repo.storeHandle() else { return }
            try? await MealJournal.removeMeal(store, id: entry.meal.id)
        }
    }
}

/// What the journal's top card shows, already resolved.
struct NutritionBalanceModel: Equatable {
    var eaten: MealNutrients
    var goalKcal: Int?
    var spentKcal: Int?
    var balanceKcal: Int?
    var proteinGoalG: Int?
    var carbsGoalG: Int?
    var fatGoalG: Int?

    init(eaten: MealNutrients, goalKcal: Int?, spentKcal: Int?, balanceKcal: Int?,
         proteinGoalG: Int?, carbsGoalG: Int?, fatGoalG: Int?) {
        self.eaten = eaten
        self.goalKcal = goalKcal
        self.spentKcal = spentKcal
        self.balanceKcal = balanceKcal
        self.proteinGoalG = proteinGoalG
        self.carbsGoalG = carbsGoalG
        self.fatGoalG = fatGoalG
    }

    init(summary: NutritionDaySummary, plan: NutritionGoals.Plan) {
        self.init(eaten: summary.eaten, goalKcal: plan.intakeKcal,
                  spentKcal: summary.spent.map { Int($0.totalKcal.rounded()) },
                  balanceKcal: summary.balanceKcal,
                  proteinGoalG: plan.proteinG > 0 ? plan.proteinG : nil,
                  carbsGoalG: plan.carbsG,
                  fatGoalG: plan.fatG > 0 ? plan.fatG : nil)
    }

    func goal(_ macro: NutritionMacro) -> Int? {
        switch macro {
        case .protein: return proteinGoalG
        case .carbs: return carbsGoalG
        case .fat: return fatGoalG
        }
    }
}

/// The day's intake card: the big gauge, goal / spent / balance, then the three macros.
struct NutritionBalanceCard: View {
    let model: NutritionBalanceModel
    var onGoals: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            NutritionIntakeGauge(eatenKcal: model.eaten.kcal, goalKcal: model.goalKcal)
            HStack(alignment: .top, spacing: 4) {
                stat(String(localized: "Goal"), model.goalKcal.map(NutritionFormat.whole))
                stat(String(localized: "Spent"), model.spentKcal.map(NutritionFormat.whole))
                stat(String(localized: "Net"), model.balanceKcal.map(NutritionFormat.signedKcal))
            }
            .padding(.top, 10)
            Rectangle()
                .fill(StrandPalette.hairline)
                .frame(height: NoopMetrics.hairlineWidth)
                .padding(.top, 14)
            Button(action: onGoals) {
                HStack(alignment: .top, spacing: 4) {
                    ForEach(NutritionMacro.allCases, id: \.self) { macro in
                        macroGauge(macro)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
        }
        .padding(.top, 18)
        .padding(.horizontal, 12)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        .background(NoopPanelSurface(cornerRadius: 28, elevated: true))
    }

    private func stat(_ title: String, _ value: String?) -> some View {
        VStack(spacing: 3) {
            Text(title.uppercased())
                .font(StrandFont.overlineScaled(11))
                .tracking(1.5)
                .foregroundStyle(StrandPalette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let value {
                Text(verbatim: value)
                    .font(StrandFont.number(17))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Text("no data")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func macroGauge(_ macro: NutritionMacro) -> some View {
        let eaten = macro.grams(model.eaten)
        let goal = model.goal(macro)
        let scale = max(Double(goal ?? 0), eaten)
        let fill = scale > 0 && goal != nil ? eaten / scale : 0
        let mark: Double? = {
            guard let goal, goal > 0, eaten > Double(goal) else { return nil }
            return Double(goal) / scale
        }()
        return VStack(spacing: 5) {
            HStack(spacing: 5) {
                NutritionMacroDot(macro: macro)
                Text(macro.title.uppercased())
                    .font(StrandFont.overlineScaled(10.5))
                    .tracking(1.2)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            TodayHalfGauge(parts: [TodayHalfGauge.Part(from: 0, to: fill, color: macro.tint)],
                           goalMark: mark, value: NutritionFormat.grams(eaten), unit: "g")
            if let goal {
                Text("out of \(Text(verbatim: NutritionFormat.gramsUnit(goal)).foregroundColor(StrandPalette.textPrimary).fontWeight(.semibold))")
                    .font(StrandFont.overlineScaled(11))
                    .foregroundStyle(StrandPalette.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(goal.map {
            String(localized: "\(macro.title): \(NutritionFormat.grams(eaten)) g of a \(NutritionFormat.whole($0)) g goal")
        } ?? String(localized: "\(macro.title): \(NutritionFormat.grams(eaten)) g")))
    }
}

/// One meal in the day's list: its origin, name, time and macros, and its energy. Consecutive rows read
/// as one card: the first is rounded at the top, the last at the bottom, a hairline between them.
struct NutritionMealRow: View {
    let entry: MealEntry
    let isFirst: Bool
    let isLast: Bool

    private static let radius: CGFloat = 26

    var body: some View {
        HStack(spacing: 14) {
            NutritionOriginIcon(origin: entry.meal.origin)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: NutritionFormat.mealTitle(entry))
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .lineLimit(1)
                Text(verbatim: NutritionFormat.mealDetail(entry))
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: NutritionFormat.mealKcal(entry))
                .font(StrandFont.number(16))
                .foregroundStyle(StrandPalette.textPrimary)
                .monospacedDigit()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(StrandPalette.textTertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 64)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: isFirst ? Self.radius : 0,
                                   bottomLeadingRadius: isLast ? Self.radius : 0,
                                   bottomTrailingRadius: isLast ? Self.radius : 0,
                                   topTrailingRadius: isFirst ? Self.radius : 0,
                                   style: .continuous)
                .fill(NoopVisualStyle.surface)
        )
        .overlay(alignment: .top) {
            if !isFirst {
                Rectangle()
                    .fill(StrandPalette.hairline)
                    .frame(height: NoopMetrics.hairlineWidth)
                    .padding(.horizontal, 16)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Opens the meal to edit it"))
    }
}

/// The journal of a day with no meal yet.
struct NutritionEmptyMeals: View {
    var body: some View {
        NoopCard {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "fork.knife")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(StrandPalette.onDarkSecondary)
                    .frame(width: 34, height: 34)
                    .background(StrandPalette.onDarkSecondary.opacity(0.14), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("No meals this day")
                        .font(StrandFont.headline)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text("Add what you eat by hand, again from your recent meals, or from a photo with the Coach. The app calculates the calories and macros.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private extension View {
    /// A row of the journal's list: no separator, no row background, the page's side margins.
    func nutritionListRow(vertical: CGFloat = 6) -> some View {
        self
            .listRowInsets(EdgeInsets(top: vertical, leading: NoopMetrics.screenHPadding,
                                      bottom: vertical, trailing: NoopMetrics.screenHPadding))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}
