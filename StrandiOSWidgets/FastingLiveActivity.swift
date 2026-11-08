import WidgetKit
import SwiftUI
import ActivityKit
import AppIntents
import StrandDesign

/// Live Activity of a running fast (personal fork, chantier 15 PR C), on the model of the Lift Log banner: the
/// ring filling toward the goal, the time fasted (green, counting up), the time left (soft red, counting down),
/// the planned end and Stop.
///
/// NOTHING HERE NEEDS A PUSH TO MOVE. The ring is `ProgressView(timerInterval:)`, both clocks are
/// `Text(timerInterval:)`, all over the start and the planned end the app sent. The stale date is the planned
/// end: once past, `context.isStale` swaps the countdown for « 16 h reached ».
struct FastingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FastingActivityAttributes.self) { context in
            lockScreen(context.state, reached: Self.reached(context))
                .activityBackgroundTint(StrandPalette.surfaceBase)
                .activitySystemActionForegroundColor(StrandPalette.textPrimary)
                .widgetURL(Self.openURL)
        } dynamicIsland: { context in
            let reached = Self.reached(context)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .foregroundStyle(StrandPalette.fastingDone)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.endText)
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 12) {
                        ring(context.state, size: 34, lineWidth: 5)
                        figures(context.state, reached: reached, compact: true)
                        Spacer(minLength: 4)
                        stopButton(context.state, compact: true)
                    }
                }
            } compactLeading: {
                ring(context.state, size: 20, lineWidth: 3.5)
            } compactTrailing: {
                // Sized by a hidden template, as the Lift Log banner's clock: a running timer takes every point
                // it is offered.
                Text(verbatim: "00:00:00")
                    .font(Self.islandFont)
                    .monospacedDigit()
                    .hidden()
                    .overlay(alignment: .trailing) {
                        Group {
                            if reached {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(StrandPalette.fastingDone)
                            } else {
                                leftClock(context.state)
                                    .foregroundStyle(StrandPalette.fastingRemaining)
                            }
                        }
                        .font(Self.islandFont)
                        .multilineTextAlignment(.trailing)
                    }
            } minimal: {
                ring(context.state, size: 20, lineWidth: 3.5)
            }
            .widgetURL(Self.openURL)
        }
    }

    /// A tap on the banner opens the Jeûne page (`StrandiOSApp.onOpenURL`).
    static let openURL = URL(string: "noop://fasting")

    private static let clockFont = Font.system(size: 20, weight: .bold, design: .rounded)
    private static let islandFont = Font.system(size: 13, weight: .semibold, design: .rounded)

    /// Past the planned end: the stale date the app set, or the clock itself on a banner shown late.
    private static func reached(_ context: ActivityViewContext<FastingActivityAttributes>) -> Bool {
        context.isStale || context.state.plannedEnd <= Date()
    }

    private func lockScreen(_ state: FastingActivityAttributes.ContentState, reached: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ring(state, size: 44, lineWidth: 6)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(state.title)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(StrandPalette.textPrimary)
                            .lineLimit(1)
                        Text(state.endText)
                            .font(.caption)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .lineLimit(1)
                    }
                    figures(state, reached: reached, compact: false)
                }
                Spacer(minLength: 6)
                stopButton(state, compact: false)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 14)
    }

    /// The time fasted (green, up) and the time left (soft red, down), or « 16 h reached » once past.
    private func figures(_ state: FastingActivityAttributes.ContentState, reached: Bool, compact: Bool) -> some View {
        HStack(spacing: compact ? 12 : 16) {
            column(state.doneLabel) {
                doneClock(state).foregroundStyle(StrandPalette.fastingDone)
            }
            if reached {
                Text(state.reachedText)
                    .font(.system(size: compact ? 13 : 14, weight: .semibold))
                    .foregroundStyle(StrandPalette.fastingDone)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            } else {
                column(state.leftLabel) {
                    leftClock(state).foregroundStyle(StrandPalette.fastingRemaining)
                }
            }
        }
    }

    private func column<Clock: View>(_ label: String, @ViewBuilder clock: () -> Clock) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(StrandPalette.textSecondary)
                .lineLimit(1)
            Text(verbatim: "00:00:00")
                .font(Self.clockFont)
                .monospacedDigit()
                .hidden()
                .overlay(alignment: .leading) {
                    clock()
                        .font(Self.clockFont)
                        .monospacedDigit()
                }
        }
    }

    /// Counts up from the start; the far end only keeps the range open (no fast lasts three days here).
    private func doneClock(_ state: FastingActivityAttributes.ContentState) -> Text {
        Text(timerInterval: state.startedAt...state.startedAt.addingTimeInterval(72 * 3600), countsDown: false)
    }

    /// Counts down to the planned end. The range starts at the fast's own start, never at « now », so a banner
    /// redrawn after the end still has a valid range and reads 0:00 (the Lift Log banner's rule).
    private func leftClock(_ state: FastingActivityAttributes.ContentState) -> Text {
        let end = max(state.plannedEnd, state.startedAt.addingTimeInterval(60))
        return Text(timerInterval: state.startedAt...end, countsDown: true)
    }

    /// The ring filling by itself from the start to the planned end, green on a soft red track.
    private func ring(_ state: FastingActivityAttributes.ContentState, size: CGFloat, lineWidth: CGFloat) -> some View {
        let end = max(state.plannedEnd, state.startedAt.addingTimeInterval(60))
        return ZStack {
            Circle()
                .stroke(StrandPalette.fastingRemaining.opacity(0.45), lineWidth: lineWidth)
            ProgressView(timerInterval: state.startedAt...end, countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.circular)
            .tint(StrandPalette.fastingDone)
        }
        .frame(width: size, height: size)
    }

    private func stopButton(_ state: FastingActivityAttributes.ContentState, compact: Bool) -> some View {
        Button(intent: FastingBannerStopIntent()) {
            Text(state.stopLabel)
                .font(.system(size: compact ? 13 : 14, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(StrandPalette.textPrimary)
                .padding(.horizontal, 14)
                .frame(height: compact ? 34 : 38)
                .background(StrandPalette.textPrimary.opacity(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(state.stopLabel)
    }
}
