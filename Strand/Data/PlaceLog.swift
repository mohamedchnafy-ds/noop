import Foundation
import WhoopStore

// Personal fork, chantier 14 step 2: the app's access to the positions, places and visits
// (`PlaceStore` in WhoopStore, migration v54-places).
//
// The place tracker writes through here and the Map screens and the Coach read through here, so a
// visit is matched to a place by the same rule wherever it comes from. Nothing here touches the
// interface or CoreLocation: the tracker hands in plain coordinates and dates.

/// How an iOS visit becomes a place and a stay. PURE: no store, no clock read, so the rules are tested
/// on their own (`PlaceLogTests`).
enum PlaceVisitPlan {

    /// Radius of a new place, metres: about a building and its surroundings, the precision iOS gives a
    /// visit (the "zone d'environ 150 m" of the screens).
    static let newPlaceRadiusM = 150.0

    /// Two reports of the same stay carry the same arrival; iOS may round it differently between the
    /// arrival and the departure report, so arrivals this close are the same stay.
    static let sameArrivalToleranceSec = 120

    /// What one iOS visit changes: maybe a new place, and the stays to write.
    struct Outcome: Equatable {
        var newPlace: PlaceRow?
        var visits: [PlaceVisitRow]
    }

    /// The place a position falls in: the nearest place whose zone contains it, or nil.
    static func matchingPlace(lat: Double, lon: Double, in places: [PlaceRow]) -> PlaceRow? {
        var best: (place: PlaceRow, distance: Double)?
        for place in places {
            let distance = RouteMath.haversineMeters(.init(lat, lon), .init(place.lat, place.lon))
            guard distance <= max(place.radiusM, newPlaceRadiusM) else { continue }
            if best == nil || distance < best!.distance { best = (place, distance) }
        }
        return best?.place
    }

    /// Plan one iOS visit. `arrival` / `departure` are nil when iOS does not know them (its
    /// `distantPast` / `distantFuture`). `open` are the stays still going. `makeId` names a new row.
    ///
    /// - An arrival with no departure opens a stay at the matching place (a new place if none); any
    ///   other stay still going is closed at that arrival (its departure was missed).
    /// - A departure closes the stay that has the same arrival, else the stay still going at the same
    ///   place, else writes the whole stay when the arrival is known. A departure with neither changes
    ///   nothing.
    static func planVisit(lat: Double, lon: Double, accuracyM: Double, arrival: Date?, departure: Date?,
                          places: [PlaceRow], open: [PlaceVisitRow], now: Date,
                          makeId: () -> String) -> Outcome {
        let arrivedAt = arrival.map { Int($0.timeIntervalSince1970) }
        let departedAt = departure.map { Int($0.timeIntervalSince1970) }
        let accuracy = max(accuracyM, 0)
        let matched = matchingPlace(lat: lat, lon: lon, in: places)

        if let departedAt {
            // The stay this departure ends: the same arrival first (wherever iOS put its centre), else
            // the stay still going at the same place.
            let byArrival = arrivedAt.flatMap { known in
                open.first(where: { abs($0.arrivedAt - known) <= sameArrivalToleranceSec })
            }
            let byPlace = matched.flatMap { place in open.first(where: { $0.placeId == place.id }) }
            if var stay = byArrival ?? byPlace {
                stay.departedAt = max(departedAt, stay.arrivedAt)
                return Outcome(newPlace: nil, visits: [stay])
            }
            guard let arrivedAt else { return Outcome(newPlace: nil, visits: []) }
            let (place, created) = placeFor(matched, lat: lat, lon: lon, now: now, makeId: makeId)
            let stay = PlaceVisitRow(id: makeId(), placeId: place.id, arrivedAt: arrivedAt,
                                     departedAt: max(departedAt, arrivedAt), lat: lat, lon: lon,
                                     accuracyM: accuracy)
            return Outcome(newPlace: created, visits: [stay])
        }

        guard let arrivedAt else { return Outcome(newPlace: nil, visits: []) }
        let (place, created) = placeFor(matched, lat: lat, lon: lon, now: now, makeId: makeId)
        if open.contains(where: { $0.placeId == place.id
                                  && abs($0.arrivedAt - arrivedAt) <= sameArrivalToleranceSec }) {
            return Outcome(newPlace: nil, visits: [])   // the same arrival reported twice
        }
        var visits: [PlaceVisitRow] = []
        for var stay in open where stay.arrivedAt <= arrivedAt {
            stay.departedAt = arrivedAt                  // its departure was missed
            visits.append(stay)
        }
        visits.append(PlaceVisitRow(id: makeId(), placeId: place.id, arrivedAt: arrivedAt, departedAt: nil,
                                    lat: lat, lon: lon, accuracyM: accuracy))
        return Outcome(newPlace: created, visits: visits)
    }

    /// The matched place, or a new one centred on the visit (returned as `created`).
    private static func placeFor(_ matched: PlaceRow?, lat: Double, lon: Double, now: Date,
                                 makeId: () -> String) -> (place: PlaceRow, created: PlaceRow?) {
        if let matched { return (matched, nil) }
        let created = PlaceRow(id: makeId(), lat: lat, lon: lon, radiusM: newPlaceRadiusM,
                               createdAt: Int(now.timeIntervalSince1970))
        return (created, created)
    }
}

enum PlaceLog {

    /// UserDefaults counter bumped after every write, so the Map and the settings reload when the
    /// tracker records something in the background.
    static let revisionKey = "places.revision"

    @MainActor
    private static func bumpPlaceRevision() {
        let defaults = UserDefaults.standard
        defaults.set(defaults.integer(forKey: revisionKey) &+ 1, forKey: revisionKey)
    }

    // MARK: Points

    /// Store one point of the continuous tracking. `steps`: the iPhone's steps since the previous point.
    static func recordPoint(_ store: WhoopStore, lat: Double, lon: Double, accuracyM: Double, at date: Date,
                            steps: Int?) async {
        let row = LocationPointRow(ts: Int64((date.timeIntervalSince1970 * 1000).rounded()), lat: lat, lon: lon,
                                   accuracyM: max(accuracyM, 0), steps: steps.map { max($0, 0) })
        try? await store.insertLocationPoint(row)
        await bumpPlaceRevision()
    }

    /// The points from `from` (included) to `to` (excluded), oldest first.
    static func points(_ store: WhoopStore, from: Date, to: Date) async -> [LocationPointRow] {
        (try? await store.locationPointsBetween(fromMs: Int64(from.timeIntervalSince1970 * 1000),
                                                toMs: Int64(to.timeIntervalSince1970 * 1000))) ?? []
    }

    /// The most recent point, or nil.
    static func lastPoint(_ store: WhoopStore) async -> LocationPointRow? {
        try? await store.latestLocationPoint()
    }

    /// How many points were stored since `since`.
    static func pointCount(_ store: WhoopStore, since: Date) async -> Int {
        (try? await store.countLocationPoints(fromMs: Int64(since.timeIntervalSince1970 * 1000))) ?? 0
    }

    /// Delete every point.
    static func erasePoints(_ store: WhoopStore) async {
        try? await store.eraseLocationPoints()
        await bumpPlaceRevision()
    }

    // MARK: Places and visits

    /// Every place, oldest first.
    static func places(_ store: WhoopStore) async -> [PlaceRow] {
        (try? await store.allPlaces()) ?? []
    }

    /// The stays that overlap `[from, to)`, in the order of arrival.
    static func visits(_ store: WhoopStore, from: Date, to: Date) async -> [PlaceVisitRow] {
        (try? await store.placeVisitsBetween(fromSec: Int(from.timeIntervalSince1970),
                                             toSec: Int(to.timeIntervalSince1970))) ?? []
    }

    /// Record one iOS visit (see `PlaceVisitPlan.planVisit`).
    static func recordVisit(_ store: WhoopStore, lat: Double, lon: Double, accuracyM: Double, arrival: Date?,
                            departure: Date?, now: Date = Date()) async {
        let places = await places(store)
        let horizon = now.addingTimeInterval(-30 * 86_400)
        let open = await visits(store, from: horizon, to: now.addingTimeInterval(86_400))
            .filter { $0.departedAt == nil }
        let outcome = PlaceVisitPlan.planVisit(lat: lat, lon: lon, accuracyM: accuracyM, arrival: arrival,
                                               departure: departure, places: places, open: open, now: now,
                                               makeId: { UUID().uuidString })
        if let place = outcome.newPlace { try? await store.upsertPlace(place) }
        for visit in outcome.visits { try? await store.upsertPlaceVisit(visit) }
        await bumpPlaceRevision()
    }

    /// Give a place a name; a blank name clears it.
    static func renameKnownPlace(_ store: WhoopStore, id: String, name: String) async {
        try? await store.renamePlace(id: id, name: name)
        await bumpPlaceRevision()
    }

    /// Forget a place and its stays.
    static func forgetKnownPlace(_ store: WhoopStore, id: String) async {
        try? await store.forgetPlace(id: id)
        await bumpPlaceRevision()
    }

    /// Delete every place and every stay.
    static func eraseAllPlaces(_ store: WhoopStore) async {
        try? await store.erasePlaces()
        await bumpPlaceRevision()
    }

    /// Keep `keepDays` of points and of stays (the "Garder" settings).
    static func applyRetention(_ store: WhoopStore, pointDays: Int, visitDays: Int, now: Date = Date()) async {
        let pointCut = now.addingTimeInterval(-Double(max(pointDays, 1)) * 86_400)
        let visitCut = now.addingTimeInterval(-Double(max(visitDays, 1)) * 86_400)
        try? await store.pruneLocationPoints(beforeMs: Int64(pointCut.timeIntervalSince1970 * 1000))
        try? await store.prunePlaceVisits(beforeSec: Int(visitCut.timeIntervalSince1970))
    }
}
