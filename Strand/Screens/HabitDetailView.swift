import SwiftUI
import StrandDesign
import WhoopStore

// MARK: - A habit's page (personal fork, chantier 24, PR B)
//
// The stopwatch (or Start), the totals (this week · this month · all time), the bars (W · M · 3M), « When »
// (the time of day of the last 30 days) and the sessions with their notes; « + Past session »; « ••• »
// edits the habit. Every figure is `HabitLog.resolveHabitFigures`, the one resolver.

struct HabitDetailView: View {
    let habitId: String
    @EnvironmentObject private var repo: Repository
    @Environment(\.dismiss) private var dismiss
    @AppStorage(HabitLog.revisionKey) private var revision = 0

    @State private var habit: HabitRow?
    @State private var habits: [HabitRow] = []
    @State private var figures: HabitFigures?
    @State private var sessions: [HabitSessionRow] = []
    @State private var running: HabitSessionRow?
    @State private var loaded = false
    @State private var period: HabitChartPeriod = .week
    @State private var selectedBar: Int?
    @State private var sheet: Sheet?
    @State private var stopped: HabitStopped?
    @State private var confirmsSwitch = false

    private enum Sheet: Identifiable {
        case newSession
        case editSession(HabitSessionRow)
        case editHabit
        var id: String {
            switch self {
            case .newSession: return "new"
            case .editSession(let session): return "edit-\(session.id)"
            case .editHabit: return "habit"
            }
        }
    }

    private var runsHere: Bool { running != nil && running?.habitId == habitId }

    private var otherRunningName: String? {
        guard let running, running.habitId != habitId else { return nil }
        return habits.first { $0.id == running.habitId }?.name
    }

    var body: some View {
        ScreenScaffold(title: nil, trailing: {
            Button { sheet = .editHabit } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Edit the habit"))
        }) {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                if let habit {
                    HStack(spacing: 12) {
                        HabitIconTile(symbol: habit.symbol, colorKey: habit.colorKey, size: 40)
                        Text(verbatim: habit.name)
                            .font(StrandFont.screenTitle)
                            .foregroundStyle(StrandPalette.textPrimary)
                            .lineLimit(2)
                    }
                    stopwatchCard(habit)
                    totals
                    chartCard(habit)
                    whenCard(habit)
                    sessionsSection(habit)
                }
            }
            .opacity(loaded ? 1 : 0)
        }
        .task(id: "\(revision)-\(repo.refreshSeq)") { await reload() }
        .sheet(item: $sheet) { which in
            switch which {
            case .newSession:
                HabitSessionEditor(habitName: habit?.name ?? "", session: nil,
                                   onSave: { start, end, note in await addSession(start: start, end: end, note: note) },
                                   onDelete: {}, onCancel: { sheet = nil })
            case .editSession(let session):
                HabitSessionEditor(habitName: habit?.name ?? "", session: session,
                                   onSave: { start, end, note in
                                       await amend(session, start: start, end: end, note: note)
                                   },
                                   onDelete: {
                                       sheet = nil
                                       Task { await remove(session) }
                                   },
                                   onCancel: { sheet = nil })
            case .editHabit:
                HabitEditor(habit: habit, sessionCount: figures?.allTime.count ?? sessions.count,
                            onSave: { name, colorKey, symbol in
                                sheet = nil
                                Task { await editHabit(name: name, colorKey: colorKey, symbol: symbol) }
                            },
                            onDelete: {
                                sheet = nil
                                Task { await deleteHabit() }
                            },
                            onCancel: { sheet = nil })
            }
        }
        .sheet(item: $stopped) { item in
            HabitStopSheet(habitName: item.habitName, session: item.session,
                           onSaveNote: { note in
                               stopped = nil
                               Task {
                                   _ = await amend(item.session, start: date(item.session.startedAt),
                                                   end: item.session.endedAt.map(date), note: note)
                               }
                           },
                           onResume: {
                               stopped = nil
                               Task { await resume(item.session) }
                           },
                           onDiscard: {
                               stopped = nil
                               Task { await remove(item.session) }
                           })
        }
        .confirmationDialog(Text("\(otherRunningName ?? "") is running"), isPresented: $confirmsSwitch,
                            titleVisibility: .visible) {
            Button {
                Task { await start() }
            } label: {
                Text("Stop \(otherRunningName ?? "") and start \(habit?.name ?? "")")
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("One stopwatch at a time.")
        }
    }

    // MARK: Cards

    private func stopwatchCard(_ habit: HabitRow) -> some View {
        NoopCard(padding: 14) {
            if let running, runsHere {
                let start = date(running.startedAt)
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Running since \(FastingFormat.clock(start))")
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textSecondary)
                        HabitStopwatchText(startedAt: start, font: StrandFont.number(32, weight: .bold))
                    }
                    Spacer(minLength: 8)
                    Button {
                        Task { await stop(running, habit: habit) }
                    } label: {
                        Text("Stop")
                            .font(StrandFont.body.weight(.bold))
                            .foregroundStyle(StrandPalette.onDarkPrimary)
                            .padding(.horizontal, 22)
                            .frame(minHeight: 48)
                            .background(StrandPalette.statusCritical, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            } else {
                FastingActionButton(title: Text("Start"), look: .primary) {
                    if otherRunningName != nil { confirmsSwitch = true } else { Task { await start() } }
                }
            }
        }
    }

    private var totals: some View {
        HStack(spacing: 8) {
            totalTile(figures?.weekSeconds ?? 0, label: Text("This week"))
            totalTile(figures?.monthSeconds ?? 0, label: Text("This month"))
            if let first = figures?.allTime.firstStartedAt {
                totalTile(figures?.allTime.totalSeconds ?? 0,
                          label: Text("Since \(date(first).formatted(.dateTime.day().month(.abbreviated)))"))
            } else {
                totalTile(0, label: Text("All time"))
            }
        }
    }

    private func totalTile(_ seconds: Int, label: Text) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: HabitFormat.duration(seconds: seconds))
                .font(StrandFont.number(19, weight: .bold))
                .foregroundStyle(StrandPalette.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            label
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StrandPalette.surfaceRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func chartCard(_ habit: HabitRow) -> some View {
        NoopCard(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                Picker(selection: $period) {
                    Text("Week").tag(HabitChartPeriod.week)
                    Text("Month").tag(HabitChartPeriod.month)
                    Text("3 months").tag(HabitChartPeriod.quarter)
                } label: {
                    Text("Period")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: period) { _ in selectedBar = nil }
                HabitBarsChart(bars: figures?.bars(period) ?? [], period: period, colorKey: habit.colorKey,
                               selected: $selectedBar)
            }
        }
    }

    private func whenCard(_ habit: HabitRow) -> some View {
        NoopCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text("When")
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                HabitDayStrip(spans: figures?.daySpans ?? [], colorKey: habit.colorKey)
                Text("The time of day of your sessions over the last 30 days.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
        }
    }

    private func sessionsSection(_ habit: HabitRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Your sessions")
                    .font(StrandFont.sectionTitle)
                    .foregroundStyle(StrandPalette.textPrimary)
                Spacer()
                Button { sheet = .newSession } label: {
                    Text("+ Add a session")
                        .font(StrandFont.subhead.weight(.semibold))
                        .foregroundStyle(StrandPalette.accent)
                }
                .buttonStyle(.plain)
            }
            if sessions.isEmpty {
                Text("No session yet. Tap Start, or add a past session.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                        Button { sheet = .editSession(session) } label: {
                            sessionRow(session)
                        }
                        .buttonStyle(.plain)
                        .overlay(alignment: .bottom) {
                            if index < sessions.count - 1 {
                                Rectangle().fill(StrandPalette.hairline).frame(height: NoopMetrics.hairlineWidth)
                            }
                        }
                    }
                }
                .background(StrandPalette.surfaceRaised,
                            in: RoundedRectangle(cornerRadius: NoopVisualStyle.compactRadius, style: .continuous))
            }
        }
    }

    private func sessionRow(_ session: HabitSessionRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: HabitFormat.sessionWhen(session))
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if session.endedAt == nil {
                    Text("running")
                        .font(StrandFont.subhead.weight(.semibold))
                        .foregroundStyle(HabitPalette.tint(habit?.colorKey ?? HabitPalette.defaultKey))
                } else {
                    Text(verbatim: HabitFormat.duration(seconds: HabitLog.habitSessionSeconds(session, nowSec: session.startedAt)))
                        .font(StrandFont.subhead.weight(.semibold))
                        .foregroundStyle(StrandPalette.textPrimary)
                        .monospacedDigit()
                }
            }
            if let note = session.note {
                Text(verbatim: note)
                    .font(StrandFont.footnote.italic())
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if session.isManual {
                Text("added by hand")
                    .font(StrandFont.caption2)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    // MARK: Reads and writes

    private func date(_ seconds: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(seconds)) }

    @MainActor
    private func reload() async {
        guard let store = await repo.storeHandle() else { loaded = true; return }
        habits = await HabitLog.loadHabitList(store)
        guard let found = habits.first(where: { $0.id == habitId }) else {
            // The habit was deleted (here or elsewhere): its page has nothing left to show.
            if loaded { dismiss() }
            loaded = true
            return
        }
        habit = found
        figures = await HabitLog.resolveHabitFigures(store, habitId: habitId)
        sessions = await HabitLog.loadHabitSessions(store, habitId: habitId)
        running = await HabitLog.resolveRunningHabit(store)
        loaded = true
    }

    @MainActor
    private func start() async {
        guard let store = await repo.storeHandle() else { return }
        await HabitLog.startHabitStopwatch(store, habitId: habitId)
    }

    @MainActor
    private func stop(_ session: HabitSessionRow, habit: HabitRow) async {
        guard let store = await repo.storeHandle() else { return }
        let saved = await HabitLog.stopHabitStopwatch(store, session)
        stopped = HabitStopped(habitName: habit.name, session: saved)
    }

    @MainActor
    private func resume(_ session: HabitSessionRow) async {
        guard let store = await repo.storeHandle() else { return }
        await HabitLog.resumeHabitStopwatch(store, session)
    }

    @MainActor
    private func addSession(start: Date, end: Date?, note: String) async -> HabitSessionProblem? {
        guard let store = await repo.storeHandle() else { return nil }
        let problem = await HabitLog.addHabitSessionByHand(store, habitId: habitId, startedAt: start,
                                                           endedAt: end ?? start, note: note)
        if problem == nil { sheet = nil }
        return problem
    }

    @MainActor
    private func amend(_ session: HabitSessionRow, start: Date, end: Date?, note: String) async -> HabitSessionProblem? {
        guard let store = await repo.storeHandle() else { return nil }
        let problem = await HabitLog.amendHabitSession(store, session, startedAt: start, endedAt: end, note: note)
        if problem == nil { sheet = nil }
        return problem
    }

    @MainActor
    private func remove(_ session: HabitSessionRow) async {
        guard let store = await repo.storeHandle() else { return }
        await HabitLog.removeHabitSession(store, session)
    }

    @MainActor
    private func editHabit(name: String, colorKey: String, symbol: String) async {
        guard let store = await repo.storeHandle(), let habit else { return }
        await HabitLog.editHabit(store, habit, name: name, colorKey: colorKey, symbol: symbol)
    }

    @MainActor
    private func deleteHabit() async {
        guard let store = await repo.storeHandle(), let habit else { return }
        await HabitLog.removeHabit(store, habit)
        dismiss()
    }
}
