import SwiftUI
import StrandDesign
import WhoopStore

// MARK: - Élan · Progrès (personal fork, chantier 10, PR B)
//
// « Avant / maintenant » in short, the weight trend, « Ce que tu as construit ». The comparison comes from
// `ElanState.comparison`, the trend from `ElanWeightSummary`, the gains from `ElanVictoryRules`; the bars
// are the Historique's (`WorkoutHistoryLogic.historyBars`), so no figure here can disagree with the screen
// that owns it. The headline numbers slam in (effect B); the curve traces itself. The cards push their
// detail as `ElanRoute` values on the stack that holds the screen.

struct ElanProgressTabView: View {
    let state: ElanState
    let bars: [WorkoutHistoryBar]
    let gains: [ElanLiftGain]
    let unitSystem: UnitSystem
    var showing: Int = 0
    var animated: Bool = true
    /// True when today's weigh-in is already logged.
    var weighedToday: Bool = false
    let onWeighIn: () -> Void

    private var key: String { "elan.progress.\(showing)" }

    var body: some View {
        VStack(alignment: .leading, spacing: NoopVisualStyle.itemGap) {
            comparisonCard
            weightCard
            ElanSectionTitle("What you have built")
                .padding(.top, 4)
            ElanGainsList(gains: gains, unitSystem: unitSystem)
            Text("Estimated one-rep max, as in Progression.")
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textSecondary)
                .padding(.horizontal, 4)
        }
    }

    // MARK: Avant / maintenant

    private var comparisonCard: some View {
        NavigationLink(value: ElanRoute.comparison) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Before / now")
                        .font(StrandFont.headline)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Spacer()
                    ElanDetailLink()
                }
                HStack(alignment: .top, spacing: 12) {
                    column(title: Text("When you were rolling"), titleColor: StrandPalette.effortColor,
                           window: state.comparison.launched, numberColor: StrandPalette.textPrimary,
                           slam: true, launchKey: key + ".launched")
                    column(title: Text("These 3 weeks"), titleColor: StrandPalette.textSecondary,
                           window: state.comparison.recent, numberColor: StrandPalette.textSecondary,
                           slam: false, launchKey: key + ".recent")
                }
                if state.comparison.launched == nil {
                    Text("Four weeks of sessions will give the point of comparison.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ElanWeeksBars(bars: bars, launched: launchedSpan, height: 60, animated: animated,
                              launchKey: key + ".bars")
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(StrandPalette.surfaceRaised,
                        in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(LiquidPressStyle())
        .accessibilityHint(Text("Opens the detail"))
    }

    private var launchedSpan: (start: String, end: String)? {
        state.comparison.launched.map { (start: $0.startDay, end: $0.endDay) }
    }

    @ViewBuilder
    private func column(title: Text, titleColor: Color, window: ElanWindow?, numberColor: Color,
                        slam: Bool, launchKey: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            title
                .font(StrandFont.footnote.weight(.semibold))
                .foregroundStyle(titleColor)
            if let window {
                NoopRollingNumber(value: window.sessionsPerWeek, format: { ElanFormat.oneDecimal($0) },
                                  font: StrandFont.rounded(30), color: numberColor,
                                  glow: StrandPalette.effortColor, entrance: slam ? .slam : .count,
                                  armed: animated, launchKey: launchKey)
                Text("sessions / week · \(window.records) records")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
            } else {
                Text(verbatim: "—")
                    .font(StrandFont.rounded(30))
                    .foregroundStyle(StrandPalette.textTertiary)
                Text("not enough history yet")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Poids

    private var weightCard: some View {
        NoopCard(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                NavigationLink(value: ElanRoute.weight) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Weight")
                            .font(StrandFont.headline)
                            .foregroundStyle(StrandPalette.textPrimary)
                        Spacer()
                        ElanDetailLink()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Trend")
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textSecondary)
                        if let trend = state.weight.trendKg {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                NoopRollingNumber(value: LiftFormat.display(fromKilograms: trend, system: unitSystem),
                                                  format: { ElanFormat.oneDecimal($0) },
                                                  font: StrandFont.rounded(30), color: StrandPalette.textPrimary,
                                                  entrance: .slam, armed: animated, launchKey: key + ".weight")
                                Text(verbatim: UnitFormatter.massUnit(unitSystem))
                                    .font(StrandFont.subhead)
                                    .foregroundStyle(StrandPalette.textSecondary)
                            }
                            if let change = state.weight.changeSinceStartKg, let first = state.weight.first {
                                Text("\(ElanFormat.signedWeight(change, system: unitSystem)) since \(ElanFormat.dayLabel(first.day))")
                                    .font(StrandFont.footnote)
                                    .foregroundStyle(StrandPalette.textSecondary)
                            }
                        } else {
                            Text("\(state.weight.count) / \(ElanWeight.trendMinimumCount) weigh-ins")
                                .font(StrandFont.rounded(24))
                                .foregroundStyle(StrandPalette.textPrimary)
                            Text("Your trend appears after five weigh-ins.")
                                .font(StrandFont.footnote)
                                .foregroundStyle(StrandPalette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if state.weight.hasTrend {
                        ElanTrendChart(points: Array(state.weight.trend.suffix(60)), targetKg: nil, system: unitSystem,
                                       height: 50, animated: animated, launchKey: key + ".curve")
                            .frame(width: 130)
                    }
                }
                if weighedToday {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(StrandPalette.intakeColor)
                        Text("Weigh-in logged this morning")
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                    .font(StrandFont.subhead.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                } else {
                    ElanActionButton(title: Text("Log this morning's weigh-in"), look: .secondary, action: onWeighIn)
                }
            }
        }
    }
}

// MARK: - Ce que tu as construit

/// The exercises with their estimate and its move; each row opens Progression.
struct ElanGainsList: View {
    let gains: [ElanLiftGain]
    let unitSystem: UnitSystem
    /// « dernière fois il y a 10 jours » under the name (the detail screen).
    var showsLastDone: Bool = false
    var now: Date = Date()

    var body: some View {
        NoopCard(padding: 0) {
            if gains.isEmpty {
                Text("Your first exercises will show here with their estimated one-rep max and how it moved.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(16)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(gains.enumerated()), id: \.offset) { index, gain in
                        NavigationLink(value: ElanRoute.progression) {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: gain.name)
                                        .font(StrandFont.body)
                                        .foregroundStyle(StrandPalette.textPrimary)
                                        .lineLimit(1)
                                    if showsLastDone {
                                        Text("last time \(ElanFormat.daysAgo(gain.lastTs, now: now))")
                                            .font(StrandFont.footnote)
                                            .foregroundStyle(StrandPalette.textSecondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(verbatim: LiftFormat.weight(gain.nowKg, system: unitSystem))
                                        .font(StrandFont.rounded(17))
                                        .foregroundStyle(StrandPalette.textPrimary)
                                    Text("\(ElanFormat.signedWeight(gain.gainKg, system: unitSystem)) in \(gain.weeks) weeks")
                                        .font(StrandFont.footnote)
                                        .foregroundStyle(gain.gainKg > 0 ? StrandPalette.accent : StrandPalette.textSecondary)
                                }
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(StrandPalette.textTertiary)
                                    .accessibilityHidden(true)
                            }
                            .padding(.horizontal, 16)
                            .frame(minHeight: 60)
                            .overlay(alignment: .bottom) {
                                if index < gains.count - 1 {
                                    Rectangle().fill(StrandPalette.hairline).frame(height: NoopMetrics.hairlineWidth)
                                        .padding(.leading, 16)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .staggeredAppear(index: index)
                    }
                }
            }
        }
    }
}
