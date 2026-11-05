import SwiftUI
import StrandDesign

// MARK: - Training screen parts (personal fork)
//
// The pure parts of the Training screen (mockup « NOOP – Entraînement et Plus », then « Entraînement
// proposé » in chantier 9): header, week strip, month grid, one-line legend, the chosen day's single card
// (planned programs with their loads to raise, planned cardio with its Start, what was done), the programs
// card, the compact Progression card, the Other activities rows and the month totals. They take loaded
// models and closures only, so the render test draws them with sample data; the store, the session
// controller and the navigation stay in `LiftLogView`.

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

    /// "November 2026", capitalised.
    static func monthTitle(_ date: Date) -> String {
        let text = date.formatted(.dateTime.month(.wide).year())
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// The day card's title (fork chantier 9): "Today", else "Monday 2 November".
    static func dayCardTitle(_ day: TrainingDay) -> String {
        guard !day.isToday else { return String(localized: "Today") }
        let text = day.date.formatted(.dateTime.weekday(.wide).day().month(.wide))
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// Beside the day card's title: today's date, then what is planned and what was done ("Wed 4 Nov · 2
    /// planned", "2 planned · 1 done"); empty for a day with neither, other than today.
    static func dayCount(_ day: TrainingDay) -> String {
        var parts: [String] = []
        if day.isToday { parts.append(day.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))) }
        let planned = day.planned.count
        if planned > 0 {
            parts.append(planned == 1 ? String(localized: "1 planned") : String(localized: "\(planned) planned"))
        }
        let done = day.lifts.count + day.activities.count
        if done > 0 {
            parts.append(done == 1 ? String(localized: "1 done") : String(localized: "\(done) done"))
        }
        return parts.joined(separator: " · ")
    }

    /// A load to raise: "Leg curl: 60 → 62.5 kg today", or "… next time" on a later day. The weights in the
    /// locale's decimal style.
    static func raiseLine(_ raise: TrainingRaise, today: Bool, system: UnitSystem) -> String {
        let from = weightNumber(raise.fromKg, system: system)
        let to = weightNumber(raise.toKg, system: system)
        let unit = LiftFormat.weightUnit(system)
        return today
            ? String(localized: "\(raise.exercise): \(from) → \(to) \(unit) today")
            : String(localized: "\(raise.exercise): \(from) → \(to) \(unit) next time")
    }

    /// A weight in the wearer's unit, up to two decimals, in the locale's decimal style ("62,5").
    static func weightNumber(_ kg: Double, system: UnitSystem) -> String {
        LiftFormat.display(fromKilograms: kg, system: system).formatted(.number.precision(.fractionLength(0...2)))
    }

    /// Planned cardio's line: "Target: 30 min", then "not done yet" today or "Missed" once the day is over.
    static func cardioLine(minutes: Int, day: TrainingDay) -> String {
        var parts: [String] = []
        if minutes > 0 { parts.append(String(localized: "Target: \(minutes) min")) }
        if day.isToday { parts.append(String(localized: "not done yet")) }
        if day.isPast { parts.append(String(localized: "Missed")) }
        return parts.joined(separator: " · ")
    }

    /// The header's period (fork chantier 9): "2–8 Nov" (the month on both ends when the week spans two).
    static func compactWeekTitle(monday: Date, calendar: Calendar) -> String {
        let sunday = calendar.date(byAdding: .day, value: 6, to: monday) ?? monday
        let sameMonth = calendar.component(.month, from: monday) == calendar.component(.month, from: sunday)
        let start = sameMonth ? monday.formatted(.dateTime.day())
            : monday.formatted(.dateTime.day().month(.abbreviated))
        return start + "–" + sunday.formatted(.dateTime.day().month(.abbreviated))
    }

    /// The header's count: "1 / 5" against the plan, "1 session(s)" without one.
    static func compactTally(done: Int, planned: Int) -> String {
        planned > 0 ? "\(done) / \(planned)" : String(localized: "\(done) sessions")
    }

    /// « All history »'s line: "last: lifting + Running, Mon 2 Nov", or what it holds when nothing was done.
    static func latestDoneLine(_ latest: TrainingLatestDone?) -> String {
        guard let latest else { return String(localized: "lifting and cardio") }
        var kinds: [String] = []
        if latest.hasLift { kinds.append(String(localized: "lifting")) }
        kinds += latest.sports.map { WorkoutSource.displaySport($0) }
        let what = kinds.joined(separator: " + ")
        return String(localized: "last: \(what), \(shortDate(latest.startTs))")
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
/// grey line naming the period shown and its count, with ‹ › to move to the previous or next period. In
/// the iOS tab shell (fork chantier 9): the title and the avatar, then the switch with ‹ period · count ›.
struct TrainingHeader: View {
    @Binding var mode: TrainingViewMode
    /// "2–8 Nov · 0 / 3".
    let subtitle: String
    var onPrevious: () -> Void = {}
    var onNext: () -> Void = {}
    /// The iOS tab shell puts the More avatar beside the title, which leaves no room for the Week | Month
    /// switch there: it moves to its own line, with ‹ › (fork chantier 9). Not `private`: that would make
    /// the memberwise initializer the screens call private too.
    @Environment(\.showsMoreAvatar) var showsMoreAvatar

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
                if showsMoreAvatar {
                    MoreAvatarButton()
                } else {
                    TrainingModeSwitch(mode: $mode)
                }
            }
            if showsMoreAvatar {
                // Fork chantier 9: the period and its count between ‹ › ("‹ 2–8 Nov · 1 / 5 ›").
                HStack(spacing: 0) {
                    TrainingModeSwitch(mode: $mode)
                    Spacer(minLength: 4)
                    TrainingPeriodArrow(symbol: "chevron.left", label: "Previous", action: onPrevious)
                    Text(verbatim: subtitle)
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    TrainingPeriodArrow(symbol: "chevron.right", label: "Next", action: onNext)
                }
                .padding(.vertical, 6)
            } else {
                periodLine
            }
        }
    }

    /// The period with its count, then ‹ › — the header's second line outside the iOS tab shell.
    private var periodLine: some View {
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

/// The marks of a day: outlined blue = lift planned, filled blue = lift done, outlined pink = cardio
/// planned, filled pink = cardio done. A missed item keeps its outline, greyed.
struct TrainingDayMarks: View {
    let day: TrainingDay
    var size: CGFloat = 8

    var body: some View {
        HStack(spacing: 3) {
            if day.hasOpenLift {
                Circle().strokeBorder(day.isPast ? StrandPalette.textTertiary : StrandPalette.effortColor, lineWidth: 2)
                    .frame(width: size, height: size)
            }
            if day.hasLift {
                Circle().fill(StrandPalette.effortColor).frame(width: size, height: size)
            }
            if day.hasOpenCardio {
                Circle().strokeBorder(day.isPast ? StrandPalette.textTertiary : StrandPalette.metricRose, lineWidth: 2)
                    .frame(width: size, height: size)
            }
            if day.hasActivity {
                Circle().fill(StrandPalette.metricRose).frame(width: size, height: size)
            }
        }
        .frame(height: size)
    }
}

/// The legend under the week strip and the month grid, on one line (fork chantier 9): lifting in blue,
/// cardio in pink, then a filled mark for done and an outlined one for planned.
struct TrainingLegend: View {
    var body: some View {
        HStack(spacing: 14) {
            item(Circle().fill(StrandPalette.effortColor), "lifting")
            item(Circle().fill(StrandPalette.metricRose), "cardio")
            HStack(spacing: 5) {
                Circle().fill(StrandPalette.textSecondary).frame(width: 8, height: 8)
                Text("done")
                Text(verbatim: "·")
                Circle().strokeBorder(StrandPalette.textSecondary, lineWidth: 1.5).frame(width: 8, height: 8)
                Text("planned")
            }
        }
        .font(StrandFont.caption)
        .foregroundStyle(StrandPalette.textSecondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, 2)
    }

    private func item<S: View>(_ mark: S, _ title: LocalizedStringKey) -> some View {
        HStack(spacing: 5) {
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

    /// Fork chantier 12: the white pill of the chosen day slides to the next one picked.
    @Namespace private var pill
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var motion = NoopMotionState.shared

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
                    .background {
                        ZStack {
                            RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                                .fill(StrandPalette.surfaceRaised)
                            if selected {
                                RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                                    .fill(StrandPalette.textPrimary)
                                    .matchedGeometryEffect(id: "chosen-day", in: pill)
                            }
                        }
                    }
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
        .animation(NoopMotion.gated(NoopMotion.card, reduced: motion.poseStill(reduceMotion)), value: selectedKey)
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

/// The month's three totals: sessions done / planned (lifts and planned cardio, `TrainingDays.sessionTally`),
/// cardio activities, time spent.
struct TrainingMonthTotals: View {
    let done: Int
    let planned: Int
    let activities: Int
    let minutes: Int

    var body: some View {
        HStack(spacing: 8) {
            tile(planned > 0 ? "\(done) / \(planned)" : "\(done)", "sessions")
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

/// The chosen day in ONE card (fork chantier 9, section 5): above it the day's name ("Today", "Monday 2
/// November") and its count ("Wed 4 Nov · 2 planned"); in it each program still to do in large — shape,
/// ≈ usual length, last time, its first blocks, the loads to raise (« ↑ Leg curl: 60 → 62.5 kg today »), Start
/// and Swap today — then each cardio still to do on one line with its own Start (today), then what was done
/// (a Lift Log session opens its detail), each under a hairline. A day with nothing planned and nothing done
/// says so in one line.
struct TrainingDaySection: View {
    let day: TrainingDay
    /// The saved programs (the planned blocks read theirs by id).
    let programs: [TrainingProgramSummary]
    /// The other programs Swap offers (today only).
    let others: [TrainingProgramSummary]
    /// A Lift Log session is running: Start becomes "Running" and opens it.
    let isRunning: Bool
    var unitSystem: UnitSystem = .metric
    var onStart: (String) -> Void = { _ in }
    /// Starts the live workout of planned cardio (its stored sport name).
    var onStartCardio: (String) -> Void = { _ in }
    var onOpenLift: (TrainingLiftDone) -> Void = { _ in }

    /// One row of the card, in the order drawn.
    private enum Row {
        case program(TrainingProgramSummary)
        case cardio(sport: String, minutes: Int)
        case lift(TrainingLiftDone)
        case activity(TrainingActivityDone)
        case note(LocalizedStringKey)
    }

    /// Planned items still to do (programs that still exist, then cardio, each in the plan's order), then
    /// what was done, or the empty-day line.
    private var rows: [Row] {
        let open = day.openItems
        var rows: [Row] = open.compactMap { item -> Row? in
            guard let id = item.programId else { return nil }
            return programs.first(where: { $0.id == id }).map(Row.program)
        }
        rows += open.compactMap { item -> Row? in
            if case .cardio(let sport, let minutes) = item { return .cardio(sport: sport, minutes: minutes) }
            return nil
        }
        rows += day.lifts.map(Row.lift)
        rows += day.activities.map(Row.activity)
        if rows.isEmpty, let emptyNote { rows.append(.note(emptyNote)) }
        return rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: TrainingText.dayCardTitle(day))
                    .font(StrandFont.sectionTitle)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                let count = TrainingText.dayCount(day)
                if !count.isEmpty {
                    Text(verbatim: count)
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .padding(.top, 6)
            .padding(.horizontal, 4)
            NoopCard(padding: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    let all = rows
                    ForEach(Array(all.enumerated()), id: \.offset) { index, row in
                        if index > 0 { hairline }
                        rowView(row)
                    }
                }
            }
        }
    }

    @ViewBuilder private func rowView(_ row: Row) -> some View {
        switch row {
        case .program(let program): programBlock(program)
        case .cardio(let sport, let minutes): cardioRow(sport: sport, minutes: minutes)
        case .lift(let lift):
            Button { onOpenLift(lift) } label: {
                doneRow(symbol: "dumbbell.fill", tint: StrandPalette.effortColor, title: lift.name,
                        line: TrainingText.liftLine(lift), chevron: true)
            }
            .buttonStyle(.plain)
        case .activity(let activity):
            doneRow(symbol: "figure.run", tint: StrandPalette.metricRose,
                    title: WorkoutSource.displaySport(activity.sport),
                    line: TrainingText.activityLine(activity), chevron: false)
        case .note(let text): note(text)
        }
    }

    private var hairline: some View {
        Rectangle()
            .fill(StrandPalette.hairline)
            .frame(height: NoopMetrics.hairlineWidth)
    }

    /// The line of a day with nothing planned still to do and nothing done.
    private var emptyNote: LocalizedStringKey? {
        if day.isToday { return "Nothing done today yet." }
        if day.isPast { return "Nothing logged that day." }
        return "Rest day."
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

    /// A program still to do: its name in large, its first blocks, the loads to raise, Start and Swap today.
    private func programBlock(_ program: TrainingProgramSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(day.isMissed ? StrandPalette.textTertiary : StrandPalette.effortColor)
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    if day.isMissed {
                        Text("Missed")
                            .font(StrandFont.overline)
                            .foregroundStyle(StrandPalette.statusWarning)
                    }
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
            let raises = day.isPast ? [] : program.raises
            if !program.blocks.isEmpty || !raises.isEmpty {
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
                    ForEach(Array(raises.enumerated()), id: \.offset) { _, raise in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 12, weight: .bold))
                                .accessibilityHidden(true)
                            Text(verbatim: TrainingText.raiseLine(raise, today: day.isToday, system: unitSystem))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .foregroundStyle(StrandPalette.effortBright)
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
        }
    }

    /// Planned cardio on one line: the sport in the app's language, its target length (a guide: an
    /// activity of the same sport that day ticks it, whatever its length) and, today, its own Start.
    private func cardioRow(sport: String, minutes: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "figure.run")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(day.isMissed ? StrandPalette.textTertiary : StrandPalette.metricRose)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: WorkoutCatalog.shownSportName(sport))
                    .font(StrandFont.body.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(verbatim: TrainingText.cardioLine(minutes: minutes, day: day))
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            Spacer(minLength: 8)
            if day.isToday {
                Button { onStartCardio(sport) } label: {
                    Text("Start")
                        .font(StrandFont.subhead.weight(.semibold))
                        .foregroundStyle(StrandPalette.metricRose)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 36)
                        .background(StrandPalette.surfaceOverlay, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func doneRow(symbol: String, tint: Color, title: String, line: String, chevron: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28)
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
        .frame(maxWidth: .infinity, alignment: .leading)
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

/// The Progression block of the Training screen (fork chantier 9: one compact card): "Progression   See ›"
/// inside it, then the four counts, each number in its status colour beside its arrow; the whole card opens
/// the Progression screen. The render tests draw it without its link (`trainingMenusAsLabels`), since a
/// link outside a navigation stack draws dimmed.
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
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    Text("See")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .accessibilityHidden(true)
                }
                .font(StrandFont.subhead.weight(.medium))
                .foregroundStyle(StrandPalette.accent)
            }
            HStack(alignment: .top, spacing: 8) {
                ForEach([3, 2, 0, 1], id: \.self) { rank in
                    let status = LiftProgressText.sample(rank)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            LiftStatusIcon(status: status, size: 15)
                            Text(verbatim: "\(data.count(rank))")
                                .font(StrandFont.number(22, weight: .bold))
                                .foregroundStyle(status.tint)
                        }
                        Text(LiftProgressText.counterLabel(rank))
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .accessibilityElement(children: .combine)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NoopPanelSurface())
        .contentShape(Rectangle())
    }
}

/// One row of "Other activities" (fork chantier 9: the card has no title; each row a dot in its colour):
/// the dot, a title, one line, a chevron, and a hairline under it unless it is the last row.
struct TrainingActivityRowLabel: View {
    private let title: LocalizedStringKey
    private let detail: Text
    private let tint: Color
    private let showsDivider: Bool

    init(title: LocalizedStringKey, detail: LocalizedStringKey, tint: Color, showsDivider: Bool = true) {
        self.title = title
        self.detail = Text(detail)
        self.tint = tint
        self.showsDivider = showsDivider
    }

    /// A line built by the screen ("last: lifting + Running, Mon 2 Nov"), already worded.
    init(title: LocalizedStringKey, line: String, tint: Color, showsDivider: Bool = true) {
        self.title = title
        self.detail = Text(verbatim: line)
        self.tint = tint
        self.showsDivider = showsDivider
    }

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(tint)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(StrandFont.body.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                detail
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
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if showsDivider {
                Rectangle().fill(StrandPalette.hairline).frame(height: NoopMetrics.hairlineWidth)
            }
        }
        .padding(.horizontal, 18)
    }
}
