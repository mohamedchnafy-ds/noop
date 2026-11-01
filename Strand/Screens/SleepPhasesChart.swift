import SwiftUI
import StrandDesign
import WhoopStore

// MARK: - Stage lanes with curves (personal fork)
//
// The night as four tall lanes (Awake, REM, Light, Deep, top to bottom) on a shared clock axis, each
// stage drawn in its lane with thin risers between consecutive stages, the stage names inside the lanes so
// the plot takes the card's whole width. The curves the user switches on are placed by
// `SleepCurveLayout`: the sleeping heart rate and the windowed rMSSD ride over the lanes, the heart
// rate's scale on the right edge and the rMSSD's on the left; the skin temperature rides over them only
// when it is the one curve on, and otherwise gets a strip of its own under the lanes, as movement always
// does. Every curve has a printed scale with its unit. A touch (or a drag) on the chart reads the time,
// the stage and each curve's value at that moment, and a line per curve under the chart gives its range.
// The skin temperature is shown as its gap to the night's own median: a WHOOP 4.0's raw-to-°C mapping is
// provisional and its offset differs between straps (#938), so the absolute degrees can read 40 °C while
// the night's rise and dips still hold. Display only: the series arrive as read.

/// Where each curve goes, kept pure so it can be tested without drawing.
enum SleepCurveLayout {
    enum Curve: Equatable { case heartRate, hrv, skinTemp }

    /// Heart rate then rMSSD over the lanes (heart rate first, so its scale takes the right edge). The
    /// skin temperature goes over the lanes only when nothing else does; otherwise it sits in a strip
    /// below. Movement is not a line and is never part of this split: it always has its own strip.
    static func split(heartRate: Bool, hrv: Bool, skinTemp: Bool) -> (onStages: [Curve], below: [Curve]) {
        var onStages: [Curve] = []
        if heartRate { onStages.append(.heartRate) }
        if hrv { onStages.append(.hrv) }
        if onStages.isEmpty { return (skinTemp ? [.skinTemp] : [], []) }
        return (onStages, skinTemp ? [.skinTemp] : [])
    }
}

/// A curve's value axis: the values' range with a little room on each side, and round tick values
/// inside it (1, 2 or 5 times a power of ten), three to five of them.
struct SleepCurveScale: Equatable {
    let lo: Double
    let hi: Double
    let step: Double
    let ticks: [Double]

    /// Room left above and below the values, as a share of their range.
    static let padShare: Double = 0.06

    static func make(_ values: [Double]) -> SleepCurveScale? {
        let finite = values.filter(\.isFinite)
        guard var lo = finite.min(), var hi = finite.max() else { return nil }
        if hi - lo < 1e-9 {
            let half = max(abs(lo) * 0.02, 0.5)
            lo -= half
            hi += half
        }
        let pad = (hi - lo) * padShare
        lo -= pad
        hi += pad
        let range = hi - lo
        // The largest round step that still puts at least three ticks inside the range.
        var exponent = (log10(range)).rounded(.down)
        var chosen: (step: Double, ticks: [Double])?
        search: while exponent > -6 {
            for factor in [5.0, 2.0, 1.0] {
                let step = factor * pow(10, exponent)
                let ticks = Self.ticks(lo: lo, hi: hi, step: step)
                if ticks.count >= 3 {
                    chosen = (step, ticks)
                    break search
                }
            }
            exponent -= 1
        }
        guard let chosen else { return nil }
        var step = chosen.step
        var ticks = chosen.ticks
        // Never more than five labels: keep every other one.
        if ticks.count > 5 {
            ticks = ticks.enumerated().filter { $0.offset % 2 == 0 }.map(\.element)
            step *= 2
        }
        return SleepCurveScale(lo: lo, hi: hi, step: step, ticks: ticks)
    }

    private static func ticks(lo: Double, hi: Double, step: Double) -> [Double] {
        var out: [Double] = []
        var k = (lo / step).rounded(.up)
        while k * step <= hi + step * 1e-9 {
            // Rounded to the step's own precision, so 0.1 steps print as 33.5, not 33.499999.
            let digits = Double(Self.decimals(for: step))
            let scale = pow(10, digits)
            out.append((k * step * scale).rounded() / scale)
            k += 1
        }
        return out
    }

    /// Digits after the decimal point the ticks need: none for whole steps, one for 0.5 or 0.2.
    static func decimals(for step: Double) -> Int {
        step >= 1 ? 0 : Int((-log10(step)).rounded(.up))
    }

    var decimals: Int { Self.decimals(for: step) }

    /// The value's height as a fraction of the plot, 0 at the top.
    func y(_ value: Double) -> Double {
        (hi - value) / max(hi - lo, 1e-9)
    }
}

/// Pure helpers for the chart, kept apart so they can be tested without drawing.
enum SleepPhasesChartMath {
    /// A series' readings as (seconds from the night's start, value), inside the night's window plus a
    /// minute of slack on each side so the line reaches the edges.
    static func points(_ trend: [TrendPoint], nightStart: Date, origin: TimeInterval,
                       span: TimeInterval) -> [(t: TimeInterval, v: Double)] {
        trend.compactMap { p in
            let t = p.date.timeIntervalSince(nightStart)
            guard t >= origin - 60, t <= origin + span + 60, p.value.isFinite else { return nil }
            return (t, p.value)
        }
    }

    static func points(_ buckets: [HRBucket], nightStart: Date, origin: TimeInterval,
                       span: TimeInterval) -> [(t: TimeInterval, v: Double)] {
        let start = nightStart.timeIntervalSince1970
        return buckets.compactMap { b in
            let t = Double(b.ts) - start
            guard t >= origin - 60, t <= origin + span + 60, b.bpm.isFinite else { return nil }
            return (t, b.bpm)
        }
    }

    /// Each value minus the values' median, so a curve reads as its gap to its own night. Empty in, empty out.
    static func gapToMedian(_ values: [Double]) -> [Double] {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return [] }
        let n = sorted.count
        let median = n % 2 == 1 ? sorted[n / 2] : (sorted[n / 2 - 1] + sorted[n / 2]) / 2
        return values.map { $0 - median }
    }

    /// The reading closest to `t`, if one lies within `tolerance` seconds of it.
    static func value(at t: TimeInterval, in points: [(t: TimeInterval, v: Double)],
                      tolerance: TimeInterval = 300) -> Double? {
        guard let nearest = points.min(by: { abs($0.t - t) < abs($1.t - t) }),
              abs(nearest.t - t) <= tolerance else { return nil }
        return nearest.v
    }

    /// The stage under `t` (seconds from the night's start), nil between intervals.
    static func stage(at t: TimeInterval, in intervals: [SleepInterval]) -> SleepStage? {
        intervals.first { t >= $0.start && t < $0.end }?.stage
    }

    /// Whole clock hours inside the night's window, thinned to at most `maxLabels`.
    static func hourMarks(nightStart: Date, origin: TimeInterval, span: TimeInterval,
                          maxLabels: Int = 6, calendar: Calendar = .current) -> [Date] {
        let from = nightStart.addingTimeInterval(origin)
        let to = from.addingTimeInterval(span)
        guard span > 0, var t = calendar.nextDate(after: from.addingTimeInterval(-1),
                                                  matching: DateComponents(minute: 0, second: 0),
                                                  matchingPolicy: .nextTime) else { return [] }
        var marks: [Date] = []
        while t <= to {
            marks.append(t)
            t = t.addingTimeInterval(3600)
        }
        let step = max(1, Int((Double(marks.count) / Double(max(1, maxLabels))).rounded(.up)))
        return marks.enumerated().filter { $0.offset % step == 0 }.map(\.element)
    }
}

struct SleepPhasesChart: View {
    /// Display-smoothed stage intervals, seconds from `nightStart`.
    let intervals: [SleepInterval]
    let nightStart: Date
    let palette: SleepStagePalette
    var highlighted: SleepStage? = nil
    /// The curves to draw; an empty series is a curve switched off.
    var heartRate: [HRBucket] = []
    var hrv: [TrendPoint] = []
    var skinTemp: [TrendPoint] = []
    var motion: [Double] = []
    /// Height of one stage lane; the full-screen view passes a taller one.
    var laneHeight: CGFloat = 56
    /// Height of a curve's own strip under the lanes.
    var stripHeight: CGFloat = 84
    /// How far the plot reaches past its container on each side (the card's padding, so the plot runs
    /// edge to edge inside the card).
    var bleed: CGFloat = NoopMetrics.cardPadding
    /// A reading shown before any touch, in seconds from `nightStart` (the render test sets one).
    var initialReading: TimeInterval? = nil

    @State private var touched: TimeInterval?
    /// The moment being read: the last touch, or the seeded reading before any.
    private var reading: TimeInterval? { touched ?? initialReading }

    private static let lanes: [SleepStage] = [.awake, .rem, .light, .deep]
    private static let laneGap: CGFloat = 6
    private static let stripGap: CGFloat = 14
    private static let top: CGFloat = 16
    private static let axisHeight: CGFloat = 22
    private static let rightGutter: CGFloat = 40
    private static let leftGutterWithScale: CGFloat = 36
    private static let leftGutter: CGFloat = 12

    // MARK: Model

    private struct Series {
        let curve: SleepCurveLayout.Curve
        let points: [(t: TimeInterval, v: Double)]
        let scale: SleepCurveScale
    }

    private var origin: TimeInterval { intervals.map(\.start).min() ?? 0 }
    private var span: TimeInterval { max(1, (intervals.map(\.end).max() ?? 1) - origin) }

    private func series(_ curve: SleepCurveLayout.Curve) -> Series? {
        let pts: [(t: TimeInterval, v: Double)]
        switch curve {
        case .heartRate: pts = SleepPhasesChartMath.points(heartRate, nightStart: nightStart, origin: origin, span: span)
        case .hrv: pts = SleepPhasesChartMath.points(hrv, nightStart: nightStart, origin: origin, span: span)
        case .skinTemp:
            let raw = SleepPhasesChartMath.points(skinTemp, nightStart: nightStart, origin: origin, span: span)
            pts = Array(zip(raw.map(\.t), SleepPhasesChartMath.gapToMedian(raw.map(\.v)))).map { (t: $0.0, v: $0.1) }
        }
        guard pts.count >= 2, let scale = SleepCurveScale.make(pts.map(\.v)) else { return nil }
        return Series(curve: curve, points: pts, scale: scale)
    }

    private var placed: (onStages: [Series], below: [Series]) {
        let split = SleepCurveLayout.split(heartRate: heartRate.count >= 2, hrv: hrv.count >= 2,
                                           skinTemp: skinTemp.count >= 2)
        return (split.onStages.compactMap(series), split.below.compactMap(series))
    }

    private var showsMotion: Bool { motion.count >= 2 }

    // MARK: Geometry

    private struct Geometry {
        let left: CGFloat
        let plotWidth: CGFloat
        let stagesTop: CGFloat
        let stagesBottom: CGFloat
        let stripTops: [CGFloat]
        let motionTop: CGFloat?
        let axisY: CGFloat
        let height: CGFloat
    }

    private func geometry(width: CGFloat, strips: Int) -> Geometry {
        let left = placed.onStages.count > 1 ? Self.leftGutterWithScale : Self.leftGutter
        let plotWidth = max(1, width - left - Self.rightGutter)
        let stagesBottom = Self.top + laneHeight * 4 + Self.laneGap * 3
        var y = stagesBottom + Self.stripGap
        var tops: [CGFloat] = []
        for _ in 0..<strips {
            tops.append(y)
            y += stripHeight + Self.stripGap
        }
        var motionTop: CGFloat?
        if showsMotion {
            motionTop = y
            y += stripHeight + Self.stripGap
        }
        let axisY = y - Self.stripGap + 6
        return Geometry(left: left, plotWidth: plotWidth, stagesTop: Self.top, stagesBottom: stagesBottom,
                        stripTops: tops, motionTop: motionTop, axisY: axisY, height: axisY + Self.axisHeight)
    }

    private var chartHeight: CGFloat {
        geometry(width: 300, strips: placed.below.count).height
    }

    // MARK: Body

    var body: some View {
        let placed = self.placed
        VStack(alignment: .leading, spacing: NoopMetrics.space3) {
            readout(placed)
            GeometryReader { geo in
                let g = geometry(width: geo.size.width, strips: placed.below.count)
                ZStack(alignment: .topLeading) {
                    Canvas { ctx, size in draw(ctx, size: size, g: g, placed: placed) }
                    if showsMotion, let motionTop = g.motionTop {
                        MotionTrace(epochs: motion, height: stripHeight - 24, tint: StrandPalette.restColor)
                            .frame(width: g.plotWidth, height: stripHeight - 24)
                            .offset(x: g.left, y: motionTop + 22)
                            .allowsHitTesting(false)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture(coordinateSpace: .local)
                        .onEnded { setReading(x: $0.location.x, g: g) }
                        .exclusively(before:
                            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                                .onChanged { setReading(x: $0.location.x, g: g) }
                        )
                )
            }
            .frame(height: chartHeight)
            .padding(.horizontal, -bleed)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(accessibilitySummary(placed)))
            summary(placed)
        }
    }

    private func setReading(x: CGFloat, g: Geometry) {
        let frac = Double((x - g.left) / g.plotWidth)
        touched = origin + max(0, min(1, frac)) * span
    }

    // MARK: Readout and summary

    private func readout(_ placed: (onStages: [Series], below: [Series])) -> some View {
        Group {
            if let reading {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(AppClock.hourMinuteFormatter().string(from: nightStart.addingTimeInterval(reading)))
                            .font(StrandFont.subhead.weight(.semibold))
                            .foregroundStyle(StrandPalette.textPrimary)
                        if let stage = SleepPhasesChartMath.stage(at: reading, in: intervals) {
                            Circle().fill(StrandPalette.sleepStageColor(stage, palette: palette)).frame(width: 8, height: 8)
                            Text(stage.label)
                                .font(StrandFont.subhead.weight(.semibold))
                                .foregroundStyle(StrandPalette.textPrimary)
                        }
                    }
                    HStack(spacing: NoopMetrics.space3) {
                        ForEach(placed.onStages + placed.below, id: \.curve) { s in
                            if let v = SleepPhasesChartMath.value(at: reading, in: s.points) {
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Circle().fill(Self.tint(s.curve)).frame(width: 7, height: 7)
                                    Text(Self.number(v, Self.valueDecimals(s.curve), signed: s.curve == .skinTemp))
                                        .font(StrandFont.subhead.weight(.semibold))
                                        .foregroundStyle(Self.tint(s.curve))
                                    Text(Self.unit(s.curve))
                                        .font(StrandFont.footnote)
                                        .foregroundStyle(StrandPalette.textSecondary)
                                }
                            }
                        }
                    }
                }
            } else {
                Text("Touch the chart to read the time and the values")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
        .padding(.horizontal, NoopMetrics.space3)
        .padding(.vertical, 6)
        .background(StrandPalette.surfaceInset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(StrandPalette.hairlineStrong, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func summary(_ placed: (onStages: [Series], below: [Series])) -> some View {
        let all = placed.onStages + placed.below
        if !all.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(all, id: \.curve) { s in
                    let values = s.points.map(\.v)
                    let d = Self.valueDecimals(s.curve)
                    HStack(spacing: NoopMetrics.space2) {
                        Capsule().fill(Self.tint(s.curve)).frame(width: 14, height: 3)
                        Text(Self.name(s.curve))
                            .font(StrandFont.footnote.weight(.semibold))
                            .foregroundStyle(StrandPalette.textPrimary)
                            .frame(width: 92, alignment: .leading)
                        Text(Self.rangeText(s.curve, values: values, decimals: d))
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                }
            }
            .monospacedDigit()
        }
    }

    // MARK: Curve identity

    static func tint(_ curve: SleepCurveLayout.Curve) -> Color {
        switch curve {
        case .heartRate: StrandPalette.liquidHeart
        case .hrv: StrandPalette.accent
        case .skinTemp: StrandPalette.signalYellow
        }
    }

    static func name(_ curve: SleepCurveLayout.Curve) -> String {
        switch curve {
        case .heartRate: String(localized: "HR")
        case .hrv: String(localized: "HRV")
        case .skinTemp: String(localized: "Skin temp.")
        }
    }

    /// Units are symbols, not words: "ms" and "°C" stay as they are in every language.
    static func unit(_ curve: SleepCurveLayout.Curve) -> String {
        switch curve {
        case .heartRate: String(localized: "bpm")
        case .hrv: "ms"
        case .skinTemp: "°C"
        }
    }

    /// A strip's own title: the curve and its unit, and for the temperature what the values are measured from.
    static func stripTitle(_ curve: SleepCurveLayout.Curve) -> String {
        curve == .skinTemp
            ? "\(name(curve)) · \(String(localized: "vs the night")) (\(unit(curve)))"
            : "\(name(curve)) · \(unit(curve))"
    }

    /// Readings print whole except the skin temperature, which moves by tenths of a degree.
    static func valueDecimals(_ curve: SleepCurveLayout.Curve) -> Int { curve == .skinTemp ? 1 : 0 }

    /// A value as printed: `signed` puts a "+" before a gap above the median ("+0,4"), never before 0.
    private static func number(_ v: Double, _ decimals: Int, signed: Bool = false) -> String {
        let style = FloatingPointFormatStyle<Double>().precision(.fractionLength(decimals))
        return signed ? v.formatted(style.sign(strategy: .always(includingZero: false))) : v.formatted(style)
    }

    /// The line under the chart: the curve's lowest and highest, or for the temperature how far it went
    /// below and above the night's median.
    private static func rangeText(_ curve: SleepCurveLayout.Curve, values: [Double], decimals d: Int) -> String {
        let lo = values.min() ?? 0
        let hi = values.max() ?? 0
        if curve == .skinTemp {
            return String(localized: "from \(number(lo, d, signed: true)) to \(number(hi, d, signed: true)) \(unit(curve)) vs the night")
        }
        return String(localized: "lowest \(number(lo, d)) · highest \(number(hi, d)) \(unit(curve))")
    }

    // MARK: Drawing

    private func draw(_ ctx: GraphicsContext, size: CGSize, g: Geometry, placed: (onStages: [Series], below: [Series])) {
        func x(_ t: TimeInterval) -> CGFloat { g.left + CGFloat((t - origin) / span) * g.plotWidth }
        func laneY(_ stage: SleepStage) -> CGFloat {
            g.stagesTop + CGFloat(Self.lanes.firstIndex(of: stage) ?? 0) * (laneHeight + Self.laneGap)
        }
        let barHeight = (laneHeight * 0.43).rounded()
        func barMid(_ stage: SleepStage) -> CGFloat { laneY(stage) + laneHeight / 2 + 6 }

        // Hour hairlines and labels.
        let f = AppClock.hourMinuteFormatter()
        for mark in SleepPhasesChartMath.hourMarks(nightStart: nightStart, origin: origin, span: span) {
            let hx = x(mark.timeIntervalSince(nightStart))
            var line = Path()
            line.move(to: CGPoint(x: hx, y: g.stagesTop))
            line.addLine(to: CGPoint(x: hx, y: g.axisY - 4))
            ctx.stroke(line, with: .color(StrandPalette.hairline), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
            let label = ctx.resolve(Text(f.string(from: mark)).font(StrandFont.captionNumber)
                .foregroundColor(StrandPalette.textSecondary))
            ctx.draw(label, at: CGPoint(x: hx, y: g.axisY + 2), anchor: .top)
        }

        // Lanes, risers, stage bands.
        for stage in Self.lanes {
            let rect = CGRect(x: g.left, y: laneY(stage), width: g.plotWidth, height: laneHeight)
            ctx.fill(Path(roundedRect: rect, cornerRadius: 8), with: .color(StrandPalette.surfaceInset))
        }
        let sorted = intervals.sorted { $0.start < $1.start }
        for (a, b) in zip(sorted, sorted.dropFirst()) where a.stage != b.stage {
            var riser = Path()
            riser.move(to: CGPoint(x: x(a.end), y: barMid(a.stage)))
            riser.addLine(to: CGPoint(x: x(a.end), y: barMid(b.stage)))
            ctx.stroke(riser, with: .color(StrandPalette.hairlineStrong), lineWidth: 1)
        }
        for iv in sorted {
            let rect = CGRect(x: x(iv.start), y: barMid(iv.stage) - barHeight / 2,
                              width: max(2, x(iv.end) - x(iv.start)), height: barHeight)
            let dimmed = highlighted != nil && highlighted != iv.stage
            ctx.fill(Path(roundedRect: rect, cornerRadius: 5),
                     with: .color(StrandPalette.sleepStageColor(iv.stage, palette: palette).opacity(dimmed ? 0.25 : 1)))
        }

        // Curves over the lanes, each with its scale: the first on the right edge, the second on the left.
        let stageBand = (top: g.stagesTop + 8, height: g.stagesBottom - g.stagesTop - 16)
        for (index, s) in placed.onStages.enumerated() {
            stroke(ctx, s, x: x, band: stageBand)
            drawScale(ctx, s, band: stageBand, g: g, onLeft: index == 1)
        }

        // Stage names inside the lanes, over the curves, on a chip of the lane's own colour.
        for stage in Self.lanes {
            let dimmed = highlighted != nil && highlighted != stage
            chip(ctx, Text(stage.label).font(StrandFont.caption.weight(.semibold))
                    .foregroundColor(dimmed ? StrandPalette.textTertiary : StrandPalette.textSecondary),
                 at: CGPoint(x: g.left + 6, y: laneY(stage) + 4))
        }

        // Strips under the lanes.
        for (s, stripTop) in zip(placed.below, g.stripTops) {
            let rect = CGRect(x: g.left, y: stripTop, width: g.plotWidth, height: stripHeight)
            ctx.fill(Path(roundedRect: rect, cornerRadius: 8), with: .color(StrandPalette.surfaceInset))
            let band = (top: stripTop + 22, height: stripHeight - 30)
            for tick in s.scale.ticks {
                let ty = band.top + CGFloat(s.scale.y(tick)) * band.height
                var grid = Path()
                grid.move(to: CGPoint(x: g.left, y: ty))
                grid.addLine(to: CGPoint(x: g.left + g.plotWidth, y: ty))
                ctx.stroke(grid, with: .color(StrandPalette.hairline), lineWidth: 0.8)
            }
            stroke(ctx, s, x: x, band: band)
            drawScale(ctx, s, band: band, g: g, onLeft: false, withUnit: false)
            chip(ctx, Text(verbatim: Self.stripTitle(s.curve)).font(StrandFont.caption.weight(.semibold))
                    .foregroundColor(Self.tint(s.curve)),
                 at: CGPoint(x: g.left + 6, y: stripTop + 4))
        }
        if let motionTop = g.motionTop {
            let rect = CGRect(x: g.left, y: motionTop, width: g.plotWidth, height: stripHeight)
            ctx.fill(Path(roundedRect: rect, cornerRadius: 8), with: .color(StrandPalette.surfaceInset))
            chip(ctx, Text("Move, relative to tonight").font(StrandFont.caption.weight(.semibold))
                    .foregroundColor(StrandPalette.restColor),
                 at: CGPoint(x: g.left + 6, y: motionTop + 4))
        }

        // The reading: a line through everything and a dot on each curve.
        if let reading {
            let rx = x(reading)
            var line = Path()
            line.move(to: CGPoint(x: rx, y: g.stagesTop - 4))
            line.addLine(to: CGPoint(x: rx, y: g.axisY - 4))
            ctx.stroke(line, with: .color(StrandPalette.textPrimary.opacity(0.85)), lineWidth: 1.3)
            for s in placed.onStages {
                dot(ctx, s, at: reading, x: rx, band: stageBand)
            }
            for (s, stripTop) in zip(placed.below, g.stripTops) {
                dot(ctx, s, at: reading, x: rx, band: (top: stripTop + 22, height: stripHeight - 30))
            }
        }
    }

    private func stroke(_ ctx: GraphicsContext, _ s: Series, x: (TimeInterval) -> CGFloat,
                        band: (top: CGFloat, height: CGFloat)) {
        var path = Path()
        for (i, p) in s.points.enumerated() {
            let pt = CGPoint(x: x(p.t), y: band.top + CGFloat(s.scale.y(p.v)) * band.height)
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        // A dark halo so the line reads over any stage colour.
        ctx.stroke(path, with: .color(StrandPalette.surfaceRaised.opacity(0.8)),
                   style: StrokeStyle(lineWidth: 4.4, lineCap: .round, lineJoin: .round))
        ctx.stroke(path, with: .color(Self.tint(s.curve)),
                   style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
    }

    /// The scale's values printed beside the band, in the curve's colour (no tick marks: a dash before a
    /// number reads as a minus sign). Every other value is dropped when they would sit closer than a line
    /// of text apart, which happens in the short strips.
    private func drawScale(_ ctx: GraphicsContext, _ s: Series, band: (top: CGFloat, height: CGFloat),
                           g: Geometry, onLeft: Bool, withUnit: Bool = true) {
        let tint = Self.tint(s.curve)
        let edge = onLeft ? g.left : g.left + g.plotWidth
        var ticks = s.scale.ticks
        if ticks.count > 2 {
            let spacing = CGFloat(s.scale.y(ticks[0]) - s.scale.y(ticks[1])) * band.height
            if spacing < 18 {
                // Keep the zero line's label when there is one: it is the night's own reference.
                let keep = (ticks.firstIndex(of: 0) ?? 0) % 2
                ticks = ticks.enumerated().filter { $0.offset % 2 == keep }.map(\.element)
            }
        }
        for tick in ticks {
            let ty = band.top + CGFloat(s.scale.y(tick)) * band.height
            let label = ctx.resolve(Text(Self.number(tick, s.scale.decimals, signed: s.curve == .skinTemp))
                .font(StrandFont.captionNumber.weight(.semibold)).foregroundColor(tint))
            ctx.draw(label, at: CGPoint(x: onLeft ? edge - 6 : edge + 6, y: ty), anchor: onLeft ? .trailing : .leading)
        }
        if withUnit {
            let unit = ctx.resolve(Text(Self.unit(s.curve)).font(StrandFont.caption).foregroundColor(tint))
            ctx.draw(unit, at: CGPoint(x: onLeft ? edge - 6 : edge + 6, y: g.stagesTop - 3),
                     anchor: onLeft ? .bottomTrailing : .bottomLeading)
        }
    }

    private func dot(_ ctx: GraphicsContext, _ s: Series, at t: TimeInterval, x: CGFloat,
                     band: (top: CGFloat, height: CGFloat)) {
        guard let v = SleepPhasesChartMath.value(at: t, in: s.points) else { return }
        let y = band.top + CGFloat(s.scale.y(v)) * band.height
        let r: CGFloat = 4.5
        let circle = Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
        ctx.fill(circle, with: .color(Self.tint(s.curve)))
        ctx.stroke(circle, with: .color(StrandPalette.surfaceRaised), lineWidth: 1.5)
    }

    /// A label on a small rounded chip of the lane colour, so it stays readable over a curve.
    private func chip(_ ctx: GraphicsContext, _ text: Text, at origin: CGPoint) {
        let resolved = ctx.resolve(text)
        let s = resolved.measure(in: CGSize(width: 300, height: 40))
        let rect = CGRect(x: origin.x, y: origin.y, width: s.width + 8, height: s.height + 2)
        ctx.fill(Path(roundedRect: rect, cornerRadius: 5), with: .color(StrandPalette.surfaceInset.opacity(0.9)))
        ctx.draw(resolved, at: CGPoint(x: origin.x + 4, y: origin.y + 1), anchor: .topLeading)
    }

    private func accessibilitySummary(_ placed: (onStages: [Series], below: [Series])) -> String {
        var parts = [String(localized: "Sleep stages over the night")]
        for s in placed.onStages + placed.below {
            let values = s.points.map(\.v)
            let d = Self.valueDecimals(s.curve)
            parts.append("\(Self.name(s.curve)): \(Self.rangeText(s.curve, values: values, decimals: d))")
        }
        return parts.joined(separator: ". ")
    }
}
