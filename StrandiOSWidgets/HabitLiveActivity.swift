import WidgetKit
import SwiftUI
import ActivityKit
import AppIntents
import StrandDesign

/// Live Activity of a running habit stopwatch (personal fork, chantier 24 PR C), on the model of the fasting
/// banner: the habit's icon and name, « since 21:48 », the time counting up, Stop.
///
/// NOTHING HERE NEEDS A PUSH TO MOVE: the clock is `Text(timerInterval:)` over the start the app sent.
struct HabitLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: HabitActivityAttributes.self) { context in
            lockScreen(context.state)
                .activityBackgroundTint(StrandPalette.surfaceBase)
                .activitySystemActionForegroundColor(StrandPalette.textPrimary)
                .widgetURL(Self.openURL)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(context.state.title)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    } icon: {
                        Image(systemName: context.state.symbol)
                    }
                    .foregroundStyle(StrandPalette.accent)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.sinceText)
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 12) {
                        habitClock(context.state)
                            .font(Self.clockFont)
                            .monospacedDigit()
                            .foregroundStyle(StrandPalette.textPrimary)
                        Spacer(minLength: 4)
                        stopButton(context.state, compact: true)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.symbol)
                    .foregroundStyle(StrandPalette.accent)
            } compactTrailing: {
                // Sized by a hidden template, as the fasting banner's clock: a running timer takes every point
                // it is offered.
                Text(verbatim: "00:00:00")
                    .font(Self.islandFont)
                    .monospacedDigit()
                    .hidden()
                    .overlay(alignment: .trailing) {
                        habitClock(context.state)
                            .font(Self.islandFont)
                            .monospacedDigit()
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(StrandPalette.accent)
                    }
            } minimal: {
                Image(systemName: context.state.symbol)
                    .foregroundStyle(StrandPalette.accent)
            }
            .widgetURL(Self.openURL)
        }
    }

    /// A tap on the banner opens the Habits screen (`StrandiOSApp.onOpenURL`).
    static let openURL = URL(string: "noop://habits")

    private static let clockFont = Font.system(size: 30, weight: .bold, design: .rounded)
    private static let islandFont = Font.system(size: 13, weight: .semibold, design: .rounded)

    private func lockScreen(_ state: HabitActivityAttributes.ContentState) -> some View {
        HStack(spacing: 12) {
            Image(systemName: state.symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(StrandPalette.surfaceBase)
                .frame(width: 40, height: 40)
                .background(StrandPalette.accent, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(state.title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(StrandPalette.textPrimary)
                        .lineLimit(1)
                    Text(state.sinceText)
                        .font(.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .lineLimit(1)
                }
                Text(verbatim: "00:00:00")
                    .font(Self.clockFont)
                    .monospacedDigit()
                    .hidden()
                    .overlay(alignment: .leading) {
                        habitClock(state)
                            .font(Self.clockFont)
                            .monospacedDigit()
                            .foregroundStyle(StrandPalette.textPrimary)
                    }
            }
            Spacer(minLength: 6)
            stopButton(state, compact: false)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 14)
    }

    /// Counts up from the start; the far end only keeps the range open (iOS ends a banner after 8 hours, and
    /// the app starts it again on its next return to the foreground).
    private func habitClock(_ state: HabitActivityAttributes.ContentState) -> Text {
        Text(timerInterval: state.startedAt...state.startedAt.addingTimeInterval(72 * 3600), countsDown: false)
    }

    private func stopButton(_ state: HabitActivityAttributes.ContentState, compact: Bool) -> some View {
        Button(intent: HabitBannerStopIntent()) {
            Text(state.stopLabel)
                .font(.system(size: compact ? 13 : 14, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(StrandPalette.onDarkPrimary)
                .padding(.horizontal, 14)
                .frame(height: compact ? 34 : 38)
                .background(StrandPalette.statusCritical, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(state.stopLabel)
    }
}
