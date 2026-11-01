import Foundation

// MARK: - Heart-rate curve switch (personal fork)
//
// The persisted switch for the heart-rate curve on the Sleep tab's stage chart (`SleepPhasesChart`). The
// key predates the redesign, so a user who had switched the curve off keeps it off.

enum SleepHROverlay {
    static let enabledKey = "sleep.hrOverlay"
}
