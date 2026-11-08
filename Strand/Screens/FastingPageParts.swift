import SwiftUI
import StrandDesign
import StrandAnalytics

// MARK: - Pieces of the Jeûne page (personal fork, chantier 15)
//
// The goal picker (quick picks and a wheel to the hour), the phases list, the water bottle card, the
// history card and the sheets (start time, planned end, real end, one phase). Every figure arrives from
// `FastingState`, `FastingTimeline` and the hydration store; nothing here computes one of its own.

// MARK: Buttons

/// A full-width action of the page: white for the main one, inset for the others, soft red to stop,
/// green to end a fast at a meal (chantier 15 PR C).
struct FastingActionButton: View {
    enum Look { case primary, secondary, stop, done }
    let title: Text
    var look: Look = .secondary
    let action: () -> Void

    private var fill: Color {
        switch look {
        case .primary: return StrandPalette.textPrimary
        case .secondary, .stop: return StrandPalette.surfaceInset
        case .done: return StrandPalette.fastingDone
        }
    }

    private var foreground: Color {
        switch look {
        case .primary, .done: return StrandPalette.surfaceBase
        case .secondary: return StrandPalette.textPrimary
        case .stop: return StrandPalette.fastingRemaining
        }
    }

    var body: some View {
        Button(action: action) {
            title
                .font(StrandFont.body.weight(look == .primary || look == .done ? .bold : .semibold))
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(LiquidPressStyle())
    }
}

// MARK: Goal picker

/// The duration aimed at: the quick picks (14 · 16 · 18 · 20 h) and a row « Other duration » stepping by
/// the hour inside the bounds. Bound to minutes, like the store.
struct FastingGoalPicker: View {
    @Binding var goalMinutes: Int

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(FastingTimeline.quickGoalHours, id: \.self) { h in
                    let picked = h * 60 == goalMinutes
                    Button {
                        withAnimation(NoopMotion.value) { goalMinutes = h * 60 }
                    } label: {
                        Text(verbatim: FastingFormat.duration(minutes: h * 60))
                            .font(StrandFont.body.weight(.bold))
                            .foregroundStyle(picked ? StrandPalette.surfaceBase : StrandPalette.textPrimary)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(picked ? StrandPalette.fastingDone : StrandPalette.surfaceInset,
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(LiquidPressStyle())
                    .accessibilityAddTraits(picked ? .isSelected : [])
                }
            }
            HStack(spacing: 4) {
                stepButton("minus", enabled: goalMinutes > FastingTimeline.minGoalMinutes,
                           label: Text("One hour less")) {
                    goalMinutes = FastingTimeline.clampGoalMinutes(goalMinutes - 60)
                }
                Spacer(minLength: 4)
                (Text("Other duration:").foregroundColor(StrandPalette.textSecondary)
                 + Text(verbatim: " ")
                 + Text(verbatim: FastingFormat.duration(minutes: goalMinutes)).bold()
                 + Text(verbatim: " ")
                 + Text("(12 to 36 h)").foregroundColor(StrandPalette.textTertiary))
                    .font(StrandFont.subhead)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                stepButton("plus", enabled: goalMinutes < FastingTimeline.maxGoalMinutes,
                           label: Text("One hour more")) {
                    goalMinutes = FastingTimeline.clampGoalMinutes(goalMinutes + 60)
                }
            }
            .padding(.horizontal, 6)
            .frame(minHeight: 44)
            .background(StrandPalette.surfaceInset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityElement(children: .contain)
        }
    }

    private func stepButton(_ symbol: String, enabled: Bool, label: Text, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(NoopMotion.value) { action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(enabled ? StrandPalette.textPrimary : StrandPalette.textTertiary)
                .frame(width: 44, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

// MARK: Phases card

/// « The phases of the fast »: the six, with done · current · « in 18 min » against the running fast.
struct FastingPhasesCard: View {
    let state: FastingState?
    let onPick: (Int) -> Void

    private enum Standing { case passed, current, future }

    private func standing(_ index: Int) -> Standing {
        guard let state else { return .future }
        if index < state.phaseIndex { return .passed }
        if index == state.phaseIndex { return .current }
        return .future
    }

    private func stateText(_ index: Int) -> String {
        switch standing(index) {
        case .passed: return String(localized: "done")
        case .current: return String(localized: "current")
        case .future:
            guard let state, state.isRunning else { return String(localized: "to come") }
            let inMinutes = FastingTimeline.phaseStartHours[index] * 60 - state.elapsedMinutes
            return String(localized: "in \(FastingFormat.duration(minutes: inMinutes))")
        }
    }

    private func stateColor(_ index: Int) -> Color {
        switch standing(index) {
        case .passed: return StrandPalette.fastingDone
        case .current: return StrandPalette.textPrimary
        case .future: return StrandPalette.fastingRemaining
        }
    }

    var body: some View {
        NoopCard(padding: 16) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("The phases of the fast")
                        .font(StrandFont.headline)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Spacer()
                    Text("tap a phase")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
                .padding(.bottom, 6)
                ForEach(0..<FastingPhaseText.count, id: \.self) { index in
                    row(index)
                }
                Text(FastingPhaseText.caution)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
        }
    }

    private func row(_ index: Int) -> some View {
        let place = standing(index)
        let tint = FastingPhaseText.tint(index)
        return Button { onPick(index) } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(place == .current ? tint
                                  : place == .passed ? StrandPalette.fastingDone.opacity(0.18)
                                  : StrandPalette.fastingRemaining.opacity(0.16))
                    Image(systemName: FastingPhaseText.symbol(index))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(place == .current ? StrandPalette.surfaceBase
                                         : place == .passed ? StrandPalette.fastingDone : StrandPalette.fastingRemaining)
                }
                .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: FastingPhaseText.name(index))
                        .font(StrandFont.body.weight(.semibold))
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text(verbatim: "\(FastingPhaseText.range(index)) · \(FastingPhaseText.short(index))")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                Text(verbatim: stateText(index))
                    .font(StrandFont.caption.weight(.bold))
                    .foregroundStyle(stateColor(index))
                    .monospacedDigit()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, place == .current ? 8 : 0)
            .frame(minHeight: 52)
            .background(place == .current ? StrandPalette.surfaceInset : Color.clear,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, place == .current ? -8 : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(LiquidPressStyle())
        .overlay(alignment: .top) {
            if index > 0 && place != .current && standing(index - 1) != .current {
                Rectangle().fill(StrandPalette.hairline).frame(height: NoopMetrics.hairlineWidth)
            }
        }
        // Fork chantier 12: the phase just reached slides its highlight in.
        .animation(NoopMotion.card, value: state?.phaseIndex)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Shows the phase"))
    }
}

// MARK: Water

/// A bottle filling with the day's water: 0 · 1 L · 2 L · 3 L graduations, the goal as a dashed line.
/// `fill` is the animated share of 3 L (the caller drives it); `goal` the goal's share of 3 L.
struct FastingBottle: View, Animatable {
    var fill: Double
    let goal: Double

    var animatableData: Double {
        get { fill }
        set { fill = newValue }
    }

    /// The bottle on a 120 × 210 design: a neck and a rounded body.
    private static func outline(in box: CGRect) -> Path {
        let s = box.width / 120
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: box.minX + x * s, y: box.minY + y * s) }
        var path = Path()
        path.move(to: p(50, 6))
        path.addLine(to: p(70, 6))
        path.addQuadCurve(to: p(74, 10), control: p(74, 6))
        path.addLine(to: p(74, 26))
        path.addQuadCurve(to: p(80, 36), control: p(74, 32))
        path.addQuadCurve(to: p(98, 70), control: p(98, 46))
        path.addLine(to: p(98, 186))
        path.addQuadCurve(to: p(84, 200), control: p(98, 200))
        path.addLine(to: p(36, 200))
        path.addQuadCurve(to: p(22, 186), control: p(22, 200))
        path.addLine(to: p(22, 70))
        path.addQuadCurve(to: p(40, 36), control: p(22, 46))
        path.addQuadCurve(to: p(46, 26), control: p(46, 32))
        path.addLine(to: p(46, 10))
        path.addQuadCurve(to: p(50, 6), control: p(46, 6))
        path.closeSubpath()
        return path
    }

    /// The body spans 0 L at y 196 to 3 L at y 46 on the design: 50 units per litre.
    private static func level(_ share: Double, in box: CGRect) -> CGFloat {
        let s = box.width / 120
        return box.minY + (196 - CGFloat(min(max(share, 0), 1)) * 150) * s
    }

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width / 150, size.height / 210)
            let box = CGRect(x: (size.width - 150 * s) / 2, y: (size.height - 210 * s) / 2, width: 120 * s, height: 210 * s)
            let outline = Self.outline(in: box)
            ctx.fill(outline, with: .color(StrandPalette.accentMuted))
            // The water, clipped to the bottle, with a low wave on its surface.
            let top = Self.level(fill, in: box)
            if fill > 0.001 {
                var water = Path()
                let left = box.minX + 22 * s, right = box.minX + 98 * s, bottom = box.minY + 200 * s
                water.move(to: CGPoint(x: left, y: top))
                water.addQuadCurve(to: CGPoint(x: (left + right) / 2, y: top), control: CGPoint(x: left + (right - left) / 4, y: top - 4 * s))
                water.addQuadCurve(to: CGPoint(x: right, y: top), control: CGPoint(x: right - (right - left) / 4, y: top + 4 * s))
                water.addLine(to: CGPoint(x: right, y: bottom))
                water.addLine(to: CGPoint(x: left, y: bottom))
                water.closeSubpath()
                var clipped = ctx
                clipped.clip(to: outline)
                clipped.fill(water, with: .color(StrandPalette.accent))
            }
            ctx.stroke(outline, with: .color(StrandPalette.hairlineStrong), lineWidth: 1.5)
            // The goal, dashed across the body.
            let goalY = Self.level(goal, in: box)
            var dash = Path()
            dash.move(to: CGPoint(x: box.minX + 26 * s, y: goalY))
            dash.addLine(to: CGPoint(x: box.minX + 94 * s, y: goalY))
            ctx.stroke(dash, with: .color(StrandPalette.textPrimary.opacity(0.7)),
                       style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
            // Graduations to the right: 0, 1 L, 2 L, 3 L and the half litres.
            let f = StrandFont.caption2.weight(.semibold)
            for litre in 0...3 {
                let y = Self.level(Double(litre) / 3, in: box)
                var tick = Path()
                tick.move(to: CGPoint(x: box.maxX + 4 * s, y: y))
                tick.addLine(to: CGPoint(x: box.maxX + 12 * s, y: y))
                ctx.stroke(tick, with: .color(StrandPalette.textSecondary), lineWidth: 1.5)
                let label = litre == 0 ? "0" : FastingFormat.litres(ml: Double(litre) * 1000)
                ctx.draw(ctx.resolve(Text(verbatim: label).font(f).foregroundColor(StrandPalette.textSecondary)),
                         at: CGPoint(x: box.maxX + 16 * s, y: y), anchor: .leading)
                if litre < 3 {
                    let half = Self.level((Double(litre) + 0.5) / 3, in: box)
                    var small = Path()
                    small.move(to: CGPoint(x: box.maxX + 4 * s, y: half))
                    small.addLine(to: CGPoint(x: box.maxX + 8 * s, y: half))
                    ctx.stroke(small, with: .color(StrandPalette.textTertiary), lineWidth: 1)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// « Water »: the bottle, the litres against the goal, + 250 ml / + 500 ml / the custom size / undo the
/// last, a long press on the bottle to correct, and the way to the caffeine log.
struct FastingWaterCard: View {
    let totalML: Double
    let goalML: Int
    let customML: Int
    let canUndo: Bool
    /// Fork chantier 12: false draws the figures at once (data loading).
    var animated: Bool = true
    let onAdd: (Int) -> Void
    let onUndo: () -> Void
    let onCorrect: () -> Void
    let onCaffeine: () -> Void

    @State private var fill: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var motion = NoopMotionState.shared

    /// The bottle holds 3 L: the share of it.
    private var share: Double { min(1, max(0, totalML / 3000)) }
    private var goalShare: Double { min(1, max(0, Double(goalML) / 3000)) }
    private var percent: Int { goalML > 0 ? Int((totalML / Double(goalML) * 100).rounded(.towardZero)) : 0 }
    private var leftML: Double { max(0, Double(goalML) - totalML) }
    /// Where the « goal » word sits under the dashed line, in the 210-point bottle (0 L at 196, 3 L at 46).
    private var goalLabelOffsetY: CGFloat {
        let level: CGFloat = 196 - CGFloat(goalShare) * 150
        return level - 105 + 12
    }

    /// « 43 % » of the goal, computed once so the body stays simple to type-check.
    private var percentText: String {
        let permille = goalML > 0 ? Int(totalML / Double(goalML) * 1000) : 0
        return FastingFormat.percent(permille: permille)
    }

    var body: some View {
        NoopCard(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                header
                HStack(alignment: .center, spacing: 14) {
                    bottle
                    figures
                }
                Rectangle().fill(StrandPalette.hairline).frame(height: NoopMetrics.hairlineWidth)
                footer
            }
        }
        .onAppear {
            if motion.poseStill(reduceMotion) || !animated { fill = share }
            else { withAnimation(NoopMotion.ringDraw) { fill = share } }
        }
        .onChangeCompat(of: share) { newShare in
            withAnimation(NoopMotion.gated(NoopMotion.valueChange, reduced: motion.poseStill(reduceMotion))) {
                fill = newShare
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Water")
                .font(StrandFont.headline)
                .foregroundStyle(StrandPalette.textPrimary)
            Spacer()
            Text("today's goal \(FastingFormat.litres(ml: Double(goalML)))")
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textSecondary)
        }
    }

    private var bottle: some View {
        ZStack {
            FastingBottle(fill: fill, goal: goalShare)
                .frame(width: 150, height: 210)
            Text("goal")
                .font(StrandFont.caption2.weight(.semibold))
                .foregroundStyle(StrandPalette.textPrimary.opacity(0.75))
                .offset(x: -15, y: goalLabelOffsetY)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .onLongPressGesture { onCorrect() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Water"))
        .accessibilityValue(Text(verbatim: "\(FastingFormat.litres(ml: totalML)) / \(FastingFormat.litres(ml: Double(goalML)))"))
        .accessibilityHint(Text("Long press to correct an entry"))
    }

    private var figures: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                NoopRollingNumber(value: totalML, format: { FastingFormat.litres(ml: $0) },
                                  font: StrandFont.rounded(26), color: StrandPalette.accent,
                                  armed: animated, launchKey: "fasting.water")
                Text("\(percentText) of the goal")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            if leftML > 0 {
                Text("\(FastingFormat.litres(ml: leftML)) to go before the goal.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Goal reached. Keep drinking to your thirst.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.fastingDone)
                    .fixedSize(horizontal: false, vertical: true)
            }
            buttons
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var buttons: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            waterButton(Text("\(250) ml"), filled: true, plus: true) { onAdd(250) }
            waterButton(Text("\(500) ml"), filled: true, plus: true) { onAdd(500) }
            waterButton(Text("Custom · \(customML) ml"), filled: false) { onAdd(customML) }
            waterButton(Text("Undo the last"), filled: false, enabled: canUndo) { onUndo() }
        }
    }

    private var footer: some View {
        HStack {
            Text("Long press on the bottle to correct an entry")
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
            Spacer(minLength: 8)
            Button(action: onCaffeine) {
                HStack(spacing: 2) {
                    Text("Coffee · tea")
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                }
                .font(StrandFont.caption.weight(.semibold))
                .foregroundStyle(StrandPalette.accent)
            }
            .buttonStyle(.plain)
        }
    }

    private func waterButton(_ title: Text, filled: Bool, plus: Bool = false, enabled: Bool = true,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                if plus { Image(systemName: "plus").font(.system(size: 13, weight: .bold)).accessibilityHidden(true) }
                title
            }
                .font(StrandFont.subhead.weight(filled ? .bold : .semibold))
                .foregroundStyle(filled ? StrandPalette.onDarkPrimary : StrandPalette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(filled ? StrandPalette.accent : StrandPalette.surfaceInset,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(LiquidPressStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }
}

// MARK: History

/// « Your fasts »: 7 or 30 days of bars (green kept, soft red shorter, grey none, today's running fast
/// lighter), the mean, the goals kept and the streak.
struct FastingHistoryCard: View {
    /// One duration per day, oldest first, today last (`FastingLog.dailyFastMinutes`).
    let durations: [Int]
    let summary: FastingTimeline.Summary
    let goalMinutes: Int
    let todayRunning: Bool
    @Binding var days: Int
    var loading = false
    var animated = true

    private let barAreaHeight: CGFloat = 100
    /// The tallest bar: the goal and a quarter, so a long fast still fits.
    private var scaleMinutes: Int { max(goalMinutes * 5 / 4, (durations.max() ?? 0), 60) }

    private func barHeight(_ minutes: Int) -> CGFloat {
        max(4, barAreaHeight * CGFloat(min(minutes, scaleMinutes)) / CGFloat(scaleMinutes))
    }

    private func barColor(_ index: Int, _ minutes: Int) -> Color {
        if minutes == 0 { return StrandPalette.surfaceInset }
        if index == durations.count - 1 && todayRunning { return StrandPalette.fastingDone.opacity(0.45) }
        return minutes >= goalMinutes ? StrandPalette.fastingDone : StrandPalette.fastingRemaining
    }

    var body: some View {
        NoopCard(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Your fasts")
                        .font(StrandFont.headline)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Spacer()
                    rangeSwitch
                }
                HStack(alignment: .top, spacing: 8) {
                    figure(Text("Average"), FastingFormat.duration(minutes: summary.averageMinutes), StrandPalette.textPrimary)
                    figure(Text("Goal kept"), "\(summary.keptCount) / \(durations.count)", StrandPalette.textPrimary)
                    figure(Text("Streak"), String(localized: "\(summary.streak) d"), StrandPalette.fastingDone)
                }
                if loading {
                    Text("Reading the fasts…")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .frame(height: barAreaHeight)
                } else {
                    bars
                }
                axis
                Text("Green: goal kept · soft red: shorter · grey: no fast · last bar: running.")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func figure(_ label: Text, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            label.font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            Text(verbatim: value)
                .font(StrandFont.rounded(17))
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rangeSwitch: some View {
        HStack(spacing: 2) {
            ForEach([7, 30], id: \.self) { n in
                let on = days == n
                Button {
                    withAnimation(NoopMotion.card) { days = n }
                } label: {
                    Text("\(n) d")
                        .font(StrandFont.caption.weight(.semibold))
                        .foregroundStyle(on ? StrandPalette.textPrimary : StrandPalette.textSecondary)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(on ? StrandPalette.hairlineStrong : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .background(StrandPalette.surfaceInset, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var bars: some View {
        let goalTop = barAreaHeight - barAreaHeight * CGFloat(min(goalMinutes, scaleMinutes)) / CGFloat(scaleMinutes)
        return NoopFirstDraw(key: "fasting.bars.\(days)", armed: animated) { phase in
            ZStack(alignment: .topLeading) {
                HStack(alignment: .bottom, spacing: days > 7 ? 3 : 10) {
                    ForEach(Array(durations.enumerated()), id: \.offset) { index, minutes in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(barColor(index, minutes))
                            .frame(height: barHeight(minutes))
                            .frame(maxWidth: .infinity)
                            // Fork chantier 12: the bars rise from the base as the card arrives.
                            .scaleEffect(x: 1, y: phase.drawn ? 1 : 0.02, anchor: .bottom)
                            .animation(phase.motion(NoopMotion.ringDraw.delay(Double(index) * NoopMotion.stagger / 2)),
                                       value: phase.drawn)
                    }
                }
                .frame(height: barAreaHeight, alignment: .bottom)
                Rectangle()
                    .fill(StrandPalette.textSecondary)
                    .frame(height: 1)
                    .offset(y: goalTop)
                    .mask(HStack(spacing: 3) { ForEach(0..<40, id: \.self) { _ in Rectangle().frame(width: 3) } })
                Text(verbatim: FastingFormat.duration(minutes: goalMinutes))
                    .font(StrandFont.caption2)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .padding(.horizontal, 3)
                    .background(StrandPalette.surfaceRaised)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .offset(y: goalTop - 14)
            }
            .frame(height: barAreaHeight)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Your fasts"))
        .accessibilityValue(Text(verbatim: "\(summary.keptCount) / \(durations.count)"))
    }

    private var axis: some View {
        HStack {
            if days > 7 {
                Text("\(days) days ago")
                Spacer()
                Text("today")
            } else {
                ForEach(Array(weekdayLetters().enumerated()), id: \.offset) { index, letter in
                    Text(verbatim: letter)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .font(StrandFont.caption2)
        .foregroundStyle(StrandPalette.textSecondary)
    }

    /// The initial of each of the last 7 days, today last, « today » for the last one.
    private func weekdayLetters(now: Date = Date(), calendar: Calendar = .current) -> [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        return (0..<7).map { back in
            if back == 6 { return String(localized: "today") }
            let day = calendar.date(byAdding: .day, value: back - 6, to: now) ?? now
            let weekday = calendar.component(.weekday, from: day) - 1
            return symbols[(weekday + symbols.count) % symbols.count]
        }
    }
}

// MARK: Sheets

/// A date and time to pick (the start, the real end): the wheel on iOS, compact elsewhere.
struct FastingTimeSheet: View {
    let title: LocalizedStringKey
    let explanation: LocalizedStringKey
    @Binding var date: Date
    let range: ClosedRange<Date>
    /// The consequence of the time picked, recomputed by the caller (« The fast is then 11 h 42 min »).
    let footer: String
    let saveTitle: LocalizedStringKey
    var destructive = false
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text(explanation)
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                DatePicker("", selection: $date, in: range, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    #if os(iOS)
                    .datePickerStyle(.wheel)
                    #else
                    .datePickerStyle(.compact)
                    #endif
                    .frame(maxWidth: .infinity)
                Text(verbatim: footer)
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
                FastingActionButton(title: Text(saveTitle), look: destructive ? .stop : .primary, action: onSave)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, NoopMetrics.screenHPadding)
            .padding(.top, 8)
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .navigationTitle(Text(title))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #endif
    }
}

/// The planned end: the quick picks and the wheel to the hour; the end time follows.
struct FastingGoalSheet: View {
    @Binding var goalMinutes: Int
    let startedAt: Date
    let now: Date
    let onSave: () -> Void
    let onCancel: () -> Void

    private var plannedEnd: Date { startedAt.addingTimeInterval(TimeInterval(goalMinutes * 60)) }
    private var remaining: Int {
        FastingTimeline.fastingRemainingMinutes(elapsedMinutes: Int(now.timeIntervalSince(startedAt)) / 60,
                                                goalMinutes: goalMinutes)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                VStack(spacing: 2) {
                    Text(verbatim: FastingFormat.clock(plannedEnd))
                        .font(StrandFont.number(44, weight: .bold))
                        .foregroundStyle(StrandPalette.textPrimary)
                        .monospacedDigit()
                    Text("\(FastingFormat.dayWord(plannedEnd, now: now)) · \(FastingFormat.duration(minutes: goalMinutes)) of fasting since \(FastingFormat.dayAndClock(startedAt, now: now))")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                FastingGoalPicker(goalMinutes: $goalMinutes)
                Text("\(FastingFormat.duration(minutes: remaining)) left then. The end notification follows this time.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                FastingActionButton(title: Text("Save"), look: .primary, action: onSave)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, NoopMetrics.screenHPadding)
            .padding(.top, 8)
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .navigationTitle(Text("Planned end"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #endif
    }
}

/// One phase: the app's text (what is happening, what you may feel), ‹ › to the neighbours, then « Ask
/// the Coach for me », whose answer arrives in a bubble. Sent to Anthropic only on that tap.
struct FastingPhaseSheet: View {
    @Binding var index: Int
    let state: FastingState?
    let now: Date
    /// Nil when the Coach is off or has no key: the button explains why instead.
    let explain: ((Int) async -> FastingExplainOutcome)?
    let onOpenCoach: () -> Void
    let onClose: () -> Void

    @State private var answer: String?
    @State private var failure: String?
    @State private var asking = false
    @State private var askTask: Task<Void, Never>?

    private var status: String {
        guard let state else { return String(localized: "to come") }
        if index == state.phaseIndex {
            return state.isRunning
                ? String(localized: "you have been here for \(FastingFormat.duration(minutes: state.elapsedMinutes - FastingTimeline.phaseStartHours[index] * 60))")
                : String(localized: "reached at the end")
        }
        if index < state.phaseIndex { return String(localized: "passed") }
        guard state.isRunning else { return String(localized: "not reached") }
        return String(localized: "in \(FastingFormat.duration(minutes: FastingTimeline.phaseStartHours[index] * 60 - state.elapsedMinutes))")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    HStack {
                        neighbour(index - 1, leading: true)
                        Spacer()
                        neighbour(index + 1, leading: false)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What is happening")
                            .font(StrandFont.overline)
                            .foregroundStyle(StrandPalette.textSecondary)
                        Text(verbatim: FastingPhaseText.what(index))
                            .font(StrandFont.body)
                            .foregroundStyle(StrandPalette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("What you may feel")
                            .font(StrandFont.overline)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .padding(.top, 4)
                        Text(verbatim: FastingPhaseText.feel(index))
                            .font(StrandFont.body)
                            .foregroundStyle(StrandPalette.textPrimary.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(StrandPalette.surfaceInset, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    // Fork chantier 12: another phase swaps its text by a fade.
                    .id(index)
                    .transition(.opacity)
                    coachSection
                    Text(FastingPhaseText.caution)
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, NoopMetrics.screenHPadding)
                .padding(.bottom, 24)
                .animation(NoopMotion.card, value: index)
            }
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close", action: onClose)
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.large])
        #endif
        .onChangeCompat(of: index) { _ in
            askTask?.cancel()
            answer = nil
            failure = nil
            asking = false
        }
        .onDisappear { askTask?.cancel() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(FastingPhaseText.tint(index))
                Image(systemName: FastingPhaseText.symbol(index))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(StrandPalette.surfaceBase)
            }
            .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: FastingPhaseText.name(index))
                    .font(StrandFont.title2)
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(verbatim: "\(FastingPhaseText.range(index)) · \(status)")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private func neighbour(_ target: Int, leading: Bool) -> some View {
        if target >= 0 && target < FastingPhaseText.count {
            Button {
                withAnimation(NoopMotion.card) { index = target }
            } label: {
                HStack(spacing: 4) {
                    if leading { Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold)) }
                    Text(verbatim: FastingPhaseText.name(target))
                    if !leading { Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)) }
                }
                .font(StrandFont.caption.weight(.semibold))
                .foregroundStyle(StrandPalette.textPrimary)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(StrandPalette.surfaceInset, in: Capsule())
            }
            .buttonStyle(.plain)
        } else {
            Color.clear.frame(width: 1, height: 30)
        }
    }

    @ViewBuilder
    private var coachSection: some View {
        if let answer {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(StrandPalette.metricPurple)
                    .frame(width: 32, height: 32)
                    .background(StrandPalette.metricPurple.opacity(0.18), in: Circle())
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: answer)
                        .font(StrandFont.body)
                        .foregroundStyle(StrandPalette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Text("Coach · read your fast, your last meal and your water")
                            .font(StrandFont.caption2)
                            .foregroundStyle(StrandPalette.metricPurple)
                        Spacer(minLength: 6)
                        Button(action: onOpenCoach) {
                            Text("Continue ›")
                                .font(StrandFont.caption2.weight(.semibold))
                                .foregroundStyle(StrandPalette.metricPurple)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .background(StrandPalette.metricPurple.opacity(0.18),
                            in: UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 6,
                                                       bottomTrailingRadius: 18, topTrailingRadius: 18, style: .continuous))
            }
            // Fork chantier 12: the Coach's bubble fades and slides in.
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        } else {
            VStack(spacing: 6) {
                Button {
                    ask()
                } label: {
                    HStack(spacing: 8) {
                        if asking {
                            ProgressView().tint(StrandPalette.onDarkPrimary)
                        } else {
                            Image(systemName: "sparkles").font(.system(size: 15, weight: .semibold))
                        }
                        if asking {
                            Text("The Coach is reading…")
                        } else {
                            Text("Ask the Coach for me")
                        }
                    }
                    .font(StrandFont.body.weight(.bold))
                    .foregroundStyle(StrandPalette.onDarkPrimary)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(StrandPalette.metricPurple, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(LiquidPressStyle())
                .disabled(asking || explain == nil)
                .opacity(explain == nil ? 0.5 : 1)
                if let failure, !failure.isEmpty {
                    Text(verbatim: failure)
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.statusWarning)
                        .multilineTextAlignment(.center)
                } else if explain == nil {
                    Text("Turn the Coach on with an Anthropic key to get this phase explained for you.")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("Sent to Anthropic only if you tap. The Coach reads your fast, your last meal and your water.")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    private func ask() {
        guard let explain, !asking else { return }
        asking = true
        failure = nil
        let target = index
        askTask = Task {
            let outcome = await explain(target)
            guard !Task.isCancelled, target == index else { return }
            withAnimation(NoopMotion.card) {
                switch outcome {
                case .answer(let text): answer = text
                case .failure(let text): failure = text
                }
                asking = false
            }
        }
    }
}
