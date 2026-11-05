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
}

/// The four concentric flat rings, outside to inside: a track at 18 %, a translucent target band, the fill
/// with round caps. Static (no animation loop): it redraws when its fractions change.
struct TodayConcentricRings: View {
    var rings: [TodayRing]
    var diameter: CGFloat = 184
    var lineWidth: CGFloat = 13
    var spacing: CGFloat = 4

    private func clamped(_ v: Double) -> CGFloat { CGFloat(min(1, max(0, v))) }

    var body: some View {
        ZStack {
            ForEach(rings.indices, id: \.self) { index in
                ringView(rings[index], size: diameter - lineWidth - 2 * CGFloat(index) * (lineWidth + spacing))
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }

    private func ringView(_ ring: TodayRing, size: CGFloat) -> some View {
        ZStack {
            Circle().stroke(ring.tint.opacity(0.18), lineWidth: lineWidth)
            if let band = ring.band, band.upperBound > band.lowerBound {
                Circle()
                    .trim(from: clamped(band.lowerBound), to: clamped(band.upperBound))
                    .stroke(ring.tint.opacity(0.35), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
            }
            if ring.fraction > 0.001 {
                Circle()
                    .trim(from: 0, to: clamped(ring.fraction))
                    .stroke(ring.tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            }
        }
        .rotationEffect(.degrees(-90))
        .frame(width: max(lineWidth, size), height: max(lineWidth, size))
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
            }
            .foregroundStyle(tint)
            if let value {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: value)
                        .font(StrandFont.rounded(21))
                        .foregroundStyle(StrandPalette.textPrimary)
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
                        Text(verbatim: value)
                            .font(StrandFont.rounded(22))
                            .foregroundStyle(StrandPalette.textPrimary)
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

    var body: some View {
        GeometryReader { geo in
            barBody(width: geo.size.width)
                .frame(height: geo.size.height)
        }
    }

    private func barBody(width: CGFloat) -> some View {
        let activity = CGFloat(arc?.activity ?? 0) * width
        let resting = CGFloat(arc?.resting ?? 0) * width
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

    var body: some View {
        GeometryReader { geo in
            barBody(width: geo.size.width)
                .frame(height: geo.size.height)
        }
    }

    private func barBody(width: CGFloat) -> some View {
        let bandFrom = gauge.flatMap { g in g.normal.map { CGFloat(g.fraction($0.lowerBound)) * width } }
        let bandTo = gauge.flatMap { g in g.normal.map { CGFloat(g.fraction($0.upperBound)) * width } }
        let dotX = gauge.map { CGFloat($0.fraction($0.value)) * width }
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

    private func number(_ v: Double) -> String {
        Int(v.rounded()).formatted(.number.locale(AppLanguage.activeLocale))
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
                      value: split.map { number($0.totalKcal) }, unit: "kcal", legend: legend) {
            TodayEnergyBar(arc: split.map { TodayEnergy.arc($0, goal: goal) })
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
                      value: gauge.map { whole($0.value) }, unit: unit, legend: legend) {
            TodayRangeBar(gauge: gauge, tint: tint)
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
}

/// The hero card: the four rings beside their four lines, a hairline, then the three cells.
struct TodayHeroCard: View {
    var model: TodayHeroModel
    var animated: Bool
    var surfaceOpacity: Double = 1
    var onGuide: (ScoreSection) -> Void

    private func number(_ v: Double) -> String {
        Int(v.rounded()).formatted(.number.locale(AppLanguage.activeLocale))
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

    private var rings: [TodayRing] {
        [TodayRing(fraction: caloriesFraction, tint: StrandPalette.caloriesActivity),
         TodayRing(fraction: fraction(model.charge), tint: chargeTint),
         TodayRing(fraction: fraction(model.effort), tint: StrandPalette.effortColor, band: effortBand),
         TodayRing(fraction: fraction(model.rest), tint: StrandPalette.restRing)]
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

    private func ringLine(_ ring: TodayHeroModel.Ring, symbol: String, tint: Color) -> some View {
        line(TodayRingRow(symbol: symbol, tint: tint, label: ring.label, value: ringValue(ring),
                          caption: ring.caption),
             route: ring.route, guide: ring.guide)
    }

    private var hairline: some View {
        Rectangle().fill(StrandPalette.hairline).frame(height: NoopMetrics.hairlineWidth)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space4) {
            HStack(alignment: .center, spacing: 14) {
                TodayConcentricRings(rings: rings)
                VStack(alignment: .leading, spacing: 0) {
                    // Fork chantier 9: « Activity », the calories burnt in activity against the activity goal
                    // (the calories eaten live in Nutrition, in green).
                    line(TodayRingRow(symbol: "flame.fill", tint: StrandPalette.caloriesActivity,
                                      label: String(localized: "Activity"), value: caloriesValue,
                                      caption: caloriesCaption),
                         route: model.caloriesRoute, guide: nil)
                    hairline
                    ringLine(model.charge, symbol: "checkmark", tint: chargeTint)
                    hairline
                    ringLine(model.effort, symbol: "bolt.fill", tint: StrandPalette.effortColor)
                    hairline
                    ringLine(model.rest, symbol: "moon.fill", tint: StrandPalette.restRing)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            hairline
            HStack(alignment: .top, spacing: 12) {
                TodayCaloriesTile(split: model.calories.split, goal: model.calories.goal)
                TodayVitalTile(symbol: "heart.fill", tint: StrandPalette.liquidHeart,
                               title: String(localized: "Rest HR"), unit: "bpm", gauge: model.restingHR)
                TodayVitalTile(symbol: "waveform.path.ecg", tint: StrandPalette.metricCyan,
                               title: String(localized: "HRV"), unit: "ms", gauge: model.hrv)
            }
            if let nutrition = model.nutrition {
                TodayNutritionLine(model: nutrition)
                    .padding(.top, -NoopMetrics.space1)
            }
        }
        .padding(18)
        .background(NoopPanelSurface(cornerRadius: NoopMetrics.cardRadius, surfaceOpacity: surfaceOpacity))
    }
}
