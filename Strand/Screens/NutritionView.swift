import SwiftUI
import StrandDesign
import WhoopStore

// MARK: - Nutrition (personal fork; by moment of the day since fork chantier 9, mockup 4)
//
// One day of the meal journal: a food search at the top, a compact card (eaten against the intake goal,
// the three macros, then left / spent / balance), the four moments of the day — each with its total, its
// macros, its share of the goal and a "+" that opens the add sheet for it — then the week and « Customize
// Nutrition ». ‹ › moves a day; a moment unfolds to its meals; a meal opens its editor; a swipe to the left
// deletes it after a confirmation. Every number comes from `NutritionDaySummary`, `NutritionSlots` and
// `NutritionGoals`: nothing here computes a figure of its own.

struct NutritionView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    /// The Coach whose key the Photo and Dictate tiles use, and the label reading of the scanner.
    @EnvironmentObject private var coach: AICoachEngine
    @EnvironmentObject private var router: NavRouter
    /// True in the iOS tab shell, where Nutrition is a tab root with the More avatar (fork chantier 9).
    @Environment(\.showsMoreAvatar) var showsMoreAvatar

    @AppStorage(MealJournal.revisionKey) private var mealRevision = 0
    // The goal settings, read through `currentPlan`: declared so a change on the Goals screen redraws the rings.
    @AppStorage(NutritionGoals.proteinTenthsKey) private var proteinTenths = NutritionGoals.defaultProteinTenths
    @AppStorage(NutritionGoals.fatTenthsKey) private var fatTenths = NutritionGoals.defaultFatTenths
    @AppStorage(NutritionGoals.goalPercentKey) private var goalPercent = NutritionGoals.defaultGoalPercent
    @AppStorage(NutritionGoals.activityLevelKey) private var activityLevel = NutritionGoals.ActivityLevel.defaultLevel.rawValue
    @AppStorage(NutritionGoals.goalModeKey) private var goalMode = NutritionGoals.GoalMode.percent.rawValue
    @AppStorage(NutritionGoals.manualKcalKey) private var manualKcal = 0

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
    // Fork chantier 9: the add sheet (a moment's "+", or the search field), the action it handed back,
    // and the moment the editor, the capture and the scanner it opens save into.
    @State private var addRequest: NutritionAddRequest?
    @State private var pendingAdd: PendingAdd?
    @State private var editorSlot: MealSlot?
    @State private var captureSlot: MealSlot?
    @State private var scannerSlot: MealSlot?
    /// The moments unfolded to their meals (all folded at first).
    @State private var expandedSlots: Set<MealSlot> = []
    @State private var showHistory = false
    @State private var showCustomize = false
    /// « Customize Nutrition »: the Blood markers card back on the page (off by default; it stays in the
    /// Lab Book). This iPhone only, outside the .noopbak.
    @AppStorage(NutritionView.labCardShownKey) private var labCardShown = false
    // Personal fork: Dictate and Photo open the capture sheet once the editor has closed, and its
    // proposal opens back in the editor, every quantity editable, once the capture sheet has closed.
    @State private var captureRequested: NutritionCaptureMode?
    @State private var capture: NutritionCaptureMode?
    @State private var capturedDraft: MealEntry?
    // Fork chantier 9: the week under the moments (the 7 complete days before today); 7 / 30 days and the
    // three charts open on the History screen.
    @State private var week: [NutritionHistoryDay]?
    // Personal fork, chantier 8: the followed Lab Book markers, and the Lab Book they open.
    @State private var labLines: [NutritionLabLine] = []
    @State private var showLabBook = false

    private enum ScannerExit {
        case manual, coach
    }

    /// The UserDefaults key of the Blood markers card's switch.
    static let labCardShownKey = "nutrition.labCardShown"

    /// One opening of the add sheet: its moment, and whether the keyboard comes up in the search.
    struct NutritionAddRequest: Identifiable {
        let id = UUID()
        let slot: MealSlot
        let focusSearch: Bool
    }

    private struct PendingAdd: Equatable {
        let action: NutritionAddAction
        let slot: MealSlot
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

    /// The goals, from the one resolver (`NutritionDayReader.currentPlan`).
    private var plan: NutritionGoals.Plan {
        NutritionDayReader.currentPlan(profile: profile)
    }

    var body: some View {
        let current = shown
        let plan = plan
        let groups = NutritionSlots.groupMealsBySlot(current.meals)
        List {
            Group {
                header
                NutritionSearchBar(onSearch: { openAddSheet(slot: nil, focusSearch: true) },
                                   onScan: barcodeScannerAvailable ? { scannerSlot = nil; showScanner = true } : nil)
                NutritionBalanceCard(model: NutritionBalanceModel(summary: current, plan: plan))
            }
            .nutritionListRow()

            ForEach(groups) { group in
                let expanded = expandedSlots.contains(group.slot) && group.hasMeals
                NutritionSlotHeader(group: group, goalKcal: plan.intakeKcal, expanded: expanded,
                                    onToggle: { toggle(group.slot) },
                                    onAdd: { openAddSheet(slot: group.slot, focusSearch: false) })
                    .nutritionListRow(top: 6, bottom: expanded ? 0 : 6)
                if expanded {
                    ForEach(Array(group.meals.enumerated()), id: \.element.meal.id) { index, entry in
                        mealRow(entry, isLast: index == group.meals.count - 1)
                            .nutritionListRow(top: 0, bottom: index == group.meals.count - 1 ? 6 : 0)
                    }
                }
            }

            if !current.meals.isEmpty {
                Text("Swipe a meal to the left to delete it. “estimate” = quantities estimated from a photo; calories and macros are always calculated by the app. Food values: \(CiqualTable.attribution)")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .nutritionListRow()
            }

            Group {
                NutritionWeekCard(model: NutritionHistoryModel(days: week ?? [], plan: plan), loading: week == nil,
                                  onOpen: { showHistory = true })
                if labCardShown, !labLines.isEmpty {
                    NutritionLabCard(lines: labLines, onOpen: { showLabBook = true })
                }
                Button { showCustomize = true } label: {
                    LiquidFullWidthNavigationAction("Customize Nutrition")
                }
                .buttonStyle(LiquidPressStyle())
            }
            .padding(.top, NoopMetrics.space2)
            .nutritionListRow()
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 1)
        .background(StrandPalette.surfaceBase.ignoresSafeArea())
        .navigationDestination(isPresented: $showGoals) { NutritionGoalsView() }
        .navigationDestination(isPresented: $showHistory) { NutritionHistoryScreen() }
        .task(id: "\(mealRevision)-\(Repository.localDayKey(Date()))") {
            let days = await NutritionHistory.loadNutritionHistory(repo, profile: profile, range: .week)
            if !Task.isCancelled { week = days }
        }
        .navigationDestination(isPresented: $showLabBook) { LabBookView() }
        .task(id: repo.refreshSeq) { labLines = await NutritionLabLines.loadLabLines(repo) }
        .task(id: "\(dayKey)-\(mealRevision)-\(repo.refreshSeq)") {
            await NutritionSeries.backfillNutritionSeriesIfNeeded(repo)
            let read = await NutritionDayReader.readDay(repo, profile: profile, day: day)
            if read.dayKey == dayKey { self.summary = read }
        }
        .sheet(item: $editor, onDismiss: openRequestedScanner) { target in
            NutritionMealEditor(target: target, day: day,
                                onBarcode: barcodeScannerAvailable ? { scannerRequested = true } : nil,
                                onPhoto: coach.canEstimateMeals ? { captureRequested = .photo } : nil,
                                onDictate: coach.canEstimateMeals ? { captureRequested = .voice } : nil,
                                initialSlot: editorSlot)
                .environmentObject(repo)
        }
        .sheet(item: $addRequest, onDismiss: runPendingAdd) { request in
            NutritionAddSheet(day: day, initialSlot: request.slot, focusSearch: request.focusSearch,
                              canScan: barcodeScannerAvailable, canEstimate: coach.canEstimateMeals) { action, slot in
                pendingAdd = PendingAdd(action: action, slot: slot)
            }
            .environmentObject(repo)
        }
        .sheet(isPresented: $showCustomize) {
            NutritionCustomizeSheet(labCardShown: $labCardShown)
        }
        .sheet(item: $capture, onDismiss: openCapturedDraft) { mode in
            NutritionMealCaptureSheet(mode: mode) { proposal in capturedDraft = proposal.draftEntry() }
                .environmentObject(coach)
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showScanner, onDismiss: afterScanner) {
            NutritionBarcodeScanner(day: day, canReadLabel: coachTakesPhotos,
                                    onManual: { scannerExit = .manual; showScanner = false },
                                    onLabelSent: { scannerExit = .coach; showScanner = false },
                                    slot: scannerSlot)
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

    /// The screen's header: the tab-root layout in the iOS tab shell, the pushed-screen one elsewhere.
    @ViewBuilder
    private var header: some View {
        if showsMoreAvatar { shellHeader } else { stackHeader }
    }

    /// The iOS tab shell (fork chantier 9): the title with the goals and the More avatar on its right,
    /// then the day between ‹ › on its own line — four round buttons beside the title would not fit.
    private var shellHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Text("Nutrition")
                    .font(StrandFont.screenTitle)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                journalHeaderButton(symbol: "target", label: "Nutrition goals", enabled: true) {
                    showGoals = true
                }
                MoreAvatarButton()
            }
            // The same day picker as Sleep's night picker (5 Nov.).
            DayPickerRow(caption: dayCaption, title: NutritionFormat.longDay(day),
                         canGoBack: dayOffset < Self.maxDaysBack, canGoForward: dayOffset > 0,
                         onBack: { dayOffset += 1 }, onForward: { dayOffset -= 1 })
        }
        .padding(.top, 8)
    }

    /// « Today » / « Yesterday » over the date in the day picker; nil further back.
    private var dayCaption: String? {
        switch dayOffset {
        case 0: return String(localized: "Today")
        case 1: return String(localized: "Yesterday")
        default: return nil
        }
    }

    /// Fork chantier 7: the day in 13 semibold grey capitals over the title in 34 bold; ‹ › and the goals
    /// on the right as round glass buttons (the day is named once, here).
    private var stackHeader: some View {
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

    /// One meal under its unfolded moment: tap to edit, swipe to the left (or the context menu) to delete.
    private func mealRow(_ entry: MealEntry, isLast: Bool) -> some View {
        Button {
            editorSlot = nil
            editor = .edit(entry)
        } label: {
            NutritionMealRow(entry: entry, isFirst: false, isLast: isLast)
        }
        .buttonStyle(.plain)
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
                editorSlot = nil
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

    private func toggle(_ slot: MealSlot) {
        if expandedSlots.contains(slot) { expandedSlots.remove(slot) } else { expandedSlots.insert(slot) }
    }

    /// The add sheet for a moment's "+", or for the search field (the moment the time of day falls in).
    private func openAddSheet(slot: MealSlot?, focusSearch: Bool) {
        let resolved = slot ?? MealJournal.mealSlotForTime(NutritionMealEditor.defaultTime(on: day))
        addRequest = NutritionAddRequest(slot: resolved, focusSearch: focusSearch)
    }

    /// The add sheet closed on one of its four ways in: open it now, for the moment chosen there.
    private func runPendingAdd() {
        guard let pending = pendingAdd else { return }
        pendingAdd = nil
        switch pending.action {
        case .scan:
            scannerSlot = pending.slot
            showScanner = true
        case .photo:
            captureSlot = pending.slot
            capture = .photo
        case .dictate:
            captureSlot = pending.slot
            capture = .voice
        case .type:
            editorSlot = pending.slot
            editor = .add
        }
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
            captureSlot = editorSlot
            capture = mode
            return
        }
        guard scannerRequested else { return }
        scannerRequested = false
        scannerSlot = editorSlot
        showScanner = true
    }

    /// The capture sheet closed on a proposal: open it in the editor, as a meal not saved yet.
    private func openCapturedDraft() {
        guard let draft = capturedDraft else { return }
        capturedDraft = nil
        editorSlot = captureSlot
        editor = .draft(draft)
    }

    /// The scanner closed on "Enter by hand" (the editor opens) or on a label sent to the Coach.
    private func afterScanner() {
        let exit = scannerExit
        scannerExit = nil
        switch exit {
        case .manual?:
            editorSlot = scannerSlot
            editor = .add
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

/// The day's intake card, compact (fork chantier 9, mockup 4): four flat concentric rings (eaten against the
/// intake goal, then protein, carbs and fat against theirs) beside "eaten" in large, the three macros, then
/// left · spent · balance. Every figure comes from `NutritionBalanceModel`.
struct NutritionBalanceCard: View {
    let model: NutritionBalanceModel

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

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            TodayConcentricRings(rings: rings, diameter: 104, lineWidth: 9, spacing: 3)
            VStack(alignment: .leading, spacing: 8) {
                eatenLine
                HStack(alignment: .top, spacing: 6) {
                    ForEach(NutritionMacro.allCases, id: \.self) { macro in
                        macroColumn(macro)
                    }
                }
                figuresLine
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NoopPanelSurface(cornerRadius: NoopMetrics.cardRadius))
    }

    /// "1 495 / 2 560 kcal eaten".
    private var eatenLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(verbatim: NutritionFormat.whole(model.eaten.kcal))
                .font(StrandFont.number(26, weight: .bold))
                .foregroundStyle(StrandPalette.intakeColor)
                .monospacedDigit()
            Text(verbatim: model.goalKcal.map { "/ " + NutritionFormat.whole($0) + " " + String(localized: "kcal eaten") }
                ?? String(localized: "kcal eaten"))
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textSecondary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(model.goalKcal.map {
            String(localized: "\(NutritionFormat.whole(model.eaten.kcal)) kcal eaten of a \(NutritionFormat.whole($0)) kcal goal")
        } ?? String(localized: "\(NutritionFormat.whole(model.eaten.kcal)) kcal eaten")))
    }

    private func macroColumn(_ macro: NutritionMacro) -> some View {
        let eaten = macro.grams(model.eaten)
        let goal = model.goal(macro)
        let caption = goal.map { "/" + NutritionFormat.gramsUnit($0) } ?? " g"
        return VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: macro.title)
                .font(StrandFont.caption.weight(.semibold))
                .foregroundStyle(macro.tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(verbatim: NutritionFormat.grams(eaten))
                    .font(StrandFont.number(15, weight: .bold))
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(verbatim: caption)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(goal.map {
            String(localized: "\(macro.title): \(NutritionFormat.grams(eaten)) g of a \(NutritionFormat.whole($0)) g goal")
        } ?? String(localized: "\(macro.title): \(NutritionFormat.grams(eaten)) g")))
    }

    /// "Left 1 065 · Spent 2 100 · Net −605": left in the eaten green, spent in the burned orange, the
    /// balance in white; a dash when it is not known.
    private var figuresLine: some View {
        let left = model.goalKcal.map { NutritionFormat.whole(max(0, $0 - model.eaten.kcal)) }
        let spent = model.spentKcal.map(NutritionFormat.whole)
        let net = model.balanceKcal.map(NutritionFormat.signedKcal)
        // Each figure under its name, like the macros above, so « Spent 2 713 » is never cut (5 Nov.).
        return HStack(alignment: .top, spacing: 12) {
            figure("Left", value: left, tint: StrandPalette.intakeColor)
            figure("Spent", value: spent, tint: StrandPalette.caloriesActivity)
            figure("Net", value: net, tint: StrandPalette.textPrimary)
        }
    }

    private func figure(_ title: LocalizedStringKey, value: String?, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(verbatim: value ?? "\u{2014}")
                .font(StrandFont.footnote.weight(.bold))
                .foregroundStyle(value == nil ? StrandPalette.textSecondary : tint)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// One meal in the day's list: its origin icon (grey, alone), name (with "Coach" for a meal of a Coach
/// menu), time and macros, its energy in SF Rounded and a chevron. Consecutive rows read as one flat card:
/// the first is rounded at the top, the last at the bottom, a hairline between them.
struct NutritionMealRow: View {
    let entry: MealEntry
    let isFirst: Bool
    let isLast: Bool

    private static let radius = NoopMetrics.cardRadius

    var body: some View {
        HStack(spacing: 12) {
            NutritionOriginIcon(origin: entry.meal.origin)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(verbatim: NutritionFormat.mealTitle(entry))
                        .font(StrandFont.body.weight(.medium))
                        .foregroundStyle(StrandPalette.textPrimary)
                        .lineLimit(1)
                    if entry.isCoachMenuMeal { NutritionCoachTag() }
                }
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

/// "Coach" after the name of a meal from a Coach menu (fork chantier 9), in the purple of mockup 4.
struct NutritionCoachTag: View {
    var body: some View {
        Text("Coach")
            .font(StrandFont.caption.weight(.bold))
            .foregroundStyle(StrandPalette.macroProtein)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(StrandPalette.macroProtein.opacity(0.18),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .fixedSize()
            .accessibilityLabel(Text("from the Coach's menu"))
    }
}

/// The four other ways to add a meal, in the add sheet (fork chantier 9: Scan, Photo, Dictate, Type in). A
/// nil action greys its tile out (no camera on the Mac, Coach off). A pure view: the sheet and the render
/// test feed it.
struct NutritionAddTiles: View {
    var onScan: (() -> Void)?
    var onPhoto: (() -> Void)?
    var onDictate: (() -> Void)?
    var onType: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            tile(symbol: "barcode.viewfinder", title: "Scan code", action: onScan)
            tile(symbol: "camera", title: "Photo", action: onPhoto)
            tile(symbol: "mic", title: "Dictate", action: onDictate)
            tile(symbol: "pencil", title: "Type in", action: onType)
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
            .background(StrandPalette.surfaceBase, in: RoundedRectangle(cornerRadius: NoopVisualStyle.compactRadius + 2,
                                                                       style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(LiquidPressStyle())
        .disabled(action == nil)
        .opacity(action == nil ? 0.45 : 1)
    }
}

private extension View {
    /// A row of the journal's list: no separator, no row background, the page's side margins.
    func nutritionListRow(vertical: CGFloat = 6) -> some View {
        nutritionListRow(top: vertical, bottom: vertical)
    }

    /// The same with its own top and bottom insets (a moment's card is several rows, one flush to the next).
    func nutritionListRow(top: CGFloat, bottom: CGFloat) -> some View {
        self
            .listRowInsets(EdgeInsets(top: top, leading: NoopMetrics.screenHPadding,
                                      bottom: bottom, trailing: NoopMetrics.screenHPadding))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}
