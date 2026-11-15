import SwiftUI
import StrandDesign

// The Regularity tab of the Progression screen (fork chantier 18, lot B; no mockup, the style of maquette 2):
// three figures (this week, the weeks in a row, the average per week), the working sets of each of the last
// 12 weeks as bars, and the same weeks as a calendar, one dot per day a session was done.

struct LiftProgressRegularityTab: View {
    let data: LiftProgressData

    private var calendar: Calendar { .current }

    var body: some View {
        let now = Date(timeIntervalSince1970: TimeInterval(data.now > 0 ? data.now : Int(Date().timeIntervalSince1970)))
        let weeks = LiftRegularity.liftRegularityWeeks(data.sessions, now: now, calendar: calendar)
        return VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
            if data.isEmpty {
                NoopCard {
                    Text("Regularity appears after your first session: sets per week and the days you trained, over 12 weeks.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                figures(weeks)
                setsCard(weeks)
                calendarCard(weeks)
            }
        }
    }

    private func figures(_ weeks: [LiftRegularity.Week]) -> some View {
        let average = LiftRegularity.liftAverageSessions(weeks)
        return HStack(spacing: NoopMetrics.rowSpacing) {
            figure("\(weeks.last?.sessions ?? 0)", Text("this week"))
            figure("\(LiftRegularity.liftWeekStreak(weeks))", Text("weeks in a row"))
            figure(UnitFormatter.decimal(average, places: 1), Text("per week on average"))
        }
    }

    private func figure(_ value: String, _ label: Text) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.spaceHalf) {
            Text(verbatim: value)
                .font(StrandFont.number(24, weight: .bold))
                .foregroundStyle(StrandPalette.textPrimary)
            label
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(NoopMetrics.space3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NoopPanelSurface())
    }

    private func setsCard(_ weeks: [LiftRegularity.Week]) -> some View {
        let values = weeks.map { Double($0.workingSets) }
        let past = values.dropLast()
        let reference = past.isEmpty ? 0 : past.reduce(0, +) / Double(past.count)
        return NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Working sets per week")
                        .font(StrandFont.headline)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Spacer(minLength: NoopMetrics.space2)
                    Text(String(localized: "\(weeks.last?.workingSets ?? 0) this week"))
                        .font(StrandFont.captionNumber)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
                LiftWeeklyBars(values: values, reference: reference)
                    .frame(height: 96)
                    .accessibilityHidden(true)
                HStack {
                    Text(String(localized: "\(LiftRegularity.weeks) weeks ago"))
                    Spacer(minLength: NoopMetrics.space2)
                    Text("this week")
                }
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
                Text("The line is your average of the weeks before this one.")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
        }
    }

    private func calendarCard(_ weeks: [LiftRegularity.Week]) -> some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                Text("Days trained")
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                HStack(spacing: NoopMetrics.space1) {
                    ForEach(Array(TrainingText.narrowWeekdays(calendar).enumerated()), id: \.offset) { _, day in
                        Text(verbatim: day)
                            .font(StrandFont.caption2)
                            .foregroundStyle(StrandPalette.textTertiary)
                            .frame(maxWidth: .infinity)
                    }
                }
                VStack(spacing: NoopMetrics.space1) {
                    ForEach(weeks.indices, id: \.self) { index in
                        HStack(spacing: NoopMetrics.space1) {
                            ForEach(0..<7, id: \.self) { day in
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(weeks[index].days[day] ? StrandPalette.effortColor : StrandPalette.surfaceInset)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 14)
                            }
                        }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(String(localized: "\(weeks.reduce(0) { $0 + $1.sessions }) sessions in \(LiftRegularity.weeks) weeks")))
            }
        }
    }
}
