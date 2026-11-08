import SwiftUI
import StrandDesign
import WhoopStore

// MARK: - Élan · Avant / maintenant (personal fork, chantier 10, PR B)
//
// The detail of the comparison: the two windows side by side (sessions, sets, records, Nutrition held, the
// average night), the Historique's minutes per week with the « lancé » weeks under a pale band, « Ce que tu
// as construit », and the one reassuring fact of the page. Every figure is `ElanState.comparison`'s.

struct ElanComparisonView: View {
    let state: ElanState
    let bars: [WorkoutHistoryBar]
    let gains: [ElanLiftGain]
    let unitSystem: UnitSystem
    var animated: Bool = true
    /// Opens the short session (PR C); nil when none is proposed today.
    var onShortSession: (() -> Void)? = nil
    var shortMinutes: Int? = nil

    private var launched: ElanWindow? { state.comparison.launched }
    private var recent: ElanWindow { state.comparison.recent }

    var body: some View {
        ScreenScaffold(title: "Before / now",
                       subtitle: "Your best four weeks of the last six months, beside your last three.") {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                tableCard
                ElanSectionTitle("Minutes per week")
                barsCard
                ElanSectionTitle("What you have built")
                ElanGainsList(gains: gains, unitSystem: unitSystem, showsLastDone: true)
                Text("Estimated one-rep max of the best set, as in Progression (a tap opens it).")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .padding(.horizontal, 4)
                comesBackCard
            }
        }
        .noopEntranceRoot()
    }

    // MARK: The two windows

    private func span(_ window: ElanWindow) -> String {
        ElanFormat.dayLabel(window.startDay) + "–" + ElanFormat.dayLabel(window.endDay)
    }

    private var tableCard: some View {
        NoopCard(padding: 0) {
            VStack(spacing: 0) {
                HStack(alignment: .bottom, spacing: 8) {
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Rolling")
                            .font(StrandFont.footnote.weight(.semibold))
                            .foregroundStyle(StrandPalette.effortColor)
                        Text(verbatim: launched.map(span) ?? "—")
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                    .frame(width: 104, alignment: .trailing)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Last 3 wk")
                            .font(StrandFont.footnote.weight(.semibold))
                            .foregroundStyle(StrandPalette.textSecondary)
                        Text(verbatim: span(recent))
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                    .frame(width: 104, alignment: .trailing)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                row(Text("Sessions / wk"), launched.map { ElanFormat.oneDecimal($0.sessionsPerWeek) },
                    ElanFormat.oneDecimal(recent.sessionsPerWeek))
                row(Text("Sets / wk"), launched.map { String(Int($0.setsPerWeek.rounded())) },
                    String(Int(recent.setsPerWeek.rounded())))
                row(Text("Records"), launched.map { String($0.records) }, String(recent.records))
                row(Text("Nutrition held"), launched.map(nutrition), nutrition(recent))
                row(Text("Average night"), launched?.averageNightMinutes.map { ElanFormat.duration($0) } ?? (launched == nil ? nil : "—"),
                    recent.averageNightMinutes.map { ElanFormat.duration($0) } ?? "—", last: true)
                if launched == nil {
                    Text("No four weeks with enough sessions in the last six months yet: this column fills itself when they come.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 14)
                }
            }
        }
    }

    private func nutrition(_ window: ElanWindow) -> String {
        guard window.nutritionLogged > 0 else { return "—" }
        return String(localized: "\(window.nutritionHeld) d / \(window.nutritionLogged)")
    }

    private func row(_ label: Text, _ a: String?, _ b: String, last: Bool = false) -> some View {
        HStack(spacing: 8) {
            label
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textPrimary)
            Spacer()
            Text(verbatim: a ?? "—")
                .font(StrandFont.rounded(17))
                .foregroundStyle(a == nil ? StrandPalette.textTertiary : StrandPalette.textPrimary)
                .frame(width: 104, alignment: .trailing)
            Text(verbatim: b)
                .font(StrandFont.rounded(17, weight: .regular))
                .foregroundStyle(StrandPalette.textSecondary)
                .frame(width: 104, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 48)
        .overlay(alignment: .top) {
            Rectangle().fill(StrandPalette.hairline).frame(height: NoopMetrics.hairlineWidth)
                .padding(.horizontal, 18)
        }
    }

    // MARK: Minutes per week

    private var barsCard: some View {
        NoopCard(padding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                ElanWeeksBars(bars: bars, launched: launched.map { (start: $0.startDay, end: $0.endDay) },
                              height: 120, animated: animated, launchKey: "elan.comparison.bars")
                if let first = bars.first, let last = bars.last {
                    HStack {
                        Text(verbatim: ElanFormat.dayLabel(TrainingCalendar.trainingDayKey(first.start, calendar: .current)))
                        Spacer()
                        Text(verbatim: ElanFormat.dayLabel(TrainingCalendar.trainingDayKey(last.start, calendar: .current)))
                    }
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                }
                HStack(spacing: 14) {
                    legend(Text("Lifting"), color: StrandPalette.effortColor)
                    legend(Text("Cardio activities"), color: StrandPalette.metricRose)
                    legend(Text("Others"), color: StrandPalette.metricCyan)
                    legend(Text("when you were rolling"), color: StrandPalette.effortColor.opacity(0.25))
                }
                Text("Same bars and same colours as the sessions' History.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
        }
    }

    private func legend(_ label: Text, color: Color) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3, style: .continuous).fill(color).frame(width: 10, height: 10)
            label
        }
        .font(StrandFont.caption)
        .foregroundStyle(StrandPalette.textSecondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    // MARK: Ce qui revient vite

    private var comesBackCard: some View {
        NoopCard(padding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                ElanSandLabel(text: Text("What comes back fast"))
                Text("A few quieter weeks cost little strength, and it comes back faster than the first time.")
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let onShortSession {
                    if let shortMinutes, shortMinutes > 0 {
                        ElanActionButton(title: Text("Short session · \(shortMinutes) min"), look: .primary,
                                         action: onShortSession)
                            .padding(.top, 4)
                    } else {
                        ElanActionButton(title: Text("Short session"), look: .primary, action: onShortSession)
                            .padding(.top, 4)
                    }
                }
            }
        }
    }
}
