import SwiftUI
import StrandDesign

// MARK: - Today synthesis (personal fork)
//
// Three numbered lines, always open: the sleep debt (the Sleep tab's own ledger), today's session from the
// Lift Log rotation, and the suggested bedtime (the usual wake time minus the sleep need). Pure: the rows
// arrive resolved, so the render test draws the real card.

struct TodaySynthesisRow: Identifiable {
    var id: String
    var symbol: String
    var tint: Color
    var title: String
    var subtitle: String?
    var value: String
    var route: TabRoute?
    /// A call to action shown in blue in place of the value (the session row's « Start »); the value then
    /// moves to the front of the subtitle. Nil for the other rows, and for the widget, which reads the
    /// fields itself.
    var action: String? = nil
}

struct TodaySynthesisCard: View {
    var rows: [TodaySynthesisRow]
    var surfaceOpacity: Double = 1

    var body: some View {
        // Fork chantier 7: one list card, no section head (as in the retained design).
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 {
                    Rectangle().fill(StrandPalette.hairline).frame(height: NoopMetrics.hairlineWidth)
                }
                link(row)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, NoopMetrics.space1)
        .frame(maxWidth: .infinity)
        .background(NoopPanelSurface(cornerRadius: NoopMetrics.cardRadius, surfaceOpacity: surfaceOpacity))
    }

    @ViewBuilder
    private func link(_ row: TodaySynthesisRow) -> some View {
        if let route = row.route {
            TabRouteLink(route: route) { rowBody(row, linked: true) }
                .buttonStyle(LiquidPressStyle())
        } else {
            rowBody(row, linked: false)
        }
    }

    private func rowBody(_ row: TodaySynthesisRow, linked: Bool) -> some View {
        HStack(spacing: 12) {
            // The icon alone, in its colour (no tinted disc behind it).
            Image(systemName: row.symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(row.tint)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(StrandFont.body.weight(.medium))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .lineLimit(1)
                if let subtitle = TodaySynthesisCard.shownSubtitle(row) {
                    Text(subtitle)
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            Spacer(minLength: NoopMetrics.space2)
            if let action = row.action {
                Text(action)
                    .font(StrandFont.body.weight(.semibold))
                    .foregroundStyle(StrandPalette.accent)
                    .lineLimit(1)
            } else {
                Text(row.value)
                    .font(StrandFont.rounded(17, weight: .semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            if linked && row.action == nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(StrandPalette.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 60)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

extension TodaySynthesisCard {
    /// The grey line under the title: with an action, the value leads it (« Full body A · ≈ 48 min »).
    static func shownSubtitle(_ row: TodaySynthesisRow) -> String? {
        guard row.action != nil else { return row.subtitle }
        return [row.value, row.subtitle].compactMap { $0 }.joined(separator: " · ")
    }
}

/// Builds the three rows from already-loaded inputs (no store, no clock), so tests pin the copy rules.
enum TodaySynthesisLogic {
    struct Session: Equatable {
        enum State: Equatable {
            case next
            case running
            case done(minutes: Int?)
            /// The week plan (personal fork, Training) has no session today.
            case rest
        }

        var name: String
        var state: State
        var supersets: Int
        var singles: Int
        var typicalMinutes: Int?
        /// Planned cardio (fork chantier 8, lot 4): its target length in minutes; nil for a Lift Log session.
        var cardioMinutes: Int? = nil
        /// The day's other planned items still to do, already worded ("Running · 30 min").
        var alsoPlanned: [String] = []

        var isCardio: Bool { cardioMinutes != nil }
    }

    static func debtRow(_ data: SleepNightsData?) -> TodaySynthesisRow {
        var value = String(localized: "no data")
        var subtitle: String?
        if let data, !(data.recent.isEmpty && data.month.isEmpty) {
            value = data.isDebt ? SleepDurationText.format(data.debtMinutes) : String(localized: "None")
            if let short = data.lastShortfallMinutes, short >= 1 {
                subtitle = String(localized: "you were \(SleepDurationText.format(short)) short last night")
            } else {
                subtitle = String(localized: "your \(SleepDurationText.format(data.needMinutes)) need was met last night")
            }
        }
        return TodaySynthesisRow(id: "debt", symbol: "moon.fill", tint: StrandPalette.sleepDebt,
                                 title: String(localized: "Sleep debt"), subtitle: subtitle, value: value,
                                 route: .sleep)
    }

    static func sessionRow(_ session: Session?, route: TabRoute?) -> TodaySynthesisRow {
        guard let session else {
            return TodaySynthesisRow(id: "session", symbol: "dumbbell.fill", tint: StrandPalette.effortColor,
                                     title: String(localized: "Today's session"), subtitle: nil,
                                     value: String(localized: "no data"), route: route)
        }
        let subtitle: String
        switch session.state {
        case .running:
            subtitle = String(localized: "in progress")
        case .done(let minutes):
            subtitle = minutes.map { String(localized: "done · \($0) min") } ?? String(localized: "done")
        case .rest:
            subtitle = String(localized: "rest day in your plan")
        case .next where session.isCardio:
            subtitle = String(localized: "\(session.cardioMinutes ?? 0) min")
        case .next:
            var parts: [String] = []
            if session.supersets > 0 {
                parts.append(session.supersets == 1 ? String(localized: "1 superset")
                                                    : String(localized: "\(session.supersets) supersets"))
            }
            if session.singles > 0 {
                parts.append(session.singles == 1 ? String(localized: "1 exercise")
                                                  : String(localized: "\(session.singles) exercises"))
            }
            var line = parts.joined(separator: " + ")
            if let m = session.typicalMinutes {
                let length = String(localized: "≈ \(m) min")
                line = line.isEmpty ? length : line + " · " + length
            }
            subtitle = line
        }
        // The day's other items still to do follow, as « + Running · 30 min » (fork chantier 8, lot 4).
        let line = ([subtitle] + session.alsoPlanned.map { "+ " + $0 }).filter { !$0.isEmpty }
            .joined(separator: " · ")
        var row = TodaySynthesisRow(id: "session", symbol: session.isCardio ? "figure.run" : "dumbbell.fill",
                                    tint: session.isCardio ? StrandPalette.metricRose : StrandPalette.effortColor,
                                    title: String(localized: "Today's session"),
                                    subtitle: line.isEmpty ? nil : line, value: session.name, route: route)
        // A session still to do offers « Start » in blue, as in the retained design (fork chantier 7).
        if session.state == .next { row.action = String(localized: "Start") }
        return row
    }

    static func bedtimeRow(wakeMinutes: Int?, needMinutes: Double, format: (Int) -> String) -> TodaySynthesisRow {
        guard let wake = wakeMinutes else {
            return TodaySynthesisRow(id: "bedtime", symbol: "bed.double.fill", tint: StrandPalette.restColor,
                                     title: String(localized: "Suggested bedtime"), subtitle: nil,
                                     value: String(localized: "no data"), route: .sleep)
        }
        let bed = HabitualWake.bedtime(wakeMinutes: wake, needMinutes: needMinutes)
        return TodaySynthesisRow(
            id: "bedtime", symbol: "bed.double.fill", tint: StrandPalette.restColor,
            title: String(localized: "Suggested bedtime"),
            subtitle: String(localized: "\(SleepDurationText.format(needMinutes)) before your usual wake-up at \(format(wake))"),
            value: format(bed), route: .sleep)
    }

    /// "HH:MM" (or the 12-hour form) for minutes after midnight, through the app's clock preference.
    static func clock(_ minutes: Int) -> String {
        let day = Calendar.current.startOfDay(for: Date())
        let date = day.addingTimeInterval(TimeInterval(minutes * 60))
        return AppClock.hourMinuteFormatter().string(from: date)
    }
}
