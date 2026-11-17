import Foundation
import Security

// Personal fork, chantier 25 — the Fajr times of Masjid At-Tawba (Bagnols-sur-Cèze).
//
// Two sources, in this order: the mosque's own yearly timetable from MAWAQIT, fetched once a day with the
// wearer's API token and cached on the phone; otherwise a calculation on the phone (sun 15° below the horizon,
// the angle MAWAQIT uses for France). Measured against the mosque's 2026 timetable, the calculation lands 3 to
// 5 minutes BEFORE the mosque's adhan, so an alarm built on it is still never after the adhan.
//
// The MAWAQIT API is not public: its official library says it is reserved for MAWAQIT's own apps, and the
// access token belongs to a MAWAQIT account. The token is therefore never in the code: the wearer pastes it in
// the Alarms screen (Keychain), and without it nothing is sent anywhere. Only the mosque's id goes out, never a
// position, a time or a health value. A deliberate gap with upstream's offline-only scope (personal fork, as
// Open Food Facts).

/// The mosque's yearly timetable as MAWAQIT returns it.
struct MawaqitTimetable: Codable, Equatable {
    var uuid: String
    var name: String
    var timezone: String
    /// One entry per month, January first; each maps its days ("1"…) to the day's times, as "HH:MM": Fajr,
    /// Shuruq, Dhuhr, Asr, Maghrib, Isha, or seven times with Imsak first for mosques that display it.
    var calendar: [[String: [String]]]
    var fetchedAt: Date
    /// The year the timetable was fetched in, the year its calendar describes.
    var year: Int
}

enum Mawaqit {
    /// Masjid At-Tawba, Bagnols-sur-Cèze, on mawaqit.net/fr/m/masjid-tawba. A public id, not a secret.
    static let mosqueUUID = "0a9b8cab-baed-4cf6-8b23-af1d4e24e4c0"
    static let mosqueName = "Masjid At-Tawba · Bagnols-sur-Cèze"
    static let latitude = 44.160745801385
    static let longitude = 4.6188346061516
    static let timeZoneId = "Europe/Paris"
    /// The API the official MAWAQIT library calls, header `Api-Access-Token`.
    static let baseURL = "https://mawaqit.net/api/2.0"
    /// A timetable older than this is fetched again (the daily refresh).
    static let refreshAge: TimeInterval = 20 * 3600

    static var mosqueTimeZone: TimeZone { TimeZone(identifier: timeZoneId) ?? .current }

    /// The calendar the timetable's days are read in: Gregorian, in the mosque's zone.
    static func mosqueCalendar(_ zone: TimeZone = mosqueTimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    /// Reads a `/mosque/{uuid}/prayer-times` response, nil unless it carries a 12-month calendar.
    static func parsePrayerTimes(_ data: Data, fetchedAt: Date) -> MawaqitTimetable? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let months = root["calendar"] as? [Any], months.count == 12 else { return nil }
        var calendar: [[String: [String]]] = []
        for month in months {
            guard let days = month as? [String: Any] else { return nil }
            var parsed: [String: [String]] = [:]
            for (day, times) in days {
                guard let list = times as? [Any] else { continue }
                parsed[day] = list.compactMap { $0 as? String }
            }
            calendar.append(parsed)
        }
        let zoneId = (root["timezone"] as? String).flatMap { TimeZone(identifier: $0) != nil ? $0 : nil } ?? timeZoneId
        let year = mosqueCalendar(TimeZone(identifier: zoneId) ?? mosqueTimeZone).component(.year, from: fetchedAt)
        return MawaqitTimetable(uuid: root["uuid"] as? String ?? mosqueUUID,
                                name: root["name"] as? String ?? mosqueName,
                                timezone: zoneId, calendar: calendar, fetchedAt: fetchedAt, year: year)
    }

    /// The day's Fajr as written in the timetable: the first time, or the second (Sabah) when the mosque
    /// displays Imsak first.
    static func fajrText(_ timetable: MawaqitTimetable, month: Int, day: Int) -> String? {
        guard (1...12).contains(month), let times = timetable.calendar[month - 1][String(day)] else { return nil }
        if times.count >= 7 { return times[1] }
        return times.first
    }

    /// "HH:MM" as hour and minute, nil for anything else (a time typed wrong by the mosque is no time).
    static func fajrClock(_ text: String) -> (hour: Int, minute: Int)? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return (hour, minute)
    }

    /// The adhan of Fajr on the mosque's day holding `day`, from the timetable, nil when the timetable is of
    /// another year or has no usable time that day.
    static func fajrAdhan(on day: Date, timetable: MawaqitTimetable) -> Date? {
        let calendar = mosqueCalendar(TimeZone(identifier: timetable.timezone) ?? mosqueTimeZone)
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        guard let year = parts.year, let month = parts.month, let dayOfMonth = parts.day, year == timetable.year,
              let text = fajrText(timetable, month: month, day: dayOfMonth),
              let time = fajrClock(text) else { return nil }
        return calendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth,
                                                  hour: time.hour, minute: time.minute))
    }

    /// Whether the cached timetable is due for its daily fetch.
    static func needsRefresh(_ cached: MawaqitTimetable?, now: Date) -> Bool {
        guard let cached else { return true }
        if mosqueCalendar().component(.year, from: now) != cached.year { return true }
        return now.timeIntervalSince(cached.fetchedAt) >= refreshAge || now < cached.fetchedAt
    }
}

/// Fajr calculated on the phone: the sun `angle` degrees below the horizon before sunrise.
///
/// The usual low-precision solar position (about a minute of accuracy at mid latitudes), enough for an alarm
/// whose promise is "before the adhan". Pure.
enum FajrCalculator {
    static let franceAngle = 15.0

    static func fajr(on day: Date, latitude: Double = Mawaqit.latitude, longitude: Double = Mawaqit.longitude,
                     angle: Double = franceAngle, timeZone: TimeZone = Mawaqit.mosqueTimeZone) -> Date? {
        let local = Mawaqit.mosqueCalendar(timeZone)
        let parts = local.dateComponents([.year, .month, .day], from: day)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0)!
        guard let year = parts.year, let month = parts.month, let date = parts.day,
              let midnight = utc.date(from: DateComponents(year: year, month: month, day: date)),
              let epoch = utc.date(from: DateComponents(year: 2000, month: 1, day: 1, hour: 12)) else { return nil }
        func positive(_ value: Double, _ modulus: Double) -> Double {
            let r = value.truncatingRemainder(dividingBy: modulus)
            return r < 0 ? r + modulus : r
        }
        let rad = Double.pi / 180
        let d = midnight.addingTimeInterval(12 * 3600).timeIntervalSince(epoch) / 86400
        let g = positive(357.529 + 0.98560028 * d, 360) * rad
        let q = positive(280.459 + 0.98564736 * d, 360)
        let l = positive(q + 1.915 * sin(g) + 0.020 * sin(2 * g), 360) * rad
        let e = (23.439 - 0.00000036 * d) * rad
        let ra = positive(atan2(cos(e) * sin(l), cos(l)) / rad / 15, 24)
        let declination = asin(sin(e) * sin(l))
        let equation = positive(q / 15 - ra + 12, 24) - 12
        let noon = 12 - longitude / 15 - equation
        let phi = latitude * rad
        let cosH = (-sin(angle * rad) - sin(phi) * sin(declination)) / (cos(phi) * cos(declination))
        guard (-1...1).contains(cosH) else { return nil }
        let hours = noon - acos(cosH) / rad / 15
        return midnight.addingTimeInterval(hours * 3600)
    }
}

/// Where a Fajr time came from, for the screen and the Coach.
enum FajrSource: Equatable {
    case mosque(fetchedAt: Date)
    case calculated
}

/// The cached timetable on disk and the funnel every reader asks for an adhan.
enum FajrTimes {
    private static var memo: MawaqitTimetable??

    private static var fileURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        return base.appendingPathComponent("Fajr", isDirectory: true).appendingPathComponent("mawaqit-timetable.json")
    }

    /// The cached timetable, nil before the first successful fetch.
    static func cachedTimetable() -> MawaqitTimetable? {
        if let memo { return memo }
        let loaded = fileURL.flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode(MawaqitTimetable.self, from: $0) }
        memo = .some(loaded)
        return loaded
    }

    static func saveTimetable(_ timetable: MawaqitTimetable) {
        guard let url = fileURL, let data = try? JSONEncoder().encode(timetable) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
        memo = .some(timetable)
    }

    static func clearTimetable() {
        if let url = fileURL { try? FileManager.default.removeItem(at: url) }
        memo = .some(nil)
    }

    /// The adhan of Fajr on the day holding `day` and where it came from: the mosque's timetable when the cache
    /// covers that day, else the calculation.
    static func adhan(on day: Date, timetable: MawaqitTimetable?) -> (time: Date, source: FajrSource)? {
        if let timetable, let time = Mawaqit.fajrAdhan(on: day, timetable: timetable) {
            return (time, .mosque(fetchedAt: timetable.fetchedAt))
        }
        guard let time = FajrCalculator.fajr(on: day) else { return nil }
        return (time, .calculated)
    }

    /// `adhan(on:timetable:)` with the cached timetable.
    static func adhan(on day: Date) -> (time: Date, source: FajrSource)? {
        adhan(on: day, timetable: cachedTimetable())
    }
}

/// The wearer's MAWAQIT token, in the Keychain only.
enum MawaqitTokenStore {
    private static let service = "com.noop.mawaqit"
    private static let account = "api-token"

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    /// Stores (or replaces) the token; empty input clears it. False if the Keychain refused the write.
    @discardableResult
    static func save(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { clear(); return true }
        guard let data = trimmed.data(using: .utf8) else { return false }
        SecItemDelete(baseQuery as CFDictionary)
        var attrs = baseQuery
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(attrs as CFDictionary, nil) == errSecSuccess
    }

    static func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, let token = String(data: data, encoding: .utf8), !token.isEmpty
        else { return nil }
        return token
    }

    static var hasToken: Bool { read() != nil }

    static func clear() { SecItemDelete(baseQuery as CFDictionary) }
}

/// The daily fetch of the mosque's timetable.
enum MawaqitClient {
    /// How the last fetch went, shown under the Fajr card.
    enum Outcome: String {
        case ok
        case unauthorized
        case network
        case invalid
    }

    static let statusKey = "alarm.fajr.mawaqitStatus"
    static let statusAtKey = "alarm.fajr.mawaqitStatusAt"

    private static var inFlight = false
    static let retryAfter: TimeInterval = 3600

    /// The last fetch's outcome and when, nil before any.
    static func lastOutcome(_ defaults: UserDefaults = .standard) -> (outcome: Outcome, at: Date)? {
        guard let raw = defaults.string(forKey: statusKey), let outcome = Outcome(rawValue: raw) else { return nil }
        return (outcome, Date(timeIntervalSince1970: defaults.double(forKey: statusAtKey)))
    }

    /// The outcome of an HTTP status and body, pure.
    static func outcome(status: Int, data: Data, now: Date) -> (MawaqitTimetable?, Outcome) {
        switch status {
        case 200:
            guard let timetable = Mawaqit.parsePrayerTimes(data, fetchedAt: now) else { return (nil, .invalid) }
            return (timetable, .ok)
        case 401, 403:
            return (nil, .unauthorized)
        default:
            return (nil, .network)
        }
    }

    /// Fetches the timetable when a token is set and the cache is due. True when a new timetable was saved.
    /// Main actor, so two callers (the foreground, a strap reconnect) cannot both pass `inFlight`.
    @MainActor
    @discardableResult
    static func refreshIfNeeded(now: Date = Date(), force: Bool = false,
                                log: ((String) -> Void)? = nil) async -> Bool {
        guard let token = MawaqitTokenStore.read(), !inFlight else { return false }
        guard force || Mawaqit.needsRefresh(FajrTimes.cachedTimetable(), now: now) else { return false }
        // A refused token or a dead network is tried again an hour later, not on every re-arm.
        if !force, let last = lastOutcome(), last.outcome != .ok, now.timeIntervalSince(last.at) < retryAfter {
            return false
        }
        guard let url = URL(string: "\(Mawaqit.baseURL)/mosque/\(Mawaqit.mosqueUUID)/prayer-times") else { return false }
        inFlight = true
        defer { inFlight = false }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(token, forHTTPHeaderField: "Api-Access-Token")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let result: (MawaqitTimetable?, Outcome)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            result = outcome(status: (response as? HTTPURLResponse)?.statusCode ?? 0, data: data, now: now)
        } catch {
            result = (nil, .network)
        }
        UserDefaults.standard.set(result.1.rawValue, forKey: statusKey)
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: statusAtKey)
        guard let timetable = result.0 else {
            log?("Fajr: MAWAQIT timetable not updated (\(result.1.rawValue)); the cached or calculated times stay in use")
            return false
        }
        FajrTimes.saveTimetable(timetable)
        log?("Fajr: MAWAQIT timetable updated for \(timetable.year)")
        return true
    }
}
