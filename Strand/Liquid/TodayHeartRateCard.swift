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
    /// Live: the light band, resting rate to usual rate.
    var band: ClosedRange<Double>? = nil
    /// Day: the usual day, drawn as a light area under this line.
    var habitual: [Point] = []
    /// Day: sleep, as 0…1 ranges across the plot.
    var sleep: [ClosedRange<Double>] = []
    /// The threshold line, drawn only once crossed.
    var threshold: Double? = nil
    /// Which side of `threshold` turns orange.
    var alertSide: TodayHRAlert.Side? = nil
    /// The halo on the last point: the curve reaches "now".
    var endDot: Bool = true
    var axis: [AxisLabel] = []

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
        let rect = CGRect(x: 4, y: 8, width: max(1, size.width - 14),
                          height: max(1, size.height - 8 - (axis.isEmpty ? 6 : 22)))
        var values = points.map(\.bpm) + habitual.map(\.bpm)
        if let band { values += [band.lowerBound, band.upperBound] }
        if let threshold { values.append(threshold) }
        var lo = (values.min() ?? 60) - 3
        var hi = (values.max() ?? 80) + 3
        if hi - lo < 12 {
            let mid = (hi + lo) / 2
            lo = mid - 6
            hi = mid + 6
        }
        return Geometry(rect: rect, low: lo, high: hi)
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

    func isBeyond(_ bpm: Double) -> Bool {
        guard let threshold, let alertSide else { return false }
        return alertSide == .high ? bpm > threshold : bpm < threshold
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
            let warning = StrandPalette.statusWarning

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
            if let band = model.band {
                let top = g.y(band.upperBound), bottom = g.y(band.lowerBound)
                let r = CGRect(x: g.rect.minX, y: top, width: g.rect.width, height: max(2, bottom - top))
                ctx.fill(Path(roundedRect: r, cornerRadius: 4), with: .color(StrandPalette.textPrimary.opacity(0.07)))
            }
            if let threshold = model.threshold {
                var line = Path()
                line.move(to: CGPoint(x: g.rect.minX, y: g.y(threshold)))
                line.addLine(to: CGPoint(x: g.rect.maxX, y: g.y(threshold)))
                ctx.stroke(line, with: .color(warning.opacity(0.45)), lineWidth: 1)
            }

            var curve = Path()
            for run in runs(model.points) {
                curve.addPath(smoothPath(run.map { CGPoint(x: g.x($0.x), y: g.y($0.bpm)) }))
            }
            let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            ctx.stroke(curve, with: .linearGradient(Gradient(colors: [tint.opacity(0.55), tint]),
                                                    startPoint: CGPoint(x: g.rect.minX, y: 0),
                                                    endPoint: CGPoint(x: g.rect.maxX, y: 0)), style: style)
            if let threshold = model.threshold, let side = model.alertSide {
                var clipped = ctx
                let ty = g.y(threshold)
                let region = side == .high
                    ? CGRect(x: 0, y: 0, width: size.width, height: ty)
                    : CGRect(x: 0, y: ty, width: size.width, height: size.height - ty)
                clipped.clip(to: Path(region))
                clipped.stroke(curve, with: .color(warning), style: style)
            }

            func dot(_ p: TodayHRChartModel.Point, radius: CGFloat) {
                let c = CGPoint(x: g.x(p.x), y: g.y(p.bpm))
                let disc = Path(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2))
                ctx.fill(disc, with: .color(model.isBeyond(p.bpm) ? warning : tint))
                ctx.stroke(disc, with: .color(StrandPalette.surfaceRaised), lineWidth: 1.5)
            }
            if let ext = model.extremes {
                dot(model.points[ext.min], radius: 3.5)
                dot(model.points[ext.max], radius: 3.5)
            }
            if model.endDot, let last = model.points.last {
                let c = CGPoint(x: g.x(last.x), y: g.y(last.bpm))
                let color = model.isBeyond(last.bpm) ? warning : tint
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 9, y: c.y - 9, width: 18, height: 18)),
                         with: .color(color.opacity(0.25)))
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 4.5, y: c.y - 4.5, width: 9, height: 9)), with: .color(color))
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
    enum Swatch { case usualDay, sleep }
    let id = UUID()
    var text: String
    var swatch: Swatch? = nil
    var isWarning: Bool = false
}

/// The card body: the same layout as before, with the new chart and the caption line. Pure, so the
/// render test draws the real card.
struct TodayHRCardBody: View {
    var tint: Color
    var bpm: Int?
    var beat: Bool = false
    var showsBeat: Bool = false
    var subtitle: String
    var subtitleIsWarning: Bool = false
    var chart: TodayHRChartModel?
    var lineWidth: CGFloat = 2.4
    var emptyText: String
    var caption: [TodayHRCaptionItem] = []
    var stats: (min: Double?, avg: Double?, max: Double?)

    @State private var scrubX: CGFloat?
    #if os(iOS)
    @State private var scrubEngaged = false
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: NoopMetrics.space2) {
                HStack(spacing: NoopMetrics.space1) {
                    Text("BEATS PER MINUTE")
                        .font(StrandFont.overline)
                        .tracking(1.6)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(tint)
                        .fixedSize()
                        .accessibilityHidden(true)
                }
                .layoutPriority(1)
                Spacer(minLength: NoopMetrics.space2)
                if let bpm {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .scaleEffect(showsBeat ? (beat ? 1.15 : 0.9) : 1)
                            .animation(.easeOut(duration: 0.28), value: beat)
                            .accessibilityHidden(true)
                        Text("\(bpm)").font(StrandFont.rounded(28)).monospacedDigit()
                            .contentTransition(.numericText())
                            .animation(.easeOut(duration: 0.25), value: bpm)
                        Text("bpm").font(StrandFont.subhead)
                    }
                    .foregroundStyle(tint)
                }
            }
            Text(subtitle)
                .font(StrandFont.subhead)
                .foregroundStyle(subtitleIsWarning ? StrandPalette.statusWarning : StrandPalette.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if let chart, chart.points.count >= 2 {
                TodayHRChart(model: chart, tint: tint, lineWidth: lineWidth)
                    .frame(height: chart.axis.isEmpty ? 104 : 124)
                    .contentShape(Rectangle())
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

    private var captionLine: some View {
        HStack(spacing: NoopMetrics.space3) {
            ForEach(caption) { item in
                HStack(spacing: 6) {
                    if let swatch = item.swatch {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(swatch == .sleep ? StrandPalette.restBright.opacity(0.45)
                                                   : StrandPalette.textPrimary.opacity(0.22))
                            .frame(width: 14, height: 10)
                            .accessibilityHidden(true)
                    }
                    Text(verbatim: item.text)
                        .foregroundStyle(item.isWarning ? StrandPalette.statusWarning : StrandPalette.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .font(StrandFont.caption)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }

    private func stat(_ label: String, _ v: Double?) -> some View {
        HStack(spacing: 5) {
            Text(label).font(StrandFont.subhead).foregroundStyle(StrandPalette.textTertiary)
            Text(v.map { String(Int($0.rounded())) } ?? "–")
                .font(StrandFont.number(15)).foregroundStyle(StrandPalette.textPrimary)
        }
    }

    private func scrubReadout(_ chart: TodayHRChartModel) -> some View {
        GeometryReader { geo in
            let g = chart.geometry(in: geo.size)
            if let scrubX, let i = chart.nearest(toX: scrubX, geometry: g) {
                let p = chart.points[i]
                let x = g.x(p.x), y = g.y(p.bpm)
                Path { path in
                    path.move(to: CGPoint(x: x, y: g.rect.minY))
                    path.addLine(to: CGPoint(x: x, y: g.rect.maxY))
                }
                .stroke(tint, lineWidth: NoopMetrics.hairlineWidth)
                Circle().fill(tint).frame(width: 8, height: 8).position(x: x, y: y)
                (Text("\(Int(p.bpm.rounded()))").font(StrandFont.captionNumber)
                    + Text(" bpm").font(StrandFont.caption))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .padding(.horizontal, NoopMetrics.space2)
                    .padding(.vertical, NoopMetrics.space1)
                    .background(StrandPalette.surfaceBase.opacity(0.9), in: Capsule())
                    .position(x: min(max(x, 40), max(40, geo.size.width - 40)), y: 12)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
        return TodayHRChartModel(points: points, habitual: habitual, sleep: sleep,
                                 endDot: day.isToday, axis: axisLabels(day))
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

    static func liveChart(samples: [(ts: Int, bpm: Double)], band: ClosedRange<Double>?,
                          alert: TodayHRAlert.Crossing?) -> TodayHRChartModel {
        let n = samples.count
        let points = samples.enumerated().map { i, s in
            TodayHRChartModel.Point(x: n > 1 ? Double(i) / Double(n - 1) : 1, bpm: s.bpm, run: 0)
        }
        return TodayHRChartModel(points: points, band: band, threshold: alert?.threshold,
                                 alertSide: alert?.side, endDot: true)
    }

    /// The live band from the resting rate to the usual rate now, in either order.
    static func band(resting: Double?, usual: Double?) -> ClosedRange<Double>? {
        guard let resting, let usual else { return nil }
        return min(resting, usual)...max(resting, usual)
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
    @State private var beat = false
    @State private var chosenMode: TodayHRMode?
    @State private var sessionRunning = false
    @State private var phoneStill: Bool?
    @State private var gatesCheckedAt = 0
    @State private var checkingGates = false

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
        TodayHRAlert.thresholds(usualNow: usualNow, awakeFloor: day.awakeFloor)
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
        VStack(spacing: 8) {
            TodayHRSectionHead(mode: modeBinding, liveEnabled: liveAvailable)
            NavigationLink(value: TabRoute.fullDayChart) {
                card
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(NoopPanelSurface(cornerRadius: 22))
            }
            .buttonStyle(LiquidPressStyle())
            .accessibilityHint("Opens the full-day heart rate timeline")
        }
        .task(id: day.isToday) { await seedBuffer() }
        .onChangeCompat(of: live.heartRate) { hr in
            guard let hr, hr > 0 else { buffer.removeAll(); return }
            buffer.append((now, Double(hr)))
            let from = now - TodayHRCardLogic.bufferSec
            if let first = buffer.first, first.ts < from { buffer.removeAll { $0.ts < from } }
            beat.toggle()
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
        let band = TodayHRCardLogic.band(resting: day.restingHR, usual: usualNow)
        var caption: [TodayHRCaptionItem] = []
        if let rest = day.restingHR, let usual = usualNow {
            caption.append(.init(text: String(localized: "rest \(Int(rest.rounded())) → usual \(Int(usual.rounded()))")))
        } else if let rest = day.restingHR {
            caption.append(.init(text: String(localized: "rest \(Int(rest.rounded()))")))
        }
        if let alert {
            caption.append(.init(text: String(localized: "threshold \(Int(alert.threshold.rounded()))"), isWarning: true))
        }
        let values = samples.map(\.bpm)
        return TodayHRCardBody(
            tint: alert == nil ? tint : StrandPalette.statusWarning,
            bpm: bigBpm, beat: beat, showsBeat: true,
            subtitle: liveSubtitle(alert: alert),
            subtitleIsWarning: alert != nil,
            chart: TodayHRCardLogic.liveChart(samples: samples, band: band, alert: alert),
            lineWidth: 2.5,
            emptyText: String(localized: "Waiting for a live heartbeat…"),
            caption: caption,
            stats: (values.min(), values.isEmpty ? nil : values.reduce(0, +) / Double(values.count), values.max()))
    }

    private var dayCard: some View {
        let chart = TodayHRCardLogic.dayChart(day, zone: .current)
        var caption: [TodayHRCaptionItem] = []
        if !chart.habitual.isEmpty { caption.append(.init(text: String(localized: "your usual day"), swatch: .usualDay)) }
        if !chart.sleep.isEmpty { caption.append(.init(text: String(localized: "sleep"), swatch: .sleep)) }
        if let rest = day.restingHR { caption.append(.init(text: String(localized: "rest \(Int(rest.rounded()))"))) }
        let values = day.bucketBpm
        return TodayHRCardBody(
            tint: tint,
            bpm: bigBpm, beat: beat, showsBeat: liveAvailable,
            subtitle: day.isToday ? String(localized: "5-minute average · since midnight")
                                  : String(localized: "5-minute average · that day"),
            chart: chart,
            lineWidth: 2,
            emptyText: live.connected ? String(localized: "Waiting for a live heartbeat…")
                                      : String(localized: "Connect your strap to see live heart rate"),
            caption: caption,
            stats: (values.min(), values.isEmpty ? nil : values.reduce(0, +) / Double(values.count), values.max()))
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
