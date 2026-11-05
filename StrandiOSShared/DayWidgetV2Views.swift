import SwiftUI
import StrandDesign

// Widgets v2 (personal fork, 5 Nov., mockup « NOOP – Widgets v2 »): the medium widgets redrawn so they read at
// a glance, each as the Today, Nutrition or Sleep card it summarises. Today's four rings with their lines; the
// heart rate of the last three hours against the day's two thresholds; the stress card's bands; today's
// planned items one per line with their Start; the meals against the goals with the card's three figures;
// the night as a four-lane hypnogram with each stage's total.
//
// Plain values in, no WidgetKit, so the macOS app module compiles this file and `StrandTests` renders it to
// PNG (`DayWidgetsRenderTests`). Every word arrives in the snapshot; nothing here is copy.

/// A widget's title in its section colour, the chantier 9 way (no capitals), with an optional trailing note.
struct DayWidgetTitle: View {
    let symbol: String
    let title: String
    let tint: Color
    var trailing: String? = nil

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(StrandFont.footnote.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
            Spacer(minLength: 6)
            if let trailing {
                Text(trailing)
                    .font(StrandFont.caption2)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A small figure under its name: « Min **64** ».
private struct DayWidgetFigure: View {
    let name: String
    let value: String

    var body: some View {
        HStack(spacing: 3) {
            Text(name).foregroundStyle(StrandPalette.textSecondary)
            Text(value).fontWeight(.semibold).foregroundStyle(StrandPalette.textPrimary).monospacedDigit()
        }
        .font(StrandFont.caption2)
        .lineLimit(1)
    }
}

// MARK: - Rings

/// One ring of the stack: its fill, its tint and, for Effort, the target band behind the fill.
struct DayWidgetRingSpec {
    var fraction: Double
    var tint: Color
    var band: ClosedRange<Double>? = nil
}

/// Today's four concentric flat rings (`TodayConcentricRings`), outside to inside: a track at 18 %, the
/// target band at 35 %, the fill with round caps.
struct DayWidgetRingStack: View {
    let rings: [DayWidgetRingSpec]
    var lineWidth: CGFloat = 9
    var spacing: CGFloat = 3

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                ForEach(Array(rings.enumerated()), id: \.offset) { index, ring in
                    let inset = CGFloat(index) * (lineWidth + spacing) + lineWidth / 2
                    let size = max(0, side - inset * 2)
                    ZStack {
                        Circle().stroke(ring.tint.opacity(0.18), lineWidth: lineWidth)
                        if let band = ring.band {
                            Circle()
                                .trim(from: CGFloat(min(1, max(0, band.lowerBound))),
                                      to: CGFloat(min(1, max(0, band.upperBound))))
                                .stroke(ring.tint.opacity(0.35), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                        }
                        Circle()
                            .trim(from: 0, to: CGFloat(min(1, max(0, ring.fraction))))
                            .stroke(ring.tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    }
                    .rotationEffect(.degrees(-90))
                    .frame(width: size, height: size)
                }
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityHidden(true)
    }
}

/// The rings widget (medium): Today's hero card in small — the four rings and, beside them, one line each.
struct DayRingsWidgetFace: View {
    let rings: DayWidgetsSnapshot.Rings?
    let noData: String

    private var chargeTint: Color {
        rings?.charge.score.map { StrandPalette.chargeTint($0) } ?? StrandPalette.chargeColor
    }

    var body: some View {
        if let rings {
            HStack(spacing: 14) {
                DayWidgetRingStack(rings: [
                    .init(fraction: rings.activity.fraction, tint: StrandPalette.caloriesActivity),
                    .init(fraction: rings.charge.fraction, tint: chargeTint),
                    .init(fraction: rings.effort.fraction, tint: StrandPalette.effortColor,
                          band: rings.effort.bandFrom.flatMap { from in rings.effort.bandTo.map { from...max(from, $0) } }),
                    .init(fraction: rings.rest.fraction, tint: StrandPalette.restRing),
                ])
                .frame(width: 118, height: 118)
                VStack(alignment: .leading, spacing: 2) {
                    line(rings.activity, tint: StrandPalette.caloriesActivity)
                    line(rings.charge, tint: chargeTint)
                    line(rings.effort, tint: StrandPalette.effortColor)
                    line(rings.rest, tint: StrandPalette.restRing)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Text(noData)
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func line(_ ring: DayWidgetsSnapshot.Ring, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(ring.label)
                .font(StrandFont.caption2.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(ring.value ?? "\u{2014}")
                    .font(StrandFont.number(17, weight: .semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                if let caption = ring.caption {
                    Text(caption)
                        .font(StrandFont.caption2)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Heart rate

/// One minute of the heart-rate trace: unix seconds and bpm.
struct DayHeartPoint: Equatable {
    var ts: Int
    var bpm: Int
}

/// A polyline over normalised points (x, y in 0…1, y down), broken where `breaks` says a new run starts.
private struct DayWidgetPolyline: Shape {
    let points: [CGPoint]
    let breaks: Set<Int>

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for (i, p) in points.enumerated() {
            let at = CGPoint(x: rect.minX + p.x * rect.width, y: rect.minY + p.y * rect.height)
            if i == 0 || breaks.contains(i) { path.move(to: at) } else { path.addLine(to: at) }
        }
        return path
    }
}

/// The region beyond a threshold line, step by step: up to the top for the high line, down to the bottom for
/// the low one. A step without a threshold, or inside sleep, leaves a gap, so the curve is not coloured there.
private struct DayWidgetZoneRegion: Shape {
    /// (x, y) of the threshold at each step, nil where there is none.
    let steps: [CGPoint?]
    let towardsTop: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for i in 0..<max(0, steps.count - 1) {
            guard let a = steps[i], let b = steps[i + 1] else { continue }
            let edge: CGFloat = towardsTop ? rect.minY : rect.maxY
            path.move(to: CGPoint(x: rect.minX + a.x * rect.width, y: edge))
            path.addLine(to: CGPoint(x: rect.minX + b.x * rect.width, y: edge))
            path.addLine(to: CGPoint(x: rect.minX + b.x * rect.width, y: rect.minY + b.y * rect.height))
            path.addLine(to: CGPoint(x: rect.minX + a.x * rect.width, y: rect.minY + a.y * rect.height))
            path.closeSubpath()
        }
        return path
    }
}

/// The heart-rate widget (medium): the last three hours as Today's card draws them — pink, red above the high
/// threshold, green under the low one, the two thresholds dashed and named.
struct DayHeartWidgetFace: View {
    /// The trace, oldest first, already pruned to the window.
    let points: [DayHeartPoint]
    /// The headline reading and whether it is too old to read as current.
    let bpm: Int?
    let stale: Bool
    /// The window's end (the entry's date) and length, unix seconds.
    let windowEnd: Int
    let windowSec: Int
    /// The day snapshot: the thresholds and the words.
    let day: DayWidgetsSnapshot?
    /// The times under the axis, formatted by the caller.
    let axis: [String]
    /// A gap longer than this breaks the trace.
    var gapSec: Int = 15 * 60

    private var heart: DayWidgetsSnapshot.Heart? { day?.heart }
    private func word(_ english: String) -> String { day?.word(english) ?? english }

    private var stepTimes: [Int] {
        let start = windowEnd - windowSec
        return Array(stride(from: start, through: windowEnd, by: DayWidgetsSnapshot.Heart.slotSeconds))
    }

    /// The bpm range drawn: the trace and the thresholds of the window, with a little room.
    private var range: ClosedRange<Double> {
        var values = points.map { Double($0.bpm) }
        if let heart {
            for ts in stepTimes {
                let t = heart.thresholds(at: ts)
                if let h = t.high { values.append(Double(h)) }
                if let l = t.low { values.append(Double(l)) }
            }
        }
        let lo = (values.min() ?? 50) - 6, hi = (values.max() ?? 120) + 6
        return lo...max(lo + 10, hi)
    }

    private func fx(_ ts: Int) -> CGFloat {
        CGFloat(min(1, max(0, Double(ts - (windowEnd - windowSec)) / Double(max(1, windowSec)))))
    }

    private func fy(_ bpm: Double) -> CGFloat {
        let r = range
        return CGFloat(1 - (bpm - r.lowerBound) / (r.upperBound - r.lowerBound))
    }

    private var curve: [CGPoint] { points.map { CGPoint(x: fx($0.ts), y: fy(Double($0.bpm))) } }

    private var curveBreaks: Set<Int> {
        var out = Set<Int>()
        for i in points.indices.dropFirst() where points[i].ts - points[i - 1].ts > gapSec { out.insert(i) }
        return out
    }

    private func thresholdSteps(high: Bool, awakeOnly: Bool) -> [CGPoint?] {
        guard let heart else { return [] }
        return stepTimes.map { ts in
            if awakeOnly && heart.isAsleep(ts) { return nil }
            let t = heart.thresholds(at: ts)
            return (high ? t.high : t.low).map { CGPoint(x: fx(ts), y: fy(Double($0))) }
        }
    }

    private func dashed(_ steps: [CGPoint?]) -> (points: [CGPoint], breaks: Set<Int>) {
        var out: [CGPoint] = [], breaks = Set<Int>()
        var open = false
        for step in steps {
            if let step {
                if !open { breaks.insert(out.count) }
                out.append(step)
                open = true
            } else {
                open = false
            }
        }
        return (out, breaks)
    }

    private var stats: (min: Int, avg: Int, max: Int)? {
        guard !points.isEmpty else { return nil }
        let values = points.map(\.bpm)
        let avg = Double(values.reduce(0, +)) / Double(values.count)
        return (values.min() ?? 0, Int(avg.rounded()), values.max() ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            DayWidgetTitle(symbol: "heart.fill", title: word("Heart rate"), tint: StrandPalette.liquidHeart,
                           trailing: word("Last 3 hours"))
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(bpm.map(String.init) ?? "\u{2014}")
                    .font(StrandFont.number(28, weight: .bold))
                    .foregroundStyle(stale ? StrandPalette.textSecondary : StrandPalette.textPrimary)
                    .monospacedDigit()
                Text(word("bpm"))
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                Spacer(minLength: 6)
                if let stats {
                    HStack(spacing: 8) {
                        DayWidgetFigure(name: word("Min"), value: "\(stats.min)")
                        DayWidgetFigure(name: word("Avg"), value: "\(stats.avg)")
                        DayWidgetFigure(name: word("Max"), value: "\(stats.max)")
                    }
                }
            }
            if !points.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    chart
                    thresholdLabels.frame(width: 34)
                }
                .frame(maxHeight: .infinity)
                HStack {
                    ForEach(Array(axis.enumerated()), id: \.offset) { index, label in
                        Text(label)
                        if index < axis.count - 1 { Spacer(minLength: 4) }
                    }
                }
                .font(StrandFont.caption2)
                .foregroundStyle(StrandPalette.textSecondary)
                .padding(.trailing, 40)
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    private var chart: some View {
        let high = dashed(thresholdSteps(high: true, awakeOnly: false))
        let low = dashed(thresholdSteps(high: false, awakeOnly: false))
        let line = DayWidgetPolyline(points: curve, breaks: curveBreaks)
        let joined = StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
        return ZStack {
            DayWidgetPolyline(points: high.points, breaks: high.breaks)
                .stroke(StrandPalette.hrZoneHigh.opacity(0.85), style: StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
            DayWidgetPolyline(points: low.points, breaks: low.breaks)
                .stroke(StrandPalette.hrZoneLow.opacity(0.85), style: StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
            line.stroke(StrandPalette.liquidHeart, style: joined)
            line.stroke(StrandPalette.hrZoneHigh, style: joined)
                .mask { DayWidgetZoneRegion(steps: thresholdSteps(high: true, awakeOnly: true), towardsTop: true) }
            line.stroke(StrandPalette.hrZoneLow, style: joined)
                .mask { DayWidgetZoneRegion(steps: thresholdSteps(high: false, awakeOnly: true), towardsTop: false) }
        }
        .accessibilityHidden(true)
    }

    /// « high 114 » over « low 68 », each beside the end of its line.
    private var thresholdLabels: some View {
        GeometryReader { geo in
            let now = heart?.thresholds(at: windowEnd)
            ZStack(alignment: .topLeading) {
                if let h = now?.high {
                    label(heart?.highLabel, value: h, tint: StrandPalette.hrZoneHigh)
                        .offset(y: max(0, fy(Double(h)) * geo.size.height - 14))
                }
                if let l = now?.low {
                    label(heart?.lowLabel, value: l, tint: StrandPalette.hrZoneLow)
                        .offset(y: min(geo.size.height - 24, max(0, fy(Double(l)) * geo.size.height - 4)))
                }
            }
        }
    }

    private func label(_ words: DayWidgetsSnapshot.Emphasis?, value: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let words, !words.value.isEmpty {
                Text(words.before.trimmingCharacters(in: .whitespaces))
            }
            Text(String(value)).monospacedDigit()
        }
        .font(StrandFont.caption2.weight(.semibold))
        .foregroundStyle(tint)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

// MARK: - Stress

/// The stress widget (medium): Today's stress card in small — the level in words, the three bands named, the
/// hours in movement greyed, and the day's figures.
struct DayStressWidgetFace: View {
    let day: DayWidgetsSnapshot?
    /// The entry's date, unix seconds: past `freshUntil`, the latest hour is named by its time.
    let now: Int

    private var stress: DayWidgetsSnapshot.Stress? { day?.stress }
    private func word(_ english: String) -> String { day?.word(english) ?? english }

    private static func bandColor(_ level: Double) -> Color {
        if level < 1 { return StrandPalette.stressCalm }
        if level < 2 { return StrandPalette.stressModerate }
        return StrandPalette.stressHigh
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            DayWidgetTitle(symbol: "waveform.path.ecg", title: word("Stress"), tint: StrandPalette.stressTitle,
                           trailing: stress.flatMap { s -> String? in
                               guard let first = s.axis.first, let last = s.axis.last else { return nil }
                               return first + " \u{2013} " + last
                           })
            if let stress, !stress.points.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let level = stress.latestLevel, let name = stress.latestName {
                        Text(name)
                            .font(StrandFont.rounded(22, weight: .bold))
                            .foregroundStyle(Self.bandColor(level))
                            .lineLimit(1)
                    }
                    if let value = stress.latestValue {
                        let when: String? = (stress.freshUntil.map { now <= $0 } ?? false) ? word("this hour") : stress.latestAt
                        Text([value, when].compactMap { $0 }.joined(separator: " · "))
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                chart(stress).frame(maxHeight: .infinity)
                HStack {
                    ForEach(Array(stress.axis.enumerated()), id: \.offset) { index, label in
                        Text(label)
                        if index < stress.axis.count - 1 { Spacer(minLength: 2) }
                    }
                }
                .font(StrandFont.caption2)
                .foregroundStyle(StrandPalette.textSecondary)
                HStack(spacing: 10) {
                    if let high = stress.high { DayWidgetFigure(name: word("High"), value: high) }
                    if let mean = stress.mean { DayWidgetFigure(name: word("Avg"), value: mean) }
                    if let peak = stress.peak { DayWidgetFigure(name: word("Peak"), value: peak) }
                    Spacer(minLength: 4)
                    if !stress.moving.isEmpty {
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 2).fill(StrandPalette.stressMoving).frame(width: 8, height: 8)
                            Text(word("moving"))
                        }
                        .font(StrandFont.caption2)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .lineLimit(1)
                    }
                }
            } else {
                Spacer(minLength: 0)
                Text(day?.labels?.noData ?? DayWidgetsSnapshot.Labels.english.noData)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    private func chart(_ stress: DayWidgetsSnapshot.Stress) -> some View {
        let points = stress.points.map { CGPoint(x: $0.x, y: 1 - min(3, max(0, $0.level)) / 3) }
        var breaks = Set<Int>()
        for i in stress.points.indices.dropFirst() where stress.points[i].run != stress.points[i - 1].run {
            breaks.insert(i)
        }
        let bands: [(name: String, tint: Color)] = [(word("High"), StrandPalette.stressHigh),
                                                    (word("Moderate"), StrandPalette.stressModerate),
                                                    (word("Calm"), StrandPalette.stressCalm)]
        return GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    ForEach(Array(bands.enumerated()), id: \.offset) { _, band in
                        ZStack(alignment: .trailing) {
                            band.tint.opacity(0.16)
                            Text(band.name)
                                .font(StrandFont.rounded(9, weight: .semibold))
                                .foregroundStyle(band.tint.opacity(0.8))
                                .padding(.trailing, 3)
                        }
                    }
                }
                ForEach(Array(stress.moving.enumerated()), id: \.offset) { _, span in
                    if span.count == 2 {
                        StrandPalette.stressMoving.opacity(0.9)
                            .frame(width: max(1, CGFloat(span[1] - span[0]) * w), height: h)
                            .offset(x: CGFloat(span[0]) * w)
                    }
                }
                DayWidgetPolyline(points: points, breaks: breaks)
                    .stroke(StrandPalette.textPrimary, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                if let last = stress.points.last {
                    Circle()
                        .fill(Self.bandColor(last.level))
                        .frame(width: 8, height: 8)
                        .offset(x: CGFloat(last.x) * w - 4, y: (1 - CGFloat(min(3, max(0, last.level)) / 3)) * h - 4)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Today's session

/// The session widget (medium, v2): each planned item on its own line — its kind, its name, what it is, and a
/// Start that launches it — then this week's tally. One item reads larger; none says nothing is planned.
struct DaySessionWidgetFaceV2: View {
    let session: DayWidgetsSnapshot.Session?
    let day: DayWidgetsSnapshot?
    let labels: DayWidgetsSnapshot.Labels

    private func word(_ english: String) -> String { day?.word(english) ?? english }
    private var rows: [DayWidgetsSnapshot.SessionRow] { session?.rows ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            DayWidgetTitle(symbol: "dumbbell.fill", title: labels.sessionTitle, tint: StrandPalette.textPrimary,
                           trailing: session?.dayLine)
            if rows.count == 1, let row = rows.first {
                Spacer(minLength: 0)
                rowView(row, large: true)
                Spacer(minLength: 0)
            } else if rows.isEmpty {
                Spacer(minLength: 0)
                Text(session == nil ? labels.noData : word("Nothing planned"))
                    .font(StrandFont.rounded(18, weight: .semibold))
                    .foregroundStyle(StrandPalette.textSecondary)
                Spacer(minLength: 0)
            } else {
                ForEach(Array(rows.prefix(2).enumerated()), id: \.offset) { index, row in
                    if index > 0 {
                        Rectangle().fill(StrandPalette.hairline).frame(height: 1).padding(.leading, 44)
                    }
                    rowView(row, large: false)
                }
                Spacer(minLength: 0)
            }
            if let weekDone = session?.weekDone {
                DayWidgetEmphasisLine(line: weekDone)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func tint(_ row: DayWidgetsSnapshot.SessionRow) -> Color {
        switch row.kind {
        case .lift: return StrandPalette.effortColor
        case .cardio: return StrandPalette.metricRose
        case .rest: return StrandPalette.restRing
        }
    }

    private func symbol(_ row: DayWidgetsSnapshot.SessionRow) -> String {
        if row.isDone { return "checkmark" }
        switch row.kind {
        case .lift: return "dumbbell.fill"
        case .cardio: return "figure.run"
        case .rest: return "moon.fill"
        }
    }

    private func rowView(_ row: DayWidgetsSnapshot.SessionRow, large: Bool) -> some View {
        let side: CGFloat = large ? 42 : 34
        return HStack(spacing: 10) {
            ZStack {
                Circle().fill(row.isDone ? tint(row) : tint(row).opacity(0.18))
                Image(systemName: symbol(row))
                    .font(.system(size: large ? 19 : 15, weight: .semibold))
                    .foregroundStyle(row.isDone ? StrandPalette.onDarkPrimary : tint(row))
            }
            .frame(width: side, height: side)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.name)
                    .font(StrandFont.rounded(large ? 20 : 16, weight: .semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if let detail = row.detail {
                    Text(detail)
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let start = row.start, let url = URL(string: start) {
                Link(destination: url) {
                    Text(word("Start"))
                        .font(StrandFont.footnote.weight(.semibold))
                        .foregroundStyle(row.kind == .cardio ? StrandPalette.onDarkPrimary : StrandPalette.surfaceBase)
                        .lineLimit(1)
                        .padding(.horizontal, 13)
                        .frame(minHeight: 30)
                        .background(row.kind == .cardio ? StrandPalette.metricRose : StrandPalette.textPrimary,
                                    in: Capsule())
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Nutrition

/// The Nutrition widget (medium, v2): the calories eaten in a ring against the intake goal, a bar per macro
/// in the Nutrition colours, and the card's three figures (left, spent, net).
struct DayNutritionWidgetFaceV2: View {
    let nutrition: DayWidgetsSnapshot.Nutrition?
    let day: DayWidgetsSnapshot?
    let labels: DayWidgetsSnapshot.Labels

    private func word(_ english: String) -> String { day?.word(english) ?? english }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            DayWidgetTitle(symbol: "fork.knife", title: labels.nutritionTitle, tint: StrandPalette.intakeColor,
                           trailing: nutrition?.meals)
            if let nutrition {
                HStack(spacing: 14) {
                    ZStack {
                        DayWidgetRing(fraction: nutrition.fraction, tint: StrandPalette.intakeColor)
                        VStack(spacing: 0) {
                            Text(nutrition.eaten)
                                .font(StrandFont.number(16, weight: .bold))
                                .foregroundStyle(StrandPalette.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            Text(nutrition.goalShort)
                                .font(StrandFont.rounded(9, weight: .regular))
                                .foregroundStyle(StrandPalette.textSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                        .padding(.horizontal, 12)
                    }
                    .frame(width: 76, height: 76)
                    VStack(spacing: 6) {
                        macroBar(labels.protein, nutrition.protein, StrandPalette.macroProtein)
                        macroBar(labels.carbs, nutrition.carbs, StrandPalette.macroCarbs)
                        macroBar(labels.fat, nutrition.fat, StrandPalette.macroFat)
                    }
                }
                Spacer(minLength: 0)
                HStack(alignment: .top, spacing: 8) {
                    figure(word("Left"), nutrition.left, tint: StrandPalette.intakeColor)
                    figure(word("Spent"), nutrition.spent, tint: StrandPalette.caloriesActivity)
                    figure(word("Net"), nutrition.net, tint: StrandPalette.textPrimary)
                }
            } else {
                Spacer(minLength: 0)
                Text(labels.noData)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func macroBar(_ label: String, _ macro: DayWidgetsSnapshot.Macro, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(label)
                    .fontWeight(.semibold)
                    .foregroundStyle(tint)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(macro.eaten).fontWeight(.semibold).foregroundStyle(StrandPalette.textPrimary)
                Text(macro.rest).foregroundStyle(StrandPalette.textSecondary)
            }
            .font(StrandFont.caption2)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(tint.opacity(0.18))
                    Capsule().fill(tint)
                        .frame(width: geo.size.width * CGFloat(min(1, max(0, macro.fraction ?? 0))))
                }
            }
            .frame(height: 5)
        }
        .accessibilityElement(children: .combine)
    }

    private func figure(_ name: String, _ value: String?, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(name)
                .font(StrandFont.caption2)
                .foregroundStyle(StrandPalette.textSecondary)
                .lineLimit(1)
            Text(value ?? "\u{2014}")
                .font(StrandFont.number(13, weight: .bold))
                .foregroundStyle(value == nil ? StrandPalette.textSecondary : tint)
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Sleep

/// The night as four lanes, Awake on top and Deep at the bottom, each stretch as wide as it lasted and in its
/// stage colour, a faint line joining the steps (the Sleep screen's hypnogram, flattened).
struct DayWidgetHypnogram: View {
    let phases: [DayWidgetsSnapshot.Phase]

    private static func lane(_ stage: String) -> Int {
        switch stage {
        case "wake": return 0
        case "rem": return 1
        case "light": return 2
        default: return 3
        }
    }

    var body: some View {
        GeometryReader { geo in
            let total = max(1, phases.reduce(0) { $0 + max(0, $1.minutes) })
            let laneHeight = geo.size.height / 4
            let barHeight = max(3, laneHeight - 3)
            let stretches: [(x: CGFloat, w: CGFloat, lane: Int, stage: String)] = {
                var at = 0
                return phases.map { phase in
                    let x = geo.size.width * CGFloat(at) / CGFloat(total)
                    let w = geo.size.width * CGFloat(max(0, phase.minutes)) / CGFloat(total)
                    at += max(0, phase.minutes)
                    return (x, w, Self.lane(phase.stage), phase.stage)
                }
            }()
            ZStack(alignment: .topLeading) {
                ForEach(0..<4, id: \.self) { lane in
                    Rectangle()
                        .fill(StrandPalette.textPrimary.opacity(0.06))
                        .frame(height: 1)
                        .offset(y: CGFloat(lane) * laneHeight + laneHeight / 2)
                }
                Path { path in
                    for (i, s) in stretches.enumerated() {
                        let y = CGFloat(s.lane) * laneHeight + laneHeight / 2
                        if i == 0 { path.move(to: CGPoint(x: s.x, y: y)) } else { path.addLine(to: CGPoint(x: s.x, y: y)) }
                        path.addLine(to: CGPoint(x: s.x + s.w, y: y))
                    }
                }
                .stroke(StrandPalette.textPrimary.opacity(0.18), lineWidth: 1)
                ForEach(Array(stretches.enumerated()), id: \.offset) { _, s in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(DayWidgetPhaseBar.color(s.stage))
                        .frame(width: max(1, s.w - 0.6), height: barHeight)
                        .offset(x: s.x, y: CGFloat(s.lane) * laneHeight + (laneHeight - barHeight) / 2)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// The sleep widget (medium, v2): the night's length, onset and end, the debt and the suggested bedtime, the
/// hypnogram in four lanes and, under it, each stage's colour, name and total.
struct DaySleepWidgetFaceV2: View {
    let sleep: DayWidgetsSnapshot.Sleep?
    let labels: DayWidgetsSnapshot.Labels

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            DayWidgetTitle(symbol: "moon.fill", title: labels.sleepTitle, tint: StrandPalette.restRing,
                           trailing: sleep.flatMap { s -> String? in
                               guard let start = s.start, let end = s.end else { return nil }
                               return start + " \u{2192} " + end
                           })
            HStack(alignment: .center, spacing: 8) {
                Text(sleep?.night ?? labels.noData)
                    .font(sleep?.night == nil ? StrandFont.caption : StrandFont.number(24, weight: .bold))
                    .foregroundStyle(sleep?.night == nil ? StrandPalette.textSecondary : StrandPalette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 1) {
                    if let debt = sleep?.debt { DayWidgetEmphasisLine(line: debt) }
                    if let bedtime = sleep?.bedtime { DayWidgetEmphasisLine(line: bedtime) }
                }
            }
            if let phases = sleep?.phases, !phases.isEmpty {
                DayWidgetHypnogram(phases: phases)
                    .frame(maxHeight: .infinity)
            } else {
                Spacer(minLength: 0)
            }
            if let stages = sleep?.stages, !stages.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    ForEach(Array(stages.enumerated()), id: \.offset) { _, stage in
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(DayWidgetPhaseBar.color(stage.stage))
                                    .frame(width: 7, height: 7)
                                Text(stage.name)
                                    .font(StrandFont.caption2)
                                    .foregroundStyle(StrandPalette.textSecondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            Text(stage.length)
                                .font(StrandFont.number(12, weight: .semibold))
                                .foregroundStyle(StrandPalette.textPrimary)
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
