import SwiftUI
import StrandDesign
import WhoopStore

// MARK: - Stage lanes with curves on top (personal fork)
//
// The night as four labelled lanes (Awake, REM, Light, Deep, top to bottom) on a shared clock axis, each
// stage drawn in its lane with thin risers between consecutive stages. Curves the user switches on ride
// over the lanes on scales of their own: the sleeping heart rate (with the night's lowest reading
// marked), the windowed rMSSD and the skin temperature. Display only: the series arrive as read.

/// Pure geometry for the curves, kept apart so it can be tested without drawing.
enum SleepPhasesChartMath {
    /// Vertical room left free above and below a curve inside the lanes band (fractions of its height).
    static let topInset: Double = 0.06
    static let bottomInset: Double = 0.08

    /// A series' points as (x, y) fractions of the plot, x from the night's own time axis, y on the
    /// series' own min–max range. Nil under two visible points.
    static func curve(_ points: [TrendPoint], nightStart: Date, origin: TimeInterval,
                      span: TimeInterval) -> [(x: Double, y: Double)]? {
        guard span > 0 else { return nil }
        let visible = points.filter {
            let rel = $0.date.timeIntervalSince(nightStart)
            return rel >= origin - 60 && rel <= origin + span + 60 && $0.value.isFinite
        }
        guard visible.count >= 2 else { return nil }
        let values = visible.map(\.value)
        let lo = values.min() ?? 0
        let hi = values.max() ?? 1
        let range = max(hi - lo, 1e-9)
        let band = 1 - topInset - bottomInset
        return visible.map { p in
            let x = (p.date.timeIntervalSince(nightStart) - origin) / span
            return (max(0, min(1, x)), topInset + (1 - (p.value - lo) / range) * band)
        }
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
    var heartRate: [HRBucket] = []
    var hrv: [TrendPoint] = []
    var skinTemp: [TrendPoint] = []

    static let laneHeight: CGFloat = 22
    static let laneGap: CGFloat = 8
    static let labelWidth: CGFloat = 66
    static let gutter: CGFloat = 28
    private static let lanes: [SleepStage] = [.awake, .rem, .light, .deep]

    private var plotHeight: CGFloat { Self.laneHeight * 4 + Self.laneGap * 3 }
    private var origin: TimeInterval { intervals.map(\.start).min() ?? 0 }
    private var span: TimeInterval { max(1, (intervals.map(\.end).max() ?? 1) - origin) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: Self.laneGap) {
                    ForEach(Self.lanes, id: \.self) { stage in
                        Text(stage.label)
                            .font(StrandFont.caption)
                            .foregroundStyle(highlighted == nil || highlighted == stage
                                             ? StrandPalette.textSecondary : StrandPalette.textTertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(width: Self.labelWidth, height: Self.laneHeight, alignment: .leading)
                    }
                }
                Canvas { ctx, size in draw(ctx, size: size) }
                    .frame(height: plotHeight)
            }
            axis
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilitySummary))
    }

    private var axis: some View {
        GeometryReader { geo in
            let plotWidth = max(1, geo.size.width - Self.labelWidth - 8 - Self.gutter)
            let f = AppClock.hourMinuteFormatter()
            ForEach(SleepPhasesChartMath.hourMarks(nightStart: nightStart, origin: origin, span: span),
                    id: \.self) { mark in
                let x = Self.labelWidth + 8 + CGFloat((mark.timeIntervalSince(nightStart) - origin) / span) * plotWidth
                Text(f.string(from: mark))
                    .font(StrandFont.captionNumber)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize()
                    .position(x: x, y: 7)
            }
        }
        .frame(height: 14)
    }

    // MARK: Drawing

    private func draw(_ ctx: GraphicsContext, size: CGSize) {
        let plotWidth = max(1, size.width - Self.gutter)
        func x(_ t: TimeInterval) -> CGFloat { CGFloat((t - origin) / span) * plotWidth }
        func laneY(_ stage: SleepStage) -> CGFloat {
            CGFloat(Self.lanes.firstIndex(of: stage) ?? 0) * (Self.laneHeight + Self.laneGap)
        }

        // Hour hairlines behind everything.
        for mark in SleepPhasesChartMath.hourMarks(nightStart: nightStart, origin: origin, span: span) {
            let hx = x(mark.timeIntervalSince(nightStart))
            var line = Path()
            line.move(to: CGPoint(x: hx, y: 0))
            line.addLine(to: CGPoint(x: hx, y: plotHeight))
            ctx.stroke(line, with: .color(StrandPalette.hairline),
                       style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
        }
        // Lane tracks.
        for stage in Self.lanes {
            let rect = CGRect(x: 0, y: laneY(stage), width: plotWidth, height: Self.laneHeight)
            ctx.fill(Path(roundedRect: rect, cornerRadius: 5), with: .color(StrandPalette.surfaceInset))
        }
        // Risers between consecutive stages.
        let sorted = intervals.sorted { $0.start < $1.start }
        for (a, b) in zip(sorted, sorted.dropFirst()) where a.stage != b.stage {
            let rx = x(a.end)
            var riser = Path()
            riser.move(to: CGPoint(x: rx, y: laneY(a.stage) + Self.laneHeight / 2))
            riser.addLine(to: CGPoint(x: rx, y: laneY(b.stage) + Self.laneHeight / 2))
            ctx.stroke(riser, with: .color(StrandPalette.hairlineStrong), lineWidth: 1)
        }
        // Stage bands.
        for iv in sorted {
            let rect = CGRect(x: x(iv.start), y: laneY(iv.stage) + 4,
                              width: max(1.5, x(iv.end) - x(iv.start)), height: Self.laneHeight - 8)
            let dimmed = highlighted != nil && highlighted != iv.stage
            ctx.fill(Path(roundedRect: rect, cornerRadius: 3),
                     with: .color(StrandPalette.sleepStageColor(iv.stage, palette: palette).opacity(dimmed ? 0.25 : 1)))
        }

        let plot = CGSize(width: plotWidth, height: plotHeight)
        if let points = SleepPhasesChartMath.curve(skinTemp, nightStart: nightStart, origin: origin, span: span) {
            strokeCurve(ctx, points, in: plot, tint: StrandPalette.signalYellow)
        }
        if let points = SleepPhasesChartMath.curve(hrv, nightStart: nightStart, origin: origin, span: span) {
            strokeCurve(ctx, points, in: plot, tint: StrandPalette.accent)
        }
        drawHeartRate(ctx, plot: plot, gutterX: plotWidth)
    }

    private func strokeCurve(_ ctx: GraphicsContext, _ points: [(x: Double, y: Double)], in plot: CGSize, tint: Color) {
        var path = Path()
        for (i, p) in points.enumerated() {
            let pt = CGPoint(x: CGFloat(p.x) * plot.width, y: CGFloat(p.y) * plot.height)
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        // A dark halo so the line reads over any stage colour.
        ctx.stroke(path, with: .color(StrandPalette.surfaceRaised.opacity(0.7)),
                   style: StrokeStyle(lineWidth: 3.2, lineCap: .round, lineJoin: .round))
        ctx.stroke(path, with: .color(tint),
                   style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
    }

    private func drawHeartRate(_ ctx: GraphicsContext, plot: CGSize, gutterX: CGFloat) {
        guard let layout = SleepHROverlayMath.layout(buckets: heartRate,
                                                    nightStartTs: nightStart.timeIntervalSince1970,
                                                    origin: origin, span: span) else { return }
        let tint = StrandPalette.liquidHeart
        let points = layout.points.map { (x: $0.xFrac, y: $0.yFrac) }
        strokeCurve(ctx, points, in: plot, tint: tint)

        if let i = layout.minIndex {
            let p = layout.points[i]
            let c = CGPoint(x: CGFloat(p.xFrac) * plot.width, y: CGFloat(p.yFrac) * plot.height)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 3.5, y: c.y - 3.5, width: 7, height: 7)), with: .color(tint))
            let label = ctx.resolve(Text(verbatim: "\(Int(p.bpm.rounded()))")
                .font(StrandFont.captionNumber.weight(.semibold)).foregroundColor(tint))
            let s = label.measure(in: plot)
            let onLeft = c.x < plot.width * 0.75
            let lx = onLeft ? c.x + 7 : c.x - 7 - s.width - 6
            let ly = min(plot.height - s.height - 2, max(0, c.y - s.height / 2))
            ctx.fill(Path(roundedRect: CGRect(x: lx, y: ly, width: s.width + 6, height: s.height + 2), cornerRadius: 5),
                     with: .color(StrandPalette.surfaceRaised))
            ctx.draw(label, at: CGPoint(x: lx + 3, y: ly + 1), anchor: .topLeading)
        }
        // The top of the bpm scale in the gutter, so the line's height means something.
        let maxBpm = layout.points.map(\.bpm).max() ?? layout.hi
        let hi = ctx.resolve(Text(verbatim: "\(Int(maxBpm.rounded()))")
            .font(StrandFont.captionNumber.weight(.semibold)).foregroundColor(tint))
        ctx.draw(hi, at: CGPoint(x: gutterX + 4, y: CGFloat(SleepHROverlayMath.topInset) * plot.height), anchor: .topLeading)
    }

    private var accessibilitySummary: String {
        var parts: [String] = []
        if let lowest = heartRate.map(\.bpm).min() {
            parts.append(String(localized: "Heart rate, lowest \(Int(lowest.rounded())) bpm"))
        }
        if !hrv.isEmpty { parts.append(String(localized: "HRV curve shown")) }
        if !skinTemp.isEmpty { parts.append(String(localized: "Skin temperature curve shown")) }
        let stages = String(localized: "Sleep stages over the night")
        return ([stages] + parts).joined(separator: ". ")
    }
}
