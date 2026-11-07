import Foundation
import WhoopStore

// Personal fork, chantier 14 step 2: the settings of the place tracking (« Lieux » and « Suivi de
// position »), and the pure rules the tracker applies with them. UserDefaults only: a setting is not data,
// and none of them crosses the `.noopbak` boundary.

/// How often the tracking keeps a position.
enum PlaceTrackingMode: String, CaseIterable, Identifiable {
    /// About every 500 m, from the cell network: iOS's significant location changes, no GPS.
    case eco
    /// One point per interval, to about 100 m.
    case balanced
    /// One point every N metres, GPS.
    case precise

    var id: String { rawValue }
}

/// A daily span with no position kept, in minutes after midnight (`end` may be before `start`: it then
/// runs over midnight).
struct PlaceQuietRange: Codable, Equatable, Hashable, Identifiable {
    var startMinute: Int
    var endMinute: Int

    var id: String { "\(startMinute)-\(endMinute)" }

    /// True when `minute` (0…1439) is inside the span.
    func containsMinute(_ minute: Int) -> Bool {
        let s = ((startMinute % 1440) + 1440) % 1440
        let e = ((endMinute % 1440) + 1440) % 1440
        if s == e { return false }
        return s < e ? (minute >= s && minute < e) : (minute >= s || minute < e)
    }
}

enum PlaceTrackingSettings {

    // MARK: Keys

    static let enabledKey = "places.enabled"
    static let modeKey = "places.mode"
    static let intervalKey = "places.intervalMinutes"
    static let distanceKey = "places.distanceMeters"
    static let pauseWhenStillKey = "places.pauseWhenStill"
    static let quietNightKey = "places.quietNight"
    static let quietRangesKey = "places.quietRanges"
    static let keepPointsDaysKey = "places.keepPointsDays"
    static let keepVisitsDaysKey = "places.keepVisitsDays"
    static let coachReadsKey = "places.coachCanRead"

    // MARK: Choices and defaults

    static let intervalChoices = [5, 15, 30, 60]
    static let distanceChoices = [50, 100, 250, 500]
    static let keepChoices = [90, 180, 365, 730]
    static let defaultMode = PlaceTrackingMode.balanced
    static let defaultInterval = 15
    static let defaultDistance = 100
    static let defaultKeepDays = 365
    /// « Pas de relevé la nuit »: 23:00 – 07:00.
    static let night = PlaceQuietRange(startMinute: 23 * 60, endMinute: 7 * 60)

    // MARK: Reads

    static func isEnabled(_ d: UserDefaults = .standard) -> Bool { d.bool(forKey: enabledKey) }

    static func mode(_ d: UserDefaults = .standard) -> PlaceTrackingMode {
        d.string(forKey: modeKey).flatMap(PlaceTrackingMode.init(rawValue:)) ?? defaultMode
    }

    static func intervalMinutes(_ d: UserDefaults = .standard) -> Int {
        let v = d.integer(forKey: intervalKey)
        return intervalChoices.contains(v) ? v : defaultInterval
    }

    static func distanceMeters(_ d: UserDefaults = .standard) -> Int {
        let v = d.integer(forKey: distanceKey)
        return distanceChoices.contains(v) ? v : defaultDistance
    }

    /// On by default.
    static func pausesWhenStill(_ d: UserDefaults = .standard) -> Bool {
        d.object(forKey: pauseWhenStillKey) as? Bool ?? true
    }

    /// On by default.
    static func quietAtNight(_ d: UserDefaults = .standard) -> Bool {
        d.object(forKey: quietNightKey) as? Bool ?? true
    }

    static func quietRanges(_ d: UserDefaults = .standard) -> [PlaceQuietRange] {
        guard let data = d.data(forKey: quietRangesKey),
              let ranges = try? JSONDecoder().decode([PlaceQuietRange].self, from: data) else { return [] }
        return ranges
    }

    static func setQuietRanges(_ ranges: [PlaceQuietRange], _ d: UserDefaults = .standard) {
        d.set(try? JSONEncoder().encode(ranges), forKey: quietRangesKey)
    }

    static func keepPointsDays(_ d: UserDefaults = .standard) -> Int {
        let v = d.integer(forKey: keepPointsDaysKey)
        return keepChoices.contains(v) ? v : defaultKeepDays
    }

    static func keepVisitsDays(_ d: UserDefaults = .standard) -> Int {
        let v = d.integer(forKey: keepVisitsDaysKey)
        return keepChoices.contains(v) ? v : defaultKeepDays
    }

    /// Off by default: the Coach reads the places only when the wearer allows it.
    static func coachReadsPlaces(_ d: UserDefaults = .standard) -> Bool { d.bool(forKey: coachReadsKey) }

    // MARK: Labels

    /// « Équilibré · 15 min », « Précis · 100 m », « Économe »: the value of the Lieux row.
    static func summaryLabel(mode: PlaceTrackingMode, intervalMinutes: Int, distanceMeters: Int) -> String {
        switch mode {
        case .eco: return String(localized: "Saver")
        case .balanced: return String(localized: "Balanced") + " · " + String(localized: "\(intervalMinutes) min")
        case .precise: return String(localized: "Precise") + " · " + String(localized: "\(distanceMeters) m")
        }
    }

    /// « 12:00 – 14:00 ».
    static func rangeLabel(_ range: PlaceQuietRange) -> String {
        func hhmm(_ m: Int) -> String {
            let v = ((m % 1440) + 1440) % 1440
            return String(format: "%02d:%02d", v / 60, v % 60)
        }
        return hhmm(range.startMinute) + " – " + hhmm(range.endMinute)
    }

    /// « Aucune », the only span, or « 2 plages ».
    static func rangesLabel(_ ranges: [PlaceQuietRange]) -> String {
        switch ranges.count {
        case 0: return String(localized: "No span")
        case 1: return rangeLabel(ranges[0])
        default: return String(localized: "\(ranges.count) spans")
        }
    }

    /// « il y a 6 min », « il y a 2 h », « il y a 3 j » (« à l'instant » under a minute).
    static func agoLabel(from date: Date, to now: Date) -> String {
        let seconds = max(Int(now.timeIntervalSince(date)), 0)
        if seconds < 60 { return String(localized: "just now") }
        if seconds < 3_600 { return String(localized: "\(seconds / 60) min ago") }
        if seconds < 86_400 { return String(localized: "\(seconds / 3_600) h ago") }
        return String(localized: "\(seconds / 86_400) d ago")
    }
}

/// The tracker's rules, pure so they are tested without CoreLocation (`PlaceTrackingTests`).
enum PlaceTrackingRules {

    /// True when no position is kept at `date`: the night (when on) or one of the other spans.
    static func isQuietTime(_ date: Date, night: Bool, ranges: [PlaceQuietRange],
                            calendar: Calendar = .current) -> Bool {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        if night && PlaceTrackingSettings.night.containsMinute(minute) { return true }
        return ranges.contains { $0.containsMinute(minute) }
    }

    /// Whether a new fix is kept as a point. Économe keeps every significant change; Équilibré one per
    /// interval (a fix a little early still counts, so a 15 min interval does not drift to 16); Précis one
    /// every N metres. The first fix is always kept.
    static func keepsFix(mode: PlaceTrackingMode, intervalMinutes: Int, distanceMeters: Int,
                         lastTsMs: Int64?, lastLat: Double?, lastLon: Double?,
                         tsMs: Int64, lat: Double, lon: Double) -> Bool {
        guard let lastTsMs, let lastLat, let lastLon else { return true }
        guard tsMs > lastTsMs else { return false }
        switch mode {
        case .eco:
            return true
        case .balanced:
            let interval = Int64(intervalMinutes) * 60_000
            return tsMs - lastTsMs >= interval - min(interval / 10, 60_000)
        case .precise:
            let moved = RouteMath.haversineMeters(.init(lastLat, lastLon), .init(lat, lon))
            return moved >= Double(distanceMeters) * 0.9
        }
    }

    /// A fix too vague to keep: worse than 1 km, or invalid.
    static func isUsableAccuracy(_ accuracyM: Double) -> Bool {
        accuracyM >= 0 && accuracyM <= 1_000
    }
}

/// How a place is called on screen: its name, else « Lieu n » by order of creation.
enum PlaceNaming {
    static func placeName(_ place: PlaceRow, in places: [PlaceRow]) -> String {
        if let name = place.name, !name.isEmpty { return name }
        let ordered = places.sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
        let number = (ordered.firstIndex { $0.id == place.id } ?? ordered.count) + 1
        return String(localized: "Place \(number)")
    }
}
