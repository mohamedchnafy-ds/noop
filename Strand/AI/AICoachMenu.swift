import Foundation
import WhoopStore

// MARK: - The Coach's menu card (personal fork, chantier 8, lot 3)
//
// "Add as planned" saves every meal of the card to the journal as PLANNED, through `MealJournal`, and the
// reply records the journal meals it became (`CoachMenuProposal.mealIds`), so it is never added twice;
// "Undo" removes those meals again (a meal already marked eaten stays: it is the wearer's now).

extension AICoachEngine {

    /// The menu card of `messageId`, nil when that message has none.
    func menuProposal(messageId: UUID) -> CoachMenuProposal? {
        messages.first(where: { $0.id == messageId }).flatMap { CoachReplyMeta.split($0.text).meta?.menu }
    }

    /// "Add as planned": every meal of the card, planned, then remembered on the reply. False when nothing
    /// could be saved.
    @discardableResult
    func addMenuAsPlanned(messageId: UUID) async -> Bool {
        guard let proposal = menuProposal(messageId: messageId), !proposal.isAdded,
              let store = await repo.storeHandle() else { return false }
        var ids: [String] = []
        for meal in proposal.meals {
            if let saved = try? await MealJournal.saveMealEntry(
                store, name: meal.name, origin: .manual,
                eatenAt: Date(timeIntervalSince1970: TimeInterval(meal.eatenAt)), planned: true, lines: meal.itemRows) {
                ids.append(saved.meal.id)
            }
        }
        guard !ids.isEmpty else { return false }
        updateMenu(messageId: messageId) { $0.mealIds = ids }
        return true
    }

    /// "Undo": the planned meals the card added are removed; one already marked eaten is kept.
    func undoMenu(messageId: UUID) async {
        guard let proposal = menuProposal(messageId: messageId), proposal.isAdded,
              let store = await repo.storeHandle() else { return }
        for id in proposal.mealIds {
            guard let entry = try? await MealJournal.mealEntryById(store, id: id), entry.meal.planned else { continue }
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
