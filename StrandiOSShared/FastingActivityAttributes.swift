#if os(iOS)
import Foundation
import ActivityKit

/// Live Activity attributes for a running fast (personal fork, chantier 15): « Fasting · done / left · Stop »
/// on the Lock Screen and in the Dynamic Island, on the model of the Lift Log banner.
///
/// A SEPARATE activity type from the live HR, the Lift Log and the sync banners: a different question with
/// a different lifetime (a fast runs for 16 hours or more). TIME IS CARRIED AS DATES, never as a formatted
/// string: the widget counts from them with `Text(timerInterval:)` and fills its ring with
/// `ProgressView(timerInterval:)`, both ticking on their own, so the app pushes a new state only when the
/// fast itself changes (its start, its goal, its end). Every word arrives already translated: the
/// extension ships no string catalog.
///
/// iOS ends any Live Activity about eight hours after it started, and only an app on screen may start one:
/// the app starts this banner again whenever it comes to the foreground with a fast still running.
public struct FastingActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// « Fasting · 16h ».
        public var title: String
        public var startedAt: Date
        public var plannedEnd: Date
        /// « left » / « end 12:30 » / « Stop » / « goal reached », localized app-side.
        public var leftLabel: String
        public var endLabel: String
        public var stopLabel: String
        public var goalReachedLabel: String
        /// The goal was met when this state was pushed.
        public var goalReached: Bool

        public init(title: String, startedAt: Date, plannedEnd: Date, leftLabel: String,
                    endLabel: String, stopLabel: String, goalReachedLabel: String, goalReached: Bool) {
            self.title = title
            self.startedAt = startedAt
            self.plannedEnd = plannedEnd
            self.leftLabel = leftLabel
            self.endLabel = endLabel
            self.stopLabel = stopLabel
            self.goalReachedLabel = goalReachedLabel
            self.goalReached = goalReached
        }
    }

    /// Nothing is fixed for the life of a fast: its start and its goal are editable, so everything
    /// travels in `ContentState`.
    public init() {}
}
#endif
