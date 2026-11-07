import Foundation

// Personal fork, chantier 14 step 2: the PLACES block of the Coach's context, written only when the wearer
// switched « Le Coach peut le lire » on (`PlaceTrackingSettings.coachReadsPlaces`). It carries the same
// figures as the Lieux view (`PlaceMapReader.loadPlaceSummaries`), never a coordinate.

extension CoachFiche {

    /// At most this many places, the most visited first.
    static let maxPlaces = 8

    static func placesBlock(_ places: [PlaceSummary]) -> String {
        guard !places.isEmpty else { return "" }
        var lines = ["PLACES (last 90 days; where the user stays, named by the user or numbered; each figure is "
                     + "compared with the user's OWN normal. A difference is not a cause: a place mostly reflects "
                     + "what the user does there. Coordinates are never shared):"]
        for place in places.sorted(by: { $0.visits > $1.visits }).prefix(maxPlaces) {
            var parts = ["\(place.visits) visits", "\(place.nights) nights"]
            func appendPlaceFigure(_ label: String, _ f: PlaceFigure, unit: String) {
                guard let value = f.value else { return }
                var text = "\(label) \(Int(value.rounded()))\(unit)"
                if let delta = f.delta, let normal = f.normal {
                    let sign = delta >= 0 ? "+" : "−"
                    text += " (\(sign)\(Int(abs(delta).rounded()))\(unit) vs normal \(Int(normal.rounded()))\(unit)"
                    text += f.verdict == .tooFew ? ", too few to conclude)" : ")"
                }
                parts.append(text)
            }
            appendPlaceFigure("night HRV", place.hrv, unit: " ms")
            appendPlaceFigure("recovery", place.recovery, unit: "%")
            appendPlaceFigure("sleep", place.sleep, unit: " min")
            appendPlaceFigure("HR during visits (sleep and workouts excluded, vs same hours elsewhere)", place.heartRate,
                   unit: " bpm")
            lines.append("  \(place.name): " + parts.joined(separator: ", "))
        }
        return lines.joined(separator: "\n")
    }
}
