import Foundation
import StrandAnalytics
import WhoopStore

// What the live heart-rate banner shows beside the bpm (personal fork, chantier 6): the day's Effort, the
// morning's Charge with the night's HRV, or the night's sleep with the debt and the suggested bedtime. The
// wearer picks one in the Live HR screen.
//
// Every figure is resolved by the helpers the Today and Sleep screens read, so the Lock Screen never states
// a number those screens would not: Effort and Charge from the same widget anchor the banner already used
// (#911), the night from Today's Rest-ring rule (`nightSleepMinutes`), the debt and the bedtime from the
// Synthèse's own funnel (`Repository.sleepSynthesisFigures`). Pure, so `StrandTests` covers it.

/// The figure beside the bpm. Kept in UserDefaults on this iPhone (not in `.noopbak`).
enum LiveHRBannerSide: String, CaseIterable, Identifiable {
    case effort, charge, sleep

    var id: String { rawValue }

    static let defaultsKey = "liveActivity.hr.side"

    /// The stored choice; Effort when none was made.
    static func storedSide(_ defaults: UserDefaults = .standard) -> LiveHRBannerSide {
        defaults.string(forKey: defaultsKey).flatMap(LiveHRBannerSide.init(rawValue:)) ?? .effort
    }

    var title: String {
        switch self {
        case .effort: return String(localized: "Effort")
        case .charge: return String(localized: "Charge")
        case .sleep:  return String(localized: "Sleep")
        }
    }

    /// The line under each choice in the Live HR screen.
    var explanation: String {
        switch self {
        case .effort: return String(localized: "The day's Effort, with its bar")
        case .charge: return String(localized: "The morning's recovery and the night's HRV")
        case .sleep:  return String(localized: "The night, the debt and the suggested bedtime")
        }
    }
}

/// The sleep figures the Synthèse states — the 14-night debt ledger with naps credited, the need and the usual
/// wake — and the bedtime they give.
struct SleepSynthesisFigures: Equatable {
    var needMin: Double
    /// Nil until a night counts in the ledger.
    var debtMin: Double?
    var isDebt: Bool
    /// How far the latest night fell short of the need, when it did.
    var lastShortfallMin: Double?
    var usualWakeMin: Int?
    /// The ledger's nights, oldest first, with naps credited: what the Coach's fiche lists night by night.
    var nights: [SleepDebtNight] = []

    /// The usual wake minus the need, as minutes after midnight (`HabitualWake.bedtime`).
    var bedtimeMin: Int? {
        usualWakeMin.map { HabitualWake.bedtime(wakeMinutes: $0, needMinutes: needMin) }
    }

    /// "1h 12m", or "None" under the on-target band: the Synthèse's Sleep debt row. Nil before a night counts.
    var debtText: String? {
        debtMin.map { isDebt ? SleepDurationText.format($0) : String(localized: "None") }
    }
}

extension Repository {
    /// The Synthèse's sleep figures, resolved as Today's Synthèse and the Coach's fiche resolve them. Nil before
    /// any day is banked.
    func sleepSynthesisFigures(now: Date = Date()) async -> SleepSynthesisFigures? {
        let todayKey = today?.day ?? Repository.localDayKey(now)
        let through = days.filter { $0.day <= todayKey }
        guard !through.isEmpty else { return nil }
        let sessions = await allSleepSessions(days: 17)
        let habitual = await habitualMidsleepSec()
        let naps = SleepModel.napSleepMinutesByDay(navDays: SleepModel.navDays(navSessions: sessions),
                                                   habitualMidsleepSec: habitual)
        let ledger = SleepModel.debtLedger(days: through, napSleepMinByDay: naps)
        let nights = SleepNightsData(ledger: ledger, month: [])
        let nowTs = Int(now.timeIntervalSince1970)
        let wakes = sleeps.map(\.endTs).filter { $0 <= nowTs }.sorted()
        return SleepSynthesisFigures(
            needMin: SleepModel.debtNeedMin(days: through),
            debtMin: nights.recent.isEmpty ? nil : nights.debtMinutes,
            isDebt: nights.isDebt,
            lastShortfallMin: nights.lastShortfallMinutes,
            usualWakeMin: HabitualWake.minutes(wakeTimestamps: wakes, zone: .current),
            nights: ledger.nights)
    }
}

/// The banner's side, worded app-side (the widget extension has no catalog).
struct LiveHRBannerSideContent: Equatable {
    var side: LiveHRBannerSide
    var label: String
    /// "38", "72", "6h 48m". Nil reads as the dash.
    var value: String?
    /// "HRV 46 ms", "debt 1h 12m · bedtime 23:10".
    var detail: String?
}

enum LiveHRBannerFigures {
    /// The night's sleep the Today screen's Rest ring names ("3h 41m"): the day's own night, else — when
    /// `carries`, which Today allows on today only — the last night banked, on the Rest score's freshness rule
    /// (`TodayView.isCarryStale`). Nil when there is none to name.
    static func nightSleepMinutes(own: DailyMetric?, days: [DailyMetric], dayKey: String, carries: Bool) -> Double? {
        if let minutes = own?.totalSleepMin, minutes > 0 { return minutes }
        guard carries,
              let carry = days.last(where: { $0.day < dayKey && ($0.totalSleepMin ?? 0) > 0 }),
              !TodayView.isCarryStale(priorDayKey: carry.day, todayKey: dayKey) else { return nil }
        return carry.totalSleepMin
    }

    /// The side as the banner shows it. `day` is the widget anchor (the day the banner's Charge and Effort
    /// already came from), `days` the banked days, `sleep` the Synthèse's figures when they are loaded.
    static func sideContent(_ side: LiveHRBannerSide, day: DailyMetric?, days: [DailyMetric], dayKey: String,
                            effortScale: EffortScale, sleep: SleepSynthesisFigures?) -> LiveHRBannerSideContent {
        switch side {
        case .effort:
            return LiveHRBannerSideContent(side: side, label: side.title,
                                           value: day?.strain.map { UnitFormatter.effortDisplay($0, scale: effortScale) },
                                           detail: nil)
        case .charge:
            let hrv = day?.avgHrv ?? Repository.lastHrvDay(days: days, todayKey: dayKey)?.avgHrv
            return LiveHRBannerSideContent(side: side, label: side.title,
                                           value: day?.recovery.map { "\(Int($0.rounded()))" },
                                           detail: hrv.map { hrvText(Int($0.rounded())) })
        case .sleep:
            let night = nightSleepMinutes(own: day, days: days, dayKey: dayKey, carries: true)
            var parts: [String] = []
            if let debt = sleep?.debtText { parts.append(String(localized: "debt \(debt)")) }
            if let bed = sleep?.bedtimeMin { parts.append(String(localized: "bedtime \(TodaySynthesisLogic.clock(bed))")) }
            return LiveHRBannerSideContent(side: side, label: side.title,
                                           value: night.map { SleepDurationText.format($0) },
                                           detail: parts.isEmpty ? nil : parts.joined(separator: " · "))
        }
    }

    /// "HRV 46 ms" ("VFC 46 ms" in French): the HRV's own name, then its value as every HRV readout writes it.
    static func hrvText(_ ms: Int) -> String {
        String(localized: "HRV") + " " + String(localized: "\(ms) ms")
    }

    /// "Live HR · zone 2", "Live HR · resting zone", or "Live HR" without a reading.
    static func subtitle(zone: Int?) -> String {
        guard let zone else { return String(localized: "Live HR") }
        return zone >= 1 ? String(localized: "Live HR · zone \(zone)") : String(localized: "Live HR · resting zone")
    }
}
