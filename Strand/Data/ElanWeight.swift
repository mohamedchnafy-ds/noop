import Foundation
import WhoopStore

// Personal fork, chantier 10 (Élan), PR A: the morning weigh-ins and THE ONE resolver of the weight trend.
//
// Storage (Mohamed's choice, 8 Nov.): one weigh-in per local day in the existing `metricSeries` tall table,
// under the dedicated source id "noop-weight" (the `MoodStore` / `NutritionSeries` pattern), key "weight",
// kilograms to a tenth. No migration: the table exists on both platforms, the rows ride the `.noopbak`
// with the database, and an Apple Health import can never clobber them (it writes under "apple-health").
// Analyses reads the series through the catalogue (`MetricDescriptor`, source "noop-weight").
//
// The fear of the scale (fiche, 2 Nov.): a single weigh-in is dominated by water, salt, carbs and
// yesterday's session, so NOTHING here states the gap between two mornings. Every surface shows the
// smoothed TREND only, and the trend exists only after `trendMinimumCount` weigh-ins. The smoothing is an
// exponential moving average over DAYS: with daily weigh-ins each one moves the trend by a tenth of its
// distance; after a gap of d days the weigh-in counts as d daily steps would (1 − 0.9^d), so a long
// silence does not freeze the trend on a stale value.

/// One weigh-in: a local day ("yyyy-MM-dd") and kilograms.
struct ElanWeighIn: Equatable {
    var day: String
    var kg: Double
}

/// One point of the smoothed curve: the trend on a weigh-in day.
struct ElanWeightTrendPoint: Equatable {
    var day: String
    var kg: Double
}

/// What the Poids card and page state, resolved once from the stored weigh-ins (`ElanWeight.weightSummary`).
struct ElanWeightSummary: Equatable {
    /// One per day, oldest first.
    var weighIns: [ElanWeighIn]
    /// The smoothed curve, one point per weigh-in day; empty under `ElanWeight.trendMinimumCount` weigh-ins.
    var trend: [ElanWeightTrendPoint]
    var targetKg: Double?
    /// Kilograms per week over the trend's last `ElanWeight.rateWindowDays`; nil under two weeks of trend.
    var ratePerWeekKg: Double?
    /// The day the trend reaches the target at that rate; nil without a target, a rate heading to it, or
    /// inside `ElanWeight.etaHorizonDays`.
    var etaDay: String?

    var count: Int { weighIns.count }
    var first: ElanWeighIn? { weighIns.first }
    var latest: ElanWeighIn? { weighIns.last }
    var trendKg: Double? { trend.last?.kg }
    var hasTrend: Bool { !trend.isEmpty }

    /// The trend minus the starting point (the first weigh-in), in kg; nil without a trend.
    var changeSinceStartKg: Double? {
        guard let trendKg, let first else { return nil }
        return trendKg - first.kg
    }

    /// The trend minus the target, in kg (positive = above the target); nil without both.
    var remainingKg: Double? {
        guard let trendKg, let targetKg else { return nil }
        return trendKg - targetKg
    }
}

enum ElanWeight {

    // MARK: Storage

    /// Dedicated source id (the `deviceId` column) of the weigh-ins.
    static let weightDeviceId = "noop-weight"

    /// The metric key, the one the catalogue and the Apple Health import use for a body weight.
    static let weightKey = "weight"

    /// UserDefaults: the target weight, kg; absent or out of range = no target. A setting, not in `.noopbak`
    /// (the Nutrition goals' rule).
    static let targetKey = "elan.weight.targetKg"

    /// UserDefaults: « Le profil suit la tendance », on by default (fiche, v2.1).
    static let profileFollowsKey = "elan.weight.profileFollowsTrend"

    // MARK: Rules

    /// Weigh-ins before a trend is stated at all (« Ta tendance apparaîtra après 5 pesées »).
    static let trendMinimumCount = 5

    /// How much of the gap to the new weigh-in the trend takes on, per day.
    static let smoothing = 0.1

    /// The trend's tail the rate is read over.
    static let rateWindowDays = 28

    /// The least span of trend the rate needs; a shorter one is noise.
    static let rateMinimumSpanDays = 14

    /// Under this pace (kg / week) no date is estimated.
    static let rateFloorKgPerWeek = 0.05

    /// A date further away than this is not stated.
    static let etaHorizonDays = 730

    /// What a weigh-in may say.
    static let kgRange: ClosedRange<Double> = 20...400

    /// One weigh-in per day, the last value of a day kept, oldest first.
    static func dedupe(_ weighIns: [ElanWeighIn]) -> [ElanWeighIn] {
        var byDay: [String: Double] = [:]
        for weighIn in weighIns { byDay[weighIn.day] = weighIn.kg }
        return byDay.keys.sorted().map { ElanWeighIn(day: $0, kg: byDay[$0] ?? 0) }
    }

    /// The smoothed curve: the first weigh-in seeds it, each later one moves it by `1 − (1 − smoothing)^gap`
    /// of the distance, `gap` the days since the previous weigh-in. Empty under `trendMinimumCount`.
    static func weightTrend(_ weighIns: [ElanWeighIn]) -> [ElanWeightTrendPoint] {
        let sorted = dedupe(weighIns)
        guard sorted.count >= trendMinimumCount, let seed = sorted.first else { return [] }
        var trend = seed.kg
        var previousDay = seed.day
        var points = [ElanWeightTrendPoint(day: seed.day, kg: trend)]
        for weighIn in sorted.dropFirst() {
            let gap = max(1, ElanDays.elanDaysBetween(previousDay, weighIn.day) ?? 1)
            let alpha = 1 - pow(1 - smoothing, Double(gap))
            trend += alpha * (weighIn.kg - trend)
            points.append(ElanWeightTrendPoint(day: weighIn.day, kg: trend))
            previousDay = weighIn.day
        }
        return points
    }

    /// Kilograms per week between the first trend point inside the last `windowDays` and the last one; nil
    /// when they are under `rateMinimumSpanDays` apart.
    static func ratePerWeek(_ trend: [ElanWeightTrendPoint], windowDays: Int = ElanWeight.rateWindowDays) -> Double? {
        guard let last = trend.last else { return nil }
        let floor = ElanDays.elanDay(last.day, adding: -windowDays)
        guard let first = trend.first(where: { $0.day >= floor }),
              let span = ElanDays.elanDaysBetween(first.day, last.day),
              span >= rateMinimumSpanDays else { return nil }
        return (last.kg - first.kg) / Double(span) * 7
    }

    /// The day the trend meets the target at `ratePerWeekKg`, from `day`; nil when the rate is under the
    /// floor, heads away from the target, or lands beyond `etaHorizonDays`.
    static func etaDay(trendKg: Double, targetKg: Double, ratePerWeekKg: Double, from day: String) -> String? {
        let gap = targetKg - trendKg
        guard abs(ratePerWeekKg) >= rateFloorKgPerWeek, gap != 0, (gap < 0) == (ratePerWeekKg < 0) else { return nil }
        let days = Int((gap / ratePerWeekKg * 7).rounded())
        guard days >= 0, days <= etaHorizonDays else { return nil }
        return ElanDays.elanDay(day, adding: days)
    }

    /// The summary of the stored weigh-ins against the target.
    static func weightSummary(weighIns: [ElanWeighIn], targetKg: Double?) -> ElanWeightSummary {
        let sorted = dedupe(weighIns)
        let trend = weightTrend(sorted)
        let rate = ratePerWeek(trend)
        var eta: String?
        if let last = trend.last, let targetKg, let rate {
            eta = etaDay(trendKg: last.kg, targetKg: targetKg, ratePerWeekKg: rate, from: last.day)
        }
        return ElanWeightSummary(weighIns: sorted, trend: trend, targetKg: targetKg, ratePerWeekKg: rate, etaDay: eta)
    }

    /// What the weigh-in screen says right after a save (fiche: the first weigh-in is the starting point;
    /// a weigh-in above the trend gets the message written in advance; never « +x kg »).
    enum WeighInOutcome: Equatable {
        /// The very first weigh-in: no comparison at all.
        case startingPoint
        /// Not enough weigh-ins for a trend yet: « 2 / 5 ».
        case buildingTrend(count: Int, needed: Int)
        /// Noted, the trend goes on.
        case noted
        /// Noted, above the trend as it stood before this weigh-in: the water message.
        case notedHigher
    }

    /// The outcome of saving `saved` over the weigh-ins stored `before` it (a same-day weigh-in replaces).
    static func weighInOutcome(before: [ElanWeighIn], saved: ElanWeighIn) -> WeighInOutcome {
        let previous = dedupe(before.filter { $0.day != saved.day })
        let after = dedupe(previous + [saved])
        if after.count == 1 { return .startingPoint }
        let trend = weightTrend(after)
        guard let now = trend.last else { return .buildingTrend(count: after.count, needed: trendMinimumCount) }
        let reference = weightTrend(previous).last?.kg ?? now.kg
        return saved.kg > reference + 0.05 ? .notedHigher : .noted
    }

    /// Weigh-ins on the `lastDays` days ending on `today` (« Pesées 5 / 7 »).
    static func weighInCount(_ weighIns: [ElanWeighIn], lastDays: Int, today: String) -> Int {
        let floor = ElanDays.elanDay(today, adding: -(max(1, lastDays) - 1))
        return dedupe(weighIns).filter { $0.day >= floor && $0.day <= today }.count
    }

    // MARK: Settings

    static func targetKg(_ d: UserDefaults = .standard) -> Double? {
        let v = d.double(forKey: targetKey)
        return kgRange.contains(v) ? v : nil
    }

    static func setTargetKg(_ kg: Double?, _ d: UserDefaults = .standard) {
        if let kg, kgRange.contains(kg) {
            d.set(kg, forKey: targetKey)
        } else {
            d.removeObject(forKey: targetKey)
        }
    }

    /// On by default.
    static func profileFollowsTrend(_ d: UserDefaults = .standard) -> Bool {
        d.object(forKey: profileFollowsKey) as? Bool ?? true
    }

    static func setProfileFollowsTrend(_ on: Bool, _ d: UserDefaults = .standard) {
        d.set(on, forKey: profileFollowsKey)
    }

    /// The profile weight the trend gives, to a tenth, when the switch is on and a trend exists; nil otherwise.
    static func profileWeight(following summary: ElanWeightSummary, enabled: Bool) -> Double? {
        guard enabled, let trend = summary.trendKg else { return nil }
        return (trend * 10).rounded() / 10
    }

    /// « Le profil suit la tendance »: the weight the Coach and the Nutrition goals read follows the trend.
    /// Called after every weigh-in and at Élan's opening; a difference under 50 g is left alone.
    @MainActor
    static func syncProfileWeight(_ summary: ElanWeightSummary, profile: ProfileStore,
                                  defaults: UserDefaults = .standard) {
        guard let kg = profileWeight(following: summary, enabled: profileFollowsTrend(defaults)),
              abs(profile.weightKg - kg) >= 0.05 else { return }
        profile.weightKg = kg
    }
}

// MARK: - Persistence (Repository extension)

extension Repository {

    /// The weigh-ins of the last `days` days, oldest first, one per day.
    func elanWeighIns(days: Int = 4000) async -> [ElanWeighIn] {
        await series(key: ElanWeight.weightKey, source: ElanWeight.weightDeviceId, days: days)
            .map { ElanWeighIn(day: $0.day, kg: $0.value) }
    }

    /// Save (or replace) the day's weigh-in, to a tenth of a kilogram. False when the value is out of range
    /// or the store is not open.
    @discardableResult
    func saveElanWeighIn(day: String, kg: Double) async -> Bool {
        guard ElanWeight.kgRange.contains(kg), let store = await storeHandle() else { return false }
        let rounded = (kg * 10).rounded() / 10
        let changed = try? await store.upsertMetricSeries(
            [MetricPoint(day: day, key: ElanWeight.weightKey, value: rounded)],
            deviceId: ElanWeight.weightDeviceId)
        return changed != nil
    }

    /// Remove the day's weigh-in.
    func deleteElanWeighIn(day: String) async {
        guard let store = await storeHandle() else { return }
        _ = try? await store.deleteMetricSeriesPoint(deviceId: ElanWeight.weightDeviceId, day: day,
                                                     key: ElanWeight.weightKey)
    }
}
