import SwiftUI
import StrandDesign

// MARK: - Power saving (#477)
//
// Lifted out of Settings into its own screen: on iPhone it is a first-class More row (between Test
// Centre and Settings) and on macOS its own sidebar item, so the strap-battery levers are one tap away
// instead of buried in the middle of the Settings scroll. The controls, their prefs and their wiring are
// UNCHANGED — `AppModel.applyPowerSaving()` still reads every value from `PuffinExperiment`, so moving
// the surface cannot alter behaviour.
//
// The master gates the sub-options: the threshold slider, "Pause HRV capture" and "Low refresh" only
// appear (and only apply) while Power saving is on — `applyPowerSaving` ANDs each one with the master.
struct PowerSavingView: View {
    @EnvironmentObject var model: AppModel

    @AppStorage(PuffinExperiment.powerSavingKey) private var powerSavingEnabled = false
    @AppStorage(PuffinExperiment.powerSavingBatteryPctKey) private var powerSavingPct = 20
    /// Stored INVERTED so the default (absent = false) reads as "HRV pause on". The toggle shows `!this`.
    @AppStorage(PuffinExperiment.pauseHrvDisabledKey) private var pauseHrvDisabled = false
    @AppStorage(PuffinExperiment.lowRefreshKey) private var lowRefreshEnabled = false

    var body: some View {
        ScreenScaffold(title: "Power saving",
                       subtitle: "The strap keeps banking data on its own, so nothing is lost — NOOP just talks to it less often to help it last until you can charge it.") {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
                SettingsListGroup {
                    SettingsListToggle(
                        title: String(localized: "Power saving mode"),
                        info: String(localized: "Slows background strap-sync (every 45 min instead of 15) while your strap's battery is low. No data loss — the strap banks everything, so sync just batches into larger, less frequent pulls."),
                        isOn: $powerSavingEnabled)
                        .onChangeCompat(of: powerSavingEnabled) { _ in model.applyPowerSaving() }
                    if powerSavingEnabled {
                        SettingsListDivider()
                        // 10…35 in 5s. 35 buys one more step of strap life than the old 30 ceiling:
                        // the levers engage ~5% earlier in the discharge, at the cost of a slightly
                        // longer stretch of quieter syncing.
                        VStack(alignment: .leading, spacing: 4) {
                            SettingsListValue(title: String(localized: "Kick in at (strap battery)"),
                                              value: "\(powerSavingPct) %", tint: StrandPalette.accent)
                            Slider(
                                value: Binding(get: { Double(powerSavingPct) }, set: { powerSavingPct = Int($0) }),
                                in: 10...35, step: 5,
                                onEditingChanged: { editing in if !editing { model.applyPowerSaving() } }
                            )
                            .tint(StrandPalette.accent)
                            .padding(.bottom, NoopMetrics.space3)
                        }
                        SettingsListDivider()
                        // HRV pause: a sub-option, ON by default when the master is on (stored inverted).
                        SettingsListToggle(
                            title: String(localized: "Pause HRV capture"),
                            info: String(localized: "While your strap's battery is low, stop the always-on background HRV stream — the biggest continuous drain on the strap. A Live screen still shows heart rate, and it re-arms automatically once the strap is charged."),
                            isOn: Binding(get: { !pauseHrvDisabled }, set: { pauseHrvDisabled = !$0 }))
                            .onChangeCompat(of: pauseHrvDisabled) { _ in model.applyPowerSaving() }
                        SettingsListDivider()
                        // Low refresh: a sub-option that applies at ANY charge, not just below the threshold.
                        SettingsListToggle(
                            title: String(localized: "Low refresh"),
                            info: String(localized: "Sync in the background every hour instead of every 15 minutes, whatever the strap's charge — fewer reconnections is the biggest saving on a WHOOP 4.0. Nothing is lost: the strap banks everything and hands it over in larger batches. Pull to sync still runs straight away, and live heart rate is untouched."),
                            isOn: $lowRefreshEnabled)
                            .onChangeCompat(of: lowRefreshEnabled) { _ in model.applyPowerSaving() }
                    }
                }
            }
        }
        .noopEntranceRoot()
    }
}
