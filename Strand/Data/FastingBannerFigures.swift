import Foundation

// Personal fork, chantier 15 PR C: what the Lock Screen banner of a fast says, resolved app-side.
//
// The widget extension ships no string catalog, so every word it renders arrives already translated
// (the same rule as the Lift Log banner). The clocks are NOT strings: the banner counts from the dates
// with `Text(timerInterval:)` and `ProgressView(timerInterval:)`, which tick on their own, so the app
// pushes a new state only when the fast itself changes (start, goal, end). Pure, tested on macOS.

struct FastingBannerFigures: Equatable {
    /// « Fasting · 16h ».
    var title: String
    /// « left », « end 12:30 », « Stop », « goal reached ».
    var leftLabel: String
    var endLabel: String
    var stopLabel: String
    var goalReachedLabel: String
    var startedAt: Date
    var plannedEnd: Date
    var goalMinutes: Int
    /// The goal was met when this state was pushed (the app was running at the planned end).
    var goalReached: Bool

    /// The banner's words for a running fast; nil for a fast that is over (no banner).
    static func fastingBannerFigures(_ state: FastingState) -> FastingBannerFigures? {
        guard state.isRunning else { return nil }
        return FastingBannerFigures(
            title: String(localized: "Fasting · \(FastingFormat.duration(minutes: state.fast.goalMinutes))"),
            leftLabel: String(localized: "left"),
            endLabel: String(localized: "end \(FastingFormat.clock(state.plannedEnd))"),
            stopLabel: String(localized: "Stop"),
            goalReachedLabel: String(localized: "goal reached"),
            startedAt: state.startedAt,
            plannedEnd: state.plannedEnd,
            goalMinutes: state.fast.goalMinutes,
            goalReached: state.goalReached)
    }
}
