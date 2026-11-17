#if os(iOS)
import Foundation
import ActivityKit
import AppIntents

/// Live Activity attributes for a running habit stopwatch (personal fork, chantier 24 PR C): the habit, the
/// time counting up and Stop, on the Lock Screen and in the Dynamic Island, on the model of the fasting banner.
///
/// TIME IS CARRIED AS A DATE. The widget counts with `Text(timerInterval:)`, which ticks on its own; the app
/// pushes only when the stopwatch itself changes (a start, a corrected start, a stop).
///
/// Every word arrives already translated (`HabitLiveActivityController.habitBannerState`): the widget
/// extension ships no string catalog.
public struct HabitActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var startedAt: Date
        /// The habit's name, as the user wrote it.
        public var title: String
        /// « since 21:48 ».
        public var sinceText: String
        /// The habit's SF Symbol.
        public var symbol: String
        /// « Stop ».
        public var stopLabel: String

        public init(startedAt: Date, title: String, sinceText: String, symbol: String, stopLabel: String) {
            self.startedAt = startedAt
            self.title = title
            self.sinceText = sinceText
            self.symbol = symbol
            self.stopLabel = stopLabel
        }
    }

    public init() {}
}

/// Where the habit banner's Stop lands in the app. Compiled into BOTH the app and the widget extension, like
/// `FastingBannerRelay`: iOS runs a `LiveActivityIntent` in the APP's process, which registers the handler as
/// it starts (`StrandiOSApp.init`); in the extension it stays nil.
@MainActor
public enum HabitBannerRelay {
    /// Stops the running stopwatch now and returns once the banner has followed.
    public static var stopHandler: (@MainActor () async -> Void)?
}

/// The Stop of the habit banner: stops the stopwatch at the moment of the tap. Hidden from Shortcuts.
public struct HabitBannerStopIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource = "Habit banner Stop"
    public static var isDiscoverable = false
    public static var openAppWhenRun = false

    public init() {}

    /// A launch iOS makes only to run this intent can arrive before the app root has registered the handler;
    /// it is waited for briefly rather than the tap being lost.
    @MainActor
    public func perform() async throws -> some IntentResult {
        for _ in 0..<20 {
            if let handler = HabitBannerRelay.stopHandler {
                await handler()
                return .result()
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return .result()
    }
}
#endif
