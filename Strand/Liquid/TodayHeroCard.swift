import SwiftUI
import StrandDesign

// MARK: - Today hero card (personal fork)
//
// The Charge / Effort / Rest rings with one short line inside each, and under them the three half-gauges:
// today's calories (activity and resting), last night's resting heart rate and HRV against the last 30
// nights and the wearer's normal band. Pure views: every number arrives in a model, so the render test
// draws the real card with the real tokens.

/// One of the three hero scores (Charge / Effort / Rest). The vessel fills from empty and the number counts
/// up when data lands; a short line under the number carries the calibration, the Effort target or the
/// night's sleep. The label under the ring taps through to the scoring guide.
struct HeroScoreCell: View {
    static let vesselDiameter: CGFloat = 96

    let label: String
    let score: Double?            // on whatever scale the caller passes (nil = no data yet)
    let tint: Color
    let animated: Bool
    let onGuide: () -> Void
    // The scale `score` is already expressed on — 100 for Charge/Rest, or the user's chosen Effort scale
    // max (100 or 21, #45) — so the vessel fill matches the displayed number.
    var maxValue: Double = 100
    // Decimal places for the displayed number (one on the WHOOP 0–21 Effort scale, #45).
    var decimals: Int = 0
    /// Where the GAUGE taps through to, or nil to keep the ring inert (#1995).
    var detailRoute: TabRoute? = nil
    /// The short line inside the ring, under the number. Nil draws nothing.
    var innerCaption: String? = nil
    /// The Effort optimal band, drawn as an arc around the vessel.
    var targetRange: ClosedRange<Double>? = nil
    /// Calibration progress (nights done, nights needed): a segmented ring, and "n/N" in place of the number.
    var calibration: (done: Int, of: Int)? = nil

    @ViewBuilder
    private var gaugeView: some View {
        let gauge = LiquidScoreGauge(
            score: score,
            tint: tint,
            diameter: Self.vesselDiameter,
            animated: animated,
            maxValue: maxValue,
            decimals: decimals,
            captionText: innerCaption,
            captionColor: StrandPalette.textSecondary,
            tapPassesThrough: detailRoute != nil,
            targetRange: targetRange,
            segments: calibration.map { (filled: $0.done, total: $0.of) },
            centerText: calibration.map { "\($0.done)/\($0.of)" },
            noDataText: String(localized: "no data"),
            captionSize: 10
        )
        if let detailRoute {
            NavigationLink(value: detailRoute) { gauge }
                .buttonStyle(LiquidPressStyle())
                .accessibilityLabel(Text("\(label), \(spokenScore)"))
                .accessibilityHint(Text("Opens the trend and readings"))
        } else {
            gauge
        }
    }

    /// The score as VoiceOver should say it, matching the label row's own phrasing.
    private var spokenScore: String {
        if let calibration { return "\(calibration.done)/\(calibration.of), \(innerCaption ?? "")" }
        guard let score else { return String(localized: "no data yet") }
        let number = decimals > 0
            ? String(format: "%.\(decimals)f", locale: AppLanguage.activeLocale, score)
            : String(Int(score.rounded()))
        return innerCaption.map { "\(number), \($0)" } ?? number
    }

    var body: some View {
        VStack(spacing: 8) {
            gaugeView
            Button(action: onGuide) {
                HStack(spacing: 3) {
                    // #74: one line, shrink-to-fit rather than wrap under large Dynamic Type.
                    Text(label.uppercased()).font(StrandFont.overline).tracking(1.6)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).opacity(0.6)
                }
                .foregroundStyle(StrandPalette.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("\(label), \(spokenScore). See how it is scored."))
        }
        .frame(maxWidth: .infinity)
    }
}

/// A 180° gauge: a track from left to right, coloured parts along it, an optional dot and goal mark, and the
/// value inside the arc. Drawn from fractions 0…1 so callers never deal with angles.
struct TodayHalfGauge: View {
    struct Part: Equatable {
        var from: Double
        var to: Double
        var color: Color
        /// A band (the normal zone) is wider and translucent; a fill part sits exactly on the track.
        var isBand: Bool = false
    }

    var parts: [Part]
    var dot: (at: Double, color: Color)? = nil
    var goalMark: Double? = nil
    var value: String?
    var unit: String

    static let width: CGFloat = 96
    static let height: CGFloat = 54
    private static let radius: CGFloat = 38
    private static let trackWidth: CGFloat = 7
    /// Width of the text inside the arc. Narrow enough that a four-digit calorie total stays clear of the
    /// arc at the height the number sits (the arc closes in towards the top).
    private static let textWidth: CGFloat = 46

    var body: some View {
        ZStack(alignment: .bottom) {
            Canvas { ctx, size in
                let center = CGPoint(x: size.width / 2, y: size.height - 6)
                let r = Self.radius
                func point(_ t: Double, _ radius: CGFloat) -> CGPoint {
                    let a = Double.pi * (1 + min(1, max(0, t)))
                    return CGPoint(x: center.x + radius * CGFloat(cos(a)), y: center.y + radius * CGFloat(sin(a)))
                }
                func arc(_ from: Double, _ to: Double) -> Path {
                    var p = Path()
                    let steps = max(2, Int((to - from) * 64))
                    for i in 0...steps {
                        let pt = point(from + (to - from) * Double(i) / Double(steps), r)
                        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                    }
                    return p
                }
                ctx.stroke(arc(0, 1), with: .color(StrandPalette.surfaceInset),
                           style: StrokeStyle(lineWidth: Self.trackWidth, lineCap: .round))
                for part in parts where part.to - part.from > 0.002 {
                    if part.isBand {
                        ctx.stroke(arc(part.from, part.to), with: .color(part.color.opacity(0.3)),
                                   style: StrokeStyle(lineWidth: Self.trackWidth + 4, lineCap: .round))
                    } else {
                        ctx.stroke(arc(part.from, part.to), with: .color(part.color),
                                   style: StrokeStyle(lineWidth: Self.trackWidth, lineCap: .butt))
                    }
                }
                if let goalMark {
                    var tick = Path()
                    tick.move(to: point(goalMark, r - Self.trackWidth))
                    tick.addLine(to: point(goalMark, r + Self.trackWidth))
                    ctx.stroke(tick, with: .color(StrandPalette.textPrimary.opacity(0.85)),
                               style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                }
                if let dot {
                    let c = point(dot.at, r)
                    let disc = Path(ellipseIn: CGRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10))
                    ctx.fill(disc, with: .color(dot.color))
                    ctx.stroke(disc, with: .color(StrandPalette.surfaceRaised), lineWidth: 2)
                }
            }
            VStack(spacing: 0) {
                if let value {
                    Text(verbatim: value)
                        .font(StrandFont.number(17))
                        .foregroundStyle(StrandPalette.textPrimary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(unit)
                        .font(StrandFont.overlineScaled(9.5))
                        .foregroundStyle(StrandPalette.textSecondary)
                } else {
                    Text("no data")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(width: Self.textWidth)
        }
        .frame(width: Self.width, height: Self.height)
    }
}

/// Today's calories under the rings: the total inside the arc, resting (copper) then activity (gold)
/// along it, full when the activity goal is met, and one named line per colour underneath.
struct TodayCaloriesTile: View {
    var split: TodayEnergy.Split?
    var goal: Double?

    private func number(_ v: Double) -> String {
        Int(v.rounded()).formatted(.number.locale(AppLanguage.activeLocale))
    }

    var body: some View {
        let arc = split.map { TodayEnergy.arc($0, goal: goal) }
        VStack(spacing: 5) {
            TodayTileLabel(symbol: "flame.fill", tint: StrandPalette.caloriesActivity,
                           title: String(localized: "Calories"))
            TodayHalfGauge(
                parts: Self.parts(arc),
                goalMark: arc?.goalMark,
                value: split.map { number($0.totalKcal) },
                unit: "kcal")
            if let split {
                VStack(alignment: .leading, spacing: 2) {
                    legendLine(StrandPalette.caloriesActivity, String(localized: "activity"),
                               goal.map { "\(number(split.activityKcal))/\(number($0))" }
                                ?? number(split.activityKcal))
                    // Imported activity alone (no strap heart rate that day) has no resting part to name.
                    if split.restingKcal > 0 {
                        legendLine(StrandPalette.caloriesResting, String(localized: "resting"),
                                   number(split.restingKcal))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// Resting from the left, then activity after it.
    private static func parts(_ arc: TodayEnergy.Arc?) -> [TodayHalfGauge.Part] {
        guard let arc else { return [] }
        return [
            TodayHalfGauge.Part(from: 0, to: arc.resting, color: StrandPalette.caloriesResting),
            TodayHalfGauge.Part(from: arc.resting, to: arc.resting + arc.activity,
                                color: StrandPalette.caloriesActivity),
        ]
    }

    private func legendLine(_ color: Color, _ label: String, _ value: String) -> some View {
        HStack(spacing: 5) {
            Capsule().fill(color).frame(width: 10, height: 4)
            (Text(label).foregroundColor(StrandPalette.textSecondary)
                + Text(verbatim: " " + value).foregroundColor(StrandPalette.textPrimary).fontWeight(.semibold))
                .font(StrandFont.overlineScaled(10))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

/// A nightly vital under the rings: last night's value inside the arc, its place between the lowest and
/// highest of the last 30 nights (labelled at the two ends) and the personal normal band.
struct TodayVitalTile: View {
    var symbol: String
    var tint: Color
    var title: String
    var unit: String
    var gauge: TodayVitalRange.Gauge?

    /// The normal band, when the baseline has one.
    private var bandParts: [TodayHalfGauge.Part] {
        guard let g = gauge, let band = g.normal else { return [] }
        return [TodayHalfGauge.Part(from: g.fraction(band.lowerBound), to: g.fraction(band.upperBound),
                                    color: tint, isBand: true)]
    }

    var body: some View {
        VStack(spacing: 5) {
            TodayTileLabel(symbol: symbol, tint: tint, title: title)
            TodayHalfGauge(
                parts: bandParts,
                dot: gauge.map { (at: $0.fraction($0.value), color: tint) },
                value: gauge.map { String(Int($0.value.rounded())) },
                unit: unit)
            if let gauge {
                HStack {
                    Text(verbatim: String(Int(gauge.low.rounded())))
                    Spacer(minLength: 0)
                    Text(verbatim: String(Int(gauge.high.rounded())))
                }
                .font(StrandFont.overlineScaled(10))
                .foregroundStyle(StrandPalette.textSecondary)
                .monospacedDigit()
                .frame(width: TodayHalfGauge.width - 4)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// The small icon + caps title above a half-gauge.
struct TodayTileLabel: View {
    var symbol: String
    var tint: Color
    var title: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(title.uppercased())
                .font(StrandFont.overlineScaled(10.5))
                .tracking(1.2)
                .foregroundStyle(StrandPalette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
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
    var sourceLabel: String?
}

/// The hero card: the three rings, a hairline, then the three half-gauges.
struct TodayHeroCard: View {
    var model: TodayHeroModel
    var animated: Bool
    var surfaceOpacity: Double = 1
    var onGuide: (ScoreSection) -> Void

    private func cell(_ ring: TodayHeroModel.Ring) -> HeroScoreCell {
        HeroScoreCell(label: ring.label, score: ring.score, tint: ring.tint, animated: animated,
                      onGuide: { onGuide(ring.guide) }, maxValue: ring.maxValue, decimals: ring.decimals,
                      detailRoute: ring.route, innerCaption: ring.caption, targetRange: ring.targetRange,
                      calibration: ring.calibration)
    }

    var body: some View {
        VStack(spacing: NoopMetrics.space4) {
            HStack(alignment: .top, spacing: NoopMetrics.space1) {
                cell(model.charge)
                cell(model.effort)
                cell(model.rest)
                    .overlay(alignment: .top) {
                        if let sourceLabel = model.sourceLabel {
                            SourceBadge("\(sourceLabel)", tint: StrandPalette.textSecondary)
                                .fixedSize()
                                .frame(width: HeroScoreCell.vesselDiameter, alignment: .trailing)
                                .offset(y: -(NoopMetrics.space4 + NoopMetrics.sourceBadgeHeight / 2))
                                .allowsHitTesting(false)
                                .accessibilityLabel(Text("Source: \(sourceLabel)"))
                        }
                    }
            }
            Rectangle()
                .fill(StrandPalette.hairline)
                .frame(height: NoopMetrics.hairlineWidth)
                .padding(.horizontal, NoopMetrics.space2)
            HStack(alignment: .top, spacing: NoopMetrics.space1) {
                TodayCaloriesTile(split: model.calories.split, goal: model.calories.goal)
                TodayVitalTile(symbol: "heart.fill", tint: StrandPalette.liquidHeart,
                               title: String(localized: "Rest HR"), unit: "bpm", gauge: model.restingHR)
                TodayVitalTile(symbol: "waveform.path.ecg", tint: StrandPalette.accent,
                               title: String(localized: "HRV"), unit: "ms", gauge: model.hrv)
            }
        }
        .padding(.vertical, NoopMetrics.space4)
        .padding(.horizontal, NoopMetrics.space3)
        .background(NoopPanelSurface(cornerRadius: 26, elevated: true, surfaceOpacity: surfaceOpacity))
    }
}
