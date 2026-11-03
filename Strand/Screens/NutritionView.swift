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
    /// The Coach whose key the Photo and Dictate tiles use, and the label reading of the scanner.
    @EnvironmentObject private var coach: AICoachEngine
    @EnvironmentObject private var router: NavRouter

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
    // Personal fork, Nutrition 4d: the barcode scanner, opened once the editor sheet has closed, and
    // what to open after it closes (the editor for "Enter by hand", the Coach for a label photo).
    @State private var scannerRequested = false
    @State private var showScanner = false
    @State private var scannerExit: ScannerExit?
    // Personal fork: Dictate and Photo open the capture sheet once the editor has closed, and its
    // proposal opens back in the editor, every quantity editable, once the capture sheet has closed.
    @State private var captureRequested: NutritionCaptureMode?
    @State private var capture: NutritionCaptureMode?
    @State private var capturedDraft: MealEntry?

    private enum ScannerExit {
        case manual, coach
    }

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
                NutritionBalanceCard(model: NutritionBalanceModel(summary: current, plan: plan),
                                     onGoals: { showGoals = true })
                // Fork chantier 7 (design F): the four ways to add a meal, straight from the screen.
                NutritionAddTiles(onType: { editor = .add },
                                  onScan: barcodeScannerAvailable ? { showScanner = true } : nil,
                                  onPhoto: coach.canEstimateMeals ? { capture = .photo } : nil,
                                  onDictate: coach.canEstimateMeals ? { capture = .voice } : nil)
                    .padding(.top, NoopMetrics.space2)
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
                Text("Swipe a meal to the left to delete it. “estimate” = quantities estimated from a photo; calories and macros are always calculated by the app. Food values: \(CiqualTable.attribution)")
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
        .navigationDestination(isPresented: $showGoals) { NutritionGoalsView() }
        .task(id: "\(dayKey)-\(mealRevision)-\(repo.refreshSeq)") {
            await NutritionSeries.backfillNutritionSeriesIfNeeded(repo)
            let read = await NutritionDayReader.readDay(repo, profile: profile, day: day)
            if read.dayKey == dayKey { self.summary = read }
        }
        .sheet(item: $editor, onDismiss: openRequestedScanner) { target in
            NutritionMealEditor(target: target, day: day,
                                onBarcode: barcodeScannerAvailable ? { scannerRequested = true } : nil,
                                onPhoto: coach.canEstimateMeals ? { captureRequested = .photo } : nil,
                                onDictate: coach.canEstimateMeals ? { captureRequested = .voice } : nil)
                .environmentObject(repo)
        }
        .sheet(item: $capture, onDismiss: openCapturedDraft) { mode in
            NutritionMealCaptureSheet(mode: mode) { proposal in capturedDraft = proposal.draftEntry() }
                .environmentObject(coach)
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showScanner, onDismiss: afterScanner) {
            NutritionBarcodeScanner(day: day, canReadLabel: coachTakesPhotos,
                                    onManual: { scannerExit = .manual; showScanner = false },
                                    onLabelSent: { scannerExit = .coach; showScanner = false })
                .environmentObject(repo)
                .environmentObject(coach)
        }
        #endif
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

    /// Fork chantier 7: the day in 13 semibold grey capitals over the title in 34 bold; ‹ › and the goals
    /// on the right as round glass buttons (the day is named once, here).
    private var header: some View {
        HStack(alignment: .bottom, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: dayLabel)
                    .font(StrandFont.overline)
                    .textCase(.uppercase)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("Nutrition")
                    .font(StrandFont.screenTitle)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 0)
            journalHeaderButton(symbol: "chevron.left", label: "Previous day", enabled: dayOffset < Self.maxDaysBack) {
                dayOffset += 1
            }
            journalHeaderButton(symbol: "chevron.right", label: "Next day", enabled: dayOffset > 0) {
                dayOffset -= 1
            }
            journalHeaderButton(symbol: "target", label: "Nutrition goals", enabled: true) {
                showGoals = true
            }
        }
        .padding(.top, 8)
    }

    private var dayLabel: String {
        let date = NutritionFormat.longDay(day)
        switch dayOffset {
        case 0: return String(localized: "Today · \(date)")
        case 1: return String(localized: "Yesterday · \(date)")
        default: return date
        }
    }

    /// A round header button: a Liquid Glass circle on iOS, a flat surface circle elsewhere. A plain button
    /// with the glass on its label, so the three buttons of the List row stay separate taps.
    private func journalHeaderButton(symbol: String, label: LocalizedStringKey, enabled: Bool,
                                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            journalHeaderCircle(
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .frame(width: NoopMetrics.compactControlSize, height: NoopMetrics.compactControlSize)
            )
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(Text(label))
    }

    @ViewBuilder
    private func journalHeaderCircle<Content: View>(_ content: Content) -> some View {
        #if os(iOS)
        content.nativeLiquidGlassCircleFinish()
        #else
        content.background(StrandPalette.surfaceRaised, in: Circle())
        #endif
    }

    /// "Meals" in 20 bold (fork chantier 7), the count on the right.
    private func mealsTitle(count: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Meals")
                .font(StrandFont.sectionTitle)
                .foregroundStyle(StrandPalette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if count > 0 {
                Text(count == 1 ? String(localized: "1 meal") : String(localized: "\(count) meals"))
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
        }
        .padding(.top, 14)
        .padding(.horizontal, 2)
    }

    /// The Coach is on, connected, and its provider reads photos (Anthropic).
    private var coachTakesPhotos: Bool {
        CoachBriefScheduler.coachMasterEnabled && coach.isConfigured && coach.provider == .anthropic
    }

    /// The barcode scanner is the iPhone's camera.
    private var barcodeScannerAvailable: Bool {
        #if os(iOS)
        return true
        #else
        return false
        #endif
    }

    /// A tile closed the editor: open the scanner or the capture sheet now that the sheet is gone.
    private func openRequestedScanner() {
        if let mode = captureRequested {
            captureRequested = nil
            capture = mode
            return
        }
        guard scannerRequested else { return }
        scannerRequested = false
        showScanner = true
    }

    /// The capture sheet closed on a proposal: open it in the editor, as a meal not saved yet.
    private func openCapturedDraft() {
        guard let draft = capturedDraft else { return }
        capturedDraft = nil
        editor = .draft(draft)
    }

    /// The scanner closed on "Enter by hand" (the editor opens) or on a label sent to the Coach.
    private func afterScanner() {
        let exit = scannerExit
        scannerExit = nil
        switch exit {
        case .manual?: editor = .add
        case .coach?: router.openCoach()
        case nil: break
        }
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
    /// The day's measured expenditure split (activity / resting), for the Spent cell's bar and legend.
    var spent: TodayEnergy.Split?

    init(eaten: MealNutrients, goalKcal: Int?, spentKcal: Int?, balanceKcal: Int?,
         proteinGoalG: Int?, carbsGoalG: Int?, fatGoalG: Int?, spent: TodayEnergy.Split? = nil) {
        self.eaten = eaten
        self.goalKcal = goalKcal
        self.spentKcal = spentKcal
        self.balanceKcal = balanceKcal
        self.proteinGoalG = proteinGoalG
        self.carbsGoalG = carbsGoalG
        self.fatGoalG = fatGoalG
        self.spent = spent
    }

    init(summary: NutritionDaySummary, plan: NutritionGoals.Plan) {
        self.init(eaten: summary.eaten, goalKcal: plan.intakeKcal,
                  spentKcal: summary.spent.map { Int($0.totalKcal.rounded()) },
                  balanceKcal: summary.balanceKcal,
                  proteinGoalG: plan.proteinG > 0 ? plan.proteinG : nil,
                  carbsGoalG: plan.carbsG,
                  fatGoalG: plan.fatG > 0 ? plan.fatG : nil,
                  spent: summary.spent)
    }

    func goal(_ macro: NutritionMacro) -> Int? {
        switch macro {
        case .protein: return proteinGoalG
        case .carbs: return carbsGoalG
        case .fat: return fatGoalG
        }
    }
}

/// The day's intake card, laid out like Today's hero (fork chantier 7): four flat concentric rings (eaten
/// against the intake goal, then protein, carbs and fat against theirs) beside one line each, a hairline,
/// then three cells on Today's fixed row grid — Goal, Spent (Today's own cell), Net.
struct NutritionBalanceCard: View {
    let model: NutritionBalanceModel
    var onGoals: () -> Void = {}

    /// The share of the goal eaten, full at the goal (`NutritionIntakeGauge.intakeArc`).
    private var intakeFill: Double {
        NutritionIntakeGauge.intakeArc(eaten: model.eaten.kcal, goal: model.goalKcal).fill
    }

    /// A macro's share of its goal, full at the goal; no goal, no fill.
    private func macroFill(_ macro: NutritionMacro) -> Double {
        let eaten = macro.grams(model.eaten)
        let goal = model.goal(macro)
        let scale = max(Double(goal ?? 0), eaten)
        return scale > 0 && goal != nil ? eaten / scale : 0
    }

    private var rings: [TodayRing] {
        [TodayRing(fraction: intakeFill, tint: StrandPalette.intakeColor)]
            + NutritionMacro.allCases.map { TodayRing(fraction: macroFill($0), tint: $0.tint) }
    }

    private var hairline: some View {
        Rectangle().fill(StrandPalette.hairline).frame(height: NoopMetrics.hairlineWidth)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space4) {
            HStack(alignment: .center, spacing: 14) {
                TodayConcentricRings(rings: rings)
                VStack(alignment: .leading, spacing: 0) {
                    eatenRow
                    hairline
                    Button(action: onGoals) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(NutritionMacro.allCases.enumerated()), id: \.offset) { index, macro in
                                if index > 0 { hairline }
                                macroRow(macro)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            hairline
            HStack(alignment: .top, spacing: 12) {
                goalCell
                TodayCaloriesTile(split: model.spent, goal: nil)
                netCell
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NoopPanelSurface(cornerRadius: NoopMetrics.cardRadius))
    }

    // MARK: Lines beside the rings

    private var eatenRow: some View {
        TodayRingRow(symbol: "fork.knife", tint: StrandPalette.intakeColor, label: String(localized: "Eaten"),
                     value: NutritionFormat.whole(model.eaten.kcal),
                     caption: model.goalKcal.map { "/" + NutritionFormat.kcalUnit($0) } ?? String(localized: "kcal"))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(model.goalKcal.map {
                String(localized: "\(NutritionFormat.whole(model.eaten.kcal)) kcal eaten of a \(NutritionFormat.whole($0)) kcal goal")
            } ?? String(localized: "\(NutritionFormat.whole(model.eaten.kcal)) kcal eaten")))
    }

    private func macroRow(_ macro: NutritionMacro) -> some View {
        let eaten = macro.grams(model.eaten)
        let goal = model.goal(macro)
        return TodayRingRow(symbol: "drop.fill", tint: macro.tint, label: macro.title,
                            value: NutritionFormat.grams(eaten),
                            caption: goal.map { "/" + NutritionFormat.gramsUnit($0) } ?? "g")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(goal.map {
                String(localized: "\(macro.title): \(NutritionFormat.grams(eaten)) g of a \(NutritionFormat.whole($0)) g goal")
            } ?? String(localized: "\(macro.title): \(NutritionFormat.grams(eaten)) g")))
    }

    // MARK: Cells

    /// "1 065 left" under the goal: what is left of it once the day's meals are counted, never below 0.
    private var goalLegend: Text? {
        guard let goal = model.goalKcal else { return nil }
        let left = NutritionFormat.whole(max(0, goal - model.eaten.kcal))
        return Text("\(left) left")
    }

    private var goalCell: some View {
        TodayHeroCell(symbol: "target", tint: StrandPalette.intakeColor, title: String(localized: "Goal"),
                      value: model.goalKcal.map(NutritionFormat.whole), unit: "kcal", legend: goalLegend) {
            NutritionFillBar(fraction: model.goalKcal == nil ? nil : intakeFill, tint: StrandPalette.intakeColor)
        }
    }

    /// "deficit" or "surplus" under the balance; nothing at exactly zero.
    private var netLegend: Text? {
        guard let balance = model.balanceKcal, balance != 0 else { return nil }
        if balance < 0 {
            return Text("deficit")
        } else {
            return Text("surplus")
        }
    }

    private var netCell: some View {
        TodayHeroCell(symbol: "chart.line.uptrend.xyaxis", tint: StrandPalette.restColor,
                      title: String(localized: "Net"),
                      value: model.balanceKcal.map(NutritionFormat.signedKcal), unit: "kcal", legend: netLegend) {
            NutritionBalanceBar(balanceKcal: model.balanceKcal, scaleKcal: model.goalKcal ?? model.spentKcal,
                                tint: StrandPalette.restColor)
        }
    }
}

/// A flat bar on a white 10 % track, filled to `fraction` (0…1) in `tint`; nil draws the track alone.
struct NutritionFillBar: View {
    var fraction: Double?
    var tint: Color

    var body: some View {
        GeometryReader { geo in
            barBody(width: geo.size.width)
                .frame(height: geo.size.height)
        }
    }

    private func barBody(width: CGFloat) -> some View {
        let filled = width * CGFloat(min(1, max(0, fraction ?? 0)))
        return ZStack(alignment: .leading) {
            Capsule().fill(StrandPalette.textPrimary.opacity(0.10))
            if filled > 0.5 {
                Capsule().fill(tint).frame(width: filled)
            }
        }
        .frame(width: width, height: 6)
    }
}

/// The balance bar: a white tick at the middle for zero, a translucent band from it to the left for a
/// deficit or to the right for a surplus, sized against the day's goal (half the bar = the whole goal).
struct NutritionBalanceBar: View {
    var balanceKcal: Int?
    var scaleKcal: Int?
    var tint: Color

    /// The band's share of the bar's width, at most half of it.
    private var share: CGFloat {
        guard let balanceKcal, let scaleKcal, scaleKcal > 0 else { return 0 }
        return min(0.5, CGFloat(abs(balanceKcal)) / CGFloat(scaleKcal))
    }

    private var isDeficit: Bool { (balanceKcal ?? 0) < 0 }

    var body: some View {
        GeometryReader { geo in
            barBody(width: geo.size.width)
                .frame(height: geo.size.height)
        }
    }

    private func barBody(width: CGFloat) -> some View {
        let half = width / 2
        let band = share * width
        let bandX: CGFloat = isDeficit ? half - band : half
        return ZStack(alignment: .leading) {
            Capsule().fill(StrandPalette.textPrimary.opacity(0.10)).frame(height: 6)
            if band > 0.5 {
                Capsule()
                    .fill(tint.opacity(0.6))
                    .frame(width: band, height: 6)
                    .offset(x: bandX)
            }
            Rectangle()
                .fill(StrandPalette.textPrimary)
                .frame(width: 2, height: 10)
                .offset(x: half - 1)
        }
        .frame(width: width, height: 10, alignment: .leading)
    }
}

/// One meal in the day's list: its origin icon (grey, alone), name, time and macros, its energy in SF
/// Rounded and a chevron. Consecutive rows read as one flat card: the first is rounded at the top, the last
/// at the bottom, a hairline between them.
struct NutritionMealRow: View {
    let entry: MealEntry
    let isFirst: Bool
    let isLast: Bool

    private static let radius = NoopMetrics.cardRadius

    var body: some View {
        HStack(spacing: 12) {
            NutritionOriginIcon(origin: entry.meal.origin)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: NutritionFormat.mealTitle(entry))
                    .font(StrandFont.body.weight(.medium))
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
                .font(StrandFont.rounded(17, weight: .semibold))
                .foregroundStyle(StrandPalette.textPrimary)
                .monospacedDigit()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(StrandPalette.textTertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 18)
        .padding(.top, isFirst ? 16 : 12)
        .padding(.bottom, isLast ? 16 : 12)
        .frame(minHeight: 60)
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
                    .padding(.horizontal, 18)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Opens the meal to edit it"))
    }
}

/// The four ways to add a meal under the intake card (fork chantier 7, design F): type it in, scan a
/// barcode, a photo or dictation estimated by the Coach. A nil action greys its tile out (no camera on
/// the Mac, Coach off). A pure view: the screen and the render test feed it.
struct NutritionAddTiles: View {
    var onType: (() -> Void)?
    var onScan: (() -> Void)?
    var onPhoto: (() -> Void)?
    var onDictate: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            tile(symbol: "pencil", title: "Type in", action: onType)
            tile(symbol: "barcode.viewfinder", title: "Scan code", action: onScan)
            tile(symbol: "camera", title: "Photo", action: onPhoto)
            tile(symbol: "mic", title: "Dictate", action: onDictate)
        }
    }

    private func tile(symbol: String, title: LocalizedStringKey, action: (() -> Void)?) -> some View {
        Button {
            action?()
        } label: {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(StrandFont.body.weight(.semibold))
                    .foregroundStyle(StrandPalette.accent)
                    // One icon height for the four tiles, so their labels share a baseline.
                    .frame(height: 24)
                    .accessibilityHidden(true)
                Text(title)
                    .font(StrandFont.footnote.weight(.medium))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(NoopPanelSurface(cornerRadius: NoopVisualStyle.compactRadius + 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(LiquidPressStyle())
        .disabled(action == nil)
        .opacity(action == nil ? 0.45 : 1)
    }
}

/// The journal of a day with no meal yet.
struct NutritionEmptyMeals: View {
    var body: some View {
        NoopCard(padding: 18) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "fork.knife")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(StrandPalette.textSecondary)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("No meals this day")
                        .font(StrandFont.body.weight(.medium))
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
