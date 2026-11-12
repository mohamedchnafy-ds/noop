import Foundation
import WhoopStore

// Personal fork: what the Training screen reads from the store, read once by ONE function so the Training
// screen and the « Start » sheet (opened by Today's « + ») can never name different planned sessions for
// the same day. Both build their days from it with `TrainingDays.buildTrainingDays`, which asks the week
// plan through `TrainingWeekPlan.planDecision`.

/// The Lift Log programs, the sessions done and the other activities over a history, and the week plan.
struct TrainingSnapshot {
    /// Saved programs, most-recently-touched first.
    var programs: [LiftProgramRow] = []
    /// Each program's lines, by program id.
    var itemsByProgram: [String: [LiftProgramItemRow]] = [:]
    /// The programs as the Training screen shows them, without the loads to raise (the caller adds them).
    var summaries: [TrainingProgramSummary] = []
    /// Lift Log sessions done: finished, with at least one working set.
    var lifts: [TrainingLiftDone] = []
    /// Every other workout (the sessions' own rows left out).
    var activities: [TrainingActivityDone] = []
    /// The stored rows of the sessions done, by id.
    var sessionsById: [String: LiftSessionRow] = [:]
    /// The week plan, its deleted programs left out.
    var plan = TrainingWeekPlan()

    /// Reads the store over the last `historyDays` days. Nil when the store is not open.
    @MainActor
    static func loadTrainingSnapshot(repo: Repository, historyDays: Int, effortScale: EffortScale,
                                     now: Date = Date()) async -> TrainingSnapshot? {
        guard let store = await repo.storeHandle() else { return nil }
        let owner = repo.deviceId
        let rows = (try? await store.liftPrograms(deviceId: owner)) ?? []
        var itemsByProgram: [String: [LiftProgramItemRow]] = [:]
        for program in rows {
            itemsByProgram[program.id] = (try? await store.liftProgramItems(programId: program.id)) ?? []
        }

        // Sessions done: finished, with at least one working set (the rotation's rule).
        let nowTs = Int(now.timeIntervalSince1970)
        let sessions = (try? await store.liftSessions(deviceId: owner,
                                                      fromTs: nowTs - historyDays * 86_400,
                                                      toTs: nowTs + 86_400)) ?? []
        var done: [(row: LiftSessionRow, working: Int)] = []
        for row in sessions where row.endTs != nil {
            let sets = (try? await store.liftSets(sessionId: row.id)) ?? []
            let working = sets.filter(LiftRotation.isWorking).count
            if working > 0 { done.append((row, working)) }
        }

        // Every workout but the sessions' own rows, so a Lift Log session is never counted twice.
        let workouts = await repo.workoutRows(days: historyDays + 1)
        let split = TrainingDays.splitLiftWorkouts(workouts, liftStarts: done.map { $0.row.startTs })
        // A session's length is its own workout row's, pauses left out (`TrainingDays.liftSessionSeconds`).
        func length(_ row: LiftSessionRow, end: Int) -> Int {
            TrainingDays.liftSessionSeconds(startTs: row.startTs, endTs: end, workout: split.lift[row.startTs])
        }
        var snapshot = TrainingSnapshot()
        snapshot.lifts = done.map { entry in
            let end = entry.row.endTs ?? entry.row.startTs
            return TrainingLiftDone(sessionId: entry.row.id, programId: entry.row.programId,
                                    name: entry.row.programName ?? String(localized: "Session"),
                                    startTs: entry.row.startTs, endTs: end,
                                    workingSets: entry.working,
                                    effort: split.lift[entry.row.startTs]?.strain.map {
                                        UnitFormatter.effortDisplay($0, scale: effortScale)
                                    },
                                    activeSeconds: length(entry.row, end: end))
        }
        snapshot.activities = split.others.map { row in
            TrainingActivityDone(sport: row.sport,
                                 source: trainingSourceLabel(row.source),
                                 startTs: row.startTs, endTs: row.endTs,
                                 kcal: row.energyKcal.map { Int($0.rounded()) })
        }
        snapshot.sessionsById = Dictionary(done.map { ($0.row.id, $0.row) }, uniquingKeysWith: { first, _ in first })
        snapshot.summaries = rows.map { program in
            let finished = done.filter { $0.row.programId == program.id }
                .compactMap { entry in
                    entry.row.endTs.map { (startTs: entry.row.startTs,
                                           endTs: entry.row.startTs + length(entry.row, end: $0)) }
                }
            return TrainingDays.programSummary(id: program.id, name: program.name,
                                               items: itemsByProgram[program.id] ?? [], finished: finished)
        }
        snapshot.programs = rows
        snapshot.itemsByProgram = itemsByProgram
        // A deleted program frees its day.
        snapshot.plan = TrainingWeekPlan.loadWeekPlan().keepingPrograms(Set(rows.map(\.id)))
        return snapshot
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

extension LiftSessionController {
    /// Starts a Lift Log program: its lines flattened into the plan the session runs. The plan is SNAPSHOT
    /// at start, so editing or deleting the program mid-session cannot change what is being tapped through.
    /// A session already running is brought up instead (two live sessions would both claim the strap
    /// gesture and both write the in-flight snapshot); an empty program starts nothing. The one start the
    /// Training screen and the « Start » sheet share.
    func beginProgramSession(programId: String, programName: String, repo: Repository) async {
        guard !isActive else {
            isPresented = true
            return
        }
        guard let store = await repo.storeHandle() else { return }
        let programItems = (try? await store.liftProgramItems(programId: programId)) ?? []
        guard !programItems.isEmpty else { return }
        // Fork chantier 18: the lines left out for today from the Training day card are skipped (the program
        // keeps them), and forgotten below with the day's additions.
        let today = TrainingCalendar.trainingDayKey(Date(), calendar: .current)
        let items = LiftDayAdditions.keptProgramLines(
            programItems, removed: LiftDayAdditions.removedLineIds(day: today, programId: programId))
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
        let added = await dayAdditionItems(programId: programId, repo: repo, store: store)
        // Read again after the awaits: a session may have been started meanwhile.
        guard !isActive else {
            isPresented = true
            return
        }
        LiftDayAdditions.takeAdditions(day: TrainingCalendar.trainingDayKey(Date(), calendar: .current),
                                       programId: programId)
        start(plan: plan + added, programId: programId, programName: programName)
    }

    /// The exercises added to this program for today from the Training screen (fork chantier 18,
    /// `LiftDayAdditions`), as lines added during the session, each with last time's working set count.
    func dayAdditionItems(programId: String, repo: Repository, store: WhoopStore) async -> [LiftPlanItem] {
        let today = TrainingCalendar.trainingDayKey(Date(), calendar: .current)
        var items: [LiftPlanItem] = []
        for addition in LiftDayAdditions.additions(day: today, programId: programId) {
            let last = (try? await store.lastLiftSets(deviceId: repo.deviceId, exercise: addition.exercise)) ?? []
            items.append(LiftDayAdditions.planItem(addition, lastSets: last))
        }
        return items
    }

    /// Starts a session with no program (« Freehand session »): exercises are added as they come, and the
    /// finish writes no program back.
    func beginFreehandSession() {
        guard !isActive else {
            isPresented = true
            return
        }
        start(plan: [], programId: nil, programName: nil)
    }
}
