import SwiftUI
import StrandDesign
import WhoopStore

// Personal fork (mockup « Démarrer », validated 4 Nov.): Today's « + » opens this sheet directly. It used to
// open a menu whose « Start workout » led to the workouts HISTORY, where nothing said what to tap to begin.
// From the top: what the week plan sets for today (the Training screen's day card, read the same way), the
// programs and « Freehand session », the five live sports done most, then a past session, the history, and
// the former quick actions (live heart rate, breathing, journal) as small buttons.

struct StartSheet: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var session: LiftSessionController
    @EnvironmentObject private var intelligence: IntelligenceEngine
    @Environment(\.dismiss) private var dismiss
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue

    /// The Training screen's read (`TrainingSnapshot.loadTrainingSnapshot`), over the sport grid's window.
    @State private var snapshot = TrainingSnapshot()
    /// The program, the freehand session or the sport tapped; the large button starts it.
    @State private var choice: StartChoice?
    /// Cardio whose Start was tapped: its stored sport name, until the live workout opens.
    @State private var cardioToStart: String?
    @State private var choosingSport = false
    @State private var addingPastSession = false
    /// Élan's short session accepted for today (personal fork, chantier 10 PR C): the planned row of its
    /// program shows it and starts it; nil when none was accepted.
    @State private var elanShort: ElanShortSessionPlan?
    @AppStorage(ElanShortSessionChoice.revisionKey) private var elanRevision = 0

    private enum StartChoice: Equatable {
        case program(id: String, name: String)
        case freehand
        case sport(String)
    }

    private var calendar: Calendar { .current }

    var body: some View {
        let now = Date()
        let today = TrainingDays.buildTrainingDays([now], plan: snapshot.plan, lifts: snapshot.lifts,
                                                   activities: snapshot.activities, now: now,
                                                   calendar: calendar).first
        let planned = StartSheetLogic.startPlannedRows(day: today, programs: snapshot.summaries)
        let week = TrainingDays.buildTrainingDays(
            TrainingCalendar.weekDates(from: TrainingCalendar.mondayOf(now, calendar: calendar), calendar: calendar),
            plan: snapshot.plan, lifts: snapshot.lifts, activities: snapshot.activities, now: now,
            calendar: calendar)
        let sports = StartSheetLogic.startSportGrid(activities: snapshot.activities,
                                                    recent: RecentSportsPrefs.recent(), now: now)
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Start")
                        .font(StrandFont.screenTitle)
                        .foregroundStyle(StrandPalette.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    if !planned.isEmpty {
                        sectionLabel("Planned today")
                        plannedCard(planned)
                    }
                    sectionLabel("Lifting")
                    programPills
                    sectionLabel("Live cardio · strap heart rate")
                    sportGrid(sports)
                    if let choice {
                        startButton(choice)
                    }
                    linksCard(sessionsThisWeek: StartSheetLogic.sessionsThisWeek(week))
                    smallButtons
                }
                .padding(.horizontal, NoopMetrics.space4)
                .padding(.bottom, NoopMetrics.space8)
            }
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(StrandPalette.accent)
                }
            }
        }
        .background(TrainingCardioLauncher(request: $cardioToStart, onClosed: { dismiss() }))
        .workoutSelectionCover(isPresented: $choosingSport) {
            StartWorkoutSheet { name in
                cardioToStart = name
            }
        }
        .sheet(isPresented: $addingPastSession) {
            ManualWorkoutSheet(editing: nil) { row, _ in
                Task {
                    await repo.saveManualWorkout(row)
                    // Rescore the new workout from the strap's heart rate now, as the history screen does
                    // (#598), so its figures are there when it is opened.
                    await intelligence.analyzeRecent()
                    await load()
                }
            }
        }
        .task(id: "\(repo.refreshSeq)-\(session.savedSessions)-\(elanRevision)") { await load() }
    }

    // MARK: - Planned today

    private func plannedCard(_ planned: [StartSheetPlanned]) -> some View {
        NoopCard(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(planned.enumerated()), id: \.offset) { index, row in
                    if index > 0 {
                        Rectangle()
                            .fill(StrandPalette.hairline)
                            .frame(height: NoopMetrics.hairlineWidth)
                    }
                    switch row {
                    case .program(let program): plannedProgramRow(program)
                    case .cardio(let sport, let minutes): plannedCardioRow(sport: sport, minutes: minutes)
                    }
                }
            }
        }
    }

    /// A planned program: its name and line; Élan's short version when it was accepted for today (the
    /// mockup's « Full body B · version courte · 2 supersets · ≈ 20 min · ajoutée par Élan », with « Retirer »).
    private func plannedProgramRow(_ program: TrainingProgramSummary) -> some View {
        let short = elanShort?.programId == program.id ? elanShort : nil
        return HStack(spacing: 12) {
            rowIcon("dumbbell.fill", tint: StrandPalette.effortColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: short?.title ?? program.name)
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                if let short {
                    HStack(spacing: 4) {
                        let line = ElanShortSession.elanPlannedLine(short)
                        if !line.isEmpty {
                            Text(verbatim: line + " ·")
                                .foregroundStyle(StrandPalette.textSecondary)
                        }
                        Text("added by Élan")
                            .foregroundStyle(StrandPalette.elanSand)
                    }
                    .font(StrandFont.footnote)
                    .lineLimit(2)
                } else {
                    let line = TrainingText.plannedLine(program)
                    if !line.isEmpty {
                        Text(verbatim: line)
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .lineLimit(2)
                    }
                }
            }
            Spacer(minLength: 8)
            if short != nil, !session.isActive {
                Button { withdrawElanShort() } label: {
                    Text("Withdraw")
                        .font(StrandFont.subhead.weight(.semibold))
                        .foregroundStyle(StrandPalette.textPrimary)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 40)
                        .background(StrandPalette.surfaceOverlay, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Button { startLift(.plannedProgram(id: program.id, name: program.name)) } label: {
                Group {
                    if session.isActive {
                        Text("Running")
                    } else {
                        Text("Start")
                    }
                }
                .font(StrandFont.subhead.weight(.semibold))
                .foregroundStyle(StrandPalette.surfaceBase)
                .padding(.horizontal, 16)
                .frame(minHeight: 40)
                .background(StrandPalette.textPrimary, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private func plannedCardioRow(sport: String, minutes: Int) -> some View {
        HStack(spacing: 12) {
            rowIcon(sportSymbol(sport), tint: StrandPalette.metricRose)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: WorkoutCatalog.shownSportName(sport))
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                if minutes > 0 {
                    Text("Target: \(minutes) min")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
            }
            Spacer(minLength: 8)
            Button { cardioToStart = sport } label: {
                Text("Start")
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(StrandPalette.onDarkPrimary)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 40)
                    .background(StrandPalette.metricRose, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private func rowIcon(_ symbol: String, tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 40, height: 40)
            .background(tint.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityHidden(true)
    }

    // MARK: - Lifting and cardio

    /// The programs with at least one line, then « Freehand session »: a tap chooses, the large button starts.
    private var programPills: some View {
        CoachChipFlow(spacing: 8) {
            ForEach(StartSheetLogic.startablePrograms(snapshot.summaries)) { program in
                let picked = choice == .program(id: program.id, name: program.name)
                pill(picked: picked) {
                    Text(verbatim: program.name)
                } action: {
                    choice = picked ? nil : .program(id: program.id, name: program.name)
                }
            }
            pill(picked: choice == .freehand) {
                Text("Freehand session")
            } action: {
                choice = choice == .freehand ? nil : .freehand
            }
        }
    }

    private func pill<Label: View>(picked: Bool, @ViewBuilder label: () -> Label,
                                   action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label()
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textPrimary)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .frame(minHeight: 40)
                .background(StrandPalette.surfaceRaised, in: Capsule())
                .overlay(Capsule().strokeBorder(picked ? StrandPalette.effortColor : StrandPalette.hairline,
                                                lineWidth: picked ? 2 : NoopMetrics.hairlineWidth))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(picked ? .isSelected : [])
    }

    /// Three columns: the sports, then « Other sport… », which opens the whole list and starts at once.
    private func sportGrid(_ sports: [String]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(sports, id: \.self) { sport in
                let picked = choice == .sport(sport)
                sportTile(symbol: sportSymbol(sport), picked: picked) {
                    Text(verbatim: WorkoutCatalog.shownSportName(sport))
                } action: {
                    choice = picked ? nil : .sport(sport)
                }
            }
            sportTile(symbol: "ellipsis", picked: false) {
                Text("Other sport…")
            } action: {
                choosingSport = true
            }
        }
    }

    private func sportTile<Label: View>(symbol: String, picked: Bool, @ViewBuilder label: () -> Label,
                                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(picked ? StrandPalette.onDarkPrimary : StrandPalette.metricRose)
                    .frame(width: 32, height: 32)
                    .background(picked ? StrandPalette.metricRose : StrandPalette.surfaceOverlay, in: Circle())
                    .accessibilityHidden(true)
                label()
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: 84)
            .background(StrandPalette.surfaceRaised,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(picked ? StrandPalette.metricRose : StrandPalette.hairline,
                              lineWidth: picked ? 2 : NoopMetrics.hairlineWidth))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(picked ? .isSelected : [])
    }

    /// The large button under the grid: white for a Lift Log session, pink for a live sport.
    @ViewBuilder private func startButton(_ choice: StartChoice) -> some View {
        switch choice {
        case .program(let id, let name):
            Button { startLift(.program(id: id, name: name)) } label: {
                Text("Start \(name)").frame(maxWidth: .infinity)
            }
            .buttonStyle(NoopButtonStyle(.primary, fullWidth: true))
        case .freehand:
            Button { startLift(.freehand) } label: {
                Text("Start a freehand session").frame(maxWidth: .infinity)
            }
            .buttonStyle(NoopButtonStyle(.primary, fullWidth: true))
        case .sport(let sport):
            Button { cardioToStart = sport } label: {
                Text("Start · \(WorkoutCatalog.shownSportName(sport))")
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.onDarkPrimary)
                    .frame(maxWidth: .infinity, minHeight: NoopButtonMetrics.height)
                    .background(StrandPalette.metricRose,
                                in: RoundedRectangle(cornerRadius: NoopButtonMetrics.cornerRadius, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: NoopButtonMetrics.cornerRadius, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Past session, history, quick actions

    private func linksCard(sessionsThisWeek: Int) -> some View {
        VStack(spacing: 0) {
            Button { addingPastSession = true } label: {
                linkRow { Text("Add a past session") } detail: { EmptyView() }
            }
            .buttonStyle(.plain)
            Rectangle()
                .fill(StrandPalette.hairline)
                .frame(height: NoopMetrics.hairlineWidth)
                .padding(.leading, 16)
            NavigationLink {
                WorkoutsView()
            } label: {
                linkRow { Text("Session history") } detail: {
                    if sessionsThisWeek > 0 {
                        Text("\(sessionsThisWeek) this week")
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .background(StrandPalette.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: NoopVisualStyle.compactRadius, style: .continuous))
        .padding(.top, 6)
    }

    private func linkRow<Title: View, Detail: View>(@ViewBuilder _ title: () -> Title,
                                                    @ViewBuilder detail: () -> Detail) -> some View {
        HStack(spacing: 8) {
            title()
                .font(StrandFont.body)
                .foregroundStyle(StrandPalette.textPrimary)
            Spacer(minLength: 8)
            detail()
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(StrandPalette.textTertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 48)
        .contentShape(Rectangle())
    }

    /// The former quick actions, each opening its screen in this sheet.
    private var smallButtons: some View {
        HStack(spacing: 8) {
            smallButton { LiveView() } label: { Text("Live HR") }
            smallButton { BreathingView() } label: { Text("Breathe") }
            smallButton { InsightsView() } label: { Text("Journal") }
        }
    }

    private func smallButton<Destination: View, Label: View>(@ViewBuilder _ destination: @escaping () -> Destination,
                                                             @ViewBuilder label: () -> Label) -> some View {
        NavigationLink {
            destination()
        } label: {
            label()
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(StrandPalette.surfaceRaised, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func sectionLabel(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(StrandFont.footnote.weight(.medium))
            .foregroundStyle(StrandPalette.textSecondary)
            .padding(.top, 6)
            .padding(.horizontal, 4)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Start and load

    private enum LiftStart {
        /// A program chosen from the pills: the whole of it.
        case program(id: String, name: String)
        /// Today's planned program: Élan's short version when it was accepted for today, else the whole of it.
        case plannedProgram(id: String, name: String)
        case freehand
    }

    /// Closes the sheet, then starts the Lift Log session: its sheet is presented by the app's root, which
    /// cannot present it while this one is still on screen.
    private func startLift(_ start: LiftStart) {
        let controller = self.session
        let store = self.repo
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            switch start {
            case .program(let id, let name):
                await controller.beginProgramSession(programId: id, programName: name, repo: store)
            case .plannedProgram(let id, let name):
                await controller.beginTodayProgramSession(programId: id, programName: name, repo: store)
            case .freehand:
                controller.beginFreehandSession()
            }
        }
    }

    /// « Retirer »: Élan's short session leaves today, and is not proposed again that day. The plan reloads
    /// through the revision the choice bumps.
    private func withdrawElanShort() {
        ElanShortSessionChoice.withdraw(day: TrainingCalendar.trainingDayKey(Date(), calendar: calendar))
    }

    private func load() async {
        let scale = UnitPrefs.resolveEffortScale(effortScaleRaw)
        if let read = await TrainingSnapshot.loadTrainingSnapshot(repo: repo,
                                                                 historyDays: StartSheetLogic.sportWindowDays,
                                                                 effortScale: scale) {
            snapshot = read
        }
        let today = TrainingCalendar.trainingDayKey(Date(), calendar: calendar)
        if let id = ElanShortSessionChoice.acceptedProgramId(day: today) {
            elanShort = await ElanShortSession.loadElanShortSession(repo: repo, programId: id)
        } else {
            elanShort = nil
        }
    }
}
