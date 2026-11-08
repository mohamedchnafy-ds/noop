import Foundation
import StrandAnalytics
import WhoopStore

// MARK: - The fiche's FASTING block (personal fork, chantier 15 PR C)

extension AICoachEngine {

    /// The fast and the water as the Jeûne page shows them: the running fast (`FastingLog.resolveFastingState`),
    /// else the newest one over, the last 7 days (`FastingLog.fastingHistory`) and today's water against its
    /// goal (the hydration store). Nil without a store, or when nothing was ever fasted and no water is logged
    /// today, so the coach is not handed an empty block.
    func fastingFiche(now: Date = Date()) async -> CoachFiche.Fasting? {
        guard let store = await repo.storeHandle() else { return nil }
        let running = await FastingLog.resolveFastingState(store, now: now)
        let newest = await FastingLog.recentFastRows(store, limit: 1).first
        let lastOver = running == nil
            ? newest.flatMap { $0.endedAt == nil ? nil : FastingLog.fastingState(of: $0, now: now) } : nil
        let water = Int((await repo.hydrationTotal(day: Repository.logicalDayKey(now))).rounded())
        guard newest != nil || water > 0 else { return nil }
        let lastGoal = UserDefaults.standard.integer(forKey: FastingLog.lastGoalKey)
        let goal = running?.fast.goalMinutes ?? newest?.goalMinutes
            ?? (lastGoal > 0 ? FastingTimeline.clampGoalMinutes(lastGoal) : FastingTimeline.defaultGoalMinutes)
        let history = await FastingLog.fastingHistory(store, days: 7, goalMinutes: goal, now: now)
        return CoachFiche.Fasting(running: running, lastOver: lastOver, dayMinutes: history.durations,
                                  summary: history.summary, goalMinutes: goal, waterML: water,
                                  waterGoalML: repo.hydrationGoalML(profileSex: profile?.sex ?? ""))
    }
}
