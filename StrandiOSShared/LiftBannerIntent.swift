#if os(iOS)
import AppIntents
import Foundation

/// Where a Lift Log banner button lands in the app (personal fork).
///
/// The intent below is compiled into BOTH the app and the widget extension — the extension needs the type to
/// draw `Button(intent:)`, and iOS runs a `LiveActivityIntent`'s `perform()` in the APP's process. The session
/// lives in the app, so the app registers this handler as it starts (`StrandiOSApp.init`); in the extension it
/// stays nil and is never called.
@MainActor
public enum LiftBannerActionRelay {
    /// Takes the step, pushes the banner's new state and returns once that push has gone out.
    public static var handler: (@MainActor (LiftBannerAction) async -> Void)?
}

/// A button on the Lift Log session's Lock Screen banner or Dynamic Island: done, skip the rest, +30 s, pause,
/// resume.
///
/// `LiveActivityIntent`, not plain `AppIntent`: that is what lets iOS run it from a Live Activity, in the app's
/// process, with the phone locked and NOOP in the background — the same adoption the Sync Strap shortcut uses to
/// start its banner from the background (`SyncStrapIntent`). Hidden from Shortcuts: it only makes sense on the
/// banner of a running session.
public struct LiftBannerActionIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource = "Lift Log banner button"
    public static var isDiscoverable = false
    public static var openAppWhenRun = false

    /// A `LiftBannerAction` raw value.
    @Parameter(title: "Action")
    public var action: String

    public init() {}

    public init(action: LiftBannerAction) {
        self.action = action.rawValue
    }

    /// A launch iOS makes only to run this intent can reach here before the app has built its session; the
    /// handler is then waited for, briefly, rather than the tap being lost.
    @MainActor
    public func perform() async throws -> some IntentResult {
        guard let step = LiftBannerAction(rawValue: action) else { return .result() }
        for _ in 0..<20 {
            if let handler = LiftBannerActionRelay.handler {
                await handler(step)
                return .result()
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return .result()
    }
}
#endif
