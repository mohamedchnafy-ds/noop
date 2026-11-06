import SwiftUI

// MARK: - Chantier 12 (personal fork): the animation pass's tokens and primitives
//
// The screens rebuilt in the fork had almost no motion. This file holds what they share, so no screen
// carries a duration of its own:
//
//   • the tokens of the motion table (ring draw, value change, the "slam" of a headline number)
//   • `NoopLaunchOnce` — the ledger of the entrances that played: once per launch (a cascade, a record),
//     or once per showing of their screen (`noopEntranceRoot()` counts the showings, 6 Nov.)
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
    static let slamBlurMax: CGFloat = 8
    /// The scale a rising number lands from.
    static let slamLandScale: CGFloat = 1.22
    /// The radius of the glow a landing number flashes.
    static let slamGlowRadius: CGFloat = 14
    /// How far the glow of a ring's lit tip reaches past the tip.
    static let tipGlowRadius: CGFloat = 8
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

// MARK: - Once per launch, once per showing

/// The entrances that already played. In memory only: a new launch plays them all again.
///
/// Two ledgers. The plain one is once per launch: a cascade of blocks, a record's burst, which must not
/// replay when their screen is shown again. The `generation` one is once per showing of the screen (the
/// rings, the headline numbers, the curves, 6 Nov.): `noopEntranceRoot()` counts the showings of a screen
/// and a key plays once per count, so a tab shown again or a screen pushed again plays its entrance anew,
/// while a lazy row scrolled back into view within the same showing does not.
public enum NoopLaunchOnce {
    private static var played: Set<String> = []
    private static var playedGeneration: [String: Int] = [:]

    /// Whether the entrance named `key` already played in this launch.
    public static func hasPlayed(_ key: String) -> Bool { played.contains(key) }

    /// Marks the entrance named `key` as played; true for the one caller that gets to play it.
    @discardableResult
    public static func markPlayed(_ key: String) -> Bool { played.insert(key).inserted }

    /// Whether the entrance named `key` already played in this `generation` of its screen.
    public static func hasPlayed(_ key: String, generation: Int) -> Bool {
        playedGeneration[key] == generation
    }

    /// Marks the entrance named `key` as played in this `generation`; true for the one caller that gets to
    /// play it, false once it played in that generation.
    @discardableResult
    public static func markPlayed(_ key: String, generation: Int) -> Bool {
        guard playedGeneration[key] != generation else { return false }
        playedGeneration[key] = generation
        return true
    }
}

private struct NoopEntranceGenerationKey: EnvironmentKey {
    static let defaultValue = 0
}

public extension EnvironmentValues {
    /// How many times the screen holding the view was shown, counted by `noopEntranceRoot()`: the
    /// entrances keyed for `NoopLaunchOnce` play once per count. 0 outside such a root (macOS, sheets,
    /// previews), where they play once per launch.
    var noopEntranceGeneration: Int {
        get { self[NoopEntranceGenerationKey.self] }
        set { self[NoopEntranceGenerationKey.self] = newValue }
    }
}

/// Counts the showings of a screen for `noopEntranceGeneration`: 1 from the start, so the first showing
/// plays once, then one more each time the root appears again (its tab selected again, a pushed screen
/// popped back to it). The views below replay their entrance on the change.
private struct NoopEntranceRoot: ViewModifier {
    @State private var generation = 1
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .environment(\.noopEntranceGeneration, generation)
            .onAppear {
                if shown {
                    generation += 1
                } else {
                    shown = true
                }
            }
    }
}

public extension View {
    /// Marks the root of a screen whose entrances (rings, headline numbers, curves) replay each time it is
    /// shown: the tab roots of the iOS shell.
    func noopEntranceRoot() -> some View {
        modifier(NoopEntranceRoot())
    }
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

/// Hands its content a `drawn` flag that turns true once, the first time the surface is armed in this showing
/// of its screen, under `NoopMotion.ringDraw`; the screen shown again (`noopEntranceGeneration`) empties the
/// surface at once and draws it in anew. Pieces of the content can pick their own curve or delay with
/// `.animation(phase.motion(…), value: phase.drawn)`.
///
/// Unarmed (data not loaded yet, or a PNG render) the content is drawn whole. Armed but already played in this
/// showing, or with the quiet-motion gate closed, it is drawn whole too.
public struct NoopFirstDraw<Content: View>: View {
    private let key: String
    private let armed: Bool
    private let content: (NoopDrawPhase) -> Content

    @State private var started = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.noopEntranceGeneration) private var generation
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
        armed && !started && !still && !NoopLaunchOnce.hasPlayed(key, generation: generation)
    }

    public var body: some View {
        content(NoopDrawPhase(drawn: !waiting, still: still))
            .onAppear { begin() }
            .onChangeCompat(of: armed) { _ in begin() }
            .onChangeCompat(of: generation) { _ in replay() }
    }

    private func begin() {
        guard armed, !started else { return }
        guard !still, NoopLaunchOnce.markPlayed(key, generation: generation) else {
            started = true
            return
        }
        withAnimation(NoopMotion.ringDraw) { started = true }
    }

    /// The screen is shown again: the surface empties without moving, then draws itself in.
    private func replay() {
        guard armed, started, !still else { return }
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { started = false }
        DispatchQueue.main.async { begin() }
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
                // The tip's glow is drawn (a radial gradient behind the dot), not a shadow: a shadow is a
                // filter the compositor runs again on every frame of a scroll (6 Nov. evening).
                Circle()
                    .fill(secondLap > 0 ? deep : tint)
                    .frame(width: lineWidth, height: lineWidth)
                    .background(
                        Circle()
                            .fill(RadialGradient(colors: [tint.opacity(0.75), tint.opacity(0)], center: .center,
                                                 startRadius: lineWidth * 0.4,
                                                 endRadius: lineWidth * 0.5 + NoopMotion.tipGlowRadius))
                            .frame(width: lineWidth + 2 * NoopMotion.tipGlowRadius,
                                   height: lineWidth + 2 * NoopMotion.tipGlowRadius)
                    )
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

/// A number that moves to its value: on its first appearance in each showing of its screen (from 0, when
/// armed and given a `launchKey`; see `noopEntranceGeneration`), and on every change. Unarmed, or with the
/// quiet-motion gate closed, it shows its value at once; a slam still gives its haptic on a change.
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
    /// True from the start of a slam's rise to its landing: the only time the text carries its blur.
    @State private var rising = false
    /// True from a landing to the end of its settle: the only time the text carries its glow.
    @State private var glowing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.noopEntranceGeneration) private var generation
    @ObservedObject private var motion = NoopMotionState.shared

    /// - Parameters:
    ///   - value: the number to show.
    ///   - format: maps the (moving) number to its text: rounding, grouping, decimals.
    ///   - font: the number's font.
    ///   - color: the number's colour.
    ///   - glow: the colour of the landing glow (a slam); the number's colour when nil.
    ///   - entrance: count or slam.
    ///   - armed: false shows the value at once and waits (data loading, or a render test).
    ///   - launchKey: names the entrance for `NoopLaunchOnce`, played once per showing of the screen; nil
    ///     skips the entrance (changes still move).
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
        return !NoopLaunchOnce.hasPlayed(launchKey, generation: generation)
    }

    private var entranceDuration: Double {
        entrance == .slam ? NoopMotion.slamRiseDuration : NoopMotion.ringDrawDuration
    }

    private var changeDuration: Double {
        entrance == .slam ? NoopMotion.slamRiseDuration : NoopMotion.valueChangeDuration
    }

    public var body: some View {
        face
            .scaleEffect(landScale, anchor: .bottomLeading)
            .onAppear { begin() }
            .onChangeCompat(of: armed) { _ in begin() }
            .onChangeCompat(of: generation) { _ in replay() }
            .onChangeCompat(of: value) { newValue in change(to: newValue) }
            .accessibilityElement()
            .accessibilityLabel(Text(verbatim: format(value)))
    }

    /// The text, blurred only while a slam rises and glowing only while it lands. A blur of 0 or a glow of
    /// no colour left on the number at rest is still a filter the compositor runs on every frame of a
    /// scroll, for nothing to show (6 Nov. evening); `rising` and `glowing` are set outside any animation,
    /// so the text swaps its filters without a fade.
    @ViewBuilder
    private var face: some View {
        let text = NoopRollingNumberFace(number: waiting ? 0 : shown, origin: origin, target: shown,
                                         blurs: entrance == .slam && rising, format: format, font: font,
                                         color: color)
        if glowing {
            text.shadow(color: glow.opacity(0.8 * flash), radius: NoopMotion.slamGlowRadius)
        } else {
            text
        }
    }

    private func begin() {
        guard let launchKey, armed, !started else { return }
        guard !still, NoopLaunchOnce.markPlayed(launchKey, generation: generation) else {
            started = true
            return
        }
        origin = 0
        shown = value
        if entrance == .slam { rising = true }
        withAnimation(NoopMotion.strongEaseOut(entranceDuration).delay(delay)) { started = true }
        if entrance == .slam { land(after: delay + entranceDuration) }
    }

    /// The screen is shown again: back to 0 without moving, then the entrance anew.
    private func replay() {
        guard launchKey != nil, armed, started, !still else { return }
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { started = false }
        DispatchQueue.main.async { begin() }
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
        if entrance == .slam { rising = true }
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
            rising = false
            glowing = true
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
                // The glow has faded: the shadow leaves the text (no animation, so no fade of the text).
                DispatchQueue.main.asyncAfter(deadline: .now() + NoopMotion.slamLandDuration - pop) {
                    guard token == landing else { return }
                    glowing = false
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
    /// True only while a slam rises: the text then carries its blur. False attaches no filter at all.
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
        let text = Text(verbatim: format(number))
            .font(font)
            .foregroundStyle(color)
            .monospacedDigit()
            .accessibilityHidden(true)
        if blurs {
            text.blur(radius: NoopMotion.slamBlurMax * remaining)
        } else {
            text
        }
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

// MARK: - Record (effect D)

/// The « Record » badge: white, it pops in (0.4 → 1.15 → 1) while eight short rays leave it (0.65 s) and a
/// heavy haptic lands. Plays once per `launchKey` (a set's record must not replay as its row scrolls back);
/// unarmed, already played or under the quiet-motion gate it is simply there, the haptic kept for a new one.
public struct NoopRecordBadge: View {
    private let label: Text
    private let tint: Color
    private let armed: Bool
    private let launchKey: String

    @State private var scale: CGFloat = 1
    @State private var rays: CGFloat = 1
    @State private var started = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var motion = NoopMotionState.shared

    /// - Parameters:
    ///   - label: the badge's word (the app's catalogue: « Record »).
    ///   - tint: the colour of the rays.
    ///   - armed: false shows the badge at once, silently (renders, a record already seen).
    ///   - launchKey: names this record for `NoopLaunchOnce`.
    public init(label: Text, tint: Color, armed: Bool, launchKey: String) {
        self.label = label
        self.tint = tint
        self.armed = armed
        self.launchKey = launchKey
    }

    private var still: Bool { motion.poseStill(reduceMotion) }

    private var waiting: Bool { armed && !started && !still && !NoopLaunchOnce.hasPlayed(launchKey) }

    public var body: some View {
        label
            .font(StrandFont.caption.weight(.bold))
            .foregroundStyle(StrandPalette.surfaceBase)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(StrandPalette.textPrimary))
            .fixedSize()
            .background { rayBurst }
            .scaleEffect(waiting ? 0.4 : scale)
            .opacity(waiting ? 0 : 1)
            .onAppear { play() }
    }

    /// Eight short strokes around the badge, travelling out and fading as `rays` goes from 0 to 1.
    private var rayBurst: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { index in
                Capsule()
                    .fill(tint)
                    .frame(width: 2, height: 7)
                    .offset(y: -(14 + 16 * rays))
                    .rotationEffect(.degrees(Double(index) * 45))
            }
        }
        .opacity(rays < 1 ? Double(1 - rays) : 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func play() {
        guard armed, !started else { return }
        guard NoopLaunchOnce.markPlayed(launchKey) else {
            started = true
            return
        }
        StrandHaptic.heavy.play()
        guard !still else {
            started = true
            return
        }
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            scale = 0.4
            rays = 0
            started = true
        }
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.55)) { scale = 1 }
            withAnimation(.easeOut(duration: 0.65)) { rays = 1 }
        }
    }
}

private struct NoopShineSweep: View {
    @State private var travel: CGFloat = -1

    var body: some View {
        GeometryReader { geo in
            LinearGradient(colors: [StrandPalette.textPrimary.opacity(0),
                                    StrandPalette.textPrimary.opacity(0.22),
                                    StrandPalette.textPrimary.opacity(0)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .frame(width: geo.size.width * 0.5, height: geo.size.height * 2)
                .rotationEffect(.degrees(20))
                .offset(x: travel * geo.size.width * 1.3, y: -geo.size.height / 2)
        }
        .allowsHitTesting(false)
        .onAppear { withAnimation(.easeOut(duration: 0.8)) { travel = 1.2 } }
    }
}

private struct NoopRecordShine: ViewModifier {
    let active: Bool
    let launchKey: String

    @State private var sweeping = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var motion = NoopMotionState.shared

    func body(content: Content) -> some View {
        content
            .overlay {
                if sweeping {
                    NoopShineSweep().mask { content }
                }
            }
            .onAppear { sweep() }
            .onChangeCompat(of: active) { _ in sweep() }
    }

    private func sweep() {
        guard active, !motion.poseStill(reduceMotion),
              NoopLaunchOnce.markPlayed(launchKey + ".shine") else { return }
        sweeping = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) { sweeping = false }
    }
}

public extension View {
    /// A diagonal reflection crosses the view once (0.8 s) when a record lands on it (`active`), once per
    /// `launchKey`; nothing under the quiet-motion gate.
    func noopRecordShine(_ active: Bool, launchKey: String) -> some View {
        modifier(NoopRecordShine(active: active, launchKey: launchKey))
    }
}

// MARK: - Scoreboard (effect F)

/// One figure of the end-of-session scoreboard.
public struct NoopScoreboardLine: Identifiable {
    public let id: Int
    public let label: Text
    public let value: String
    public let tint: Color

    public init(id: Int, label: Text, value: String, tint: Color) {
        self.id = id
        self.label = label
        self.value = value
        self.tint = tint
    }
}

/// The end of a session as a scoreboard: an optional Effort ring in a gradient (effect A), then each figure
/// coming in from the right, 60 pt SF Rounded, tilted by −12° and straightening, 0.22 s apart, then the
/// record line (effect D). A tap anywhere, or the close button, ends it. Under the quiet-motion gate it is
/// drawn at once.
public struct NoopScoreboard: View {
    private let title: Text
    private let lines: [NoopScoreboardLine]
    private let ring: (fraction: Double, tint: Color, deep: Color, value: String)?
    private let record: Text?
    private let recordBadge: Text
    private let recordKey: String
    private let closeLabel: Text
    private let onClose: () -> Void

    @State private var entered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var motion = NoopMotionState.shared

    /// - Parameters:
    ///   - title: the session's name.
    ///   - lines: the figures, top to bottom.
    ///   - ring: the Effort ring: its share of the scale, tint, deep tone and the value written inside.
    ///   - record: the record line (« 2 records »), nil without a record.
    ///   - recordBadge: the badge's word (« Record »).
    ///   - recordKey: names the badge's burst for `NoopLaunchOnce`.
    ///   - closeLabel: the close button's word.
    ///   - onClose: called once, on a tap or the button.
    public init(title: Text, lines: [NoopScoreboardLine],
                ring: (fraction: Double, tint: Color, deep: Color, value: String)? = nil,
                record: Text? = nil, recordBadge: Text, recordKey: String, closeLabel: Text,
                onClose: @escaping () -> Void) {
        self.title = title
        self.lines = lines
        self.ring = ring
        self.record = record
        self.recordBadge = recordBadge
        self.recordKey = recordKey
        self.closeLabel = closeLabel
        self.onClose = onClose
    }

    private var still: Bool { motion.poseStill(reduceMotion) }
    private var shown: Bool { entered || still }

    public var body: some View {
        ZStack {
            StrandPalette.surfaceBase.ignoresSafeArea()
            VStack(alignment: .leading, spacing: NoopMetrics.space4) {
                title
                    .font(StrandFont.screenTitle)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                if let ring {
                    ZStack {
                        Circle().stroke(ring.tint.opacity(0.18), lineWidth: 14)
                        NoopGradientArc(fraction: shown ? ring.fraction : 0, tint: ring.tint, deep: ring.deep,
                                        diameter: 132, lineWidth: 14)
                            .rotationEffect(.degrees(-90))
                            .animation(still ? nil : NoopMotion.ringDraw, value: entered)
                        Text(verbatim: ring.value)
                            .font(StrandFont.rounded(36, weight: .heavy))
                            .foregroundStyle(StrandPalette.textPrimary)
                            .monospacedDigit()
                    }
                    .frame(width: 132, height: 132)
                    .frame(maxWidth: .infinity)
                }
                ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                    VStack(alignment: .leading, spacing: 0) {
                        line.label
                            .font(StrandFont.subhead.weight(.semibold))
                            .foregroundStyle(StrandPalette.textSecondary)
                        Text(verbatim: line.value)
                            .font(StrandFont.rounded(60, weight: .heavy))
                            .foregroundStyle(line.tint)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .offset(x: shown ? 0 : 80)
                    .rotationEffect(.degrees(shown ? 0 : -12), anchor: .leading)
                    .opacity(shown ? 1 : 0)
                    .animation(still ? nil : NoopMotion.strongEaseOut(0.55).delay(0.2 + Double(index) * 0.22),
                               value: entered)
                }
                if let record {
                    HStack(spacing: NoopMetrics.space2) {
                        NoopRecordBadge(label: recordBadge, tint: StrandPalette.statusPositive,
                                        armed: shown, launchKey: recordKey)
                        record
                            .font(StrandFont.body.weight(.semibold))
                            .foregroundStyle(StrandPalette.textPrimary)
                    }
                    .opacity(shown ? 1 : 0)
                    .animation(still ? nil : .easeOut(duration: 0.3).delay(0.2 + Double(lines.count) * 0.22),
                               value: entered)
                }
                Spacer(minLength: 0)
                Button(action: onClose) {
                    closeLabel
                        .font(StrandFont.body.weight(.semibold))
                        .foregroundStyle(StrandPalette.surfaceBase)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Capsule().fill(StrandPalette.textPrimary))
                }
                .buttonStyle(.plain)
            }
            .padding(NoopMetrics.space5)
        }
        .contentShape(Rectangle())
        .onTapGesture { onClose() }
        .onAppear {
            StrandHaptic.success.play()
            entered = true
        }
    }
}

// MARK: - Countdown (effect E)

/// 3 · 2 · 1 · Go before a cardio session: an 80 pt SF Rounded figure landing from 1.55, a ring emptying in
/// each second, a selection tick on 3, 2 and 1, then « Go » in green with a glow and a heavy haptic. `onGo`
/// starts the recording at the « Go »; `onEnd` hides the overlay 0.6 s later. A tap skips straight to both.
/// Under the quiet-motion gate the figures change without moving; the haptics stay.
public struct NoopCountdown: View {
    private let goLabel: Text
    private let onGo: () -> Void
    private let onEnd: () -> Void

    @State private var step = 3
    @State private var pop: CGFloat = 1
    @State private var ring: CGFloat = 1
    @State private var went = false
    @State private var ended = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var motion = NoopMotionState.shared

    public init(goLabel: Text, onGo: @escaping () -> Void, onEnd: @escaping () -> Void) {
        self.goLabel = goLabel
        self.onGo = onGo
        self.onEnd = onEnd
    }

    private var still: Bool { motion.poseStill(reduceMotion) }
    private var tint: Color { step == 0 ? StrandPalette.statusPositive : StrandPalette.textPrimary }

    public var body: some View {
        ZStack {
            StrandPalette.surfaceBase.opacity(0.94).ignoresSafeArea()
            ZStack {
                Circle().stroke(StrandPalette.hairline, lineWidth: 8)
                Circle()
                    .trim(from: 0, to: ring)
                    .stroke(tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Group {
                    if step > 0 {
                        Text(verbatim: String(step))
                    } else {
                        goLabel
                    }
                }
                .font(StrandFont.rounded(80, weight: .heavy))
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .shadow(color: StrandPalette.statusPositive.opacity(step == 0 ? 0.7 : 0), radius: 18)
            }
            .frame(width: 180, height: 180)
            .scaleEffect(pop)
        }
        .contentShape(Rectangle())
        .onTapGesture { skip() }
        .onAppear { beat() }
        .onDisappear { ended = true }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    /// One second of the countdown: its haptic, the figure landing, the ring emptying, then the next.
    private func beat() {
        guard !ended else { return }
        if step > 0 {
            StrandHaptic.selection.play()
        } else {
            StrandHaptic.heavy.play()
            go()
        }
        if !still {
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) {
                pop = 1.55
                ring = 1
            }
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.45)) { pop = 1 }
                withAnimation(.linear(duration: 0.95)) { ring = step == 0 ? 1 : 0 }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (step == 0 ? 0.6 : 1.0)) {
            guard !ended else { return }
            if step > 0 {
                step -= 1
                beat()
            } else {
                end()
            }
        }
    }

    private func go() {
        guard !went else { return }
        went = true
        onGo()
    }

    private func end() {
        guard !ended else { return }
        ended = true
        onEnd()
    }

    private func skip() {
        go()
        end()
    }
}

// MARK: - Live heart (effect C)

/// A heart beating at the real rhythm (a period of 60 / bpm): a quick swell at each beat and a ring leaving
/// it. A loop only while it serves (`beating`, a live heart rate); still under the quiet-motion gate.
public struct NoopHeartbeat: View {
    private let bpm: Int?
    private let tint: Color
    private let size: CGFloat
    private let beating: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var motion = NoopMotionState.shared

    public init(bpm: Int?, tint: Color, size: CGFloat = 18, beating: Bool) {
        self.bpm = bpm
        self.tint = tint
        self.size = size
        self.beating = beating
    }

    public var body: some View {
        if beating, let bpm, bpm >= Self.slowestBeat, !motion.poseStill(reduceMotion) {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                heart(phase: Self.beatPhase(at: context.date, bpm: bpm))
            }
        } else {
            heart(phase: 1)
        }
    }

    /// Below this rate nothing beats: a reading that low is not a rhythm to show.
    public static let slowestBeat = 25

    /// Where a beat at `bpm` stands at `date`, 0 at the beat and rising to 1 just before the next, on the
    /// shared clock: every view beating at one rate (the heart beside Today's number, the wave at the end of
    /// its curve) reads the same phase and beats together (6 Nov. evening). 0 below `slowestBeat`.
    public static func beatPhase(at date: Date, bpm: Int) -> Double {
        guard bpm >= slowestBeat else { return 0 }
        let period = 60.0 / Double(bpm)
        return date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
    }

    private func heart(phase: Double) -> some View {
        let swell = phase < 0.16 ? sin(phase / 0.16 * .pi) : 0
        return ZStack {
            Circle()
                .stroke(tint, lineWidth: 1.5)
                .frame(width: size, height: size)
                .scaleEffect(CGFloat(1 + 1.3 * phase))
                .opacity(phase < 1 ? 0.55 * (1 - phase) : 0)
            Image(systemName: "heart.fill")
                .font(.system(size: size * 0.8, weight: .semibold))
                .foregroundStyle(tint)
                .scaleEffect(CGFloat(1 + 0.2 * swell))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Z1 to Z5 as five short bars, the active zone lit in its colour and the others dimmed; the light moves in
/// 0.35 s when the zone changes.
public struct NoopZoneStrip: View {
    private let zone: Int
    private let colors: [Color]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var motion = NoopMotionState.shared

    /// - Parameters:
    ///   - zone: the active zone, 1…5; 0 lights none.
    ///   - colors: the five zone colours (`StrandPalette.zone1…zone5`).
    public init(zone: Int, colors: [Color]) {
        self.zone = zone
        self.colors = colors
    }

    public var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(colors.prefix(5).enumerated()), id: \.offset) { index, color in
                Capsule()
                    .fill(color.opacity(index + 1 == zone ? 1 : 0.25))
                    .frame(height: 5)
                    .shadow(color: color.opacity(index + 1 == zone ? 0.7 : 0), radius: 4)
            }
        }
        .animation(NoopMotion.gated(.easeOut(duration: 0.35), reduced: motion.poseStill(reduceMotion)), value: zone)
        .accessibilityHidden(true)
    }
}

// MARK: - Beat pulse (effect C, the end of a live curve)

/// A wave leaving a point at every beat: a ring that grows from the point and fades over the beat, at the true
/// rhythm (60 / bpm) on the same clock as `NoopHeartbeat`, so both beat together. For the "now" dot at the
/// end of a live curve. Draws nothing when not beating, under the quiet-motion gate, or below
/// `NoopHeartbeat.slowestBeat`: the dot itself is the curve's to draw.
public struct NoopBeatPulse: View {
    private let bpm: Int?
    private let tint: Color
    private let size: CGFloat
    private let beating: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var motion = NoopMotionState.shared

    /// - Parameters:
    ///   - bpm: the live rate; nil draws nothing.
    ///   - tint: the colour of the wave (the dot's).
    ///   - size: the diameter the wave starts from (the dot's).
    ///   - beating: false draws nothing (a render, a paused session).
    public init(bpm: Int?, tint: Color, size: CGFloat = 8, beating: Bool) {
        self.bpm = bpm
        self.tint = tint
        self.size = size
        self.beating = beating
    }

    public var body: some View {
        if beating, let bpm, bpm >= NoopHeartbeat.slowestBeat, !motion.poseStill(reduceMotion) {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                wave(phase: NoopHeartbeat.beatPhase(at: context.date, bpm: bpm))
            }
        } else {
            EmptyView()
        }
    }

    private func wave(phase: Double) -> some View {
        Circle()
            .stroke(tint, lineWidth: 1.5)
            .frame(width: size, height: size)
            .scaleEffect(CGFloat(1 + 2.2 * phase))
            .opacity(phase < 1 ? 0.6 * (1 - phase) : 0)
            .accessibilityHidden(true)
    }
}

// MARK: - Waiting spark

/// The Coach's spark while it works: sparkles that breathe (scale and light), looping while they serve;
/// still under the quiet-motion gate.
public struct NoopWaitingSpark: View {
    private let tint: Color

    @State private var lit = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var motion = NoopMotionState.shared

    public init(tint: Color) {
        self.tint = tint
    }

    public var body: some View {
        let still = motion.poseStill(reduceMotion)
        Image(systemName: "sparkles")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(tint)
            .scaleEffect(lit && !still ? 1.15 : 0.9)
            .opacity(lit && !still ? 1 : 0.6)
            .shadow(color: tint.opacity(lit && !still ? 0.6 : 0), radius: 6)
            .animation(still ? nil : .easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: lit)
            .onAppear { lit = true }
            .accessibilityHidden(true)
    }
}
