import Foundation
import WhoopStore

// MARK: - The Coach's action cards, run on the device (personal fork, chantier 8)
//
// A nap, a workout correction, a set correction or a fact to remember: the card is made from the rows the
// screens read (`repo.workoutRows`, the Lift Log store, `coachProfile`), written only on "Confirm" through
// the paths the screens use (`Repository.addManualNap`, `saveManualWorkout`, the Lift Log store as
// `LiftSessionEditSheet` writes it), and put back on "Undo" from what the card kept. Each Confirm and Undo
// is logged on this device (`coachActionLog`) so a corrected record can be told from a measured one.

extension AICoachEngine {

    /// The card for one action tool call, or the problem the model is told about.
    func resolveAction(_ kind: CoachActionProposal.Kind, input: [String: Any],
                       now: Date = Date()) async -> CoachActionProposal.Parsed {
        if kind.readsData && !dataConsent {
            return (nil, "No data access: the user turned off “Use my data”.")
        }
        let system = UnitSystem(rawValue: UserDefaults.standard.string(forKey: UnitPrefs.systemKey) ?? "") ?? .metric
        switch kind {
        case .nap:
            return CoachActionProposal.nap(from: input, now: now)
        case .remember:
            return CoachActionProposal.rememberCard(from: input, profile: coachProfile)
        case .workout:
            let distanceSystem = UnitPrefs.resolveDistance(
                system: system, override: UserDefaults.standard.string(forKey: UnitPrefs.distanceSystemKey) ?? "")
            let rows = await repo.workoutRows(days: 62)
            return CoachActionProposal.workoutFix(from: input, rows: rows, now: now) {
                UnitFormatter.distanceFromMeters($0, system: distanceSystem)
            }
        case .liftSets:
            guard let store = await repo.storeHandle() else { return (nil, "The Lift Log cannot be read right now.") }
            let to = Int(now.timeIntervalSince1970)
            var sessions: [CoachActionProposal.LiftSession] = []
            for row in (try? await store.liftSessions(deviceId: repo.deviceId, fromTs: to - 366 * 86_400, toTs: to)) ?? [] {
                sessions.append(.init(row: row, sets: (try? await store.liftSets(sessionId: row.id)) ?? []))
            }
            return CoachActionProposal.liftFix(from: input, sessions: sessions, system: system, now: now)
        }
    }

    /// The action card of `messageId`, nil when that message has none.
    func actionProposal(messageId: UUID) -> CoachActionProposal? {
        messages.first(where: { $0.id == messageId }).flatMap { CoachReplyMeta.split($0.text).meta?.action }
    }

    /// "Confirm": write the card's change and remember on the reply that it was. False when nothing could be
    /// written (the card stays as it was).
    @discardableResult
    func confirmAction(messageId: UUID) async -> Bool {
        guard var proposal = actionProposal(messageId: messageId), proposal.state == .proposed else { return false }
        switch proposal.kind {
        case .nap:
            guard let nap = proposal.nap else { return false }
            await repo.addManualNap(startTs: nap.startTs, endTs: nap.endTs)
        case .workout:
            guard let fix = proposal.workout else { return false }
            await repo.saveManualWorkout(fix.after, replacing: fix.before)
        case .liftSets:
            guard let fix = proposal.lift, let store = await repo.storeHandle() else { return false }
            if !fix.upserts.isEmpty { _ = try? await store.upsertLiftSets(fix.upserts) }
            if !fix.deletedIds.isEmpty { _ = try? await store.deleteLiftSets(ids: fix.deletedIds) }
        case .remember:
            guard let fact = proposal.fact else { return false }
            coachProfile = CoachActionProposal.profileAdding(fact, to: coachProfile)
        }
        proposal.state = .applied
        proposal.appliedAt = Int(Date().timeIntervalSince1970)
        storeAction(proposal, messageId: messageId)
        logAction("confirmed", proposal)
        return true
    }

    /// "Undo": put back what the card changed.
    func undoAction(messageId: UUID) async {
        guard var proposal = actionProposal(messageId: messageId), proposal.state == .applied else { return }
        switch proposal.kind {
        case .nap:
            guard let nap = proposal.nap else { return }
            // `addManualNap` keys the session on its start; the same delete the Sleep tab offers.
            _ = await repo.deleteSleepSession(detectedStartTs: nap.startTs, endTs: nap.endTs)
        case .workout:
            guard let fix = proposal.workout else { return }
            await repo.saveManualWorkout(fix.before, replacing: fix.after)
        case .liftSets:
            guard let fix = proposal.lift, let store = await repo.storeHandle() else { return }
            let original = Set(fix.before.map(\.id))
            let added = fix.upserts.map(\.id).filter { !original.contains($0) }
            if !added.isEmpty { _ = try? await store.deleteLiftSets(ids: added) }
            if !fix.before.isEmpty { _ = try? await store.upsertLiftSets(fix.before) }
        case .remember:
            guard let fact = proposal.fact else { return }
            coachProfile = CoachActionProposal.profileRemoving(fact, from: coachProfile)
        }
        proposal.state = .undone
        storeAction(proposal, messageId: messageId)
        logAction("undone", proposal)
    }

    private func storeAction(_ proposal: CoachActionProposal, messageId: UUID) {
        guard let message = messages.first(where: { $0.id == messageId }) else { return }
        let (body, meta) = CoachReplyMeta.split(message.text)
        guard var meta else { return }
        meta.action = proposal
        updateStoredMessage(id: messageId, text: CoachReplyMeta.join(body: body, meta: meta))
    }

    // MARK: Origin log

    static let actionLogKey = "ai.coachActionLog"
    static let actionLogLimit = 200

    /// Each Confirm and Undo of a Coach card, newest last: when, what and the card's lines. On this device
    /// only, never sent, not in `.noopbak`.
    var coachActionLog: [String] { UserDefaults.standard.stringArray(forKey: Self.actionLogKey) ?? [] }

    private func logAction(_ verb: String, _ proposal: CoachActionProposal) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let entry = "\(stamp) \(verb) \(proposal.kind.toolName): " + proposal.lines.joined(separator: "; ")
        UserDefaults.standard.set(Array((coachActionLog + [entry]).suffix(Self.actionLogLimit)), forKey: Self.actionLogKey)
    }
}
