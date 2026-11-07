import Foundation

// Personal fork, chantier 14 (Carte v2): what keeps the Map's Lieux fast. Opening Lieux used to score the
// stress of 14 days one by one (`StressDayCurve.day`, the heaviest read) and to bucket 90 days of heart
// rate, every time, and again after each new point. Two things now:
//
// 1. The inputs of a past day are kept once the day is over (`PlaceMapDayStore`): a day that ended more
//    than `PlaceMapFreeze.frozenAfterSeconds` ago no longer changes, so only today and yesterday are read
//    again. Kept in the Caches folder: losing it costs one slow opening, nothing else.
// 2. The last place figures are kept too (`PlaceMapSnapshot`), so Lieux draws them at once and refreshes
//    behind.

/// The inputs of past days, kept between openings of the Map.
struct PlaceMapDayStore: Codable, Equatable {
    static let formatVersion = 1
    var version = PlaceMapDayStore.formatVersion
    /// The stress setting the kept windows were scored with; a change drops them.
    var personalBaseline = false
    /// Hourly stress windows by day ("yyyy-MM-dd").
    var stress: [String: [PlaceStressWindow]] = [:]
    /// Five-minute heart-rate buckets by day ("yyyy-MM-dd").
    var heartRate: [String: [PlaceHRBucket]] = [:]
}

/// The last place figures shown, with when they were computed.
struct PlaceMapSnapshot: Codable, Equatable {
    static let formatVersion = 1
    var version = PlaceMapSnapshot.formatVersion
    /// Unix seconds.
    var computedAt: Int
    var summaries: [PlaceSummary]
}

/// When a past day stops changing. PURE: tested in `PlaceMapCacheTests`.
enum PlaceMapFreeze {

    /// A day is kept once it ended at least this long ago (a strap synced the next morning has had the
    /// whole following day to deliver it).
    static let frozenAfterSeconds: TimeInterval = 86_400

    /// Days older than this are dropped from the store (the Lieux period plus a margin).
    static let keepDays = 100

    static func isFrozenDay(dayEnd: Date, now: Date) -> Bool {
        now.timeIntervalSince(dayEnd) >= frozenAfterSeconds
    }

    /// The store without the days before `oldestKey` ("yyyy-MM-dd" keys sort as dates), and empty when it
    /// was written by another format or with another stress setting.
    static func prunedDayStore(_ store: PlaceMapDayStore, oldestKey: String,
                               personalBaseline: Bool) -> PlaceMapDayStore {
        guard store.version == PlaceMapDayStore.formatVersion else {
            return PlaceMapDayStore(personalBaseline: personalBaseline)
        }
        var out = store
        if out.personalBaseline != personalBaseline {
            out.stress = [:]
            out.personalBaseline = personalBaseline
        }
        out.stress = out.stress.filter { $0.key >= oldestKey }
        out.heartRate = out.heartRate.filter { $0.key >= oldestKey }
        return out
    }

    /// The stress figure of each place carried over from the last computation, for figures computed
    /// without stress (stress is scored only when the Stress layer is asked for).
    static func carryPlaceStress(from previous: [PlaceSummary], into fresh: [PlaceSummary]) -> [PlaceSummary] {
        let kept = Dictionary(previous.map { ($0.id, $0.stress) }, uniquingKeysWith: { a, _ in a })
        return fresh.map { summary in
            var out = summary
            if out.stress.verdict == .none, out.stress.value == nil, let old = kept[summary.id] { out.stress = old }
            return out
        }
    }
}

/// The two cache files. Reads and writes are best effort: a missing or unreadable file reads as empty.
@MainActor
enum PlaceMapCacheFiles {

    private static var memoDays: PlaceMapDayStore?

    private static func fileURL(_ name: String) -> URL? {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        return base.appendingPathComponent(name, isDirectory: false)
    }

    private static let dayStoreName = "noop-places-map-days.json"
    private static let snapshotName = "noop-places-map-summaries.json"

    static func loadDayStore() -> PlaceMapDayStore {
        if let memoDays { return memoDays }
        guard let url = fileURL(dayStoreName), let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(PlaceMapDayStore.self, from: data)
        else { return PlaceMapDayStore() }
        memoDays = decoded
        return decoded
    }

    static func saveDayStore(_ store: PlaceMapDayStore) {
        memoDays = store
        guard let url = fileURL(dayStoreName), let data = try? JSONEncoder().encode(store) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func loadPlaceSnapshot() -> PlaceMapSnapshot? {
        guard let url = fileURL(snapshotName), let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(PlaceMapSnapshot.self, from: data),
              decoded.version == PlaceMapSnapshot.formatVersion
        else { return nil }
        return decoded
    }

    static func savePlaceSnapshot(_ summaries: [PlaceSummary], now: Date = Date()) {
        let snapshot = PlaceMapSnapshot(computedAt: Int(now.timeIntervalSince1970), summaries: summaries)
        guard let url = fileURL(snapshotName), let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Forget the last figures (every place was erased: they must not come back).
    static func clearPlaceSnapshot() {
        guard let url = fileURL(snapshotName) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Take one forgotten place out of the last figures.
    static func dropPlaceFromSnapshot(id: String) {
        guard var snapshot = loadPlaceSnapshot() else { return }
        snapshot.summaries.removeAll { $0.id == id }
        guard let url = fileURL(snapshotName), let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
