import SwiftUI
import StrandDesign

// MARK: - The traces around the essential rings (personal fork, chantier 20)
//
// Pure geometry first (`EssentialTraceMath`, angles in degrees clockwise from 12 o'clock), then the views
// that draw it: the heart's trace around Today's rings, the breath around the night's ring, the week's
// Effort around Training's ring and the glass that fills in Nutrition's centre. Each moving part runs on a
// `TimelineView` and stands still under Reduce Motion or with the app's animations off.

enum EssentialTraceMath {
    /// The point at `degrees` (clockwise from 12 o'clock) on a circle of `radius` around `center`.
    static func point(_ center: CGPoint, radius: CGFloat, degrees: Double) -> CGPoint {
        let a = degrees * .pi / 180
        return CGPoint(x: center.x + radius * CGFloat(sin(a)), y: center.y - radius * CGFloat(cos(a)))
    }

    /// One heartbeat drawn as an electrocardiogram, `u` from 0 to 1 across the beat: a small P wave, the
    /// sharp QRS (the spike sits at `spikeAt`), then the T wave. Outward is positive, in points at scale 1.
    static func ecgBeat(_ u: Double) -> Double {
        func bump(_ c: Double, _ w: Double, _ a: Double) -> Double { a * exp(-pow((u - c) / w, 2)) }
        return bump(0.15, 0.035, 3) + bump(spikeAt - 0.03, 0.012, -3.5) + bump(spikeAt, 0.012, 19)
            + bump(spikeAt + 0.03, 0.012, -7) + bump(0.56, 0.05, 5)
    }

    /// Where the R spike sits inside a beat.
    static let spikeAt: Double = 0.31

    /// The beats drawn around Today's rings: the bright head passes one spike per heartbeat.
    static let ecgBeats = 12

    /// The closed electrocardiogram around a circle, `beats` beats on one turn, from `fromTurn` to
    /// `toTurn` (fractions of the turn; the range may run past 1 and wraps).
    static func ecgPath(center: CGPoint, radius: CGFloat, beats: Int = ecgBeats, scale: CGFloat = 1,
                        fromTurn: Double = 0, toTurn: Double = 1, samplesPerBeat: Int = 40) -> Path {
        var path = Path()
        let total = max(2, Int((toTurn - fromTurn) * Double(beats * samplesPerBeat)))
        for i in 0...total {
            let turn = fromTurn + (toTurn - fromTurn) * Double(i) / Double(total)
            let beatPos = turn * Double(beats)
            let u = beatPos - floor(beatPos)
            let r = radius + scale * CGFloat(ecgBeat(u))
            let p = point(center, radius: r, degrees: turn * 360)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        return path
    }

    /// Where the bright head of the heart trace stands at `date` for `bpm`, as a fraction of the turn: on
    /// the shared beat clock (`NoopHeartbeat.beatPhase`), so it crosses a spike when the heart beats.
    static func ecgHead(at date: Date, bpm: Int, beats: Int = ecgBeats) -> Double {
        let period = 60.0 / Double(max(bpm, 1))
        let elapsed = date.timeIntervalSinceReferenceDate / period
        let beatIndex = floor(elapsed).truncatingRemainder(dividingBy: Double(beats))
        let phase = NoopHeartbeat.beatPhase(at: date, bpm: bpm)
        return (beatIndex + phase + spikeAt) / Double(beats)
    }

    /// The breath around the night's ring: a sine of `waves` waves along the arc from `fromDegrees` to
    /// `toDegrees`, `amplitude` points either side of `radius`.
    static func breathPath(center: CGPoint, radius: CGFloat, amplitude: CGFloat, waves: Int,
                           fromDegrees: Double, toDegrees: Double, samples: Int = 600) -> Path {
        var path = Path()
        for i in 0...samples {
            let t = Double(i) / Double(samples)
            let r = radius + amplitude * CGFloat(sin(2 * .pi * Double(waves) * t))
            let p = point(center, radius: r, degrees: fromDegrees + (toDegrees - fromDegrees) * t)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        return path
    }

    /// The week's Effort around Training's ring: one hill per day, as high as that day's Effort against
    /// `fullScale`, from the baseline at each midnight. Days with no Effort (nil) stay on the baseline;
    /// days after `throughDay` are not drawn.
    static func effortPath(center: CGPoint, base: CGFloat, height: CGFloat, values: [Double?],
                           fullScale: Double, throughDay: Int, samplesPerDay: Int = 40) -> Path {
        var path = Path()
        let days = max(values.count, 1)
        let last = min(throughDay, days - 1)
        guard last >= 0 else { return path }
        for day in 0...last {
            let share = values[day].map { min(1, max(0, $0 / max(fullScale, 1))) } ?? 0
            for i in 0...samplesPerDay {
                let u = Double(i) / Double(samplesPerDay)
                let r = base + height * CGFloat(share * pow(sin(.pi * u), 0.8))
                let p = point(center, radius: r, degrees: (Double(day) + u) * 360 / Double(days))
                if day == 0 && i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
        }
        return path
    }

    /// The peak of one day's hill (the beating dot of today).
    static func effortPeak(center: CGPoint, base: CGFloat, height: CGFloat, value: Double?,
                           fullScale: Double, day: Int, days: Int) -> CGPoint {
        let share = value.map { min(1, max(0, $0 / max(fullScale, 1))) } ?? 0
        return point(center, radius: base + height * CGFloat(share),
                     degrees: (Double(day) + 0.5) * 360 / Double(max(days, 1)))
    }
}

// MARK: - Today: the heart around the rings

/// The live heart rate around Today's rings, drawn as an electrocardiogram: a dim trace on the whole turn,
/// a bright head that crosses one spike per heartbeat, and a fine wave leaving the rings at each beat.
/// Its own leaf: it observes `LiveState`, so the ~1 Hz heart rate redraws this view alone.
struct EssentialHeartTrace: View {
    var diameter: CGFloat
    /// The baseline radius of the trace and the outer edge of the rings it surrounds.
    var radius: CGFloat
    var ringsEdge: CGFloat

    @EnvironmentObject var live: LiveState
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @ObservedObject var motion = NoopMotionState.shared

    private var bpm: Int? {
        guard live.connected, let hr = live.heartRate, hr >= NoopHeartbeat.slowestBeat else { return nil }
        return hr
    }

    var body: some View {
        Group {
            if let bpm, !motion.poseStill(reduceMotion) {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                    canvas(at: context.date, bpm: bpm)
                }
            } else {
                canvas(at: nil, bpm: bpm)
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }

    private func canvas(at date: Date?, bpm: Int?) -> some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let tint = StrandPalette.liquidHeart
            context.stroke(EssentialTraceMath.ecgPath(center: center, radius: radius),
                           with: .color(tint.opacity(bpm == nil ? 0.14 : 0.24)),
                           style: StrokeStyle(lineWidth: 1.3, lineJoin: .round))
            guard let date, let bpm else { return }
            // The wave of the beat, leaving the rings.
            let phase = NoopHeartbeat.beatPhase(at: date, bpm: bpm)
            let ripple = ringsEdge * CGFloat(1 + 0.12 * phase)
            context.stroke(Path(ellipseIn: CGRect(x: center.x - ripple, y: center.y - ripple,
                                                  width: ripple * 2, height: ripple * 2)),
                           with: .color(tint.opacity(0.4 * (1 - phase))), lineWidth: 1.4)
            // The head and its tail, brighter towards the head.
            let head = EssentialTraceMath.ecgHead(at: date, bpm: bpm)
            let tail = 0.075
            let pieces = 6
            context.drawLayer { layer in
                layer.addFilter(.shadow(color: tint.opacity(0.9), radius: 4))
                for k in 0..<pieces {
                    let from = head - tail + tail * Double(k) / Double(pieces)
                    let to = head - tail + tail * Double(k + 1) / Double(pieces)
                    layer.stroke(EssentialTraceMath.ecgPath(center: center, radius: radius, fromTurn: from,
                                                            toTurn: to, samplesPerBeat: 60),
                                 with: .color(tint.opacity(Double(k + 1) / Double(pieces))),
                                 style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }
}

/// The heart and the live number in the middle of Today's rings, beating on the shared clock; « — » while
/// no live heartbeat comes in. Its own leaf, like the trace.
struct EssentialHeartCenter: View {
    @EnvironmentObject var live: LiveState

    private var bpm: Int? {
        guard live.connected, let hr = live.heartRate, hr > 0 else { return nil }
        return hr
    }

    var body: some View {
        VStack(spacing: 0) {
            NoopHeartbeat(bpm: bpm, tint: StrandPalette.liquidHeart, size: 16, beating: bpm != nil)
            Text(verbatim: bpm.map(String.init) ?? "—")
                .font(StrandFont.number(24, weight: .bold))
                .foregroundStyle(StrandPalette.textPrimary)
                .contentTransition(.numericText())
            Text("bpm")
                .font(StrandFont.caption.weight(.semibold))
                .foregroundStyle(StrandPalette.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(bpm.map { Text("Heart rate \($0) bpm") } ?? Text("Waiting for a live heartbeat…"))
    }
}

// MARK: - Sleep: the breath around the night

/// The night's breathing around the sleep ring: a turquoise wave along the ring's arc that swells and
/// relaxes at the night's breathing rate, with a slow bright point running along it. Without a rate for
/// the night, the wave is drawn still and nothing claims a rhythm.
struct EssentialBreathTrace: View {
    var diameter: CGFloat
    var radius: CGFloat
    /// The night's breaths per minute, nil when none was measured.
    var breathsPerMinute: Double?

    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @ObservedObject var motion = NoopMotionState.shared

    /// The arc of the night on the sleep ring (`SleepNightRingMath`): the gap sits at the bottom.
    private var fromDegrees: Double { 180 + SleepNightRingMath.gapDegrees / 2 }
    private var toDegrees: Double { 540 - SleepNightRingMath.gapDegrees / 2 }

    var body: some View {
        Group {
            if let rate = breathsPerMinute, rate > 0, !motion.poseStill(reduceMotion) {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                    canvas(at: context.date, rate: rate)
                }
            } else {
                canvas(at: nil, rate: nil)
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }

    private func canvas(at date: Date?, rate: Double?) -> some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let tint = StrandPalette.metricCyan
            // One breath: in on 45 % of the cycle, out on the rest.
            var swell: CGFloat = 0
            if let date, let rate {
                let cycle = 60 / rate
                let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle) / cycle
                swell = CGFloat(t < 0.45 ? sin(t / 0.45 * .pi / 2) : cos((t - 0.45) / 0.55 * .pi / 2))
            }
            let path = EssentialTraceMath.breathPath(center: center, radius: radius + 2.5 * swell,
                                                     amplitude: 3.5 + 1.5 * swell, waves: 26,
                                                     fromDegrees: fromDegrees, toDegrees: toDegrees)
            context.stroke(path, with: .color(tint.opacity(0.28 + 0.2 * Double(swell))),
                           style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
            guard let date else { return }
            // The bright point: one lap of the night in 40 s.
            let lap = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 40) / 40
            let degrees = fromDegrees + (toDegrees - fromDegrees) * lap
            let p = EssentialTraceMath.point(center, radius: radius + 2.5 * swell, degrees: degrees)
            context.drawLayer { layer in
                layer.addFilter(.shadow(color: tint, radius: 5))
                layer.fill(Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)),
                           with: .color(StrandPalette.textPrimary))
            }
        }
    }
}

// MARK: - Training: the week's Effort around the week

/// The week's Effort around Training's week ring: one hill per day as high as its Effort, drawn up to
/// today, the dot on today's hill beating slowly. Days with no Effort stay on the dotted baseline.
struct EssentialEffortTrace: View {
    var diameter: CGFloat
    var base: CGFloat
    var height: CGFloat
    /// Monday first, seven values; nil where the day has no Effort.
    var values: [Double?]
    var fullScale: Double
    /// Today's index in the week, nil when the week shown is not this one.
    var todayIndex: Int?

    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @ObservedObject var motion = NoopMotionState.shared

    var body: some View {
        Group {
            if todayIndex != nil, !motion.poseStill(reduceMotion) {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                    canvas(at: context.date)
                }
            } else {
                canvas(at: nil)
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }

    private func canvas(at date: Date?) -> some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let tint = StrandPalette.effortColor
            context.stroke(Path(ellipseIn: CGRect(x: center.x - base, y: center.y - base,
                                                  width: base * 2, height: base * 2)),
                           with: .color(StrandPalette.textPrimary.opacity(0.12)),
                           style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
            // No Effort stored for the week: the dotted baseline alone, no line that would look like data.
            guard values.contains(where: { $0 != nil }) else { return }
            let through = todayIndex ?? (values.count - 1)
            let path = EssentialTraceMath.effortPath(center: center, base: base, height: height, values: values,
                                                     fullScale: fullScale, throughDay: through)
            context.drawLayer { layer in
                layer.addFilter(.shadow(color: tint.opacity(0.8), radius: 3))
                layer.stroke(path, with: .color(tint), style: StrokeStyle(lineWidth: 2, lineCap: .round,
                                                                         lineJoin: .round))
            }
            guard let today = todayIndex, today < values.count else { return }
            let peak = EssentialTraceMath.effortPeak(center: center, base: base, height: height,
                                                     value: values[today], fullScale: fullScale,
                                                     day: today, days: values.count)
            var beat: CGFloat = 0
            if let date {
                let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
                beat = CGFloat(sin(t * .pi))
            }
            let r = 4 * (1 + 0.5 * beat)
            context.drawLayer { layer in
                layer.addFilter(.shadow(color: tint, radius: 6))
                layer.fill(Path(ellipseIn: CGRect(x: peak.x - r, y: peak.y - r, width: r * 2, height: r * 2)),
                           with: .color(StrandPalette.textPrimary))
            }
        }
    }
}

// MARK: - Nutrition: the glass in the middle

/// Nutrition's centre fills like a glass: the share of the day's goal eaten, as two waves that rise to
/// their level when the screen appears and then keep moving.
struct EssentialGlassCore: View {
    var diameter: CGFloat
    /// 0…1, the share of the goal eaten.
    var fill: Double
    var tint: Color

    @State var appeared = Date()
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @ObservedObject var motion = NoopMotionState.shared

    var body: some View {
        Group {
            if !motion.poseStill(reduceMotion) {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                    canvas(at: context.date)
                }
            } else {
                canvas(at: nil)
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .onAppear { appeared = Date() }
        .accessibilityHidden(true)
    }

    private func canvas(at date: Date?) -> some View {
        Canvas { context, size in
            let level = min(1, max(0, fill))
            var rise = 1.0
            var shift = 0.0
            if let date {
                let since = date.timeIntervalSince(appeared)
                let t = min(1, max(0, since / 1.6))
                rise = 1 - pow(1 - t, 3)
                shift = date.timeIntervalSinceReferenceDate
            }
            let top = size.height * CGFloat(1 - level * rise)
            for (speed, height, opacity) in [(0.33, 5.0, 0.22), (0.5, 4.0, 0.38)] {
                var wave = Path()
                wave.move(to: CGPoint(x: 0, y: size.height))
                let steps = 48
                for i in 0...steps {
                    let x = size.width * CGFloat(i) / CGFloat(steps)
                    let phase = Double(i) / Double(steps) * 2 * .pi * 1.2 + shift * speed * 2 * .pi
                    wave.addLine(to: CGPoint(x: x, y: top + CGFloat(height * sin(phase))))
                }
                wave.addLine(to: CGPoint(x: size.width, y: size.height))
                wave.closeSubpath()
                context.fill(wave, with: .color(tint.opacity(opacity)))
            }
        }
    }
}
