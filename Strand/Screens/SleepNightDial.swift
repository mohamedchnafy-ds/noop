import SwiftUI
import StrandDesign

// MARK: - Night dial (personal fork)
//
// The Sleep tab's hero: a 12-hour clock face with the night drawn on it. The thick arc runs from the
// moment sleep began to the wake time, coloured by stage, with every awake stretch left as a gap. A thin
// dashed arc outside it covers the sleep need counted back from the wake time, so a short night reads as
// the part of the need it did not cover. The score (or, without one, the time asleep) sits in the
// middle. Over the night scene the face sits on a dark disc with a light edge along the night, so the
// darkest stage colour still reads against the photograph. Display only: every number arrives from the
// caller.

/// Pure geometry for `SleepNightDial`, kept apart so it can be tested without drawing.
enum SleepNightDialMath {
    /// One drawn stretch of the stage arc, in degrees clockwise from 12 o'clock. `end` may exceed 360
    /// when the night crosses the top of the dial.
    struct Arc: Equatable {
        let stage: SleepStage
        let start: Double
        let end: Double
    }

    /// Degrees per hour on a 12-hour face.
    static let degreesPerHour: Double = 30

    /// A local clock time as fractional hours (0 ..< 24).
    static func clockHours(_ date: Date, calendar: Calendar = .current) -> Double {
        let c = calendar.dateComponents([.hour, .minute, .second], from: date)
        return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60 + Double(c.second ?? 0) / 3600
    }

    /// The dial angle of a clock time, 0 ..< 360, 12 o'clock at 0.
    static func angle(hours: Double) -> Double {
        let h = hours.truncatingRemainder(dividingBy: 12)
        return (h < 0 ? h + 12 : h) * degreesPerHour
    }

    /// The asleep stretches of the night as arcs. Awake stretches are left out (gaps). Intervals are in
    /// seconds from the onset; anything past twelve hours after it would lap the face and is dropped.
    static func arcs(intervals: [SleepInterval], onsetHours: Double) -> [Arc] {
        let start = angle(hours: onsetHours)
        let limit: TimeInterval = 12 * 3600
        return intervals
            .filter { $0.stage != .awake && $0.end > $0.start && $0.start < limit }
            .sorted { $0.start < $1.start }
            .map { iv in
                Arc(stage: iv.stage,
                    start: start + iv.start / 3600 * degreesPerHour,
                    end: start + min(iv.end, limit) / 3600 * degreesPerHour)
            }
    }

    /// The need arc: `needMinutes` counted back from the wake time. A need of twelve hours or more
    /// fills the face.
    static func needArc(wakeHours: Double, needMinutes: Double) -> (start: Double, end: Double) {
        let end = angle(hours: wakeHours) + 360
        let sweep = min(360, max(0, needMinutes) / 60 * degreesPerHour)
        return (end - sweep, end)
    }
}

struct SleepNightDial: View {
    let onset: Date
    let wake: Date
    /// The night's stage intervals, seconds from `onset` (display-smoothed by the caller).
    let intervals: [SleepInterval]
    let palette: SleepStagePalette
    /// The sleep need to draw counted back from the wake time; nil hides the dashed arc.
    let needMinutes: Double?
    let score: Double?
    let scoreWord: String?
    let asleepMinutes: Double
    /// True over the night scene (light-on-dark text), false over the plain canvas.
    var onScene: Bool = true
    var diameter: CGFloat = 256

    private let ringRadius: CGFloat = 88
    private let ringWidth: CGFloat = 18
    /// How far the dark disc behind the face reaches past the ring's centre line.
    private let plateReach: CGFloat = 21

    private var primary: Color { onScene ? StrandPalette.onDarkPrimary : StrandPalette.textPrimary }
    private var secondary: Color { onScene ? StrandPalette.onDarkSecondary : StrandPalette.textSecondary }

    var body: some View {
        let onsetH = SleepNightDialMath.clockHours(onset)
        let wakeH = SleepNightDialMath.clockHours(wake)
        let arcs = SleepNightDialMath.arcs(intervals: intervals, onsetHours: onsetH)
        let need = needMinutes.map { SleepNightDialMath.needArc(wakeHours: wakeH, needMinutes: $0) }
        let nightStart = SleepNightDialMath.angle(hours: onsetH)
        let nightEnd = nightStart + min(360, max(0, wake.timeIntervalSince(onset)) / 3600 * SleepNightDialMath.degreesPerHour)
        let needStartLabel = needMinutes.map {
            AppClock.hourMinuteFormatter().string(from: wake.addingTimeInterval(-$0 * 60))
        }
        ZStack {
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                drawFace(ctx, center: c)
                if let need { drawNeed(ctx, center: c, arc: need, label: needStartLabel) }
                for arc in arcs {
                    ctx.stroke(arcPath(center: c, radius: ringRadius, from: arc.start, to: arc.end),
                               with: .color(StrandPalette.sleepStageColor(arc.stage, palette: palette)),
                               style: StrokeStyle(lineWidth: ringWidth, lineCap: .butt))
                }
                drawNightEdges(ctx, center: c, arcs: arcs, from: nightStart, to: nightEnd)
            }
            marker("moon.fill", at: SleepNightDialMath.angle(hours: onsetH))
            marker("sun.max.fill", at: SleepNightDialMath.angle(hours: wakeH))
            center
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilitySummary(needStart: needStartLabel)))
    }

    // MARK: Drawing

    private func drawFace(_ ctx: GraphicsContext, center c: CGPoint) {
        if onScene {
            let r = ringRadius + plateReach
            let plate = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            ctx.fill(plate, with: .color(StrandPalette.heroFill))
            ctx.stroke(plate, with: .color(StrandPalette.heroBorder), lineWidth: 1)
        }
        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - ringRadius, y: c.y - ringRadius,
                                          width: ringRadius * 2, height: ringRadius * 2)),
                   with: .color(primary.opacity(0.13)), lineWidth: ringWidth)
        for h in 0..<12 {
            let a = Double(h) * SleepNightDialMath.degreesPerHour
            let major = h % 3 == 0
            let outer = ringRadius - ringWidth / 2 - 4
            let inner = outer - (major ? 5 : 3)
            var tick = Path()
            tick.move(to: point(c, outer, a))
            tick.addLine(to: point(c, inner, a))
            ctx.stroke(tick, with: .color(secondary.opacity(0.7)), lineWidth: major ? 1.6 : 1)
        }
        for h in [0, 3, 6, 9] {
            let text = ctx.resolve(Text(String(localized: "\(h)h"))
                .font(StrandFont.caption).foregroundColor(secondary))
            ctx.draw(text, at: point(c, ringRadius + 30, Double(h) * SleepNightDialMath.degreesPerHour), anchor: .center)
        }
    }

    private func drawNeed(_ ctx: GraphicsContext, center c: CGPoint, arc: (start: Double, end: Double), label: String?) {
        let r = ringRadius + 15
        ctx.stroke(arcPath(center: c, radius: r, from: arc.start, to: arc.end),
                   with: .color(secondary.opacity(0.85)),
                   style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [4, 4]))
        let p = point(c, r, arc.start)
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7)), with: .color(secondary))
        if let label {
            let text = ctx.resolve(Text(label).font(StrandFont.captionNumber.weight(.semibold)).foregroundColor(primary))
            ctx.draw(text, at: point(c, ringRadius + 31, arc.start), anchor: .center)
        }
    }

    /// A thin light line along both edges of the night, and a dark hairline where one stage hands over to
    /// the next, so neighbouring stages and the darkest colour stay apart from the track.
    private func drawNightEdges(_ ctx: GraphicsContext, center c: CGPoint, arcs: [SleepNightDialMath.Arc],
                                from a0: Double, to a1: Double) {
        guard a1 > a0 else { return }
        for r in [ringRadius - ringWidth / 2 - 0.5, ringRadius + ringWidth / 2 + 0.5] {
            ctx.stroke(arcPath(center: c, radius: r, from: a0, to: a1),
                       with: .color(primary.opacity(0.32)), lineWidth: 1)
        }
        for arc in arcs.dropFirst() {
            var seam = Path()
            seam.move(to: point(c, ringRadius - ringWidth / 2, arc.start))
            seam.addLine(to: point(c, ringRadius + ringWidth / 2, arc.start))
            ctx.stroke(seam, with: .color(StrandPalette.heroFill), lineWidth: 1)
        }
    }

    /// A circular arc sampled every degree, clockwise from `from` to `to` (degrees from 12 o'clock).
    private func arcPath(center c: CGPoint, radius r: CGFloat, from a0: Double, to a1: Double) -> Path {
        var path = Path()
        guard a1 > a0 else { return path }
        path.move(to: point(c, r, a0))
        var a = a0 + 1
        while a < a1 {
            path.addLine(to: point(c, r, a))
            a += 1
        }
        path.addLine(to: point(c, r, a1))
        return path
    }

    private func point(_ c: CGPoint, _ r: CGFloat, _ degrees: Double) -> CGPoint {
        let rad = degrees * .pi / 180
        return CGPoint(x: c.x + r * CGFloat(sin(rad)), y: c.y - r * CGFloat(cos(rad)))
    }

    private func marker(_ symbol: String, at degrees: Double) -> some View {
        let rad = degrees * .pi / 180
        return ZStack {
            Circle().fill(StrandPalette.surfaceRaised)
            Circle().strokeBorder(primary, lineWidth: 1.5)
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(primary)
        }
        .frame(width: 22, height: 22)
        .offset(x: ringRadius * CGFloat(sin(rad)), y: -ringRadius * CGFloat(cos(rad)))
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var center: some View {
        VStack(spacing: 2) {
            if let score {
                Text("\(Int(score.rounded()))")
                    .font(StrandFont.number(40, weight: .bold))
                    .foregroundStyle(primary)
                if let scoreWord {
                    Text(scoreWord)
                        .font(StrandFont.footnote)
                        .foregroundStyle(secondary)
                }
                asleepLine.padding(.top, 4)
            } else {
                Text(SleepDurationText.format(asleepMinutes))
                    .font(StrandFont.number(30, weight: .bold))
                    .foregroundStyle(primary)
                Text("asleep")
                    .font(StrandFont.footnote)
                    .foregroundStyle(secondary)
            }
        }
        .monospacedDigit()
    }

    private var asleepLine: some View {
        HStack(spacing: 4) {
            Text(SleepDurationText.format(asleepMinutes))
                .font(StrandFont.subhead.weight(.semibold))
                .foregroundStyle(primary)
            if let needMinutes {
                Text("out of \(SleepDurationText.format(needMinutes))")
                    .font(StrandFont.subhead)
                    .foregroundStyle(secondary)
            }
        }
    }

    private func accessibilitySummary(needStart: String?) -> String {
        let f = AppClock.hourMinuteFormatter()
        var parts: [String] = []
        if let score {
            parts.append(String(localized: "Sleep score \(Int(score.rounded())) of 100"))
        }
        parts.append(String(localized: "Asleep \(SleepDurationText.format(asleepMinutes)) from \(f.string(from: onset)) to \(f.string(from: wake))"))
        if let needMinutes, let needStart {
            parts.append(String(localized: "Sleep need \(SleepDurationText.format(needMinutes)) before waking, from \(needStart)"))
        }
        return parts.joined(separator: ". ")
    }
}

/// The one duration format of the Sleep tab: "3h 41m", "47m", "8h". Never "8h 0m", never decimal hours.
enum SleepDurationText {
    static func format(_ minutes: Double) -> String {
        let m = max(0, Int(minutes.rounded()))
        if m < 60 { return String(localized: "\(m)m") }
        if m % 60 == 0 { return String(localized: "\(m / 60)h") }
        return String(localized: "\(m / 60)h \(m % 60)m")
    }
}
