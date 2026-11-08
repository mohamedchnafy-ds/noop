import SwiftUI
import Charts
import StrandDesign
import WhoopStore

// MARK: - Pieces of the Élan screens (personal fork, chantier 10, PR B)
//
// The words and the small drawings every Élan screen shares: a weight, a day, a theme's colour, the
// seven marks of a week, the stacked bars of the weeks, the smoothed weight curve. Every figure arrives
// resolved (`ElanState`, `ElanWeightSummary`, `WorkoutHistoryBar`); nothing here computes one of its own.
// Motion follows the chantier 12 rules: a drawing traces itself once per showing (`NoopFirstDraw`), the
// marks light up left to right with the rings' stagger, nothing loops.

enum ElanTab: Hashable, CaseIterable {
    case week, progress, read
}

/// What an Élan screen pushes.
enum ElanRoute: Hashable {
    case comparison
    case weight
    case reading(String)
    case progression
}

enum ElanFormat {

    /// « 84,1 kg » / « 185.4 lb ».
    static func weight(_ kg: Double, system: UnitSystem) -> String {
        UnitFormatter.massFromKilograms(kg, system: system)
    }

    /// « −1,9 kg », « +0,4 kg » (the sign always written).
    static func signedWeight(_ kg: Double, system: UnitSystem) -> String {
        let text = weight(abs(kg), system: system)
        if kg > 0.049 { return "+" + text }
        if kg < -0.049 { return "−" + text }
        return text
    }

    /// « 2,8 » (one decimal, the app's separator).
    static func oneDecimal(_ value: Double) -> String { UnitFormatter.decimal(value, places: 1) }

    /// « 5 oct. »: a day key as a short date in the app's language.
    static func dayLabel(_ dayKey: String) -> String {
        guard let date = ElanDays.elanDate(dayKey) else { return dayKey }
        var style = Date.FormatStyle(timeZone: TimeZone(identifier: "UTC") ?? .current)
        style.locale = AppLanguage.activeLocale
        return date.formatted(style.day().month(.abbreviated))
    }

    /// « jeudi 5 novembre »: today's line under the title.
    static func longDate(_ date: Date) -> String {
        var style = Date.FormatStyle()
        style.locale = AppLanguage.activeLocale
        return date.formatted(style.weekday(.wide).day().month(.wide))
    }

    /// « 10 days ago », « yesterday », « today » for a unix start.
    static func daysAgo(_ ts: Int, now: Date = Date()) -> String {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(ts)))
        let days = max(0, calendar.dateComponents([.day], from: day, to: calendar.startOfDay(for: now)).day ?? 0)
        switch days {
        case 0: return String(localized: "today")
        case 1: return String(localized: "yesterday")
        default: return String(localized: "\(days) days ago")
        }
    }

    /// « 6h 10m », as the Sleep tab writes a duration.
    static func duration(_ minutes: Double) -> String { SleepDurationText.format(minutes) }

    /// The initials of the days of the week, Monday first, in the app's language.
    static func weekdayLetters(calendar: Calendar = .current) -> [String] {
        var cal = calendar
        cal.locale = AppLanguage.activeLocale
        let symbols = cal.veryShortWeekdaySymbols
        guard symbols.count == 7 else { return ["M", "T", "W", "T", "F", "S", "S"] }
        return (1...7).map { symbols[$0 % 7] }
    }

    /// The initial of a day key's weekday, in the app's language.
    static func weekdayLetter(_ dayKey: String) -> String {
        guard let date = ElanDays.elanDate(dayKey) else { return "" }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .current
        cal.locale = AppLanguage.activeLocale
        let symbols = cal.veryShortWeekdaySymbols
        let weekday = cal.component(.weekday, from: date)
        return symbols.indices.contains(weekday - 1) ? symbols[weekday - 1] : ""
    }

    /// The colour of a reading's theme: the colour of the screen that owns the subject.
    static func themeColor(_ theme: ElanReadingTheme) -> Color {
        switch theme {
        case .heart: return StrandPalette.metricRose
        case .sleep: return StrandPalette.restRing
        case .nutrition: return StrandPalette.intakeColor
        case .training: return StrandPalette.effortColor
        }
    }

    static func themeName(_ theme: ElanReadingTheme) -> String {
        switch theme {
        case .heart: return String(localized: "Heart")
        case .sleep: return String(localized: "Sleep")
        case .nutrition: return String(localized: "Nutrition")
        case .training: return String(localized: "Training")
        }
    }

    /// The app's language code for the readings (French, else English).
    static var languageCode: String { AppLanguage.activeLocale.language.languageCode?.identifier ?? "en" }
}

// MARK: - Small pieces

/// A section title over a card, as the mockup's « Victoires » / « Ce que tu as construit ».
struct ElanSectionTitle: View {
    let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) { self.title = title }

    var body: some View {
        Text(title)
            .font(StrandFont.sectionTitle)
            .foregroundStyle(StrandPalette.textPrimary)
            .padding(.horizontal, 4)
    }
}

/// A small sand label at the head of a card: « Jamais deux fois de suite », « À essayer ».
struct ElanSandLabel: View {
    let text: Text

    var body: some View {
        text
            .font(StrandFont.footnote.weight(.semibold))
            .foregroundStyle(StrandPalette.elanSand)
    }
}

/// A full-width action: white for the main one, inset for the others (the Jeûne page's buttons).
struct ElanActionButton: View {
    enum Look { case primary, secondary }
    let title: Text
    var look: Look = .secondary
    var systemImage: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 13, weight: .bold))
                }
                title
            }
            .font(StrandFont.body.weight(look == .primary ? .bold : .semibold))
            .foregroundStyle(look == .primary ? StrandPalette.surfaceBase : StrandPalette.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(look == .primary ? StrandPalette.textPrimary : StrandPalette.surfaceInset,
                        in: RoundedRectangle(cornerRadius: 23, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
        }
        .buttonStyle(LiquidPressStyle())
    }
}

/// The right-hand « Détail › » of a card header.
struct ElanDetailLink: View {
    var body: some View {
        HStack(spacing: 2) {
            Text("Details")
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
        }
        .font(StrandFont.subhead)
        .foregroundStyle(StrandPalette.accent)
    }
}

// MARK: - The seven marks of a week

/// One mark of « Cette semaine »: done (filled blue), planned (blue ring), missed (grey ring), today
/// (dashed sand ring), tonight's short session (filled sand), rest (a small grey dot).
struct ElanDayMarkView: View {
    let mark: ElanDayMark

    var body: some View {
        ZStack {
            switch mark {
            case .done:
                Circle().fill(StrandPalette.effortColor).frame(width: 22, height: 22)
            case .planned:
                Circle().strokeBorder(StrandPalette.effortColor, lineWidth: 2).frame(width: 18, height: 18)
            case .missed:
                Circle().strokeBorder(StrandPalette.textTertiary, lineWidth: 2).frame(width: 18, height: 18)
            case .today:
                Circle().strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
                    .foregroundStyle(StrandPalette.elanSand).frame(width: 18, height: 18)
            case .todayShort:
                Circle().fill(StrandPalette.elanSand).frame(width: 22, height: 22)
            case .rest:
                Circle().fill(StrandPalette.surfaceInset).frame(width: 6, height: 6)
            }
        }
        .frame(width: 22, height: 22)
        .accessibilityLabel(label)
    }

    private var label: Text {
        switch mark {
        case .done: return Text("session done")
        case .planned: return Text("session planned")
        case .missed: return Text("session missed")
        case .today: return Text("today")
        case .todayShort: return Text("tonight: the short session")
        case .rest: return Text("rest")
        }
    }
}

/// The week's row: a letter above each mark; the marks light up left to right, once per showing.
struct ElanWeekRow: View {
    let days: [ElanWeekDay]
    var animated: Bool = false
    var launchKey: String = "elan.week.marks"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var motion = NoopMotionState.shared

    var body: some View {
        let letters = ElanFormat.weekdayLetters()
        NoopFirstDraw(key: launchKey, armed: animated) { phase in
            HStack(spacing: 4) {
                ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                    VStack(spacing: 6) {
                        Text(verbatim: letters.indices.contains(index) ? letters[index] : "")
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textSecondary)
                        ElanDayMarkView(mark: day.mark)
                            .opacity(phase.drawn ? 1 : 0)
                            .scaleEffect(phase.drawn ? 1 : 0.6)
                            .animation(phase.motion(NoopMotion.valueChange.delay(Double(index) * NoopMotion.ringStagger)),
                                       value: phase.drawn)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

// MARK: - The weeks' bars

/// The minutes of each week, stacked (cardio at the bottom, then lifting, then the rest), the Historique's
/// colours, with the « lancé » weeks under a pale band. The bars rise once per showing.
struct ElanWeeksBars: View {
    let bars: [WorkoutHistoryBar]
    /// The launched window's first and last day keys, when there is one.
    var launched: (start: String, end: String)?
    var height: CGFloat = 60
    var animated: Bool = false
    var launchKey: String = "elan.weeks.bars"

    private func isLaunched(_ bar: WorkoutHistoryBar) -> Bool {
        guard let launched else { return false }
        let key = TrainingCalendar.trainingDayKey(bar.start, calendar: .current)
        let end = TrainingCalendar.trainingDayKey(bar.start.addingTimeInterval(6 * 86_400), calendar: .current)
        return end >= launched.start && key <= launched.end
    }

    var body: some View {
        let peak = max(1, bars.map(\.totalMinutes).max() ?? 1)
        NoopFirstDraw(key: launchKey, armed: animated) { phase in
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(Array(bars.enumerated()), id: \.offset) { index, bar in
                    VStack(spacing: 1) {
                        Spacer(minLength: 0)
                        segment(bar.otherMinutes, peak: peak, color: StrandPalette.metricCyan)
                        segment(bar.liftMinutes, peak: peak, color: StrandPalette.effortColor)
                        segment(bar.cardioMinutes, peak: peak, color: StrandPalette.metricRose)
                        if bar.totalMinutes == 0 {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(StrandPalette.surfaceInset)
                                .frame(height: 3)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
                    .scaleEffect(x: 1, y: phase.drawn ? 1 : 0.02, anchor: .bottom)
                    .animation(phase.motion(NoopMotion.ringDraw.delay(Double(index) * NoopMotion.stagger)),
                               value: phase.drawn)
                    .background {
                        if isLaunched(bar) {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(StrandPalette.effortColor.opacity(0.12))
                                .padding(.horizontal, -2.5)
                                .opacity(phase.drawn ? 1 : 0)
                                .animation(phase.motion(NoopMotion.valueChange.delay(NoopMotion.ringDrawDuration)),
                                           value: phase.drawn)
                        }
                    }
                    .accessibilityLabel(Text(verbatim: WorkoutHistoryLogic.historyDuration(minutes: bar.totalMinutes)))
                }
            }
            .frame(height: height)
        }
    }

    @ViewBuilder
    private func segment(_ minutes: Int, peak: Int, color: Color) -> some View {
        if minutes > 0 {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(color)
                .frame(height: max(3, (height - 4) * CGFloat(minutes) / CGFloat(peak)))
        }
    }
}

// MARK: - The weight curve

/// The smoothed trend, drawn left to right once per showing: no point per weigh-in, the target as a dashed
/// line, the last point marked. Empty under a trend.
struct ElanTrendChart: View {
    let points: [ElanWeightTrendPoint]
    var targetKg: Double?
    var system: UnitSystem = .metric
    var height: CGFloat = 150
    var animated: Bool = false
    var launchKey: String = "elan.weight.curve"

    private func display(_ kg: Double) -> Double { LiftFormat.display(fromKilograms: kg, system: system) }

    private var dated: [(date: Date, value: Double)] {
        points.compactMap { point in
            ElanDays.elanDate(point.day).map { (date: $0, value: display(point.kg)) }
        }
    }

    var body: some View {
        let rows = dated
        let values = rows.map(\.value) + (targetKg.map { [display($0)] } ?? [])
        let low = (values.min() ?? 0) - 0.5
        let high = (values.max() ?? 1) + 0.5
        NoopFirstDraw(key: launchKey, armed: animated) { phase in
            Chart {
                if let targetKg {
                    RuleMark(y: .value("Target", display(targetKg)))
                        .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 5]))
                        .foregroundStyle(StrandPalette.textSecondary)
                }
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    LineMark(x: .value("Day", row.date), y: .value("Trend", row.value))
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                        .foregroundStyle(StrandPalette.textPrimary)
                }
                if let last = rows.last {
                    PointMark(x: .value("Day", last.date), y: .value("Trend", last.value))
                        .symbolSize(40)
                        .foregroundStyle(StrandPalette.textPrimary)
                        .opacity(phase.drawn ? 1 : 0)
                }
            }
            .chartYScale(domain: low...high)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .frame(height: height)
            .mask(alignment: .leading) {
                GeometryReader { geo in
                    Rectangle().frame(width: geo.size.width * (phase.drawn ? 1 : 0))
                }
            }
            .animation(phase.motion(NoopMotion.ringDraw), value: phase.drawn)
            .accessibilityLabel(Text("Weight trend"))
        }
    }
}

/// The three dots legend under the Nutrition week: held · not held · nothing logged.
struct ElanNutritionDayMark: View {
    let status: ElanNutritionDay.Status

    var body: some View {
        ZStack {
            switch status {
            case .held: Circle().fill(StrandPalette.intakeColor).frame(width: 22, height: 22)
            case .missed: Circle().strokeBorder(StrandPalette.textSecondary, lineWidth: 2).frame(width: 18, height: 18)
            case .none: RoundedRectangle(cornerRadius: 2).fill(StrandPalette.surfaceInset).frame(width: 16, height: 3)
            }
        }
        .frame(width: 22, height: 22)
        .accessibilityLabel(label)
    }

    private var label: Text {
        switch status {
        case .held: return Text("held")
        case .missed: return Text("not held")
        case .none: return Text("no meal logged")
        }
    }
}
