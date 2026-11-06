import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopProtocol
import WhoopStore
#if os(iOS)
import CoreMotion
#endif

// MARK: - Today heart-rate card (personal fork)
//
// The same card as before (title, live number, subtitle, smoothed rose curve, Min / Avg / Max) with a
// Live | Day selector in the section head. Live draws the last 90 seconds over one light band, from the
// wearer's resting rate to their usual rate at this time of day. Day draws the 5-minute averages since
// midnight over the wearer's usual day, with the sleep in a blue band. No grid, no dotted lines, and no
// text inside the plot: every small label sits on one line under the curve, so the curve can never cover
// it. The curve turns orange when it stays away from the usual range while the wearer is still.

enum TodayHRMode: Hashable {
    case live
    case day
}

/// What the chart draws, already resolved to fractions of its width.
struct TodayHRChartModel: Equatable {
    struct Point: Equatable {
        /// 0…1 across the plot.
        var x: Double
        var bpm: Double
        /// Points sharing a run are joined; a new run starts after a gap in the recording.
        var run: Int
    }

    struct AxisLabel: Equatable {
        var x: Double
        var text: String
    }

    var points: [Point]
    /// Live: the light band between the two thresholds (the wearer's range while still).
    var band: ClosedRange<Double>? = nil
    /// Live: the high threshold, always drawn as a thin pale orange line.
    var highLine: Double? = nil
    /// Live: the low threshold, always drawn as a thin pale green line.
    var lowLine: Double? = nil
    /// Day: the usual day, drawn as a light area under this line.
    var habitual: [Point] = []
    /// Day: sleep, as 0…1 ranges across the plot.
    var sleep: [ClosedRange<Double>] = []
    /// The threshold crossed while still (the subtitle's alert); the curve itself is coloured by zone.
    var threshold: Double? = nil
    /// Which side of `threshold` the alert is on.
    var alertSide: TodayHRAlert.Side? = nil
    /// Fork chantier 9: the two thresholds as polylines across the plot (flat when live, following the
    /// usual day in the whole-day view). The curve is red above `zoneHigh`, green below `zoneLow`, pink
    /// between; each threshold is a dashed line of its zone's colour.
    var zoneHigh: [Point] = []
    var zoneLow: [Point] = []
    /// Ranges (0…1) the zones do not colour: sleep, where a low rate is expected.
    var zoneExclude: [ClosedRange<Double>] = []
    /// The halo on the last point: the curve reaches "now".
    var endDot: Bool = true
    var axis: [AxisLabel] = []
    /// The HUD style (fork chantier 13): a bpm scale on the right, the curve's lowest and highest points
    /// marked, and a drawn glow under the curve. Off, the chart is the one it was.
    var yAxis: Bool = false
    /// The unix seconds the plot spans, left to right, when the points sit on a clock (the whole day, and
    /// the HUD's live curve): the HUD's scrub then names the time of the point under the finger.
    var timeSpan: ClosedRange<Int>? = nil

    /// The time at `x` (0…1) across the plot, when the plot sits on a clock.
    func time(at x: Double) -> Int? {
        guard let span = timeSpan else { return nil }
        return span.lowerBound + Int((Double(span.upperBound - span.lowerBound) * x).rounded())
    }

    /// This chart with the HUD's bpm scale.
    var withYAxis: TodayHRChartModel {
        var chart = self
        chart.yAxis = true
        return chart
    }

    /// The plot mapping, shared by the drawing and the scrub readout so both point at the same place.
    struct Geometry {
        let rect: CGRect
        let low: Double
        let high: Double
        func x(_ f: Double) -> CGFloat { rect.minX + CGFloat(f) * rect.width }
        func y(_ bpm: Double) -> CGFloat {
            rect.maxY - CGFloat((bpm - low) / max(1, high - low)) * rect.height
        }
    }

    func geometry(in size: CGSize) -> Geometry {
        let rect = CGRect(x: 4, y: 8, width: max(1, size.width - (yAxis ? TodayHRChartModel.yAxisWidth : 14)),
                          height: max(1, size.height - 8 - (axis.isEmpty ? 6 : 22)))
        var values = points.map(\.bpm) + habitual.map(\.bpm)
        if let band { values += [band.lowerBound, band.upperBound] }
        values += [threshold, highLine, lowLine].compactMap { $0 }
        var lo = (values.min() ?? 60) - 3
        var hi = (values.max() ?? 80) + 3
        if hi - lo < 12 {
            let mid = (hi + lo) / 2
            lo = mid - 6
            hi = mid + 6
        }
        return Geometry(rect: rect, low: lo, high: hi)
    }

    /// The room the HUD's bpm labels take on the right.
    static let yAxisWidth: CGFloat = 32

    /// The bpm values the HUD's scale labels: round steps inside the plot, three or four of them.
    func yTicks(_ g: Geometry) -> [Double] {
        let span = g.high - g.low
        let step = [5.0, 10, 20, 30, 40, 50].first { span / $0 <= 4 } ?? 50
        var out: [Double] = []
        var v = (g.low / step).rounded(.up) * step
        while v <= g.high - step * 0.25 {
            if v >= g.low + step * 0.25 { out.append(v) }
            v += step
        }
        return out
    }

    /// Indices of the lowest and highest points, when there is a shape to mark.
    var extremes: (min: Int, max: Int)? {
        guard points.count >= 3,
              let lo = points.indices.min(by: { points[$0].bpm < points[$1].bpm }),
              let hi = points.indices.max(by: { points[$0].bpm < points[$1].bpm }),
              points[hi].bpm > points[lo].bpm else { return nil }
        return (lo, hi)
    }

    /// The point nearest a touch at `x` (in points), for the scrub readout.
    func nearest(toX x: CGFloat, geometry g: Geometry) -> Int? {
        guard !points.isEmpty else { return nil }
        return points.indices.min { abs(g.x(points[$0].x) - x) < abs(g.x(points[$1].x) - x) }
    }

    /// A threshold polyline's value at `x`, interpolated inside the run that spans it; nil outside.
    static func zoneValue(of line: [Point], at x: Double) -> Double? {
        for (a, b) in zip(line, line.dropFirst()) where a.run == b.run && a.x <= x && x <= b.x {
            guard b.x > a.x else { return a.bpm }
            return a.bpm + (b.bpm - a.bpm) * (x - a.x) / (b.x - a.x)
        }
        return line.count == 1 && line[0].x == x ? line[0].bpm : nil
    }

    /// The zone a point of the curve sits in, nil between the thresholds or where zones do not apply.
    func zone(of p: Point) -> TodayHRAlert.Side? {
        guard !zoneExclude.contains(where: { $0.contains(p.x) }) else { return nil }
        if let high = Self.zoneValue(of: zoneHigh, at: p.x), p.bpm > high { return .high }
        if let low = Self.zoneValue(of: zoneLow, at: p.x), p.bpm < low { return .low }
        return nil
    }

    /// The colour of a side: bright red above the high threshold, green below the low one (one style for
    /// every heart-rate curve with thresholds, `StrandPalette.hrZone*`).
    static func sideColor(_ side: TodayHRAlert.Side) -> Color {
        side == .high ? StrandPalette.hrZoneHigh : StrandPalette.hrZoneLow
    }
}

/// The chart itself: one Canvas, static (it redraws when its model changes, never on a clock).
struct TodayHRChart: View {
    var model: TodayHRChartModel
    var tint: Color
    var lineWidth: CGFloat

    private func smoothPath(_ pts: [CGPoint]) -> Path {
        var p = Path()
        guard let first = pts.first else { return p }
        p.move(to: first)
        guard pts.count > 1 else {
            p.addLine(to: CGPoint(x: first.x + 0.6, y: first.y))
            return p
        }
        for i in 1..<pts.count - 1 {
            let mid = CGPoint(x: (pts[i].x + pts[i + 1].x) / 2, y: (pts[i].y + pts[i + 1].y) / 2)
            p.addQuadCurve(to: mid, control: pts[i])
        }
        p.addLine(to: pts[pts.count - 1])
        return p
    }

    private func runs(_ points: [TodayHRChartModel.Point]) -> [[TodayHRChartModel.Point]] {
        var out: [[TodayHRChartModel.Point]] = []
        for p in points {
            if let last = out.last?.last, last.run == p.run { out[out.count - 1].append(p) } else { out.append([p]) }
        }
        return out
    }

    var body: some View {
        Canvas { ctx, size in
            let g = model.geometry(in: size)

            for range in model.sleep {
                let r = CGRect(x: g.x(range.lowerBound), y: g.rect.minY,
                               width: max(1, g.x(range.upperBound) - g.x(range.lowerBound)), height: g.rect.height)
                ctx.fill(Path(roundedRect: r, cornerRadius: 5), with: .color(StrandPalette.restBright.opacity(0.10)))
            }
            for run in runs(model.habitual) where run.count >= 2 {
                var area = smoothPath(run.map { CGPoint(x: g.x($0.x), y: g.y($0.bpm)) })
                area.addLine(to: CGPoint(x: g.x(run[run.count - 1].x), y: g.rect.maxY))
                area.addLine(to: CGPoint(x: g.x(run[0].x), y: g.rect.maxY))
                area.closeSubpath()
                ctx.fill(area, with: .color(StrandPalette.textPrimary.opacity(0.07)))
            }
            // Fork chantier 9: each threshold is a dashed line of its zone's colour (no filled band), kept
            // inside the plot even where the usual day plus the margin climbs above it.
            var plot = ctx
            plot.clip(to: Path(g.rect.insetBy(dx: 0, dy: -2)))
            for (line, side) in [(model.zoneHigh, TodayHRAlert.Side.high), (model.zoneLow, .low)] {
                var dashed = Path()
                for run in runs(line) where run.count >= 2 {
                    dashed.move(to: CGPoint(x: g.x(run[0].x), y: g.y(run[0].bpm)))
                    for p in run.dropFirst() { dashed.addLine(to: CGPoint(x: g.x(p.x), y: g.y(p.bpm))) }
                }
                plot.stroke(dashed, with: .color(TodayHRChartModel.sideColor(side).opacity(0.85)),
                            style: StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
            }

            var curve = Path()
            for run in runs(model.points) {
                curve.addPath(smoothPath(run.map { CGPoint(x: g.x($0.x), y: g.y($0.bpm)) }))
            }
            let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            if model.yAxis {
                // The HUD's scale (fork chantier 13): a faint rule and its value at each round step, the unit
                // on top; then the curve's drawn glow, a wide translucent copy (no blur, no shadow).
                for v in model.yTicks(g) {
                    var rule = Path()
                    rule.move(to: CGPoint(x: g.rect.minX, y: g.y(v)))
                    rule.addLine(to: CGPoint(x: g.rect.maxX, y: g.y(v)))
                    ctx.stroke(rule, with: .color(NoopHUDStyle.chrome.opacity(0.14)), lineWidth: 1)
                    let label = ctx.resolve(Text(verbatim: String(Int(v))).font(StrandFont.hudLabel)
                        .foregroundColor(NoopHUDStyle.textSecondary))
                    ctx.draw(label, at: CGPoint(x: g.rect.maxX + 5, y: g.y(v)), anchor: .leading)
                }
                let unit = ctx.resolve(Text("bpm").font(StrandFont.hudLabel)
                    .foregroundColor(NoopHUDStyle.textSecondary))
                ctx.draw(unit, at: CGPoint(x: g.rect.maxX + 5, y: g.rect.minY - 2), anchor: .leading)
                ctx.stroke(curve, with: .color(tint.opacity(0.22)),
                           style: StrokeStyle(lineWidth: lineWidth + 5, lineCap: .round, lineJoin: .round))
            }
            ctx.stroke(curve, with: .color(tint), style: style)
            // The curve over each zone, redrawn in the zone's colour: clipped to the region beyond the
            // threshold, and away from the excluded ranges (sleep).
            var outside = Path(CGRect(origin: .zero, size: size))
            for r in model.zoneExclude {
                outside.addRect(CGRect(x: g.x(r.lowerBound), y: 0,
                                       width: max(0, g.x(r.upperBound) - g.x(r.lowerBound)), height: size.height))
            }
            for (line, side) in [(model.zoneHigh, TodayHRAlert.Side.high), (model.zoneLow, .low)] {
                var region = Path()
                for run in runs(line) where run.count >= 2 {
                    let edgeY: CGFloat = side == .high ? 0 : size.height
                    region.move(to: CGPoint(x: g.x(run[0].x), y: edgeY))
                    for p in run { region.addLine(to: CGPoint(x: g.x(p.x), y: g.y(p.bpm))) }
                    region.addLine(to: CGPoint(x: g.x(run[run.count - 1].x), y: edgeY))
                    region.closeSubpath()
                }
                guard !region.isEmpty else { continue }
                var zoned = ctx
                zoned.clip(to: outside, style: FillStyle(eoFill: true))
                zoned.clip(to: region)
                zoned.stroke(curve, with: .color(TodayHRChartModel.sideColor(side)), style: style)
            }

            // The retained design marks "now" with one solid dot at the end of the curve, in its zone's colour.
            if model.endDot, let last = model.points.last {
                let c = CGPoint(x: g.x(last.x), y: g.y(last.bpm))
                let color = model.zone(of: last).map(TodayHRChartModel.sideColor) ?? tint
                let r = TodayHRCardBody.endDotSize / 2
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                         with: .color(color))
            }

            // The HUD marks the day's lowest and highest points with their value.
            if model.yAxis, let ext = model.extremes {
                for (index, below) in [(ext.min, true), (ext.max, false)] {
                    let p = model.points[index]
                    let c = CGPoint(x: g.x(p.x), y: g.y(p.bpm))
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - 2.5, y: c.y - 2.5, width: 5, height: 5)),
                             with: .color(NoopHUDStyle.text))
                    let text = ctx.resolve(Text(verbatim: String(Int(p.bpm.rounded()))).font(StrandFont.hudLabel)
                        .foregroundColor(NoopHUDStyle.text))
                    let x = min(max(c.x, g.rect.minX + 10), g.rect.maxX - 10)
                    ctx.draw(text, at: CGPoint(x: x, y: below ? c.y + 5 : c.y - 5),
                             anchor: below ? .top : .bottom)
                }
            }

            for (i, label) in model.axis.enumerated() {
                let text = ctx.resolve(Text(verbatim: label.text).font(StrandFont.caption)
                    .foregroundColor(StrandPalette.textSecondary))
                ctx.draw(text, at: CGPoint(x: g.x(label.x), y: size.height),
                         anchor: i == 0 ? .bottomLeading : .bottom)
            }
        }
        .accessibilityHidden(true)
    }
}

/// One entry of the line under the curve: plain text, or text after a small swatch of the chart colour.
struct TodayHRCaptionItem: Identifiable {
    enum Swatch { case usualDay, sleep, highLine, lowLine }
    let id = UUID()
    var text: String
    var swatch: Swatch? = nil
    /// Set when the item names a threshold the curve has crossed: the text takes that side's colour.
    var crossed: TodayHRAlert.Side? = nil
}

/// The card body: the same layout as before, with the new chart and the caption line. Pure, so the
/// render test draws the real card.
struct TodayHRCardBody: View {
    var tint: Color
    var bpm: Int?
    /// The heart before the number beats at `bpm` (fork chantier 12, 6 Nov. evening: the true rhythm, in
    /// place of the number's tick at each sample); false keeps it still (no live rate).
    var showsBeat: Bool = false
    /// The wave at the end of the curve beats with the heart: the live curve, whose last point is now.
    var pulsesCurve: Bool = false
    var subtitle: String
    /// The crossed side, when there is one: the subtitle takes its colour.
    var subtitleSide: TodayHRAlert.Side? = nil
    var chart: TodayHRChartModel?
    var lineWidth: CGFloat = 2.4
    var emptyText: String
    var caption: [TodayHRCaptionItem] = []
    var stats: (min: Double?, avg: Double?, max: Double?)
    /// Armed, the curve traces itself left to right once per launch (fork chantier 12); false draws it
    /// whole (render tests), and the heart and the wave stay still.
    var animated: Bool = false

    /// The beating heart before the number, and how far its bottom sits above the number's baseline.
    static let heartSize: CGFloat = 22
    static let heartLift: CGFloat = 2
    /// The "now" dot the curve draws at its end, and the wave's starting diameter.
    static let endDotSize: CGFloat = 8

    @State private var scrubX: CGFloat?
    #if os(iOS)
    @State private var scrubEngaged = false
    #endif
    @Environment(\.todayHUDStyle) private var hud

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Fork chantier 7: the live number large in SF Rounded, then "bpm · subtitle" in grey (the
            // crossed side's colour when the curve is past a threshold).
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let bpm {
                    // The heart at the true rhythm, in the crossed side's colour when there is one, else rose.
                    NoopHeartbeat(bpm: bpm, tint: subtitleSide.map(TodayHRChartModel.sideColor) ?? tint,
                                  size: Self.heartSize, beating: showsBeat && animated)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - Self.heartLift }
                    Text("\(bpm)")
                        .font(StrandFont.rounded(36))
                        .foregroundStyle(subtitleSide.map(TodayHRChartModel.sideColor) ?? StrandPalette.textPrimary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.easeOut(duration: 0.25), value: bpm)
                }
                Text(verbatim: bpmLine)
                    .font(StrandFont.subhead.weight(.medium))
                    .foregroundStyle(subtitleSide.map(TodayHRChartModel.sideColor) ?? StrandPalette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            if let source = chart, source.points.count >= 2 {
                // The HUD (fork chantier 13) adds its bpm scale; the scrub and the wave read the same model.
                let chart = hud ? source.withYAxis : source
                TodayHRChart(model: chart, tint: tint, lineWidth: lineWidth)
                    .noopRevealOnce("today.hr.curve", armed: animated)
                    .frame(height: chart.axis.isEmpty ? 104 : 124)
                    .contentShape(Rectangle())
                    .overlay { curvePulse(chart) }
                    .overlay { scrubReadout(chart) }
                    .onContinuousHover(coordinateSpace: .local) { phase in
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            switch phase {
                            case .active(let location): scrubX = location.x
                            case .ended: scrubX = nil
                            }
                        }
                    }
                    #if os(iOS)
                    .gesture(touchScrubGesture)
                    #endif
                if !caption.isEmpty { captionLine }
                HStack {
                    stat(String(localized: "Min"), stats.min)
                    Spacer()
                    stat(String(localized: "Avg"), stats.avg)
                    Spacer()
                    stat(String(localized: "Max"), stats.max)
                }
            } else {
                Text(emptyText)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 24)
            }
        }
    }

    /// "bpm · Live · resting zone" under a live number, the subtitle alone without one.
    private var bpmLine: String {
        bpm == nil ? subtitle : [String(localized: "bpm"), subtitle].joined(separator: " \u{00B7} ")
    }

    /// The caption in rows of three at most (fork chantier 9: the whole day adds its two thresholds).
    private var captionLine: some View {
        let rows = stride(from: 0, to: caption.count, by: 3).map { Array(caption[$0..<min($0 + 3, caption.count)]) }
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: NoopMetrics.space3) {
                    ForEach(rows[r]) { item in
                        HStack(spacing: 6) {
                            if let swatch = item.swatch { captionSwatch(swatch) }
                            Text(verbatim: item.text)
                                .foregroundStyle(item.crossed.map(TodayHRChartModel.sideColor) ?? StrandPalette.textSecondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .font(StrandFont.caption)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }

    /// A small sample of what the item names: a light area (usual day, sleep) or a thin line (a threshold).
    @ViewBuilder
    private func captionSwatch(_ swatch: TodayHRCaptionItem.Swatch) -> some View {
        switch swatch {
        case .usualDay, .sleep:
            RoundedRectangle(cornerRadius: 3)
                .fill(swatch == .sleep ? StrandPalette.restBright.opacity(0.45)
                                       : StrandPalette.textPrimary.opacity(0.22))
                .frame(width: 14, height: 10)
                .accessibilityHidden(true)
        case .highLine, .lowLine:
            Path { p in
                p.move(to: CGPoint(x: 0, y: 1))
                p.addLine(to: CGPoint(x: 14, y: 1))
            }
            .stroke(TodayHRChartModel.sideColor(swatch == .highLine ? .high : .low),
                    style: StrokeStyle(lineWidth: 2, dash: [3, 2]))
            .frame(width: 14, height: 2)
            .accessibilityHidden(true)
        }
    }

    private func stat(_ label: String, _ v: Double?) -> some View {
        HStack(spacing: 5) {
            Text(label).font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
            Text(v.map { String(Int($0.rounded())) } ?? "–")
                .font(StrandFont.subhead.weight(.semibold)).foregroundStyle(StrandPalette.textPrimary)
        }
    }

    private func scrubReadout(_ chart: TodayHRChartModel) -> some View {
        GeometryReader { geo in
            let g = chart.geometry(in: geo.size)
            if let scrubX, let i = chart.nearest(toX: scrubX, geometry: g) {
                let p = chart.points[i]
                let x = g.x(p.x), y = g.y(p.bpm)
                // The HUD's readout carries the time too, so it keeps further from the edges.
                let edge: CGFloat = chart.yAxis ? 60 : 40
                Path { path in
                    path.move(to: CGPoint(x: x, y: g.rect.minY))
                    path.addLine(to: CGPoint(x: x, y: g.rect.maxY))
                }
                .stroke(tint, lineWidth: NoopMetrics.hairlineWidth)
                Circle().fill(tint).frame(width: 8, height: 8).position(x: x, y: y)
                (scrubTime(chart, at: p.x)
                    + Text("\(Int(p.bpm.rounded()))").font(StrandFont.captionNumber)
                    + Text(" bpm").font(StrandFont.caption))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .padding(.horizontal, NoopMetrics.space2)
                    .padding(.vertical, NoopMetrics.space1)
                    .background(StrandPalette.surfaceBase.opacity(0.9), in: Capsule())
                    .position(x: min(max(x, edge), max(edge, geo.size.width - edge)), y: 12)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The HUD names the time of the point under the finger (« 11:20 · »); nothing elsewhere, or off a clock.
    private func scrubTime(_ chart: TodayHRChartModel, at x: Double) -> Text {
        guard chart.yAxis, let ts = chart.time(at: x) else { return Text(verbatim: "") }
        let time = AppClock.hourMinuteFormatter().string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
        return Text(verbatim: time).font(StrandFont.captionNumber) + Text(verbatim: TodayHUDDial.separator)
    }

    /// The wave at the end of the live curve, at each beat (fork chantier 12, 6 Nov. evening): on the "now"
    /// dot the chart draws, in the dot's colour, placed by the same plot mapping as the drawing.
    @ViewBuilder
    private func curvePulse(_ chart: TodayHRChartModel) -> some View {
        if pulsesCurve, animated, let bpm, chart.endDot, let last = chart.points.last {
            GeometryReader { geo in
                let g = chart.geometry(in: geo.size)
                NoopBeatPulse(bpm: bpm, tint: chart.zone(of: last).map(TodayHRChartModel.sideColor) ?? tint,
                              size: Self.endDotSize, beating: showsBeat)
                    .position(x: g.x(last.x), y: g.y(last.bpm))
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    #if os(iOS)
    private var touchScrubGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.25, maximumDistance: 8)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                if !scrubEngaged {
                    scrubEngaged = true
                    StrandHaptic.selection.play()
                }
                if let drag {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { scrubX = drag.location.x }
                }
            }
            .onEnded { _ in
                scrubEngaged = false
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { scrubX = nil }
            }
    }
    #endif
}

/// The selected day's inputs, resolved by the Today loader. Equatable so the live leaf only rebuilds
/// its day chart when these change, never on the 1 Hz heart-rate tick.
struct TodayHRDayInput: Equatable {
    var bucketTs: [Int] = []
    var bucketBpm: [Double] = []
    var segments: [String] = []
    /// Local midnight of the day shown, and where its axis ends (now for today, the next midnight else).
    var dayStart: Int = 0
    var domainEnd: Int = 0
    var isToday: Bool = true
    /// Slot (5 minutes after midnight) → usual bpm over the 14 days before (`HabitualHR`).
    var habitual: [Int: Double] = [:]
    var restingHR: Double?
    var awakeFloor: Double?
    /// Sleep inside the day, unix seconds.
    var sleep: [ClosedRange<Int>] = []
}

/// Pure builders for the two modes, kept apart from the view so tests can pin them.
enum TodayHRCardLogic {
    static let liveWindowSec = 90
    static let bufferSec = 300

    static func dayChart(_ day: TodayHRDayInput, zone: TimeZone) -> TodayHRChartModel {
        let span = Double(max(1, day.domainEnd - day.dayStart))
        func fx(_ ts: Int) -> Double { min(1, max(0, Double(ts - day.dayStart) / span)) }
        let runIds: [Int] = {
            guard day.segments.count == day.bucketTs.count else { return Array(repeating: 0, count: day.bucketTs.count) }
            var ids = Array(repeating: 0, count: day.bucketTs.count)
            for (i, run) in hrGapRuns(segments: day.segments).enumerated() { for j in run { ids[j] = i } }
            return ids
        }()
        let points = zip(day.bucketTs, day.bucketBpm).enumerated().map { i, pair in
            TodayHRChartModel.Point(x: fx(pair.0), bpm: pair.1, run: runIds[i])
        }
        var habitual: [TodayHRChartModel.Point] = []
        var run = 0
        var open = false
        var ts = day.dayStart
        while ts <= day.domainEnd {
            if let v = day.habitual[HabitualHR.slot(ts, zone: zone)] {
                habitual.append(.init(x: fx(ts), bpm: v, run: run))
                open = true
            } else if open {
                run += 1
                open = false
            }
            ts += HabitualHR.bucketSeconds
        }
        let sleep = day.sleep.compactMap { r -> ClosedRange<Double>? in
            let a = fx(max(r.lowerBound, day.dayStart)), b = fx(min(r.upperBound, day.domainEnd))
            return b > a ? a...b : nil
        }
        let (zoneHigh, zoneLow) = dayZones(day, zone: zone, fx: fx)
        var chart = TodayHRChartModel(points: points, habitual: habitual, sleep: sleep,
                                      zoneHigh: zoneHigh, zoneLow: zoneLow, zoneExclude: sleep,
                                      endDot: day.isToday, axis: axisLabels(day))
        chart.timeSpan = day.domainEnd > day.dayStart ? day.dayStart...day.domainEnd : nil
        return chart
    }

    /// The whole-day thresholds (fork chantier 9): at each 5-minute step, the SAME rule the live card
    /// applies now (`TodayHRAlert.thresholds`: the usual rate at that time plus the margin, the awake
    /// floor), so the dashed high line follows the usual day. A step with no usual rate breaks the run.
    static func dayZones(_ day: TodayHRDayInput, zone: TimeZone,
                         fx: (Int) -> Double) -> (high: [TodayHRChartModel.Point], low: [TodayHRChartModel.Point]) {
        var high: [TodayHRChartModel.Point] = [], low: [TodayHRChartModel.Point] = []
        var highRun = 0, lowRun = 0
        var highOpen = false, lowOpen = false
        var ts = day.dayStart
        while ts <= day.domainEnd {
            let usual = HabitualHR.usual(at: ts, profile: day.habitual, zone: zone)
            let t = TodayHRAlert.thresholds(usualNow: usual, awakeFloor: day.awakeFloor, restingHR: day.restingHR)
            if let h = t.high {
                high.append(.init(x: fx(ts), bpm: h, run: highRun)); highOpen = true
            } else if highOpen { highRun += 1; highOpen = false }
            if let l = t.low {
                low.append(.init(x: fx(ts), bpm: l, run: lowRun)); lowOpen = true
            } else if lowOpen { lowRun += 1; lowOpen = false }
            ts += HabitualHR.bucketSeconds
        }
        return (high, low)
    }

    /// Three to five round-hour labels from midnight, never the far end.
    static func axisLabels(_ day: TodayHRDayInput) -> [TodayHRChartModel.AxisLabel] {
        let spanH = Double(max(1, day.domainEnd - day.dayStart)) / 3600
        let step = [1, 2, 3, 4, 6, 8].first { spanH / Double($0) <= 4.2 } ?? 6
        let formatter = AppClock.hourMinuteFormatter()
        var out: [TodayHRChartModel.AxisLabel] = []
        var h = 0
        while Double(h) < spanH - 0.25 {
            let ts = day.dayStart + h * 3600
            out.append(.init(x: Double(h) / spanH,
                             text: formatter.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))))
            h += step
        }
        return out
    }

    /// The live curve. `onClock` (the HUD, fork chantier 13) places each sample at its own time and breaks the
    /// line across a pause in the stream; otherwise the samples sit evenly, as they always did.
    static func liveChart(samples: [(ts: Int, bpm: Double)], thresholds: TodayHRAlert.Thresholds,
                          alert: TodayHRAlert.Crossing?, onClock: Bool = false) -> TodayHRChartModel {
        let n = samples.count
        let first = samples.first?.ts ?? 0
        let last = samples.last?.ts ?? 0
        let timed = onClock && n > 1 && last > first
        var points: [TodayHRChartModel.Point] = []
        var run = 0
        for (i, s) in samples.enumerated() {
            if timed, i > 0, s.ts - samples[i - 1].ts > liveGapSec { run += 1 }
            let x = timed ? Double(s.ts - first) / Double(last - first) : (n > 1 ? Double(i) / Double(n - 1) : 1)
            points.append(TodayHRChartModel.Point(x: x, bpm: s.bpm, run: run))
        }
        let flat: (Double?) -> [TodayHRChartModel.Point] = { v in
            v.map { [.init(x: 0, bpm: $0, run: 0), .init(x: 1, bpm: $0, run: 0)] } ?? []
        }
        var chart = TodayHRChartModel(points: points, band: band(thresholds), highLine: thresholds.high,
                                      lowLine: thresholds.low, threshold: alert?.threshold,
                                      alertSide: alert?.side, zoneHigh: flat(thresholds.high),
                                      zoneLow: flat(thresholds.low), endDot: true)
        if timed { chart.timeSpan = first...last }
        return chart
    }

    /// A pause in the live stream longer than this breaks the HUD's timed curve.
    static let liveGapSec = 15

    /// The whole-day caption's two dashed thresholds (fork chantier 9): the high one follows the usual day
    /// (« high: usual + 20 »), or sits flat over the resting rate while calibrating; the low one is flat.
    static func dayZoneCaption(_ chart: TodayHRChartModel, habitual: Bool) -> [TodayHRCaptionItem] {
        var items: [TodayHRCaptionItem] = []
        if let high = chart.zoneHigh.first {
            let text = habitual
                ? String(localized: "high: usual + \(Int(TodayHRAlert.highMarginBpm))")
                : String(localized: "high \(Int(high.bpm.rounded()))")
            items.append(.init(text: text, swatch: .highLine))
        }
        if let low = chart.zoneLow.first {
            items.append(.init(text: String(localized: "low \(Int(low.bpm.rounded()))"), swatch: .lowLine))
        }
        return items
    }

    /// The live band: the range between the two thresholds, when both are known.
    static func band(_ thresholds: TodayHRAlert.Thresholds) -> ClosedRange<Double>? {
        guard let low = thresholds.low, let high = thresholds.high, low < high else { return nil }
        return low...high
    }

    /// The line under the live curve: each threshold with its colour, then "provisional thresholds" while
    /// they come from the resting rate. A crossed threshold takes its side's colour.
    static func liveCaption(_ thresholds: TodayHRAlert.Thresholds,
                            crossed: TodayHRAlert.Side?) -> [TodayHRCaptionItem] {
        var items: [TodayHRCaptionItem] = []
        if let low = thresholds.low {
            items.append(.init(text: String(localized: "low \(Int(low.rounded()))"), swatch: .lowLine,
                               crossed: crossed == .low ? .low : nil))
        }
        if let high = thresholds.high {
            items.append(.init(text: String(localized: "high \(Int(high.rounded()))"), swatch: .highLine,
                               crossed: crossed == .high ? .high : nil))
        }
        if thresholds.provisional, !items.isEmpty {
            items.append(.init(text: String(localized: "provisional thresholds")))
        }
        return items
    }
}

/// The phone's own motion, read only when the heart rate already looks away from its range: the strap
/// sends no motion while live, so "still" means the iPhone recorded no walking, running, cycling or
/// driving over the window. Nil (no sensor, no permission, no data) never lets the curve turn orange.
enum PhoneStillness {
    #if os(iOS)
    private static let manager = CMMotionActivityManager()

    static func isStill(seconds: Int, now: Date = Date()) async -> Bool? {
        guard CMMotionActivityManager.isActivityAvailable() else { return nil }
        switch CMMotionActivityManager.authorizationStatus() {
        case .denied, .restricted: return nil
        default: break
        }
        let start = now.addingTimeInterval(-TimeInterval(seconds))
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool?, Never>) in
            manager.queryActivityStarting(from: start.addingTimeInterval(-600), to: now, to: .main) { activities, error in
                guard error == nil, let activities, !activities.isEmpty else { cont.resume(returning: nil); return }
                let inWindow = activities.filter { $0.startDate >= start }
                let current = activities.last { $0.startDate < start }
                let relevant = inWindow + (current.map { [$0] } ?? [])
                let moving = relevant.contains { $0.walking || $0.running || $0.cycling || $0.automotive }
                cont.resume(returning: !moving && relevant.contains { $0.stationary })
            }
        }
    }
    #else
    static func isStill(seconds: Int, now: Date = Date()) async -> Bool? { nil }
    #endif
}

/// The heart-rate section: the head with the Live | Day selector, then the card. Owns LiveState so the
/// ~1 Hz heart-rate notifies re-render only this section, never the whole Today.
struct TodayHeartRateSection: View {
    var day: TodayHRDayInput
    var tint: Color = StrandPalette.liquidHeart

    @EnvironmentObject private var live: LiveState
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore

    @State private var buffer: [(ts: Int, bpm: Double)] = []
    @State private var chosenMode: TodayHRMode?
    @State private var sessionRunning = false
    @State private var phoneStill: Bool?
    @State private var gatesCheckedAt = 0
    @State private var checkingGates = false
    @Environment(\.todayHUDStyle) private var hud

    private var now: Int { Int(Date().timeIntervalSince1970) }
    private var liveSamples: [(ts: Int, bpm: Double)] {
        let from = now - TodayHRCardLogic.liveWindowSec
        return buffer.filter { $0.ts >= from }
    }
    private var liveAvailable: Bool { day.isToday && live.connected && liveSamples.count >= 2 }
    private var mode: TodayHRMode {
        switch chosenMode {
        case .day: return .day
        case .live: return liveAvailable ? .live : .day
        case nil: return liveAvailable ? .live : .day
        }
    }
    private var modeBinding: Binding<TodayHRMode> {
        Binding(get: { mode }, set: { chosenMode = $0 })
    }
    private var usualNow: Double? {
        guard day.isToday else { return nil }
        return HabitualHR.usual(at: now, profile: day.habitual, zone: .current)
    }
    private var thresholds: TodayHRAlert.Thresholds {
        TodayHRAlert.thresholds(usualNow: usualNow, awakeFloor: day.awakeFloor, restingHR: day.restingHR)
    }
    private var crossing: TodayHRAlert.Crossing? {
        guard day.isToday, live.connected else { return nil }
        return TodayHRAlert.crossing(samples: buffer, thresholds: thresholds, now: now)
    }
    private var alert: TodayHRAlert.Crossing? {
        TodayHRAlert.alert(crossing: crossing, sessionRunning: sessionRunning, phoneStill: phoneStill)
    }
    private var bigBpm: Int? {
        guard let hr = live.heartRate, hr > 0, live.connected, day.isToday else { return nil }
        return hr
    }

    var body: some View {
        // Fork chantier 7: one card holding the rose title (a link) and the Live | Day selector, then the
        // number and curve (a link too); the selector stays outside both links.
        VStack(alignment: .leading, spacing: 8) {
            TodayHRSectionHead(mode: modeBinding, liveEnabled: liveAvailable, tint: tint,
                               titleRoute: .fullDayChart)
            NavigationLink(value: TabRoute.fullDayChart) {
                card
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(LiquidPressStyle())
            .accessibilityHint("Opens the full-day heart rate timeline")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Fork chantier 13: the HUD panel edged in the heart rose, else the usual card.
        .modifier(TodayHUDCardSurface(hud: hud, accent: tint))
        .task(id: day.isToday) { await seedBuffer() }
        .onChangeCompat(of: live.heartRate) { hr in
            guard let hr, hr > 0 else { buffer.removeAll(); return }
            buffer.append((now, Double(hr)))
            let from = now - TodayHRCardLogic.bufferSec
            if let first = buffer.first, first.ts < from { buffer.removeAll { $0.ts < from } }
            refreshGatesIfNeeded()
        }
    }

    @ViewBuilder
    private var card: some View {
        switch mode {
        case .live: liveCard
        case .day: dayCard
        }
    }

    private var liveCard: some View {
        let samples = liveSamples
        let alert = self.alert
        let thresholds = self.thresholds
        let caption = TodayHRCardLogic.liveCaption(thresholds, crossed: alert?.side)
        let values = samples.map(\.bpm)
        return TodayHRCardBody(
            tint: tint,
            bpm: bigBpm, showsBeat: true, pulsesCurve: true,
            subtitle: liveSubtitle(alert: alert),
            subtitleSide: alert?.side,
            chart: TodayHRCardLogic.liveChart(samples: samples, thresholds: thresholds, alert: alert, onClock: hud),
            lineWidth: 2.5,
            emptyText: String(localized: "Waiting for a live heartbeat…"),
            caption: caption,
            stats: (values.min(), values.isEmpty ? nil : values.reduce(0, +) / Double(values.count), values.max()),
            animated: true)
    }

    private var dayCard: some View {
        let chart = TodayHRCardLogic.dayChart(day, zone: .current)
        var caption: [TodayHRCaptionItem] = []
        if !chart.habitual.isEmpty { caption.append(.init(text: String(localized: "your usual day"), swatch: .usualDay)) }
        if !chart.sleep.isEmpty { caption.append(.init(text: String(localized: "sleep"), swatch: .sleep)) }
        caption += TodayHRCardLogic.dayZoneCaption(chart, habitual: !day.habitual.isEmpty)
        if let rest = day.restingHR { caption.append(.init(text: String(localized: "rest \(Int(rest.rounded()))"))) }
        let values = day.bucketBpm
        return TodayHRCardBody(
            tint: tint,
            bpm: bigBpm, showsBeat: liveAvailable,
            subtitle: day.isToday ? String(localized: "5-minute average · since midnight")
                                  : String(localized: "5-minute average · that day"),
            chart: chart,
            lineWidth: 2,
            emptyText: live.connected ? String(localized: "Waiting for a live heartbeat…")
                                      : String(localized: "Connect your strap to see live heart rate"),
            caption: caption,
            stats: (values.min(), values.isEmpty ? nil : values.reduce(0, +) / Double(values.count), values.max()),
            animated: true)
    }

    private func liveSubtitle(alert: TodayHRAlert.Crossing?) -> String {
        if let alert {
            let minutes = alert.minutes(now: now)
            return alert.side == .high
                ? String(localized: "Higher than usual at rest · \(minutes) min")
                : String(localized: "Lower than usual while awake · \(minutes) min")
        }
        guard let hr = live.heartRate, hr > 0 else { return String(localized: "Live") }
        let zone = profile.hrZoneSet.zoneNumber(forBPM: Double(hr))
        return zone >= 1 ? String(localized: "Live · zone \(zone)") : String(localized: "Live · resting zone")
    }

    /// Fills the 5-minute buffer from the store (live beats are banked as they arrive), so the 3-minute
    /// rule does not have to wait three minutes of watching.
    private func seedBuffer() async {
        guard day.isToday else { buffer = []; return }
        let to = now
        let rows = await repo.hrSamples(from: to - TodayHRCardLogic.bufferSec, to: to, limit: 2_000)
        let seeded = rows.filter { $0.bpm > 0 }.map { (ts: $0.ts, bpm: Double($0.bpm)) }
        let newest = seeded.last?.ts ?? 0
        buffer = seeded + buffer.filter { $0.ts > newest }
    }

    /// The activity gates are read only while the heart rate already looks away from its range, at most
    /// every 20 seconds: a workout or Lift Log session in progress, and the phone's own motion.
    private func refreshGatesIfNeeded() {
        guard crossing != nil, !checkingGates, now - gatesCheckedAt >= 20 else { return }
        checkingGates = true
        Task {
            var running = app.activeWorkout != nil
            if !running, let store = await repo.storeHandle() {
                let t = Int(Date().timeIntervalSince1970)
                let rows = (try? await store.liftSessions(deviceId: repo.deviceId, fromTs: t - 6 * 3600, toTs: t)) ?? []
                running = rows.contains { $0.endTs == nil }
            }
            let still = await PhoneStillness.isStill(seconds: TodayHRAlert.minDurationSec)
            sessionRunning = running
            phoneStill = still
            gatesCheckedAt = Int(Date().timeIntervalSince1970)
            checkingGates = false
        }
    }
}
