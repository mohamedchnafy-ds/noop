#if os(iOS)
import AppIntents
import Foundation

/// What the fast banner's button does (personal fork, chantier 15): one action, stop the fast now.
public enum FastingBannerAction: String, Codable, Hashable, CaseIterable {
    case stop
}

/// Where the fast banner's button lands in the app. Compiled into BOTH the app and the widget extension,
/// like `LiftBannerActionRelay`: the extension needs the type to draw `Button(intent:)`, iOS runs the
/// intent in the APP's process, and the app registers the handler as it starts (`StrandiOSApp.init`).
@MainActor
public enum FastingBannerActionRelay {
    /// Ends the fast through the one resolver and returns once the banner's end has gone out.
    public static var handler: (@MainActor (FastingBannerAction) async -> Void)?
}

/// « Stop » on the fast's Lock Screen banner or in the Dynamic Island. A `LiveActivityIntent`, so iOS runs
/// it from the banner with the phone locked and NOOP in the background. Hidden from Shortcuts.
public struct FastingBannerActionIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource = "Fasting banner button"
    public static var isDiscoverable = false
    public static var openAppWhenRun = false

    /// A `FastingBannerAction` raw value.
    @Parameter(title: "Action")
    public var action: String

    public init() {}

    public init(action: FastingBannerAction) {
        self.action = action.rawValue
    }

    /// A launch iOS makes only to run this intent can reach here before the app has wired its handler; it
    /// is then waited for, briefly, rather than the tap being lost.
    @MainActor
    public func perform() async throws -> some IntentResult {
        guard let step = FastingBannerAction(rawValue: action) else { return .result() }
        for _ in 0..<20 {
            if let handler = FastingBannerActionRelay.handler {
                await handler(step)
                return .result()
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return .result()
    }
}
#endif
