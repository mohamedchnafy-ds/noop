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
//
// Fork chantier 9 (section 5, mockup « Entraînement proposé »): the week, then ONE card for the chosen day
// (the program in large with the loads to raise, cardio on a line with its own Start, what was done), then
// Progression, Programs and Other activities in the order « Customize Training » keeps
// (`TrainingLayoutPrefs`), each of them hideable there.

struct LiftLogView: View {
    @EnvironmentObject var repo: Repository

    /// Saved programs, most-recently-touched first. Loaded off the store on appear/refresh.
    @State private var programs: [LiftProgramRow] = []
    /// The same programs as the Training screen shows them (shape, usual length, last done, blocks).
    @State private var summaries: [TrainingProgramSummary] = []
    @State private var loaded = false

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
    /// Élan's short session accepted for today (personal fork, chantier 10 PR C): today's card shows it in
    /// place of the whole program, and its Start runs it.
    @State private var elanShort: ElanShortSessionPlan?
    @AppStorage(ElanShortSessionChoice.revisionKey) private var elanRevision = 0
    @State private var mode: TrainingViewMode = .week
    /// Fork chantier 18: the legend, shown by the header's « i ».
    @State private var showsLegend = false
    /// Fork chantier 18: « Other session » opens the « Start » sheet.
    @State private var showStart = false
    /// Fork chantier 18 (« + Exercise »): today's additions by program, and the program being added to.
    @State private var dayAdditions: [String: [LiftDayAddition]] = [:]
    /// The program lines left out for today, by program (the day card's list of every exercise).
    @State private var dayLeftOut: [String: Set<String>] = [:]
    @State private var addingTo: ProgramAddTarget?
    @AppStorage(LiftDayAdditions.revisionKey) private var additionsRevision = 0
    /// The chosen day; the week and the month shown are the ones holding it.
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())

    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    /// Live Sessions (silent guardian, beta): the Settings switch, and the session screen (fork chantier 9:
    /// its start row moved here from Today).
    @AppStorage(LiveSessionPrefs.betaKey) private var liveSessionsBeta = true
    @State private var showLiveSession = false
    /// Planned cardio whose Start was tapped: its stored sport name, until the live workout opens.
    @State private var cardioToStart: String?
    @State private var showCustomize = false
    @AppStorage(TrainingLayoutPrefs.orderKey) private var sectionOrderRaw = ""
    @AppStorage(TrainingLayoutPrefs.hiddenKey) private var hiddenSectionsRaw = ""
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
                ForEach(TrainingLayoutPrefs.shownSections(orderRaw: sectionOrderRaw, hiddenRaw: hiddenSectionsRaw)) {
                    pageSection($0)
                }
                Button { showCustomize = true } label: {
                    LiquidFullWidthNavigationAction("Customize Training")
                }
                .buttonStyle(.plain)
            }
        }
        .background(TrainingCardioLauncher(request: $cardioToStart))
        .sheet(isPresented: $showStart) {
            StartSheet()
                #if os(iOS)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                #endif
        }
        .liveSessionCover(isPresented: $showLiveSession)
        .sheet(isPresented: $showCustomize) {
            TrainingCustomizeSheet(sectionOrderRaw: $sectionOrderRaw, hiddenSectionsRaw: $hiddenSectionsRaw)
        }
        // Also on a saved session: the session sheet lives above this screen and cannot tell it
        // directly, and a save does not always bump `refreshSeq`.
        .task(id: "\(repo.refreshSeq)-\(session.savedSessions)-\(elanRevision)") { await load() }
        .sheet(item: $viewing) { target in
            LiftSessionDetailSheet(session: target.session) { await load() }
        }
        .sheet(item: $addingTo) { target in
            LiftSessionExerciseSheet(destination: .today) { name, primary, secondaries in
                LiftDayAdditions.add(LiftDayAddition(id: UUID().uuidString, exercise: name,
                                                     primaryMuscle: primary, secondaryMuscles: secondaries),
                                     day: todayKey, programId: target.id)
                readDayAdditions()
            }
        }
        .onChange(of: additionsRevision) { _ in readDayAdditions() }
    }

    private var todayKey: String { TrainingCalendar.trainingDayKey(Date(), calendar: calendar) }

    private func readDayAdditions() {
        dayAdditions = LiftDayAdditions.additionsByProgram(day: todayKey)
        dayLeftOut = LiftDayAdditions.removedLinesByProgram(day: todayKey)
    }

    // MARK: - Sections

    /// Fork chantier 18 (maquette 2): each block is one line. Progression says how many loads are ready to
    /// raise; Programs opens the list with New, Import and Plan the week; Other activities is « Other session »
    /// (the « Start » sheet) and the history, with the Beta session when Live Sessions are on.
    @ViewBuilder private func pageSection(_ section: TrainingSection) -> some View {
        switch section {
        case .progression:
            NavigationLink {
                LiftProgressView(data: progress, unitSystem: unitSystem)
            } label: {
                let raises = progress.readyExercises.count
                TrainingLineLabel(
                    title: Text("Progression"),
                    detail: raises == 1 ? Text("1 load to raise")
                        : raises > 1 ? Text(String(localized: "\(raises) loads to raise"))
                        : Text("Per exercise and per muscle"),
                    mark: raises > 0 ? Image(systemName: "arrow.up") : nil)
            }
            .buttonStyle(.plain)
        case .programs:
            NavigationLink {
                TrainingProgramsScreen(programs: programs, summaries: summaries, plan: plan, loaded: loaded,
                                       reload: { await load() },
                                       savePlan: { saved in savePlan(saved) })
            } label: {
                TrainingLineLabel(title: Text("Programs"),
                                  detail: summaries.count == 1 ? Text("1 program · Plan the week")
                                      : Text(String(localized: "\(summaries.count) programs · Plan the week")))
            }
            .buttonStyle(.plain)
        case .otherActivities:
            otherActivities
        }
    }

    // MARK: - Header

    /// The title and the Week | Month switch, then the week or month shown with its count and ‹ ›
    /// (fork chantier 7: the count moved up from the bar above the week strip).
    private var header: some View {
        TrainingCompactHeader(mode: $mode, showsLegend: $showsLegend,
                              isAwayFromToday: isAwayFromToday,
                              monthTitle: TrainingText.monthTitle(selectedDate),
                              onToday: { selectedDate = calendar.startOfDay(for: Date()) },
                              onPrevious: { shift(months: -1) },
                              onNext: { shift(months: 1) })
    }

    /// Whether the week (or month) shown is not the one holding today.
    private var isAwayFromToday: Bool {
        let now = Date()
        if mode == .month {
            return TrainingCalendar.monthStart(selectedDate, calendar: calendar)
                != TrainingCalendar.monthStart(now, calendar: calendar)
        }
        return TrainingCalendar.mondayOf(selectedDate, calendar: calendar)
            != TrainingCalendar.mondayOf(now, calendar: calendar)
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
                // Fork chantier 18: no arrows any more; a swipe moves to the next or previous week.
                .gesture(DragGesture(minimumDistance: 30).onEnded { drag in
                    guard abs(drag.translation.width) > abs(drag.translation.height),
                          abs(drag.translation.width) > 50 else { return }
                    shift(days: drag.translation.width < 0 ? 7 : -7)
                })
            if showsLegend { TrainingLegend() }
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
                    if showsLegend { TrainingLegend().padding(.horizontal, 6) }
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
                TrainingDaySection(day: day, programs: dayPrograms(day),
                                   others: summaries.filter { !openIds.contains($0.id) },
                                   isRunning: session.isActive,
                                   unitSystem: unitSystem,
                                   onStart: { id in
                                       guard let program = programs.first(where: { $0.id == id }) else { return }
                                       Task { await start(program) }
                                   },
                                   onStartCardio: { sport in cardioToStart = sport },
                                   onOpenLift: { lift in
                                       if let row = sessionsById[lift.sessionId] {
                                           viewing = SessionDetailTarget(id: row.id, session: row)
                                       }
                                   },
                                   additions: dayAdditions,
                                   onAddExercise: { id in addingTo = ProgramAddTarget(id: id) },
                                   onRemoveAddition: { programId, additionId in
                                       LiftDayAdditions.remove(id: additionId, day: todayKey, programId: programId)
                                       readDayAdditions()
                                   },
                                   leftOut: dayLeftOut,
                                   onLeaveOut: { programId, lineId, left in
                                       LiftDayAdditions.setLineLeftOut(lineId, left: left, day: todayKey,
                                                                       programId: programId)
                                       readDayAdditions()
                                   })
            }
        }
    }

    // MARK: - Other activities

    /// Fork chantier 18 (maquette 2): « Other session » opens the « Start » sheet (programs, the sports done
    /// most, any other sport, live heart rate, intervals), then the history in one line with the last day
    /// something was done; the Beta session stays when Live Sessions are on.
    private var otherActivities: some View {
        VStack(spacing: NoopMetrics.space3) {
            Button { showStart = true } label: {
                Text("Other session (cardio, another sport)")
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: NoopMetrics.controlHeight)
                    .background(StrandPalette.surfaceRaised,
                                in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if liveSessionsBeta {
                Button { showLiveSession = true } label: {
                    TrainingLineLabel(title: Text("Start session (Beta)"),
                                      detail: Text("Silent strap coaching against today's Charge."))
                }
                .buttonStyle(.plain)
            }
            NavigationLink {
                WorkoutsView()
            } label: {
                TrainingLineLabel(title: Text("History"),
                                  detail: Text(verbatim: TrainingText.latestDoneLine(
                                      TrainingDays.latestDone(lifts: lifts, activities: activities,
                                                              calendar: calendar))))
            }
            .buttonStyle(.plain)
        }
    }

    /// Keep the week plan as the planning sheet saved it, dated from today the first time.
    private func savePlan(_ saved: TrainingWeekPlan) {
        var next = saved
        if next.since == nil {
            next.since = TrainingCalendar.trainingDayKey(Date(), calendar: calendar)
        }
        next.storeWeekPlan()
        plan = next
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

    /// Starts a program through the start the « Start » sheet shares: Élan's short version when it was
    /// accepted for today, else the whole program (`beginTodayProgramSession`).
    private func start(_ program: LiftProgramRow) async {
        await session.beginTodayProgramSession(programId: program.id, programName: program.name, repo: repo)
    }

    /// The programs as the day card shows them: today, Élan's accepted program as its short version
    /// (`ElanShortSession.elanProgramSummary`), the others without the lines left out for today
    /// (`TrainingDays.dayProgramSummary`, the rule the start applies); another day, as they are.
    private func dayPrograms(_ day: TrainingDay) -> [TrainingProgramSummary] {
        guard day.isToday else { return summaries }
        return summaries.map { summary in
            if let short = elanShort, summary.id == short.programId {
                return ElanShortSession.elanProgramSummary(short)
            }
            return TrainingDays.dayProgramSummary(summary, leftOut: dayLeftOut[summary.id] ?? [])
        }
    }

    // MARK: - Load

    /// The store read the « Start » sheet shares (`TrainingSnapshot.loadTrainingSnapshot`), then the
    /// Progression data and the loads to raise, which only this screen shows.
    private func load() async {
        guard let read = await TrainingSnapshot.loadTrainingSnapshot(repo: repo, historyDays: Self.historyDays,
                                                                     effortScale: effortScale) else { return }
        lifts = read.lifts
        activities = read.activities
        sessionsById = read.sessionsById
        programs = read.programs
        plan = read.plan

        let step = unitSystem == .imperial ? LiftProgression.imperialStepKg : LiftProgression.metricStepKg
        let progressRead = await LiftProgressData.load(repo: repo, stepKg: step)
        if let progressRead { progress = progressRead }
        // The loads to raise, judged as the session sheet will judge them when the program starts.
        let judged = progressRead ?? progress
        summaries = read.summaries.map { summary in
            var raised = summary
            raised.raises = TrainingDays.programRaises(items: read.itemsByProgram[summary.id] ?? [],
                                                       lastSets: { judged.exercise(named: $0)?.points.last?.sets },
                                                       stepKg: step)
            return raised
        }
        let today = TrainingCalendar.trainingDayKey(Date(), calendar: calendar)
        if let id = ElanShortSessionChoice.acceptedProgramId(day: today) {
            elanShort = await ElanShortSession.loadElanShortSession(repo: repo, programId: id)
        } else {
            elanShort = nil
        }
        readDayAdditions()
        loaded = true
    }
}

/// Starts the live workout of planned cardio from the day card (fork chantier 9): the sport is already
/// chosen, so the sport picker is skipped. A workout already running is opened instead. Its own view so only
/// it observes `AppModel`. The « Start » sheet uses it too, and closes
/// itself once the live workout is closed (`onClosed`).
struct TrainingCardioLauncher: View {
    @EnvironmentObject var model: AppModel
    @Binding var request: String?
    var onClosed: () -> Void
    @State private var showLiveWorkout = false
    /// The planned sport, started by the live workout at the « Go » of its countdown (fork chantier 12).
    @State private var pendingSport: String?

    // Explicit, since the private state makes the memberwise one private to this file.
    init(request: Binding<String?>, onClosed: @escaping () -> Void = {}) {
        _request = request
        self.onClosed = onClosed
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onChange(of: request) { sport in
                guard let sport else { return }
                request = nil
                pendingSport = model.activeWorkout == nil ? sport : nil
                showLiveWorkout = true
            }
            .sheet(isPresented: $showLiveWorkout, onDismiss: onClosed) {
                LiveWorkoutView(onClose: { showLiveWorkout = false }, startingSport: pendingSport)
                    .environmentObject(model.live)
            }
    }
}

/// The session whose detail is being read back. A wrapper rather than a retroactive `Identifiable`
/// on `LiftSessionRow`, keeping the store's row types free of app-layer conformances.
/// Programs (fork chantier 18): the list with New, Import and Plan the week, behind the Training screen's
/// « Programs » line. Its sheets are its own; saving reloads the Training screen.
private struct TrainingProgramsScreen: View {
    let programs: [LiftProgramRow]
    let summaries: [TrainingProgramSummary]
    let plan: TrainingWeekPlan
    let loaded: Bool
    let reload: () async -> Void
    let savePlan: (TrainingWeekPlan) -> Void

    @State private var editing: ProgramEditTarget?
    @State private var importing = false
    @State private var planning = false

    var body: some View {
        ScreenScaffold(title: "Programs") {
            TrainingProgramsCard(programs: summaries, plan: plan,
                                 weekdays: TrainingText.shortWeekdays(.current), loaded: loaded,
                                 onEdit: { id in
                                     editing = ProgramEditTarget(id: id, program: programs.first { $0.id == id })
                                 },
                                 onNew: { editing = ProgramEditTarget(id: "new", program: nil) },
                                 onImport: { importing = true },
                                 onPlan: { planning = true })
        }
        .sheet(item: $editing) { target in
            LiftProgramEditorSheet(program: target.program) { await reload() }
        }
        .sheet(isPresented: $importing) {
            LiftProgramImportSheet { await reload() }
        }
        .sheet(isPresented: $planning) {
            TrainingPlanSheet(programs: summaries, plan: plan) { saved in savePlan(saved) }
        }
    }
}

/// The program « + Exercise » adds to, for today (fork chantier 18).
private struct ProgramAddTarget: Identifiable {
    let id: String
}

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
