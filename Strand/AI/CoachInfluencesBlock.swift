import Foundation

// « What shapes my sessions » in the Coach's fiche (personal fork, chantier 18): the comparisons the
// Progression block shows, handed to the Coach so it can explain them. Sent only while the wearer has the
// Experimental analysis on (`LiftInfluencesSection.enabledKey`) and « Use my data » is on. Every figure is
// `LiftInfluences`' own (the same groups, thresholds and clear-difference rule as the block), and the head
// tells the Coach the rule the block's wording keeps: an observed difference, never a cause.

extension CoachFiche {

    /// The comparisons of the latest sessions, every factor against every measure
    /// (`LiftInfluences.liftInfluenceComparisons`), and the protein goal the day before is judged against.
    struct Influences: Equatable {
        var comparisons: [LiftInfluences.Comparison]
        var proteinGoalG: Int?
        var sessions: Int
    }

    /// The WHAT SHAPES MY SESSIONS block: for each factor, the measures with enough sessions (both means,
    /// both counts, the verdict), else one line saying how far it is from enough.
    static func influencesBlock(_ influences: Influences) -> String {
        var lines = ["WHAT SHAPES MY SESSIONS (Experimental, turned on by the wearer in Progression; their last "
                     + "\(influences.sessions) strength sessions compared with themselves only; a comparison counts "
                     + "only with at least \(LiftInfluences.minPerGroup) sessions in each group and "
                     + "\(LiftInfluences.minTotal) in all; a gap within \(Int(LiftInfluences.clearShare * 100)) % "
                     + "is no clear difference; an observed difference is never a cause: say \"in your sessions, "
                     + "we observe…\" and name what else changes on those days):"]
        for factor in LiftInfluences.Factor.allCases {
            let rows = influences.comparisons.filter { $0.factor == factor }
            guard !rows.isEmpty else { continue }
            let name = influenceFactorText(factor, proteinGoalG: influences.proteinGoalG)
            let enough = rows.filter(\.isEnough)
            if enough.isEmpty {
                let best = rows.max { ($0.withCount + $0.withoutCount) < ($1.withCount + $1.withoutCount) } ?? rows[0]
                lines.append("  \(name): not enough data yet (\(best.withCount) sessions with, "
                             + "\(best.withoutCount) without)")
                continue
            }
            lines.append("  \(name):")
            for c in enough {
                guard let with = c.withMean, let without = c.withoutMean else { continue }
                let verdict: String
                if !c.isClearDifference {
                    verdict = "no clear difference"
                } else {
                    verdict = c.isFavorable ? "clear difference, reads better with" : "clear difference, reads worse with"
                }
                lines.append("    \(influenceMeasureText(c.measure)): \(influenceValue(with, c.measure)) with, "
                             + "\(influenceValue(without, c.measure)) without (\(c.withCount) vs \(c.withoutCount) "
                             + "sessions), \(verdict)")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// A factor and what « with » means for it.
    static func influenceFactorText(_ factor: LiftInfluences.Factor, proteinGoalG: Int?) -> String {
        switch factor {
        case .sleep:
            return "sleep the night before (with = \(duration(LiftInfluences.sleepThresholdMin)) or more)"
        case .water:
            return "water logged from 3 h before to the end (with = \(LiftInfluences.waterThresholdMl) ml or more)"
        case .sessionDayBefore:
            return "a strength session the day before (with = yes)"
        case .proteinDayBefore:
            let goal = proteinGoalG.map { "\($0) g" } ?? "the"
            return "protein of the meals logged the day before (with = at or above \(goal) goal; a day with no "
                + "meal logged is left out)"
        }
    }

    static func influenceMeasureText(_ measure: LiftInfluences.Measure) -> String {
        switch measure {
        case .averageHr: return "average HR (lower reads better)"
        case .recovery: return "HR recovery between sets"
        case .volume: return "weight lifted (volume load)"
        case .effort: return "Effort"
        case .nextNightHrv: return "HRV of the next night"
        }
    }

    static func influenceValue(_ value: Double, _ measure: LiftInfluences.Measure) -> String {
        switch measure {
        case .averageHr, .recovery: return "\(Int(value.rounded())) bpm"
        case .volume: return "\(Int(value.rounded())) kg"
        case .effort: return one(value)
        case .nextNightHrv: return "\(Int(value.rounded())) ms"
        }
    }
}
