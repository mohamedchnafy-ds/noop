import Foundation
import WhoopStore

// MARK: - The Coach's menu card (personal fork, chantier 8, lot 3)
//
// "Add to the journal" saves every meal of the card to the journal as a normal meal (fork chantier 9:
// origin `coach`, in its moment of the day), counted at once, through `MealJournal`; the reply records
// the journal meals it became (`CoachMenuProposal.mealIds`), so it is never added twice. "Undo" removes
// those meals again. The wearer deletes the meals not eaten.

extension AICoachEngine {

    /// The menu card of `messageId`, nil when that message has none.
    func menuProposal(messageId: UUID) -> CoachMenuProposal? {
        messages.first(where: { $0.id == messageId }).flatMap { CoachReplyMeta.split($0.text).meta?.menu }
    }

    /// "Add to the journal": every meal of the card, as Coach meals, then remembered on the reply. False
    /// when nothing could be saved.
    @discardableResult
    func addMenuToJournal(messageId: UUID) async -> Bool {
        guard let proposal = menuProposal(messageId: messageId), !proposal.isAdded,
              let store = await repo.storeHandle() else { return false }
        var ids: [String] = []
        for meal in proposal.meals {
            if let saved = try? await MealJournal.saveMealEntry(
                store, name: meal.name, origin: .coach,
                eatenAt: Date(timeIntervalSince1970: TimeInterval(meal.eatenAt)), slot: meal.slot, lines: meal.itemRows) {
                ids.append(saved.meal.id)
            }
        }
        guard !ids.isEmpty else { return false }
        updateMenu(messageId: messageId) { $0.mealIds = ids }
        return true
    }

    /// "Undo": the meals the card added are removed (one already deleted is skipped).
    func undoMenu(messageId: UUID) async {
        guard let proposal = menuProposal(messageId: messageId), proposal.isAdded,
              let store = await repo.storeHandle() else { return }
        for id in proposal.mealIds {
            guard (try? await MealJournal.mealEntryById(store, id: id)) != nil else { continue }
            try? await MealJournal.removeMeal(store, id: id)
        }
        updateMenu(messageId: messageId) { $0.mealIds = [] }
    }

    private func updateMenu(messageId: UUID, _ change: (inout CoachMenuProposal) -> Void) {
        guard let message = messages.first(where: { $0.id == messageId }) else { return }
        let (body, meta) = CoachReplyMeta.split(message.text)
        guard var meta, var menu = meta.menu else { return }
        change(&menu)
        meta.menu = menu
        updateStoredMessage(id: messageId, text: CoachReplyMeta.join(body: body, meta: meta))
    }
}
