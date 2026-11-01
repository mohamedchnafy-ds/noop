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
}

struct TodaySynthesisCard: View {
    var rows: [TodaySynthesisRow]
    var surfaceOpacity: Double = 1

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("SYNTHESIS").font(StrandFont.overline).tracking(1.6)
                    .foregroundStyle(StrandPalette.textTertiary)
                Spacer()
            }
            .padding(.horizontal, 2)
            .padding(.top, 4)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        Rectangle().fill(StrandPalette.hairline).frame(height: NoopMetrics.hairlineWidth)
                    }
                    link(row)
                }
            }
            .padding(.horizontal, NoopMetrics.space4)
            .padding(.vertical, NoopMetrics.space1)
            .frame(maxWidth: .infinity)
            .background(NoopPanelSurface(cornerRadius: 22, surfaceOpacity: surfaceOpacity))
        }
    }

    @ViewBuilder
    private func link(_ row: TodaySynthesisRow) -> some View {
        if let route = row.route {
            NavigationLink(value: route) { rowBody(row, linked: true) }
                .buttonStyle(LiquidPressStyle())
        } else {
            rowBody(row, linked: false)
        }
    }

    private func rowBody(_ row: TodaySynthesisRow, linked: Bool) -> some View {
        HStack(spacing: 14) {
            Image(systemName: row.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(row.tint)
                .frame(width: 34, height: 34)
                .background(row.tint.opacity(0.16), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .lineLimit(1)
                if let subtitle = row.subtitle {
                    Text(subtitle)
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            Spacer(minLength: NoopMetrics.space2)
            Text(row.value)
                .font(StrandFont.number(16))
                .foregroundStyle(StrandPalette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if linked {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(StrandPalette.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 64)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Builds the three rows from already-loaded inputs (no store, no clock), so tests pin the copy rules.
enum TodaySynthesisLogic {
    struct Session: Equatable {
        enum State: Equatable {
            case next
            case running
            case done(minutes: Int?)
        }

        var name: String
        var state: State
        var supersets: Int
        var singles: Int
        var typicalMinutes: Int?
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
        return TodaySynthesisRow(id: "debt", symbol: "moon.fill", tint: StrandPalette.restBright,
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
        return TodaySynthesisRow(id: "session", symbol: "dumbbell.fill", tint: StrandPalette.effortColor,
                                 title: String(localized: "Today's session"),
                                 subtitle: subtitle.isEmpty ? nil : subtitle, value: session.name, route: route)
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
