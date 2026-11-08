#if os(iOS)
import Foundation
import ActivityKit
import AppIntents

/// Live Activity attributes for a running fast (personal fork, chantier 15 PR C): « Fasting · done / left ·
/// Stop » on the Lock Screen and in the Dynamic Island, on the model of the Lift Log banner.
///
/// TIME IS CARRIED AS DATES. The widget counts with `Text(timerInterval:)` and fills its ring with
/// `ProgressView(timerInterval:)`, which tick on their own; the app pushes only when the fast itself changes
/// (a new start, a new goal, a stop). The stale date is the planned end: from then on `context.isStale` shows
/// the goal reached without any push.
///
/// Every word arrives already translated (`FastingLiveActivityController.fastingBannerState`): the widget
/// extension ships no string catalog.
public struct FastingActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var startedAt: Date
        /// The start plus the goal (`FastingLog.fastingState`).
        public var plannedEnd: Date
        /// « Fasting · 16 h ».
        public var title: String
        /// « end 12:30 ».
        public var endText: String
        /// « Done » over the count-up.
        public var doneLabel: String
        /// « Left » over the countdown.
        public var leftLabel: String
        /// « 16 h reached », once the planned end is past.
        public var reachedText: String
        /// « Stop ».
        public var stopLabel: String

        public init(startedAt: Date, plannedEnd: Date, title: String, endText: String, doneLabel: String,
                    leftLabel: String, reachedText: String, stopLabel: String) {
            self.startedAt = startedAt
            self.plannedEnd = plannedEnd
            self.title = title
            self.endText = endText
            self.doneLabel = doneLabel
            self.leftLabel = leftLabel
            self.reachedText = reachedText
            self.stopLabel = stopLabel
        }
    }

    /// Nothing is fixed for the life of a fast: its start and its goal can be corrected while it runs.
    public init() {}
}

/// Where the banner's Stop lands in the app. Compiled into BOTH the app and the widget extension, like
/// `LiftBannerActionRelay`: iOS runs a `LiveActivityIntent` in the APP's process, which registers the handler
/// as it starts (`StrandiOSApp.init`); in the extension it stays nil.
@MainActor
public enum FastingBannerRelay {
    /// Ends the running fast now and returns once the banner has followed.
    public static var stopHandler: (@MainActor () async -> Void)?
}

/// The Stop of the fasting banner: ends the running fast at the moment of the tap. Hidden from Shortcuts.
public struct FastingBannerStopIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource = "Fasting banner Stop"
    public static var isDiscoverable = false
    public static var openAppWhenRun = false

    public init() {}

    /// A launch iOS makes only to run this intent can arrive before the app root has registered the handler;
    /// it is waited for briefly rather than the tap being lost.
    @MainActor
    public func perform() async throws -> some IntentResult {
        for _ in 0..<20 {
            if let handler = FastingBannerRelay.stopHandler {
                await handler()
                return .result()
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return .result()
    }
}
#endif
