#if os(iOS)
import Foundation
import ActivityKit

/// Live Activity attributes for a running Lift Log session — the minimised session bar, on the Lock
/// Screen and in the Dynamic Island.
///
/// Deliberately a SEPARATE activity type from `NOOPActivityAttributes` (live HR). They answer
/// different questions and have different lifetimes: the HR activity lives as long as the strap is
/// streaming, this one as long as a gym session is open. While a session is running this one is the
/// useful surface — it carries the heart rate too — so the app suppresses the HR activity rather
/// than stacking two banners on the Lock Screen.
///
/// TIME IS CARRIED AS DATES, NOT AS A FORMATTED STRING. The widget renders them with
/// `Text(timerInterval:)`, which ticks on its own without the app pushing anything. Pushing a new
/// content state every second to animate a clock would burn the Live Activity update budget and
/// still look worse.
public struct LiftActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// Amber rest vs green working — the same colour language as the sheet and the bar.
        public var isResting: Bool
        /// The exercise being worked, or rested from.
        public var exercise: String
        /// "Set 2" / "Resting after set 2" — resolved app-side so the wording matches the bar.
        public var status: String
        /// "8 x 30 kg", already unit-converted, because the unit preference lives in the app.
        /// Nil when neither reps nor weight is known.
        public var detail: String?
        public var bpm: Int?
        /// "Next: Set 3 · Bench press", localized APP-SIDE (`LiftSessionController.nextLine`). The widget
        /// extension ships no string catalog, so every word it renders has to arrive already translated
        /// — the same reason `status` and `detail` are strings rather than numbers.
        public var next: String
        /// When the current stage began — the widget counts UP from here while working.
        public var stageStartedAt: Date
        /// When the running rest is due to end; the widget counts DOWN to it. Nil while working.
        public var restEndsAt: Date?
        /// When the session was paused (personal fork): both clocks stand at this instant
        /// (`Text(timerInterval:pauseTime:)`). Nil while it runs.
        ///
        /// This and `buttons` are OPTIONAL with no default to decode: a banner started by an older build
        /// carries neither, and must still decode — as a running session with no buttons.
        public var pausedAt: Date?
        /// The banner's buttons, in order, already worded app-side like every other string here.
        public var buttons: [LiftBannerButton]?

        public var isPaused: Bool { pausedAt != nil }

        public init(isResting: Bool, exercise: String, status: String, detail: String?,
                    bpm: Int?, next: String,
                    stageStartedAt: Date, restEndsAt: Date?,
                    pausedAt: Date? = nil, buttons: [LiftBannerButton]? = nil) {
            self.isResting = isResting
            self.exercise = exercise
            self.status = status
            self.detail = detail
            self.bpm = bpm
            self.next = next
            self.stageStartedAt = stageStartedAt
            self.restEndsAt = restEndsAt
            self.pausedAt = pausedAt
            self.buttons = buttons
        }
    }

    /// Nothing is fixed for the life of a session: everything the banner shows can change mid-session and
    /// travels in `ContentState`.
    public init() {}
}

/// What a button on the Lift Log banner does (personal fork). Each is a step the session already takes from
/// the app (`LiftSessionController`), run in the app's process by `LiftBannerActionIntent`.
public enum LiftBannerAction: String, Codable, Hashable, CaseIterable {
    /// The set or the round being worked is done — the strap double-tap's step.
    case finishRound
    case skipRest
    /// +30 s on the running rest.
    case addRest
    case pause
    case resume
}

/// One button of the Lift Log banner: what it does and its words, localized APP-SIDE (the extension ships no
/// string catalog).
public struct LiftBannerButton: Codable, Hashable {
    public var action: LiftBannerAction
    /// On the Lock Screen: "Skip rest", "Round done", "Pause"…
    public var label: String
    /// In the Dynamic Island, where room is short: "Skip", "+30 s"… Nil shows the icon alone.
    public var compactLabel: String?

    public init(action: LiftBannerAction, label: String, compactLabel: String?) {
        self.action = action
        self.label = label
        self.compactLabel = compactLabel
    }
}
#endif
