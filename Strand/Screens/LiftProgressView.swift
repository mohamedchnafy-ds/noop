import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

// The Lift Log's Progression (personal fork): the card on the Lift Log and the screen it opens, with its
// three tabs — Exercises (what moves, what stalls), Muscles (body map, priorities, balances) and Form (the
// day's Charge and the night before against how a session went). Design: « NOOP – Progression (Carnet de
// force) ». Every figure comes from `LiftProgress`; nothing here computes a rule of its own.

// MARK: - Card on the Lift Log

struct LiftProgressCard: View {
    let data: LiftProgressData
    let unitSystem: UnitSystem

    private var period: LiftProgress.Period { .fourWeeks }

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            HStack(spacing: NoopMetrics.space2) {
                Text("Progression").strandOverline()
                Spacer(minLength: NoopMetrics.space2)
                Text("Last 4 weeks")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            NoopCard(tint: StrandPalette.effortColor) {
                if data.isEmpty {
                    VStack(alignment: .leading, spacing: NoopMetrics.space4) {
                        Text("Your progression shows here after a few sessions: what is moving, what has stalled and which muscles need more work.")
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        LiftDivider()
                        seeProgression
                    }
                } else {
                    content
                }
            }
        }
    }

    private var content: some View {
        let ready = data.readyExercises
        let priorities = data.priorities(period)
        return VStack(alignment: .leading, spacing: NoopMetrics.space4) {
            LiftStatusCounters(data: data)
            if !ready.isEmpty {
                LiftDivider()
                VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                    HStack(spacing: NoopMetrics.space2) {
                        LiftStatusIcon(status: .ready(fromKg: 0, toKg: 0), size: 11)
                        Text("Loads to raise").strandOverline()
                    }
                    ForEach(ready, id: \.name) { exercise in
                        if let step = exercise.status.step {
                            HStack(spacing: NoopMetrics.space2) {
                                Text(readyName(exercise))
                                    .font(StrandFont.subhead)
                                    .foregroundStyle(StrandPalette.textPrimary)
                                    .lineLimit(1)
                                Spacer(minLength: NoopMetrics.space2)
                                Text(verbatim: LiftProgressText.step(step.from, step.to, system: unitSystem))
                                    .font(StrandFont.number(15))
                                    .foregroundStyle(StrandPalette.textPrimary)
                            }
                        }
                    }
                }
            }
            if !priorities.isEmpty {
                LiftDivider()
                HStack(spacing: NoopMetrics.space3) {
                    let hot = Set(priorities.map(\.muscle))
                    let weekly = data.weekly(period)
                    HStack(spacing: 2) {
                        LiftBodyMap(side: .front, sets: weekly, highlighted: hot).frame(width: 40)
                        LiftBodyMap(side: .back, sets: weekly, highlighted: hot).frame(width: 40)
                    }
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                        HStack(spacing: NoopMetrics.space2) {
                            LiftPriorityMark()
                            Text("To prioritise").strandOverline()
                        }
                        Text(priorities.map(\.muscle.displayName).joined(separator: ", "))
                            .font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            LiftDivider()
            seeProgression
        }
    }

    /// The way into the Progression screen, open even before the first session so its tabs can be seen.
    private var seeProgression: some View {
        NavigationLink {
            LiftProgressView(data: data, unitSystem: unitSystem)
        } label: {
            HStack {
                Text("See progression")
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.effortBright)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(StrandPalette.effortBright)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func readyName(_ exercise: LiftProgress.Exercise) -> String {
        guard let program = exercise.line?.programName else { return exercise.name }
        return "\(exercise.name) · \(program)"
    }
}

/// The four counts: progressing, ready to go up, stalled, declining.
struct LiftStatusCounters: View {
    let data: LiftProgressData

    var body: some View {
        HStack(alignment: .top, spacing: NoopMetrics.space2) {
            ForEach([3, 2, 0, 1], id: \.self) { rank in
                VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                    HStack(spacing: 6) {
                        LiftStatusIcon(status: LiftProgressText.sample(rank))
                        Text(verbatim: "\(data.count(rank))")
                            .font(StrandFont.number(24, weight: .bold))
                            .foregroundStyle(StrandPalette.textPrimary)
                    }
                    Text(LiftProgressText.counterLabel(rank))
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A hairline between the blocks of a card.
struct LiftDivider: View {
    var body: some View {
        Rectangle().fill(StrandPalette.hairline).frame(height: 1).accessibilityHidden(true)
    }
}

/// The small outlined square that marks a muscle to prioritise.
struct LiftPriorityMark: View {
    var fill: Color = .clear
    var size: CGFloat = 11

    var body: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(fill)
            .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(StrandPalette.statusWarning, lineWidth: 2))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// An overline title with something on its right, above a card.
struct LiftSectionTitle<Trailing: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: NoopMetrics.space2) {
            Text(title).strandOverline()
            Spacer(minLength: NoopMetrics.space2)
            trailing()
        }
        .frame(minHeight: 28)
    }
}

extension LiftProgress.Status {
    /// The load step of a `ready` status.
    var step: (from: Double, to: Double)? {
        if case let .ready(from, to) = self { return (from, to) }
        return nil
    }
}

extension LiftProgressText {
    /// "40 → 42.5 kg".
    static func step(_ from: Double, _ to: Double, system: UnitSystem) -> String {
        "\(LiftFormat.trim(LiftFormat.display(fromKilograms: from, system: system))) → \(LiftFormat.weight(to, system: system))"
    }

    static func periodLabel(_ period: LiftProgress.Period) -> String {
        switch period {
        case .fourWeeks: return String(localized: "4 wk")
        case .twelveWeeks: return String(localized: "12 wk")
        case .all: return String(localized: "All")
        }
    }
}

// MARK: - The Progression screen

struct LiftProgressView: View {
    enum Tab: Hashable { case exercises, muscles, form }

    let data: LiftProgressData
    let unitSystem: UnitSystem

    @State private var tab: Tab = .exercises
    @State private var period: LiftProgress.Period = .fourWeeks
    @State private var musclePeriod: LiftProgress.Period = .fourWeeks
    @State private var openMuscle: LiftMuscleTarget?

    var body: some View {
        ScreenScaffold(title: "Progression") {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                SegmentedPillControl([Tab.exercises, Tab.muscles, Tab.form], selection: $tab,
                                     fillsAvailableWidth: true) { tab in
                    switch tab {
                    case .exercises: return String(localized: "Exercises")
                    case .muscles: return String(localized: "Muscles")
                    case .form: return String(localized: "Form")
                    }
                }
                switch tab {
                case .exercises:
                    LiftProgressExercisesTab(data: data, unitSystem: unitSystem, period: $period)
                case .muscles:
                    LiftProgressMusclesTab(data: data, period: $musclePeriod) { openMuscle = LiftMuscleTarget(muscle: $0) }
                case .form:
                    LiftProgressFormTab(data: data)
                }
            }
        }
        .sheet(item: $openMuscle) { target in
            LiftMuscleProgressSheet(muscle: target.muscle, data: data, period: musclePeriod, unitSystem: unitSystem)
        }
    }
}

/// The muscle whose sheet is open.
struct LiftMuscleTarget: Identifiable {
    let muscle: LiftMuscle
    var id: String { muscle.rawValue }
}

// MARK: - Exercises tab

struct LiftProgressExercisesTab: View {
    let data: LiftProgressData
    let unitSystem: UnitSystem
    @Binding var period: LiftProgress.Period

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
            VStack(alignment: .leading, spacing: NoopMetrics.gap) {
                LiftSectionTitle(title: "Progress summary") {
                    SegmentedPillControl(LiftProgress.Period.allCases, selection: $period) {
                        LiftProgressText.periodLabel($0)
                    }
                    .fixedSize()
                }
                NoopCard {
                    VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                        LiftStatusCounters(data: data)
                        LiftDivider()
                        HStack {
                            stat(String(localized: "Records"), LiftProgress.recordCount(data.exercises, in: period, now: data.now))
                            Spacer()
                            stat(String(localized: "Sessions"), sessionCount)
                        }
                    }
                }
            }

            ForEach(LiftProgressText.ranks, id: \.self) { rank in
                let group = data.group(rank)
                if !group.isEmpty {
                    VStack(alignment: .leading, spacing: NoopMetrics.gap) {
                        HStack(spacing: NoopMetrics.space2) {
                            LiftStatusIcon(status: LiftProgressText.sample(rank))
                            Text(verbatim: "\(LiftProgressText.groupTitle(rank)) · \(group.count)").strandOverline()
                        }
                        NoopCard(padding: 0) {
                            VStack(spacing: 0) {
                                ForEach(Array(group.enumerated()), id: \.element.name) { index, exercise in
                                    if index > 0 { LiftDivider().padding(.horizontal, NoopMetrics.cardPadding) }
                                    NavigationLink {
                                        LiftExerciseProgressView(exercise: exercise, now: data.now, unitSystem: unitSystem)
                                    } label: {
                                        LiftExerciseProgressRow(exercise: exercise, period: period, now: data.now,
                                                                unitSystem: unitSystem)
                                            .padding(.horizontal, NoopMetrics.cardPadding)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }

            if data.exercises.isEmpty {
                NoopCard {
                    Text("No session yet. After your first session, each exercise shows here; its status comes after 3 sessions.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            let waiting = data.group(LiftProgress.Status.notEnough(sessions: 0).rank)
            if !waiting.isEmpty {
                NoopCard {
                    HStack(alignment: .top, spacing: NoopMetrics.space3) {
                        LiftStatusIcon(status: .notEnough(sessions: 0), size: 15)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: "\(LiftProgressText.groupTitle(4)) · \(waiting.count)")
                                .font(StrandFont.subhead)
                                .foregroundStyle(StrandPalette.textPrimary)
                            Text(verbatim: waiting.map { "\($0.name) \($0.points.count)/\(LiftProgress.minimumSessions)" }
                                .joined(separator: " · "))
                                .font(StrandFont.caption)
                                .foregroundStyle(StrandPalette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            Text("A record is a weight never lifted before, or more reps at a weight already lifted. The status comes from the last 3 sessions of each exercise; the curve shows the best set of each session.")
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var sessionCount: Int {
        guard let start = period.start(now: data.now) else { return data.sessions.count }
        return data.sessions.filter { $0.row.startTs >= start }.count
    }

    private func stat(_ label: String, _ value: Int) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
            Text(verbatim: "\(value)")
                .font(StrandFont.number(15))
                .foregroundStyle(StrandPalette.textPrimary)
        }
    }
}

/// One exercise in the Exercises tab: name, muscle and program, its curve, and what its status says.
struct LiftExerciseProgressRow: View {
    let exercise: LiftProgress.Exercise
    let period: LiftProgress.Period
    let now: Int
    let unitSystem: UnitSystem

    var body: some View {
        HStack(spacing: NoopMetrics.space3) {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: exercise.name)
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: LiftProgressText.subtitle(exercise))
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                if exercise.status.needsAttention, let last = exercise.points.last {
                    Text(verbatim: LiftProgressText.sets(last.sets, system: unitSystem))
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
            }
            Spacer(minLength: NoopMetrics.space2)
            VStack(alignment: .trailing, spacing: 3) {
                LiftSparkline(values: curve, tint: exercise.status.tint)
                    .frame(width: 64, height: 22)
                Text(verbatim: headline)
                    .font(StrandFont.number(15))
                    .foregroundStyle(exercise.status.tint)
                    .lineLimit(1)
                Text(verbatim: detail)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .lineLimit(1)
            }
            .frame(width: 112, alignment: .trailing)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(StrandPalette.textTertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// The period's values, or the last six sessions when the period holds fewer than two.
    private var curve: [Double] {
        let inPeriod = LiftProgress.points(exercise, in: period, now: now).compactMap(\.value)
        return inPeriod.count >= 2 ? inPeriod : exercise.points.suffix(6).compactMap(\.value)
    }

    private var headline: String {
        switch exercise.status {
        case .stalled(let sessions):
            return String(localized: "\(sessions) sessions")
        case .declining(let percent):
            return LiftProgressText.percent(percent)
        case .ready(let from, let to):
            return LiftProgressText.step(from, to, system: unitSystem)
        case .progressing:
            let change = LiftProgress.change(LiftProgress.points(exercise, in: period, now: now))
            return change.map(LiftProgressText.percent) ?? String(localized: "Record")
        case .notEnough(let sessions):
            return "\(sessions)/\(LiftProgress.minimumSessions)"
        }
    }

    private var detail: String {
        switch exercise.status {
        case .stalled:
            return String(localized: "without a record")
        case .declining:
            return String(localized: "over 2 sessions")
        case .ready:
            let item = exercise.line?.item
            let top = item?.targetRepsHigh ?? item?.targetRepsLow ?? 0
            return String(localized: "\(item?.targetSets ?? 0) × \(top) reached")
        case .progressing, .notEnough:
            guard let last = exercise.points.last else { return "" }
            return LiftProgressText.set(last.bestWeightKg, last.bestReps, system: unitSystem)
        }
    }
}

/// A small line of an exercise's values, its last point marked.
struct LiftSparkline: View {
    let values: [Double]
    let tint: Color

    var body: some View {
        Canvas { ctx, size in
            guard let lo0 = values.min(), let hi0 = values.max() else { return }
            // A flat-ish line stays flat: the scale never zooms in under 15 % of the value.
            let span = max(hi0 - lo0, abs(hi0) * 0.15, 0.0001)
            let lo = (lo0 + hi0) / 2 - span / 2
            let step = values.count > 1 ? (size.width - 6) / CGFloat(values.count - 1) : 0
            let points = values.enumerated().map { index, value in
                CGPoint(x: 3 + CGFloat(index) * step, y: 3 + (size.height - 6) * CGFloat(1 - (value - lo) / span))
            }
            if points.count > 1 {
                var line = Path()
                line.move(to: points[0])
                for p in points.dropFirst() { line.addLine(to: p) }
                ctx.stroke(line, with: .color(tint), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            }
            if let last = points.last {
                ctx.fill(Path(ellipseIn: CGRect(x: last.x - 2.6, y: last.y - 2.6, width: 5.2, height: 5.2)),
                         with: .color(tint))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Muscles tab

struct LiftProgressMusclesTab: View {
    let data: LiftProgressData
    @Binding var period: LiftProgress.Period
    let open: (LiftMuscle) -> Void

    var body: some View {
        let weekly = data.weekly(period)
        let priorities = data.priorities(period)
        let hot = Set(priorities.map(\.muscle))
        return VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
            VStack(alignment: .leading, spacing: NoopMetrics.gap) {
                LiftSectionTitle(title: "Sets per muscle") {
                    SegmentedPillControl([LiftProgress.Period.fourWeeks, LiftProgress.Period.twelveWeeks],
                                         selection: $period) { LiftProgressText.periodLabel($0) }
                        .fixedSize()
                }
                NoopCard {
                    VStack(alignment: .leading, spacing: NoopMetrics.space4) {
                        HStack(alignment: .top, spacing: NoopMetrics.space4) {
                            figure(.front, String(localized: "Front view"), weekly: weekly, hot: hot)
                            figure(.back, String(localized: "Back view"), weekly: weekly, hot: hot)
                        }
                        legend
                    }
                }
                Text("Tap a muscle to see its weeks and its exercises.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
            }

            VStack(alignment: .leading, spacing: NoopMetrics.gap) {
                LiftSectionTitle(title: "To prioritise") {
                    if !priorities.isEmpty {
                        Text(String(localized: "\(priorities.count) muscles"))
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                }
                NoopCard(padding: 0) {
                    if data.isEmpty {
                        Text("After your first sessions, the muscles under the reference or no longer progressing show here.")
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(NoopMetrics.cardPadding)
                    } else if priorities.isEmpty {
                        Text("No muscle to prioritise: every muscle your programs work gets at least 4 sets a week and keeps moving.")
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(NoopMetrics.cardPadding)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(priorities.enumerated()), id: \.element.muscle) { index, priority in
                                if index > 0 { LiftDivider().padding(.horizontal, NoopMetrics.cardPadding) }
                                Button { open(priority.muscle) } label: {
                                    priorityRow(priority)
                                        .padding(.horizontal, NoopMetrics.cardPadding)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            let balances = LiftProgress.BalancePair.allCases.compactMap { pair in
                pair.totals(weekly).map { (pair, $0.left, $0.right) }
            }
            if !balances.isEmpty {
                VStack(alignment: .leading, spacing: NoopMetrics.gap) {
                    LiftSectionTitle(title: "Balances") {
                        Text("sets / week")
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                    NoopCard {
                        VStack(spacing: NoopMetrics.space3) {
                            ForEach(Array(balances.enumerated()), id: \.offset) { index, balance in
                                if index > 0 { LiftDivider() }
                                LiftBalanceRow(pair: balance.0, left: balance.1, right: balance.2)
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                let untargeted = LiftMuscle.allCases.filter { !data.targeted.contains($0) }
                if !untargeted.isEmpty {
                    Text(String(localized: "No exercise in your programs works these directly, so they are never prioritised: \(untargeted.map(\.displayName).joined(separator: ", "))."))
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Counted from the muscles you assigned each exercise: a direct set counts 1, an indirect set ½, averaged per week over the period. Reference 4: below it, studies stop reliably detecting muscle growth. It is not a target.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func figure(_ side: LiftBodyMap.Side, _ label: String, weekly: [LiftMuscle: Double],
                        hot: Set<LiftMuscle>) -> some View {
        VStack(spacing: NoopMetrics.space2) {
            LiftBodyMap(side: side, sets: weekly, highlighted: hot, onTap: open)
                .frame(maxWidth: 150)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(LiftProgressText.mapSummary(weekly)))
            Text(label).strandOverline()
        }
        .frame(maxWidth: .infinity)
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            HStack(spacing: 3) {
                ForEach(Array(LiftBodyMapStyle.bands.enumerated()), id: \.offset) { _, band in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 3).fill(band.color).frame(height: 8)
                        Text(verbatim: band.label)
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            HStack(spacing: NoopMetrics.space3) {
                Text("sets per week · reference: 4")
                HStack(spacing: 6) {
                    LiftPriorityMark()
                    Text("to prioritise")
                }
            }
            .font(StrandFont.caption)
            .foregroundStyle(StrandPalette.textSecondary)
        }
        .accessibilityHidden(true)
    }

    private func priorityRow(_ priority: LiftProgress.Priority) -> some View {
        HStack(spacing: NoopMetrics.space3) {
            LiftPriorityMark(fill: LiftBodyMapStyle.color(priority.setsPerWeek), size: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: priority.muscle.displayName)
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(verbatim: LiftProgressText.reason(priority, data: data))
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: NoopMetrics.space2)
            VStack(alignment: .trailing, spacing: 0) {
                Text(verbatim: LiftProgressText.setCount(priority.setsPerWeek))
                    .font(StrandFont.number(16))
                    .foregroundStyle(StrandPalette.textPrimary)
                Text("sets / week")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(StrandPalette.textTertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Two groups of muscles side by side: their weekly sets, the ratio, and a split bar.
struct LiftBalanceRow: View {
    let pair: LiftProgress.BalancePair
    let left: Double
    let right: Double

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                (Text(verbatim: names.left + " ") + Text(verbatim: LiftProgressText.setCount(left)).bold())
                Spacer()
                Text(verbatim: ratio)
                    .foregroundStyle(StrandPalette.textSecondary)
                Spacer()
                (Text(verbatim: LiftProgressText.setCount(right)).bold() + Text(verbatim: " " + names.right))
            }
            .font(StrandFont.subhead)
            .foregroundStyle(StrandPalette.textPrimary)
            GeometryReader { geo in
                HStack(spacing: 3) {
                    Capsule().fill(StrandPalette.effortColor)
                        .frame(width: max(4, (geo.size.width - 3) * CGFloat(left / (left + right))))
                    Capsule().fill(StrandPalette.effortBright)
                }
            }
            .frame(height: 8)
            .accessibilityHidden(true)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    /// "1.3 : 1", in the user's decimal style.
    private var ratio: String {
        (left / right).formatted(.number.precision(.fractionLength(1))) + " : 1"
    }

    private var names: (left: String, right: String) {
        switch pair {
        case .pushPull: return (String(localized: "Pushing"), String(localized: "Pulling"))
        case .quadsHamstrings: return (LiftMuscle.quads.displayName, LiftMuscle.hamstrings.displayName)
        case .frontRearDelts: return (LiftMuscle.frontDelts.displayName, LiftMuscle.rearDelts.displayName)
        }
    }
}

extension LiftProgressText {
    /// Why a muscle is a priority: "under the reference · Lateral raise stalled".
    static func reason(_ priority: LiftProgress.Priority, data: LiftProgressData) -> String {
        var parts: [String] = []
        if priority.belowReference { parts.append(String(localized: "under the reference")) }
        for name in priority.stuckExercises {
            if case .declining? = data.exercise(named: name)?.status {
                parts.append(String(localized: "\(name) declining"))
            } else {
                parts.append(String(localized: "\(name) stalled"))
            }
        }
        return parts.joined(separator: " · ")
    }

    /// The map read aloud: each worked muscle and its weekly sets.
    static func mapSummary(_ weekly: [LiftMuscle: Double]) -> String {
        LiftMuscle.allCases.compactMap { muscle in
            guard let sets = weekly[muscle], sets > 0 else { return nil }
            return "\(muscle.displayName) \(setCount(sets))"
        }.joined(separator: ", ")
    }
}

// MARK: - Muscle sheet

struct LiftMuscleProgressSheet: View {
    let muscle: LiftMuscle
    let data: LiftProgressData
    let period: LiftProgress.Period
    let unitSystem: UnitSystem
    /// False in the render test, which draws the content whole.
    var scrolls = true

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if scrolls {
            ScrollView { content }
                .background(StrandPalette.surfaceBase)
        } else {
            content
        }
    }

    private var content: some View {
        let weeks = LiftProgress.weekly(muscle, sessions: data.sessions, weeks: 12, now: data.now)
        let average = data.weekly(period)[muscle] ?? 0
        let priority = data.priorities(period).first { $0.muscle == muscle }
        let contributions = LiftProgress.contributions(muscle, sessions: data.sessions, period: period, now: data.now)
        return VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
            HStack(spacing: NoopMetrics.space3) {
                LiftPriorityMark(fill: LiftBodyMapStyle.color(average), size: 16)
                    .opacity(priority == nil ? 0 : 1)
                Text(verbatim: muscle.displayName)
                    .font(StrandFont.title2)
                    .foregroundStyle(StrandPalette.textPrimary)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(StrandPalette.textSecondary)
                        .frame(width: 44, height: 44)
                        .background(StrandPalette.surfaceInset, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Close"))
            }
            Text(verbatim: priority.map { LiftProgressText.reason($0, data: data) }
                 ?? String(localized: "\(LiftProgressText.setCount(average)) sets a week on average"))
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: NoopMetrics.gap) {
                LiftSectionTitle(title: "Sets per week") {
                    Text("12 weeks")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
                NoopCard {
                    VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                        LiftWeeklyBars(values: weeks, reference: LiftMetrics.ReferenceDose.hypertrophyMinimumSetsPerWeek)
                            .frame(height: 110)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(Text(verbatim: weeks.map(LiftProgressText.setCount).joined(separator: ", ")))
                        weekAxis
                        HStack(spacing: NoopMetrics.space4) {
                            HStack(spacing: 6) {
                                Rectangle().fill(StrandPalette.textPrimary.opacity(0.6)).frame(width: 14, height: 2)
                                Text("reference: 4 sets")
                            }
                            Text(String(localized: "mean \(LiftProgressText.setCount(average)) / week"))
                        }
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                    }
                }
            }

            if !contributions.isEmpty {
                VStack(alignment: .leading, spacing: NoopMetrics.gap) {
                    LiftSectionTitle(title: "Exercises") {
                        Text("sets / week")
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                    NoopCard(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(contributions.enumerated()), id: \.element.exercise) { index, item in
                                if index > 0 { LiftDivider().padding(.horizontal, NoopMetrics.cardPadding) }
                                contributionRow(item)
                                    .padding(.horizontal, NoopMetrics.cardPadding)
                            }
                        }
                    }
                }
            }
        }
        .padding(NoopMetrics.screenPadding)
    }

    private var weekAxis: some View {
        let day = 86_400
        let labels = [11, 7, 3, 0].map { LiftProgressText.day(data.now - $0 * 7 * day - 6 * day) }
        return HStack {
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                if index > 0 { Spacer() }
                Text(verbatim: label)
            }
        }
        .font(StrandFont.caption)
        .foregroundStyle(StrandPalette.textSecondary)
        .accessibilityHidden(true)
    }

    private func contributionRow(_ item: LiftProgress.Contribution) -> some View {
        let status = data.exercise(named: item.exercise)?.status
        let program = data.lines[item.exercise]?.programName
        let kind = item.direct ? String(localized: "direct") : String(localized: "indirect (½)")
        return HStack(spacing: NoopMetrics.space3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: item.exercise)
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(verbatim: [kind, program].compactMap { $0 }.joined(separator: " · "))
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            Spacer(minLength: NoopMetrics.space2)
            VStack(alignment: .trailing, spacing: 2) {
                Text(verbatim: LiftProgressText.setCount(item.setsPerWeek))
                    .font(StrandFont.number(15))
                    .foregroundStyle(StrandPalette.textPrimary)
                if let status, status.hasVerdict {
                    HStack(spacing: 4) {
                        LiftStatusIcon(status: status, size: 10)
                        Text(verbatim: status.label)
                    }
                    .font(StrandFont.caption)
                    .foregroundStyle(status.tint)
                }
            }
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}

/// A muscle's weekly sets as bars, a thin line at the reference; bars under it are dimmer.
struct LiftWeeklyBars: View {
    let values: [Double]
    let reference: Double

    var body: some View {
        Canvas { ctx, size in
            guard !values.isEmpty else { return }
            let top = max(reference * 1.5, (values.max() ?? 0) * 1.1, 1)
            func y(_ v: Double) -> CGFloat { size.height - CGFloat(v / top) * size.height }
            let gap: CGFloat = 6
            let width = (size.width - gap * CGFloat(values.count - 1)) / CGFloat(values.count)
            for (index, value) in values.enumerated() where value > 0 {
                let x = CGFloat(index) * (width + gap)
                let rect = CGRect(x: x, y: y(value), width: width, height: size.height - y(value))
                ctx.fill(Path(roundedRect: rect, cornerRadius: 4),
                         with: .color(value >= reference ? StrandPalette.effortColor : StrandPalette.effortDeep))
            }
            ctx.fill(Path(CGRect(x: 0, y: y(reference) - 0.75, width: size.width, height: 1.5)),
                     with: .color(StrandPalette.textPrimary.opacity(0.45)))
        }
    }
}

// MARK: - Form tab

struct LiftProgressFormTab: View {
    let data: LiftProgressData

    var body: some View {
        let sessions = LiftProgress.formSessions(data.exercises)
        return VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            LiftSectionTitle(title: "Your form and your lifting") {
                Text(String(localized: "\(sessions.count) sessions"))
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            if sessions.count < LiftProgress.formMinimumSessions {
                locked(sessions.count)
            } else {
                Text("One dot per session. Right of 0: better than your recent average on the same exercises.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                LiftFormCard(title: "By Charge", caption: "Morning Charge on the day of the session",
                             groups: LiftProgress.group(sessions) { session in
                                 data.charge[Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval(session.startTs)))]
                                     .map(LiftProgress.chargeBand)
                             },
                             bands: [(.high, "67–100", StrandPalette.recovery100),
                                     (.middle, "34–66", StrandPalette.recovery055),
                                     (.low, "0–33", StrandPalette.recovery000)])
                LiftFormCard(title: "By sleep", caption: "Sleep the night before",
                             groups: LiftProgress.group(sessions) { session in
                                 data.sleep[Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval(session.startTs)))]
                                     .map(LiftProgress.sleepBand)
                             },
                             bands: [(.high, String(localized: "7 h or more"), StrandPalette.goldLight),
                                     (.middle, String(localized: "6–7 h"), StrandPalette.restBright),
                                     (.low, String(localized: "Under 6 h"), StrandPalette.restDeep)])
                Text("The form of a session is the gap between its best sets (estimated 1RM) and the mean of the 4 sessions before, for each exercise, then the median. Exercises past 12 reps are left out. It is a link observed in your data, not a cause.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, NoopMetrics.space1)
            }
        }
    }

    private func locked(_ count: Int) -> some View {
        let target = LiftProgress.formMinimumSessions
        return NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                HStack(spacing: NoopMetrics.space3) {
                    Image(systemName: "lock")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(StrandPalette.textSecondary)
                        .accessibilityHidden(true)
                    Text(String(localized: "\(target - count) more sessions"))
                        .font(StrandFont.headline)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Spacer()
                    Text(verbatim: "\(count) / \(target)")
                        .font(StrandFont.number(15))
                        .foregroundStyle(StrandPalette.textSecondary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(StrandPalette.surfaceInset)
                        Capsule().fill(StrandPalette.effortColor)
                            .frame(width: geo.size.width * CGFloat(min(1, Double(count) / Double(target))))
                    }
                }
                .frame(height: 7)
                .accessibilityHidden(true)
                Text("With fewer than 20 sessions, a gap between good days and bad days is mostly chance.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// One Form chart: three bands of sessions, a dot per session, the median marked and printed.
struct LiftFormCard: View {
    let title: LocalizedStringKey
    let caption: LocalizedStringKey
    let groups: [LiftProgress.FormBand: [Double]]
    let bands: [(band: LiftProgress.FormBand, label: String, color: Color)]

    var body: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).strandOverline()
                    Text(caption)
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
                ForEach(Array(bands.enumerated()), id: \.offset) { index, band in
                    if index > 0 { LiftDivider() }
                    row(band)
                }
                HStack(spacing: NoopMetrics.space2) {
                    Spacer().frame(width: 76)
                    HStack {
                        Text(verbatim: LiftProgressText.percent(-10))
                        Spacer()
                        Text(verbatim: "0")
                        Spacer()
                        Text(verbatim: LiftProgressText.percent(10))
                    }
                    Text("median").frame(width: 64, alignment: .trailing)
                }
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
                .accessibilityHidden(true)
            }
        }
    }

    private func row(_ band: (band: LiftProgress.FormBand, label: String, color: Color)) -> some View {
        let values = groups[band.band] ?? []
        let median = LiftProgress.median(values)
        return HStack(spacing: NoopMetrics.space2) {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: band.label)
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(String(localized: "\(values.count) sessions"))
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            .frame(width: 76, alignment: .leading)
            LiftFormStrip(values: values, median: median, tint: band.color)
                .frame(height: 28)
            Text(verbatim: median.map(LiftProgressText.percent) ?? "—")
                .font(StrandFont.number(16))
                .foregroundStyle(StrandPalette.textPrimary)
                .frame(width: 64, alignment: .trailing)
        }
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
    }
}

/// Sessions as dots on a −10 % … +10 % strip, 0 marked, the median as a bar.
struct LiftFormStrip: View {
    let values: [Double]
    let median: Double?
    let tint: Color

    var body: some View {
        Canvas { ctx, size in
            let range = 10.0
            func x(_ v: Double) -> CGFloat {
                let clamped = min(max(v, -range), range)
                return 6 + CGFloat((clamped + range) / (2 * range)) * (size.width - 12)
            }
            ctx.fill(Path(roundedRect: CGRect(x: 0, y: 2, width: size.width, height: size.height - 4), cornerRadius: 8),
                     with: .color(StrandPalette.surfaceInset))
            ctx.fill(Path(CGRect(x: x(0) - 0.75, y: 2, width: 1.5, height: size.height - 4)),
                     with: .color(StrandPalette.textPrimary.opacity(0.25)))
            for (index, value) in values.enumerated() {
                let y = size.height / 2 + CGFloat((index * 7) % 3 - 1) * 5
                ctx.fill(Path(ellipseIn: CGRect(x: x(value) - 4, y: y - 4, width: 8, height: 8)),
                         with: .color(tint.opacity(0.8)))
            }
            if let median {
                ctx.fill(Path(roundedRect: CGRect(x: x(median) - 1.5, y: 0, width: 3, height: size.height), cornerRadius: 1.5),
                         with: .color(StrandPalette.textPrimary))
            }
        }
        .accessibilityHidden(true)
    }
}
