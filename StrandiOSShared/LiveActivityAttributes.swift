#if os(iOS)
import Foundation
import ActivityKit

/// Live Activity attributes for an active live-HR / workout session. Shared between the app (which
/// starts/updates the activity) and the widget extension (which renders it on the Lock Screen and in
/// the Dynamic Island).
public struct NOOPActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var bpm: Int?
        public var recovery: Int?
        public var bonded: Bool
        // Effort / strain on NOOP's 0–100 axis (#446) — one more stat in the Dynamic Island expanded
        // region. OPTIONAL with a nil default so an activity started by an older build still decodes.
        public var effort: Int?
        /// "Live HR · zone 1", localized app-side (personal fork). Nil: the title alone.
        public var subtitle: String?
        /// The figure beside the bpm the wearer picked (`LiveHRBannerSide`, "effort" | "charge" | "sleep"), with its
        /// words already localized — the extension has no catalog. All optional, like `effort`: nil `sideKind` is a
        /// banner from an older build, drawn as it always was (Charge and Effort).
        public var sideKind: String?
        public var sideLabel: String?
        public var sideValue: String?
        public var sideDetail: String?

        public init(bpm: Int?, recovery: Int?, bonded: Bool, effort: Int? = nil, subtitle: String? = nil,
                    sideKind: String? = nil, sideLabel: String? = nil, sideValue: String? = nil,
                    sideDetail: String? = nil) {
            self.bpm = bpm
            self.recovery = recovery
            self.bonded = bonded
            self.effort = effort
            self.subtitle = subtitle
            self.sideKind = sideKind
            self.sideLabel = sideLabel
            self.sideValue = sideValue
            self.sideDetail = sideDetail
        }
    }

    /// Static title shown for the session.
    public var title: String

    public init(title: String = "Live HR") {
        self.title = title
    }
}
#endif
