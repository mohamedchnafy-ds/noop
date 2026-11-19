import Foundation

extension AICoachEngine {

    /// What the Coach's suggested questions may rely on (personal fork, `CoachDayPrompts`), read on the
    /// device through the funnels the Today screen and the Coach's fiche already read: today's row
    /// (`Repository.today`), the Charge baselines' HRV band (`TodayVitalRange.normalBand`), the Synthèse's
    /// sleep figures (`sleepSynthesisFigures`), today's session (`TodaySessionResolver`), the meal journal
    /// (`nutritionFiche`) and the fast (`FastingLog.resolveFastingState`). Nothing is sent: these only pick
    /// and word the chips. With « Use my data » off, only the hour and the photo switch are read.
    func suggestionFacts(photosAvailable: Bool, now: Date = Date()) async -> CoachSuggestionFacts {
        var facts = CoachSuggestionFacts()
        facts.photosAvailable = photosAvailable
        facts.hour = Calendar.current.component(.hour, from: now)
        guard dataConsent else { return facts }
        facts.useData = true

        // Today's own row only: `Repository.today` is nil, never yesterday's, when today has none.
        let days = repo.days
        if let today = repo.today {
            facts.nightMinutes = today.totalSleepMin.flatMap { $0 >= 1 ? Int($0.rounded()) : nil }
            facts.charge = today.recovery.map { Int($0.rounded()) }
            if let hrv = today.avgHrv, let band = TodayVitalRange.normalBand(repo.chargeBaselines?.hrv) {
                facts.hrvBelowNormal = hrv < band.lowerBound
            }
        }
        let todayKey = repo.today?.day ?? Repository.logicalDayKey(now)
        func since(_ daysBack: Int) -> String {
            Repository.localDayKey(Calendar.current.date(byAdding: .day, value: -daysBack, to: now) ?? now)
        }
        let month = days.filter { $0.day <= todayKey && $0.day >= since(29) }
        facts.hrvDays30 = month.filter { $0.avgHrv != nil }.count
        facts.dataDays7 = month.filter { $0.day >= since(6) }.count

        if let sleep = await repo.sleepSynthesisFigures(now: now) {
            if sleep.isDebt, let debt = sleep.debtMin, debt >= 60 { facts.debtMinutes = Int(debt.rounded()) }
            facts.bedtimeKnown = sleep.bedtimeMin != nil
        }

        let dayStart = Calendar.current.startOfDay(for: now)
        let nowTs = Int(now.timeIntervalSince1970)
        if let resolution = await TodaySessionResolver.resolveTodaySession(
            repo: repo, calendarFrom: Int(dayStart.timeIntervalSince1970), calendarTo: nowTs, isToday: true, now: now) {
            switch resolution.session?.state {
            case .next?: facts.session = .planned(resolution.session?.name ?? "")
            case .running?: facts.session = .running
            case .done?: facts.session = .done(resolution.session?.name ?? "")
            case .rest?: facts.session = .rest
            case nil: facts.session = .none
            }
            if let last = resolution.performed.compactMap({ $0.row.endTs }).max() {
                facts.lastLiftDaysAgo = max(0, (nowTs - last) / 86_400)
            }
        }

        if let nutrition = await nutritionFiche(spent: nil, now: now) {
            facts.mealsToday = nutrition.meals
            facts.mealDays7 = nutrition.weekDaysLogged
            let left = nutrition.plan.proteinG - Int(nutrition.eaten.proteinG.rounded())
            if nutrition.meals > 0, left > 10 { facts.proteinLeftG = left }
        }

        if let store = await repo.storeHandle(), let fast = await FastingLog.resolveFastingState(store, now: now),
           fast.isRunning {
            facts.fastingMinutes = fast.elapsedMinutes
        }
        return facts
    }
}
