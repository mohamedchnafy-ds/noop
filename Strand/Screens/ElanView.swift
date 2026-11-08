import SwiftUI
import StrandDesign
import WhoopStore

// MARK: - Élan (personal fork, chantier 10, PR B)
//
// The motivation section, opened from the head of the Plus sheet (mockup v2.1, validated 5 Nov.; animated
// mockup validated 8 Nov.). Three tabs under the title: Semaine (the recap), Progrès (Avant / maintenant,
// the weight, what was built), Lectures (the essentials, the daily reading with PR D). Everything shown
// comes from ONE read, `ElanResolver.loadElanState` (plus Progression's data and the Historique's bars), so
// no two cards can disagree. The entrances replay at each showing and at each change of tab (chantier 12).
// Nothing here lives on Today: Élan comes to the wearer by its notifications only (PR C).

struct ElanView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue

    @State private var tab: ElanTab = .week
    /// Bumped at each change of tab: the tab's entrances play again (the mockup's rule 1).
    @State private var showing = 0
    @State private var state: ElanState?
    @State private var progress: LiftProgressData?
    @State private var victories: ElanVictories?
    @State private var figures = ElanFigures()
    @State private var bars: [WorkoutHistoryBar] = []
    @State private var readFilter: ElanReadingTheme?
    @State private var readIds: Set<String> = ElanReadLog.readIds()
    @State private var sheet: Sheet?
    @State private var reload = 0

    private enum Sheet: Identifiable {
        case why, weighIn
        var id: Int { self == .why ? 0 : 1 }
    }

    private var unitSystem: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }

    private var today: String { TrainingCalendar.trainingDayKey(Date(), calendar: .current) }

    var body: some View {
        ScreenScaffold(title: "Élan") {
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
            }
        }
        .task(id: "\(repo.refreshSeq)-\(reload)") { await load() }
        .onChangeCompat(of: tab) { _ in showing += 1 }
        .onAppear { readIds = ElanReadLog.readIds() }
    }

    @ViewBuilder
    private var content: some View {
        if let state {
            switch tab {
            case .week:
                ElanWeekTabView(state: state, victories: victories, unitSystem: unitSystem, showing: showing,
                                onEditWhy: { sheet = .why },
                                onDismissShort: { dismissShort() })
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
                ElanComparisonView(state: state, bars: bars, gains: victories?.gains ?? [], unitSystem: unitSystem)
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
        }
    }

    private func dismissShort() {
        ElanShortSessionChoice.dismiss(day: today)
        reload += 1
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
        state = loaded
    }
}
