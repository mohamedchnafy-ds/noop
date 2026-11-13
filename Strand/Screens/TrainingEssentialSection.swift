import SwiftUI
import StrandDesign

// MARK: - Training, essential mode (personal fork, chantier 20)
//
// The week as a ring of seven days (lifting in blue, cardio in rose, planned and not done as a faint track,
// today beating), the week's Effort going round it as one hill per day, the sessions done against those
// planned, then today's session and its Start. The days are the calendar's own (`buildTrainingDays`), the
// count is `sessionTally`, the minutes `periodTotals`: the same funnels as the week strip and the month.

struct TrainingEssentialSection: View {
    /// Monday first, the seven days of this week.
    let week: [TrainingDay]
    /// Monday first, each day's stored Effort on the 0–100 axis, nil where there is none.
    let effort: [Double?]
    /// Monday first, one letter per day.
    let weekdays: [String]
    var caption: String
    /// What is planned and not done today: its name, whether it is cardio, and its Start; nil when nothing.
    var todayTitle: String?
    var todayIsCardio: Bool = false
    var onStart: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @ObservedObject var motion = NoopMotionState.shared

    private static let ringDiameter: CGFloat = 236
    private static let ringLine: CGFloat = 22
    private static let traceDiameter: CGFloat = 330
    private static let effortBase: CGFloat = 126
    private static let effortHeight: CGFloat = 36

    private var todayIndex: Int? { week.firstIndex(where: \.isToday) }
    private var tally: (done: Int, planned: Int) { TrainingDays.sessionTally(week) }
    private var minutes: Int { TrainingDays.periodTotals(week).minutes }

    var body: some View {
        VStack(spacing: 0) {
            EssentialHeader(caption: caption)
            Spacer(minLength: NoopMetrics.space3)
            ZStack {
                EssentialEffortTrace(diameter: Self.traceDiameter, base: Self.effortBase,
                                     height: Self.effortHeight, values: effort, fullScale: 100,
                                     todayIndex: todayIndex)
                weekRing
                VStack(spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text(verbatim: "\(tally.done)")
                            .font(StrandFont.number(50, weight: .bold))
                            .foregroundStyle(StrandPalette.textPrimary)
                        if tally.planned > 0 {
                            Text("/ \(tally.planned)")
                                .font(StrandFont.number(30, weight: .bold))
                                .foregroundStyle(StrandPalette.textSecondary)
                                .padding(.leading, 6)
                        }
                    }
                    Text("sessions this week")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                    if minutes > 0 {
                        Text("\(minutes) min")
                            .font(StrandFont.number(13, weight: .bold))
                            .foregroundStyle(StrandPalette.effortColor)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            .frame(width: Self.traceDiameter, height: Self.traceDiameter)
            VStack(spacing: 4) {
                Text("Today")
                    .font(StrandFont.footnote.weight(.semibold))
                    .foregroundStyle(StrandPalette.textSecondary)
                Text(verbatim: todayTitle ?? String(localized: "Nothing planned"))
                    .font(StrandFont.title2.weight(.bold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .padding(.top, NoopMetrics.space3)
            if let onStart, todayTitle != nil {
                EssentialActionButton(title: "Start", symbol: "play.fill", action: onStart)
                    .padding(.top, NoopMetrics.space4)
            }
            Spacer(minLength: NoopMetrics.space3)
        }
        .frame(maxWidth: .infinity, minHeight: 600)
    }

    // MARK: The week ring

    /// Seven arcs from Monday at 12 o'clock, a gap between two days; the day's letter written on its arc.
    private var weekRing: some View {
        let still = motion.poseStill(reduceMotion)
        return ZStack {
            ForEach(Array(week.enumerated()), id: \.offset) { index, day in
                dayArc(day, index: index, still: still)
            }
            ForEach(Array(weekdays.prefix(7).enumerated()), id: \.offset) { index, letter in
                let point = EssentialTraceMath.point(CGPoint(x: Self.ringDiameter / 2, y: Self.ringDiameter / 2),
                                                     radius: (Self.ringDiameter - Self.ringLine) / 2,
                                                     degrees: (Double(index) + 0.5) * 360 / 7)
                Text(verbatim: letter)
                    .font(StrandFont.caption.weight(.bold))
                    .foregroundStyle(letterColor(index))
                    .position(point)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: Self.ringDiameter, height: Self.ringDiameter)
    }

    private func arcColor(_ day: TrainingDay) -> Color? {
        if day.hasLift { return StrandPalette.effortColor }
        if day.hasActivity { return StrandPalette.metricRose }
        return nil
    }

    private func letterColor(_ index: Int) -> Color {
        guard week.indices.contains(index) else { return StrandPalette.textSecondary }
        let day = week[index]
        if arcColor(day) != nil { return StrandPalette.surfaceBase }
        return day.isToday ? StrandPalette.textPrimary : StrandPalette.textSecondary
    }

    @ViewBuilder
    private func dayArc(_ day: TrainingDay, index: Int, still: Bool) -> some View {
        let gap = 0.025
        let from = Double(index) / 7 + gap
        let to = Double(index + 1) / 7 - gap
        let style = StrokeStyle(lineWidth: Self.ringLine, lineCap: .round)
        let arcSide = Self.ringDiameter - Self.ringLine
        ZStack {
            Circle().trim(from: from, to: to)
                .stroke(StrandPalette.textPrimary.opacity(0.08), style: style)
            if let color = arcColor(day) {
                Circle().trim(from: from, to: to)
                    .stroke(color, style: style)
                    .noopStaggeredCharge(index: index, still: still)
            } else if day.isToday {
                EssentialTodayPulse(from: from, to: to, style: style, tint: StrandPalette.textPrimary,
                                    still: still)
            } else if day.isPlannedOpen {
                Circle().trim(from: from, to: to)
                    .stroke((day.hasOpenLift ? StrandPalette.effortColor : StrandPalette.metricRose).opacity(0.28),
                            style: style)
            }
        }
        .rotationEffect(.degrees(-90))
        .frame(width: arcSide, height: arcSide)
    }
}

/// Today's arc on the week ring: a white track whose light rises and falls every 2.4 s.
private struct EssentialTodayPulse: View {
    let from: Double
    let to: Double
    let style: StrokeStyle
    let tint: Color
    let still: Bool

    var body: some View {
        if still {
            arc(0.4)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.4) / 2.4
                arc(0.22 + 0.48 * (0.5 - 0.5 * cos(t * 2 * .pi)))
            }
        }
    }

    private func arc(_ opacity: Double) -> some View {
        Circle().trim(from: from, to: to).stroke(tint.opacity(opacity), style: style)
    }
}

private extension View {
    /// A day done « charges » in: it appears 0.15 s after the day before.
    func noopStaggeredCharge(index: Int, still: Bool) -> some View {
        modifier(EssentialChargeIn(delay: 0.1 + 0.15 * Double(index), still: still))
    }
}

private struct EssentialChargeIn: ViewModifier {
    let delay: Double
    let still: Bool
    @State var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(still || shown ? 1 : 0)
            .onAppear {
                guard !still else { return }
                withAnimation(.easeOut(duration: 0.6).delay(delay)) { shown = true }
            }
    }
}
