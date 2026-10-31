import Foundation
import StrandAnalytics
import WhoopStore

// MARK: - Naps in the Coach's context (personal fork)
//
// The day lines say `rest 7.8h`, which is the MAIN night only (#525): a nap logged in the Sleep tab never
// reached the Coach in any form. This block lists the recent days' naps — when, how long asleep — and the
// credited total (night + naps, the figure the sleep-debt ledger counts), so the Coach can weigh a
// short night against the nap that followed it. Rest and Charge are unchanged: they still score the
// night, as on Android.

enum CoachNapContext {
    /// Days of history the block covers, matching the "Recent days" lines.
    static let windowDays = 14

    /// One nap as the block reports it.
    struct Nap: Equatable {
        /// The local day the nap ended on, `YYYY-MM-DD`.
        let day: String
        let startTs: Int
        let endTs: Int
        /// Minutes actually asleep (decoded stages), or nil for a stage-less block.
        let asleepMin: Double?
    }

    /// Split each day's blocks into its main night and its naps with the SAME selector the Sleep tab and
    /// the analytics rollup use, so a block is a nap here exactly when the Naps card calls it one.
    static func naps(dayGroups: [[CachedSleepSession]], habitualMidsleepSec: Int?,
                     dayKey: (Int) -> String) -> [Nap] {
        var out: [Nap] = []
        for blocks in dayGroups {
            let mainStarts = Set(SleepView.mainNightGroup(blocks, habitualMidsleepSec: habitualMidsleepSec)
                .map(\.startTs))
            for b in blocks where !mainStarts.contains(b.startTs) {
                let asleep = SleepView.decodedAsleepMinutes(b.stagesJSON, effectiveStartTs: b.effectiveStartTs)
                out.append(Nap(day: dayKey(b.endTs), startTs: b.effectiveStartTs, endTs: b.endTs,
                               asleepMin: b.stagesJSON == nil ? nil : asleep))
            }
        }
        return out.sorted { $0.startTs > $1.startTs }
    }

    /// The block, or "" when no day in the window had a nap, so a user who never naps gets no heading.
    /// `mainSleepMinByDay` is `DailyMetric.totalSleepMin` by day, for the credited total.
    static func summary(naps: [Nap], mainSleepMinByDay: [String: Double], zone: TimeZone) -> String {
        guard !naps.isEmpty else { return "" }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = zone
        fmt.dateFormat = "HH:mm"
        var lines = ["NAPS (daytime sleep logged separately from the night; the day lines' rest/sleep is the "
                     + "MAIN NIGHT only, and Charge and Rest score the night — naps are not in them):"]
        let byDay = Dictionary(grouping: naps, by: \.day)
        for day in byDay.keys.sorted(by: >) {
            let dayNaps = (byDay[day] ?? []).sorted { $0.startTs < $1.startTs }
            let items = dayNaps.map { nap -> String in
                let when = fmt.string(from: Date(timeIntervalSince1970: TimeInterval(nap.startTs)))
                    + "–" + fmt.string(from: Date(timeIntervalSince1970: TimeInterval(nap.endTs)))
                let length = nap.asleepMin.map { "\(Int($0.rounded())) min asleep" } ?? "no stages"
                return "\(when) (\(length))"
            }
            let napMin = dayNaps.compactMap(\.asleepMin).reduce(0, +)
            var line = "  \(day): " + items.joined(separator: ", ")
            if let main = mainSleepMinByDay[day] {
                let credited = SleepDebt.creditedSleepMin(mainSleepMin: main, napSleepMin: napMin) ?? main
                line += String(format: "; night %.1fh + naps %.1fh = %.1fh credited",
                               main / 60, napMin / 60, credited / 60)
            } else {
                line += String(format: "; night not scored, naps %.1fh", napMin / 60)
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }
}
