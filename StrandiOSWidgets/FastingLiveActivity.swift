import WidgetKit
import SwiftUI
import ActivityKit
import AppIntents
import StrandDesign

/// Live Activity of a running fast (personal fork, chantier 15): the ring filling toward the planned end,
/// « Fasting · 16h », the time done and the time left, « end 12:30 », and a Stop button, on the Lock
/// Screen and in the Dynamic Island (mockup board 4 « Autour »: « Jeûne · 11 h 42 min », « reste 4 h 18 min · fin 12:30 »).
///
/// EVERYTHING TICKS WITHOUT THE APP. The ring is `ProgressView(timerInterval:)`, the clocks are
/// `Text(timerInterval:)`, all driven by the dates in the content state; the app pushes a new state only
/// when the fast itself changes. Past the planned end the ring stays full and the countdown reads 0:00
/// until the app, when next running, pushes « goal reached ». Every word arrives already translated.
struct FastingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FastingActivityAttributes.self) { context in
            lockScreen(context.state)
                .activityBackgroundTint(StrandPalette.surfaceBase)
                .activitySystemActionForegroundColor(StrandPalette.textPrimary)
                .widgetURL(Self.openURL)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ring(context.state, size: 40)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(context.state.leftLabel)
                            .font(.caption2)
                            .foregroundStyle(StrandPalette.textSecondary)
                        leftClock(context.state)
                            .font(Self.islandFont)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(context.state.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(StrandPalette.textPrimary)
                                .lineLimit(1)
                            Text(context.state.endLabel)
                                .font(.caption2)
                                .foregroundStyle(StrandPalette.textSecondary)
                        }
                        Spacer(minLength: 8)
                        stopButton(context.state, compact: true)
                    }
                }
            } compactLeading: {
                ring(context.state, size: 18)
            } compactTrailing: {
                // Sized by a hidden template, as the Lift Log banner does: a running timer takes all the
                // width it is offered.
                Text(verbatim: "00:00:00")
                    .font(Self.islandFont)
                    .monospacedDigit()
                    .hidden()
                    .overlay(alignment: .trailing) {
                        leftClock(context.state)
                            .font(Self.islandFont)
                            .multilineTextAlignment(.trailing)
                    }
            } minimal: {
                ring(context.state, size: 18)
            }
            .widgetURL(Self.openURL)
        }
    }

    /// Opens the Jeûne page (`StrandiOSApp.onOpenURL` → `NavRouter.openFastingPage`).
    private static let openURL = URL(string: "noop://fasting")

    private static let clockFont = Font.system(size: 20, weight: .bold, design: .rounded)
    private static let islandFont = Font.system(size: 13, weight: .semibold, design: .rounded)

    /// The ring filling from the start to the planned end, green on a soft red track, on its own clock.
    private func ring(_ state: FastingActivityAttributes.ContentState, size: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(StrandPalette.fastingRemaining.opacity(0.35), lineWidth: size >= 40 ? 5 : 3)
            if state.goalReached || state.plannedEnd <= state.startedAt {
                Circle()
                    .stroke(StrandPalette.fastingDone, lineWidth: size >= 40 ? 5 : 3)
            } else {
                ProgressView(timerInterval: state.startedAt...state.plannedEnd, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .progressViewStyle(.circular)
                .tint(StrandPalette.fastingDone)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// Counts UP from the start, for a day at most (well past any fast).
    private func doneClock(_ state: FastingActivityAttributes.ContentState) -> some View {
        Text(timerInterval: state.startedAt...state.startedAt.addingTimeInterval(36 * 3600), countsDown: false)
            .monospacedDigit()
            .foregroundStyle(StrandPalette.fastingDone)
    }

    /// Counts DOWN to the planned end and reads 0:00 past it; « goal reached » once the app has said so.
    @ViewBuilder
    private func leftClock(_ state: FastingActivityAttributes.ContentState) -> some View {
        if state.goalReached {
            Text(state.goalReachedLabel)
                .foregroundStyle(StrandPalette.fastingDone)
                .lineLimit(1)
        } else if state.plannedEnd > state.startedAt {
            Text(timerInterval: state.startedAt...state.plannedEnd, countsDown: true)
                .monospacedDigit()
                .foregroundStyle(StrandPalette.fastingRemaining)
        } else {
            Text(verbatim: "0:00")
                .monospacedDigit()
                .foregroundStyle(StrandPalette.fastingRemaining)
        }
    }

    /// « Stop »: `FastingBannerActionIntent` runs in NOOP's process and ends the fast through `FastingLog`.
    private func stopButton(_ state: FastingActivityAttributes.ContentState, compact: Bool) -> some View {
        Button(intent: FastingBannerActionIntent(action: .stop)) {
            HStack(spacing: 6) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 11, weight: .bold))
                Text(state.stopLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .font(.system(size: compact ? 13 : 14, weight: .semibold))
            .foregroundStyle(StrandPalette.textPrimary)
            .padding(.horizontal, 12)
            .frame(height: compact ? 34 : 38)
            .background(StrandPalette.textPrimary.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(state.stopLabel)
    }

    private func lockScreen(_ state: FastingActivityAttributes.ContentState) -> some View {
        HStack(spacing: 12) {
            ring(state, size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(state.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .lineLimit(1)
                doneClock(state)
                    .font(Self.clockFont)
                HStack(spacing: 4) {
                    Text(state.leftLabel)
                        .font(.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                    leftClock(state)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                    Text(verbatim: "·")
                        .font(.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                    Text(state.endLabel)
                        .font(.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            stopButton(state, compact: false)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 14)
    }
}
