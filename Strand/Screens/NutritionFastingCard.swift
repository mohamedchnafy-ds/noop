import SwiftUI
import StrandDesign
import StrandAnalytics

// MARK: - The Fast · Water card of the Nutrition page (personal fork, chantier 15)
//
// Under the four rings, above the moments: a small ring and the fast's standing (running, over, none)
// on the left, the day's water on one line, and « + 250 ml » at the right edge. A tap opens the Jeûne
// page. Every figure arrives resolved (`FastingState`, the hydration store): nothing is computed here.

struct NutritionFastingCard: View {
    /// The running fast, or the one just over (`FastingLog.shownFastingState`); nil when nothing.
    let state: FastingState?
    let waterML: Double
    let goalML: Int
    /// Fork chantier 12: the small ring traces itself and the figures slam in once per showing.
    var animated: Bool = false
    let onOpen: () -> Void
    let onAddWater: () -> Void

    @State private var splash = 0

    private var mode: FastingRingMode {
        state.map { $0.isRunning ? .running : .done(reached: $0.goalReached) } ?? .idle
    }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    NoopFirstDraw(key: "nutrition.fasting.\(state?.fast.id ?? "idle")", armed: animated) { phase in
                        FastingRing(mode: mode, progressPermille: state?.progressPermille ?? 0,
                                    trace: phase.drawn ? 1 : 0, markers: state?.markers ?? [],
                                    currentPhase: state?.phaseIndex ?? 0, diameter: 74) {
                            VStack(spacing: 0) {
                                if let state {
                                    Text(verbatim: FastingFormat.duration(minutes: state.elapsedMinutes))
                                        .font(StrandFont.rounded(13))
                                        .foregroundStyle(StrandPalette.textPrimary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.6)
                                    Text("of \(FastingFormat.duration(minutes: state.fast.goalMinutes))")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(StrandPalette.textSecondary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.6)
                                } else {
                                    Image(systemName: "fork.knife")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(StrandPalette.textTertiary)
                                }
                            }
                            .monospacedDigit()
                        }
                        .animation(phase.motion(NoopMotion.ringDraw), value: phase.drawn)
                    }
                    .frame(width: 82, height: 82)
                    VStack(alignment: .leading, spacing: 3) {
                        titleLine
                        detailLine
                        waterLine
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(StrandPalette.textTertiary)
                        .accessibilityHidden(true)
                }
                .padding(.vertical, 12)
                .padding(.leading, 14)
                .padding(.trailing, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(LiquidPressStyle())
            .accessibilityElement(children: .combine)
            .accessibilityHint(Text("Opens the fasting page"))
            Rectangle().fill(StrandPalette.hairline).frame(width: NoopMetrics.hairlineWidth).padding(.vertical, 10)
            Button {
                splash += 1
                onAddWater()
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .bold))
                        .noopSymbolBounce(splash)
                    Text("\(250) ml")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(StrandPalette.accent)
                .frame(width: 56)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(LiquidPressStyle())
            .accessibilityLabel(Text("Add 250 ml of water"))
        }
        .frame(maxWidth: .infinity)
        .background(NoopPanelSurface(cornerRadius: NoopMetrics.cardRadius))
    }

    @ViewBuilder
    private var titleLine: some View {
        HStack(spacing: 6) {
            Text("Fasting")
                .font(StrandFont.body.weight(.semibold))
                .foregroundStyle(StrandPalette.textPrimary)
            if let state {
                let tint = state.isRunning ? StrandPalette.fastingDone
                    : state.goalReached ? StrandPalette.fastingDone : StrandPalette.fastingRemaining
                Group {
                    if state.isRunning { Text("running") } else if state.goalReached { Text("goal reached") } else { Text("goal not reached") }
                }
                    .font(StrandFont.caption2.weight(.bold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(tint.opacity(0.18), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
    }

    @ViewBuilder
    private var detailLine: some View {
        if let state, state.isRunning {
            (Text("Left").foregroundColor(StrandPalette.textSecondary) + Text(verbatim: " ")
             + Text(verbatim: FastingFormat.duration(minutes: state.remainingMinutes)).foregroundColor(StrandPalette.fastingRemaining).bold()
             + Text(verbatim: " · ") + Text("planned end").foregroundColor(StrandPalette.textSecondary) + Text(verbatim: " ")
             + Text(verbatim: FastingFormat.clock(state.plannedEnd)).foregroundColor(StrandPalette.textPrimary).bold())
                .font(StrandFont.footnote)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack(spacing: 4) {
                Image(systemName: FastingPhaseText.symbol(state.phaseIndex))
                    .font(.system(size: 11, weight: .semibold))
                Text(verbatim: FastingPhaseText.name(state.phaseIndex))
            }
            .font(StrandFont.footnote.weight(.semibold))
            .foregroundStyle(FastingPhaseText.tint(state.phaseIndex))
            .lineLimit(1)
            .id(state.phaseIndex)
            .transition(.opacity)
        } else if let state {
            Text("Over · \(FastingFormat.duration(minutes: state.elapsedMinutes)) out of \(FastingFormat.duration(minutes: state.fast.goalMinutes))")
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textSecondary)
                .lineLimit(1)
        } else {
            Text("No fast running · Start ›")
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textSecondary)
                .lineLimit(1)
        }
    }

    private var waterLine: some View {
        HStack(spacing: 6) {
            Image(systemName: "drop.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(StrandPalette.accent)
            (Text("Water").foregroundColor(StrandPalette.textSecondary) + Text(verbatim: " ")
             + Text(verbatim: FastingFormat.litres(ml: waterML)).foregroundColor(StrandPalette.accent).bold()
             + Text(verbatim: " ") + Text("of \(FastingFormat.litres(ml: Double(goalML)))").foregroundColor(StrandPalette.textSecondary))
                .font(StrandFont.footnote)
                .lineLimit(1)
                .noopRollingDigits(waterML)
        }
        .padding(.top, 2)
    }
}
