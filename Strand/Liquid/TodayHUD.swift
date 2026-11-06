import SwiftUI
import StrandDesign

// MARK: - Today HUD (personal fork, chantier 13)
//
// The optional "holographic HUD" drawing of Today's top: a graduated reticle holding the four existing rings
// (01 activity, 02 Charge, 03 Effort, 04 Rest, outside to inside) with the Charge in the middle, a 2 × 2 grid
// of numbered cells that name each ring's value and unit, then the night's three vitals in small panels.
// It reads the same `TodayHeroModel` as the rings card, through the same resolvers (`activityFraction`,
// `fraction(of:)`, `valueText(of:)`…), so switching the style never changes a number. Switched on in
// Settings → Appearance (`TodayHUDPrefs.enabledKey`, on the device only, off by default); off, Today is the
// screen it was. Pure views: every value arrives in the model, so the render test draws the real panels.

/// The device-only switch between the current Today and the HUD (outside `.noopbak`).
enum TodayHUDPrefs {
    static let enabledKey = "today.hudStyle"
}

private struct TodayHUDStyleKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True while Today is drawn in the HUD style: the cards below the hero take the HUD panel and the heart
    /// rate chart its bpm scale.
    var todayHUDStyle: Bool {
        get { self[TodayHUDStyleKey.self] }
        set { self[TodayHUDStyleKey.self] = newValue }
    }
}

/// One numbered ring of the HUD with its cell.
struct TodayHUDDial: Identifiable {
    var id: Int
    var label: String
    var tint: Color
    var fraction: Double
    var band: ClosedRange<Double>? = nil
    /// Nil draws "no data".
    var value: String?
    var unit: String
    var note: String?
    var route: TabRoute?
    var guide: ScoreSection?
    var done: Bool = false

    /// "01" … "04", outside to inside.
    var index: String { String(format: "%02d", id + 1) }

    /// "01 · Activity", the cell's label.
    var heading: String { [index, label].joined(separator: TodayHUDDial.separator) }

    static let separator = " \u{00B7} "

}

/// The reticle's middle: the Charge, its unit and its note.
struct TodayHUDCenter {
    var value: String
    var unit: String
    var note: String?
    var muted: Bool
}

/// The reticle's measures, shared by the drawing and its labels.
enum TodayHUDMetrics {
    static let size = CGSize(width: 268, height: 264)
    static let radii: [CGFloat] = [98, 82, 66, 50]
    static let ringWidth: CGFloat = 9
    static let glowWidth: CGFloat = 17
    static let tickInner: CGFloat = 112
    static let tickOuter: CGFloat = 116
    static let tickMajor: CGFloat = 121
    static let dashedRadius: CGFloat = 126
    static let segments = 20
    /// The graduations turn into place by this much while the screen boots.
    static let bootTurn: Double = -24
    /// The middle and the cells follow the rings by this much.
    static let centerDelay: Double = 0.35
    static let cellDelay: Double = 0.3
    static let cellStep: Double = 0.05
}

/// The graduated reticle with the four rings, drawn whole or booting in once per showing of the screen.
struct TodayHUDReticle: View {
    var dials: [TodayHUDDial]
    var center: TodayHUDCenter
    var coreTint: Color
    var phase: NoopDrawPhase
    /// A goal just closed: the ring it lights (`litRing`) brightens its drawn glow by `lit` (0…1).
    var litRing: Int? = nil
    var lit: Double = 0

    @Environment(\.colorScheme) private var scheme

    private var mid: CGPoint { CGPoint(x: TodayHUDMetrics.size.width / 2, y: TodayHUDMetrics.size.height / 2) }

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [coreTint.opacity(NoopHUDStyle.glowOpacity(scheme)), coreTint.opacity(0)],
                                     center: .center, startRadius: 0, endRadius: 48))
                .frame(width: 96, height: 96)
            graduations
                .rotationEffect(.degrees(phase.drawn ? 0 : TodayHUDMetrics.bootTurn))
                .opacity(phase.drawn ? 1 : 0)
                .animation(phase.motion(NoopMotion.ringDraw), value: phase.drawn)
            ForEach(dials) { dial in
                ring(dial)
            }
            ForEach(dials) { dial in
                Text(verbatim: dial.index)
                    .font(StrandFont.hudLabel)
                    .foregroundStyle(dial.tint)
                    .frame(width: 24, alignment: .trailing)
                    .position(x: mid.x - 18, y: mid.y - radius(dial))
            }
            centerReadout
                .opacity(phase.drawn ? 1 : 0)
                .offset(y: phase.drawn ? 0 : 6)
                .animation(phase.motion(NoopMotion.ringDraw.delay(TodayHUDMetrics.centerDelay)), value: phase.drawn)
        }
        .frame(width: TodayHUDMetrics.size.width, height: TodayHUDMetrics.size.height)
        .accessibilityHidden(true)
    }

    private func radius(_ dial: TodayHUDDial) -> CGFloat {
        TodayHUDMetrics.radii[min(dial.id, TodayHUDMetrics.radii.count - 1)]
    }

    /// 72 graduations every 5°, a longer one every 30°, a dotted circle outside them and four cross marks.
    private var graduations: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            var minor = Path()
            var major = Path()
            for i in 0..<72 {
                let a = (Double(i) * 5 - 90) * .pi / 180
                let isMajor = i % 6 == 0
                let r2 = isMajor ? TodayHUDMetrics.tickMajor : TodayHUDMetrics.tickOuter
                let from = CGPoint(x: c.x + TodayHUDMetrics.tickInner * cos(a), y: c.y + TodayHUDMetrics.tickInner * sin(a))
                let to = CGPoint(x: c.x + r2 * cos(a), y: c.y + r2 * sin(a))
                if isMajor {
                    major.move(to: from)
                    major.addLine(to: to)
                } else {
                    minor.move(to: from)
                    minor.addLine(to: to)
                }
            }
            ctx.stroke(minor, with: .color(NoopHUDStyle.chrome.opacity(0.45)), lineWidth: 1)
            ctx.stroke(major, with: .color(NoopHUDStyle.chrome.opacity(0.9)), lineWidth: 1.4)
            let r = TodayHUDMetrics.dashedRadius
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                       with: .color(NoopHUDStyle.chrome.opacity(0.2)),
                       style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
            var cross = Path()
            cross.move(to: CGPoint(x: c.x, y: c.y - 132))
            cross.addLine(to: CGPoint(x: c.x, y: c.y - 124))
            cross.move(to: CGPoint(x: c.x, y: c.y + 124))
            cross.addLine(to: CGPoint(x: c.x, y: c.y + 132))
            cross.move(to: CGPoint(x: c.x - 134, y: c.y))
            cross.addLine(to: CGPoint(x: c.x - 126, y: c.y))
            cross.move(to: CGPoint(x: c.x + 126, y: c.y))
            cross.addLine(to: CGPoint(x: c.x + 134, y: c.y))
            ctx.stroke(cross, with: .color(NoopHUDStyle.chrome), lineWidth: 1.4)
        }
        .frame(width: TodayHUDMetrics.size.width, height: TodayHUDMetrics.size.height)
    }

    /// One ring: its track, then (once drawn) a wide translucent copy for the glow, the fill and a fine light
    /// line on top. The rings sweep in from the outside one after the other, then follow any change of value.
    private func ring(_ dial: TodayHUDDial) -> some View {
        let r = radius(dial)
        let fill = min(1, max(0, dial.fraction))
        let shown = phase.drawn ? fill : 0
        let round = StrokeStyle(lineWidth: TodayHUDMetrics.ringWidth, lineCap: .round)
        return ZStack {
            Circle().stroke(dial.tint.opacity(0.14), lineWidth: TodayHUDMetrics.ringWidth)
            if let band = dial.band, band.upperBound > band.lowerBound {
                bandEdge(at: band.lowerBound)
                bandEdge(at: band.upperBound)
            }
            Group {
                Circle().trim(from: 0, to: CGFloat(shown))
                    .stroke(dial.tint.opacity(NoopHUDStyle.glowOpacity(scheme) + (litRing == dial.id ? 0.6 * lit : 0)),
                            style: StrokeStyle(lineWidth: TodayHUDMetrics.glowWidth, lineCap: .round))
                Circle().trim(from: 0, to: CGFloat(shown)).stroke(dial.tint, style: round)
                Circle().trim(from: 0, to: CGFloat(shown))
                    .stroke(NoopHUDStyle.sheen.opacity(0.55), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
            }
            .opacity(fill > 0 ? 1 : 0)
            .animation(phase.motion(NoopMotion.ringDraw.delay(Double(dial.id) * NoopMotion.ringStagger)),
                       value: phase.drawn)
            .animation(phase.motion(NoopMotion.valueChange), value: fill)
        }
        .rotationEffect(.degrees(-90))
        .frame(width: 2 * r, height: 2 * r)
    }

    /// A short light mark across the ring where its target band starts or ends.
    private func bandEdge(at share: Double) -> some View {
        let s = CGFloat(min(1, max(0, share)))
        return Circle()
            .trim(from: max(0, s - 0.004), to: min(1, s + 0.004))
            .stroke(NoopHUDStyle.text.opacity(0.7), lineWidth: TodayHUDMetrics.ringWidth + 4)
    }

    private var centerReadout: some View {
        VStack(spacing: 2) {
            Text("Charge")
                .font(StrandFont.hudLabel)
                .noopHUDLabel()
                .foregroundStyle(NoopHUDStyle.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(verbatim: center.value)
                    .font(StrandFont.hudCenter)
                    .foregroundStyle(center.muted ? NoopHUDStyle.textSecondary : NoopHUDStyle.text)
                if !center.unit.isEmpty {
                    Text(verbatim: center.unit)
                        .font(StrandFont.hudCaption)
                        .foregroundStyle(NoopHUDStyle.textSecondary)
                }
            }
            if let note = center.note {
                Text(verbatim: note)
                    .font(StrandFont.hudLabel)
                    .noopHUDLabel()
                    .foregroundStyle(NoopHUDStyle.textSecondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .frame(width: 86)
    }
}

/// A bar of 20 segments, the lit share in the dial's colour.
struct TodayHUDSegments: View {
    var fraction: Double
    var tint: Color

    var body: some View {
        let lit = Int((min(1, max(0, fraction)) * Double(TodayHUDMetrics.segments)).rounded())
        HStack(spacing: 2) {
            ForEach(0..<TodayHUDMetrics.segments, id: \.self) { i in
                Rectangle()
                    .fill(i < lit ? tint : NoopHUDStyle.segmentOff)
                    .frame(height: 3)
            }
        }
        .accessibilityHidden(true)
    }
}

/// A night vital's bar on the HUD: the personal normal band and a tick where the value sits; the tick turns
/// to the warning colour outside the band (the rule of `TodayRangeBar`).
struct TodayHUDRangeBar: View {
    var gauge: TodayVitalRange.Gauge?
    var tint: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Rectangle().fill(NoopHUDStyle.track).frame(height: 2)
                if let g = gauge, let band = g.normal {
                    let from = CGFloat(g.fraction(band.lowerBound)) * w
                    let to = CGFloat(g.fraction(band.upperBound)) * w
                    Rectangle().fill(tint.opacity(0.35)).frame(width: max(4, to - from), height: 6).offset(x: from)
                }
                if let g = gauge {
                    Rectangle()
                        .fill(g.isOutsideNormal ? StrandPalette.statusWarning : NoopHUDStyle.text)
                        .frame(width: 2, height: 10)
                        .offset(x: min(max(0, CGFloat(g.fraction(g.value)) * w - 1), max(0, w - 2)))
                }
            }
            .frame(height: 10)
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}

/// The spent-energy bar on the HUD: activity then resting, on the HUD track.
struct TodayHUDEnergyBar: View {
    var arc: TodayEnergy.Arc?

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let activity = CGFloat(arc?.activity ?? 0) * w
            let resting = CGFloat(arc?.resting ?? 0) * w
            ZStack(alignment: .leading) {
                Rectangle().fill(NoopHUDStyle.track).frame(height: 2)
                HStack(spacing: 2) {
                    Rectangle().fill(StrandPalette.caloriesActivity).frame(width: activity, height: 6)
                    Rectangle().fill(StrandPalette.caloriesResting).frame(width: max(0, resting - 2), height: 6)
                }
            }
            .frame(height: 10)
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}

/// The HUD hero: the reticle and its four cells in one panel, then the night's three vitals.
struct TodayHUDHero: View {
    var model: TodayHeroModel
    var animated: Bool
    var onGuide: (ScoreSection) -> Void

    /// A goal just closed (the rule of `TodayHeroCard`, the same stored day): the ring lit, its light, and the
    /// bounces of the check.
    @State private var litRing: Int?
    @State private var lit: Double = 0
    @State private var celebrations = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var motion = NoopMotionState.shared

    private func number(_ v: Double) -> String { TodayHeroModel.wholeNumber(v) }

    /// Celebrates the first goal closed today that was not celebrated yet, on either drawing of the hero: a
    /// success haptic, the check bounces, the ring's glow brightens for a moment. Once per day and per ring,
    /// under the keys `TodayHeroCard` uses, so switching the style never celebrates twice.
    private func celebrateClosedGoal() {
        guard animated, let day = model.goalDayKey else { return }
        var reached: [(ring: Int, name: String)] = []
        if model.activityGoalReached { reached.append((ring: 0, name: "activity")) }
        if model.effortGoalReached { reached.append((ring: 2, name: "effort")) }
        guard let goal = reached.first(where: {
            UserDefaults.standard.string(forKey: TodayHeroMotion.goalStoreKey($0.name)) != day
        }) else { return }
        UserDefaults.standard.set(day, forKey: TodayHeroMotion.goalStoreKey(goal.name))
        let still = motion.poseStill(reduceMotion)
        DispatchQueue.main.asyncAfter(deadline: .now() + (still ? 0 : TodayHeroMotion.goalDelay)) {
            StrandHaptic.success.play()
            celebrations += 1
            guard !still else { return }
            litRing = goal.ring
            withAnimation(.easeOut(duration: 0.28)) { lit = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                withAnimation(.easeIn(duration: 0.45)) { lit = 0 }
            }
        }
    }

    // MARK: Dials

    private var hasAnyValue: Bool {
        model.calories.split != nil || model.charge.score != nil || model.charge.calibration != nil
            || model.effort.score != nil || model.rest.score != nil
    }

    var dials: [TodayHUDDial] {
        let goal = model.calories.goal ?? 0
        let activityUnit = goal > 0 ? "/ " + number(goal) + " kcal" : "kcal"
        let charge = model.charge
        let chargeValue: String?
        let chargeUnit: String
        if let c = charge.calibration {
            chargeValue = "\(c.done) / \(c.of)"
            chargeUnit = String(localized: "nights")
        } else {
            chargeValue = TodayHeroModel.valueText(of: charge)
            chargeUnit = "%"
        }
        let effortScale = "/ " + String(Int(model.effort.maxValue.rounded()))
        return [
            TodayHUDDial(id: 0, label: String(localized: "Activity"), tint: StrandPalette.caloriesActivity,
                         fraction: model.activityFraction, value: model.activityValueText, unit: activityUnit,
                         note: nil, route: model.caloriesRoute, guide: nil, done: model.activityGoalReached),
            TodayHUDDial(id: 1, label: charge.label, tint: model.chargeRingTint,
                         fraction: TodayHeroModel.fraction(of: charge), value: chargeValue, unit: chargeUnit,
                         note: charge.caption, route: charge.route, guide: charge.guide),
            TodayHUDDial(id: 2, label: model.effort.label, tint: StrandPalette.effortColor,
                         fraction: TodayHeroModel.fraction(of: model.effort), band: model.effortBandFraction,
                         value: TodayHeroModel.valueText(of: model.effort), unit: effortScale,
                         note: model.effort.caption, route: model.effort.route, guide: model.effort.guide,
                         done: model.effortGoalReached),
            TodayHUDDial(id: 3, label: model.rest.label, tint: StrandPalette.restRing,
                         fraction: TodayHeroModel.fraction(of: model.rest),
                         value: TodayHeroModel.valueText(of: model.rest), unit: "%",
                         note: model.rest.caption.map { String(localized: "night \($0)") },
                         route: model.rest.route, guide: model.rest.guide)
        ]
    }

    private var center: TodayHUDCenter {
        let charge = model.charge
        if let c = charge.calibration {
            return TodayHUDCenter(value: "\(c.done)/\(c.of)", unit: "", note: String(localized: "calibration"),
                                  muted: false)
        }
        guard let value = TodayHeroModel.valueText(of: charge) else {
            return TodayHUDCenter(value: "\u{2013}", unit: "", note: String(localized: "no data"), muted: true)
        }
        return TodayHUDCenter(value: value, unit: "%", note: charge.caption, muted: false)
    }

    // MARK: Body

    var body: some View {
        NoopFirstDraw(key: "today.hud", armed: animated) { phase in
            VStack(spacing: 12) {
                panel(phase)
                vitals(phase)
            }
        }
        .onAppear { celebrateClosedGoal() }
        .onChangeCompat(of: animated) { _ in celebrateClosedGoal() }
        .onChangeCompat(of: model.activityGoalReached) { _ in celebrateClosedGoal() }
        .onChangeCompat(of: model.effortGoalReached) { _ in celebrateClosedGoal() }
    }

    private func panel(_ phase: NoopDrawPhase) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Today's status")
                .font(StrandFont.hudLabel)
                .noopHUDLabel()
                .foregroundStyle(NoopHUDStyle.textSecondary)
            TodayHUDReticle(dials: dials, center: center,
                            coreTint: hasAnyValue ? model.chargeRingTint : NoopHUDStyle.textSecondary,
                            phase: phase, litRing: litRing, lit: lit)
                .frame(maxWidth: .infinity)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(dials) { dial in
                    hudCell(dial)
                        .rise(phase, delay: TodayHUDMetrics.cellDelay + Double(dial.id) * TodayHUDMetrics.cellStep)
                }
            }
            if let nutrition = model.nutrition {
                TodayNutritionLine(model: nutrition)
            }
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 14, trailing: 14))
        .noopHUDPanel()
        .rise(phase, delay: 0)
    }

    @ViewBuilder
    private func hudCell(_ dial: TodayHUDDial) -> some View {
        let content = cellBody(dial)
        Group {
            if let route = dial.route {
                TabRouteLink(route: route) { content }
                    .buttonStyle(LiquidPressStyle())
            } else {
                content
            }
        }
        .contextMenu {
            if let guide = dial.guide {
                Button("How your scores work") { onGuide(guide) }
            }
        }
    }

    private func cellBody(_ dial: TodayHUDDial) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(verbatim: dial.heading)
                    .font(StrandFont.hudLabel)
                    .noopHUDLabel()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if dial.done {
                    Image(systemName: "checkmark.circle.fill")
                        .font(StrandFont.hudLabel)
                        .noopSymbolBounce(celebrations)
                        .accessibilityLabel(Text("Goal reached"))
                }
            }
            .foregroundStyle(dial.tint)
            if let value = dial.value {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: value)
                        .font(StrandFont.hudValue)
                        .foregroundStyle(NoopHUDStyle.text)
                    Text(verbatim: dial.unit)
                        .font(StrandFont.hudCaption)
                        .foregroundStyle(NoopHUDStyle.textSecondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            } else {
                Text("no data")
                    .font(StrandFont.subhead)
                    .foregroundStyle(NoopHUDStyle.textSecondary)
                    .lineLimit(1)
            }
            TodayHUDSegments(fraction: dial.value == nil ? 0 : dial.fraction, tint: dial.tint)
                .padding(.top, 2)
            Text(verbatim: dial.note ?? " ")
                .font(StrandFont.hudLabel)
                .foregroundStyle(NoopHUDStyle.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
        .background(NoopChamferShape(cut: NoopHUDStyle.cutSmall).fill(NoopHUDStyle.wash))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    // MARK: Vitals

    /// "activity 185 · resting 760", the words from the catalogue (the legend of `TodayCaloriesTile`).
    private var energyLegend: Text? {
        guard let split = model.calories.split else { return nil }
        let activityPart = Text("activity") + Text(verbatim: " " + number(split.activityKcal))
        guard split.restingKcal > 0 else { return activityPart }
        return activityPart + Text(verbatim: TodayHUDDial.separator) + Text("resting")
            + Text(verbatim: " " + number(split.restingKcal))
    }

    private func normalLegend(_ gauge: TodayVitalRange.Gauge?) -> Text? {
        guard let gauge else { return nil }
        let whole = { (v: Double) in String(Int(v.rounded())) }
        if let band = gauge.normal {
            let range = whole(band.lowerBound) + "\u{2013}" + whole(band.upperBound)
            return Text("your normal \(range)")
        }
        return Text(verbatim: whole(gauge.low) + "\u{2013}" + whole(gauge.high))
    }

    private func vitals(_ phase: NoopDrawPhase) -> some View {
        HStack(alignment: .top, spacing: 8) {
            vitalPanel(title: String(localized: "Spent"), tint: StrandPalette.caloriesResting,
                       value: model.calories.split.map { number($0.totalKcal) }, unit: "kcal",
                       legend: energyLegend, note: model.calories.split == nil ? nil : String(localized: "estimate")) {
                TodayHUDEnergyBar(arc: model.calories.split.map { TodayEnergy.arc($0, goal: model.calories.goal) })
            }
            .rise(phase, delay: TodayHUDMetrics.cellDelay + 0.1)
            vitalPanel(title: String(localized: "Rest HR"), tint: NoopHUDStyle.heartLabel,
                       value: model.restingHR.map { String(Int($0.value.rounded())) }, unit: "bpm",
                       legend: normalLegend(model.restingHR),
                       note: model.restingHR == nil ? nil : String(localized: "measured · night")) {
                TodayHUDRangeBar(gauge: model.restingHR, tint: StrandPalette.liquidHeart)
            }
            .rise(phase, delay: TodayHUDMetrics.cellDelay + 0.15)
            vitalPanel(title: String(localized: "HRV"), tint: StrandPalette.metricCyan,
                       value: model.hrv.map { String(Int($0.value.rounded())) }, unit: "ms",
                       legend: normalLegend(model.hrv),
                       note: model.hrv == nil ? nil : String(localized: "measured · night")) {
                TodayHUDRangeBar(gauge: model.hrv, tint: StrandPalette.metricCyan)
            }
            .rise(phase, delay: TodayHUDMetrics.cellDelay + 0.2)
        }
    }

    private func vitalPanel<Bar: View>(title: String, tint: Color, value: String?, unit: String, legend: Text?,
                                       note: String?, @ViewBuilder bar: () -> Bar) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: title)
                .font(StrandFont.hudLabel)
                .noopHUDLabel()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let value {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(verbatim: value)
                        .font(StrandFont.hudValueSmall)
                        .foregroundStyle(NoopHUDStyle.text)
                    Text(verbatim: unit)
                        .font(StrandFont.hudLabel)
                        .foregroundStyle(NoopHUDStyle.textSecondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            } else {
                Text("no data")
                    .font(StrandFont.caption)
                    .foregroundStyle(NoopHUDStyle.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            bar()
                .padding(.vertical, 2)
            (legend ?? Text(verbatim: " "))
                .font(StrandFont.caption2)
                .foregroundStyle(NoopHUDStyle.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(verbatim: note ?? " ")
                .font(StrandFont.hudLabel)
                .foregroundStyle(NoopHUDStyle.chrome)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(9)
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
        .background {
            ZStack {
                NoopChamferShape(cut: NoopHUDStyle.cutSmall).fill(NoopHUDStyle.panelFlat)
                NoopChamferShape(cut: NoopHUDStyle.cutSmall).strokeBorder(NoopHUDStyle.frameSoft, lineWidth: 1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The line under Today's title in the HUD: whether the strap history is syncing, or when it last synced
/// (the same facts as the Data Sources card's « Strap history » row, from `LiveState`).
struct TodayHUDStatusLine: View {
    @EnvironmentObject private var live: LiveState

    var body: some View {
        TodayHUDStatusText(syncing: live.backfilling, lastSyncedAt: live.lastSyncedAt)
    }
}

/// `TodayHUDStatusLine`'s drawing, pure so the render test draws it.
struct TodayHUDStatusText: View {
    var syncing: Bool
    var lastSyncedAt: TimeInterval?

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(NoopHUDStyle.chrome)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Group {
                if syncing {
                    Text("Syncing…")
                } else if let ts = lastSyncedAt {
                    Text("Synced \(relativeAgo(ts))")
                } else {
                    Text("Not synced yet")
                }
            }
            .font(StrandFont.hudLabel)
            .noopHUDLabel()
        }
        .foregroundStyle(NoopHUDStyle.chrome)
        .accessibilityElement(children: .combine)
    }
}

/// The surface of a Today card below the hero: the usual card, or the HUD panel edged in `accent`.
struct TodayHUDCardSurface: ViewModifier {
    var hud: Bool
    var accent: Color

    @ViewBuilder
    func body(content: Content) -> some View {
        if hud {
            content.noopHUDPanel(edge: accent.opacity(0.45), accent: accent)
        } else {
            content.background(NoopPanelSurface(cornerRadius: NoopMetrics.cardRadius))
        }
    }
}

/// The surface of a small Today tile: the usual card, or a small HUD panel with its quiet edge.
struct TodayHUDTileSurface: ViewModifier {
    var hud: Bool
    var surfaceOpacity: Double = 1

    @ViewBuilder
    func body(content: Content) -> some View {
        if hud {
            content.background {
                ZStack {
                    NoopChamferShape(cut: NoopHUDStyle.cutSmall).fill(NoopHUDStyle.panelFlat)
                    NoopChamferShape(cut: NoopHUDStyle.cutSmall).strokeBorder(NoopHUDStyle.frameSoft, lineWidth: 1)
                }
            }
        } else {
            content.background(NoopPanelSurface(cornerRadius: NoopMetrics.cardRadius, surfaceOpacity: surfaceOpacity))
        }
    }
}

/// The section order as the HUD reads it: the Synthesis (the day explained) moves just above the heart rate
/// when the stored order puts it below. The stored order is never rewritten, so switching the HUD off gives
/// back the order the wearer had (choice of 6 Nov., fork chantier 13).
enum TodayHUDOrder {
    static func hudSectionOrder(_ order: [TodaySection]) -> [TodaySection] {
        guard let synthesis = order.firstIndex(of: .synthesis),
              let heart = order.firstIndex(of: .heartRate),
              heart < synthesis else { return order }
        var out = order
        out.remove(at: synthesis)
        out.insert(.synthesis, at: heart)
        return out
    }
}

private extension View {
    /// Rises 8 pt into place while the screen boots, `delay` after the rings start.
    func rise(_ phase: NoopDrawPhase, delay: Double) -> some View {
        opacity(phase.drawn ? 1 : 0)
            .offset(y: phase.drawn ? 0 : 8)
            .animation(phase.motion(NoopMotion.ringDraw.delay(delay)), value: phase.drawn)
    }
}
