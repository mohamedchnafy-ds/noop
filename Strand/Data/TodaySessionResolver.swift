import Foundation
import WhoopStore

// Personal fork, chantier 6: today's session resolved once, for the Synthèse on Today and for the
// "Today's session" widget. Both read it through `TodaySessionResolver.resolveTodaySession`, so the Home
// Screen can never name another session than the one Today names.

/// Today's session as the Synthèse resolves it, with what the same read already holds that the widget also
/// draws: the program's lines (its blocks) and the sessions and workouts of the lookback (its week).
struct TodaySessionResolution {
    /// Nil when there is nothing to name: no program, a past day with nothing done, or no plan and no rotation.
    var session: TodaySynthesisLogic.Session?
    /// The program of that session (running, done or planned), when it has one.
    var programId: String?
    /// That program's lines, in any order; empty without a program.
    var programItems: [LiftProgramItemRow]
    /// At least one program is saved (the Synthèse's empty-state hint reads it).
    var hasPrograms: Bool
    /// The lookback's Lift Log sessions with at least one working set, with that count.
    var performed: [(row: LiftSessionRow, workingSets: Int)]
    /// The lookback's workout rows split as the Training calendar splits them: each session's own row (by
    /// the session's start), then every other activity.
    var liftWorkouts: [Int: WorkoutRow]
    var otherWorkouts: [WorkoutRow]
    /// The week plan, its deleted or empty programs left out (`TrainingWeekPlan.keepingPrograms`).
    var plan: TrainingWeekPlan
    /// Every program with at least one line, by id: its name (the session widget names each planned item).
    var programNames: [String: String] = [:]
}

enum TodaySessionResolver {
    /// Today's session from the Lift Log: the one running that day; else (today only) the first item the
    /// week plan sets for today that is still to do (personal fork, Training; a program or cardio, the
    /// others listed with it); else the session done that day; else rest, and without a plan the next
    /// program of the rotation; with its blocks and its usual length. Nil when the store is not open.
    @MainActor
    static func resolveTodaySession(repo: Repository, calendarFrom: Int, calendarTo: Int, isToday: Bool,
                                    now: Date = Date()) async -> TodaySessionResolution? {
        guard let store = await repo.storeHandle() else { return nil }
        let owner = repo.deviceId
        let programs = (try? await store.liftPrograms(deviceId: owner)) ?? []
        var itemsByProgram: [String: [LiftProgramItemRow]] = [:]
        for program in programs {
            itemsByProgram[program.id] = (try? await store.liftProgramItems(programId: program.id)) ?? []
        }
        let withItems = programs.filter { !(itemsByProgram[$0.id] ?? []).isEmpty }
        let lookbackFrom = calendarTo - CoachLiftContext.lookbackDays * 86_400
        let rows = (try? await store.liftSessions(deviceId: owner, fromTs: lookbackFrom, toTs: calendarTo)) ?? []
        var performed: [(row: LiftSessionRow, workingSets: Int)] = []
        for row in rows {
            let sets = (try? await store.liftSets(sessionId: row.id)) ?? []
            let working = sets.filter(LiftRotation.isWorking).count
            if working > 0 { performed.append((row, working)) }
        }
        func shape(_ programId: String?) -> (supersets: Int, singles: Int) {
            LiftRotation.shape(labels: (programId.flatMap { itemsByProgram[$0] } ?? []).map(\.supersetGroup))
        }
        // A session's length is its own workout row's, pauses left out — the rule the Training calendar
        // and the Workouts list read (`TrainingDays.liftSessionSeconds`).
        let lookbackDays = max(1, (Int(now.timeIntervalSince1970) - lookbackFrom) / 86_400 + 1)
        let recentWorkouts = await repo.workoutRows(days: lookbackDays)
        let split = TrainingDays.splitLiftWorkouts(recentWorkouts, liftStarts: performed.map { $0.row.startTs })
        func length(_ row: LiftSessionRow, end: Int) -> Int {
            TrainingDays.liftSessionSeconds(startTs: row.startTs, endTs: end, workout: split.lift[row.startTs])
        }
        let plan = TrainingWeekPlan.loadWeekPlan(now: now).keepingPrograms(Set(withItems.map(\.id)))
        // Élan's short session accepted for today (personal fork, chantier 10 PR C): the plan above already
        // holds its program on today; its shape and length are the short session's (`ElanShortSession`).
        var elanShort: ElanShortSessionPlan?
        if isToday, let id = ElanShortSessionChoice.acceptedProgramId(day: TrainingCalendar.trainingDayKey(now, calendar: .current)),
           let program = withItems.first(where: { $0.id == id }) {
            var lastByExercise: [String: [LiftSetRow]] = [:]
            for line in ElanShortSession.elanShortLines(itemsByProgram[id] ?? []).flatMap({ $0 })
            where lastByExercise[line.exercise] == nil {
                lastByExercise[line.exercise] = (try? await store.lastLiftSets(deviceId: owner, exercise: line.exercise)) ?? []
            }
            elanShort = ElanShortSession.elanShortPlan(programId: id, name: program.name, items: itemsByProgram[id] ?? [],
                                                       lastSets: { lastByExercise[$0] ?? [] })
        }
        var resolution = TodaySessionResolution(
            session: nil, programId: nil, programItems: [], hasPrograms: !programs.isEmpty,
            performed: performed, liftWorkouts: split.lift, otherWorkouts: split.others, plan: plan,
            programNames: Dictionary(withItems.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first }))
        func named(_ session: TodaySynthesisLogic.Session, programId: String?) -> TodaySessionResolution {
            resolution.session = session
            resolution.programId = programId
            resolution.programItems = programId.flatMap { itemsByProgram[$0] } ?? []
            return resolution
        }
        /// A program still to do: its shape and its usual length; Élan's short version when it was
        /// accepted for today, with its own two blocks as the lines the widget draws.
        func nextSession(_ next: LiftProgramRow) -> TodaySessionResolution {
            if let elanShort, elanShort.programId == next.id {
                var result = named(.init(name: next.name, state: .next, supersets: elanShort.supersets,
                                         singles: elanShort.singles, typicalMinutes: elanShort.estimatedMinutes,
                                         elanShort: true),
                                   programId: next.id)
                result.programItems = elanShort.lines.map(\.item)
                return result
            }
            let s = shape(next.id)
            let finished = performed.map { $0.row }.filter { $0.programId == next.id }
                .compactMap { row in row.endTs.map { (startTs: row.startTs, endTs: row.startTs + length(row, end: $0)) } }
            return named(.init(name: next.name, state: .next, supersets: s.supersets, singles: s.singles,
                               typicalMinutes: LiftRotation.typicalMinutes(finished)),
                         programId: next.id)
        }

        let ofDay = rows.filter { $0.startTs >= calendarFrom && $0.startTs < calendarTo }
        if let running = ofDay.first(where: { $0.endTs == nil }), isToday {
            let s = shape(running.programId)
            return named(.init(name: running.programName ?? String(localized: "Session"), state: .running,
                               supersets: s.supersets, singles: s.singles, typicalMinutes: nil),
                         programId: running.programId)
        }
        let doneToday = ofDay.filter { row in performed.contains { $0.row.id == row.id } }
        func doneSession(_ done: LiftSessionRow) -> TodaySessionResolution {
            let s = shape(done.programId)
            let minutes = done.endTs.map { length(done, end: $0) / 60 }
            return named(.init(name: done.programName ?? String(localized: "Session"),
                               state: .done(minutes: minutes), supersets: s.supersets, singles: s.singles,
                               typicalMinutes: nil),
                         programId: done.programId)
        }
        // The week plan decides when it has a say about today (`TrainingWeekPlan.planDecision`, the
        // resolver the Training calendar reads); a deleted or empty program frees its place. Its items are
        // matched against what was done today by the calendar's own rule (`TrainingDays.matchPlanned`):
        // the first one still to do is named, the others follow it (fork chantier 8, lot 4).
        let planned = isToday
            ? plan.planDecision(for: Date(timeIntervalSince1970: TimeInterval(calendarFrom)), calendar: .current)
            : nil
        if case .planned(let items) = planned {
            let lifts = doneToday.compactMap { row -> TrainingLiftDone? in
                guard let end = row.endTs else { return nil }
                return TrainingLiftDone(sessionId: row.id, programId: row.programId, name: row.programName ?? "",
                                        startTs: row.startTs, endTs: end, workingSets: 0, effort: nil)
            }
            let cardioToday = split.others.filter { $0.startTs >= calendarFrom && $0.startTs < calendarTo }
            let activities = cardioToday.map { row in
                TrainingActivityDone(sport: row.sport, source: row.source, startTs: row.startTs, endTs: row.endTs,
                                     kcal: nil)
            }
            let open = TrainingDays.matchPlanned(items, lifts: lifts, activities: activities)
                .filter { !$0.isDone }.map(\.item)
            if let first = open.first {
                let others = open.dropFirst().compactMap { item -> String? in
                    switch item {
                    case .program(let id): return withItems.first(where: { $0.id == id })?.name
                    case .cardio(let sport, let minutes): return cardioName(sport, minutes: minutes)
                    }
                }
                switch first {
                case .cardio(let sport, let minutes):
                    var result = named(.init(name: WorkoutCatalog.shownSportName(sport), state: .next, supersets: 0,
                                             singles: 0, typicalMinutes: nil, cardioMinutes: minutes),
                                       programId: nil)
                    result.session?.alsoPlanned = others
                    return result
                case .program(let id):
                    guard let next = withItems.first(where: { $0.id == id }) else { return resolution }
                    var result = nextSession(next)
                    result.session?.alsoPlanned = others
                    return result
                }
            }
            if let done = doneToday.first { return doneSession(done) }
            // Only cardio was planned, and it is done: the activity that did it.
            for case .cardio(let sport, let minutes) in items {
                guard let run = cardioToday.first(where: { TrainingDays.isSameSport($0.sport, sport) }) else { continue }
                return named(.init(name: WorkoutSource.displaySport(run.sport),
                                   state: .done(minutes: max(0, run.endTs - run.startTs) / 60), supersets: 0,
                                   singles: 0, typicalMinutes: nil, cardioMinutes: minutes),
                             programId: nil)
            }
            return resolution
        }
        if let done = doneToday.first { return doneSession(done) }
        guard isToday else { return resolution }
        let nextId: String?
        switch planned {
        case .rest:
            return named(.init(name: String(localized: "Rest"), state: .rest, supersets: 0, singles: 0,
                               typicalMinutes: nil),
                         programId: nil)
        case .planned, nil:
            nextId = LiftRotation.next(
                programIds: withItems.map(\.id),
                lastDone: LiftRotation.lastDone(performed.map { (programId: $0.row.programId, startTs: $0.row.startTs) }))
        }
        guard let nextId, let next = withItems.first(where: { $0.id == nextId }) else { return resolution }
        return nextSession(next)
    }

    /// Planned cardio as one line: « Running · 30 min », the sport shown in the app's language.
    static func cardioName(_ sport: String, minutes: Int) -> String {
        WorkoutCatalog.shownSportName(sport) + " · " + String(localized: "\(minutes) min")
    }
}
