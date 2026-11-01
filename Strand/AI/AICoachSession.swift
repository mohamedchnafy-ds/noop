import Foundation
import WhoopStore

// MARK: - The session card's two actions (personal fork, step 6b)
//
// "Add to Lift Log" stores the proposal as a program, the way the spreadsheet import does, and records
// the program on the card so it is never added twice. "Start" hands the Lift Log session the same plan
// a program start builds (`LiftLogView.start`): from the stored program once added, from the card
// otherwise. Neither runs without a tap.

extension AICoachEngine {

    /// The session card of a message on screen, nil when it has none.
    func sessionProposal(messageId: UUID) -> CoachSessionProposal? {
        messages.first { $0.id == messageId }.flatMap { CoachReplyMeta.split($0.text).meta?.session }
    }

    /// Store the card of `messageId` as a Lift Log program. Returns the program id (the existing one
    /// when it was already added), nil when nothing could be stored.
    @discardableResult
    func addSessionToLiftLog(messageId: UUID) async -> String? {
        guard let message = messages.first(where: { $0.id == messageId }) else { return nil }
        let (body, meta) = CoachReplyMeta.split(message.text)
        guard var meta, var proposal = meta.session else { return nil }
        if let existing = proposal.programId { return existing }
        guard let store = await repo.storeHandle() else { return nil }

        let known = ((try? await store.liftExercises(deviceId: repo.deviceId)) ?? []).map(\.name)
        let now = Int(Date().timeIntervalSince1970)
        let programId = UUID().uuidString
        let saved = (try? await store.upsertLiftPrograms([LiftProgramRow(
            id: programId, deviceId: repo.deviceId, name: proposal.name, note: nil,
            createdAt: now, updatedAt: now, archived: false)])) != nil
        guard saved else { return nil }
        let items = proposal.programItems(programId: programId, deviceId: repo.deviceId) {
            CoachSessionProposal.liftLogName($0, known: known)
        }
        _ = try? await store.replaceLiftProgramItems(programId: programId, items: items)

        // New names join the exercise vocabulary, with no muscle: the Lift Log asks for it when the
        // exercise is next edited. Known names are left exactly as they are. Best-effort: a full
        // vocabulary must not undo the program.
        let fresh = Set(items.map(\.exercise)).filter { name in !known.contains(name) }
        for name in fresh.sorted() {
            _ = try? await store.upsertLiftExercises([LiftExerciseRow(
                id: UUID().uuidString, deviceId: repo.deviceId, name: name, primaryMuscle: nil,
                secondaryMuscles: [], createdAt: now, lastUsedTs: nil)])
        }

        proposal.programId = programId
        meta.session = proposal
        updateStoredMessage(id: messageId, text: CoachReplyMeta.join(body: body, meta: meta))
        return programId
    }

    /// The plan "Start" runs for the card of `messageId`, with the program behind it when it was added.
    func liftPlan(messageId: UUID) async -> (plan: [LiftPlanItem], programId: String?, name: String)? {
        guard let proposal = sessionProposal(messageId: messageId),
              let store = await repo.storeHandle() else { return nil }
        let vocabulary = (try? await store.liftExercises(deviceId: repo.deviceId)) ?? []
        func knownExercise(_ exercise: String) -> LiftExerciseRow? {
            vocabulary.first { CoachTools.sameExercise($0.name, exercise) }
        }

        if let programId = proposal.programId,
           let items = try? await store.liftProgramItems(programId: programId), !items.isEmpty {
            let plan = items.sorted { $0.ord < $1.ord }.map { item in
                LiftPlanItem(exercise: item.exercise, primaryMuscle: knownExercise(item.exercise)?.primaryMuscle,
                             secondaryMuscles: knownExercise(item.exercise)?.secondaryMuscles ?? [],
                             targetSets: item.targetSets, restSec: item.restSec,
                             targetRepsLow: item.targetRepsLow, targetRepsHigh: item.targetRepsHigh,
                             targetRpe: item.targetRpe, targetWeightKg: item.targetWeightKg, note: item.note,
                             programItemId: item.id, supersetGroup: item.supersetGroup)
            }
            return (plan, programId, proposal.name)
        }

        let plan = proposal.lines.map { line in
            let known = knownExercise(line.exercise)
            return LiftPlanItem(exercise: known?.name ?? line.exercise, primaryMuscle: known?.primaryMuscle,
                                secondaryMuscles: known?.secondaryMuscles ?? [], targetSets: line.sets,
                                restSec: line.restSec, targetRepsLow: line.repsLow, targetRepsHigh: line.repsHigh,
                                targetWeightKg: line.weightKg, note: line.note, supersetGroup: line.superset)
        }
        return (plan, nil, proposal.name)
    }
}
