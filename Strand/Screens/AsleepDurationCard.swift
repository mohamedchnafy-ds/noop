import SwiftUI
import StrandDesign
import WhoopStore

// MARK: - Asleep duration trend (#today-hosted-cards)
//
// The Sleep tab's "Asleep duration" card, extracted into a standalone view so it can ALSO be hosted in
// the Today tab. Both the Sleep tab and the Today host render THIS view from the SAME `AsleepDurationData`,
// so the number can never diverge between the two surfaces (the parity contract). The card body is a
// verbatim lift of the former `SleepView.durationTrend`; the data builder is a verbatim lift of
// `SleepView.durationTrendPoints` + `typicalTotalMin`.

/// Pure inputs for the asleep-duration card: trailing-30-night sleep hours + the typical mean minutes.
/// Built identically by the Sleep tab and by a Today host so the two never diverge.
struct AsleepDurationData {
    let points: [TrendPoint]
    let typicalTotalMin: Double?
    /// The need the bars are drawn against: the Sleep tab's one need (`SleepModel.debtNeedMin`).
    var needMin: Double? = nil

    /// yyyy-MM-dd → Date (en_US_POSIX, UTC) — matches `SleepView.dayParser`.
    private static let dayParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Trailing 30 days of total sleep in HOURS, falling back to all nights with data when the trailing
    /// window is too sparse (verbatim of `SleepView.durationTrendPoints`). `typicalTotalMin` is the mean
    /// asleep minutes across nights with data (verbatim of `SleepView.typicalTotalMin`).
    static func build(days: [DailyMetric]) -> AsleepDurationData {
        func mk(_ slice: ArraySlice<DailyMetric>) -> [TrendPoint] {
            slice.compactMap { d -> TrendPoint? in
                guard let mins = d.totalSleepMin, mins > 0,
                      let date = dayParser.date(from: d.day) else { return nil }
                return TrendPoint(date: date, value: mins / 60.0)
            }
        }
        let recent = mk(days.suffix(30))
        let points = recent.count >= 2 ? recent : mk(days[...])
        let totals = days.compactMap { $0.totalSleepMin }.filter { $0 > 0 }
        let typical = totals.isEmpty ? nil : totals.reduce(0, +) / Double(totals.count)
        return AsleepDurationData(points: points, typicalTotalMin: typical, needMin: SleepModel.debtNeedMin(days: days))
    }
}

/// The "Asleep duration" trend card. Personal fork: the same bars as the Sleep tab's "Your nights" card
/// over 30 days (one slot per day, the need as a dashed line), with plain durations.
struct AsleepDurationCard: View {
    let data: AsleepDurationData

    var body: some View {
        let pts = data.points
        let nights = SleepNightsData(debtMinutes: 0, isDebt: false, needMinutes: data.needMin ?? 480,
                                     lastShortfallMinutes: nil, recent: [],
                                     month: pts.map { SleepNightsData.Night(day: SleepNightsData.dayKey($0.date),
                                                                             minutes: $0.value * 60) })
        let slots = nights.slots(30, from: nights.month)
        let values = pts.map { $0.value * 60 }
        NoopCard(tint: StrandPalette.restColor) {
            VStack(alignment: .leading, spacing: NoopMetrics.cardInnerSpacing) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Hours asleep").strandOverline()
                    Spacer(minLength: NoopMetrics.space2)
                    Text("Per night, trailing 30 days")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
                if pts.count >= 2 {
                    SleepNightsBars(slots: slots.map { $0.minutes }, needMinutes: nights.needMinutes)
                        .frame(height: 132)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text("Hours asleep trend"))
                    HStack {
                        Text(slots.first.map { SleepModel.shortDayLabel($0.day) } ?? "")
                        Spacer()
                        Text(slots.last.map { SleepModel.shortDayLabel($0.day) } ?? "")
                    }
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .accessibilityHidden(true)
                    Divider().overlay(StrandPalette.hairline)
                    HStack(alignment: .top) {
                        stat(String(localized: "Average"), data.typicalTotalMin.map(SleepDurationText.format) ?? "—")
                        stat(String(localized: "Min"), values.min().map(SleepDurationText.format) ?? "—")
                        stat(String(localized: "Max"), values.max().map(SleepDurationText.format) ?? "—")
                        stat(String(localized: "Nights"), "\(pts.count)")
                    }
                } else {
                    Text("Not enough nights yet.")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 60, alignment: .center)
                }
            }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            Text(value).font(StrandFont.number(15)).foregroundStyle(StrandPalette.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
