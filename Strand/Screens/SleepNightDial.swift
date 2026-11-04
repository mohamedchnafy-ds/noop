import SwiftUI
import StrandDesign

// MARK: - Night ring (personal fork, chantier 7 design A; horseshoe since chantier 9)
//
// The Sleep tab's hero: a circular hypnogram shaped like a horseshoe, open at the bottom. The night runs
// clockwise from the bedtime (moon, bottom left) up the left side, over the top and down to the wake time
// (sun, bottom right), so it reads left to right like a watch; each time is written under its badge. Each stage
// stretch is a rounded arc drawn on its own track, and the track's distance from the centre is the
// stage's depth: awake on the outside, then REM, light, and deep nearest the score. Thin light lines join
// one stretch to the next, so the night reads as one path diving in and out. Ticks outside the ring mark
// each whole hour. The score (or, without
// one, the time asleep) sits in the middle; a tap on a stage lights it alone and puts its total there.
// Display only: every number arrives from the caller.

/// Pure geometry for `SleepNightDial`, kept apart so it can be tested without drawing.
enum SleepNightRingMath {
    /// The opening at the bottom of the ring, in degrees, between the bedtime and the wake time.
    static let gapDegrees: Double = 90

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

    /// The ring angle of a moment `seconds` after the bedtime: the night fills the circle minus the gap,
    /// from just left of 6 o'clock (180° + half the gap) clockwise to just right of it. Angles past 360°
    /// are kept as they are (the drawing only takes their sine and cosine), so a stretch never wraps.
    static func angle(seconds: TimeInterval, night: TimeInterval) -> Double {
        guard night > 0 else { return 180 + gapDegrees / 2 }
        let t = min(max(seconds / night, 0), 1)
        return 180 + gapDegrees / 2 + t * (360 - gapDegrees)
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
    /// The ring's own size on the 260-point design; the hour labels add a margin around it.
    var diameter: CGFloat = 260
    /// The stage picked on the ring, its legend or the phases chart below (one shared selection): only
    /// that stage stays lit and the centre shows its total.
    var selected: SleepStage? = nil
    /// Each stage's minutes and share of the night, as the phases chart shows them (same funnel).
    var stageMinutes: [SleepStage: Double] = [:]
    var stagePercent: [SleepStage: Int] = [:]
    /// A tap on a track picks its stage; a tap on the lit stage or the centre clears it. Nil = not tappable.
    var onSelect: ((SleepStage?) -> Void)? = nil

    /// Track radii on the 260-point design, outermost (awake) first.
    private let trackRadii: [CGFloat] = [114, 100, 86, 72]
    private let lineWidth: CGFloat = 10
    /// Room around the ring for the hour ticks and labels.
    private let labelMargin: CGFloat = 22
    private var scale: CGFloat { diameter / 260 }
    private var frameSide: CGFloat { diameter + labelMargin * 2 }

    var body: some View {
        let night = SleepNightRingMath.nightSeconds(intervals: intervals, span: wake.timeIntervalSince(onset))
        let arcs = SleepNightRingMath.arcs(intervals: intervals, night: night)
        let hours = hourMarks(night: night)
        ZStack {
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                drawTracks(ctx, center: c)
                drawHours(ctx, center: c, hours: hours, night: night)
                ctx.drawLayer { glow in
                    glow.addFilter(.blur(radius: 4 * scale))
                    glow.opacity = 0.6
                    for arc in arcs where isLit(arc.stage) { stroke(glow, arc, center: c) }
                }
                drawLinks(ctx, center: c, arcs: arcs)
                for arc in arcs { stroke(ctx, arc, center: c) }
            }
            marker("moon.fill", tint: StrandPalette.sleepBedtime,
                   at: SleepNightRingMath.angle(seconds: 0, night: night))
            marker("sun.max.fill", tint: StrandPalette.sleepWake,
                   at: SleepNightRingMath.angle(seconds: night, night: night))
            center
        }
        .frame(width: frameSide, height: frameSide)
        .contentShape(Circle())
        .gesture(SpatialTapGesture().onEnded { value in pickStageAtTap(at: value.location, arcs: arcs) },
                 including: onSelect == nil ? .none : .all)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilitySummary))
    }

    // MARK: Selection

    private func isLit(_ stage: SleepStage) -> Bool { selected == nil || selected == stage }

    /// The track under the finger picks its stage (toggling it off when it is already the one lit); a tap
    /// in the middle, or anywhere away from a track, clears the selection.
    private func pickStageAtTap(at location: CGPoint, arcs: [SleepNightRingMath.Arc]) {
        guard let onSelect else { return }
        let c = CGPoint(x: frameSide / 2, y: frameSide / 2)
        let distance = hypot(location.x - c.x, location.y - c.y)
        let hit = [SleepStage.awake, .rem, .light, .deep].first { stage in
            abs(distance - radius(stage)) <= 7 * scale && arcs.contains { $0.stage == stage }
        }
        guard let hit, hit != selected else {
            onSelect(nil)
            return
        }
        onSelect(hit)
    }

    // MARK: Drawing

    private func radius(_ stage: SleepStage) -> CGFloat {
        trackRadii[SleepNightRingMath.depth(stage)] * scale
    }

    /// The four faint tracks, each a horseshoe from the bedtime to the wake time (open at the bottom).
    private func drawTracks(_ ctx: GraphicsContext, center c: CGPoint) {
        let from = SleepNightRingMath.angle(seconds: 0, night: 1)
        let to = SleepNightRingMath.angle(seconds: 1, night: 1)
        for stage in [SleepStage.awake, .rem, .light, .deep] {
            ctx.stroke(arcPath(center: c, radius: radius(stage), from: from, to: to),
                       with: .color(StrandPalette.sleepStageColor(stage, palette: palette)
                        .opacity(isLit(stage) ? 0.14 : 0.05)),
                       style: StrokeStyle(lineWidth: lineWidth * scale, lineCap: .round))
        }
    }

    /// Every whole hour of the night as a tick outside the ring, with its label (« 3h ») unless the hour
    /// falls right by the bedtime or wake-time badge, whose exact times are labelled instead.
    private func drawHours(_ ctx: GraphicsContext, center c: CGPoint, hours: [(hour: Int, seconds: TimeInterval)],
                           night: TimeInterval) {
        let outer = trackRadii[0] * scale + lineWidth * scale / 2
        let labelRadius = outer + 13
        for mark in hours {
            let a = SleepNightRingMath.angle(seconds: mark.seconds, night: night)
            var tick = Path()
            tick.move(to: point(c, outer + 2, a))
            tick.addLine(to: point(c, outer + 6, a))
            ctx.stroke(tick, with: .color(StrandPalette.textSecondary.opacity(0.8)), lineWidth: 1.5)
            let nearBadge = mark.seconds < night * 0.06 || mark.seconds > night * 0.94
            if !nearBadge {
                let text = ctx.resolve(Text(String(localized: "\(mark.hour)h"))
                    .font(StrandFont.caption2.weight(.medium)).foregroundColor(StrandPalette.textSecondary))
                ctx.draw(text, at: point(c, labelRadius, a), anchor: .center)
            }
        }
        let f = AppClock.hourMinuteFormatter()
        for (seconds, date) in [(TimeInterval(0), onset), (night, onset.addingTimeInterval(night))] {
            let a = SleepNightRingMath.angle(seconds: seconds, night: night)
            let text = ctx.resolve(Text(f.string(from: date))
                .font(StrandFont.rounded(17, weight: .bold)).foregroundColor(StrandPalette.textPrimary))
            // Written right under its badge, so each time stays attached to its own end of the night.
            let badge = point(c, trackRadii[0] * scale, a)
            ctx.draw(text, at: CGPoint(x: badge.x, y: badge.y + 16 + 10 * scale), anchor: .top)
        }
    }

    /// The whole clock hours strictly inside the night, with their offset from the bedtime.
    private func hourMarks(night: TimeInterval) -> [(hour: Int, seconds: TimeInterval)] {
        guard night > 0 else { return [] }
        let calendar = Calendar.current
        guard var next = calendar.nextDate(after: onset, matching: DateComponents(minute: 0, second: 0),
                                           matchingPolicy: .nextTime) else { return [] }
        var marks: [(hour: Int, seconds: TimeInterval)] = []
        while next.timeIntervalSince(onset) < night && marks.count < 24 {
            marks.append((calendar.component(.hour, from: next), next.timeIntervalSince(onset)))
            next = next.addingTimeInterval(3600)
        }
        return marks
    }

    /// One stretch as a rounded arc on its track, trimmed a little at both ends so neighbours stay apart.
    /// A stage other than the selected one is drawn faint.
    private func stroke(_ ctx: GraphicsContext, _ arc: SleepNightRingMath.Arc, center c: CGPoint) {
        let trim = min(0.6, (arc.end - arc.start) / 4)
        ctx.stroke(arcPath(center: c, radius: radius(arc.stage), from: arc.start + trim, to: arc.end - trim),
                   with: .color(StrandPalette.sleepStageColor(arc.stage, palette: palette)
                    .opacity(isLit(arc.stage) ? 1 : 0.18)),
                   style: StrokeStyle(lineWidth: lineWidth * scale, lineCap: .round))
    }

    /// A thin light line from one stretch's track to the next one's, where the stage changes.
    private func drawLinks(_ ctx: GraphicsContext, center c: CGPoint, arcs: [SleepNightRingMath.Arc]) {
        let opacity = selected == nil ? 0.35 : 0.12
        for (previous, next) in zip(arcs, arcs.dropFirst()) where previous.stage != next.stage {
            var link = Path()
            link.move(to: point(c, radius(previous.stage), next.start))
            link.addLine(to: point(c, radius(next.stage), next.start))
            ctx.stroke(link, with: .color(StrandPalette.textPrimary.opacity(opacity)),
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

    /// The bedtime / wake-time badge, on the outer track at either side of the opening at the bottom.
    private func marker(_ symbol: String, tint: Color, at degrees: Double) -> some View {
        let rad = degrees * .pi / 180
        let r = trackRadii[0] * scale
        return ZStack {
            Circle().fill(StrandPalette.surfaceRaised)
            Circle().strokeBorder(tint, lineWidth: 2)
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: 28, height: 28)
        .offset(x: r * CGFloat(sin(rad)), y: -r * CGFloat(cos(rad)))
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var center: some View {
        VStack(spacing: 1) {
            if let stage = selected {
                // The picked stage alone: its name, its total and its share of the night.
                Text(stage.label)
                    .font(StrandFont.caption.weight(.semibold))
                    .foregroundStyle(StrandPalette.sleepStageColor(stage, palette: palette))
                Text(SleepDurationText.format(stageMinutes[stage] ?? 0))
                    .font(StrandFont.number(40, weight: .bold))
                    .foregroundStyle(StrandPalette.textPrimary)
                if let share = stageShare(stage) {
                    Text("\(share) of the night")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
            } else if let score {
                Text("Rest")
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(StrandPalette.restRing)
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

    /// The stage's share formatted apart (key « %lld%% », as the phases chart), so the sentence key
    /// « %@ of the night » carries no literal percent sign.
    private func stageShare(_ stage: SleepStage) -> String? {
        stagePercent[stage].map { String(localized: "\($0)%") }
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
