import SwiftUI
import StrandDesign
import WhoopStore

// MARK: - Habits: shared parts (personal fork, chantier 24, PR B)
//
// The pieces the Habits list, a habit's page and the More row share: the colour of a habit (its key
// mapped to a design token, never a local colour), its icon tile, the formats, the ticking stopwatch,
// the bars and the « When » strip. Every figure they draw comes from `HabitLog` (the one resolver).

/// A habit's colour: its stored key mapped to an existing design token. An unknown key falls back to
/// the default.
enum HabitPalette {
    static let defaultKey = "cyan"

    static func tint(_ key: String) -> Color {
        switch key {
        case "violet": return StrandPalette.macroProtein
        case "orange": return StrandPalette.caloriesActivity
        case "green": return StrandPalette.fastingDone
        case "blue": return StrandPalette.accent
        case "pink": return StrandPalette.liquidHeart
        case "yellow": return StrandPalette.macroCarbs
        default: return StrandPalette.macroFat
        }
    }

    /// The SF Symbols a habit can take, the default first.
    static let symbols = [
        "book.fill", "figure.mind.and.body", "guitars.fill", "pencil", "brain.head.profile", "paintpalette.fill",
        "laptopcomputer", "music.note", "globe", "leaf.fill", "dumbbell.fill", "moon.stars.fill",
    ]
}

/// The formats the habits screens share.
enum HabitFormat {
    /// « 3h 25m », « 45 min »: the catalogue's existing duration forms (as the fasting screens).
    static func duration(seconds: Int) -> String {
        FastingFormat.duration(minutes: max(0, seconds) / 60)
    }

    /// The stopwatch: « 12:34 », then « 1:02:03 » past an hour. Digits only.
    static func stopwatch(seconds: Int) -> String {
        let total = max(0, seconds)
        let hours = total / 3_600
        let minutes = total % 3_600 / 60
        let secs = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// Why the session editor refuses what was entered.
    static func problemText(_ problem: HabitSessionProblem) -> String {
        switch problem {
        case .endNotAfterStart: return String(localized: "The end must come after the start.")
        case .tooLong: return String(localized: "A session can last 12 hours at most.")
        case .inFuture: return String(localized: "The session cannot end in the future.")
        case .overlaps: return String(localized: "Another session of this habit already covers this time.")
        }
    }

    /// « Yesterday · 22:05 – 22:42 », the start's day then the two times (only the start while it runs).
    static func sessionWhen(_ session: HabitSessionRow, now: Date = Date()) -> String {
        let start = Date(timeIntervalSince1970: TimeInterval(session.startedAt))
        let day = FastingFormat.dayWord(start, now: now)
        guard let endSec = session.endedAt else { return "\(day) · \(FastingFormat.clock(start))" }
        let end = Date(timeIntervalSince1970: TimeInterval(endSec))
        return "\(day) · \(FastingFormat.clock(start)) – \(FastingFormat.clock(end))"
    }
}

/// A habit's icon on its colour.
struct HabitIconTile: View {
    let symbol: String
    let colorKey: String
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(StrandPalette.surfaceBase)
            .frame(width: size, height: size)
            .background(HabitPalette.tint(colorKey),
                        in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// The running stopwatch, ticking every second from `startedAt`. Nothing counts in the background: the
/// text is recomputed from the stored start.
struct HabitStopwatchText: View {
    let startedAt: Date
    var font: Font = StrandFont.number(44, weight: .bold)
    var color: Color = StrandPalette.textPrimary

    var body: some View {
        TimelineView(.periodic(from: startedAt, by: 1)) { context in
            Text(verbatim: HabitFormat.stopwatch(seconds: Int(context.date.timeIntervalSince(startedAt))))
                .font(font)
                .foregroundStyle(color)
                .monospacedDigit()
                .lineLimit(1)
        }
    }
}

/// The bars of a habit's chart (`HabitLog.habitBars`), a tap selecting one and a second tap releasing it.
struct HabitBarsChart: View {
    let bars: [HabitBar]
    let period: HabitChartPeriod
    let colorKey: String
    @Binding var selected: Int?

    private var maxSeconds: Int { max(60, bars.map(\.seconds).max() ?? 0) }

    private var activeCount: Int { bars.filter { $0.seconds > 0 }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            caption
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(alignment: .bottom, spacing: period == .month ? 2 : 6) {
                ForEach(Array(bars.enumerated()), id: \.offset) { index, bar in
                    Button {
                        selected = selected == index ? nil : index
                    } label: {
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(HabitPalette.tint(colorKey).opacity(selected == nil || selected == index ? 1 : 0.35))
                                .frame(height: bar.seconds > 0 ? max(3, 110 * CGFloat(bar.seconds) / CGFloat(maxSeconds)) : 2)
                                .opacity(bar.seconds > 0 ? 1 : 0.25)
                        }
                        .frame(maxWidth: .infinity, minHeight: 110, maxHeight: 110)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: label(bar)))
                    .accessibilityValue(Text(verbatim: HabitFormat.duration(seconds: bar.seconds)))
                }
            }
            axis
                .font(StrandFont.caption2)
                .foregroundStyle(StrandPalette.textTertiary)
        }
    }

    @ViewBuilder
    private var caption: some View {
        if let selected, bars.indices.contains(selected) {
            Text(verbatim: [HabitFormat.duration(seconds: bars[selected].seconds), label(bars[selected])]
                .joined(separator: " · "))
        } else {
            let total = bars.reduce(0) { $0 + $1.seconds }
            if period == .quarter {
                Text("\(HabitFormat.duration(seconds: total)) · \(activeCount) weeks with a session")
            } else {
                Text("\(HabitFormat.duration(seconds: total)) · \(activeCount) days with a session")
            }
        }
    }

    @ViewBuilder
    private var axis: some View {
        if period == .week {
            HStack(spacing: 6) {
                ForEach(Array(bars.enumerated()), id: \.offset) { _, bar in
                    Text(verbatim: bar.start.formatted(.dateTime.weekday(.narrow)))
                        .frame(maxWidth: .infinity)
                }
            }
        } else if let first = bars.first, let last = bars.last {
            HStack {
                Text(verbatim: first.start.formatted(.dateTime.day().month(.abbreviated)))
                Spacer()
                Text(verbatim: last.start.formatted(.dateTime.day().month(.abbreviated)))
            }
        }
    }

    /// « Mon 9 Nov », or « from 9 Nov » for a week bar.
    private func label(_ bar: HabitBar) -> String {
        if period == .quarter {
            return String(localized: "week of \(bar.start.formatted(.dateTime.day().month(.abbreviated)))")
        }
        return bar.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }
}

/// « When »: the stretches of the day the sessions of the last 30 days covered, on a 24 h strip.
struct HabitDayStrip: View {
    let spans: [HabitDaySpan]
    let colorKey: String

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(StrandPalette.surfaceInset)
                    ForEach(Array(spans.enumerated()), id: \.offset) { _, span in
                        Rectangle()
                            .fill(HabitPalette.tint(colorKey).opacity(0.55))
                            .frame(width: max(2, width * CGFloat(span.endMinute - span.startMinute) / 1_440))
                            .offset(x: width * CGFloat(span.startMinute) / 1_440)
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 14)
            HStack {
                ForEach([0, 6, 12, 18, 24], id: \.self) { hour in
                    Text(verbatim: hourLabel(hour))
                    if hour < 24 { Spacer(minLength: 0) }
                }
            }
            .font(StrandFont.caption2)
            .foregroundStyle(StrandPalette.textTertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Times of day of the sessions over 30 days"))
    }

    /// « 06:00 » in the wearer's clock format (24 reads as midnight's own label).
    private func hourLabel(_ hour: Int) -> String {
        let midnight = Calendar.current.startOfDay(for: Date())
        return FastingFormat.clock(midnight.addingTimeInterval(TimeInterval((hour % 24) * 3_600)))
    }
}
