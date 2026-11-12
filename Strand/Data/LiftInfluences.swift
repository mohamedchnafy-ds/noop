import Foundation

// « Ce qui influence mes séances » (fork chantier 18, lot C, maquette 4). EXPERIMENTAL and off by default
// (AGENTS.md: a signal that is not validated is never shown as a finding): each strength session is described
// by a few facts — the night's sleep, the water drunk before and during it, whether there was a session the
// day before, the protein eaten the day before — and by a few measures — its average heart rate, the recovery
// between sets, the weight lifted, its Effort, the HRV of the night after it. For one fact and one measure, the sessions WITH it are compared with the sessions WITHOUT it.
//
// Each lifter is compared with themselves only. Nothing is shown before `minPerGroup` sessions in each group
// and `minTotal` in all; the difference and both counts are always shown with it; and the words never say
// « causes »: the sentence is a fixed rule (« in your sessions, we observe… »), not free text. Pure: facts
// in, comparisons out, so tests pin the counting and the thresholds.

enum LiftInfluences {

    /// Sessions needed in each group, and in all, before a comparison is shown.
    static let minPerGroup = 6
    static let minTotal = 12
    /// A night of at least this many minutes counts as « slept well ».
    static let sleepThresholdMin = 450.0
    /// At least this much water from three hours before the session to its end.
    static let waterThresholdMl = 750
    /// How long before the session the water counted starts.
    static let waterLeadSec = 3 * 3600
    /// A difference smaller than this share of the « without » value (or 0.1) is no clear difference.
    static let clearShare = 0.03

    enum Factor: String, CaseIterable, Identifiable {
        case sleep, water, sessionDayBefore, proteinDayBefore
        var id: String { rawValue }
    }

    enum Measure: String, CaseIterable, Identifiable {
        case averageHr, recovery, volume, effort, nextNightHrv
        var id: String { rawValue }
        /// +1 when more is better, −1 when less is (an average heart rate lower at the same work).
        var direction: Double { self == .averageHr ? -1 : 1 }
    }

    /// What is known of one session. A nil fact or measure leaves the session out of the comparisons that
    /// need it.
    struct SessionFacts: Equatable {
        var startTs: Int
        var sleepMin: Double?
        var waterMl: Int?
        var sessionDayBefore: Bool
        var measures: [Measure: Double]
        /// The protein of the meals written down the day before, nil when no meal was (a hole, not a fast).
        var proteinDayBeforeG: Double? = nil
        /// The protein goal it is judged against (the current goal, `NutritionDayReader.currentPlan`), nil
        /// when there is none.
        var proteinGoalG: Int? = nil
    }

    struct Comparison: Equatable {
        var factor: Factor
        var measure: Measure
        var withMean: Double?
        var withoutMean: Double?
        var withCount: Int
        var withoutCount: Int

        var isEnough: Bool {
            withCount >= minPerGroup && withoutCount >= minPerGroup && withCount + withoutCount >= minTotal
        }
        /// « with » minus « without », nil until there is enough.
        var difference: Double? {
            guard isEnough, let withMean, let withoutMean else { return nil }
            return withMean - withoutMean
        }
        /// Too small to call a difference.
        var isClearDifference: Bool {
            guard let difference, let withoutMean else { return false }
            return abs(difference) > max(clearShare * abs(withoutMean), 0.1)
        }
        /// The « with » sessions read better on this measure (only meaningful for a clear difference).
        var isFavorable: Bool { (difference ?? 0) * measure.direction > 0 }
        /// The smaller group, for the progress bar shown before there is enough.
        var smallerGroup: Int { min(withCount, withoutCount) }
    }

    /// Whether a session has the factor, nil when that fact is not known for it.
    static func liftInfluenceHas(_ factor: Factor, _ facts: SessionFacts) -> Bool? {
        switch factor {
        case .sleep: return facts.sleepMin.map { $0 >= sleepThresholdMin }
        case .water: return facts.waterMl.map { $0 >= waterThresholdMl }
        case .sessionDayBefore: return facts.sessionDayBefore
        case .proteinDayBefore:
            guard let protein = facts.proteinDayBeforeG, let goal = facts.proteinGoalG, goal > 0 else { return nil }
            return protein >= Double(goal)
        }
    }

    /// The sessions with `factor` against those without, on `measure`.
    static func liftInfluenceComparison(_ sessions: [SessionFacts], factor: Factor,
                                        measure: Measure) -> Comparison {
        var with: [Double] = [], without: [Double] = []
        for session in sessions {
            guard let value = session.measures[measure], let has = liftInfluenceHas(factor, session) else { continue }
            if has { with.append(value) } else { without.append(value) }
        }
        func mean(_ xs: [Double]) -> Double? { xs.isEmpty ? nil : xs.reduce(0, +) / Double(xs.count) }
        return Comparison(factor: factor, measure: measure, withMean: mean(with), withoutMean: mean(without),
                          withCount: with.count, withoutCount: without.count)
    }

    /// Whether another strength session started the calendar day before `startTs`.
    static func liftHadSessionDayBefore(_ startTs: Int, among starts: [Int], calendar: Calendar) -> Bool {
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(startTs)))
        guard let before = calendar.date(byAdding: .day, value: -1, to: day) else { return false }
        return starts.contains { calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval($0))) == before }
    }

    /// The local day key (« yyyy-MM-dd ») `offset` days from the day `ts` falls on: −1 the day before (its
    /// meals), +1 the day after (the night that ends that morning, the next night's HRV).
    static func liftInfluenceDayKey(_ ts: Int, offset: Int, calendar: Calendar) -> String? {
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(ts)))
        guard let shifted = calendar.date(byAdding: .day, value: offset, to: day) else { return nil }
        return MealJournal.mealDayKey(shifted, calendar: calendar)
    }

    /// The water logged from `waterLeadSec` before `start` to `end`, nil when nothing was logged at all that
    /// day (water not tracked, rather than none drunk).
    static func liftSessionWater(_ entries: [HydrationEntry], start: Int, end: Int) -> Int? {
        guard !entries.isEmpty else { return nil }
        let from = Date(timeIntervalSince1970: TimeInterval(start - waterLeadSec))
        let to = Date(timeIntervalSince1970: TimeInterval(end))
        return entries.filter { $0.loggedAt >= from && $0.loggedAt <= to }.reduce(0) { $0 + $1.amountMl }
    }
}
