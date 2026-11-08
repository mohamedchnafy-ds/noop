import SwiftUI
import StrandDesign

// MARK: - Élan · Semaine (personal fork, chantier 10, PR B)
//
// The recap tab: « Jamais deux fois de suite » the day after a missed session, « Mon pourquoi », « Cette
// semaine » and the Victoires. Every figure comes from `ElanState` and `ElanVictories`, resolved once by
// `ElanResolver`; the tab only words them. The alert card's primary action opens the short session
// (`ElanShortSessionSheet`, PR C) when the screen could build one, and « Pas aujourd'hui » folds the card.

struct ElanWeekTabView: View {
    let state: ElanState
    let victories: ElanVictories?
    let unitSystem: UnitSystem
    /// Bumped at each showing of the tab, so its entrances replay (chantier 12 rule).
    var showing: Int = 0
    var animated: Bool = true
    let onEditWhy: () -> Void
    let onDismissShort: () -> Void
    /// Nil hides the short-session action (the short plan could not be built).
    var onShortSession: (() -> Void)? = nil
    var onWithdrawShort: (() -> Void)? = nil
    /// The short session's length, for its button (« Séance courte · 20 min »); nil until built.
    var shortMinutes: Int? = nil

    private var key: String { "elan.week.\(showing)" }

    var body: some View {
        VStack(alignment: .leading, spacing: NoopVisualStyle.itemGap) {
            if let missed = state.missedYesterday {
                alertCard(missed)
            }
            whyCard
            weekCard
            ElanSectionTitle("Victories")
                .padding(.top, 4)
            victoriesCard
        }
    }

    // MARK: Jamais deux fois de suite

    @ViewBuilder
    private func alertCard(_ missed: ElanMissedSession) -> some View {
        if state.shortSessionAccepted != nil {
            NoopCard(padding: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        iconBadge("checkmark")
                        VStack(alignment: .leading, spacing: 3) {
                            ElanSandLabel(text: Text("Added to today"))
                            Text("\(state.shortTarget?.name ?? missed.name) · short version · tonight")
                                .font(StrandFont.headline)
                                .foregroundStyle(StrandPalette.textPrimary)
                            Text("Done tonight, it counts in your week.")
                                .font(StrandFont.subhead)
                                .foregroundStyle(StrandPalette.textSecondary)
                        }
                    }
                    if let onWithdrawShort {
                        ElanActionButton(title: Text("Withdraw"), look: .secondary, action: onWithdrawShort)
                    }
                }
            }
        } else if state.shortSessionDismissed {
            NoopCard(padding: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "flame")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(StrandPalette.textSecondary)
                    Text("Not today. Élan proposes nothing more before tomorrow.")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            NoopCard(padding: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 12) {
                        iconBadge("flame.fill")
                        VStack(alignment: .leading, spacing: 3) {
                            ElanSandLabel(text: Text("Never two in a row"))
                            Text("\(missed.name) was yesterday")
                                .font(StrandFont.headline)
                                .foregroundStyle(StrandPalette.textPrimary)
                            Text("Twenty minutes tonight are enough to keep the rhythm.")
                                .font(StrandFont.subhead)
                                .foregroundStyle(StrandPalette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    HStack(spacing: 8) {
                        if let onShortSession {
                            if let shortMinutes, shortMinutes > 0 {
                                ElanActionButton(title: Text("Short session · \(shortMinutes) min"), look: .primary,
                                                 action: onShortSession)
                                    .layoutPriority(1)
                            } else {
                                ElanActionButton(title: Text("Short session"), look: .primary, action: onShortSession)
                                    .layoutPriority(1)
                            }
                        }
                        ElanActionButton(title: Text("Not today"), look: .secondary, action: onDismissShort)
                    }
                }
            }
        }
    }

    private func iconBadge(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(StrandPalette.elanSand)
            .frame(width: 38, height: 38)
            .background(StrandPalette.elanSand.opacity(0.18), in: Circle())
            .accessibilityHidden(true)
    }

    // MARK: Mon pourquoi

    private var whyCard: some View {
        Button(action: onEditWhy) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("My why")
                        .font(StrandFont.footnote.weight(.semibold))
                        .foregroundStyle(StrandPalette.textSecondary)
                    Spacer()
                    Text("Edit")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.accent)
                }
                if let why = state.why {
                    Text(verbatim: why)
                        .font(StrandFont.title2)
                        .foregroundStyle(StrandPalette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(6)
                } else {
                    Text("Your own words, written on a day you felt motivated. Élan shows them back on the days without.")
                        .font(StrandFont.body)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(StrandPalette.surfaceRaised,
                        in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(LiquidPressStyle())
        .accessibilityHint(Text("Opens the editor"))
    }

    // MARK: Cette semaine

    private var weekCard: some View {
        NoopCard(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("This week")
                        .font(StrandFont.headline)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Spacer()
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        NoopRollingNumber(value: Double(state.week.done), format: { String(Int($0.rounded())) },
                                          font: StrandFont.rounded(17), color: StrandPalette.textPrimary,
                                          entrance: .slam, armed: animated, launchKey: key + ".done")
                        if state.week.planned > 0 {
                            Text("/ \(state.week.planned) sessions")
                                .font(StrandFont.subhead)
                                .foregroundStyle(StrandPalette.textSecondary)
                        } else {
                            Text("sessions")
                                .font(StrandFont.subhead)
                                .foregroundStyle(StrandPalette.textSecondary)
                        }
                    }
                }
                ElanWeekRow(days: state.week.days, animated: animated, launchKey: key + ".marks")
                Rectangle().fill(StrandPalette.hairline).frame(height: NoopMetrics.hairlineWidth)
                HStack(alignment: .top, spacing: 10) {
                    figure(title: Text("Nutrition held"), value: nutritionValue, unit: state.week.nutritionLoggedDays > 0 ? Text("/ \(state.week.nutritionLoggedDays) d") : nil)
                    figure(title: Text("Average night"), value: state.week.averageNightMinutes.map { ElanFormat.duration($0) }, unit: nil)
                    figure(title: Text("Weigh-ins"), value: String(state.week.weighIns), unit: Text("/ 7"))
                }
            }
        }
    }

    private var nutritionValue: String? {
        state.week.nutritionLoggedDays > 0 ? String(state.week.nutritionHeldDays) : nil
    }

    private func figure(title: Text, value: String?, unit: Text?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            title
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(verbatim: value ?? "—")
                    .font(StrandFont.rounded(17))
                    .foregroundStyle(StrandPalette.textPrimary)
                if value != nil, let unit {
                    unit
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Victoires

    private var victoryLines: [(title: String, detail: String)] {
        guard let victories else { return [] }
        var lines: [(title: String, detail: String)] = []
        if victories.recentRecords > 0 {
            lines.append((title: String(localized: "\(victories.recentRecords) records in the last 30 days"),
                          detail: String(localized: "heavier than ever, or more reps at a load you know")))
        }
        if let streak = victories.planStreak {
            lines.append((title: String(localized: "\(streak.weeks) weeks in a row on the plan"),
                          detail: String(localized: "every planned session done")))
        }
        if let gain = victories.bestGain {
            lines.append((title: gain.name + " : " + ElanFormat.signedWeight(gain.gainKg, system: unitSystem)
                            + " " + String(localized: "in \(gain.weeks) weeks"),
                          detail: String(localized: "estimated one-rep max, as in Progression")))
        }
        return lines
    }

    @ViewBuilder
    private var victoriesCard: some View {
        let lines = victoryLines
        NoopCard(padding: 0) {
            if lines.isEmpty {
                Text("Your victories will show here: a record, weeks kept to the plan, a load that went up.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(16)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        HStack(spacing: 12) {
                            Image(systemName: "trophy")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(StrandPalette.elanSand)
                                .frame(width: 24)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: line.title)
                                    .font(StrandFont.body)
                                    .foregroundStyle(StrandPalette.textPrimary)
                                Text(verbatim: line.detail)
                                    .font(StrandFont.footnote)
                                    .foregroundStyle(StrandPalette.textSecondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(minHeight: 60)
                            .overlay(alignment: .bottom) {
                                if index < lines.count - 1 {
                                    Rectangle().fill(StrandPalette.hairline).frame(height: NoopMetrics.hairlineWidth)
                                }
                            }
                        }
                        .padding(.leading, 16)
                        .padding(.trailing, 16)
                        .staggeredAppear(index: index)
                    }
                }
            }
        }
    }
}
