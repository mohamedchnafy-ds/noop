import Foundation
#if os(iOS)
import CoreLocation
import CoreMotion
#endif

// MARK: - The continuous place tracking (personal fork, chantier 14 step 2)

/// Keeps where the wearer goes while « Lieux » is on: iOS visits (`CLVisit`, a stay and its place),
/// significant location changes (about 500 m, also what relaunches NOOP after it was swiped away), and,
/// in the Équilibré / Précis modes, standard location updates thinned to one point per interval or per
/// distance (`PlaceTrackingRules.keepsFix`). Each point also gets the iPhone's steps since the previous
/// point, read from the pedometer's history (iOS keeps 7 days).
///
/// Nothing is sent: everything goes through `PlaceLog` into the on-device database. Fail-safe: no
/// permission, a Mac, or location services off, and it records nothing.
///
/// `@MainActor`: the manager is created on the main thread, so CoreLocation calls the delegate there.
@MainActor
final class PlaceTracker: NSObject, ObservableObject {

    static let shared = PlaceTracker()

    /// Where the location permission stands, as the settings screen states it.
    enum Permission: Equatable {
        case notAsked, always, whileUsing, denied, unavailable
    }

    @Published private(set) var permission: Permission = .unavailable
    /// True while some tracking runs (visits at least).
    @Published private(set) var isRunning = false

    private weak var repo: Repository?
    private var log: ((String) -> Void)?
    private var last: (tsMs: Int64, lat: Double, lon: Double)?
    private var lastLoaded = false

    #if os(iOS)
    private let manager = CLLocationManager()
    private let pedometer = CMPedometer()
    private var standardRunning = false
    private var backgroundSession: CLBackgroundActivitySession?
    #endif

    private override init() {
        super.init()
        #if os(iOS)
        manager.delegate = self
        permission = Self.permission(of: manager.authorizationStatus)
        #endif
    }

    /// Wire the tracker to the app at launch (also a relaunch by iOS for a location event, which is why
    /// this runs from the app's init), then start what the settings ask for.
    func attach(repo: Repository, log: @escaping (String) -> Void) {
        self.repo = repo
        self.log = log
        applyPlaceSettings()
        Task { await retainPlaceData() }
    }

    /// Ask for « Always » (the settings screen's Activer button). iOS first offers « While using »; the
    /// upgrade to « Always » is asked by iOS itself later, or from the Settings app.
    func requestAlwaysPermission() {
        #if os(iOS)
        manager.requestAlwaysAuthorization()
        #endif
    }

    /// Start, stop or retune the tracking from the current settings. Called when a setting changes, when
    /// the app comes to the foreground and after every location event.
    func applyPlaceSettings(now: Date = Date()) {
        #if os(iOS)
        let defaults = UserDefaults.standard
        // The permission already reads « denied » when location services are off for the whole phone.
        guard PlaceTrackingSettings.isEnabled(defaults),
              permission == .always || permission == .whileUsing else {
            stopEverything()
            return
        }
        if !isRunning {
            manager.startMonitoringVisits()
            manager.startMonitoringSignificantLocationChanges()
            isRunning = true
            log?("places: tracking on, mode \(PlaceTrackingSettings.mode(defaults).rawValue)")
        }
        let mode = PlaceTrackingSettings.mode(defaults)
        let quiet = PlaceTrackingRules.isQuietTime(now, night: PlaceTrackingSettings.quietAtNight(defaults),
                                                   ranges: PlaceTrackingSettings.quietRanges(defaults))
        guard mode != .eco, !quiet else {
            stopStandardUpdates()
            return
        }
        if mode == .precise {
            manager.desiredAccuracy = kCLLocationAccuracyBest
            manager.distanceFilter = Double(PlaceTrackingSettings.distanceMeters(defaults)) * 0.9
        } else {
            manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
            manager.distanceFilter = kCLDistanceFilterNone
        }
        manager.activityType = .other
        manager.pausesLocationUpdatesAutomatically = PlaceTrackingSettings.pausesWhenStill(defaults)
        if permission == .always {
            manager.allowsBackgroundLocationUpdates = true
            manager.showsBackgroundLocationIndicator = true
        }
        if !standardRunning {
            // iOS 17: keeps the updates flowing while NOOP is in the background.
            if permission == .always, backgroundSession == nil {
                backgroundSession = CLBackgroundActivitySession()
            }
            manager.startUpdatingLocation()
            standardRunning = true
        }
        #endif
    }

    #if os(iOS)
    private func stopStandardUpdates() {
        guard standardRunning else { return }
        manager.stopUpdatingLocation()
        standardRunning = false
        backgroundSession?.invalidate()
        backgroundSession = nil
    }

    private func stopEverything() {
        stopStandardUpdates()
        guard isRunning else { return }
        manager.stopMonitoringVisits()
        manager.stopMonitoringSignificantLocationChanges()
        isRunning = false
        log?("places: tracking off")
    }

    private static func permission(of status: CLAuthorizationStatus) -> Permission {
        switch status {
        case .notDetermined: return .notAsked
        case .authorizedAlways: return .always
        case .authorizedWhenInUse: return .whileUsing
        case .denied, .restricted: return .denied
        @unknown default: return .denied
        }
    }

    /// Keep one fix as a point if the rules say so, with the phone's steps since the previous point.
    private func considerFix(_ location: CLLocation) {
        guard let repo, PlaceTrackingSettings.isEnabled(),
              PlaceTrackingRules.isUsableAccuracy(location.horizontalAccuracy) else { return }
        let defaults = UserDefaults.standard
        let date = location.timestamp
        if PlaceTrackingRules.isQuietTime(date, night: PlaceTrackingSettings.quietAtNight(defaults),
                                          ranges: PlaceTrackingSettings.quietRanges(defaults)) { return }
        let tsMs = Int64((date.timeIntervalSince1970 * 1000).rounded())
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        guard PlaceTrackingRules.keepsFix(mode: PlaceTrackingSettings.mode(defaults),
                                          intervalMinutes: PlaceTrackingSettings.intervalMinutes(defaults),
                                          distanceMeters: PlaceTrackingSettings.distanceMeters(defaults),
                                          lastTsMs: last?.tsMs, lastLat: last?.lat, lastLon: last?.lon,
                                          tsMs: tsMs, lat: lat, lon: lon) else { return }
        let previous = last
        last = (tsMs, lat, lon)
        let accuracy = location.horizontalAccuracy
        stepsSince(previous.map { Date(timeIntervalSince1970: Double($0.tsMs) / 1000) }, to: date) { steps in
            Task { @MainActor in
                guard let store = await repo.storeHandle() else { return }
                await PlaceLog.recordPoint(store, lat: lat, lon: lon, accuracyM: accuracy, at: date, steps: steps)
            }
        }
    }

    /// The pedometer's steps between `from` and `to`, or nil (no previous point, no pedometer, refused).
    private func stepsSince(_ from: Date?, to: Date, done: @escaping (Int?) -> Void) {
        guard let from, from < to, CMPedometer.isStepCountingAvailable(),
              CMPedometer.authorizationStatus() != .denied, CMPedometer.authorizationStatus() != .restricted,
              to.timeIntervalSince(from) < 7 * 86_400 else {
            done(nil)
            return
        }
        pedometer.queryPedometerData(from: from, to: to) { data, error in
            done(error == nil ? data?.numberOfSteps.intValue : nil)
        }
    }
    #endif

    /// Load the last stored point once, so the first fix after a launch is judged against it.
    private func loadLastPoint() async {
        guard !lastLoaded, let repo, let store = await repo.storeHandle() else { return }
        lastLoaded = true
        if last == nil, let row = await PlaceLog.lastPoint(store) {
            last = (row.ts, row.lat, row.lon)
        }
    }

    /// Apply the « Garder » settings now (after one of them changed).
    func applyRetentionNow() {
        Task { await retainPlaceData() }
    }

    /// Apply the « Garder » settings.
    private func retainPlaceData() async {
        await loadLastPoint()
        guard let repo, let store = await repo.storeHandle() else { return }
        await PlaceLog.applyRetention(store, pointDays: PlaceTrackingSettings.keepPointsDays(),
                                      visitDays: PlaceTrackingSettings.keepVisitsDays())
    }
}

#if os(iOS)
// MARK: - CLLocationManagerDelegate
//
// The manager is created on main, so CoreLocation calls back on the main thread; `@preconcurrency` lets
// this `@MainActor` type satisfy the nonisolated requirements (the `GpsWorkoutRecorder` idiom).

extension PlaceTracker: @preconcurrency CLLocationManagerDelegate {

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let next = Self.permission(of: manager.authorizationStatus)
        if next != permission {
            log?("places: location permission \(next)")
            permission = next
        }
        applyPlaceSettings()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            await loadLastPoint()
            for location in locations.sorted(by: { $0.timestamp < $1.timestamp }) { considerFix(location) }
            // A significant change also lands here: it is the wake-up that restarts the finer updates
            // after a pause, a quiet span or a relaunch.
            applyPlaceSettings()
        }
    }

    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        guard let repo, PlaceTrackingSettings.isEnabled(), visit.horizontalAccuracy >= 0 else { return }
        let arrival = visit.arrivalDate == .distantPast ? nil : visit.arrivalDate
        let departure = visit.departureDate == .distantFuture ? nil : visit.departureDate
        let lat = visit.coordinate.latitude
        let lon = visit.coordinate.longitude
        let accuracy = visit.horizontalAccuracy
        Task { @MainActor in
            guard let store = await repo.storeHandle() else { return }
            await PlaceLog.recordVisit(store, lat: lat, lon: lon, accuracyM: accuracy, arrival: arrival,
                                       departure: departure)
            applyPlaceSettings()
        }
    }

    func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
        // « Pause à l'arrêt »: iOS stopped the updates while still. Visits and significant changes keep
        // running and bring them back at the next move.
        standardRunning = false
    }

    func locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager) {
        standardRunning = true
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // A transient failure (no fix yet) heals by itself; a refusal arrives through the permission.
    }
}
#endif
