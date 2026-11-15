import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

// MARK: - Jeûne (personal fork, chantier 15)
//
// The fasting page under Nutrition: the ring (nothing running · running · over), the phases, the water
// bottle and the history. Every figure of the fast comes from ONE resolver, `FastingLog.fastingState`,
// so the Nutrition card, this page, the lock-screen banner and the Coach cannot disagree; the arithmetic
// is `FastingTimeline`, shared byte for byte with Android. The water is the existing hydration store.

struct FastingView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @EnvironmentObject private var coach: AICoachEngine
    @EnvironmentObject private var router: NavRouter
    @AppStorage(FastingLog.revisionKey) private var revision = 0
    @AppStorage(FastingLog.lastGoalKey) private var lastGoalMinutes = 0
    /// The over fast whose card was dismissed by « New fast »: the page is then empty again.
    @AppStorage(FastingView.dismissedDoneKey) private var dismissedDoneId = ""
    @AppStorage(HydrationStore.customSizeKey) private var customSizeML = HydrationGoal.cupML
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var motion = NoopMotionState.shared

    /// The fast running, and the newest fast of all (the one just over shows its card).
    @State private var running: FastRow?
    @State private var latest: FastRow?
    @State private var loaded = false
    @State private var now = Date()
    /// The duration picked before a start (the last one used, 16 h the first time).
    @State private var pickedGoalMinutes = FastingTimeline.defaultGoalMinutes
    // Water: the day's total, the goal, whether a hand-logged entry can be undone.
    @State private var waterML: Double = 0
    @State private var canUndoWater = false
    @State private var waterTick = 0
    // History.
    @State private var historyDays = 7
    @State private var history: (durations: [Int], summary: FastingTimeline.Summary)?
    /// Chantier 15 PR C: the fasting nights against the others (nil while reading).
    @State private var nights: FastingNightsResult?
    // Sheets and what they edit.
    @State private var sheet: Sheet?
    @State private var editDate = Date()
    @State private var editGoalMinutes = FastingTimeline.defaultGoalMinutes
    @State private var phaseIndex = 0

    static let dismissedDoneKey = "fasting.dismissedDoneId"

    private enum Sheet: Identifiable {
        case startTime, plannedEnd, stop, phase, caffeine, waterCorrect, reminders
        var id: Int {
            switch self {
            case .startTime: return 0
            case .plannedEnd: return 1
            case .stop: return 2
            case .phase: return 3
            case .caffeine: return 4
            case .waterCorrect: return 5
            case .reminders: return 6
            }
        }
    }

    private var still: Bool { motion.poseStill(reduceMotion) }

    /// The state shown: the running fast, else the fast just over (until « New fast », or the end of the
    /// logical day after its end), else nothing. The one rule: `FastingLog.shownFastingState`.
    private var state: FastingState? {
        FastingLog.shownFastingState(running: running, newest: latest, dismissedId: dismissedDoneId, now: now)
    }

    private var goalML: Int { repo.hydrationGoalML(profileSex: profile.sex) }

    private var todayKey: String { Repository.logicalDayKey(now) }

    var body: some View {
        ScreenScaffold(title: "Fasting", trailing: {
            // Chantier 15 PR C: the notifications and the Lock Screen banner.
            Button { sheet = .reminders } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Fasting reminders"))
        }) {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                ringCard
                FastingPhasesCard(state: state) { index in
                    phaseIndex = index
                    sheet = .phase
                }
                FastingWaterCard(totalML: waterML, goalML: goalML, customML: customSizeML, canUndo: canUndoWater,
                                 animated: loaded,
                                 onAdd: { ml in Task { await addWater(ml) } },
                                 onUndo: { Task { await undoWater() } },
                                 onCorrect: { sheet = .waterCorrect },
                                 onCaffeine: { sheet = .caffeine })
                FastingHistoryCard(durations: history?.durations ?? Array(repeating: 0, count: historyDays),
                                   summary: history?.summary ?? FastingTimeline.Summary(averageMinutes: 0, keptCount: 0, fastedCount: 0, streak: 0),
                                   goalMinutes: state?.fast.goalMinutes ?? pickedGoalMinutes,
                                   todayRunning: running != nil, days: $historyDays,
                                   loading: history == nil, animated: loaded)
                FastingNightsCard(result: nights)
                    .animation(NoopMotion.gated(NoopMotion.card, reduced: still), value: nights)
                Text("Indicative landmarks from the general literature, on \(Platform.deviceNounPhrase) only. Not medical advice.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .noopEntranceRoot()
        .task(id: revision) { await reloadFasts() }
        .task(id: "\(historyDays)-\(revision)-\(todayKey)") { await reloadHistory() }
        .task(id: "\(revision)-\(repo.refreshSeq)-\(todayKey)") {
            nights = await FastingNights.loadFastingNights(repo: repo)
        }
        .task(id: "\(waterTick)-\(repo.refreshSeq)-\(todayKey)") { await reloadWater() }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { now = $0 }
        .sheet(item: $sheet, onDismiss: { Task { await reloadWater() } }) { which in
            switch which {
            case .startTime: startTimeSheet
            case .plannedEnd: plannedEndSheet
            case .stop: stopSheet
            case .phase: phaseSheet
            case .caffeine: caffeineSheet
            case .waterCorrect:
                NavigationStack { HydrationView() }
                    .environmentObject(repo)
                    .environmentObject(profile)
            case .reminders:
                FastingRemindersSheet(onChange: { Task { await refreshSurroundings() } },
                                      onClose: { sheet = nil })
            }
        }
    }

    // MARK: Ring card

    @ViewBuilder
    private var ringCard: some View {
        NoopCard(padding: 16) {
            VStack(spacing: 10) {
                if let state {
                    if state.isRunning { runningHeader(state) } else { doneHeader(state) }
                    ring(state)
                    if state.isRunning { runningControls(state) } else { doneControls(state) }
                } else {
                    idleHeader
                    ring(nil)
                    idleControls
                }
            }
            .frame(maxWidth: .infinity)
        }
        .animation(NoopMotion.gated(NoopMotion.card, reduced: still), value: state?.isRunning)
    }

    private var idleHeader: some View {
        HStack {
            Text("No fast running")
                .font(StrandFont.headline)
                .foregroundStyle(StrandPalette.textPrimary)
            Spacer()
            if let latest, let end = latest.endedAt {
                let minutes = max(0, (end - latest.startedAt) / 60)
                Text("last: \(FastingFormat.duration(minutes: minutes))")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
        }
    }

    private func runningHeader(_ state: FastingState) -> some View {
        HStack(spacing: 8) {
            Text("Fasting · \(FastingFormat.duration(minutes: state.fast.goalMinutes))")
                .font(StrandFont.headline)
                .foregroundStyle(StrandPalette.textPrimary)
            Text("running")
                .font(StrandFont.caption2.weight(.bold))
                .foregroundStyle(StrandPalette.fastingDone)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(StrandPalette.fastingDone.opacity(0.18), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            Spacer()
            Text(verbatim: FastingFormat.percent(permille: state.progressPermille))
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textSecondary)
                .monospacedDigit()
        }
    }

    private func doneHeader(_ state: FastingState) -> some View {
        HStack {
            Text("Fast over")
                .font(StrandFont.headline)
                .foregroundStyle(StrandPalette.textPrimary)
            Spacer()
            Group {
                if state.goalReached { Text("goal reached") } else { Text("goal not reached") }
            }
                .font(StrandFont.caption2.weight(.bold))
                .foregroundStyle(state.goalReached ? StrandPalette.fastingDone : StrandPalette.fastingRemaining)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background((state.goalReached ? StrandPalette.fastingDone : StrandPalette.fastingRemaining).opacity(0.18),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    /// The ring, traced on arrival and again for another fast; its « now » dot breathes while it runs.
    @ViewBuilder
    private func ring(_ state: FastingState?) -> some View {
        let mode: FastingRingMode = state.map { $0.isRunning ? .running : .done(reached: $0.goalReached) } ?? .idle
        let key = "fasting.ring.\(state?.fast.id ?? "idle")"
        NoopFirstDraw(key: key, armed: loaded) { phase in
            // The « now » dot breathes only while a fast runs and the quiet-motion gate is open; at rest the
            // ring is drawn with no timeline behind it (a paused timeline still costs frames).
            if still || mode != .running || !phase.drawn {
                ringFace(state, mode: mode, phase: phase, breath: 0)
            } else {
                TimelineView(.animation(minimumInterval: 1 / 24)) { context in
                    let breath = (sin(context.date.timeIntervalSinceReferenceDate * 2 * .pi / 3.2) + 1) / 2
                    ringFace(state, mode: mode, phase: phase, breath: breath)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func ringFace(_ state: FastingState?, mode: FastingRingMode, phase: NoopDrawPhase, breath: Double) -> some View {
        FastingRing(mode: mode, progressPermille: state?.progressPermille ?? 0,
                    trace: phase.drawn ? 1 : 0,
                    markers: state?.markers ?? FastingTimeline.fastingMarkers(goalMinutes: pickedGoalMinutes),
                    currentPhase: state?.phaseIndex ?? 0, diameter: 250, breath: breath,
                    onMarker: { index in
                        phaseIndex = index
                        sheet = .phase
                    }) {
            ringCenter(state, drawn: phase.drawn)
        }
        .animation(phase.motion(NoopMotion.ringDraw), value: phase.drawn)
    }

    @ViewBuilder
    private func ringCenter(_ state: FastingState?, drawn: Bool) -> some View {
        VStack(spacing: 2) {
            if let state {
                NoopRollingNumber(value: Double(state.elapsedMinutes), format: { FastingFormat.duration(minutes: Int($0.rounded())) },
                                  font: StrandFont.number(30, weight: .bold), color: StrandPalette.textPrimary,
                                  glow: StrandPalette.fastingDone, entrance: .slam, armed: loaded,
                                  launchKey: "fasting.slam.\(state.fast.id)", delay: 0.45)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if state.isRunning {
                    Text("done out of \(FastingFormat.duration(minutes: state.fast.goalMinutes))")
                        .font(StrandFont.caption.weight(.semibold))
                        .foregroundStyle(StrandPalette.textSecondary)
                    Text("\(FastingFormat.duration(minutes: state.remainingMinutes)) left")
                        .font(StrandFont.subhead.weight(.bold))
                        .foregroundStyle(StrandPalette.fastingRemaining)
                } else {
                    Text("out of \(FastingFormat.duration(minutes: state.fast.goalMinutes))")
                        .font(StrandFont.caption.weight(.semibold))
                        .foregroundStyle(StrandPalette.textSecondary)
                    if state.goalReached {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .noopSymbolBounce(drawn)
                            Text("+ \(FastingFormat.duration(minutes: state.elapsedMinutes - state.fast.goalMinutes)) past the goal")
                        }
                        .font(StrandFont.subhead.weight(.bold))
                        .foregroundStyle(StrandPalette.fastingDone)
                    } else {
                        Text("stopped \(FastingFormat.duration(minutes: state.remainingMinutes)) before the goal")
                            .font(StrandFont.subhead.weight(.bold))
                            .foregroundStyle(StrandPalette.fastingRemaining)
                    }
                }
            } else {
                Text("Ready for")
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(StrandPalette.textSecondary)
                Text(verbatim: FastingFormat.duration(minutes: pickedGoalMinutes))
                    .font(StrandFont.number(34, weight: .bold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .noopNumericTransition(Double(pickedGoalMinutes))
            }
        }
        .multilineTextAlignment(.center)
        .monospacedDigit()
        .padding(.horizontal, 8)
    }

    // MARK: Controls

    private var idleControls: some View {
        VStack(spacing: 10) {
            FastingGoalPicker(goalMinutes: $pickedGoalMinutes)
            FastingActionButton(title: Text("Start now · \(FastingFormat.clock(now))"), look: .primary) {
                Task { await start(at: Date()) }
            }
            Button {
                editDate = Date().addingTimeInterval(-3600)
                sheet = .startTime
            } label: {
                Text("Already started? Set the start time")
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(StrandPalette.accent)
                    .frame(minHeight: 36)
            }
            .buttonStyle(.plain)
        }
    }

    private func runningControls(_ state: FastingState) -> some View {
        VStack(spacing: 8) {
            // Fork chantier 12: the phase pill changes by a fade when a phase is reached.
            Button {
                phaseIndex = state.phaseIndex
                sheet = .phase
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: FastingPhaseText.symbol(state.phaseIndex)).font(.system(size: 13, weight: .semibold))
                    Text(verbatim: FastingPhaseText.name(state.phaseIndex)).fontWeight(.bold)
                    Text("since \(FastingFormat.duration(minutes: state.elapsedMinutes - FastingTimeline.phaseStartHours[state.phaseIndex] * 60))")
                        .opacity(0.85)
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).opacity(0.7)
                }
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.onDarkPrimary)
                .padding(.horizontal, 14)
                .frame(height: 40)
                .background(FastingPhaseText.tint(state.phaseIndex), in: Capsule())
            }
            .buttonStyle(LiquidPressStyle())
            .id(state.phaseIndex)
            .transition(.opacity)
            .accessibilityHint(Text("Shows the phase"))
            HStack(spacing: 8) {
                timeButton(Text("Start"), FastingFormat.dayAndClock(state.startedAt, now: now)) {
                    editDate = state.startedAt
                    sheet = .startTime
                }
                timeButton(Text("Planned end"), FastingFormat.dayAndClock(state.plannedEnd, now: now)) {
                    editGoalMinutes = state.fast.goalMinutes
                    sheet = .plannedEnd
                }
            }
            FastingActionButton(title: Text("Stop the fast"), look: .stop) {
                editDate = Date()
                sheet = .stop
            }
        }
    }

    private func doneControls(_ state: FastingState) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Text(verbatim: FastingFormat.dayAndClock(state.startedAt, now: now))
                Image(systemName: "arrow.right").font(.system(size: 11, weight: .semibold)).accessibilityLabel(Text("to"))
                Text(verbatim: FastingFormat.dayAndClock(state.endedAt ?? now, now: now))
            }
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textSecondary)
            HStack(spacing: 8) {
                FastingActionButton(title: Text("Correct the end"), look: .secondary) {
                    editDate = state.endedAt ?? Date()
                    sheet = .stop
                }
                Button {
                    dismissedDoneId = state.fast.id
                } label: {
                    Text("New fast")
                        .font(StrandFont.body.weight(.bold))
                        .foregroundStyle(StrandPalette.surfaceBase)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(StrandPalette.fastingDone, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(LiquidPressStyle())
            }
        }
    }

    private func timeButton(_ label: Text, _ value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                label.font(StrandFont.caption.weight(.semibold)).foregroundStyle(StrandPalette.textSecondary)
                HStack(spacing: 6) {
                    Text(verbatim: value)
                        .font(StrandFont.body.weight(.bold))
                        .foregroundStyle(StrandPalette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(StrandPalette.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(StrandPalette.surfaceInset, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(LiquidPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Edit"))
    }

    // MARK: Sheets

    /// The fast as it would be with `editDate` as its start (the footer of the start sheet).
    private var startFooter: String {
        let goal = running?.goalMinutes ?? pickedGoalMinutes
        let elapsed = max(0, Int(now.timeIntervalSince(editDate)) / 60)
        let end = editDate.addingTimeInterval(TimeInterval(goal * 60))
        return String(localized: "The fast is then \(FastingFormat.duration(minutes: elapsed)) · planned end \(FastingFormat.dayAndClock(end, now: now))")
    }

    private var startTimeSheet: some View {
        FastingTimeSheet(title: "Start time",
                         explanation: "If the fast started before you pressed Start, move the time back: the ring updates at once.",
                         date: $editDate,
                         range: now.addingTimeInterval(-36 * 3600)...now,
                         footer: startFooter, saveTitle: "Save",
                         onSave: {
                             sheet = nil
                             Task { await saveStart(editDate) }
                         },
                         onCancel: { sheet = nil })
    }

    private var plannedEndSheet: some View {
        FastingGoalSheet(goalMinutes: $editGoalMinutes, startedAt: running.map { $0.startedAt }.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? now,
                         now: now,
                         onSave: {
                             sheet = nil
                             Task { await saveGoal(editGoalMinutes) }
                         },
                         onCancel: { sheet = nil })
    }

    /// The footer of the stop sheet: the duration with `editDate` as the end, and its distance to the goal.
    private var stopFooter: String {
        guard let row = running ?? latest else { return "" }
        let elapsed = max(0, Int(editDate.timeIntervalSince1970) - row.startedAt) / 60
        let goal = row.goalMinutes
        let delta = (elapsed >= goal ? "+ " : "− ") + FastingFormat.duration(minutes: abs(elapsed - goal))
        return String(localized: "Duration \(FastingFormat.duration(minutes: elapsed)) out of \(FastingFormat.duration(minutes: goal)) · \(delta)")
    }

    private var stopSheet: some View {
        let row = running ?? latest
        let start = row.map { Date(timeIntervalSince1970: TimeInterval($0.startedAt)) } ?? now.addingTimeInterval(-60)
        let correcting = running == nil
        return FastingTimeSheet(title: correcting ? "Correct the end" : "Stop the fast",
                                explanation: "The real end time. If you ate before opening the app, move it back.",
                                date: $editDate,
                                range: start...max(start.addingTimeInterval(60), now),
                                footer: stopFooter,
                                saveTitle: correcting ? "Save" : "Stop the fast",
                                destructive: !correcting,
                                onSave: {
                                    sheet = nil
                                    Task { await saveEnd(editDate) }
                                },
                                onCancel: { sheet = nil })
    }

    /// The Coach's explanation, when it can run; nil tells the sheet why not.
    private var phaseExplainer: ((Int) async -> FastingExplainOutcome)? {
        guard coach.canExplainFasting else { return nil }
        return { index in await explainPhase(index) }
    }

    private var phaseSheet: some View {
        FastingPhaseSheet(index: $phaseIndex, state: state, now: now,
                          explain: phaseExplainer,
                          onOpenCoach: {
                              coach.pendingPrompt = coachHandoffPrompt
                              sheet = nil
                              DispatchQueue.main.async { router.openCoach() }
                          },
                          onClose: { sheet = nil })
    }

    /// The question « Continue › » hands to the Coach tab. Short again (chantier 15 PR C): the fiche's FASTING
    /// block carries the fast's figures and the water with every question.
    private var coachHandoffPrompt: String {
        String(localized: "Explain where I am in my fast and what to do next.")
    }

    private var caffeineSheet: some View {
        NavigationStack {
            ScrollView {
                CaffeineLogCard()
                    .padding(.horizontal, NoopMetrics.screenHPadding)
                    .padding(.vertical, 12)
            }
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .navigationTitle(Text("Coffee · tea"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { sheet = nil }
                }
            }
        }
        .environmentObject(repo)
    }

    // MARK: Loading

    private func reloadFasts() async {
        guard let store = await repo.storeHandle() else { return }
        let open = try? await store.runningFast()
        let newest = (try? await store.recentFasts(limit: 1))?.first
        running = open
        latest = newest
        if lastGoalMinutes > 0 { pickedGoalMinutes = FastingTimeline.clampGoalMinutes(lastGoalMinutes) }
        now = Date()
        loaded = true
    }

    private func reloadHistory() async {
        guard let store = await repo.storeHandle() else { return }
        let goal = running?.goalMinutes ?? latest?.goalMinutes ?? pickedGoalMinutes
        history = await FastingLog.fastingHistory(store, days: historyDays, goalMinutes: goal, now: Date())
    }

    private func reloadWater() async {
        waterML = await repo.hydrationTotal(day: todayKey)
        canUndoWater = !repo.hydrationEntries(day: todayKey).isEmpty
    }

    // MARK: Actions

    private func start(at date: Date) async {
        guard let store = await repo.storeHandle() else { return }
        await FastingLog.startFast(store, startedAt: date, goalMinutes: pickedGoalMinutes)
        dismissedDoneId = ""
    }

    private func saveStart(_ date: Date) async {
        guard let store = await repo.storeHandle() else { return }
        if let running {
            await FastingLog.amendFast(store, running, startedAt: date)
        } else {
            await FastingLog.startFast(store, startedAt: date, goalMinutes: pickedGoalMinutes)
            dismissedDoneId = ""
        }
    }

    private func saveGoal(_ minutes: Int) async {
        guard let store = await repo.storeHandle(), let running else { return }
        await FastingLog.amendFast(store, running, goalMinutes: minutes)
        lastGoalMinutes = FastingTimeline.clampGoalMinutes(minutes)
    }

    private func saveEnd(_ date: Date) async {
        guard let store = await repo.storeHandle() else { return }
        if let running {
            await FastingLog.endFast(store, running, endedAt: date)
        } else if let latest, latest.endedAt != nil {
            await FastingLog.amendFast(store, latest, endedAt: date)
        }
    }

    /// A reminder setting changed: the notification and the banner re-planned at once.
    private func refreshSurroundings() async {
        guard let store = await repo.storeHandle() else { return }
        await FastingLog.refreshFastingSurroundings(store)
    }

    private func addWater(_ ml: Int) async {
        guard ml > 0 else { return }
        _ = await repo.logHydration(amountMl: ml, day: todayKey)
        waterTick += 1
    }

    private func undoWater() async {
        guard let last = repo.hydrationEntries(day: todayKey).last else { return }
        _ = await repo.deleteHydrationEntry(id: last.id, day: todayKey)
        waterTick += 1
    }

    /// What the Coach is told, in the page's own words.
    private func explainPhase(_ index: Int) async -> FastingExplainOutcome {
        let s = state
        var lastMeal: String?
        if let store = await repo.storeHandle(), let s {
            let dayKey = MealJournal.mealDayKey(s.startedAt)
            if let meals = try? await MealJournal.mealJournalDay(store, day: dayKey),
               let last = meals.filter({ $0.meal.eatenAt <= s.fast.startedAt }).max(by: { $0.meal.eatenAt < $1.meal.eatenAt }) {
                lastMeal = "\(last.meal.name), \(FastingFormat.dayAndClock(Date(timeIntervalSince1970: TimeInterval(last.meal.eatenAt)), now: now))"
            }
        }
        let status: String
        if let s, index == s.phaseIndex { status = s.isRunning ? "current" : "reached at the end" }
        else if let s, index < s.phaseIndex { status = "passed" }
        else { status = "to come" }
        let context = FastingCoachContext(
            phaseName: FastingPhaseText.name(index), phaseRange: FastingPhaseText.range(index), phaseStatus: status,
            elapsedText: FastingFormat.duration(minutes: s?.elapsedMinutes ?? 0),
            goalText: FastingFormat.duration(minutes: s?.fast.goalMinutes ?? pickedGoalMinutes),
            remainingText: FastingFormat.duration(minutes: s?.remainingMinutes ?? pickedGoalMinutes),
            startText: s.map { FastingFormat.dayAndClock($0.startedAt, now: now) } ?? "not started",
            plannedEndText: s.map { FastingFormat.dayAndClock($0.plannedEnd, now: now) } ?? "none",
            waterText: "\(FastingFormat.litres(ml: waterML)) of \(FastingFormat.litres(ml: Double(goalML)))",
            lastMealText: lastMeal)
        return await coach.explainFastingPhase(context)
    }
}
