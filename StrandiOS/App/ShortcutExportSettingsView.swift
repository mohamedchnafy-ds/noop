#if os(iOS)
import SwiftUI
import StrandDesign

/// #155 — the opt-in surface for the Apple-Health-free export. Sideloaded installs (free 7-day
/// signing) can't carry the HealthKit entitlement, so HealthKitBridge never runs for them; this
/// toggle instead has NOOP rewrite Documents/noop_sync.txt on every background transition, and the
/// user's Siri Shortcut reads the file and logs the rows into Apple Health. Default OFF.
///
/// Fork chantier 17: the Data domain of Settings carries this switch as a row (`ShortcutExportRow`);
/// this screen stays for the routes that still open it.
struct ShortcutExportSettingsView: View {
    var body: some View {
        ScreenScaffold(title: "Shortcuts Export",
                       subtitle: "Strap data into Apple Health without HealthKit, for sideloaded installs.") {
            SettingsListGroup { ShortcutExportRow() }
        }
        .noopEntranceRoot()
    }
}

/// The export switch as a settings row, with its explanation in a popover.
struct ShortcutExportRow: View {
    @AppStorage(ShortcutHealthExport.enabledKey) private var enabled = false

    var body: some View {
        SettingsListToggle(
            title: String(localized: "Export for Shortcuts"),
            info: String(localized: "When this is on, NOOP rewrites a plain-text file (On My iPhone › NOOP › noop_sync.txt) each time you leave the app: one line per 15 minutes of heart rate, HRV and steps, read straight from your strap. Pair it with the Siri Shortcut that reads the file and logs everything into Apple Health (no HealthKit entitlement needed), so it works on sideloaded installs. The setup guide and the pre-built Shortcut live in the project wiki on GitHub."),
            isOn: $enabled)
    }
}
#endif
