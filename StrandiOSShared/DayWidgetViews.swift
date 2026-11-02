import SwiftUI
import StrandDesign

// The three day widgets' faces (personal fork, chantier 6): "Today's session", "Nutrition" and "Sleep", small
// and medium, as drawn in the mockup ("NOOP – Bannières et widgets", artboards 7 and 8).
//
// Plain values in, no WidgetKit: the extension draws them from `DayWidgetsSnapshot`, and the macOS app module
// compiles this same file so `StrandTests` renders them to PNG (`DayWidgetsRenderTests`). Every word arrives
// already localized in the snapshot: nothing here is copy. The faces carry no padding of their own — the
// widget's content margins frame them, and the render test adds the same margin.

/// The two families the day widgets come in.
enum DayWidgetSize {
    case small, medium
}

/// A widget's overline: the section's icon and title in its colour.
struct DayWidgetHeader: View {
    let symbol: String
    let title: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
            Text(title)
                .font(StrandFont.overline)
                .tracking(1)
                .textCase(.uppercase)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(tint)
        .accessibilityElement(children: .combine)
    }
}

/// A line with its figure set apart (`DayWidgetsSnapshot.Emphasis`).
struct DayWidgetEmphasisLine: View {
    let line: DayWidgetsSnapshot.Emphasis
    var tint: Color = StrandPalette.textPrimary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            if !line.before.isEmpty {
                Text(line.before).foregroundStyle(StrandPalette.textSecondary)
            }
            Text(line.value)
                .fontWeight(.semibold)
                .foregroundStyle(tint)
            if !line.after.isEmpty {
                Text(line.after).foregroundStyle(StrandPalette.textSecondary)
            }
        }
        .font(StrandFont.caption)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Today's session

/// "Today's session": the program, the Synthèse's line and the week strip; the medium one adds the first two
/// blocks and an Open button.
struct DaySessionWidgetFace: View {
    let session: DayWidgetsSnapshot.Session?
    let labels: DayWidgetsSnapshot.Labels
    let size: DayWidgetSize

    var body: some View {
        switch size {
        case .small: small
        case .medium: medium
        }
    }

    private var header: some View {
        DayWidgetHeader(symbol: "dumbbell.fill", title: labels.sessionTitle, tint: StrandPalette.effortBright)
    }

    @ViewBuilder
    private var name: some View {
        if let name = session?.name {
            Text(name)
                .font(StrandFont.rounded(19, weight: .bold))
                .foregroundStyle(StrandPalette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        } else {
            Text(labels.noData)
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
        }
    }

    @ViewBuilder
    private func line(_ text: String?) -> some View {
        if let text {
            if session?.state == .done {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .heavy))
                    Text(text)
                }
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.statusPositive)
                .lineLimit(1)
                .accessibilityElement(children: .combine)
            } else {
                Text(text)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            name.padding(.top, 6)
            line(session?.line)
            Spacer(minLength: 0)
            if let week = session?.week, !week.isEmpty {
                HStack(spacing: 4) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        DayWidgetWeekMark(mark: day.mark, size: 9)
                    }
                    if let tally = session?.tally {
                        Text(tally)
                            .font(StrandFont.caption)
                            .monospacedDigit()
                            .foregroundStyle(StrandPalette.textSecondary)
                            .padding(.leading, 4)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                header
                name.padding(.top, 4)
                line(session?.lineMedium ?? session?.line)
                if let blocks = session?.blocks, !blocks.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(blocks.prefix(2).enumerated()), id: \.offset) { _, block in
                            Text(block)
                                .font(StrandFont.caption)
                                .foregroundStyle(StrandPalette.textPrimary.opacity(0.8))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    .padding(.top, 6)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 0) {
                if let weekLine = session?.weekLine {
                    Text(weekLine)
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 6)
                if let week = session?.week, !week.isEmpty {
                    DayWidgetWeekGrid(week: week)
                }
                Spacer(minLength: 6)
                HStack(spacing: 5) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text(labels.open)
                        .font(StrandFont.rounded(13, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(StrandPalette.accent)
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(StrandPalette.accent.opacity(0.2), in: Capsule())
                .accessibilityElement(children: .combine)
            }
            .frame(width: 112)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// One day's mark in the week strip.
struct DayWidgetWeekMark: View {
    let mark: DayWidgetsSnapshot.Mark
    var size: CGFloat = 9

    var body: some View {
        Group {
            switch mark {
            case .planned:
                Circle().strokeBorder(StrandPalette.effortColor, lineWidth: 2)
            case .done:
                Circle().fill(StrandPalette.effortColor)
            case .missed:
                Circle().strokeBorder(StrandPalette.textTertiary, lineWidth: 2)
            case .cardio:
                Circle().fill(StrandPalette.metricRose)
            case .none:
                Circle().fill(StrandPalette.textPrimary.opacity(0.1))
            }
        }
        .frame(width: size, height: size)
    }
}

/// The medium widget's week: the day letters over their marks, an empty day left blank.
struct DayWidgetWeekGrid: View {
    let week: [DayWidgetsSnapshot.WeekDay]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                VStack(spacing: 4) {
                    Text(day.letter)
                        .font(StrandFont.rounded(10, weight: day.isToday ? .bold : .regular))
                        .foregroundStyle(day.isToday ? StrandPalette.textPrimary : StrandPalette.textSecondary)
                    if day.mark == .none {
                        Color.clear.frame(width: 9, height: 9)
                    } else {
                        DayWidgetWeekMark(mark: day.mark, size: 9)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Nutrition

/// "Nutrition": eaten against the intake goal (a ring in the small one) and the macros; the medium one adds
/// the balance, the meals and a bar per macro.
struct DayNutritionWidgetFace: View {
    let nutrition: DayWidgetsSnapshot.Nutrition?
    let labels: DayWidgetsSnapshot.Labels
    let size: DayWidgetSize

    var body: some View {
        switch size {
        case .small: small
        case .medium: medium
        }
    }

    private var header: some View {
        DayWidgetHeader(symbol: "fork.knife", title: labels.nutritionTitle, tint: StrandPalette.caloriesActivity)
    }

    private var noData: some View {
        Text(labels.noData)
            .font(StrandFont.caption)
            .foregroundStyle(StrandPalette.textSecondary)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            if let nutrition {
                HStack(spacing: 10) {
                    DayWidgetRing(fraction: nutrition.fraction, tint: StrandPalette.caloriesActivity)
                        .frame(width: 58, height: 58)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(nutrition.eaten)
                            .font(StrandFont.number(19, weight: .bold))
                            .foregroundStyle(StrandPalette.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(nutrition.goalShort)
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .padding(.top, 4)
                Spacer(minLength: 0)
                DayWidgetEmphasisLine(
                    line: .init(before: labels.protein + " ", value: nutrition.protein.eaten,
                                after: " " + nutrition.protein.rest),
                    tint: StrandPalette.metricCyan)
            } else {
                noData.padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                header
                if let nutrition {
                    Text(nutrition.eaten)
                        .font(StrandFont.number(24, weight: .bold))
                        .foregroundStyle(StrandPalette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.top, 4)
                    Text(nutrition.goalLong)
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    if let balance = nutrition.balance {
                        DayWidgetEmphasisLine(line: .init(before: balance.before, value: balance.value,
                                                          after: balance.after + " · " + nutrition.meals))
                    } else {
                        Text(nutrition.meals)
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                } else {
                    noData.padding(.top, 6)
                    Spacer(minLength: 0)
                }
            }
            .frame(width: 124, alignment: .leading)
            if let nutrition {
                VStack(spacing: 10) {
                    macroBar(labels.protein, nutrition.protein, StrandPalette.metricCyan)
                    macroBar(labels.carbs, nutrition.carbs, StrandPalette.metricAmber)
                    macroBar(labels.fat, nutrition.fat, StrandPalette.metricPurple)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func macroBar(_ label: String, _ macro: DayWidgetsSnapshot.Macro, _ tint: Color) -> some View {
        let figures = [macro.eaten, macro.rest].joined(separator: " ")
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(label)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(figures)
                    .monospacedDigit()
                    .foregroundStyle(StrandPalette.textPrimary)
                    .lineLimit(1)
            }
            .font(StrandFont.caption)
            .minimumScaleFactor(0.8)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(tint.opacity(0.22))
                    Capsule().fill(tint)
                        .frame(width: geo.size.width * CGFloat(min(1, max(0, macro.fraction ?? 0))))
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The small Nutrition widget's ring: eaten against the goal, empty without one.
struct DayWidgetRing: View {
    let fraction: Double?
    let tint: Color

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.18), lineWidth: 7)
            Circle()
                .trim(from: 0, to: CGFloat(min(1, max(0, fraction ?? 0))))
                .stroke(tint, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(3.5)
    }
}

// MARK: - Sleep

/// "Sleep": the night, the debt and the suggested bedtime; the medium one adds the night's phases with its
/// onset, the usual wake-up and its end.
struct DaySleepWidgetFace: View {
    let sleep: DayWidgetsSnapshot.Sleep?
    let labels: DayWidgetsSnapshot.Labels
    let size: DayWidgetSize

    var body: some View {
        switch size {
        case .small: small
        case .medium: medium
        }
    }

    private var header: some View {
        DayWidgetHeader(symbol: "bed.double.fill", title: labels.sleepTitle, tint: StrandPalette.restColor)
    }

    private func night(_ points: CGFloat) -> some View {
        Text(sleep?.night ?? labels.noData)
            .font(sleep?.night == nil ? StrandFont.caption : StrandFont.number(points, weight: .bold))
            .foregroundStyle(sleep?.night == nil ? StrandPalette.textSecondary : StrandPalette.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            night(26).padding(.top, 6)
            if let debt = sleep?.debt {
                DayWidgetEmphasisLine(line: debt, tint: StrandPalette.textSecondary)
            }
            Spacer(minLength: 0)
            if let bedtime = sleep?.bedtime {
                DayWidgetEmphasisLine(line: bedtime)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    header
                    night(24)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    if let debt = sleep?.debt { DayWidgetEmphasisLine(line: debt) }
                    if let bedtime = sleep?.bedtime { DayWidgetEmphasisLine(line: bedtime) }
                }
            }
            Spacer(minLength: 0)
            if let phases = sleep?.phases, !phases.isEmpty {
                DayWidgetPhaseBar(phases: phases)
                    .frame(height: 14)
            }
            HStack {
                if let start = sleep?.start { Text(start) }
                Spacer(minLength: 4)
                if let wake = sleep?.usualWake { Text(wake).lineLimit(1).minimumScaleFactor(0.8) }
                Spacer(minLength: 4)
                if let end = sleep?.end { Text(end) }
            }
            .font(StrandFont.footnote)
            .monospacedDigit()
            .foregroundStyle(StrandPalette.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// The night's phases side by side, each as wide as it lasted.
struct DayWidgetPhaseBar: View {
    let phases: [DayWidgetsSnapshot.Phase]

    var body: some View {
        GeometryReader { geo in
            let total = max(1, phases.reduce(0) { $0 + max(0, $1.minutes) })
            HStack(spacing: 0) {
                ForEach(Array(phases.enumerated()), id: \.offset) { _, phase in
                    Self.color(phase.stage)
                        .frame(width: geo.size.width * CGFloat(max(0, phase.minutes)) / CGFloat(total))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .accessibilityHidden(true)
    }

    /// The Sleep screen's stage colours.
    static func color(_ stage: String) -> Color {
        switch stage {
        case "light": return StrandPalette.sleepLight
        case "deep": return StrandPalette.sleepDeep
        case "rem": return StrandPalette.sleepREM
        default: return StrandPalette.sleepAwake
        }
    }
}
