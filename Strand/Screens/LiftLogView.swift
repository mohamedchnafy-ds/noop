import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

// The Lift Log: build a program once, then run it in the gym by tapping through it.
//
// This screen is the front door — it lists the saved programs and (from a later phase) the sessions
// run from them. It lives in the Effort colour world, like Workouts, because a finished session
// lands in the `workout` table beside every other workout.
//
// EFFORT IS NEVER MODIFIED HERE (load-bearing). NOOP's Effort is computed from heart rate alone
// (Karvonen %HRR → Edwards TRIMP, `StrainScorer`), and there is no validated public path from typed
// sets/reps/weight to a cardiovascular-strain equivalent — WHOOP's own muscular load runs
// velocity-based algorithms over strap accelerometer/gyroscope data under an unpublished model.
// So the lifting figures are shown BESIDE Effort and never folded into it, matching the choice the
// imported-lifting path already made (`strain: nil, // never a fabricated cardiovascular strain`).

// Personal fork: this screen is now « Training » (mockup « NOOP – Entraînement et Plus »). It keeps the
// Lift Log's programs, editor, import, session start and session detail, and adds the week plan
// (`TrainingWeekPlan`, fixed days), a week strip and a month grid of what was planned and done (Lift Log
// sessions in Effort blue, every other workout in orange), the Progression counts, and the other
// activities (start one, intervals, live heart rate, all history).

struct LiftLogView: View {
    @EnvironmentObject var repo: Repository

    /// Saved programs, most-recently-touched first. Loaded off the store on appear/refresh.
    @State private var programs: [LiftProgramRow] = []
    /// The same programs as the Training screen shows them (shape, usual length, last done, blocks).
    @State private var summaries: [TrainingProgramSummary] = []
    @State private var loaded = false

    /// The program being created or edited (nil = the editor is closed).
    @State private var editing: ProgramEditTarget?
    @State private var importing = false
    @State private var planning = false
    /// The live session, owned at the app root so it survives this screen going away.
    @EnvironmentObject private var session: LiftSessionController
    /// Lift Log sessions done (finished, with a working set) and every other workout, over the history.
    @State private var lifts: [TrainingLiftDone] = []
    @State private var activities: [TrainingActivityDone] = []
    /// The stored rows of the sessions done, for their detail sheet.
    @State private var sessionsById: [String: LiftSessionRow] = [:]
    /// Every finished session, judged: the Progression card and the screens it opens (personal fork).
    @State private var progress = LiftProgressData()
    /// The session whose detail sheet is open.
    @State private var viewing: SessionDetailTarget?
    /// The week plan, kept on the iPhone.
    @State private var plan = TrainingWeekPlan()
    @State private var mode: TrainingViewMode = .week
    /// The chosen day; the week and the month shown are the ones holding it.
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())

    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    /// Live Sessions (silent guardian, beta): the Settings switch, and the session screen (fork chantier 9:
    /// its start row moved here from Today).
    @AppStorage(LiveSessionPrefs.betaKey) private var liveSessionsBeta = true
    @State private var showLiveSession = false
    private var unitSystem: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    private var effortScale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }

    /// How far back the calendar reads (sessions, workouts).
    private static let historyDays = 400
    private var calendar: Calendar { .current }

    var body: some View {
        ScreenScaffold(title: nil, onRefresh: { await load() }) {
            // Fork chantier 7: 16 between the blocks; each section title adds its own 6 above it.
            VStack(alignment: .leading, spacing: NoopMetrics.space4) {
                header
                if mode == .week { weekSection } else { monthSection }
                daySection
                TrainingProgramsCard(programs: summaries, plan: plan, weekdays: TrainingText.shortWeekdays(calendar),
                                     loaded: loaded,
                                     onEdit: { id in
                                         editing = ProgramEditTarget(id: id, program: programs.first { $0.id == id })
                                     },
                                     onNew: { editing = ProgramEditTarget(id: "new", program: nil) },
                                     onImport: { importing = true },
                                     onPlan: { planning = true })
                TrainingProgressSummaryCard(data: progress) {
                    LiftProgressView(data: progress, unitSystem: unitSystem)
                }
                otherActivities
            }
        }
        // Also on a saved session: the session sheet lives above this screen and cannot tell it
        // directly, and a save does not always bump `refreshSeq`.
        .task(id: "\(repo.refreshSeq)-\(session.savedSessions)") { await load() }
        .sheet(item: $editing) { target in
            LiftProgramEditorSheet(program: target.program) {
                await load()
            }
        }
        .sheet(isPresented: $importing) {
            LiftProgramImportSheet { await load() }
        }
        .sheet(item: $viewing) { target in
            LiftSessionDetailSheet(session: target.session) { await load() }
        }
        .sheet(isPresented: $planning) {
            TrainingPlanSheet(programs: summaries, plan: plan) { saved in
                var next = saved
                if next.since == nil {
                    next.since = TrainingCalendar.trainingDayKey(Date(), calendar: calendar)
                }
                next.storeWeekPlan()
                plan = next
            }
        }
    }

    // MARK: - Header

    /// The title and the Week | Month switch, then the week or month shown with its count and ‹ ›
    /// (fork chantier 7: the count moved up from the bar above the week strip).
    private var header: some View {
        TrainingHeader(mode: $mode, subtitle: headerSubtitle,
                       onPrevious: { if mode == .week { shift(days: -7) } else { shift(months: -1) } },
                       onNext: { if mode == .week { shift(days: 7) } else { shift(months: 1) } })
    }

    /// "Week of 2 to 8 November · 0 / 3 sessions"; the month alone ("November 2026"), since the month's
    /// count is already in its totals under the grid.
    private var headerSubtitle: String {
        guard mode == .week else { return TrainingText.monthTitle(selectedDate) }
        let monday = TrainingCalendar.mondayOf(selectedDate, calendar: calendar)
        let tally = TrainingDays.sessionTally(days(TrainingCalendar.weekDates(from: monday, calendar: calendar)))
        return TrainingText.weekTitle(monday: monday, calendar: calendar) + " · "
            + TrainingText.tallyLine(done: tally.done, planned: tally.planned, current: nil)
    }

    // MARK: - Week and month

    private func days(_ dates: [Date]) -> [TrainingDay] {
        TrainingDays.buildTrainingDays(dates, plan: plan, lifts: lifts, activities: activities,
                                       now: Date(), calendar: calendar)
    }

    private var weekSection: some View {
        let monday = TrainingCalendar.mondayOf(selectedDate, calendar: calendar)
        let week = days(TrainingCalendar.weekDates(from: monday, calendar: calendar))
        return VStack(alignment: .leading, spacing: 10) {
            TrainingWeekStrip(days: week, selectedKey: key(selectedDate),
                              weekdays: TrainingText.shortWeekdays(calendar)) { selectedDate = $0.date }
            TrainingLegend()
        }
    }

    private var monthSection: some View {
        let cells = TrainingCalendar.monthCells(containing: selectedDate, calendar: calendar)
        let monthDays = days(cells.compactMap { $0 })
        let byKey = Dictionary(uniqueKeysWithValues: monthDays.map { ($0.key, $0) })
        let tally = TrainingDays.sessionTally(monthDays)
        let totals = TrainingDays.periodTotals(monthDays)
        return VStack(alignment: .leading, spacing: 10) {
            NoopCard(padding: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    TrainingMonthGrid(cells: cells.map { $0.flatMap { byKey[key($0)] } },
                                      selectedKey: key(selectedDate),
                                      weekdays: TrainingText.narrowWeekdays(calendar)) { selectedDate = $0.date }
                    TrainingLegend().padding(.horizontal, 6)
                }
            }
            TrainingMonthTotals(done: tally.done, planned: tally.planned,
                                activities: totals.activities, minutes: totals.minutes)
        }
    }

    // MARK: - The chosen day

    private var daySection: some View {
        let day = days([selectedDate]).first
        let openIds = Set(day?.openProgramIds ?? [])
        return Group {
            if let day {
                TrainingDaySection(day: day, programs: summaries,
                                   others: summaries.filter { !openIds.contains($0.id) },
                                   isRunning: session.isActive,
                                   onStart: { id in
                                       guard let program = programs.first(where: { $0.id == id }) else { return }
                                       Task { await start(program) }
                                   },
                                   onOpenLift: { lift in
                                       if let row = sessionsById[lift.sessionId] {
                                           viewing = SessionDetailTarget(id: row.id, session: row)
                                       }
                                   })
            }
        }
    }

    // MARK: - Other activities

    /// Fork chantier 7: the title in 20 bold, one flat card of rows with their icon alone (start an
    /// activity green, intervals orange, live heart rate pink, all history grey).
    private var otherActivities: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Other activities")
                .font(StrandFont.sectionTitle)
                .foregroundStyle(StrandPalette.textPrimary)
                .padding(.top, 6)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                TrainingStartActivityRow()
                NavigationLink {
                    IntervalTimerView()
                } label: {
                    TrainingActivityRowLabel(title: "Intervals", detail: "Work / recovery timer",
                                             symbol: "timer", tint: StrandPalette.caloriesActivity)
                }
                .buttonStyle(.plain)
                NavigationLink {
                    LiveView()
                } label: {
                    TrainingActivityRowLabel(title: "Live HR", detail: "Zones, curve and banner",
                                             symbol: "waveform.path.ecg", tint: StrandPalette.liquidHeart)
                }
                .buttonStyle(.plain)
                if liveSessionsBeta {
                    Button { showLiveSession = true } label: {
                        TrainingActivityRowLabel(title: "Start session (Beta)",
                                                 detail: "Silent strap coaching against today's Charge.",
                                                 symbol: "shield.lefthalf.filled", tint: StrandPalette.metricCyan)
                    }
                    .buttonStyle(.plain)
                }
                NavigationLink {
                    WorkoutsView()
                } label: {
                    TrainingActivityRowLabel(title: "All history", detail: "lifting and cardio",
                                             symbol: "list.bullet", tint: StrandPalette.textSecondary,
                                             showsDivider: false)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NoopPanelSurface())
        }
        .liveSessionCover(isPresented: $showLiveSession)
    }

    // MARK: - Navigation in time

    private func key(_ date: Date) -> String { TrainingCalendar.trainingDayKey(date, calendar: calendar) }

    private func shift(days: Int) {
        selectedDate = calendar.date(byAdding: .day, value: days, to: selectedDate) ?? selectedDate
    }

    /// Moves to the same day number of another month (clamped to its length), or today when that month
    /// is the current one.
    private func shift(months: Int) {
        guard let moved = calendar.date(byAdding: .month, value: months, to: selectedDate) else { return }
        if TrainingCalendar.monthStart(moved, calendar: calendar) == TrainingCalendar.monthStart(Date(), calendar: calendar) {
            selectedDate = calendar.startOfDay(for: Date())
        } else {
            selectedDate = moved
        }
    }

    // MARK: - Start a session

    /// Flatten a program into the plan the session runs. The plan is SNAPSHOT at start: editing or
    /// deleting the program mid-session cannot change what is being tapped through.
    private func start(_ program: LiftProgramRow) async {
        guard let store = await repo.storeHandle() else { return }
        let items = (try? await store.liftProgramItems(programId: program.id)) ?? []
        guard !items.isEmpty else { return }
        let vocabulary = (try? await store.liftExercises(deviceId: repo.deviceId)) ?? []

        let plan = items.map { item -> LiftPlanItem in
            // The classification comes from the exercise vocabulary, which is the one place that owns
            // it — the program line deliberately stores no muscle of its own to drift from.
            let known = vocabulary.first { $0.name == item.exercise }
            return LiftPlanItem(exercise: item.exercise,
                                primaryMuscle: known?.primaryMuscle,
                                secondaryMuscles: known?.secondaryMuscles ?? [],
                                targetSets: item.targetSets,
                                restSec: item.restSec,
                                targetRepsLow: item.targetRepsLow,
                                targetRepsHigh: item.targetRepsHigh,
                                targetRpe: item.targetRpe,
                                targetWeightKg: item.targetWeightKg,
                                note: item.note,
                                // Carried so a set added or dropped mid-session can be written back
                                // onto the line it came from, and be there next time.
                                programItemId: item.id,
                                supersetGroup: item.supersetGroup)
        }
        // Refuse to start a second session over a running one: two live sessions would both claim
        // the strap gesture and both write the in-flight snapshot.
        guard !session.isActive else {
            session.isPresented = true
            return
        }
        session.start(plan: plan, programId: program.id, programName: program.name)
    }

    // MARK: - Load

    private func load() async {
        guard let store = await repo.storeHandle() else { return }
        let owner = repo.deviceId
        let rows = (try? await store.liftPrograms(deviceId: owner)) ?? []
        var itemsByProgram: [String: [LiftProgramItemRow]] = [:]
        for program in rows {
            itemsByProgram[program.id] = (try? await store.liftProgramItems(programId: program.id)) ?? []
        }

        // Sessions done: finished, with at least one working set (the rotation's rule).
        let now = Int(Date().timeIntervalSince1970)
        let sessions = (try? await store.liftSessions(deviceId: owner,
                                                      fromTs: now - Self.historyDays * 86_400,
                                                      toTs: now + 86_400)) ?? []
        var done: [(row: LiftSessionRow, working: Int)] = []
        for row in sessions where row.endTs != nil {
            let sets = (try? await store.liftSets(sessionId: row.id)) ?? []
            let working = sets.filter(LiftRotation.isWorking).count
            if working > 0 { done.append((row, working)) }
        }

        // Every workout but the sessions' own rows, so a Lift Log session is never counted twice.
        let workouts = await repo.workoutRows(days: Self.historyDays + 1)
        let split = TrainingDays.splitLiftWorkouts(workouts, liftStarts: done.map { $0.row.startTs })
        let scale = effortScale
        // A session's length is its own workout row's, pauses left out (`TrainingDays.liftSessionSeconds`).
        func length(_ row: LiftSessionRow, end: Int) -> Int {
            TrainingDays.liftSessionSeconds(startTs: row.startTs, endTs: end, workout: split.lift[row.startTs])
        }
        lifts = done.map { entry in
            let end = entry.row.endTs ?? entry.row.startTs
            return TrainingLiftDone(sessionId: entry.row.id, programId: entry.row.programId,
                                    name: entry.row.programName ?? String(localized: "Session"),
                                    startTs: entry.row.startTs, endTs: end,
                                    workingSets: entry.working,
                                    effort: split.lift[entry.row.startTs]?.strain.map { UnitFormatter.effortDisplay($0, scale: scale) },
                                    activeSeconds: length(entry.row, end: end))
        }
        activities = split.others.map { row in
            TrainingActivityDone(sport: row.sport,
                                 source: Self.trainingSourceLabel(row.source),
                                 startTs: row.startTs, endTs: row.endTs,
                                 kcal: row.energyKcal.map { Int($0.rounded()) })
        }
        sessionsById = Dictionary(done.map { ($0.row.id, $0.row) }, uniquingKeysWith: { first, _ in first })

        summaries = rows.map { program in
            let finished = done.filter { $0.row.programId == program.id }
                .compactMap { entry in
                    entry.row.endTs.map { (startTs: entry.row.startTs,
                                           endTs: entry.row.startTs + length(entry.row, end: $0)) }
                }
            return TrainingDays.programSummary(id: program.id, name: program.name,
                                               items: itemsByProgram[program.id] ?? [], finished: finished)
        }
        programs = rows
        // A deleted program frees its day.
        plan = TrainingWeekPlan.loadWeekPlan().keepingPrograms(Set(rows.map(\.id)))

        let step = unitSystem == .imperial ? LiftProgression.imperialStepKg : LiftProgression.metricStepKg
        if let data = await LiftProgressData.load(repo: repo, stepKg: step) { progress = data }
        loaded = true
    }

    /// Where another activity comes from, in a word.
    static func trainingSourceLabel(_ source: String) -> String {
        switch WorkoutSource.classify(source) {
        case .detected: return String(localized: "detected")
        case .manual: return String(localized: "recorded")
        case .apple: return String(localized: "Apple Health")
        case .whoop: return "WHOOP"
        case .lifting, .activityFile: return String(localized: "imported")
        }
    }
}

/// « Start an activity »: names a sport, then opens the live workout — the same flow as Workouts' Start
/// workout (`WorkoutStartControl`). Its own view so only this row observes `AppModel`.
private struct TrainingStartActivityRow: View {
    @EnvironmentObject var model: AppModel
    @State private var showLiveWorkout = false
    @State private var showStartSport = false

    var body: some View {
        Button {
            if model.activeWorkout == nil { showStartSport = true } else { showLiveWorkout = true }
        } label: {
            TrainingActivityRowLabel(title: "Start an activity",
                                     detail: "Run, ride, walk… with the strap's heart rate",
                                     symbol: "figure.run", tint: StrandPalette.chargeColor)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showLiveWorkout) {
            LiveWorkoutView(onClose: { showLiveWorkout = false })
                .environmentObject(model.live)
        }
        .workoutSelectionCover(isPresented: $showStartSport) {
            StartWorkoutSheet { name in
                model.startWorkout(sport: name)
                showLiveWorkout = true
            }
        }
    }
}

/// The session whose detail is being read back. A wrapper rather than a retroactive `Identifiable`
/// on `LiftSessionRow`, keeping the store's row types free of app-layer conformances.
private struct SessionDetailTarget: Identifiable {
    let id: String
    let session: LiftSessionRow
}


/// Identifies what the editor sheet is editing. A wrapper rather than a retroactive `Identifiable`
/// on `LiftProgramRow`, so the store's row types stay free of app-layer conformances — and so
/// "new program" has an identity of its own to present on.
private struct ProgramEditTarget: Identifiable {
    let id: String
    let program: LiftProgramRow?
}
