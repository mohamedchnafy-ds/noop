import SwiftUI
import StrandDesign
import WhoopStore

// MARK: - Élan (personal fork, chantier 10, PR B · PR C)
//
// The motivation section, opened from the head of the Plus sheet (mockup v2.1, validated 5 Nov.; animated
// mockup validated 8 Nov.). Three tabs under the title: Semaine (the recap), Progrès (Avant / maintenant,
// the weight, what was built), Lectures (the essentials, the daily reading with PR D). Everything shown
// comes from ONE read, `ElanResolver.loadElanState` (plus Progression's data and the Historique's bars), so
// no two cards can disagree. The entrances replay at each showing and at each change of tab (chantier 12).
// Nothing here lives on Today: Élan comes to the wearer by its notifications only (PR C), whose actions
// arrive through `NavRouter.elanRequest` (the short session, the weigh-in); the bell opens the Rappels.

struct ElanView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @EnvironmentObject private var router: NavRouter
    @EnvironmentObject private var coach: AICoachEngine
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue

    @State private var tab: ElanTab = .week
    /// Bumped at each change of tab: the tab's entrances play again (the mockup's rule 1).
    @State private var showing = 0
    @State private var state: ElanState?
    @State private var progress: LiftProgressData?
    @State private var victories: ElanVictories?
    @State private var figures = ElanFigures()
    @State private var bars: [WorkoutHistoryBar] = []
    /// The short session built for today's proposal (`ElanState.shortTarget`); nil without one.
    @State private var shortPlan: ElanShortSessionPlan?
    @State private var readFilter: ElanReadingTheme?
    @State private var readIds: Set<String> = ElanReadLog.readIds()
    @State private var sheet: Sheet?
    @State private var reload = 0
    /// Bumped when the short session is accepted: the success haptic (rule 7).
    @State private var accepted = 0

    private enum Sheet: Identifiable {
        case why, weighIn, shortSession
        var id: Int {
            switch self {
            case .why: return 0
            case .weighIn: return 1
            case .shortSession: return 2
            }
        }
    }

    private var unitSystem: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }

    private var today: String { TrainingCalendar.trainingDayKey(Date(), calendar: .current) }

    /// The short session is still to be decided today: proposed, neither declined nor accepted.
    private var shortSessionOpen: Bool {
        guard let state, state.shortTarget != nil else { return false }
        return !state.shortSessionDismissed && state.shortSessionAccepted == nil
    }

    var body: some View {
        ScreenScaffold(title: "Élan", trailing: {
            NavigationLink(value: ElanRoute.reminders) {
                Image(systemName: "bell")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Reminders"))
        }) {
            VStack(alignment: .leading, spacing: NoopVisualStyle.itemGap) {
                Text(verbatim: ElanFormat.longDate(Date()))
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .padding(.top, -8)
                SegmentedPillControl([ElanTab.week, .progress, .read], selection: $tab, fillsAvailableWidth: true) { tab in
                    switch tab {
                    case .week: return String(localized: "Week")
                    case .progress: return String(localized: "Progress")
                    case .read: return String(localized: "Readings")
                    }
                }
                .padding(.bottom, 4)
                content
            }
        }
        .noopEntranceRoot()
        .navigationDestination(for: ElanRoute.self) { route in
            destination(route)
                .background(StrandPalette.surfaceBase.ignoresSafeArea())
        }
        .sheet(item: $sheet, onDismiss: { readIds = ElanReadLog.readIds(); reload += 1 }) { which in
            switch which {
            case .why:
                ElanWhySheet()
            case .weighIn:
                ElanWeighInSheet(summary: state?.weight ?? ElanWeight.weightSummary(weighIns: [], targetKg: nil),
                                 unitSystem: unitSystem, defaultKg: profile.weightKg)
                    .environmentObject(repo)
                    .environmentObject(profile)
            case .shortSession:
                if let shortPlan, let state {
                    ElanShortSessionSheet(plan: shortPlan, unitSystem: unitSystem,
                                          weekDoneAfter: state.week.done + 1, weekPlanned: state.week.planned,
                                          onAccept: { acceptShort(start: false) },
                                          onStartNow: { acceptShort(start: true) })
                        .environmentObject(repo)
                        .environmentObject(router)
                        .environmentObject(coach)
                }
            }
        }
        .elanSuccessHaptic(trigger: accepted)
        .task(id: "\(repo.refreshSeq)-\(reload)") { await load() }
        .onChangeCompat(of: tab) { _ in showing += 1 }
        .onChangeCompat(of: router.elanRequest) { _ in consumeRequest() }
        .onAppear { readIds = ElanReadLog.readIds() }
    }

    @ViewBuilder
    private var content: some View {
        if let state {
            switch tab {
            case .week:
                ElanWeekTabView(state: state, victories: victories, unitSystem: unitSystem, showing: showing,
                                onEditWhy: { sheet = .why },
                                onDismissShort: { dismissShort() },
                                onShortSession: shortPlan == nil ? nil : { sheet = .shortSession },
                                onWithdrawShort: { withdrawShort() },
                                shortMinutes: shortPlan?.estimatedMinutes)
            case .progress:
                ElanProgressTabView(state: state, bars: bars, gains: victories?.gains ?? [], unitSystem: unitSystem,
                                    showing: showing, weighedToday: state.weight.latest?.day == today,
                                    onWeighIn: { sheet = .weighIn })
            case .read:
                ElanReadTabView(readings: ElanEssentials.bundled, filter: $readFilter, readIds: readIds)
            }
        } else {
            NoopCard(padding: 18) {
                Text("Reading your week…")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
        }
    }

    @ViewBuilder
    private func destination(_ route: ElanRoute) -> some View {
        switch route {
        case .comparison:
            if let state {
                ElanComparisonView(state: state, bars: bars, gains: victories?.gains ?? [], unitSystem: unitSystem,
                                   onShortSession: shortSessionOpen && shortPlan != nil ? { sheet = .shortSession } : nil,
                                   shortMinutes: shortPlan?.estimatedMinutes)
            }
        case .weight:
            if let state {
                ElanWeightView(state: state, bestGain: victories?.bestGain, unitSystem: unitSystem,
                               defaultKg: profile.weightKg, onChanged: { reload += 1 })
            }
        case .reading(let id):
            if let reading = ElanEssentials.bundled.first(where: { $0.id == id }) {
                ElanReadingView(reading: reading, figures: figures)
            }
        case .progression:
            if let progress {
                LiftProgressView(data: progress, unitSystem: unitSystem)
            } else {
                NoopCard(padding: 18) {
                    Text("Progression needs a finished session.")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
                .padding(NoopVisualStyle.pagePadding)
            }
        case .reminders:
            RemindersView()
        }
    }

    // MARK: The short session

    private func dismissShort() {
        ElanShortSessionChoice.dismiss(day: today)
        reload += 1
    }

    /// « Retirer »: the accepted session leaves today, and is not proposed again that day.
    private func withdrawShort() {
        ElanShortSessionChoice.withdraw(day: today)
        reload += 1
    }

    /// « Ce soir · l'ajouter à aujourd'hui » (the card becomes « Ajoutée à aujourd'hui », the day's mark turns
    /// sand, the haptic), or « Démarrer maintenant »: accepted the same way, then started through the start
    /// the session widget uses (`NavRouter.widgetStart`), which closes the Plus sheet and runs the short plan.
    private func acceptShort(start: Bool) {
        guard let shortPlan else { return }
        ElanShortSessionChoice.accept(day: today, programId: shortPlan.programId)
        sheet = nil
        accepted += 1
        reload += 1
        if start {
            let programId = shortPlan.programId
            let name = shortPlan.programName
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                router.widgetStart = .program(id: programId, name: name)
            }
        }
    }

    /// What a notification's action asked Élan to present, once the state is read.
    private func consumeRequest() {
        guard state != nil, let request = router.elanRequest else { return }
        router.elanRequest = nil
        switch request {
        case .shortSession:
            if shortSessionOpen, shortPlan != nil { sheet = .shortSession }
        case .weighIn:
            sheet = .weighIn
        }
    }

    @MainActor
    private func load() async {
        let step = unitSystem == .imperial ? LiftProgression.imperialStepKg : LiftProgression.metricStepKg
        let progressRead = await LiftProgressData.load(repo: repo, stepKg: step)
        progress = progressRead
        let now = Date()
        let loaded = await ElanResolver.loadElanState(repo: repo, profile: profile, now: now, progress: progressRead)
        let rows = await repo.workoutRows(days: 12 * 7 + 7)
        bars = WorkoutHistoryLogic.historyBars(rows, days: 84, anchorTs: Int(now.timeIntervalSince1970), calendar: .current)
        if let loaded {
            victories = ElanVictoryRules.elanVictories(exercises: progressRead?.exercises ?? [], weeks: loaded.recentWeeks,
                                                       now: now, calendar: .current)
        }
        figures = await ElanFigures.loadElanFigures(repo: repo, profile: profile, sessionsThisWeek: loaded?.week.done, now: now)
        if let target = loaded?.shortTarget {
            shortPlan = await ElanShortSession.loadElanShortSession(repo: repo, programId: target.programId)
        } else {
            shortPlan = nil
        }
        state = loaded
        consumeRequest()
    }
}
