import Foundation
import StrandAnalytics
import WhoopStore

// MARK: - Load suggestion (personal fork)
//
// Double progression, the plain version: when every working set of an exercise LAST time reached the
// top of its rep range without going past the planned RPE, the weight goes up by one step next time.
// Pure, so `LiftProgressionTests` can pin the rule; the sheet only formats what comes back.

enum LiftProgression {
    /// One plate step on a metric bar.
    static let metricStepKg = 2.5
    /// One plate step on an imperial bar, in kilograms (5 lb).
    static let imperialStepKg = 5 / UnitFormatter.poundsPerKilogram

    struct Suggestion: Equatable {
        /// The weight every qualifying set was done at last time.
        let fromKg: Double
        /// What to load this time.
        let toKg: Double
    }

    /// - Parameters:
    ///   - lastSets: the exercise's sets from the most recent session it appeared in (what the grey
    ///     numbers come from); warm-ups and unperformed sets are ignored here.
    ///   - item: the program line, whose targets define "enough".
    ///   - stepKg: the increment to propose.
    /// Nil when the line has no rep target, fewer qualifying sets were done than planned, any set fell
    /// short of the top of the range, any rated set exceeded the planned RPE, or the sets were not all
    /// at one weight (a pyramid is its own plan, not a double progression).
    static func suggest(lastSets: [LiftSetRow], item: LiftPlanItem, stepKg: Double = metricStepKg) -> Suggestion? {
        guard let topReps = item.targetRepsHigh ?? item.targetRepsLow, topReps > 0, item.targetSets > 0 else {
            return nil
        }
        let working = lastSets.filter { !$0.isWarmup && LiftMetrics.isPerformed(reps: $0.reps) }
        guard working.count >= item.targetSets else { return nil }
        var weight: Double?
        for set in working {
            guard let reps = set.reps, reps >= topReps, let kg = set.weightKg, kg > 0 else { return nil }
            if let cap = item.targetRpe, let rpe = set.rpe, rpe > cap { return nil }
            if let w = weight, abs(w - kg) > 0.001 { return nil }
            weight = kg
        }
        guard let fromKg = weight else { return nil }
        return Suggestion(fromKg: fromKg, toKg: fromKg + stepKg)
    }
}
