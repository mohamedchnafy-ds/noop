import SwiftUI
import StrandDesign
import WhoopStore

// MARK: - Habitudes (personal fork, chantier 24, PR B)
//
// Mock-up validated 15 Nov. (https://claude.ai/artifact/1xoQf4BcjsQ8xHjeYUe3x1): reached from the More
// sheet. The stopwatch running on top, then one row per habit (its week's total, its last session, a ▶
// that starts it at once), then « New habit ». One stopwatch at a time: starting another habit asks
// first. No goal, no streak, no reminder. Every figure comes from `HabitLog`.

/// A habit's page, pushed by value from the list.
struct HabitRoute: Hashable {
    let habitId: String
}

/// The stopwatch just stopped, waiting for its note (the stop sheet).
struct HabitStopped: Identifiable {
    var habitName: String
    var session: HabitSessionRow
    var id: String { session.id }
}

struct HabitsView: View {
    @EnvironmentObject private var repo: Repository
    @AppStorage(HabitLog.revisionKey) private var revision = 0

    private struct Line: Identifiable {
        var habit: HabitRow
        var weekSeconds: Int
        var last: HabitSessionRow?
        var id: String { habit.id }
    }

    @State private var lines: [Line] = []
    @State private var running: HabitSessionRow?
    @State private var loaded = false
    @State private var creating = false
    @State private var stopped: HabitStopped?
    /// The habit whose ▶ was tapped while another stopwatch runs (the confirmation).
    @State private var switchTarget: HabitRow?

    private var runningHabit: HabitRow? {
        guard let running else { return nil }
        return lines.first { $0.habit.id == running.habitId }?.habit
    }

    var body: some View {
        ScreenScaffold(title: "Habits", trailing: {
            Button { creating = true } label: {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("New habit"))
        }) {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                if let running, let habit = runningHabit {
                    runningCard(running, habit: habit)
                }
                if loaded && lines.isEmpty {
                    emptyCard
                } else if !lines.isEmpty {
                    listCard
                }
                FastingActionButton(title: Text("New habit"), look: .secondary) { creating = true }
            }
            .opacity(loaded ? 1 : 0)
        }
        .navigationDestination(for: HabitRoute.self) { route in
            HabitDetailView(habitId: route.habitId)
                .background(StrandPalette.surfaceBase.ignoresSafeArea())
        }
        .task(id: "\(revision)-\(repo.refreshSeq)") { await reload() }
        .sheet(isPresented: $creating) {
            HabitEditor(habit: nil, sessionCount: 0,
                        onSave: { name, colorKey, symbol in
                            creating = false
                            Task { await create(name: name, colorKey: colorKey, symbol: symbol) }
                        },
                        onDelete: {}, onCancel: { creating = false })
        }
        .sheet(item: $stopped) { item in
            HabitStopSheet(habitName: item.habitName, session: item.session,
                           onSaveNote: { note in
                               stopped = nil
                               Task { await saveNote(note, on: item.session) }
                           },
                           onResume: {
                               stopped = nil
                               Task { await resume(item.session) }
                           },
                           onDiscard: {
                               stopped = nil
                               Task { await discard(item.session) }
                           })
        }
        .confirmationDialog(switchTitle, isPresented: Binding(get: { switchTarget != nil },
                                                              set: { if !$0 { switchTarget = nil } }),
                            titleVisibility: .visible) {
            if let target = switchTarget {
                Button {
                    switchTarget = nil
                    Task { await start(target) }
                } label: {
                    Text("Stop \(runningHabit?.name ?? "") and start \(target.name)")
                }
            }
            Button("Cancel", role: .cancel) { switchTarget = nil }
        } message: {
            Text("One stopwatch at a time.")
        }
    }

    private var switchTitle: Text {
        Text("\(runningHabit?.name ?? "") is running")
    }

    // MARK: Cards

    private func runningCard(_ session: HabitSessionRow, habit: HabitRow) -> some View {
        let start = Date(timeIntervalSince1970: TimeInterval(session.startedAt))
        return NoopCard(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    HabitIconTile(symbol: habit.symbol, colorKey: habit.colorKey, size: 26)
                    Text("\(habit.name) · since \(FastingFormat.clock(start))")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .lineLimit(1)
                }
                HabitStopwatchText(startedAt: start)
                FastingActionButton(title: Text("Stop"), look: .stop) {
                    Task { await stop(session, habit: habit) }
                }
            }
        }
    }

    private var emptyCard: some View {
        NoopCard(padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "timer")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(HabitPalette.tint(HabitPalette.defaultKey))
                    .accessibilityHidden(true)
                Text("Create a habit, then tap ▶ to time it.")
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                Text("Reading, meditation, an instrument… Each session keeps its time and a note if you want one. No goal and no reminder: you record when you choose.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var listCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                HStack(spacing: 12) {
                    NavigationLink(value: HabitRoute(habitId: line.habit.id)) {
                        HStack(spacing: 12) {
                            HabitIconTile(symbol: line.habit.symbol, colorKey: line.habit.colorKey)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: line.habit.name)
                                    .font(StrandFont.body)
                                    .foregroundStyle(StrandPalette.textPrimary)
                                    .lineLimit(1)
                                Text(verbatim: detail(line))
                                    .font(StrandFont.footnote)
                                    .foregroundStyle(StrandPalette.textSecondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 8)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    playButton(line.habit)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 62)
                .overlay(alignment: .bottom) {
                    if index < lines.count - 1 {
                        Rectangle().fill(StrandPalette.hairline).frame(height: NoopMetrics.hairlineWidth)
                    }
                }
            }
        }
        .background(StrandPalette.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: NoopVisualStyle.compactRadius, style: .continuous))
    }

    private func playButton(_ habit: HabitRow) -> some View {
        let isRunning = running?.habitId == habit.id
        return Button {
            if isRunning, let running {
                Task { await stop(running, habit: habit) }
            } else if running != nil {
                switchTarget = habit
            } else {
                Task { await start(habit) }
            }
        } label: {
            Image(systemName: isRunning ? "stop.fill" : "play.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(StrandPalette.surfaceBase)
                .frame(width: 40, height: 40)
                .background(isRunning ? StrandPalette.statusCritical : HabitPalette.tint(habit.colorKey), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRunning ? Text("Stop \(habit.name)") : Text("Start \(habit.name)"))
    }

    /// « 3h 25m this week · yesterday · 15 min », or « running ».
    private func detail(_ line: Line) -> String {
        var parts = [String(localized: "\(HabitFormat.duration(seconds: line.weekSeconds)) this week")]
        if running?.habitId == line.habit.id {
            parts.append(String(localized: "running"))
        } else if let last = line.last {
            let start = Date(timeIntervalSince1970: TimeInterval(last.startedAt))
            parts.append(FastingFormat.dayWord(start))
            parts.append(HabitFormat.duration(seconds: HabitLog.habitSessionSeconds(last, nowSec: last.startedAt)))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Reads and writes

    @MainActor
    private func reload() async {
        guard let store = await repo.storeHandle() else { loaded = true; return }
        let habits = await HabitLog.loadHabitList(store)
        var next: [Line] = []
        for habit in habits {
            let figures = await HabitLog.resolveHabitFigures(store, habitId: habit.id)
            let last = await HabitLog.loadHabitSessions(store, habitId: habit.id, limit: 1).first
            next.append(Line(habit: habit, weekSeconds: figures.weekSeconds, last: last))
        }
        lines = next
        running = await HabitLog.resolveRunningHabit(store)
        loaded = true
    }

    @MainActor
    private func create(name: String, colorKey: String, symbol: String) async {
        guard let store = await repo.storeHandle() else { return }
        await HabitLog.createHabit(store, name: name, colorKey: colorKey, symbol: symbol)
    }

    @MainActor
    private func start(_ habit: HabitRow) async {
        guard let store = await repo.storeHandle() else { return }
        await HabitLog.startHabitStopwatch(store, habitId: habit.id)
    }

    @MainActor
    private func stop(_ session: HabitSessionRow, habit: HabitRow) async {
        guard let store = await repo.storeHandle() else { return }
        let saved = await HabitLog.stopHabitStopwatch(store, session)
        stopped = HabitStopped(habitName: habit.name, session: saved)
    }

    @MainActor
    private func saveNote(_ note: String, on session: HabitSessionRow) async {
        guard HabitLog.storedNote(note) != nil, let store = await repo.storeHandle() else { return }
        let start = Date(timeIntervalSince1970: TimeInterval(session.startedAt))
        let end = session.endedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        await HabitLog.amendHabitSession(store, session, startedAt: start, endedAt: end, note: note)
    }

    @MainActor
    private func resume(_ session: HabitSessionRow) async {
        guard let store = await repo.storeHandle() else { return }
        await HabitLog.resumeHabitStopwatch(store, session)
    }

    @MainActor
    private func discard(_ session: HabitSessionRow) async {
        guard let store = await repo.storeHandle() else { return }
        await HabitLog.removeHabitSession(store, session)
    }
}
