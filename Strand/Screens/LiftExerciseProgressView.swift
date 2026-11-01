import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

// One exercise's progression (personal fork): its status, the curve of its best set per session with the
// records marked, the double-progression ladder at the current weight, its records and its last sessions.

struct LiftExerciseProgressView: View {
    let exercise: LiftProgress.Exercise
    let now: Int
    let unitSystem: UnitSystem

    var body: some View {
        ScreenScaffold(title: nil) {
            LiftExerciseProgressContent(exercise: exercise, now: now, unitSystem: unitSystem)
        }
    }
}

/// The screen's content without its scroll view, so the render test can draw it whole.
struct LiftExerciseProgressContent: View {
    let exercise: LiftProgress.Exercise
    let now: Int
    let unitSystem: UnitSystem

    @State private var period: LiftProgress.Period = .twelveWeeks

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
            VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                Text(verbatim: exercise.name)
                    .font(StrandFont.title1)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: LiftProgressText.subtitle(exercise))
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            banner
            curveSection
            if let ladder = LiftProgress.ladder(exercise) {
                ladderSection(ladder)
            }
            recordsSection
            sessionsSection
        }
    }

    // MARK: Status

    private var banner: some View {
        let status = exercise.status
        return HStack(alignment: .top, spacing: NoopMetrics.space3) {
            LiftStatusIcon(status: status, size: 16)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: bannerTitle)
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(verbatim: bannerDetail)
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(NoopMetrics.space3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(status.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(status.tint.opacity(0.32), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var bannerTitle: String {
        switch exercise.status {
        case .ready(_, let to):
            return String(localized: "Ready to go up: \(LiftFormat.weight(to, system: unitSystem))")
        case .stalled(let sessions):
            return String(localized: "No record for \(sessions) sessions")
        case .declining(let percent):
            return String(localized: "Declining: \(LiftProgressText.percent(percent))")
        case .progressing:
            return String(localized: "Progressing")
        case .notEnough:
            return String(localized: "Not enough sessions yet")
        }
    }

    private var bannerDetail: String {
        switch exercise.status {
        case .ready(let from, _):
            let item = exercise.line?.item
            let top = item?.targetRepsHigh ?? item?.targetRepsLow ?? 0
            let low = item?.targetRepsLow ?? top
            let sets = item?.targetSets ?? 0
            let goal = "\(sets) × \(top)"
            let next = "\(sets) × \(low)"
            return String(localized: "\(goal) reached at \(LiftFormat.weight(from, system: unitSystem)) · aim for \(next)")
        case .stalled:
            guard let last = exercise.points.last else { return "" }
            return String(localized: "Last time: \(LiftProgressText.sets(last.sets, system: unitSystem))")
        case .declining:
            return String(localized: "Your last 2 sessions are under your best estimate.")
        case .progressing:
            guard let record = exercise.points.last(where: \.isRecord) else { return "" }
            return String(localized: "Last record on \(LiftProgressText.day(record.startTs))")
        case .notEnough(let sessions):
            return String(localized: "\(sessions) of \(LiftProgress.minimumSessions) sessions before a status")
        }
    }

    // MARK: Curve

    private var curveSection: some View {
        let points = LiftProgress.points(exercise, in: period, now: now)
        let usesEstimate = points.contains { $0.estimatedOneRepMaxKg != nil }
        let values = points.compactMap(\.value)
        return VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            LiftSectionTitle(title: "Curve") {
                SegmentedPillControl(LiftProgress.Period.allCases, selection: $period) {
                    LiftProgressText.periodLabel($0)
                }
                .fixedSize()
            }
            NoopCard {
                VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 2) {
                            if usesEstimate {
                                Text("Estimated 1RM").strandOverline()
                            } else {
                                Text("Heaviest set").strandOverline()
                            }
                            Text("best set of each session")
                                .font(StrandFont.footnote)
                                .foregroundStyle(StrandPalette.textSecondary)
                        }
                        Spacer()
                        if let last = values.last {
                            Text(verbatim: LiftFormat.weight(last, system: unitSystem))
                                .font(StrandFont.number(28, weight: .bold))
                                .foregroundStyle(StrandPalette.effortBright)
                        }
                    }
                    if points.isEmpty {
                        Text("No session in this period.")
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textSecondary)
                    } else {
                        LiftProgressCurve(points: points)
                            .frame(height: 132)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(Text(verbatim: values.map { LiftFormat.trim(($0 * 10).rounded() / 10) }
                                .joined(separator: ", ")))
                        LiftWeightBandLabels(points: points, unitSystem: unitSystem)
                            .frame(height: 16)
                        HStack {
                            Text(verbatim: points.first.map { LiftProgressText.day($0.startTs) } ?? "")
                            Spacer()
                            if points.count > 2 {
                                Text(verbatim: LiftProgressText.day(points[points.count / 2].startTs))
                                Spacer()
                            }
                            Text(verbatim: points.last.map { LiftProgressText.day($0.startTs) } ?? "")
                        }
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .accessibilityHidden(true)
                        legend
                        LiftDivider()
                        HStack {
                            stat(String(localized: "At start"), values.first.map { LiftFormat.trim(($0 * 10).rounded() / 10) } ?? "—")
                            Spacer()
                            stat(String(localized: "Trend"), LiftProgress.change(points).map(LiftProgressText.percent) ?? "—")
                            Spacer()
                            stat(String(localized: "Sessions"), "\(points.count)")
                        }
                    }
                }
            }
        }
    }

    private var legend: some View {
        HStack(spacing: NoopMetrics.space3) {
            HStack(spacing: 6) {
                Circle().fill(StrandPalette.effortBright).frame(width: 8, height: 8)
                Text("record")
            }
            HStack(spacing: 6) {
                Circle().strokeBorder(StrandPalette.effortBright, lineWidth: 1.8).frame(width: 8, height: 8)
                Text("no record")
            }
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3).fill(StrandPalette.textPrimary.opacity(0.12)).frame(width: 14, height: 10)
                Text("same weight")
            }
        }
        .font(StrandFont.caption)
        .foregroundStyle(StrandPalette.textSecondary)
        .accessibilityHidden(true)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
            Text(verbatim: value)
                .font(StrandFont.number(15))
                .foregroundStyle(StrandPalette.textPrimary)
        }
    }

    // MARK: Ladder

    private func ladderSection(_ ladder: LiftProgress.Ladder) -> some View {
        let weight = LiftFormat.weight(ladder.weightKg, system: unitSystem)
        let step = unitSystem == .imperial ? LiftProgression.imperialStepKg : LiftProgression.metricStepKg
        let goal = "\(ladder.targetSets) × \(ladder.topReps)"
        let nextGoal = "\(ladder.targetSets) × \(exercise.line?.item.targetRepsLow ?? ladder.topReps)"
        return VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            HStack(spacing: NoopMetrics.space2) {
                Text(String(localized: "Ladder at \(weight)")).strandOverline()
                Spacer(minLength: NoopMetrics.space2)
                Text(String(localized: "\(goal), then +\(LiftFormat.weight(step, system: unitSystem))"))
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            .frame(minHeight: 28)
            NoopCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(ladder.rows.enumerated()), id: \.offset) { index, row in
                        if index > 0 { LiftDivider().padding(.horizontal, NoopMetrics.cardPadding) }
                        ladderRow(row, ladder: ladder)
                            .padding(.horizontal, NoopMetrics.cardPadding)
                    }
                    if let step = exercise.status.step {
                        LiftDivider().padding(.horizontal, NoopMetrics.cardPadding)
                        HStack(spacing: NoopMetrics.space3) {
                            Text("Next time")
                                .font(StrandFont.subhead.weight(.semibold))
                                .foregroundStyle(StrandPalette.effortBright)
                                .frame(width: 64, alignment: .leading)
                            Text(String(localized: "\(LiftFormat.weight(step.to, system: unitSystem)) · aim for \(nextGoal)"))
                                .font(StrandFont.body)
                                .foregroundStyle(StrandPalette.textPrimary)
                            Spacer()
                            LiftStatusIcon(status: exercise.status, size: 14)
                        }
                        .frame(minHeight: 50)
                        .padding(.horizontal, NoopMetrics.cardPadding)
                    }
                }
            }
        }
    }

    private func ladderRow(_ row: LiftProgress.LadderRow, ladder: LiftProgress.Ladder) -> some View {
        let total = row.reps.reduce(0, +)
        let done = total >= ladder.targetTotal
        return HStack(spacing: NoopMetrics.space3) {
            Text(verbatim: LiftProgressText.day(row.startTs))
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
                .frame(width: 64, alignment: .leading)
            HStack(spacing: 6) {
                ForEach(Array(row.reps.enumerated()), id: \.offset) { _, reps in
                    let top = reps >= ladder.topReps
                    Text(verbatim: "\(reps)")
                        .font(StrandFont.number(14))
                        .foregroundStyle(top ? StrandPalette.goldDeepText : StrandPalette.textPrimary)
                        .frame(width: 34, height: 28)
                        .background(top ? StrandPalette.effortColor : StrandPalette.surfaceInset,
                                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
            }
            Spacer(minLength: NoopMetrics.space2)
            VStack(alignment: .trailing, spacing: 5) {
                Text(verbatim: "\(total) / \(ladder.targetTotal)")
                    .font(StrandFont.number(14))
                    .foregroundStyle(done ? StrandPalette.textPrimary : StrandPalette.textSecondary)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(StrandPalette.surfaceInset)
                        Capsule().fill(done ? StrandPalette.effortBright : StrandPalette.effortDeep)
                            .frame(width: geo.size.width * CGFloat(min(1, Double(total) / Double(max(1, ladder.targetTotal)))))
                    }
                }
                .frame(width: 64, height: 5)
            }
        }
        .frame(minHeight: 56)
        .accessibilityElement(children: .combine)
    }

    // MARK: Records

    private var recordsSection: some View {
        let sets = exercise.points.flatMap { point in point.sets.map { (set: $0, ts: point.startTs) } }
        let heaviest = sets.filter { $0.set.weightKg != nil && $0.set.reps != nil }.max { a, b in
            let wa = a.set.weightKg ?? 0, wb = b.set.weightKg ?? 0
            return wa != wb ? wa < wb : (a.set.reps ?? 0) < (b.set.reps ?? 0)
        }
        let bestEstimate = exercise.points.filter { $0.estimatedOneRepMaxKg != nil }
            .max { ($0.estimatedOneRepMaxKg ?? 0) < ($1.estimatedOneRepMaxKg ?? 0) }
        let ladder = LiftProgress.ladder(exercise)
        let mostReps = ladder.flatMap { l in
            exercise.points.filter { point in
                !point.sets.isEmpty && point.sets.allSatisfy { abs(($0.weightKg ?? -1) - l.weightKg) < 0.001 }
            }
            .max { $0.sets.compactMap(\.reps).reduce(0, +) < $1.sets.compactMap(\.reps).reduce(0, +) }
            .map { (weight: l.weightKg, point: $0) }
        }
        return VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            Text("Records").strandOverline().frame(minHeight: 28)
            NoopCard(padding: 0) {
                VStack(spacing: 0) {
                    if let heaviest {
                        recordRow(String(localized: "Heaviest weight"),
                                  LiftProgressText.set(heaviest.set.weightKg, heaviest.set.reps, system: unitSystem),
                                  heaviest.ts)
                    }
                    if let bestEstimate, let value = bestEstimate.estimatedOneRepMaxKg {
                        LiftDivider().padding(.horizontal, NoopMetrics.cardPadding)
                        recordRow(String(localized: "Best estimated 1RM"),
                                  LiftFormat.weight((value * 10).rounded() / 10, system: unitSystem), bestEstimate.startTs)
                    }
                    if let mostReps {
                        LiftDivider().padding(.horizontal, NoopMetrics.cardPadding)
                        recordRow(String(localized: "Most reps at \(LiftFormat.weight(mostReps.weight, system: unitSystem))"),
                                  "\(mostReps.point.sets.compactMap(\.reps).reduce(0, +))", mostReps.point.startTs)
                    }
                }
            }
        }
    }

    private func recordRow(_ label: String, _ value: String, _ ts: Int) -> some View {
        HStack(spacing: NoopMetrics.space3) {
            Image(systemName: "trophy")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(StrandPalette.statusPositive)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: label)
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(verbatim: LiftProgressText.day(ts))
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            Spacer(minLength: NoopMetrics.space2)
            Text(verbatim: value)
                .font(StrandFont.number(15))
                .foregroundStyle(StrandPalette.textPrimary)
        }
        .frame(minHeight: 56)
        .padding(.horizontal, NoopMetrics.cardPadding)
        .accessibilityElement(children: .combine)
    }

    // MARK: Sessions

    private var sessionsSection: some View {
        let recent = Array(exercise.points.suffix(6).reversed())
        return VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            HStack {
                Text("Sessions").strandOverline()
                Spacer()
                Text("Est. 1RM")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            .frame(minHeight: 28)
            NoopCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(recent.enumerated()), id: \.element.sessionId) { index, point in
                        if index > 0 { LiftDivider().padding(.horizontal, NoopMetrics.cardPadding) }
                        HStack(spacing: NoopMetrics.space3) {
                            Text(verbatim: LiftProgressText.day(point.startTs))
                                .font(StrandFont.subhead)
                                .foregroundStyle(StrandPalette.textSecondary)
                                .frame(width: 64, alignment: .leading)
                            Text(verbatim: LiftProgressText.sets(point.sets, system: unitSystem))
                                .font(StrandFont.body)
                                .foregroundStyle(StrandPalette.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: NoopMetrics.space2)
                            if point.isRecord {
                                Image(systemName: "trophy.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(StrandPalette.statusPositive)
                                    .accessibilityLabel(Text("record"))
                            }
                            Text(verbatim: point.estimatedOneRepMaxKg.map { LiftFormat.trim(($0 * 10).rounded() / 10) } ?? "—")
                                .font(StrandFont.number(14))
                                .foregroundStyle(StrandPalette.textSecondary)
                        }
                        .frame(minHeight: 52)
                        .padding(.horizontal, NoopMetrics.cardPadding)
                    }
                }
            }
        }
    }
}

/// The curve of an exercise: one point per session, records filled, the same-weight runs as soft bands.
struct LiftProgressCurve: View {
    let points: [LiftProgress.Point]

    var body: some View {
        Canvas { ctx, size in
            let values = points.map { $0.value ?? 0 }
            guard let lo0 = values.min(), let hi0 = values.max() else { return }
            let pad = max((hi0 - lo0) * 0.15, hi0 * 0.03, 0.5)
            let lo = lo0 - pad, hi = hi0 + pad
            let xs = LiftCurveLayout.xs(count: points.count, width: size.width)
            func y(_ v: Double) -> CGFloat { 8 + (size.height - 16) * CGFloat(1 - (v - lo) / (hi - lo)) }

            for band in LiftCurveLayout.bands(points) {
                let rect = LiftCurveLayout.bandRect(band, xs: xs, width: size.width, height: size.height)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 6), with: .color(StrandPalette.textPrimary.opacity(0.035)))
            }

            let line = zip(xs, values).map { CGPoint(x: $0, y: y($1)) }
            if line.count > 1 {
                var path = Path()
                path.move(to: line[0])
                for p in line.dropFirst() { path.addLine(to: p) }
                var area = path
                area.addLine(to: CGPoint(x: line[line.count - 1].x, y: size.height))
                area.addLine(to: CGPoint(x: line[0].x, y: size.height))
                area.closeSubpath()
                ctx.fill(area, with: .linearGradient(
                    Gradient(colors: [StrandPalette.effortColor.opacity(0.28), StrandPalette.effortColor.opacity(0)]),
                    startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: size.height)))
                ctx.stroke(path, with: .color(StrandPalette.effortBright),
                           style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            }
            if let last = line.last {
                ctx.fill(Path(ellipseIn: CGRect(x: last.x - 9, y: last.y - 9, width: 18, height: 18)),
                         with: .color(StrandPalette.effortBright.opacity(0.22)))
            }
            for (point, p) in zip(points, line) {
                if point.isRecord {
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)),
                             with: .color(StrandPalette.effortBright))
                } else {
                    let dot = Path(ellipseIn: CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7))
                    ctx.fill(dot, with: .color(StrandPalette.surfaceRaised))
                    ctx.stroke(dot, with: .color(StrandPalette.effortBright), lineWidth: 1.8)
                }
            }
        }
    }
}

/// Where the curve's points and weight bands sit, shared by the curve and the labels under it.
enum LiftCurveLayout {
    /// A run of consecutive sessions whose best set used the same weight.
    struct Band {
        let first: Int
        let last: Int
        let weightKg: Double
    }

    static func xs(count: Int, width: CGFloat) -> [CGFloat] {
        guard count > 1 else { return [width / 2] }
        return (0..<count).map { 10 + CGFloat($0) * (width - 22) / CGFloat(count - 1) }
    }

    static func bands(_ points: [LiftProgress.Point]) -> [Band] {
        var out: [Band] = []
        for (index, point) in points.enumerated() {
            let w = point.bestWeightKg ?? 0
            if let previous = out.last, abs(previous.weightKg - w) < 0.001 {
                out[out.count - 1] = Band(first: previous.first, last: index, weightKg: w)
            } else {
                out.append(Band(first: index, last: index, weightKg: w))
            }
        }
        return out
    }

    static func bandRect(_ band: Band, xs: [CGFloat], width: CGFloat, height: CGFloat) -> CGRect {
        let x0 = band.first == 0 ? 0 : xs[band.first] - 10
        let x1 = band.last == xs.count - 1 ? width : xs[band.last] + 10
        return CGRect(x: x0, y: 0, width: max(0, x1 - x0 - 2), height: height)
    }
}

/// The weight of each band, centred under it.
struct LiftWeightBandLabels: View {
    let points: [LiftProgress.Point]
    let unitSystem: UnitSystem

    var body: some View {
        GeometryReader { geo in
            let xs = LiftCurveLayout.xs(count: points.count, width: geo.size.width)
            ZStack(alignment: .topLeading) {
                ForEach(Array(LiftCurveLayout.bands(points).enumerated()), id: \.offset) { _, band in
                    let rect = LiftCurveLayout.bandRect(band, xs: xs, width: geo.size.width, height: 16)
                    if band.weightKg > 0, rect.width > 30 {
                        Text(verbatim: LiftFormat.weight(band.weightKg, system: unitSystem))
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .lineLimit(1)
                            .position(x: rect.midX, y: 8)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}
