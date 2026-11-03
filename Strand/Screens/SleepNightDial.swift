import SwiftUI
import StrandDesign

// MARK: - Night ring (personal fork, chantier 7 design A)
//
// The Sleep tab's hero: a circular hypnogram. The whole night runs once round the ring, clockwise from
// the bedtime (moon, right of the opening at the top) to the wake time (sun, left of it). Each stage
// stretch is a rounded arc drawn on its own track, and the track's distance from the centre is the
// stage's depth: awake on the outside, then REM, light, and deep nearest the score. Thin light lines join
// one stretch to the next, so the night reads as one path diving in and out. The score (or, without one,
// the time asleep) sits in the middle. Display only: every number arrives from the caller.

/// Pure geometry for `SleepNightDial`, kept apart so it can be tested without drawing.
enum SleepNightRingMath {
    /// The opening at the top of the ring, in degrees, between the wake time and the bedtime.
    static let gapDegrees: Double = 34

    /// One drawn stretch, in degrees clockwise from 12 o'clock.
    struct Arc: Equatable {
        let stage: SleepStage
        let start: Double
        let end: Double
    }

    /// The night's length in seconds: the bed-to-wake span, or the last interval's end if that is later.
    static func nightSeconds(intervals: [SleepInterval], span: TimeInterval) -> TimeInterval {
        max(span, intervals.map(\.end).max() ?? 0)
    }

    /// The ring angle of a moment `seconds` after the bedtime: the night fills the circle minus the gap.
    static func angle(seconds: TimeInterval, night: TimeInterval) -> Double {
        guard night > 0 else { return gapDegrees / 2 }
        let t = min(max(seconds / night, 0), 1)
        return gapDegrees / 2 + t * (360 - gapDegrees)
    }

    /// Every stretch of the night (awake included) as an arc, in time order.
    static func arcs(intervals: [SleepInterval], night: TimeInterval) -> [Arc] {
        intervals
            .filter { $0.end > $0.start }
            .sorted { $0.start < $1.start }
            .map { Arc(stage: $0.stage, start: angle(seconds: $0.start, night: night),
                       end: angle(seconds: $0.end, night: night)) }
    }

    /// The track of a stage, 0 for the outermost (awake) to 3 for the innermost (deep).
    static func depth(_ stage: SleepStage) -> Int {
        switch stage {
        case .awake: return 0
        case .rem: return 1
        case .light: return 2
        case .deep: return 3
        }
    }
}

struct SleepNightDial: View {
    let onset: Date
    let wake: Date
    /// The night's stage intervals, seconds from `onset` (display-smoothed by the caller).
    let intervals: [SleepInterval]
    let palette: SleepStagePalette
    /// The sleep need, shown in the centre as « out of 8h »; nil leaves it out.
    let needMinutes: Double?
    let score: Double?
    let scoreWord: String?
    let asleepMinutes: Double
    /// Kept for the call sites; the night photo is gone (fork chantier 7), the ring always sits on a card.
    var onScene: Bool = false
    var diameter: CGFloat = 260

    /// Track radii on the 260-point design, outermost (awake) first.
    private let trackRadii: [CGFloat] = [114, 100, 86, 72]
    private let lineWidth: CGFloat = 10
    private var scale: CGFloat { diameter / 260 }

    var body: some View {
        let night = SleepNightRingMath.nightSeconds(intervals: intervals, span: wake.timeIntervalSince(onset))
        let arcs = SleepNightRingMath.arcs(intervals: intervals, night: night)
        ZStack {
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                drawTracks(ctx, center: c)
                ctx.drawLayer { glow in
                    glow.addFilter(.blur(radius: 4 * scale))
                    glow.opacity = 0.6
                    for arc in arcs { stroke(glow, arc, center: c) }
                }
                drawLinks(ctx, center: c, arcs: arcs)
                for arc in arcs { stroke(ctx, arc, center: c) }
            }
            marker("moon.fill", tint: StrandPalette.sleepStageColor(.deep, palette: palette),
                   at: SleepNightRingMath.angle(seconds: 0, night: night))
            marker("sun.max.fill", tint: StrandPalette.sleepStageColor(.awake, palette: palette),
                   at: SleepNightRingMath.angle(seconds: night, night: night))
            center
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilitySummary))
    }

    // MARK: Drawing

    private func radius(_ stage: SleepStage) -> CGFloat {
        trackRadii[SleepNightRingMath.depth(stage)] * scale
    }

    private func drawTracks(_ ctx: GraphicsContext, center c: CGPoint) {
        for stage in [SleepStage.awake, .rem, .light, .deep] {
            let r = radius(stage)
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                       with: .color(StrandPalette.sleepStageColor(stage, palette: palette).opacity(0.10)),
                       lineWidth: lineWidth * scale)
        }
    }

    /// One stretch as a rounded arc on its track, trimmed a little at both ends so neighbours stay apart.
    private func stroke(_ ctx: GraphicsContext, _ arc: SleepNightRingMath.Arc, center c: CGPoint) {
        let trim = min(0.6, (arc.end - arc.start) / 4)
        ctx.stroke(arcPath(center: c, radius: radius(arc.stage), from: arc.start + trim, to: arc.end - trim),
                   with: .color(StrandPalette.sleepStageColor(arc.stage, palette: palette)),
                   style: StrokeStyle(lineWidth: lineWidth * scale, lineCap: .round))
    }

    /// A thin light line from one stretch's track to the next one's, where the stage changes.
    private func drawLinks(_ ctx: GraphicsContext, center c: CGPoint, arcs: [SleepNightRingMath.Arc]) {
        for (previous, next) in zip(arcs, arcs.dropFirst()) where previous.stage != next.stage {
            var link = Path()
            link.move(to: point(c, radius(previous.stage), next.start))
            link.addLine(to: point(c, radius(next.stage), next.start))
            ctx.stroke(link, with: .color(StrandPalette.textPrimary.opacity(0.35)),
                       style: StrokeStyle(lineWidth: 1.5 * scale, lineCap: .round))
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

    /// The bedtime / wake-time badge, on the outer track at either side of the opening.
    private func marker(_ symbol: String, tint: Color, at degrees: Double) -> some View {
        let rad = degrees * .pi / 180
        let r = trackRadii[0] * scale
        return ZStack {
            Circle().fill(StrandPalette.surfaceRaised)
            Circle().strokeBorder(tint, lineWidth: 2)
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: 22, height: 22)
        .offset(x: r * CGFloat(sin(rad)), y: -r * CGFloat(cos(rad)))
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var center: some View {
        VStack(spacing: 1) {
            if let score {
                Text("Rest")
                    .font(StrandFont.caption.weight(.semibold))
                    .foregroundStyle(StrandPalette.restColor)
                Text("\(Int(score.rounded()))")
                    .font(StrandFont.number(54, weight: .bold))
                    .foregroundStyle(StrandPalette.textPrimary)
                if let scoreWord {
                    Text(scoreWord)
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
                asleepLine.padding(.top, 4)
            } else {
                Text(SleepDurationText.format(asleepMinutes))
                    .font(StrandFont.number(32, weight: .bold))
                    .foregroundStyle(StrandPalette.textPrimary)
                Text("asleep")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
        }
        .monospacedDigit()
    }

    private var asleepLine: some View {
        HStack(spacing: 4) {
            Text(SleepDurationText.format(asleepMinutes))
                .font(StrandFont.rounded(13, weight: .semibold))
                .foregroundStyle(StrandPalette.textPrimary)
            if let needMinutes {
                Text("out of \(SleepDurationText.format(needMinutes))")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
        }
    }

    private var accessibilitySummary: String {
        let f = AppClock.hourMinuteFormatter()
        var parts: [String] = []
        if let score {
            parts.append(String(localized: "Sleep score \(Int(score.rounded())) of 100"))
        }
        parts.append(String(localized: "Asleep \(SleepDurationText.format(asleepMinutes)) from \(f.string(from: onset)) to \(f.string(from: wake))"))
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
