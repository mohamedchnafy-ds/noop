import SwiftUI
import StrandDesign

// MARK: - Today hero card (personal fork, chantier 7 "Fitness + Santé")
//
// One card, as in the retained mockup: four flat concentric rings (activity calories, Charge, Effort,
// Rest) beside one line per ring, a hairline, then three cells on a fixed row grid (spent energy, resting
// heart rate, HRV) with a flat bar each. Pure views: every number arrives in a model, so the render test
// draws the real card with the real tokens.

/// One ring of the hero: the share of the full circle it fills, and for Effort the optimal band behind it.
struct TodayRing: Equatable {
    var fraction: Double
    var tint: Color
    var band: ClosedRange<Double>? = nil
    /// The deep tone the gradient starts from (a `StrandPalette` token, fork chantier 12); nil draws it flat.
    var deep: Color? = nil
}

/// The four concentric flat rings, outside to inside: a track at 18 %, a translucent target band, the fill
/// with round caps, in a gradient from its deep tone to its vivid tip (fork chantier 12, effect A). Armed, the
/// rings trace themselves once per launch, 0.09 s apart, then follow every change of value in 0.65 s.
struct TodayConcentricRings: View {
    var rings: [TodayRing]
    var diameter: CGFloat = 184
    var lineWidth: CGFloat = 13
    var spacing: CGFloat = 4
    /// False draws the rings whole at once (data still loading, or a PNG render).
    var animated: Bool = false
    /// Names the entrance for `NoopLaunchOnce`, one per screen.
    var drawKey: String = "today.rings"
    /// The soft light behind the rings (Today: the colour of the day's Charge), nil for none.
    var halo: Color? = nil
    /// A goal just closed, 0…1: the rings grow by 4.5 % and the ring at `pulseRing` glows.
    var pulse: Double = 0
    var pulseRing: Int? = nil
    /// A fraction above 1 adds a second lap in the deep tone (Nutrition: an intake over its goal).
    var allowsOverflow: Bool = false

    private func clamped(_ v: Double) -> CGFloat { CGFloat(min(1, max(0, v))) }

    var body: some View {
        NoopFirstDraw(key: drawKey, armed: animated) { phase in
            ZStack {
                if let halo {
                    haloLight(halo, phase: phase)
                }
                ForEach(rings.indices, id: \.self) { index in
                    ringView(rings[index], index: index,
                             size: diameter - lineWidth - 2 * CGFloat(index) * (lineWidth + spacing),
                             phase: phase)
                }
            }
            .scaleEffect(1 + 0.045 * pulse)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }

    /// Lit once the rings are traced, then kept at `TodayHeroMotion.haloRest`; a closed goal brightens it to
    /// full for a moment. Wider than the rings, so the card that holds them clips it (6 Nov.: the first cut,
    /// at a third of the tint over 1.3 diameters, could not be seen on the card).
    private func haloLight(_ tint: Color, phase: NoopDrawPhase) -> some View {
        Circle()
            .fill(RadialGradient(gradient: Gradient(stops: [
                .init(color: tint.opacity(TodayHeroMotion.haloCore), location: 0),
                .init(color: tint.opacity(TodayHeroMotion.haloMid), location: 0.4),
                .init(color: tint.opacity(0), location: 1)
            ]), center: .center, startRadius: 0, endRadius: diameter * TodayHeroMotion.haloReach))
            .frame(width: diameter * TodayHeroMotion.haloSpread, height: diameter * TodayHeroMotion.haloSpread)
            .opacity(phase.drawn ? TodayHeroMotion.haloRest + (1 - TodayHeroMotion.haloRest) * pulse : 0)
            .animation(phase.motion(NoopMotion.ringDraw.delay(NoopMotion.ringDrawDuration * 0.7)),
                       value: phase.drawn)
            .allowsHitTesting(false)
    }

    private func ringView(_ ring: TodayRing, index: Int, size: CGFloat, phase: NoopDrawPhase) -> some View {
        let ringDiameter = max(lineWidth, size)
        let fill = allowsOverflow ? max(0, ring.fraction) : min(1, max(0, ring.fraction))
        let lit = pulseRing == index ? pulse : 0
        return ZStack {
            Circle().stroke(ring.tint.opacity(0.18), lineWidth: lineWidth)
            if let band = ring.band, band.upperBound > band.lowerBound {
                Circle()
                    .trim(from: clamped(band.lowerBound), to: clamped(band.upperBound))
                    .stroke(ring.tint.opacity(0.35), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
            }
            tracedArc(ring, fill: fill, index: index, diameter: ringDiameter, lit: lit, phase: phase)
                .animation(phase.motion(NoopMotion.ringDraw.delay(Double(index) * NoopMotion.ringStagger)),
                           value: phase.drawn)
                .animation(phase.motion(NoopMotion.valueChange), value: fill)
        }
        .rotationEffect(.degrees(-90))
        .frame(width: ringDiameter, height: ringDiameter)
    }

    /// The arc, with its glow only while its goal is celebrated (`pulseRing`): the glow is a shadow, a filter
    /// the compositor runs on every frame the modifier is attached, so a ring at rest carries none
    /// (6 Nov. evening). `pulseRing` is set and cleared outside the pulse's animations, so the arc swaps
    /// without a fade.
    @ViewBuilder
    private func tracedArc(_ ring: TodayRing, fill: Double, index: Int, diameter: CGFloat, lit: Double,
                           phase: NoopDrawPhase) -> some View {
        let arc = NoopGradientArc(fraction: phase.drawn ? fill : 0, tint: ring.tint, deep: ring.deep ?? ring.tint,
                                  diameter: diameter, lineWidth: lineWidth, litTip: ring.deep != nil)
        if pulseRing == index {
            arc.shadow(color: ring.tint.opacity(0.9 * lit), radius: 8 * lit)
        } else {
            arc
        }
    }
}

/// One line beside the rings: the coloured label with its icon, then the number and a grey caption.
struct TodayRingRow: View {
    var symbol: String
    var tint: Color
    var label: String
    /// Nil draws "no data".
    var value: String?
    var caption: String?
    /// The number behind `value`, slammed in on its first appearance and on a change (fork chantier 12,
    /// effect B); nil draws `value` as plain text (a calibration "1/4").
    var number: Double? = nil
    var format: ((Double) -> String)? = nil
    /// False shows the number at once (data loading, or a PNG render).
    var armed: Bool = false
    var slamKey: String? = nil
    var slamDelay: Double = 0
    /// The ring's goal is reached: a check after the label, bouncing each time `celebrations` changes.
    var done: Bool = false
    var celebrations: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .accessibilityHidden(true)
                Text(label)
                    .font(StrandFont.overlineScaled(12))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if done {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .bold))
                        .noopSymbolBounce(celebrations)
                        .accessibilityLabel(Text("Goal reached"))
                }
            }
            .foregroundStyle(tint)
            if let value {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if let number, let format {
                        NoopRollingNumber(value: number, format: format, font: StrandFont.rounded(21),
                                          color: StrandPalette.textPrimary, glow: tint, entrance: .slam,
                                          armed: armed, launchKey: slamKey, delay: slamDelay)
                    } else {
                        Text(verbatim: value)
                            .font(StrandFont.rounded(21))
                            .foregroundStyle(StrandPalette.textPrimary)
                    }
                    if let caption {
                        Text(verbatim: caption)
                            .font(StrandFont.caption.weight(.medium))
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            } else {
                Text("no data")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .lineLimit(1)
                    .frame(minHeight: 24, alignment: .leading)
            }
        }
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// The fixed row grid shared by the three cells under the rings (label 16 / number 26 / bar 12 /
/// legend 14), so the three bars sit on one line whatever each cell holds.
struct TodayHeroCell<Bar: View>: View {
    var symbol: String
    var tint: Color
    var title: String
    /// Nil draws "no data".
    var value: String?
    var unit: String
    var legend: Text?
    /// The number behind `value`, counted up with the rings (fork chantier 12); nil draws `value` as text.
    var number: Double? = nil
    var format: ((Double) -> String)? = nil
    var armed: Bool = false
    var countKey: String? = nil
    @ViewBuilder var bar: Bar

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .accessibilityHidden(true)
                Text(title)
                    .font(StrandFont.overlineScaled(12))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(tint)
            .frame(height: 16, alignment: .leading)
            Group {
                if let value {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        if let number, let format {
                            NoopRollingNumber(value: number, format: format, font: StrandFont.rounded(22),
                                              color: StrandPalette.textPrimary, entrance: .count, armed: armed,
                                              launchKey: countKey, delay: TodayHeroMotion.cellsDelay)
                        } else {
                            Text(verbatim: value)
                                .font(StrandFont.rounded(22))
                                .foregroundStyle(StrandPalette.textPrimary)
                        }
                        Text(verbatim: unit)
                            .font(StrandFont.caption.weight(.medium))
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                } else {
                    Text("no data")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(height: 26, alignment: .leading)
            bar
                .frame(height: 12)
            (legend ?? Text(verbatim: " "))
                .font(StrandFont.caption2)
                .foregroundStyle(StrandPalette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(height: 14, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// The spent-energy bar: activity (orange), a 2-point gap, then resting (brown), on a white 10 % track.
struct TodayEnergyBar: View {
    var arc: TodayEnergy.Arc?
    /// Armed, the bar grows from the left once per launch, with the rings (fork chantier 12).
    var animated: Bool = false

    var body: some View {
        GeometryReader { geo in
            NoopFirstDraw(key: "today.bar.energy", armed: animated) { phase in
                barBody(width: geo.size.width, grown: phase.drawn)
                    .animation(phase.motion(NoopMotion.ringDraw.delay(TodayHeroMotion.cellsDelay)),
                               value: phase.drawn)
                    .animation(phase.motion(NoopMotion.valueChange), value: arc)
            }
            .frame(height: geo.size.height)
        }
    }

    private func barBody(width: CGFloat, grown: Bool) -> some View {
        let activity = grown ? CGFloat(arc?.activity ?? 0) * width : 0
        let resting = grown ? CGFloat(arc?.resting ?? 0) * width : 0
        let gap: CGFloat = activity > 0 && resting > 0 ? 2 : 0
        return ZStack(alignment: .leading) {
            Capsule().fill(StrandPalette.textPrimary.opacity(0.10))
            HStack(spacing: 0) {
                Rectangle().fill(StrandPalette.caloriesActivity).frame(width: activity)
                Rectangle().fill(StrandPalette.surfaceRaised).frame(width: gap)
                Rectangle().fill(StrandPalette.caloriesResting).frame(width: max(0, resting - gap))
            }
        }
        .frame(width: width, height: 6)
        .clipShape(Capsule())
    }
}

/// A nightly vital's bar: the personal normal band (translucent) and a dot where last night sits, between
/// the lowest and highest of the last 30 nights. The dot takes the tile's colour inside the normal band and
/// the warning colour outside it, the same rule for resting HR and HRV (5 Nov.).
struct TodayRangeBar: View {
    var gauge: TodayVitalRange.Gauge?
    var tint: Color
    /// Armed, the dot slides in from the left once per launch (`drawKey`), with the rings (fork chantier 12).
    var animated: Bool = false
    var drawKey: String = "today.bar.vital"

    var body: some View {
        GeometryReader { geo in
            NoopFirstDraw(key: drawKey, armed: animated) { phase in
                barBody(width: geo.size.width, placed: phase.drawn)
                    .animation(phase.motion(NoopMotion.ringDraw.delay(TodayHeroMotion.cellsDelay)),
                               value: phase.drawn)
                    .animation(phase.motion(NoopMotion.valueChange), value: gauge?.value)
            }
            .frame(height: geo.size.height)
        }
    }

    private func barBody(width: CGFloat, placed: Bool) -> some View {
        let bandFrom = gauge.flatMap { g in g.normal.map { CGFloat(g.fraction($0.lowerBound)) * width } }
        let bandTo = gauge.flatMap { g in g.normal.map { CGFloat(g.fraction($0.upperBound)) * width } }
        let dotX = gauge.map { placed ? CGFloat($0.fraction($0.value)) * width : 0 }
        return ZStack(alignment: .leading) {
            Capsule().fill(StrandPalette.textPrimary.opacity(0.10)).frame(height: 6)
            if let bandFrom, let bandTo {
                Capsule()
                    .fill(tint.opacity(0.28))
                    .frame(width: max(6, bandTo - bandFrom), height: 6)
                    .offset(x: bandFrom)
            }
            if let dotX {
                Circle()
                    .fill(gauge?.isOutsideNormal == true ? StrandPalette.statusWarning : tint)
                    .frame(width: 10, height: 10)
                    .offset(x: min(max(0, dotX - 5), max(0, width - 10)))
            }
        }
        .frame(width: width, height: 10, alignment: .leading)
    }
}

/// The spent-energy cell under the rings: the day's total, the activity / resting bar and both named.
struct TodayCaloriesTile: View {
    var split: TodayEnergy.Split?
    var goal: Double?
    /// Armed, the total counts up and the bar grows once per launch (fork chantier 12).
    var animated: Bool = false

    /// The kcal formatter Nutrition's « Spent » and « Net » use too (`NutritionFormat.wholeKcal`).
    private func number(_ v: Double) -> String {
        NutritionFormat.wholeKcal(v)
    }

    /// "activity 185 · resting 760", the two words from the catalogue and the numbers as they are.
    private var legend: Text? {
        guard let split else { return nil }
        let activityPart = " " + number(split.activityKcal)
        guard split.restingKcal > 0 else { return Text("activity") + Text(verbatim: activityPart) }
        let separator = activityPart + " \u{00B7} "
        let restingPart = " " + number(split.restingKcal)
        return Text("activity") + Text(verbatim: separator) + Text("resting") + Text(verbatim: restingPart)
    }

    var body: some View {
        TodayHeroCell(symbol: "flame.fill", tint: StrandPalette.caloriesResting,
                      title: String(localized: "Spent"),
                      value: split.map { number($0.totalKcal) }, unit: "kcal", legend: legend,
                      number: split.map(\.totalKcal), format: number, armed: animated,
                      countKey: "today.count.spent") {
            TodayEnergyBar(arc: split.map { TodayEnergy.arc($0, goal: goal) }, animated: animated)
        }
    }
}

/// A nightly vital cell under the rings: last night's value, its bar, and the personal normal band.
struct TodayVitalTile: View {
    var symbol: String
    var tint: Color
    var title: String
    var unit: String
    var gauge: TodayVitalRange.Gauge?
    /// Armed, the value counts up and the dot slides in once per launch, under this key (fork chantier 12).
    var animated: Bool = false
    var motionKey: String = "today.vital"

    private func whole(_ v: Double) -> String { String(Int(v.rounded())) }

    /// "your normal 58–64" once the baseline has a band, else the 30-night range alone.
    private var legend: Text? {
        guard let gauge else { return nil }
        if let band = gauge.normal {
            let range = whole(band.lowerBound) + "\u{2013}" + whole(band.upperBound)
            return Text("your normal \(range)")
        }
        return Text(verbatim: whole(gauge.low) + "\u{2013}" + whole(gauge.high))
    }

    var body: some View {
        TodayHeroCell(symbol: symbol, tint: tint, title: title,
                      value: gauge.map { whole($0.value) }, unit: unit, legend: legend,
                      number: gauge?.value, format: whole, armed: animated, countKey: motionKey + ".count") {
            TodayRangeBar(gauge: gauge, tint: tint, animated: animated, drawKey: motionKey + ".bar")
        }
    }
}

/// The day's meals under the three cells (personal fork, Nutrition mockup 4): eaten, the balance against
/// the calories spent, protein against its goal. A tap opens Nutrition.
struct TodayNutritionLine: View {
    struct Model: Equatable {
        var eatenKcal: Int
        /// Eaten minus spent; nil while nothing was measured.
        var balanceKcal: Int?
        var proteinG: Int
        var proteinGoalG: Int?
    }

    let model: Model

    private func number(_ value: Int) -> String {
        value.formatted(.number.locale(AppLanguage.activeLocale))
    }

    private func signedText(_ value: Int) -> String {
        value < 0 ? "\u{2212}" + number(-value) : (value > 0 ? "+" + number(value) : number(0))
    }

    private var line: Text {
        let bold = { (value: String) in
            Text(verbatim: value).foregroundColor(StrandPalette.textPrimary).fontWeight(.semibold)
        }
        var text = Text("Eaten \(bold(number(model.eatenKcal)))")
        if let balance = model.balanceKcal {
            text = text + Text(verbatim: " · ") + Text("balance \(bold(signedText(balance)))")
        }
        if let goal = model.proteinGoalG {
            text = text + Text(verbatim: " · ")
                + Text("protein \(bold(number(model.proteinG)))/\(number(goal)) g")
        } else {
            text = text + Text(verbatim: " · ") + Text("protein \(bold(number(model.proteinG))) g")
        }
        return text
    }

    private var spoken: String {
        var parts = [String(localized: "Nutrition: \(number(model.eatenKcal)) kcal eaten")]
        if let balance = model.balanceKcal { parts.append(String(localized: "balance \(signedText(balance))")) }
        if let goal = model.proteinGoalG {
            parts.append(String(localized: "protein \(number(model.proteinG)) of \(number(goal)) g"))
        } else {
            parts.append(String(localized: "protein \(number(model.proteinG)) g"))
        }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        TabRouteLink(route: .nutrition) {
            HStack(spacing: 8) {
                Image(systemName: "fork.knife")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(StrandPalette.textSecondary)
                    .accessibilityHidden(true)
                line
                    .font(StrandFont.overlineScaled(12.5))
                    .foregroundStyle(StrandPalette.textSecondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(StrandPalette.textTertiary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .overlay(alignment: .top) {
                Rectangle().fill(StrandPalette.hairline).frame(height: NoopMetrics.hairlineWidth)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: spoken))
        .accessibilityHint(Text("Opens Nutrition"))
        .accessibilityAddTraits(.isButton)
    }
}

/// The hero's own timings, from the motion table (fork chantier 12): the three cells follow the rings.
enum TodayHeroMotion {
    /// The cells' count-up and bars start 0.38 s after the rings.
    static let cellsDelay: Double = 0.38
    /// A closed goal is celebrated once the rings have landed.
    static let goalDelay: Double = 1.0
    /// The halo behind the rings (effect A), in the tint of the day's Charge: its width in ring diameters,
    /// the reach of its gradient in ring diameters, the share of the tint at its centre and at 40 % of the
    /// reach, and its opacity once lit (a closed goal takes it to full).
    static let haloSpread: CGFloat = 1.7
    static let haloReach: CGFloat = 0.85
    static let haloCore: Double = 0.55
    static let haloMid: Double = 0.2
    static let haloRest: Double = 0.75

    /// Where the day a goal was last celebrated is kept (device only, outside `.noopbak`).
    static func goalStoreKey(_ ring: String) -> String { "today.goalClosed." + ring }
}

/// Everything the hero card shows, already resolved.
struct TodayHeroModel {
    struct Ring {
        var label: String
        var score: Double?
        var tint: Color
        var maxValue: Double = 100
        var decimals: Int = 0
        var caption: String?
        var targetRange: ClosedRange<Double>? = nil
        var calibration: (done: Int, of: Int)? = nil
        var route: TabRoute?
        var guide: ScoreSection
    }

    var charge: Ring
    var effort: Ring
    var rest: Ring
    var calories: (split: TodayEnergy.Split?, goal: Double?)
    var restingHR: TodayVitalRange.Gauge?
    var hrv: TodayVitalRange.Gauge?
    /// Kept for the callers; the retained design shows no source badge on the hero.
    var sourceLabel: String?
    /// The day's meals, nil when none was logged (the line under the cells is then left out).
    var nutrition: TodayNutritionLine.Model? = nil
    /// Where the Calories line taps through to, or nil to keep it inert.
    var caloriesRoute: TabRoute? = nil
    /// The logical day when the card shows today, nil for a past day: a goal closed today is celebrated once
    /// (halo, check, success haptic), the day stored on the device (fork chantier 12).
    var goalDayKey: String? = nil
}

/// The hero card: the four rings beside their four lines, a hairline, then the three cells.
struct TodayHeroCard: View {
    var model: TodayHeroModel
    var animated: Bool
    var surfaceOpacity: Double = 1
    var onGuide: (ScoreSection) -> Void

    /// A goal just closed (fork chantier 12): the pulse of the rings, the ring it lights, the check's bounce.
    @State private var goalPulse: Double = 0
    @State private var pulseRing: Int?
    @State private var celebrations = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var motion = NoopMotionState.shared

    /// The kcal formatter Nutrition's « Spent » and « Net » use too (`NutritionFormat.wholeKcal`).
    private func number(_ v: Double) -> String {
        NutritionFormat.wholeKcal(v)
    }

    // MARK: Rings

    private var caloriesFraction: Double {
        guard let split = model.calories.split else { return 0 }
        if let goal = model.calories.goal, goal > 0 { return split.activityKcal / goal }
        return TodayEnergy.arc(split, goal: nil).activity
    }

    private func fraction(_ ring: TodayHeroModel.Ring) -> Double {
        if let c = ring.calibration { return c.of > 0 ? Double(c.done) / Double(c.of) : 0 }
        guard let score = ring.score, ring.maxValue > 0 else { return 0 }
        return score / ring.maxValue
    }

    private var effortBand: ClosedRange<Double>? {
        guard let band = model.effort.targetRange, model.effort.maxValue > 0 else { return nil }
        return (band.lowerBound / model.effort.maxValue)...(band.upperBound / model.effort.maxValue)
    }

    /// The Charge ring and its line share one tint: the score's band (red / yellow / green), or the plain
    /// Charge green while there is no score yet (calibration, no data).
    private var chargeTint: Color {
        guard model.charge.calibration == nil, let score = model.charge.score else {
            return StrandPalette.chargeColor
        }
        return StrandPalette.chargeTint(score)
    }

    /// The deep tone the Charge ring starts from, in the same bands as its tint.
    private var chargeDeep: Color {
        guard model.charge.calibration == nil, let score = model.charge.score else {
            return StrandPalette.chargeDeep
        }
        return StrandPalette.chargeTintDeep(score)
    }

    private var rings: [TodayRing] {
        [TodayRing(fraction: caloriesFraction, tint: StrandPalette.caloriesActivity,
                   deep: StrandPalette.caloriesActivityDeep),
         TodayRing(fraction: fraction(model.charge), tint: chargeTint, deep: chargeDeep),
         TodayRing(fraction: fraction(model.effort), tint: StrandPalette.effortColor, band: effortBand,
                   deep: StrandPalette.effortDeep),
         TodayRing(fraction: fraction(model.rest), tint: StrandPalette.restRing, deep: StrandPalette.restRingDeep)]
    }

    // MARK: Goals (fork chantier 12)

    /// The activity calories reached their goal.
    private var activityGoalReached: Bool {
        guard let split = model.calories.split, let goal = model.calories.goal, goal > 0 else { return false }
        return split.activityKcal >= goal
    }

    /// The Effort reached the bottom of its target band.
    private var effortGoalReached: Bool {
        guard let band = model.effort.targetRange, let score = model.effort.score else { return false }
        return score >= band.lowerBound
    }

    /// Celebrates the first goal closed today that was not celebrated yet: a success haptic, the rings pulse
    /// and the ring glows, the check bounces. Once per day and per ring, the day stored on the device.
    private func celebrateClosedGoal() {
        guard animated, let day = model.goalDayKey else { return }
        var reached: [(ring: Int, name: String)] = []
        if activityGoalReached { reached.append((ring: 0, name: "activity")) }
        if effortGoalReached { reached.append((ring: 2, name: "effort")) }
        guard let goal = reached.first(where: {
            UserDefaults.standard.string(forKey: TodayHeroMotion.goalStoreKey($0.name)) != day
        }) else { return }
        UserDefaults.standard.set(day, forKey: TodayHeroMotion.goalStoreKey(goal.name))
        let still = motion.poseStill(reduceMotion)
        DispatchQueue.main.asyncAfter(deadline: .now() + (still ? 0 : TodayHeroMotion.goalDelay)) {
            StrandHaptic.success.play()
            celebrations += 1
            guard !still else { return }
            pulseRing = goal.ring
            withAnimation(.easeOut(duration: 0.28)) { goalPulse = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                withAnimation(.easeIn(duration: 0.28)) { goalPulse = 0 }
                // The glow is out: the ring drops its shadow (see `TodayConcentricRings.tracedArc`).
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { pulseRing = nil }
            }
        }
    }

    // MARK: Lines

    private func ringValue(_ ring: TodayHeroModel.Ring) -> String? {
        if let c = ring.calibration { return "\(c.done)/\(c.of)" }
        guard let score = ring.score else { return nil }
        return ring.decimals > 0
            ? String(format: "%.\(ring.decimals)f", locale: AppLanguage.activeLocale, score)
            : String(Int(score.rounded()))
    }

    private var caloriesValue: String? {
        model.calories.split.map { number($0.activityKcal) }
    }

    /// "/480 kcal" against the activity goal, or the unit alone without one.
    private var caloriesCaption: String {
        guard let goal = model.calories.goal, goal > 0 else { return "kcal" }
        return ["/" + number(goal), "kcal"].joined(separator: " ")
    }

    @ViewBuilder
    private func line(_ row: TodayRingRow, route: TabRoute?, guide: ScoreSection?) -> some View {
        Group {
            if let route {
                TabRouteLink(route: route) { row }
                    .buttonStyle(LiquidPressStyle())
            } else {
                row
            }
        }
        .contextMenu {
            if let guide {
                Button("How your scores work") { onGuide(guide) }
            }
        }
    }

    /// The text of a score while it moves, with the ring's decimals.
    private func scoreFormat(_ ring: TodayHeroModel.Ring) -> (Double) -> String {
        let decimals = ring.decimals
        return { value in
            decimals > 0
                ? String(format: "%.\(decimals)f", locale: AppLanguage.activeLocale, value)
                : String(Int(value.rounded()))
        }
    }

    private func ringLine(_ ring: TodayHeroModel.Ring, symbol: String, tint: Color, index: Int,
                          slamKey: String, done: Bool = false) -> some View {
        line(TodayRingRow(symbol: symbol, tint: tint, label: ring.label, value: ringValue(ring),
                          caption: ring.caption,
                          number: ring.calibration == nil ? ring.score : nil, format: scoreFormat(ring),
                          armed: animated, slamKey: slamKey,
                          slamDelay: Double(index) * NoopMotion.ringStagger,
                          done: done, celebrations: celebrations),
             route: ring.route, guide: ring.guide)
    }

    private var hairline: some View {
        Rectangle().fill(StrandPalette.hairline).frame(height: NoopMetrics.hairlineWidth)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space4) {
            HStack(alignment: .center, spacing: 14) {
                TodayConcentricRings(rings: rings, animated: animated, halo: chargeTint,
                                     pulse: goalPulse, pulseRing: pulseRing)
                VStack(alignment: .leading, spacing: 0) {
                    // Fork chantier 9: « Activity », the calories burnt in activity against the activity goal
                    // (the calories eaten live in Nutrition, in green).
                    line(TodayRingRow(symbol: "flame.fill", tint: StrandPalette.caloriesActivity,
                                      label: String(localized: "Activity"), value: caloriesValue,
                                      caption: caloriesCaption,
                                      number: model.calories.split?.activityKcal, format: number,
                                      armed: animated, slamKey: "today.slam.activity",
                                      done: activityGoalReached, celebrations: celebrations),
                         route: model.caloriesRoute, guide: nil)
                    hairline
                    ringLine(model.charge, symbol: "checkmark", tint: chargeTint, index: 1,
                             slamKey: "today.slam.charge")
                    hairline
                    ringLine(model.effort, symbol: "bolt.fill", tint: StrandPalette.effortColor, index: 2,
                             slamKey: "today.slam.effort", done: effortGoalReached)
                    hairline
                    ringLine(model.rest, symbol: "moon.fill", tint: StrandPalette.restRing, index: 3,
                             slamKey: "today.slam.rest")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            hairline
            HStack(alignment: .top, spacing: 12) {
                TodayCaloriesTile(split: model.calories.split, goal: model.calories.goal, animated: animated)
                TodayVitalTile(symbol: "heart.fill", tint: StrandPalette.liquidHeart,
                               title: String(localized: "Rest HR"), unit: "bpm", gauge: model.restingHR,
                               animated: animated, motionKey: "today.vital.rhr")
                TodayVitalTile(symbol: "waveform.path.ecg", tint: StrandPalette.metricCyan,
                               title: String(localized: "HRV"), unit: "ms", gauge: model.hrv,
                               animated: animated, motionKey: "today.vital.hrv")
            }
            if let nutrition = model.nutrition {
                TodayNutritionLine(model: nutrition)
                    .padding(.top, -NoopMetrics.space1)
            }
        }
        .padding(18)
        .background(NoopPanelSurface(cornerRadius: NoopMetrics.cardRadius, surfaceOpacity: surfaceOpacity))
        // The halo spreads past the rings: the card's own shape bounds it.
        .clipShape(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
        .onAppear { celebrateClosedGoal() }
        .onChangeCompat(of: animated) { _ in celebrateClosedGoal() }
        .onChangeCompat(of: activityGoalReached) { _ in celebrateClosedGoal() }
        .onChangeCompat(of: effortGoalReached) { _ in celebrateClosedGoal() }
    }
}
