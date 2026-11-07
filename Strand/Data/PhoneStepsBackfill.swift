import Foundation
import WhoopStore

// MARK: - The iPhone's daily steps, kept before iOS forgets them (personal fork, 7 Nov.)
//
// The iPhone's pedometer keeps only about seven days of history, and a sideloaded NOOP cannot read
// Apple Health (a free signing identity carries no HealthKit entitlement). So the history of phone steps
// is lost unless something copies it while it is still there. Each time the app comes to the foreground
// (at most once an hour), the daily totals of the last seven calendar days are read from the pedometer
// and written where the Apple Health import writes them: `appleDaily.steps` under the `apple-health`
// source, which is what the steps estimate's calibration and the step read-outs already read. The past
// before these seven days comes from a one-off Apple Health export (.zip) import.
//
// The upsert replaces the whole row of a day, so the other columns an import wrote (active energy,
// VO2 max, weight…) are carried over, and a day already holding more steps (Apple Health counts the
// Watch too) is left alone. Nothing leaves the device.
enum PhoneStepsBackfill {
    /// Days read back, today included: what the pedometer keeps.
    static let daysBack = 7
    static let lastRunKey = "noop.phoneStepsBackfill.lastRunSec"
    static let minimumIntervalSec = 3600

    /// One calendar day of the pedometer: its `yyyy-MM-dd` key and its span (today ends now).
    struct PhoneStepDay: Equatable {
        let day: String
        let start: Date
        let end: Date
    }

    /// The last `days` calendar days, newest first.
    static func phoneStepDayWindows(now: Date, calendar: Calendar, days: Int = daysBack) -> [PhoneStepDay] {
        let today = calendar.startOfDay(for: now)
        return (0..<days).compactMap { back in
            guard let start = calendar.date(byAdding: .day, value: -back, to: today) else { return nil }
            let next = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
            return PhoneStepDay(day: phoneStepDayKey(start, calendar: calendar), start: start, end: min(next, now))
        }
    }

    /// `yyyy-MM-dd` in the calendar's own time zone, the key the Apple Health import uses.
    static func phoneStepDayKey(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// The rows to write: one per day the phone counted steps on, carrying the day's other imported
    /// values, skipped when the day already holds at least as many steps.
    static func mergedPhoneStepRows(existing: [AppleDaily], phone: [String: Int]) -> [AppleDaily] {
        let byDay = Dictionary(existing.map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first })
        return phone.keys.sorted().compactMap { day in
            guard let steps = phone[day], steps > 0 else { return nil }
            guard let row = byDay[day] else {
                return AppleDaily(day: day, steps: steps, activeKcal: nil, basalKcal: nil, vo2max: nil,
                                  avgHr: nil, maxHr: nil, walkingHr: nil, weightKg: nil)
            }
            if let kept = row.steps, kept >= steps { return nil }
            return AppleDaily(day: day, steps: steps, activeKcal: row.activeKcal, basalKcal: row.basalKcal,
                              vo2max: row.vo2max, avgHr: row.avgHr, maxHr: row.maxHr,
                              walkingHr: row.walkingHr, weightKg: row.weightKg)
        }
    }

    /// Copy the pedometer's last seven days into the store. iPhone only; at most once an hour.
    @MainActor
    static func runPhoneStepsBackfill(repo: Repository, now: Date = Date(),
                                      defaults: UserDefaults = .standard) async {
        #if os(iOS)
        let nowSec = Int(now.timeIntervalSince1970)
        guard nowSec - defaults.integer(forKey: lastRunKey) >= minimumIntervalSec else { return }
        defaults.set(nowSec, forKey: lastRunKey)
        let windows = phoneStepDayWindows(now: now, calendar: .current)
        var phone: [String: Int] = [:]
        for window in windows {
            if let steps = await WorkoutPedometer.steps(fromSec: Int(window.start.timeIntervalSince1970),
                                                        toSec: Int(window.end.timeIntervalSince1970)) {
                phone[window.day] = steps
            }
        }
        guard !phone.isEmpty, let newest = windows.first?.day, let oldest = windows.last?.day,
              let store = await repo.storeHandle() else { return }
        let existing = (try? await store.appleDaily(deviceId: Repository.appleHealthSource,
                                                    from: oldest, to: newest)) ?? []
        let rows = mergedPhoneStepRows(existing: existing, phone: phone)
        guard !rows.isEmpty else { return }
        _ = try? await store.upsertAppleDaily(rows, deviceId: Repository.appleHealthSource)
        await repo.refresh()
        #endif
    }
}
