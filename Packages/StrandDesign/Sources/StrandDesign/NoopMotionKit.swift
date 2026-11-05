import SwiftUI

// MARK: - Chantier 12 (personal fork): the animation pass's tokens and primitives
//
// The screens rebuilt in the fork had almost no motion. This file holds what they share, so no screen
// carries a duration of its own:
//
//   • the tokens of the motion table (ring draw, value change, the "slam" of a headline number)
//   • `NoopLaunchOnce` — an entrance plays once per launch of the app, not at every tab change
//   • `NoopFirstDraw` — the one-shot "draw" flag a ring or a curve traces itself in with
//   • `NoopGradientArc` — a flat ring stroked from its deep tone to its vivid one, with a lit tip (effect A)
//   • `NoopRollingNumber` — a number that counts to its value, or rises blurred and lands (effect B)
//   • `.noopNumericTransition(_:)`, `.noopSymbolBounce(_:)` — iOS 17 / macOS 14 effects behind one check
//   • `.noopDaySlide(_:)` — a day change nudges the card in from the side it came from
//   • `.noopShimmer(_:)` — a loading skeleton's sweep, only while it loads
//
// Every one of them consults the quiet-motion gate (`NoopMotionState.poseStill`): with Reduce Motion, Low
// Power Mode or NOOP's own setting the final value is drawn at once. The haptics are kept: they are not
// motion. A view that is never "armed" (the PNG render tests pass `false`) draws its final state too,
// because `ImageRenderer` captures a single frame.

public extension NoopMotion {

    // MARK: Durations

    /// A ring tracing itself on its first appearance.
    static let ringDrawDuration: Double = 0.9
    /// The delay between two concentric rings, outside to inside.
    static let ringStagger: Double = 0.09
    /// A ring or a figure moving to a new value (another day, a meal added, a set ticked).
    static let valueChangeDuration: Double = 0.65
    /// A headline number rising to its value before it lands (effect B).
    static let slamRiseDuration: Double = 0.85
    /// The landing of that number: from `slamLandScale` back to 1.
    static let slamLandDuration: Double = 0.42
    /// The motion blur of a rising number at its fastest.
    static let slamBlurMax: CGFloat = 6
    /// The scale a rising number lands from.
    static let slamLandScale: CGFloat = 1.14
    /// How far a card slides in when the day changes.
    static let daySlideDistance: CGFloat = 28
    /// A curve (heart rate, stress) tracing itself on its first appearance.
    static let curveDrawDuration: Double = 1.1

    // MARK: Curves

    /// The house ease-out: strong, without bounce (≈ cubic-bezier(0.25, 1, 0.5, 1)).
    static func strongEaseOut(_ duration: Double) -> Animation {
        .timingCurve(0.25, 1, 0.5, 1, duration: duration)
    }

    /// A ring's first trace.
    static var ringDraw: Animation { strongEaseOut(ringDrawDuration) }

    /// A ring or a number moving to a new value.
    static var valueChange: Animation { strongEaseOut(valueChangeDuration) }

    /// A curve's first trace.
    static var curveDraw: Animation { strongEaseOut(curveDrawDuration) }
}

// MARK: - Once per launch

/// The entrances that already played in this run of the app. In memory only: a new launch plays them again,
/// a tab change or a sheet does not.
public enum NoopLaunchOnce {
    private static var played: Set<String> = []

    /// Whether the entrance named `key` already played in this launch.
    public static func hasPlayed(_ key: String) -> Bool { played.contains(key) }

    /// Marks the entrance named `key` as played; true for the one caller that gets to play it.
    @discardableResult
    public static func markPlayed(_ key: String) -> Bool { played.insert(key).inserted }
}

// MARK: - First draw

/// What a drawing surface needs to know from `NoopFirstDraw`.
public struct NoopDrawPhase: Equatable {
    /// False while the surface waits for its entrance (draw it empty); true once it is drawn or drawing.
    public let drawn: Bool
    /// True when the quiet-motion gate is closed: draw every change at once.
    public let still: Bool

    public init(drawn: Bool, still: Bool) {
        self.drawn = drawn
        self.still = still
    }

    /// `animation`, or nil when the surface must not move.
    public func motion(_ animation: Animation) -> Animation? { still ? nil : animation }
}

/// Hands its content a `drawn` flag that turns true once, the first time the surface is armed in this launch,
/// under `NoopMotion.ringDraw`. Pieces of the content can pick their own curve or delay with
/// `.animation(phase.motion(…), value: phase.drawn)`.
///
/// Unarmed (data not loaded yet, or a PNG render) the content is drawn whole. Armed but already played in this
/// launch, or with the quiet-motion gate closed, it is drawn whole too.
public struct NoopFirstDraw<Content: View>: View {
    private let key: String
    private let armed: Bool
    private let content: (NoopDrawPhase) -> Content

    @State private var started = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var motion = NoopMotionState.shared

    /// - Parameters:
    ///   - key: names the entrance for `NoopLaunchOnce`; one key per surface.
    ///   - armed: false draws the surface whole and waits (data still loading, or a render test).
    public init(key: String, armed: Bool, @ViewBuilder content: @escaping (NoopDrawPhase) -> Content) {
        self.key = key
        self.armed = armed
        self.content = content
    }

    private var still: Bool { motion.poseStill(reduceMotion) }

    private var waiting: Bool {
        armed && !started && !still && !NoopLaunchOnce.hasPlayed(key)
    }

    public var body: some View {
        content(NoopDrawPhase(drawn: !waiting, still: still))
            .onAppear { begin() }
            .onChangeCompat(of: armed) { _ in begin() }
    }

    private func begin() {
        guard armed, !started else { return }
        guard !still, NoopLaunchOnce.markPlayed(key) else {
            started = true
            return
        }
        withAnimation(NoopMotion.ringDraw) { started = true }
    }
}

// MARK: - Gradient ring (effect A)

/// One flat ring stroked from its deep tone (at the start) to its vivid tint (at the tip), with a lit tip: a
/// dot of the vivid tint and its glow. Beyond a full turn, the second lap is drawn in the deep tone.
///
/// Draws from 3 o'clock clockwise, like `Circle().trim`; rotate the ring by −90° to start at the top. Every
/// part follows `fraction` through an animation, so the caller animates the trace by animating `fraction`.
public struct NoopGradientArc: View {
    private let fraction: Double
    private let tint: Color
    private let deep: Color
    private let diameter: CGFloat
    private let lineWidth: CGFloat
    private let litTip: Bool

    /// - Parameters:
    ///   - fraction: the share of the turn filled; above 1 adds a second lap.
    ///   - tint: the vivid tone, at the tip.
    ///   - deep: the deep tone, at the start (a `StrandPalette` token).
    ///   - diameter: the diameter of the stroke's centre line.
    ///   - lineWidth: the stroke width.
    ///   - litTip: false leaves the tip without its dot and glow.
    public init(fraction: Double, tint: Color, deep: Color, diameter: CGFloat, lineWidth: CGFloat,
                litTip: Bool = true) {
        self.fraction = fraction
        self.tint = tint
        self.deep = deep
        self.diameter = diameter
        self.lineWidth = lineWidth
        self.litTip = litTip
    }

    private var firstLap: CGFloat { CGFloat(min(1, max(0, fraction))) }
    private var secondLap: CGFloat { CGFloat(min(1, max(0, fraction - 1))) }

    /// The angle the gradient reaches its vivid end at: the end of the first lap.
    private var gradientEnd: Angle { .degrees(360 * Double(max(firstLap, 0.02))) }

    /// Where the tip sits, in degrees from 3 o'clock.
    private var tipDegrees: Double { 360 * Double(secondLap > 0 ? secondLap : firstLap) }

    public var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: firstLap)
                .stroke(AngularGradient(gradient: Gradient(colors: [deep, tint]), center: .center,
                                        startAngle: .degrees(0), endAngle: gradientEnd),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .opacity(firstLap > 0.001 ? 1 : 0)
            // The round cap at the start sits just before 0°, where the angular gradient already wraps to
            // its vivid end: a dot of the deep tone covers it.
            Circle()
                .fill(deep)
                .frame(width: lineWidth, height: lineWidth)
                .offset(x: diameter / 2)
                .frame(width: diameter, height: diameter)
                .opacity(firstLap > 0.001 ? 1 : 0)
            Circle()
                .trim(from: 0, to: secondLap)
                .stroke(deep, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .opacity(secondLap > 0.001 ? 1 : 0)
            if litTip {
                Circle()
                    .fill(secondLap > 0 ? deep : tint)
                    .frame(width: lineWidth, height: lineWidth)
                    .shadow(color: tint.opacity(0.75), radius: 6)
                    .offset(x: diameter / 2)
                    .frame(width: diameter, height: diameter)
                    .rotationEffect(.degrees(tipDegrees))
                    .opacity(firstLap > 0.001 ? 1 : 0)
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

// MARK: - Rolling number (effects B and count-up)

/// How a `NoopRollingNumber` enters and changes.
public enum NoopNumberEntrance: Equatable {
    /// Counts to its value in step with the rings (0.9 s on entrance, 0.65 s on a change).
    case count
    /// Rises blurred in 0.85 s, then lands: a scale from 1.14 to 1, a brief glow of its colour, and a light
    /// haptic (effect B). For the headline number of a card.
    case slam
}

/// A number that moves to its value: on its first appearance in this launch (from 0, when armed and given a
/// `launchKey`), and on every change. Unarmed, or with the quiet-motion gate closed, it shows its value at
/// once; a slam still gives its haptic on a change.
///
/// The caller's `lineLimit` / `minimumScaleFactor` apply to the number as to any `Text`.
public struct NoopRollingNumber: View {
    private let value: Double
    private let format: (Double) -> String
    private let font: Font
    private let color: Color
    private let glow: Color
    private let entrance: NoopNumberEntrance
    private let armed: Bool
    private let launchKey: String?
    private let delay: Double
    private let haptic: Bool

    @State private var shown: Double
    @State private var origin: Double = 0
    @State private var started = false
    @State private var landScale: CGFloat = 1
    @State private var flash: Double = 0
    @State private var landing = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var motion = NoopMotionState.shared

    /// - Parameters:
    ///   - value: the number to show.
    ///   - format: maps the (moving) number to its text: rounding, grouping, decimals.
    ///   - font: the number's font.
    ///   - color: the number's colour.
    ///   - glow: the colour of the landing glow (a slam); the number's colour when nil.
    ///   - entrance: count or slam.
    ///   - armed: false shows the value at once and waits (data loading, or a render test).
    ///   - launchKey: names the entrance for `NoopLaunchOnce`; nil skips the entrance (changes still move).
    ///   - delay: the entrance's delay, to follow a ring's stagger.
    ///   - haptic: false keeps a slam silent.
    public init(value: Double, format: @escaping (Double) -> String, font: Font, color: Color,
                glow: Color? = nil, entrance: NoopNumberEntrance = .count, armed: Bool = true,
                launchKey: String? = nil, delay: Double = 0, haptic: Bool = true) {
        self.value = value
        self.format = format
        self.font = font
        self.color = color
        self.glow = glow ?? color
        self.entrance = entrance
        self.armed = armed
        self.launchKey = launchKey
        self.delay = delay
        self.haptic = haptic
        _shown = State(initialValue: value)
    }

    private var still: Bool { motion.poseStill(reduceMotion) }

    /// Armed and waiting for its entrance: drawn from 0, so the first frame is not the end of the run.
    private var waiting: Bool {
        guard let launchKey, armed, !started, !still else { return false }
        return !NoopLaunchOnce.hasPlayed(launchKey)
    }

    private var entranceDuration: Double {
        entrance == .slam ? NoopMotion.slamRiseDuration : NoopMotion.ringDrawDuration
    }

    private var changeDuration: Double {
        entrance == .slam ? NoopMotion.slamRiseDuration : NoopMotion.valueChangeDuration
    }

    public var body: some View {
        NoopRollingNumberFace(number: waiting ? 0 : shown, origin: origin, target: shown,
                              blurs: entrance == .slam, format: format, font: font, color: color)
            .scaleEffect(landScale, anchor: .bottomLeading)
            .shadow(color: glow.opacity(0.8 * flash), radius: 8)
            .onAppear { begin() }
            .onChangeCompat(of: armed) { _ in begin() }
            .onChangeCompat(of: value) { newValue in change(to: newValue) }
            .accessibilityElement()
            .accessibilityLabel(Text(verbatim: format(value)))
    }

    private func begin() {
        guard let launchKey, armed, !started else { return }
        guard !still, NoopLaunchOnce.markPlayed(launchKey) else {
            started = true
            return
        }
        origin = 0
        shown = value
        withAnimation(NoopMotion.strongEaseOut(entranceDuration).delay(delay)) { started = true }
        if entrance == .slam { land(after: delay + entranceDuration) }
    }

    private func change(to newValue: Double) {
        if still || waiting {
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) { shown = newValue }
            if still, entrance == .slam, haptic, armed { NoopSlamHaptic.fire() }
            return
        }
        origin = shown
        withAnimation(NoopMotion.strongEaseOut(changeDuration)) { shown = newValue }
        if entrance == .slam { land(after: changeDuration) }
    }

    /// The landing: a brief rise to `slamLandScale` with the glow lit, then the settle back to 1.
    private func land(after seconds: Double) {
        landing += 1
        let token = landing
        let pop = 0.06
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            guard token == landing else { return }
            if haptic { NoopSlamHaptic.fire() }
            withAnimation(.easeOut(duration: pop)) {
                landScale = NoopMotion.slamLandScale
                flash = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + pop) {
                guard token == landing else { return }
                withAnimation(.easeOut(duration: NoopMotion.slamLandDuration - pop)) {
                    landScale = 1
                    flash = 0
                }
            }
        }
    }
}

/// The animatable face of `NoopRollingNumber`: SwiftUI interpolates `number` frame by frame, and the blur of
/// a slam follows the share of the run still to go (largest at the start, where an ease-out moves fastest).
private struct NoopRollingNumberFace: View, Animatable {
    var number: Double
    let origin: Double
    let target: Double
    let blurs: Bool
    let format: (Double) -> String
    let font: Font
    let color: Color

    var animatableData: Double {
        get { number }
        set { number = newValue }
    }

    private var remaining: CGFloat {
        let span = abs(target - origin)
        guard span > 0.0001 else { return 0 }
        return CGFloat(min(1, abs(target - number) / span))
    }

    var body: some View {
        Text(verbatim: format(number))
            .font(font)
            .foregroundStyle(color)
            .monospacedDigit()
            .blur(radius: blurs ? NoopMotion.slamBlurMax * remaining : 0)
            .accessibilityHidden(true)
    }
}

/// One light haptic for the landings of several numbers at once (the four values of Today land within a few
/// hundredths of a second): at most one every 0.3 s.
enum NoopSlamHaptic {
    private static var lastFire: Date = .distantPast

    static func fire() {
        let now = Date()
        guard now.timeIntervalSince(lastFire) > 0.3 else { return }
        lastFire = now
        StrandHaptic.light.play()
    }
}

// MARK: - iOS 17 / macOS 14 effects

public extension View {
    /// A number's digits roll to a new `value` (`.numericText(value:)`, iOS 17 / macOS 14); nothing below.
    /// Drive the change with `NoopMotion.value` (or `.animation(…, value:)`).
    @ViewBuilder
    func noopNumericTransition(_ value: Double) -> some View {
        if #available(iOS 17.0, macOS 14.0, watchOS 10.0, *) {
            self.contentTransition(.numericText(value: value))
        } else {
            self
        }
    }

    /// An SF Symbol bounces once each time `trigger` changes (iOS 17 / macOS 14); nothing below. The system
    /// leaves it still under Reduce Motion.
    @ViewBuilder
    func noopSymbolBounce<V: Equatable>(_ trigger: V) -> some View {
        if #available(iOS 17.0, macOS 14.0, watchOS 10.0, *) {
            self.symbolEffect(.bounce, value: trigger)
        } else {
            self
        }
    }
}

// MARK: - Day slide

private struct NoopDaySlide: ViewModifier {
    /// The day shown, counted back from today (0 = today, 1 = yesterday…).
    let dayOffset: Int

    @State private var shift: CGFloat = 0
    @State private var previous: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var motion = NoopMotionState.shared

    func body(content: Content) -> some View {
        content
            .offset(x: shift)
            .opacity(1 - 0.6 * Double(min(1, abs(shift) / NoopMotion.daySlideDistance)))
            .onAppear { previous = dayOffset }
            .onChangeCompat(of: dayOffset) { newOffset in
                let before = previous ?? newOffset
                previous = newOffset
                guard !motion.poseStill(reduceMotion), before != newOffset else { return }
                // An older day comes in from the left, a newer one from the right.
                let side: CGFloat = newOffset > before ? 1 : -1
                var instant = Transaction()
                instant.disablesAnimations = true
                withTransaction(instant) { shift = -side * NoopMotion.daySlideDistance }
                DispatchQueue.main.async {
                    withAnimation(NoopMotion.strongEaseOut(0.42)) { shift = 0 }
                }
            }
    }
}

public extension View {
    /// Slides the view in by 28 pt from the side the new day came from, fading from 40 %, when `dayOffset`
    /// changes (0 = today, larger = older). Still under the quiet-motion gate.
    func noopDaySlide(_ dayOffset: Int) -> some View {
        modifier(NoopDaySlide(dayOffset: dayOffset))
    }
}

// MARK: - Loading shimmer

/// The sweep of a loading skeleton: a band of light crossing the view, looping while it loads. A view of its
/// own so each loading run starts from the left edge.
private struct NoopShimmerSweep: View {
    @State private var phase: CGFloat = -0.6

    var body: some View {
        GeometryReader { geo in
            LinearGradient(colors: [StrandPalette.textPrimary.opacity(0),
                                    StrandPalette.textPrimary.opacity(0.16),
                                    StrandPalette.textPrimary.opacity(0)],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: geo.size.width * 0.6)
                .offset(x: phase * geo.size.width)
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { phase = 1.1 }
        }
    }
}

private struct NoopShimmer: ViewModifier {
    let active: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var motion = NoopMotionState.shared

    func body(content: Content) -> some View {
        content
            .overlay {
                if active && !motion.poseStill(reduceMotion) {
                    NoopShimmerSweep().mask { content }
                }
            }
    }
}

public extension View {
    /// A loading skeleton's sweep over the view while `active`; nothing once it loads or under the
    /// quiet-motion gate.
    func noopShimmer(_ active: Bool) -> some View {
        modifier(NoopShimmer(active: active))
    }
}

// MARK: - Curve reveal

private struct NoopRevealOnce: ViewModifier {
    let key: String
    let armed: Bool

    func body(content: Content) -> some View {
        NoopFirstDraw(key: key, armed: armed) { phase in
            content
                .mask(alignment: .leading) {
                    Rectangle()
                        .scaleEffect(x: phase.drawn ? 1 : 0.001, y: 1, anchor: .leading)
                        .animation(phase.motion(NoopMotion.curveDraw), value: phase.drawn)
                }
        }
    }
}

public extension View {
    /// A curve traces itself in, left to right in 1.1 s, the first time it is armed in this launch (`key`
    /// names it for `NoopLaunchOnce`). Unarmed, already played or under the quiet-motion gate it is drawn
    /// whole.
    func noopRevealOnce(_ key: String, armed: Bool = true) -> some View {
        modifier(NoopRevealOnce(key: key, armed: armed))
    }
}

// MARK: - Rolling digits

private struct NoopRollingDigits: ViewModifier {
    let value: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var motion = NoopMotionState.shared

    func body(content: Content) -> some View {
        content
            .noopNumericTransition(value)
            .animation(NoopMotion.gated(NoopMotion.valueChange, reduced: motion.poseStill(reduceMotion)),
                       value: value)
    }
}

public extension View {
    /// A figure rolls its digits to a new `value` in 0.65 s (`.numericText(value:)`, iOS 17 / macOS 14); at
    /// once under the quiet-motion gate.
    func noopRollingDigits(_ value: Double) -> some View {
        modifier(NoopRollingDigits(value: value))
    }
}
