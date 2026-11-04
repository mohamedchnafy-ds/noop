import Foundation
import WhoopStore
import StrandAnalytics

// MARK: - The points of a Coach chart, read on the device (personal fork, chantier 9)
//
// What a `CoachChartSpec` draws, read where its screen reads it: a catalogue metric through
// `Repository.exploreSeries` (Analyses' reader, so the card and Analyses › agree), a day's heart rate
// through the Today card's 5-minute buckets, a day's stress through `StressDayCurve` (the Today Stress
// card). The same read answers `show_chart` (the figures the model comments on) and draws the card.

extension AICoachEngine {

    /// The points of a chart, oldest first: the metric's (or the day's), and the second metric's of a pair.
    /// Empty without "Use my data", or when nothing was measured.
    func chartPoints(_ spec: CoachChartSpec, now: Date = Date()) async -> (first: [CoachChartPoint], second: [CoachChartPoint]) {
        guard dataConsent else { return ([], []) }
        let calendar = Calendar.current
        switch spec.kind {
        case .day:
            guard let dayStart = CoachChart.dayDate(spec.day, calendar: calendar) else { return ([], []) }
            if spec.series == .stress {
                let scored = await StressDayCurve.day(repo: repo, dayStart: dayStart, now: now,
                                                      personalBaseline: PuffinExperiment.stressPersonalBaselineEnabled)
                let points = (scored?.result.hours ?? []).compactMap { hour -> CoachChartPoint? in
                    guard let level = hour.level else { return nil }
                    return CoachChartPoint(date: Date(timeIntervalSince1970: TimeInterval(hour.startTs)), value: level)
                }
                return (points, [])
            }
            let from = Int(dayStart.timeIntervalSince1970)
            let next = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
            let to = calendar.isDate(dayStart, inSameDayAs: now) ? Int(now.timeIntervalSince1970)
                : Int(next.timeIntervalSince1970)
            let buckets = await repo.hrBuckets(from: from, to: to, bucketSeconds: 300)
            return (buckets.map { CoachChartPoint(date: Date(timeIntervalSince1970: TimeInterval($0.ts)), value: $0.bpm) }, [])
        case .line, .bars, .pair:
            let window = CoachChart.windowDays(endingOn: spec.day, days: spec.days ?? 30, calendar: calendar)
            guard let start = window.first.flatMap({ CoachChart.dayDate($0, calendar: calendar) }) else { return ([], []) }
            // How far back the reader looks: from the window's first day to now, plus a day of margin.
            let lookback = max(1, (calendar.dateComponents([.day], from: start, to: now).day ?? 0) + 2)
            func read(_ id: String?) async -> [CoachChartPoint] {
                guard let descriptor = CoachChart.descriptor(id) else { return [] }
                let values = await repo.exploreSeries(key: descriptor.key, source: descriptor.source, days: lookback)
                return CoachChart.dailyPoints(values, window: window, calendar: calendar)
            }
            let first = await read(spec.metric)
            guard spec.kind == .pair else { return (first, []) }
            let second = await read(spec.second)
            return (first, second)
        }
    }
}
