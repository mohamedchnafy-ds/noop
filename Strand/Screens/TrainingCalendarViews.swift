import SwiftUI
import StrandDesign

// MARK: - Training screen parts (personal fork)
//
// The pure parts of the Training screen (mockup « NOOP – Entraînement et Plus »): week strip, month grid,
// legend, the selected day (planned card, what was done), the programs card and the month totals. They
// take loaded models and closures only, so the render test draws them with sample data; the store, the
// session controller and the navigation stay in `LiftLogView`.

/// Copy shared by the Training parts, worded through the catalogue.
enum TrainingText {
    /// "5 supersets + 2 exercises" (either part left out when zero).
    static func shapeLine(supersets: Int, singles: Int) -> String {
        var parts: [String] = []
        if supersets > 0 {
            parts.append(supersets == 1 ? String(localized: "1 superset") : String(localized: "\(supersets) supersets"))
        }
        if singles > 0 {
            parts.append(singles == 1 ? String(localized: "1 exercise") : String(localized: "\(singles) exercises"))
        }
        return parts.joined(separator: " + ")
    }

    /// The planned card's line: shape · ≈ usual length · when it was last done.
    static func plannedLine(_ program: TrainingProgramSummary) -> String {
        var parts = [shapeLine(supersets: program.supersets, singles: program.singles)].filter { !$0.isEmpty }
        if let minutes = program.typicalMinutes { parts.append(String(localized: "≈ \(minutes) min")) }
        if let last = program.lastDoneTs {
            parts.append(String(localized: "last time: \(shortDate(last))"))
        }
        return parts.joined(separator: " · ")
    }

    /// A program row's line: shape · total working sets.
    static func programLine(_ program: TrainingProgramSummary) -> String {
        var parts = [shapeLine(supersets: program.supersets, singles: program.singles)].filter { !$0.isEmpty }
        if program.totalSets > 0 {
            parts.append(program.totalSets == 1 ? String(localized: "1 set") : String(localized: "\(program.totalSets) sets"))
        }
        return parts.joined(separator: " · ")
    }

    /// A Lift Log session done: Lift Log · 14:05 · 52 min · 18 sets · Effort 58.
    static func liftLine(_ lift: TrainingLiftDone) -> String {
        var parts = [String(localized: "Lift Log"), clockText(lift.startTs), String(localized: "\(lift.minutes) min")]
        parts.append(lift.workingSets == 1 ? String(localized: "1 set") : String(localized: "\(lift.workingSets) sets"))
        if let effort = lift.effort { parts.append(String(localized: "Effort \(effort)")) }
        return parts.joined(separator: " · ")
    }

    /// Another activity: detected · 18:30 · 25 min · 140 kcal.
    static func activityLine(_ activity: TrainingActivityDone) -> String {
        var parts = [activity.source, clockText(activity.startTs), String(localized: "\(activity.minutes) min")]
        if let kcal = activity.kcal, kcal > 0 { parts.append(String(localized: "\(kcal) kcal")) }
        return parts.joined(separator: " · ")
    }

    /// "14:05" (or the 12-hour form) through the app's clock preference.
    static func clockText(_ ts: Int) -> String {
        AppClock.hourMinuteFormatter().string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
    }

    /// "Mon 26 Oct".
    static func shortDate(_ ts: Int) -> String {
        Date(timeIntervalSince1970: TimeInterval(ts))
            .formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    /// "Monday 2 November", with "· today" on today.
    static func dayTitle(_ day: TrainingDay) -> String {
        let text = day.date.formatted(.dateTime.weekday(.wide).day().month(.wide))
        let title = text.prefix(1).uppercased() + text.dropFirst()
        return day.isToday ? String(localized: "\(title) · today") : title
    }

    /// "Week of 2 to 8 November" (the month on both ends when the week spans two months).
    static func weekTitle(monday: Date, calendar: Calendar) -> String {
        let sunday = calendar.date(byAdding: .day, value: 6, to: monday) ?? monday
        let sameMonth = calendar.component(.month, from: monday) == calendar.component(.month, from: sunday)
        let start = sameMonth ? monday.formatted(.dateTime.day()) : monday.formatted(.dateTime.day().month(.wide))
        let end = sunday.formatted(.dateTime.day().month(.wide))
        return String(localized: "Week of \(start) to \(end)")
    }

    /// "November 2026", capitalised.
    static func monthTitle(_ date: Date) -> String {
        let text = date.formatted(.dateTime.month(.wide).year())
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// The period bar's count: "This week · 1 / 3 sessions", or done sessions alone without a plan.
    static func tallyLine(done: Int, planned: Int, current: String?) -> String {
        let count = planned > 0 ? String(localized: "\(done) / \(planned) sessions") : String(localized: "\(done) sessions")
        guard let current else { return count }
        return current + " · " + count
    }

    /// Short weekday names, Monday first ("lun.", "mar."…), from the locale.
    static func shortWeekdays(_ calendar: Calendar) -> [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols   // Sunday first
        return (0..<7).map { symbols[($0 + 1) % 7] }
    }

    /// One-letter weekday names, Monday first.
    static func narrowWeekdays(_ calendar: Calendar) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        return (0..<7).map { symbols[($0 + 1) % 7] }
    }

    /// Full weekday names, Monday first, capitalised.
    static func fullWeekdays(_ calendar: Calendar) -> [String] {
        let symbols = calendar.standaloneWeekdaySymbols
        return (0..<7).map { index in
            let name = symbols[(index + 1) % 7]
            return name.prefix(1).uppercased() + name.dropFirst()
        }
    }
}

/// The two views of the screen.
enum TrainingViewMode: Hashable { case week, month }

/// Set by the render tests: the PNG renderer cannot draw a `Menu`, so `TrainingMenu` then draws its
/// label alone (and a navigation link outside a navigation stack draws dimmed, so the Progression card
/// draws its label alone too).
private struct TrainingMenusAsLabelsKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var trainingMenusAsLabels: Bool {
        get { self[TrainingMenusAsLabelsKey.self] }
        set { self[TrainingMenusAsLabelsKey.self] = newValue }
    }
}

/// A menu without its indicator, drawn as its label alone in the render tests.
struct TrainingMenu<Content: View, Label: View>: View {
    private let content: () -> Content
    private let label: () -> Label
    @Environment(\.trainingMenusAsLabels) private var asLabel

    init(@ViewBuilder content: @escaping () -> Content, @ViewBuilder label: @escaping () -> Label) {
        self.content = content
        self.label = label
    }

    var body: some View {
        if asLabel {
            label()
        } else {
            Menu(content: content, label: label).menuIndicator(.hidden)
        }
    }
}

/// "Week | Month" in the header: the shared grey pill control (fork chantier 7).
struct TrainingModeSwitch: View {
    @Binding var mode: TrainingViewMode

    var body: some View {
        SegmentedPillControl([TrainingViewMode.week, TrainingViewMode.month], selection: $mode) { value in
            switch value {
            case .week: return String(localized: "Week")
            case .month: return String(localized: "Month")
            }
        }
        .fixedSize()
    }
}

/// The screen's header (fork chantier 7): the title in 34 bold beside the Week | Month switch, then one
/// grey line naming the period shown and its count, with ‹ › to move to the previous or next period.
struct TrainingHeader: View {
    @Binding var mode: TrainingViewMode
    /// "Week of 2 to 8 November · 0 / 3 sessions".
    let subtitle: String
    var onPrevious: () -> Void = {}
    var onNext: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .center, spacing: 12) {
                Text("Training")
                    .font(StrandFont.screenTitle)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                TrainingModeSwitch(mode: $mode)
            }
            HStack(spacing: 0) {
                Text(verbatim: subtitle)
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                TrainingPeriodArrow(symbol: "chevron.left", label: "Previous", action: onPrevious)
                TrainingPeriodArrow(symbol: "chevron.right", label: "Next", action: onNext)
            }
        }
    }
}

/// One of the header's ‹ › buttons: a grey chevron in its own hit area.
struct TrainingPeriodArrow: View {
    let symbol: String
    let label: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(StrandPalette.textSecondary)
                .frame(width: 36, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}

/// The marks of a day: outlined blue = lift planned, filled blue = lift done, orange = cardio. A missed
/// day keeps its outline, greyed.
struct TrainingDayMarks: View {
    let day: TrainingDay
    var size: CGFloat = 8

    var body: some View {
        HStack(spacing: 3) {
            if day.isPlannedOpen {
                Circle().strokeBorder(StrandPalette.effortColor, lineWidth: 2).frame(width: size, height: size)
            } else if day.isMissed {
                Circle().strokeBorder(StrandPalette.textTertiary, lineWidth: 2).frame(width: size, height: size)
            }
            if day.hasLift {
                Circle().fill(StrandPalette.effortColor).frame(width: size, height: size)
            }
            if day.hasActivity {
                Circle().fill(StrandPalette.metricRose).frame(width: size, height: size)
            }
        }
        .frame(height: size)
    }
}

/// The legend under the week strip and the month grid.
struct TrainingLegend: View {
    var body: some View {
        HStack(spacing: 16) {
            item(Circle().strokeBorder(StrandPalette.effortColor, lineWidth: 2), "lift planned")
            item(Circle().fill(StrandPalette.effortColor), "lift done")
            item(Circle().fill(StrandPalette.metricRose), "cardio")
        }
        .font(StrandFont.caption)
        .foregroundStyle(StrandPalette.textSecondary)
    }

    private func item<S: View>(_ mark: S, _ title: LocalizedStringKey) -> some View {
        HStack(spacing: 6) {
            mark.frame(width: 8, height: 8)
            Text(title)
        }
    }
}

/// Seven days, Monday first: the weekday (sentence case, 11 semibold grey), the day number (SF Rounded 20)
/// and its marks, on #1C1C1E tiles of radius 14. The chosen day is filled white with black text.
struct TrainingWeekStrip: View {
    let days: [TrainingDay]
    let selectedKey: String
    let weekdays: [String]
    let onSelect: (TrainingDay) -> Void

    private static let radius = NoopVisualStyle.compactRadius

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                let selected = day.key == selectedKey
                Button { onSelect(day) } label: {
                    VStack(spacing: 3) {
                        Text(verbatim: weekdayLabel(index))
                            .font(StrandFont.caption2.weight(.semibold))
                            .foregroundStyle(selected ? StrandPalette.surfaceBase.opacity(0.75) : StrandPalette.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(verbatim: day.date.formatted(.dateTime.day()))
                            .font(StrandFont.number(20, weight: .bold))
                            .foregroundStyle(selected ? StrandPalette.surfaceBase : StrandPalette.textPrimary)
                        TrainingDayMarks(day: day, size: 7)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 70)
                    .background(selected ? StrandPalette.textPrimary : StrandPalette.surfaceRaised,
                                in: RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
                    .overlay {
                        if day.isToday && !selected {
                            RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                                .strokeBorder(StrandPalette.accent, lineWidth: 1.5)
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func weekdayLabel(_ index: Int) -> String {
        guard weekdays.indices.contains(index) else { return "" }
        return weekdays[index]
    }
}

/// The month grid, Monday first: blanks before the 1st, each day with its marks; today outlined, the
/// chosen day filled white.
struct TrainingMonthGrid: View {
    let cells: [TrainingDay?]
    let selectedKey: String
    let weekdays: [String]
    let onSelect: (TrainingDay) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(Array(weekdays.enumerated()), id: \.offset) { _, name in
                    Text(verbatim: name.uppercased())
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                    if let day = cell {
                        dayCell(day)
                    } else {
                        Color.clear.frame(height: 46)
                    }
                }
            }
        }
    }

    private func dayCell(_ day: TrainingDay) -> some View {
        let selected = day.key == selectedKey
        return Button { onSelect(day) } label: {
            VStack(spacing: 3) {
                Text(verbatim: day.date.formatted(.dateTime.day()))
                    .font(StrandFont.number(16))
                    .foregroundStyle(selected ? StrandPalette.surfaceBase : StrandPalette.textPrimary)
                TrainingDayMarks(day: day, size: 7)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(selected ? StrandPalette.textPrimary : Color.clear,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                if day.isToday && !selected {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(StrandPalette.accent, lineWidth: 1.5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The month's three totals: lift sessions done / planned, cardio activities, time spent.
struct TrainingMonthTotals: View {
    let done: Int
    let planned: Int
    let activities: Int
    let minutes: Int

    var body: some View {
        HStack(spacing: 8) {
            tile(planned > 0 ? "\(done) / \(planned)" : "\(done)", "lift sessions")
            tile("\(activities)", "cardio")
            tile(SleepDurationText.format(Double(minutes)), "in total")
        }
    }

    private func tile(_ value: String, _ caption: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: value)
                .font(StrandFont.number(22, weight: .bold))
                .foregroundStyle(StrandPalette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(caption)
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NoopPanelSurface(cornerRadius: NoopVisualStyle.compactRadius))
    }
}

/// The chosen day: the planned program (with Start and Swap today), then what was done. A day with
/// nothing planned and nothing done says so in one line. Fork chantier 7: the day's title in 20 bold, the
/// planned card with its icon alone and "Planned today" in blue, the empty-day line inside that card under a
/// hairline, and the sessions done as cards with their icon alone.
struct TrainingDaySection: View {
    let day: TrainingDay
    /// The planned program, when the plan has one on this day and it still exists.
    let planned: TrainingProgramSummary?
    /// The other programs Swap offers (today only).
    let others: [TrainingProgramSummary]
    /// A Lift Log session is running: Start becomes "Running" and opens it.
    let isRunning: Bool
    var onStart: (String) -> Void = { _ in }
    var onOpenLift: (TrainingLiftDone) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: TrainingText.dayTitle(day))
                .font(StrandFont.sectionTitle)
                .foregroundStyle(StrandPalette.textPrimary)
                .padding(.top, 6)
                .accessibilityAddTraits(.isHeader)
            if let planned, !day.hasLift {
                plannedCard(planned)
            } else if let emptyNote {
                NoopCard { note(emptyNote) }
            }
            ForEach(Array(day.lifts.enumerated()), id: \.offset) { _, lift in
                Button { onOpenLift(lift) } label: {
                    doneRow(symbol: "dumbbell.fill", tint: StrandPalette.effortColor, title: lift.name,
                            line: TrainingText.liftLine(lift), chevron: true)
                }
                .buttonStyle(.plain)
            }
            ForEach(Array(day.activities.enumerated()), id: \.offset) { _, activity in
                doneRow(symbol: "figure.run", tint: StrandPalette.metricRose, title: activity.sport,
                        line: TrainingText.activityLine(activity), chevron: false)
            }
        }
    }

    /// The line of a day with nothing done, or nil when the day needs none (something was done, or a
    /// future day already shows its planned card).
    private var emptyNote: LocalizedStringKey? {
        guard !day.hasLift && !day.hasActivity else { return nil }
        if day.isToday { return "Nothing done today yet." }
        if day.isPast { return "Nothing logged that day." }
        if planned == nil { return "Rest day." }
        return nil
    }

    private func note(_ text: LocalizedStringKey) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "clock")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(StrandPalette.textSecondary)
                .accessibilityHidden(true)
            Text(text)
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textSecondary)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private var plannedLabel: some View {
        if day.isMissed {
            Text("Missed")
        } else if day.isToday {
            Text("Planned today")
        } else {
            Text("Planned")
        }
    }

    private func plannedCard(_ program: TrainingProgramSummary) -> some View {
        NoopCard(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(day.isMissed ? StrandPalette.textTertiary : StrandPalette.effortColor)
                        .frame(width: 28, height: 28)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        plannedLabel
                            .font(StrandFont.overline)
                            .foregroundStyle(day.isMissed ? StrandPalette.statusWarning : StrandPalette.effortColor)
                        Text(verbatim: program.name)
                            .font(StrandFont.title2.weight(.bold))
                            .foregroundStyle(StrandPalette.textPrimary)
                        let line = TrainingText.plannedLine(program)
                        if !line.isEmpty {
                            Text(verbatim: line)
                                .font(StrandFont.footnote)
                                .foregroundStyle(StrandPalette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
                if !program.blocks.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(program.blocks.enumerated()), id: \.offset) { _, block in
                            HStack(alignment: .firstTextBaseline) {
                                Text(verbatim: block.text)
                                    .foregroundStyle(StrandPalette.textPrimary)
                                    .lineLimit(2)
                                Spacer(minLength: 8)
                                if let sets = block.sets, sets > 0 {
                                    Text("\(sets) ×").foregroundStyle(StrandPalette.textSecondary)
                                }
                            }
                        }
                        if program.blockCount > program.blocks.count {
                            Text("+ \(program.blockCount - program.blocks.count) more")
                                .foregroundStyle(StrandPalette.textSecondary)
                        }
                    }
                    .font(StrandFont.subhead)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(StrandPalette.surfaceInset,
                                in: RoundedRectangle(cornerRadius: NoopVisualStyle.compactRadius, style: .continuous))
                }
                if day.isToday {
                    HStack(spacing: 10) {
                        Button { onStart(program.id) } label: {
                            Group {
                                if isRunning {
                                    Label("Running", systemImage: "timer")
                                } else {
                                    Label("Start", systemImage: "play.fill")
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(NoopButtonStyle(.primary, fullWidth: true))
                        if !others.isEmpty && !isRunning {
                            TrainingMenu {
                                ForEach(others) { other in
                                    Button { onStart(other.id) } label: { Text(verbatim: other.name) }
                                }
                            } label: {
                                Label("Swap", systemImage: "arrow.left.arrow.right")
                                    .font(StrandFont.headline)
                                    .foregroundStyle(StrandPalette.textPrimary)
                                    .padding(.horizontal, 20)
                                    .frame(minHeight: NoopButtonMetrics.height)
                                    .background(StrandPalette.surfaceOverlay,
                                                in: RoundedRectangle(cornerRadius: NoopButtonMetrics.cornerRadius,
                                                                     style: .continuous))
                                    .contentShape(RoundedRectangle(cornerRadius: NoopButtonMetrics.cornerRadius,
                                                                   style: .continuous))
                            }
                            .fixedSize()
                        }
                    }
                }
                if let emptyNote {
                    Rectangle()
                        .fill(StrandPalette.hairline)
                        .frame(height: NoopMetrics.hairlineWidth)
                    note(emptyNote)
                }
            }
        }
    }

    private func doneRow(symbol: String, tint: Color, title: String, line: String, chevron: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .font(StrandFont.body.weight(.medium))
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(verbatim: line)
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(StrandPalette.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NoopPanelSurface())
        .contentShape(Rectangle())
    }
}

/// "Programs   Plan": each program with its planned days, then New and Import (Excel). Fork chantier 7:
/// the title in 20 bold, rows of 16 medium / 13 grey, the planned days as plain grey text, a flat card.
struct TrainingProgramsCard: View {
    let programs: [TrainingProgramSummary]
    let plan: TrainingWeekPlan
    let weekdays: [String]
    let loaded: Bool
    var onEdit: (String) -> Void = { _ in }
    var onNew: () -> Void = {}
    var onImport: () -> Void = {}
    var onPlan: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Programs")
                    .font(StrandFont.sectionTitle)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if !programs.isEmpty {
                    Button("Plan", action: onPlan)
                        .font(StrandFont.subhead.weight(.medium))
                        .foregroundStyle(StrandPalette.accent)
                        .buttonStyle(.plain)
                        .frame(minHeight: 32)
                }
            }
            .padding(.top, 6)
            VStack(spacing: 0) {
                if !loaded {
                    message("Reading your programs…", detail: nil)
                } else if programs.isEmpty {
                    message("No programs yet",
                            detail: "A program is a name and an ordered list of exercises with your targets — working sets, reps, weight, rest and your own technique note.")
                } else {
                    ForEach(programs) { program in
                        Button { onEdit(program.id) } label: { programRow(program) }
                            .buttonStyle(.plain)
                    }
                }
                HStack(spacing: 16) {
                    footerButton("New program", symbol: "plus", action: onNew)
                    Spacer(minLength: 0)
                    footerButton("Import (Excel)", symbol: "square.and.arrow.down", action: onImport)
                }
                .padding(.horizontal, 18)
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NoopPanelSurface())
        }
    }

    private var divider: some View {
        Rectangle().fill(StrandPalette.hairline).frame(height: NoopMetrics.hairlineWidth)
    }

    private func message(_ title: LocalizedStringKey, detail: LocalizedStringKey?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(StrandFont.body.weight(.medium))
                .foregroundStyle(StrandPalette.textPrimary)
            if let detail {
                Text(detail)
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { divider }
        .padding(.horizontal, 18)
    }

    private func programRow(_ program: TrainingProgramSummary) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: program.name)
                    .font(StrandFont.body.weight(.medium))
                    .foregroundStyle(StrandPalette.textPrimary)
                let line = TrainingText.programLine(program)
                if !line.isEmpty {
                    Text(verbatim: line)
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
            }
            Spacer(minLength: 8)
            ForEach(plan.plannedWeekdays(of: program.id), id: \.self) { weekday in
                Text(verbatim: weekdays.indices.contains(weekday - 1) ? weekdays[weekday - 1] : "")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(StrandPalette.textTertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { divider }
        .padding(.horizontal, 18)
    }

    private func footerButton(_ title: LocalizedStringKey, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(StrandFont.subhead.weight(.medium))
                .foregroundStyle(StrandPalette.accent)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The Progression block of the Training screen: "Progression   See" in 20 bold, then the four counts in a
/// flat card; the whole block opens the Progression screen. The render tests draw it without its link
/// (`trainingMenusAsLabels`), since a link outside a navigation stack draws dimmed.
struct TrainingProgressSummaryCard<Destination: View>: View {
    let data: LiftProgressData
    @ViewBuilder let destination: () -> Destination
    // Not private: a private stored property would make the memberwise init private.
    @Environment(\.trainingMenusAsLabels) var drawsLabelOnly

    var body: some View {
        if drawsLabelOnly {
            summary
        } else {
            NavigationLink {
                destination()
            } label: {
                summary
            }
            .buttonStyle(.plain)
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Progression")
                    .font(StrandFont.sectionTitle)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Text("See")
                    .font(StrandFont.subhead.weight(.medium))
                    .foregroundStyle(StrandPalette.accent)
            }
            .padding(.top, 6)
            LiftStatusCounters(data: data)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(NoopPanelSurface())
        }
        .contentShape(Rectangle())
    }
}

/// One row of "Other activities": the icon alone in its colour, a title, one line, a chevron, and a
/// hairline under it unless it is the last row.
struct TrainingActivityRowLabel: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let symbol: String
    let tint: Color
    var showsDivider = true

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(StrandFont.body.weight(.medium))
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(detail)
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(StrandPalette.textTertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if showsDivider {
                Rectangle().fill(StrandPalette.hairline).frame(height: NoopMetrics.hairlineWidth)
            }
        }
        .padding(.horizontal, 18)
    }
}
