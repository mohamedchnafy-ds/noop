import Foundation
import WhoopStore

// MARK: - The Coach's meals (personal fork, Nutrition 4c)
//
// The meal card's two actions and the NUTRITION block of the fiche. A card is saved to the journal only
// on a tap, through `MealJournal`, with the lines the card shows; the reply then records the journal meal
// it became (`CoachMealProposal.mealId`), so it is never added twice.

extension AICoachEngine {

    /// The meal card of `messageId`, nil when that message has none.
    func mealProposal(messageId: UUID) -> CoachMealProposal? {
        messages.first(where: { $0.id == messageId }).flatMap { CoachReplyMeta.split($0.text).meta?.meal }
    }

    /// "Add to journal": save the card's meal and remember it on the reply. Returns the journal meal's id,
    /// the existing one when the card was already added; nil when nothing could be saved.
    @discardableResult
    func addMealToJournal(messageId: UUID) async -> String? {
        guard let proposal = mealProposal(messageId: messageId) else { return nil }
        if let existing = proposal.mealId { return existing }
        guard let store = await repo.storeHandle() else { return nil }
        guard let saved = try? await MealJournal.saveMealEntry(
            store, name: proposal.name, origin: proposal.origin,
            eatenAt: Date(timeIntervalSince1970: TimeInterval(proposal.eatenAt)), lines: proposal.itemRows) else {
            return nil
        }
        markMealSaved(messageId: messageId, mealId: saved.meal.id)
        return saved.meal.id
    }

    /// Record on the reply that its card became the journal meal `mealId` (the editor's Save after Edit).
    func markMealSaved(messageId: UUID, mealId: String) {
        guard let message = messages.first(where: { $0.id == messageId }) else { return }
        let (body, meta) = CoachReplyMeta.split(message.text)
        guard var meta, var proposal = meta.meal, proposal.mealId == nil else { return }
        proposal.mealId = mealId
        meta.meal = proposal
        updateStoredMessage(id: messageId, text: CoachReplyMeta.join(body: body, meta: meta))
    }

    /// The fiche's NUTRITION block: today's meals against the calories spent and the goals, with the
    /// figures the Nutrition screen shows (`NutritionDaySummary`, `NutritionDayReader.currentPlan`), then
    /// the logged days of the 7 days before. Nil without a profile or a store.
    func nutritionFiche(spent: TodayEnergy.Split?, now: Date = Date()) async -> CoachFiche.Nutrition? {
        guard let profile, let store = await repo.storeHandle() else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let todayKey = Repository.localDayKey(today)
        let weekStart = calendar.date(byAdding: .day, value: -7, to: today) ?? today
        let entries = (try? await MealJournal.mealJournalRange(
            store, fromDay: Repository.localDayKey(weekStart), toDay: todayKey)) ?? []
        let day = NutritionDaySummary(dayKey: todayKey, meals: entries.filter { $0.meal.day == todayKey }, spent: spent)

        var weekKcal: [Int] = []
        var weekProtein: [Double] = []
        for (key, meals) in Dictionary(grouping: entries.filter { $0.meal.day != todayKey }, by: { $0.meal.day })
            where !meals.isEmpty && key < todayKey {
            let total = MealMath.totals(meals.flatMap { $0.items.map(\.nutrients) })
            weekKcal.append(total.kcal)
            weekProtein.append(total.proteinG)
        }
        return CoachFiche.Nutrition(
            eaten: day.eaten, meals: day.meals.count,
            spentKcal: spent.map { Int($0.totalKcal.rounded()) }, balanceKcal: day.balanceKcal,
            plan: NutritionDayReader.currentPlan(profile: profile),
            reference: NutritionDayReader.referenceBefore(repo, today: now),
            weekDaysLogged: weekKcal.count,
            weekMeanKcal: weekKcal.isEmpty ? nil : Int((Double(weekKcal.reduce(0, +)) / Double(weekKcal.count)).rounded()),
            weekMeanProteinG: weekProtein.isEmpty ? nil
                : Int((weekProtein.reduce(0, +) / Double(weekProtein.count)).rounded()))
    }
}
