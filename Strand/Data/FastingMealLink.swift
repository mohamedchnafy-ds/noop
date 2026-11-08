import Foundation
import WhoopStore

// Personal fork, chantier 15 PR C: a meal logged during a fast proposes to end the fast at the meal's time.
//
// The rule is PURE (`fastingEndProposal`, tested in `FastingMealLinkTests`): `MealJournal.saveMealEntry`
// records what the meal just saved proposes (UserDefaults, `pendingKey`), and the screens a meal can be
// saved from, Nutrition, the Coach and the Jeûne page, present it as a sheet (`FastingMealQuestionSheet`).
// The meal is saved whatever the answer. The end written is the meal's time, never « now », so a meal
// logged late moves the real end back to when it was eaten; a drink without calories asks nothing. The
// fast itself is only ever written through `FastingLog`, the one resolver.

/// « End the fast at 12:30? »: what a logged meal proposes about a fast.
struct FastingMealProposal: Equatable, Codable {
    enum Kind: String, Codable {
        /// The fast is running: end it at the meal's time.
        case endRunning
        /// The fast is over, but the meal was eaten before its recorded end: move that end back.
        case moveEndBack
    }

    var kind: Kind
    var fastId: String
    var mealId: String
    var mealName: String
    /// The end proposed, unix seconds: the meal's time, never after now and always after the start.
    var endSec: Int
}

enum FastingMealLink {

    /// UserDefaults: the proposal waiting for an answer, JSON of `FastingMealProposal`; absent when none.
    static let pendingKey = "fasting.pendingMealQuestion"
    /// UserDefaults: « meal id:end » of the last proposal answered « keep », so an edit of the same meal
    /// that changes nothing does not ask again.
    static let dismissedKey = "fasting.mealQuestionDismissed"

    // MARK: Rule

    /// What `meal`, with `kcal` of energy, proposes about `fast` at `now`; nil when nothing: no calories
    /// (water, black coffee, tea), a meal at or before the start (the last meal itself), or a meal after
    /// the recorded end of a fast that is over. A meal dated in the future counts as eaten now.
    static func fastingEndProposal(fast: FastRow, meal: MealRow, kcal: Int, now: Date) -> FastingMealProposal? {
        guard kcal > 0 else { return nil }
        let eaten = min(meal.eatenAt, Int(now.timeIntervalSince1970))
        guard eaten > fast.startedAt else { return nil }
        if let end = fast.endedAt {
            guard eaten < end else { return nil }
            return FastingMealProposal(kind: .moveEndBack, fastId: fast.id, mealId: meal.id, mealName: meal.name,
                                       endSec: eaten)
        }
        return FastingMealProposal(kind: .endRunning, fastId: fast.id, mealId: meal.id, mealName: meal.name,
                                   endSec: eaten)
    }

    /// Whether `proposal` still holds against `fast` as stored now (it may have been ended or corrected
    /// since the meal was saved).
    static func proposalStillHolds(_ proposal: FastingMealProposal, for fast: FastRow) -> Bool {
        guard proposal.endSec > fast.startedAt else { return false }
        switch proposal.kind {
        case .endRunning: return fast.endedAt == nil
        case .moveEndBack: return fast.endedAt.map { proposal.endSec < $0 } ?? false
        }
    }

    static func dismissalMemo(_ proposal: FastingMealProposal) -> String {
        "\(proposal.mealId):\(proposal.endSec)"
    }

    // MARK: Record

    /// Record what `entry`, just saved, proposes; called by `MealJournal.saveMealEntry` for every meal,
    /// wherever it was entered. The candidate fast is the running one, else the newest one over. An edit
    /// that moves the meal out of the fast withdraws its pending question.
    static func recordMealForFast(_ store: WhoopStore, entry: MealEntry, now: Date = Date()) async {
        let candidate: FastRow?
        if let running = try? await store.runningFast() {
            candidate = running
        } else {
            candidate = (try? await store.recentFasts(limit: 1))?.first
        }
        guard let fast = candidate else { return }
        let kcal = MealMath.totals(entry.items.map(\.nutrients)).kcal
        guard let proposal = fastingEndProposal(fast: fast, meal: entry.meal, kcal: kcal, now: now) else {
            if let pending = pendingProposal(), pending.mealId == entry.meal.id { clearPending() }
            return
        }
        guard UserDefaults.standard.string(forKey: dismissedKey) != dismissalMemo(proposal) else { return }
        if let data = try? JSONEncoder().encode(proposal) {
            UserDefaults.standard.set(data, forKey: pendingKey)
        }
    }

    /// The proposal waiting for an answer, if any.
    static func pendingProposal() -> FastingMealProposal? {
        guard let data = UserDefaults.standard.data(forKey: pendingKey) else { return nil }
        return try? JSONDecoder().decode(FastingMealProposal.self, from: data)
    }

    static func clearPending() {
        UserDefaults.standard.removeObject(forKey: pendingKey)
    }

    /// The pending proposal with its fast, re-read from the store; nil, and the record cleared, when the
    /// fast is gone or no longer in the state the proposal was made for.
    static func resolvePending(_ store: WhoopStore) async -> (proposal: FastingMealProposal, fast: FastRow)? {
        guard let proposal = pendingProposal() else { return nil }
        let rows = (try? await store.recentFasts(limit: 20)) ?? []
        guard let fast = rows.first(where: { $0.id == proposal.fastId }), proposalStillHolds(proposal, for: fast) else {
            clearPending()
            return nil
        }
        return (proposal, fast)
    }

    // MARK: Answer

    /// « End at 12:30 »: the end written through `FastingLog`, then the question is gone.
    static func applyProposal(_ store: WhoopStore, _ proposal: FastingMealProposal, fast: FastRow,
                              now: Date = Date()) async {
        let end = Date(timeIntervalSince1970: TimeInterval(proposal.endSec))
        switch proposal.kind {
        case .endRunning: await FastingLog.endFast(store, fast, endedAt: end, now: now)
        case .moveEndBack: await FastingLog.amendFast(store, fast, endedAt: end, now: now)
        }
        clearPending()
    }

    /// « Keep fasting » / « Keep 13:00 »: nothing written; the same meal at the same time will not ask again.
    static func dismissProposal(_ proposal: FastingMealProposal) {
        UserDefaults.standard.set(dismissalMemo(proposal), forKey: dismissedKey)
        clearPending()
    }
}
