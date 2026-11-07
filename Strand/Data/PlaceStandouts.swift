import Foundation

// Personal fork, chantier 14 (Carte v2): « Ce qui ressort », the clear differences of the places, ranked.
// PURE: inputs are the place summaries (`PlaceMapReader.loadPlaceSummaries`), tested in
// `PlaceStandoutsTests`. A difference is listed only when it is a verdict (enough nights or visits, past
// the « proche » band) AND larger than its own margin of error, so noise is never ranked.

/// The figure a stand-out is about.
enum PlaceStandoutMetric: String, CaseIterable, Codable {
    case hrv, recovery, sleep, heartRate, stress
}

/// One clear difference of one place.
struct PlaceStandout: Equatable, Identifiable {
    var placeId: String
    var name: String
    var metric: PlaceStandoutMetric
    /// Place mean − normal, in the figure's unit (ms, points, minutes, bpm, points of time in High).
    var delta: Double
    /// Half-width of the 95 % interval, same unit.
    var margin: Double
    /// Nights (HRV, recovery, sleep) or visits (heart rate, stress).
    var count: Int
    var verdict: PlaceVerdict

    var id: String { placeId + "-" + metric.rawValue }
    /// How many margins the difference spans: the ranking key.
    var signalToNoise: Double { abs(delta) / max(margin, 0.000_1) }
}

enum PlaceStandouts {

    /// At most this many lines.
    static let maxStandouts = 5

    static func standoutFigure(_ summary: PlaceSummary, _ metric: PlaceStandoutMetric) -> PlaceFigure {
        switch metric {
        case .hrv: return summary.hrv
        case .recovery: return summary.recovery
        case .sleep: return summary.sleep
        case .heartRate: return summary.heartRate
        case .stress: return summary.stress
        }
    }

    /// The clear differences, the strongest first (in margins, then in size).
    static func placeStandouts(_ summaries: [PlaceSummary], limit: Int = maxStandouts) -> [PlaceStandout] {
        var out: [PlaceStandout] = []
        for summary in summaries {
            for metric in PlaceStandoutMetric.allCases {
                let f = standoutFigure(summary, metric)
                guard f.verdict == .better || f.verdict == .worse,
                      let delta = f.delta, let margin = f.margin, abs(delta) > margin
                else { continue }
                out.append(PlaceStandout(placeId: summary.id, name: summary.name, metric: metric, delta: delta,
                                         margin: margin, count: f.count, verdict: f.verdict))
            }
        }
        out.sort {
            $0.signalToNoise != $1.signalToNoise ? $0.signalToNoise > $1.signalToNoise : abs($0.delta) > abs($1.delta)
        }
        return Array(out.prefix(max(limit, 0)))
    }
}
