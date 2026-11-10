import SwiftUI
#if os(macOS)
import AppKit
#endif
#if os(iOS)
import UIKit
#endif
import UniformTypeIdentifiers
import PhotosUI
import StrandDesign
import StrandAnalytics
import WhoopStore
// #174: the R22 card reads the flag COUNT off `Whoop5Config.enableR22Sequence` rather than restating it —
// the hardcoded "15" outlived the sequence growing to 16 and declared success a flag early.
import WhoopProtocol

/// Settings — profile (powers zones / calories / recovery), strap connection, and about.
/// Grouped cards on surface.raised with a two-column form feel.
struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var live: LiveState
    @EnvironmentObject var profile: ProfileStore

    /// Profile-photo picker selection (PhotosUI). Cleared back to nil once the bytes are loaded.
    @State private var avatarPickerItem: PhotosPickerItem?

    /// Backup & restore UI state.
    @State private var backupBusy = false
    @State private var backupAlertTitle = ""
    @State private var backupAlertMessage = ""
    @State private var showBackupAlert = false
    /// #1807: a restore refused ONLY for size is recoverable, so it gets its own two-button alert rather
    /// than the shared single-OK one every other backup outcome uses.
    @State private var showOversizeRestoreConfirm = false
    @State private var oversizeRestoreMessage = ""

    /// Opt-in WHOOP 5/MG "R22" deep-data unlock (off by default) — the one probe that writes a
    /// persistent feature flag to the strap. See [PuffinExperiment.deepDataKey]. (#174)
    @AppStorage(PuffinExperiment.deepDataKey) private var deepDataEnabled = false

    /// #174: set when the deep-data switch is turned OFF, so the app can OFFER to clear the flags on the
    /// strap instead of silently leaving them set. The switch alone has never written anything in either
    /// direction — it gates sends — so turning it off used to change nothing on the hardware while reading
    /// like an undo. Asking is the right shape rather than writing automatically: the strap may not be
    /// connected, and a write to bonded hardware is not something a toggle should do unannounced.
    @State private var confirmingDeepDataDisable = false

    /// #103 opt-in: surfaces the WHOOP 5/MG `spo2_candidate_82` nightly mean in the Blood Oxygen tile
    /// as a "strap estimate (unverified)" fallback when no calibrated `spo2Pct` exists. Display-only —
    /// writes nothing to the strap. See [PuffinExperiment.spo2CandidateDisplayKey].
    @AppStorage(PuffinExperiment.spo2CandidateDisplayKey) private var spo2CandidateDisplayEnabled = false
    @AppStorage(AppModel.ouraAllDayLiveHRKey) private var ouraAllDayLiveHREnabled = false   // item 27

    /// #1545 opt-in: score Effort with Banister's exponential TRIMP instead of Edwards' heart-rate zones.
    /// Default OFF — it re-scores the whole window against a different recipe. See
    /// [PuffinExperiment.banisterEffortKey].
    @AppStorage(PuffinExperiment.banisterEffortKey) private var banisterEffortEnabled = false

    /// Opt-in "Continuous HRV capture" (off by default) — holds the dense realtime stream armed 24/7 so
    /// the strap banks beat-to-beat R-R for better overnight HRV/recovery/sleep, at a battery cost.
    /// See [PuffinExperiment.keepRealtimeForDataKey].
    @AppStorage(PuffinExperiment.keepRealtimeForDataKey) private var continuousHrvEnabled = false

    /// #927 "Overnight only" refinement of Continuous HRV capture (off by default): arm the stream only
    /// inside the nightly quiet-hours window instead of 24/7. Composed with the base toggle (base on +
    /// this off = ALWAYS, the pre-#927 behaviour); existing installs are pinned to OFF by
    /// `PuffinExperiment.migrateContinuousHrvOvernightDefault()` at launch, so they still see no change.
    ///
    /// The `@AppStorage` default MUST match `PuffinExperiment.continuousHrvOvernightOnlyEnabled` (#1008).
    /// They read the same key by different routes, so a mismatch shows the toggle OFF on a fresh install
    /// while capture is actually overnight-only — and a user "correcting" that would write an explicit
    /// false and get the 24/7 behaviour they were trying to avoid.
    @AppStorage(PuffinExperiment.continuousHrvOvernightOnlyKey) private var continuousHrvOvernightOnly = true

    // #477 Power saving moved OUT of this screen into `PowerSavingView` — a first-class More row on
    // iPhone (between Test Centre and Settings) and its own sidebar item on macOS. Its `@AppStorage`
    // keys live there now; nothing here reads them.

    /// "Experimental sleep staging (V2)" (ON by default, promoted after the 44-subject cross-subject
    /// benchmark). When on, detected nights are re-staged with `SleepStagerV2` (the transparent
    /// cardiorespiratory recipe) instead of the older V1 stager. Read at the staging call site in
    /// `Repository`. See [PuffinExperiment.experimentalSleepV2Key].
    @AppStorage(PuffinExperiment.experimentalSleepV2Key) private var experimentalSleepV2Enabled = true

    /// "Motion-aware wake refinement" (#364 follow-up, OFF by default). A post-pass over the already-staged
    /// hypnogram: reclassifies a scored WAKE segment to `light` when its per-minute step-tick cadence shows
    /// no locomotion and its per-minute gravity posture is stable outside a minority of isolated burst
    /// minutes. Self-gates on OBSERVED gravity + step density (#345) — a no-op on a sparse night (e.g.
    /// WHOOP 4.0) regardless of this switch. See [PuffinExperiment.motionAwareWakeKey].
    @AppStorage(PuffinExperiment.motionAwareWakeKey) private var motionAwareWakeEnabled = false

    // Display preferences. `units.system` remains the body-measurement choice for compatibility;
    // exercise distance/pace can override it independently. Stored data is always SI.
    /// #1821: Clock format. Defaults to `.system`, so upgrading changes nobody's displayed times.
    /// #1841: shared with Android by name and meaning; each platform keeps its own store. Default FALSE
    /// on Apple (Android defaults true) because the system behaviour may not fire on our
    /// `NavigationStack(path:)` tabs — see RootTabView.
    /// The Coach master switch, under the same `noop.` key Android writes. Default ON, so nothing changes
    /// for an install that never opens this row. Read by `RootTabView` (the tab), Today (the launcher card)
    /// and `CoachBriefScheduler` (the daily background brief).
    @AppStorage("noop.coachEnabled") private var coachEnabled = true
    @AppStorage("noop.bottomBarAutoHide") private var bottomBarAutoHide = false
    @AppStorage(ClockFormatPreference.defaultsKey)
    private var clockFormatRaw = ClockFormatPreference.system.rawValue
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.distanceSystemKey) private var distanceSystemRaw = ""
    @AppStorage(UnitPrefs.temperatureKey) private var temperatureRaw = ""
    @AppStorage(UnitPrefs.skinTempDisplayKey) private var skinTempDisplayRaw = ""   // #1846
    // Effort display scale (#268). Display-only — Effort stays stored 0–100, this only chooses whether
    // it's shown on NOOP's 0–100 axis or WHOOP's 0–21 Day Strain axis.
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    @AppStorage(UnitPrefs.hrvWindowKey) private var hrvWindowRaw = HrvWindow.whole.rawValue
    // Live-HR Live Activity (Lock Screen + Dynamic Island), iOS only (#336). Default on.
    @AppStorage(UnitPrefs.liveActivityKey) private var liveActivityEnabled = true
    // Strap-sync Live Activity, iOS only. Separate from the live-HR one on purpose. Default on.
    @AppStorage(UnitPrefs.syncLiveActivityKey) private var syncLiveActivityEnabled = true
    @AppStorage(UnitPrefs.liftLiveActivityKey) private var liftLiveActivityEnabled = true
    @AppStorage(DayCycleMode.storageKey) private var dayCycleModeRaw = DayCycleMode.sleepOnset.rawValue
    // Alternate app icon (iOS only) — false = Titanium (primary AppIcon), true = Blue Titanium
    // ("AppIcon-Navy"). Display-only preference; the live switch goes through setAlternateIconName.
    @AppStorage("appIcon.alt") private var useNavyIcon = false
    // Light/Dark/System theme. Read by both app roots' .preferredColorScheme; default follows the OS.
    @AppStorage(AppearanceMode.storageKey) private var appearanceRaw = AppearanceMode.system.rawValue
    // App-owned copy language. Apple binds a bundle localization at process launch, so this writes the
    // standard AppleLanguages override and takes effect after the user reopens NOOP.
    @AppStorage(AppLanguage.storageKey) private var appLanguageRaw = AppLanguage.system.rawValue
    // "Reduce motion in NOOP" (default OFF): pose every looping animation still and stop the decorative
    // tilt sensor, without needing system Low Power Mode or system Reduce Motion. Apple-only so far —
    // Android has no such toggle yet and its gate reads two signals, not three (#941).
    @AppStorage(QuietMotionPrefs.enabledKey) private var quietMotion = false
    /// Opt-in "Auto-detect workouts" (default OFF). When ON, Today scans the last day or two of HR for a
    /// sustained-elevated window and offers — via a single dismissible card — to save it as a workout.
    /// Nothing is ever created automatically. Mirrors the Android `NoopPrefs.KEY_AUTO_DETECT_WORKOUTS`.
    @AppStorage(PuffinExperiment.autoDetectWorkoutsKey) private var autoDetectWorkoutsEnabled = false

    /// "Journal reminder" (#627, default ON). When ON, Today shows the persistent journal widget
    /// (last-7-days strip + tap-through). Mirrors the Android `NoopPrefs.KEY_JOURNAL_REMINDER_ENABLED`.
    @AppStorage(PuffinExperiment.journalReminderKey) private var journalReminderEnabled = true

    /// Opt-in "Keep screen on during a workout" (default OFF, #703). When ON, the live-workout view
    /// holds the screen awake while a manual recording is running so you can glance at your live HR
    /// without the device dimming. The live-workout view reads this same key. The string is shared
    /// verbatim with the Android twin (SharedPreferences "workoutKeepScreenOn").
    @AppStorage("workoutKeepScreenOn") private var workoutKeepScreenOn = false
    /// Fork chantier 12: 3 · 2 · 1 · Go before a live cardio session (on by default, device-only).
    @AppStorage(WorkoutCountdownPrefs.enabledKey) private var workoutCountdown = true

    /// Opt-in "Keep screen on while syncing" (default OFF, iOS only). `SyncKeepAwake` holds the screen awake
    /// for as long as a strap history sync runs while this is on.
    @AppStorage(ScreenIdle.strapSyncKeepAwakeKey) private var syncKeepScreenOn = false

    /// The strap model the user last picked (same key the scan pickers write). Gates the WHOOP 4.0-only
    /// rename control in the strap card — renaming uses the Harvard command set, which a 5/MG doesn't share.
    @AppStorage("selectedWhoopModel") private var selectedWhoopModelRaw = WhoopModel.whoop4.rawValue
    /// Draft text for the strap-rename field (strap card). Empty placeholder; never pre-seeded so the
    /// current name stays visible separately above it.
    @State private var strapNameDraft = ""

    /// Whether to surface the WHOOP 5/MG-only probes (puffin/R22/broadcast-HR/frame-capture). Gated so a
    /// confident 4.0 owner never sees 5/MG controls that can't touch their strap (#22). The model
    /// preference DEFAULTS to whoop4, so we deliberately do NOT hide on the raw default alone — the same
    /// `"selectedWhoopModel"` key is rewritten to the family that actually advertised when a strap
    /// connects (BLEManager, PR#195), so a real 5/MG owner who never opened the model picker still flips
    /// this true the moment their strap is discovered. We hide the 5/MG block only when the user is
    /// confidently on a 4.0 (pref says whoop4 AND nothing 5/MG is connected). The always-on raw-CSV
    /// diagnostic stays visible on every model regardless.
    private var showFiveMGControls: Bool {
        selectedWhoopModelRaw == WhoopModel.whoop5mg.rawValue
    }

    private var unitSystem: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }
    private var distanceUnitSystem: UnitSystem {
        UnitPrefs.resolveDistance(system: unitSystem, override: distanceSystemRaw)
    }
    private var distanceSystemBinding: Binding<String> {
        Binding(get: { distanceUnitSystem.rawValue }, set: { distanceSystemRaw = $0 })
    }

    /// Raw-sensor CSV export (experimental diagnostic, #308/#276/#322). Holds the last-written file so
    /// macOS can "Reveal in Finder" after a share, mirroring the puffin-capture export.
    @State private var rawCsvBusy = false
    @State private var lastRawCsvURL: URL?

    /// Passive WHOOP 5/MG optical experiment: the picker writes local timestamp markers into the
    /// durable deep-buffer JSONL. It never calls a BLE write path.
    @State private var showOpticalPhasePicker = false
    @State private var opticalPhaseStatus = ""

    /// Confirm gate for the "Recalibrate Charge baseline" action (it re-learns the HRV anchor from tonight).
    @State private var showRecalibrateConfirm = false

    /// "How your scores work" explainer sheet, reachable any time from About.
    @State private var showScoringGuide = false

    /// "How NOOP works" primer sheet (the four-section explainability primer), reachable any
    /// time from About — covers how sleep is sorted, how scores + calibration work, what
    /// recording means, and where the provenance badges come from.
    @State private var showHowNoopWorks = false

    /// Steps-estimate calibration sheet (WHOOP 4.0). Reached from the Profile card's "Steps estimate"
    /// tap-through; explains the estimate, shows the current fit + a recent estimated-vs-phone table,
    /// and offers a manual coefficient override. See [StepsCalibrationSheet].
    @State private var showStepsCalibration = false

    /// iOS environment-diagnostics sheet (device, iOS+build, Data Protection, background refresh,
    /// low-power, sideload + cert expiry). iOS-only; the macOS strap log already carries OS + version.
    @State private var showDiagnostics = false

    // MARK: - Domains (fork chantier 17, step 2)

    /// The domain that is unfolded, if any. One at a time: opening another folds the first.
    @State private var openDomain: SettingsDomain?
    /// The search field. Non-empty = the domains give way to the rows that match.
    @State private var query = ""
    /// Next-backup / battery words shown on the folded headers.
    @AppStorage(PuffinExperiment.powerSavingKey) private var powerSavingEnabled = false
    @AppStorage(PuffinExperiment.powerSavingBatteryPctKey) private var powerSavingPct = 20

    /// `opening` unfolds that domain on arrival (Nutrition › Goals and Health › Fitness Age open
    /// « Profile & body »); nil = every domain folded.
    init(opening: SettingsDomain? = nil) {
        _openDomain = State(initialValue: opening)
    }

    var body: some View {
        ScreenScaffold(title: "Settings") {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
                searchField
                if trimmedQuery.isEmpty {
                    VStack(alignment: .leading, spacing: NoopMetrics.rowSpacing) {
                        ForEach(Array(SettingsDomain.allCases.enumerated()), id: \.element) { index, domain in
                            domainCard(domain).staggeredAppear(index: index)
                        }
                    }
                } else {
                    searchResults
                }
                legalFooter
            }
        }
        .alert(backupAlertTitle, isPresented: $showBackupAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(backupAlertMessage)
        }
        // Title and buttons reuse catalogue strings that already carry all nine locales, rather than
        // minting new copy that would ship English everywhere until someone translated it. The message
        // below is where the specifics live. (#1807)
        .alert("Backup problem", isPresented: $showOversizeRestoreConfirm) {
            Button("Restore") { runImport(allowOversize: true) }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(oversizeRestoreMessage)
        }
        .confirmationDialog("Recalibrate your Charge baseline?",
                            isPresented: $showRecalibrateConfirm, titleVisibility: .visible) {
            Button("Recalibrate") { recalibrateHrvBaseline() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This restarts the roughly 4-night build-up for Charge and your HRV baseline. Your history stays. Use it if a bad first week, like wearing it while sick, set your baseline off.")
        }
        // #174: the switch going OFF is the moment to offer the undo. Declining leaves the flags set and
        // says so — which is still an improvement on the old behaviour, where the same tap silently left
        // them set with no indication either way.
        .confirmationDialog("Clear the R22 flags on your strap?",
                            isPresented: $confirmingDeepDataDisable, titleVisibility: .visible) {
            Button("Clear flags on strap") { model.ble.disableWhoop5DeepData() }
            Button("Just stop sending", role: .cancel) { }
        } message: {
            Text("Turning this switch off only stops NOOP sending the unlock. The flags it already wrote stay on the strap until something clears them. NOOP can write the off value to all 16 now and read each one back so you can see what the strap actually stores. Needs the strap connected and bonded.")
        }
        .confirmationDialog("Mark optical experiment phase",
                            isPresented: $showOpticalPhasePicker, titleVisibility: .visible) {
            ForEach(PuffinOpticalExperimentPhase.allCases, id: \.self) { phase in
                Button(phase.displayName) { markOpticalPhase(phase) }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("A marker starts the selected phase and ends the previous one. This only timestamps the local capture file; it sends nothing to the strap.")
        }
        .sheet(isPresented: $showScoringGuide) {
            ScoringGuideView(onClose: { showScoringGuide = false })
        }
        .sheet(isPresented: $showHowNoopWorks) {
            HowNoopWorksView(onClose: { showHowNoopWorks = false })
        }
        .sheet(isPresented: $showStepsCalibration) {
            StepsCalibrationSheet(repo: model.repo, onClose: { showStepsCalibration = false })
                .environmentObject(profile)
        }
        #if os(iOS)
        .sheet(isPresented: $showDiagnostics) {
            DiagnosticsSheet(onClose: { showDiagnostics = false }, expectations: AnyView(iphoneExpectations))
        }
        #endif
    }

    // MARK: - Search and domain cards

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var searchField: some View {
        HStack(spacing: NoopMetrics.space2) {
            Image(systemName: "magnifyingglass")
                .font(StrandFont.body)
                .foregroundStyle(StrandPalette.textTertiary)
                .accessibilityHidden(true)
            TextField("Search settings", text: $query)
                .textFieldStyle(.plain)
                .font(StrandFont.body)
                .foregroundStyle(StrandPalette.textPrimary)
                .disableAutocorrection(true)
                .accessibilityLabel("Search settings")
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(StrandPalette.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
        }
        .padding(.horizontal, NoopMetrics.space3)
        .frame(minHeight: 44)
        .background(NoopPanelSurface(cornerRadius: NoopVisualStyle.compactRadius))
    }

    /// One domain: its header (tile, name, what it holds, a value when useful, a chevron) and, when
    /// unfolded, its rows inside the same card.
    private func domainCard(_ domain: SettingsDomain) -> some View {
        let isOpen = openDomain == domain
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    openDomain = isOpen ? nil : domain
                }
            } label: {
                HStack(spacing: NoopMetrics.space3) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(domain.tint)
                        .frame(width: 30, height: 30)
                        .overlay(
                            Image(systemName: domain.icon)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(StrandPalette.onDarkPrimary)
                        )
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: domain.titleText)
                            .font(StrandFont.body.weight(.semibold))
                            .foregroundStyle(StrandPalette.textPrimary)
                        Text(verbatim: domain.subtitleText)
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if let value = headerValue(domain), !isOpen {
                        Text(verbatim: value)
                            .font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .lineLimit(1)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(StrandPalette.textTertiary)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 62)
                .contentShape(Rectangle())
            }
            .buttonStyle(LiquidPressStyle())
            .accessibilityLabel(Text(verbatim: domain.titleText))
            .accessibilityValue(isOpen ? "Expanded" : "Collapsed")

            if isOpen {
                ForEach(settingsRows(domain)) { row in
                    rowDivider
                    row.view
                }
            }
        }
        .padding(.horizontal, NoopMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NoopPanelSurface(cornerRadius: NoopMetrics.cardRadius))
    }

    /// The word on the right of a folded header, when there is one worth showing.
    private func headerValue(_ domain: SettingsDomain) -> String? {
        switch domain {
        case .strap:
            return live.batteryPct.map { "\(Int($0.rounded())) %" }
        case .coach:
            return coachEnabled ? String(localized: "On") : String(localized: "Off")
        case .appearance:
            let language = AppLanguage(rawValue: appLanguageRaw) ?? .system
            return language == .system ? String(localized: "System default") : language.autonym
        case .data:
            return MoreSheetReader.moreBackupText(lastMs: FolderBackup.lastBackupMs, now: Date())
        case .help:
            return bundleVersionString
        default:
            return nil
        }
    }

    private struct SettingsSearchGroup: Identifiable {
        let domain: SettingsDomain
        let rows: [SettingsRowItem]
        var id: String { domain.rawValue }
    }

    /// Rows whose name holds the query, from every domain. Only the rows this strap actually shows are
    /// searched (the registry already leaves out what a 4.0 cannot do).
    @ViewBuilder private var searchResults: some View {
        let groups: [SettingsSearchGroup] = SettingsDomain.allCases.compactMap { domain in
            let hits = settingsRows(domain).filter { Self.matches($0.title, trimmedQuery) }
            return hits.isEmpty ? nil : SettingsSearchGroup(domain: domain, rows: hits)
        }
        if groups.isEmpty {
            Text("No setting matches your search.")
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
                .padding(.horizontal, 4)
        } else {
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            openDomain = group.domain
                            query = ""
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(verbatim: group.domain.titleText)
                                .font(StrandFont.footnote.weight(.semibold))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(StrandPalette.textSecondary)
                        .padding(.horizontal, 4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens this domain")
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(group.rows.enumerated()), id: \.element.id) { index, row in
                            if index > 0 { rowDivider }
                            row.view
                        }
                    }
                    .padding(.horizontal, NoopMetrics.cardPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(NoopPanelSurface(cornerRadius: NoopMetrics.cardRadius))
                }
            }
            Text("Tap a domain name to open it.")
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textTertiary)
                .padding(.horizontal, 4)
        }
    }

    private static func matches(_ title: String, _ query: String) -> Bool {
        title.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    /// Legal footer, always at the foot of the page: the medical disclaimer and the protocol credits.
    private var legalFooter: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space3) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(StrandPalette.statusWarning)
                    .font(.system(size: 13))
                    .accessibilityHidden(true)
                Text("NOOP is not a medical device. It is for informational and personal-insight purposes only and is not intended to diagnose, treat, cure or prevent any condition. Talk to a clinician for medical advice.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Built on")
                    .font(StrandFont.footnote.weight(.semibold))
                    .foregroundStyle(StrandPalette.textSecondary)
                attribution(repo: "johnmiddleton12/my-whoop", note: String(localized: "WHOOP 4.0 protocol"))
                attribution(repo: "b-nnett/goose", note: String(localized: "WHOOP 5.0 protocol"))
            }
            Text("Open-source BLE reverse-engineering work. Thank you.")
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textTertiary)
        }
        .padding(.horizontal, 4)
    }

    /// Compact profile-photo control kept inside the Profile card so the optional avatar does not
    /// consume a second top-level settings section. PhotosUI works on both supported platforms.
    private var profilePhotoRow: some View {
        let hasAvatar = profile.hasAvatar
        return VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            HStack(spacing: NoopMetrics.space3) {
                ProfileAvatarView(
                    imageData: profile.avatarImageData,
                    size: NoopMetrics.profileAvatarDiameter
                )
                    .accessibilityLabel(hasAvatar ? "Your profile photo" : "No profile photo set")

                PhotosPicker(selection: $avatarPickerItem, matching: .images) {
                    Text(hasAvatar ? "Change photo" : "Choose photo")
                }
                .buttonStyle(NoopButtonStyle(.secondary, fullWidth: true))

                if hasAvatar {
                    Button {
                        profile.clearAvatar()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(NoopButtonStyle(.tertiary))
                    .accessibilityLabel("Remove photo")
                    .accessibilityHint("Reverts to the default profile icon")
                }
            }

            Text("Optional. Add a photo for your avatar. It stays on \(Platform.deviceNounPhrase) and is never uploaded.")
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        // Load the picked photo's bytes, then hand them to the store (which downscales + persists).
        // Clearing the selection afterwards lets the user re-pick the same photo if they want.
        .onChange(of: avatarPickerItem) { newItem in
            guard let newItem else { return }
            Task {
                let data = try? await newItem.loadTransferable(type: Data.self)
                await MainActor.run {
                    if let data { profile.setAvatar(data) }
                    avatarPickerItem = nil
                }
            }
        }
    }

    /// One-line state for the "Steps estimate" tap-through row: manual, the auto-fit confidence, or a
    /// not-yet-calibrated prompt — so the row reflects the current calibration without opening the sheet.
    private var stepsCalibrationSummary: String {
        if profile.stepsManualCoefficient > 0 { return String(localized: "Manual") }
        if profile.stepsCalibrationCoefficient > 0 {
            return String(localized: "Auto · \(StepsCalibrationFormat.confidenceLabel(profile.stepsCalibrationConfidence)) confidence")
        }
        return String(localized: "Not calibrated")
    }

    /// Numeric weight/height field: tabular value + small +/- stepper.
    private func measureField(value: Binding<Double>, unit: String,
                              range: ClosedRange<Double>, step: Double,
                              format: String, accessibility: String) -> some View {
        HStack(spacing: NoopMetrics.space2) {
            HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.space1) {
                Text(String(format: format, value.wrappedValue))
                    .font(StrandFont.bodyNumber)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .frame(width: NoopMetrics.formValueColumnWidth, alignment: .center)
                Text(unit)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize()
            }
            .fixedSize()
            Stepper(accessibility, value: value, in: range, step: step)
                .labelsHidden()
                .accessibilityLabel(accessibility)
        }
        .fixedSize()
    }

    /// Imperial weight entry: shows pounds, steps in 1-lb increments, and writes the kg equivalent back
    /// to the SI-stored profile. Range mirrors the metric 30…250 kg (≈66…551 lb).
    private func poundsField(weightKg: Binding<Double>) -> some View {
        let lb = Binding<Double>(
            get: { UnitFormatter.kgToPounds(weightKg.wrappedValue) },
            set: { weightKg.wrappedValue = $0 / UnitFormatter.poundsPerKilogram }
        )
        return HStack(spacing: NoopMetrics.space2) {
            HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.space1) {
                Text(String(format: "%.0f", lb.wrappedValue))
                    .font(StrandFont.bodyNumber)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .frame(width: NoopMetrics.formValueColumnWidth, alignment: .center)
                Text("lb")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize()
            }
            .fixedSize()
            Stepper("Weight in pounds", value: lb, in: 66...551, step: 1)
                .labelsHidden()
                .accessibilityLabel("Weight, \(Int(lb.wrappedValue.rounded())) pounds")
        }
        .fixedSize()
    }

    /// Imperial height entry: shows feet′ inches″, steps in whole inches, and writes the cm equivalent
    /// back to the SI-stored profile. Range mirrors the metric 120…230 cm (≈47…91 in).
    private func feetInchesField(heightCm: Binding<Double>) -> some View {
        let inches = Binding<Double>(
            get: { UnitFormatter.cmToInches(heightCm.wrappedValue).rounded() },
            set: { heightCm.wrappedValue = $0 * UnitFormatter.centimetersPerInch }
        )
        let parts = UnitFormatter.cmToFeetInches(heightCm.wrappedValue)
        return HStack(spacing: NoopMetrics.space2) {
            Text("\(parts.feet)′ \(parts.inches)″")
                .font(StrandFont.bodyNumber)
                .foregroundStyle(StrandPalette.textPrimary)
                .frame(width: NoopMetrics.formWideValueColumnWidth, alignment: .center)
            Stepper("Height in inches", value: inches, in: 47...91, step: 1)
                .labelsHidden()
                .accessibilityLabel("Height, \(parts.feet) feet \(parts.inches) inches")
        }
        .fixedSize()
    }

    /// Metric waist entry: 0 = unset (shows a muted "Not set" rather than a misleading 0 cm). Steps in
    /// 1-cm increments; the first increment from unset lands at a sensible 80 cm so the stepper doesn't
    /// crawl up from the range floor. Mirrors `measureField` but tolerant of the optional empty state.
    private func waistCentimetresField(waistCm: Binding<Double>) -> some View {
        let set = waistCm.wrappedValue > 0
        return HStack(spacing: NoopMetrics.space2) {
            HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.space1) {
                Text(set ? String(format: "%.0f", waistCm.wrappedValue) : String(localized: "Not set"))
                    .font(StrandFont.bodyNumber)
                    .foregroundStyle(set ? StrandPalette.textPrimary : StrandPalette.textTertiary)
                    .frame(minWidth: NoopMetrics.formValueColumnWidth, alignment: .center)
                if set {
                    Text("cm")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize()
                }
            }
            .fixedSize()
            Stepper("Waist in centimetres") {
                waistCm.wrappedValue = min(160, (set ? waistCm.wrappedValue : 79) + 1)
            } onDecrement: {
                // Stepping below the 60-cm floor clears it back to unset (optional).
                let next = waistCm.wrappedValue - 1
                waistCm.wrappedValue = next < 60 ? 0 : next
            }
                .labelsHidden()
                .accessibilityLabel(set ? "Waist, \(Int(waistCm.wrappedValue.rounded())) centimetres" : "Waist not set")
        }
        .fixedSize()
    }

    /// Imperial waist entry: 0 = unset (muted "Not set"); otherwise shows whole inches and stores the cm
    /// equivalent — the same metric/imperial treatment as Height. First increment from unset lands near a
    /// sensible 31″. Range mirrors the metric 60…160 cm (≈24…63 in).
    private func waistInchesField(waistCm: Binding<Double>) -> some View {
        let set = waistCm.wrappedValue > 0
        let inches = set ? UnitFormatter.cmToInches(waistCm.wrappedValue).rounded() : 0
        return HStack(spacing: NoopMetrics.space2) {
            HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.space1) {
                Text(set ? "\(Int(inches))" : "Not set")
                    .font(StrandFont.bodyNumber)
                    .foregroundStyle(set ? StrandPalette.textPrimary : StrandPalette.textTertiary)
                    .frame(minWidth: NoopMetrics.formValueColumnWidth, alignment: .center)
                if set {
                    Text("in")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize()
                }
            }
            .fixedSize()
            Stepper("Waist in inches") {
                let nextIn = (set ? inches : 30) + 1
                waistCm.wrappedValue = min(160, nextIn * UnitFormatter.centimetersPerInch)
            } onDecrement: {
                let nextIn = inches - 1
                // Stepping below the ~24″ floor clears it back to unset (optional).
                waistCm.wrappedValue = nextIn < 24 ? 0 : nextIn * UnitFormatter.centimetersPerInch
            }
                .labelsHidden()
                .accessibilityLabel(set ? "Waist, \(Int(inches)) inches" : "Waist not set")
        }
        .fixedSize()
    }

    /// HR-max override: 0 = auto. Shown as a compact tabular value with a stepper.
    private var hrMaxField: some View {
        HStack(spacing: NoopMetrics.space2) {
            HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.space1) {
                Text(profile.hrMaxOverride > 0 ? "\(profile.hrMaxOverride)" : "Auto")
                    .font(StrandFont.bodyNumber)
                    .foregroundStyle(profile.hrMaxOverride > 0
                                     ? StrandPalette.textPrimary
                                     : StrandPalette.textTertiary)
                    .frame(width: NoopMetrics.formValueColumnWidth, alignment: .center)
                Text("bpm")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize()
            }
            .fixedSize()
            Stepper("Max heart rate override",
                    value: $profile.hrMaxOverride, in: 0...230, step: 1)
                .labelsHidden()
                .accessibilityLabel("Max heart rate override, \(profile.hrMaxOverride == 0 ? "automatic" : "\(profile.hrMaxOverride) bpm")")
        }
        .fixedSize()
    }

    /// One personalized zone lower bound (bpm), stepped neighbour-aware (see `Profile.stepHRZoneThreshold`)
    /// so the five bounds stay strictly increasing. Mirrors `hrMaxField`'s compact value + stepper layout.
    private func hrZoneThresholdField(index: Int) -> some View {
        let value = profile.hrZoneThresholds.indices.contains(index) ? profile.hrZoneThresholds[index] : 0
        return HStack(spacing: NoopMetrics.space2) {
            HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.space1) {
                Text("\(value)")
                    .font(StrandFont.bodyNumber)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .frame(width: NoopMetrics.formValueColumnWidth, alignment: .center)
                Text("bpm")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize()
            }
            .fixedSize()
            Stepper("",
                    onIncrement: { profile.stepHRZoneThreshold(at: index, up: true) },
                    onDecrement: { profile.stepHRZoneThreshold(at: index, up: false) })
                .labelsHidden()
                .accessibilityLabel("Zone \(index + 1) starts at \(value) beats per minute")
        }
        .fixedSize()
    }

    #if os(iOS)
    /// Apply the alternate-icon choice. Runs on the main actor (UIKit requirement) and tolerates the
    /// no-op cases (already-set, unsupported); on failure it surfaces the error and reverts the toggle
    /// so the control never disagrees with what's actually on the Home Screen.
    private func applyAppIcon(_ useNavy: Bool) {
        Task { @MainActor in
            let target = useNavy ? "AppIcon-Navy" : nil
            // No-op if iOS already shows the requested icon (avoids a needless system prompt).
            guard UIApplication.shared.supportsAlternateIcons,
                  UIApplication.shared.alternateIconName != target else { return }
            do {
                try await UIApplication.shared.setAlternateIconName(target)
            } catch {
                useNavyIcon = !useNavy
                backupAlertTitle = String(localized: "Couldn't change the app icon")
                backupAlertMessage = error.localizedDescription
                showBackupAlert = true
            }
        }
    }
    #endif

    // MARK: - Strap

    /// Rename the WHOOP 4.0's BLE advertising name. Shows the current name (read back from firmware in
    /// the connect handshake → `LiveState.advertisingName`) and writes a new one via `renameStrap`. The
    /// strap reboots to apply, so the new name lands on the next connect. WHOOP 4.0 only (Harvard).
    @ViewBuilder private var strapNameControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: NoopMetrics.space2) {
                Text("Strap name")
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.textPrimary)
                TrendsInfoButton(label: "Explanation",
                                 text: "Changes the Bluetooth name your WHOOP 4.0 advertises (what you see when pairing). The strap reboots to apply, so the new name appears the next time it connects. WHOOP 4.0 only.")
            }
            Text("Current: \(live.advertisingName ?? "—")")
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
            HStack(spacing: NoopMetrics.space3) {
                TextField("New strap name", text: $strapNameDraft)
                    .textFieldStyle(.plain)
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .padding(.horizontal, NoopMetrics.space3)
                    .padding(.vertical, 9)
                    .background(StrandPalette.surfaceInset, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(StrandPalette.hairline, lineWidth: 1))
                    .disableAutocorrection(true)
                    .accessibilityLabel("New strap name")
                NoopButton("Rename", systemImage: "pencil", kind: .primary) {
                    model.ble.renameStrap(strapNameDraft)
                }
                .disabled(strapNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let status = live.renameStatus {
                Text(status)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
        }
    }

    // Shares LiveState.connectionStatus* with the sidebar footer (RootView) so the two never drift (#266).
    private var strapStatusTitle: String { live.connectionStatusLabel }

    private var strapTone: StrandTone {
        if live.connectionStatusIsActive { return .positive }
        if live.connectionStatusIsIdle { return .warning }
        return .critical
    }

    private var strapStatusDetail: String {
        // encryptedBond, not bonded — see LiveState.connectionStatusLabel. Saying "is paired" for a
        // live-HR-only link contradicts both LiveView's pill and the buzz/alarm rows on this same screen,
        // which correctly refuse and explain that they need the full encrypted bond.
        //
        // A live-HR link falls through to the pairing hint when one is set, and otherwise to "Finishing
        // the secure pairing handshake…", which is accurate HERE because this platform still retries the
        // CLIENT_HELLO on every connect. The #1635 suppression is now ported here too, so once it latches
        // nothing is finishing any more and the old fall-through would describe a handshake that is no
        // longer being attempted. The `bonded && connected` arm below is that fix, matching the Android
        // twin (`SettingsLogic.strapStatusLine`).
        if live.encryptedBond && live.connected {
            return String(localized: "Your strap is paired and sending data. Open Live for a real-time heart rate.")
        }
        // An actionable hint outranks the generic arm: the suppression hint names the one action that
        // restores the handshake, which "not fully paired" alone does not.
        if live.connected, let hint = live.pairingHint { return hint }
        // Live HR over the UNBONDED standard profile (#69). True whenever the handshake is suppressed or
        // simply has not landed, and the honest description either way.
        if live.bonded && live.connected {
            return String(localized: "Live heart rate is streaming, but your strap is not fully paired. The encrypted pairing is what carries motion, skin temperature, SpO₂ and respiratory rate — without it, sleep is staged from heart rate alone. Buzz, alarms and history sync need it too.")
        }
        if live.connected { return String(localized: "Connected. Finishing the secure pairing handshake…") }
        if live.bonded { return String(localized: "Previously paired but not currently connected. Re-scan to reconnect.") }
        return String(localized: "No strap connected. Put your WHOOP nearby and tap Re-scan to pair.")
    }

    private func batteryTone(_ pct: Double) -> StrandTone {
        if pct <= 15 { return .critical }
        if pct <= 30 { return .warning }
        return .positive
    }

    /// Write the recalibration anchor and trigger a recompute. Re-anchors EVERY baseline that feeds
    /// Charge — HRV plus resting HR / respiration / skin temp — by writing now (epoch SECONDS) to both
    /// `noop.hrvBaselineEpoch` and `noop.recoveryBaselineEpoch` via the single cross-platform source of
    /// truth (`Baselines.recalibrateRecoveryBaselines`). No stored day is deleted; only the day the
    /// baselines re-learn from moves. Then re-score + refresh so the change is reflected without a
    /// relaunch (same path as a sleep edit), and Today honestly shows the building/calibrating state.
    private func recalibrateHrvBaseline() {
        Baselines.recalibrateRecoveryBaselines()
        Task {
            await model.intelligence.analyzeRecent()
            await model.repo.refresh()
        }
        backupAlertTitle = String(localized: "Charge baseline recalibrating")
        backupAlertMessage = String(localized: "NOOP will re-learn your baseline from tonight's data onward. Your history is kept, and it takes a few nights to settle.")
        showBackupAlert = true
    }

    // MARK: - Stored values read by the rows

    /// Today's activity-calorie goal in kcal; 0 uses the 14-day average (personal fork, Today v2).
    @AppStorage(TodayEnergy.goalKey) private var activityKcalGoal = 0
    /// Live Sessions (beta) — the silent-guardian in-workout coach. Default ON (the entry itself is
    /// BETA-labelled on the Liquid Today); off removes the Start-session control entirely. Same key the
    /// Today entry reads (`LiveSessionPrefs.betaKey`).
    @AppStorage(LiveSessionPrefs.betaKey) private var liveSessionsBeta = true
    /// Export the last 24h of decoded sensor streams for the connected strap to a CSV, then save (macOS
    /// NSSavePanel) or share (iOS share sheet). This is the only exporter left on this screen: the Puffin
    /// capture export that shared the shape went with the research card in #2417.
    ///
    /// The strap id comes from `repo.deviceId`, NOT `model.deviceId`. The latter is a hardcoded
    /// `let "my-whoop"`; the former is seeded with it and then re-pointed to the registry's active strap
    /// once the store opens (`adoptActiveDeviceId`). This read used the hardcoded one, so after a
    /// remove+re-add — which mints a fresh "whoop-<uuid>" that the Collector writes today's raw under —
    /// the CSV exported the legacy id's streams rather than the strap being worn, silently, in the file
    /// people attach to bug reports. That is #814 on the diagnostic path, and the Android twin of it.
    ///
    /// Read on the MainActor before the Task hop, as `LiveSessionRunner` does, rather than reaching into
    /// the actor-isolated repo from inside the task.
    private func exportRawSensorCSV() {
        rawCsvBusy = true
        let strapId = model.repo.deviceId
        Task {
            let since = Date().timeIntervalSince1970 - 24 * 60 * 60
            guard let store = await model.repo.storeHandle() else {
                await MainActor.run {
                    rawCsvBusy = false
                    backupAlertTitle = String(localized: "Export failed")
                    backupAlertMessage = String(localized: "Couldn't open the local store.")
                    showBackupAlert = true
                }
                return
            }
            do {
                let url = try await store.exportRawCSV(deviceId: strapId, since: since)
                await MainActor.run {
                    rawCsvBusy = false
                    lastRawCsvURL = url
                    #if os(macOS)
                    let panel = NSSavePanel()
                    panel.allowedContentTypes = [.commaSeparatedText]
                    panel.nameFieldStringValue = url.lastPathComponent
                    panel.canCreateDirectories = true
                    guard panel.runModal() == .OK, let dest = panel.url else { return }
                    let fm = FileManager.default
                    do {
                        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
                        try fm.copyItem(at: url, to: dest)
                    } catch {
                        backupAlertTitle = String(localized: "Export failed")
                        backupAlertMessage = error.localizedDescription
                        showBackupAlert = true
                    }
                    #else
                    FileExport.exportFile(at: url)
                    #endif
                }
            } catch {
                await MainActor.run {
                    rawCsvBusy = false
                    backupAlertTitle = String(localized: "Export failed")
                    backupAlertMessage = error.localizedDescription
                    showBackupAlert = true
                }
            }
        }
    }

    private func markOpticalPhase(_ phase: PuffinOpticalExperimentPhase) {
        if model.ble.markWhoop5OpticalPhase(phase) {
            opticalPhaseStatus = String(localized: "Marked: \(phase.displayName)")
        } else {
            opticalPhaseStatus = String(localized: "Marker wasn't saved. Keep frame recording on and try again.")
        }
    }

    #if os(macOS)
    #endif

    private func runExport() {
        backupBusy = true
        Task {
            let result = await DataBackup.runExport(checkpoint: { await model.repo.checkpointForBackup() })
            handleBackup(result)
        }
    }

    private func runImport(allowOversize: Bool = false) {
        backupBusy = true
        Task {
            let result = await DataBackup.runImport(allowOversize: allowOversize)
            handleBackup(result)
        }
    }

    private func runCsvExport() {
        backupBusy = true
        Task {
            let result = await CsvExport.run(repo: model.repo)
            backupBusy = false
            switch result {
            case .cancelled:
                return
            case .exported(let url):
                backupAlertTitle = String(localized: "CSV exported")
                backupAlertMessage = String(localized: "Saved to \(url.lastPathComponent). The zip re-imports into NOOP (Data Sources → WHOOP Export) on any Mac, iPhone, or Android device.")
                showBackupAlert = true
            case .failure(let message):
                backupAlertTitle = String(localized: "Export problem")
                backupAlertMessage = message
                showBackupAlert = true
            }
        }
    }

    @MainActor
    private func handleBackup(_ result: DataBackup.BackupResult) {
        backupBusy = false
        switch result {
        case .cancelled:
            return
        case .exported(let url):
            backupAlertTitle = String(localized: "Backup exported")
            backupAlertMessage = String(localized: "Saved to \(url.lastPathComponent). Copy this file to your other \(Platform.deviceNoun) and use Import there to restore everything.")
            showBackupAlert = true
        case .exportedOversize(let url, let bytes, let limit):
            // #1807: the file is written and worth keeping — say so first, then say what restoring it
            // will ask for. The old behaviour said nothing here and refused at restore, which is the
            // one moment the original is already gone.
            let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
            let cap = ByteCountFormatter.string(fromByteCount: limit, countStyle: .file)
            backupAlertTitle = String(localized: "Backup exported")
            backupAlertMessage = String(localized: "Saved to \(url.lastPathComponent). Your database is \(size), over the \(cap) NOOP restores without asking — the backup is complete and valid, and restoring it will ask you to confirm once.")
            showBackupAlert = true
        case .restoreTooLarge(let name, let limit):
            let cap = ByteCountFormatter.string(fromByteCount: limit, countStyle: .file)
            oversizeRestoreMessage = String(localized: "\(name) is larger than the \(cap) NOOP restores without asking. That limit guards against a malicious archive expanding to fill this \(Platform.deviceNoun) — a backup you exported yourself is not that. Restoring it needs the space the database will take. You'll be asked to choose the file again.")
            showOversizeRestoreConfirm = true
        case .imported:
            backupAlertTitle = String(localized: "Backup imported")
            backupAlertMessage = String(localized: "Your data has been restored. Quit and reopen NOOP for it to take effect.")
            showBackupAlert = true
        case .failure(let message):
            backupAlertTitle = String(localized: "Backup problem")
            backupAlertMessage = message
            showBackupAlert = true
        }
    }

    // MARK: - About

    /// The real marketing version straight from the bundle (CFBundleShortVersionString, set from
    /// project.yml MARKETING_VERSION), so the About pill can never go stale the way a hand-edited
    /// Swift constant can. Mirrors how Android's pill reads BuildConfig.VERSION_NAME. Falls back to
    /// the hand-maintained changelog version only if the Info.plist key is somehow missing.
    private var bundleVersionString: String { UpdateWatch.installedVersion }

    private func attribution(repo: String, note: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(StrandPalette.accent)
                .accessibilityHidden(true)
            Text(repo)
                .font(StrandFont.mono(12))
                .foregroundStyle(StrandPalette.textPrimary)
            Text("· \(note)")
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textTertiary)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - iOS reality & diagnostics (iOS-only)

    #if os(iOS)
    /// Calm, honest "what to expect running NOOP on iPhone" callout — sideloading reality, re-sign
    /// cadence, the unlock-after-reboot (#222) note, background-BLE limits, and beta-iOS caveat. Surfaces
    /// the live sideload-cert expiry when we can read it, with a gentle warning under ~3 days.
    private var iphoneExpectations: some View {
        let diag = IOSDiagnostics.capture()
        let expiry = diag.expiryDaysRemaining()
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "iphone.gen3")
                    .foregroundStyle(StrandPalette.accent)
                    .accessibilityHidden(true)
                Text("Using NOOP on iPhone")
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
            }

            iphoneExpectationLine(String(localized: "This is a sideloaded build, installed outside the App Store. It needs re-signing periodically: roughly every 7 days on a free Apple ID, about a year on a paid developer account."))
            iphoneExpectationLine(String(localized: "After your iPhone reboots, unlock it once. Until you do, iOS keeps NOOP's files locked (Data Protection), so new history can't be written or synced."))
            iphoneExpectationLine(String(localized: "Background Bluetooth has OS limits: iOS may pause NOOP when it's not in the foreground, so keep it open while syncing a fresh strap."))
            iphoneExpectationLine(String(localized: "On a beta version of iOS, things can break that work on the release build."))

            if let days = expiry {
                let warning = days <= 3
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: warning ? "exclamationmark.triangle.fill" : "clock.badge.checkmark")
                        .font(.system(size: 13))
                        .foregroundStyle(warning ? StrandPalette.statusWarning : StrandPalette.textTertiary)
                        .accessibilityHidden(true)
                    Text(expiryMessage(days))
                        .font(StrandFont.footnote)
                        .foregroundStyle(warning ? StrandPalette.statusWarning : StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StrandPalette.surfaceInset,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(StrandPalette.hairline, lineWidth: 1)
        )
    }

    private func expiryMessage(_ days: Int) -> String {
        if days < 0 {
            let expired = -days
            return expired == 1
                ? String(localized: "This sideloaded build expired 1 day ago. Re-sign it to keep it running.")
                : String(localized: "This sideloaded build expired \(expired) days ago. Re-sign it to keep it running.")
        }
        return days == 1
            ? String(localized: "This sideloaded build expires in 1 day. Re-sign to keep it running.")
            : String(localized: "This sideloaded build expires in \(days) days. Re-sign to keep it running.")
    }

    private func iphoneExpectationLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "circle.fill")
                .font(.system(size: 4))
                .foregroundStyle(StrandPalette.textTertiary)
                .padding(.top, 6)
                .accessibilityHidden(true)
            Text(text)
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    #endif

    // MARK: - Shared bits

    /// The hairline between two rows of a settings card (iOS Settings list look, fork chantier 7).
    private var rowDivider: some View {
        Rectangle()
            .fill(StrandPalette.hairline)
            .frame(height: 1)
            .padding(.vertical, 2)
    }
}

// MARK: - The ten domains

/// The ten domains Settings is sorted into (fork chantier 17, step 2). The page folds them all; one
/// opens at a time. Declared at file level so the screens that deep-link into Settings can name one.
enum SettingsDomain: String, CaseIterable, Identifiable, Hashable {
    case profile, strap, sleep, sport, today, coach, notifications, appearance, data, help

    var id: String { rawValue }

    var titleText: String {
        switch self {
        case .profile: return String(localized: "Profile & body")
        case .strap: return String(localized: "Strap")
        case .sleep: return String(localized: "Sleep & recovery")
        case .sport: return String(localized: "Sport")
        case .today: return String(localized: "Today")
        case .coach: return String(localized: "Coach")
        case .notifications: return String(localized: "Notifications & reminders")
        case .appearance: return String(localized: "Language, units & appearance")
        case .data: return String(localized: "Data")
        case .help: return String(localized: "Help & about")
        }
    }

    /// What the domain holds, said before it is opened.
    var subtitleText: String {
        switch self {
        case .profile: return String(localized: "Birth date, sex, weight, height")
        case .strap: return String(localized: "Connection, steps, battery, Siri")
        case .sleep: return String(localized: "Alarms, HRV, sleep phases, Charge")
        case .sport: return String(localized: "Max heart rate, zones, Effort, workouts")
        case .today: return String(localized: "Start of the day, goals, Journal")
        case .coach: return String(localized: "Switch, key, what it reads")
        case .notifications: return String(localized: "Reminders, alerts, Lock Screen")
        case .appearance: return String(localized: "Language, clock, units, theme")
        case .data: return String(localized: "Backup, exports, places, storage")
        case .help: return String(localized: "How it works, test, version")
        }
    }

    var icon: String {
        switch self {
        case .profile: return "person.fill"
        case .strap: return "antenna.radiowaves.left.and.right"
        case .sleep: return "moon.fill"
        case .sport: return "bolt.fill"
        case .today: return "sun.max.fill"
        case .coach: return "sparkles"
        case .notifications: return "bell.fill"
        case .appearance: return "circle.lefthalf.filled"
        case .data: return "externaldrive.fill"
        case .help: return "info.circle.fill"
        }
    }

    /// Design tokens only: each tile borrows the colour its subject already has elsewhere in the app.
    var tint: Color {
        switch self {
        case .profile: return StrandPalette.restRingDeep
        case .strap: return StrandPalette.macroFatDeep
        case .sleep: return StrandPalette.sleepBedtime
        case .sport: return StrandPalette.caloriesActivityDeep
        case .today: return StrandPalette.liquidHeart
        case .coach: return StrandPalette.accent
        case .notifications: return StrandPalette.stressHigh
        case .appearance: return StrandPalette.textTertiary
        case .data: return StrandPalette.intakeDeep
        case .help: return StrandPalette.textSecondary
        }
    }
}

/// One searchable row: a stable id, the domain it lives in, its localised name (what the search reads)
/// and the live control.
private struct SettingsRowItem: Identifiable {
    let id: String
    let domain: SettingsDomain
    let title: String
    let view: AnyView
}

// MARK: - Row registry and builders

extension SettingsView {
    /// The registry: every row of a domain, in order. A row the connected strap cannot use is left out, so
    /// the search never finds what the page does not show.
    fileprivate func settingsRows(_ domain: SettingsDomain) -> [SettingsRowItem] {
        switch domain {
        case .profile: return profileRows()
        case .strap: return strapRows()
        case .sleep: return sleepRows()
        case .sport: return sportRows()
        case .today: return todayRows()
        case .coach: return coachRows()
        case .notifications: return notificationRows()
        case .appearance: return appearanceRows()
        case .data: return dataRows()
        case .help: return helpRows()
        }
    }

    private func entry<V: View>(_ domain: SettingsDomain, _ id: String, _ title: String, _ view: V) -> SettingsRowItem {
        SettingsRowItem(id: "\(domain.rawValue).\(id)", domain: domain, title: title, view: AnyView(view))
    }

    // MARK: Builders

    /// The shell of a row: its name (with the ⓘ and the « Experimental » mark when it has them) on the left,
    /// the control on the right. 52 pt tall, like the mockup.
    private func rowShell<Trailing: View>(_ title: String, info: LocalizedStringKey? = nil,
                                          experimental: Bool = false,
                                          @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(alignment: .center, spacing: NoopMetrics.space3) {
            HStack(spacing: NoopMetrics.space2) {
                Text(verbatim: title)
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let info {
                    TrendsInfoButton(label: "Explanation", text: info)
                }
                if experimental {
                    Text("Experimental")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.deviationOrange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(StrandPalette.deviationOrange.opacity(0.5), lineWidth: 1)
                        )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
                .layoutPriority(1)
        }
        .frame(minHeight: 52)
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>, info: LocalizedStringKey? = nil,
                           experimental: Bool = false) -> some View {
        rowShell(title, info: info, experimental: experimental) {
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .tint(StrandPalette.switchOn)
        }
    }

    private func menuRow<T: Hashable>(_ title: String, info: LocalizedStringKey? = nil,
                                      selection: Binding<T>, options: [(String, T)]) -> some View {
        rowShell(title, info: info) {
            Picker(title, selection: selection) {
                ForEach(options.indices, id: \.self) { index in
                    Text(verbatim: options[index].0).tag(options[index].1)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(StrandPalette.textSecondary)
        }
    }

    /// A row that opens another screen: the name, an optional value, a chevron. No ⓘ here (a button
    /// inside a link would fight it for the tap).
    private func linkRow<D: View>(_ title: String, value: String? = nil,
                                  @ViewBuilder destination: @escaping () -> D) -> some View {
        NavigationLink {
            destination()
        } label: {
            rowShell(title) {
                HStack(spacing: 8) {
                    if let value {
                        Text(verbatim: value)
                            .font(StrandFont.body)
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(StrandPalette.textTertiary)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(LiquidPressStyle())
    }

    /// A row that opens a sheet or runs a navigation of its own.
    private func sheetRow(_ title: String, value: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            rowShell(title) {
                HStack(spacing: 8) {
                    if let value {
                        Text(verbatim: value)
                            .font(StrandFont.body)
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(StrandPalette.textTertiary)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(LiquidPressStyle())
    }

    /// A blue text row that does something (export, import, recalibrate).
    private func actionRow(_ title: String, info: LocalizedStringKey? = nil, disabled: Bool = false,
                           action: @escaping () -> Void) -> some View {
        HStack(spacing: NoopMetrics.space2) {
            Button(action: action) {
                Text(verbatim: title)
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.accent)
            }
            .buttonStyle(.plain)
            .disabled(disabled)
            if let info {
                TrendsInfoButton(label: "Explanation", text: info)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 52)
    }

    private func valueText(_ text: String) -> some View {
        Text(verbatim: text)
            .font(StrandFont.body)
            .foregroundStyle(StrandPalette.textSecondary)
    }

    // MARK: Profile & body

    private func profileRows() -> [SettingsRowItem] {
        let d = SettingsDomain.profile
        let dobTitle = String(localized: "Date of birth")
        let weightTitle = String(localized: "Weight")
        let heightTitle = String(localized: "Height")
        let waistTitle = String(localized: "Waist (optional)")
        return [
            entry(d, "photo", String(localized: "Profile photo"), profilePhotoRow.padding(.vertical, NoopMetrics.space3)),
            entry(d, "dob", dobTitle, rowShell(dobTitle) {
                HStack(spacing: 12) {
                    Text("\(profile.age)")
                        .font(StrandFont.bodyNumber)
                        .foregroundStyle(StrandPalette.textPrimary)
                        .frame(minWidth: 28, alignment: .trailing)
                    // #146: age is derived from the date of birth, so it advances on its own.
                    DatePicker("Date of birth",
                               selection: $profile.dateOfBirth,
                               in: ProfileStore.dateOfBirthRange,
                               displayedComponents: .date)
                        .labelsHidden()
                        .tint(StrandPalette.accent)
                        .accessibilityLabel("Date of birth, age \(profile.age) years")
                }
            }),
            entry(d, "sex", String(localized: "Sex"), menuRow(
                String(localized: "Sex"),
                selection: $profile.sex,
                options: [(String(localized: "Male"), "male"),
                          (String(localized: "Female"), "female"),
                          (String(localized: "Non-binary"), "nonbinary")])),
            entry(d, "weight", weightTitle, rowShell(weightTitle) {
                // Imperial mode steps in pounds and stores the kg equivalent; metric steps in kg.
                if unitSystem == .imperial {
                    poundsField(weightKg: $profile.weightKg)
                } else {
                    measureField(value: $profile.weightKg, unit: "kg",
                                 range: 30...250, step: 0.5, format: "%.1f",
                                 accessibility: String(localized: "Weight in kilograms"))
                }
            }),
            entry(d, "height", heightTitle, rowShell(heightTitle) {
                // Imperial mode steps in whole inches and stores the cm equivalent; metric steps in cm.
                if unitSystem == .imperial {
                    feetInchesField(heightCm: $profile.heightCm)
                } else {
                    measureField(value: $profile.heightCm, unit: "cm",
                                 range: 120...230, step: 1, format: "%.0f",
                                 accessibility: String(localized: "Height in centimetres"))
                }
            }),
            // Waist (optional). An empty waist is valid (0 = unset). VO₂max is always offered (the Uth
            // HR-ratio fallback needs no waist, #1391); a waist upgrades it to the Nes estimate.
            entry(d, "waist", waistTitle, rowShell(
                waistTitle,
                info: "Optional: VO₂max builds from about 4 nights of heart rate; a waist makes it more accurate. The Fitness Age itself doesn't need it. Measure around your middle, at the navel."
            ) {
                if unitSystem == .imperial {
                    waistInchesField(waistCm: $profile.waistCm)
                } else {
                    waistCentimetresField(waistCm: $profile.waistCm)
                }
            }),
        ]
    }

    // MARK: Strap

    private var strapConnectionRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                StatePill("\(strapStatusTitle)", tone: strapTone, pulsing: live.connected)
                if let pct = live.batteryPct {
                    StatePill(live.charging == true
                              ? "Battery \(Int(pct.rounded()))% · Charging"
                              : "Battery \(Int(pct.rounded()))%",
                              tone: batteryTone(pct), showsDot: false)
                }
                Spacer(minLength: 0)
            }
            Text(strapStatusDetail)
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: NoopMetrics.space3) {
                NoopButton("Re-scan", systemImage: "arrow.clockwise", kind: .primary) {
                    model.scan()
                }
                NoopButton("Disconnect", systemImage: "xmark.circle", kind: .secondary) {
                    model.disconnect()
                }
                .disabled(!live.connected && !live.bonded)
            }
        }
        .padding(.vertical, NoopMetrics.space3)
    }

    private func strapRows() -> [SettingsRowItem] {
        let d = SettingsDomain.strap
        var rows: [SettingsRowItem] = [
            entry(d, "connection", String(localized: "Connection"), strapConnectionRow),
        ]
        // Rename: a WHOOP 4.0 that is connected right now (Harvard command set).
        if live.connected && selectedWhoopModelRaw == WhoopModel.whoop4.rawValue {
            rows.append(entry(d, "name", String(localized: "Strap name"),
                              strapNameControl.padding(.vertical, NoopMetrics.space3)))
        }
        // The 4.0 sends no step count: NOOP estimates it from motion and calibrates it to the phone.
        rows.append(entry(d, "stepsEstimate", String(localized: "Steps estimate"),
                          sheetRow(String(localized: "Steps estimate"), value: stepsCalibrationSummary) {
                              showStepsCalibration = true
                          }))
        // 5.0/MG only: the @57 counter divisor. A different thing from the estimate above.
        if showFiveMGControls {
            let title = String(localized: "Step counter divisor")
            rows.append(entry(d, "stepDivisor", title, rowShell(
                title,
                info: "Counter ticks per step. Leave at 1.0 unless your steps run high. On a WHOOP 5/MG they can run very high (10× or more), so this goes up to 30. Walk a known 1,000 steps and divide NOOP's count by the real count to get your value."
            ) {
                HStack(spacing: 10) {
                    Text(String(format: "%.1f", profile.stepTicksPerStep))
                        .font(StrandFont.bodyNumber)
                        .foregroundStyle(StrandPalette.textPrimary)
                        .frame(minWidth: 44, alignment: .trailing)
                    Stepper(title) {
                        profile.stepTicksPerStep = ProfileStore.steppedStepScale(profile.stepTicksPerStep, up: true)
                    } onDecrement: {
                        profile.stepTicksPerStep = ProfileStore.steppedStepScale(profile.stepTicksPerStep, up: false)
                    }
                    .labelsHidden()
                    .accessibilityLabel("Step calibration, \(String(format: "%.1f", profile.stepTicksPerStep)) counter ticks per step")
                }
            }))
        }
        let hrvTitle = String(localized: "Continuous HRV capture")
        rows.append(entry(d, "hrvCapture", hrvTitle,
                          toggleRow(hrvTitle, isOn: $continuousHrvEnabled,
                                    info: "Keeps the detailed beat-to-beat heart-rate stream running all day and night, not just while a live screen is open, so NOOP captures much more for overnight HRV, recovery and sleep. Uses more battery: your strap streams heart rate continuously while connected.")
                            .onChangeCompat(of: continuousHrvEnabled) { on in model.ble.setKeepRealtimeForData(on) }))
        if continuousHrvEnabled {
            let nightTitle = String(localized: "Overnight only")
            rows.append(entry(d, "hrvOvernight", nightTitle,
                              toggleRow(nightTitle, isOn: $continuousHrvOvernightOnly,
                                        info: "Runs the continuous HRV stream only during your quiet hours window (22:00–07:00 by default), roughly halving the battery cost. Daytime Stress readings will be sparser. Note: continuous background HRV capture (including daytime naps) is paused outside this window. For on-demand daytime HRV readings (including naps), use the \"Take an HRV reading\" button on the Live screen.")
                                .onChangeCompat(of: continuousHrvOvernightOnly) { _ in
                                    model.ble.setKeepRealtimeForData(PuffinExperiment.keepRealtimeForDataEnabled)
                                }))
        }
        #if os(iOS)
        let syncTitle = String(localized: "Keep screen on while syncing")
        rows.append(entry(d, "syncAwake", syncTitle,
                          toggleRow(syncTitle, isOn: $syncKeepScreenOn,
                                    info: "Holds the screen awake while NOOP pulls stored history from your strap, so you can watch a long sync finish without the phone locking. Only applies while a sync is running and NOOP is open. The screen sleeps normally the rest of the time. It uses a bit more battery while the screen stays on.")))
        #endif
        rows.append(entry(d, "powerSaving", String(localized: "Power saving"),
                          linkRow(String(localized: "Power saving"),
                                  value: powerSavingEnabled ? "\(powerSavingPct) %" : String(localized: "Off")) {
                              PowerSavingView()
                          }))
        rows.append(entry(d, "automations", String(localized: "Automations"),
                          linkRow(String(localized: "Automations")) { AutomationsView() }))
        #if os(iOS)
        rows.append(entry(d, "siri", String(localized: "Siri & Shortcuts"),
                          linkRow(String(localized: "Siri & Shortcuts")) { SiriShortcutsSettingsView() }))
        #endif
        if showFiveMGControls || model.repo.activeDeviceIsOura {
            let title = String(localized: "Blood Oxygen: strap estimate (WHOOP 5/MG, Oura)")
            rows.append(entry(d, "spo2", title,
                              toggleRow(title, isOn: $spo2CandidateDisplayEnabled,
                                        info: "Your WHOOP 5.0/MG sends a strap-computed SpO₂ percentage (the @82 candidate byte) every second — an 8-night independent validation tracked it at corr +0.99 against the WHOOP app, but two nights on the original test device moved the OPPOSITE direction, so device/firmware variance is unresolved. An Oura ring's own SpO₂ reading runs high on the wire (over 100% on a fifth to a half of samples on a clean night); this instead surfaces the ring's mean with each sample capped at 100% first, which has matched the Oura app's own displayed value on every full night checked against it so far, though only a few nights. Turning this on surfaces whichever applies to your device as \"strap estimate (unverified)\" in the Blood Oxygen tile when no calibrated import exists. It never feeds recovery or illness scoring. WHOOP 4.0 has no @82 stream, so this does nothing there.",
                                        experimental: true)
                                .onChangeCompat(of: spo2CandidateDisplayEnabled) { _ in
                                    // Re-score now so the candidate is computed on the flip, not at the next loop.
                                    Task { await model.intelligence.analyzeRecent(); await model.repo.refresh() }
                                }))
        }
        if model.repo.activeDeviceIsOura {
            let title = String(localized: "Oura ring: all-day heart rate & HRV")
            rows.append(entry(d, "ouraAllDay", title,
                              toggleRow(title, isOn: $ouraAllDayLiveHREnabled,
                                        info: "Your Oura ring only measures daytime heart rate while NOOP keeps it in that mode, and NOOP stops asking whenever the screen has been off for five minutes — which protects the ring's own sleep tracking at night, but also leaves a pocketed phone's day blank on the Heart Rate and HRV charts. On, NOOP keeps asking through the day and stops only for your usual night, learned from your sleep history (an hour before your typical bedtime to an hour after your usual wake), so the night is unchanged. Costs ring battery: the ring runs its own optical sensor all day. Until enough nights are learned it behaves as if off. Off by default.",
                                        experimental: true)))
        }
        return rows
    }

    // MARK: Sleep & recovery

    private func sleepRows() -> [SettingsRowItem] {
        let d = SettingsDomain.sleep
        let hrvTitle = String(localized: "HRV measured over")
        let stagingTitle = String(localized: "Sleep phases (V2)")
        let motionTitle = String(localized: "Wake detection with motion")
        let recalTitle = String(localized: "Recalibrate Charge…")
        return [
            entry(d, "alarms", String(localized: "Alarms"),
                  linkRow(String(localized: "Alarms")) { SmartAlarmView() }),
            // HRV window (#141): the whole night, or deep sleep only. It CHANGES the number, so a switch
            // re-scores and re-baselines like a sleep edit.
            entry(d, "hrvWindow", hrvTitle, menuRow(
                hrvTitle,
                info: "Whole night is NOOP's default measure; Deep sleep pools HRV over slow-wave sleep only, reading lower and matching WHOOP. Switching re-scores your recent nights over the new window and takes effect right away once you have a few nights of data.",
                selection: $hrvWindowRaw,
                options: [(String(localized: "Night"), HrvWindow.whole.rawValue),
                          (String(localized: "Deep sleep"), HrvWindow.deep.rawValue)])
                .onChangeCompat(of: hrvWindowRaw) { _ in
                    // #201/#195: analyzeRecent re-scores the recent nights AND re-folds the baseline.
                    Task { await model.intelligence.analyzeRecent(); await model.repo.refresh() }
                }),
            entry(d, "stagingV2", stagingTitle, toggleRow(
                stagingTitle, isOn: $experimentalSleepV2Enabled,
                info: "A transparent cardiorespiratory recipe that recovers deep and REM better than the older V1 staging, and is now the default. It only changes how already-detected nights are split into stages (detection and scores are unchanged); turn it off to fall back to V1. Takes effect on the next nights staged.")),
            entry(d, "motionWake", motionTitle, toggleRow(
                motionTitle, isOn: $motionAwareWakeEnabled,
                info: "Reviews each scored wake block for real evidence of getting up (walking cadence, a change in body position) instead of just a heart-rate rise. A wake block with no locomotion and a stable posture — a hot night, a brief turn-over — is folded back into light sleep; a real get-up is left alone. Self-checks how much motion detail your strap actually recorded and stays off on a night that's too sparse to trust (older WHOOP 4.0 firmware, mainly). Off by default; takes effect on the next nights staged.",
                experimental: true)),
            entry(d, "recalibrate", recalTitle, actionRow(
                recalTitle,
                info: "Restarts the roughly 4-night build-up for Charge and your HRV baseline from tonight. Use it if a bad first week set your baseline off. Your history stays."
            ) { showRecalibrateConfirm = true }),
        ]
    }

    // MARK: Sport

    private func sportRows() -> [SettingsRowItem] {
        let d = SettingsDomain.sport
        let hrMaxTitle = String(localized: "Max heart rate")
        let zonesTitle = String(localized: "Custom HR zones")
        let effortTitle = String(localized: "Effort calculation")
        let detectTitle = String(localized: "Auto-detect workouts")
        let screenTitle = String(localized: "Keep screen on during a workout")
        let countdownTitle = String(localized: "Countdown before a session")
        let guidedTitle = String(localized: "Guided sessions (beta)")
        var rows: [SettingsRowItem] = [
            entry(d, "hrMax", hrMaxTitle, rowShell(hrMaxTitle) {
                VStack(alignment: .trailing, spacing: 6) {
                    hrMaxField
                    Text(profile.hrMaxOverride > 0
                         ? "Manual override"
                         : "Auto · \(profile.hrMax) bpm (Tanaka)")
                        .font(StrandFont.footnote)
                        .foregroundStyle(profile.hrMaxOverride > 0
                                         ? StrandPalette.accent
                                         : StrandPalette.textTertiary)
                }
            }),
            // Custom HR zones (#531, @kavemang): five personalised inclusive BPM lower bounds replace the
            // conventional %HRmax bands. Off = the effective set stays conventional.
            entry(d, "zones", zonesTitle, toggleRow(
                zonesTitle,
                isOn: Binding(get: { profile.hasCustomHRZones },
                              set: { profile.setCustomHRZonesEnabled($0) }),
                info: "Set the BPM where each zone begins. Turn off to restore the default percentage-of-max zones.")),
        ]
        if profile.hasCustomHRZones {
            for index in profile.hrZoneThresholds.indices {
                let title = String(localized: "Zone \(index + 1) starts")
                rows.append(entry(d, "zone\(index)", title, rowShell(title) {
                    hrZoneThresholdField(index: index)
                }))
            }
        }
        // #1545: Edwards heart-rate zones (default) or Banister's exponential TRIMP. A different thing from
        // the Effort DISPLAY scale, which lives with the units.
        rows.append(entry(d, "effortCalc", effortTitle, menuRow(
            effortTitle,
            info: "Scores Effort on an exponential intensity curve (Banister TRIMP) instead of the default heart-rate zones (Edwards). The default earns nothing below half of your heart-rate reserve, so an hour of lifting — where hard sets average out against the rests — can score close to zero. The exponential curve has no floor and weights short, hard efforts far more heavily. Re-scores your history, and both scales reach the same maximum. Off by default.",
            selection: $banisterEffortEnabled,
            options: [(String(localized: "Zones (Edwards)"), false),
                      (String(localized: "Exponential (Banister)"), true)])
            .onChangeCompat(of: banisterEffortEnabled) { _ in
                // Re-score immediately: the recipe changes stored Effort for EVERY day in the window.
                Task { await model.intelligence.analyzeRecent(); await model.repo.refresh() }
            }))
        rows.append(entry(d, "detect", detectTitle, toggleRow(
            detectTitle, isOn: $autoDetectWorkoutsEnabled,
            info: "After a sync, NOOP looks over your recent heart rate for a sustained, raised stretch that looks like exercise and offers to save it. It only ever suggests. Nothing is saved until you tap Save, and you can dismiss any suggestion. Turning this off stops future suggestions but keeps your existing workout history. Deliberately conservative, so the odd workout may be missed. On \(Platform.deviceNounPhrase) only.")))
        rows.append(entry(d, "screenOn", screenTitle, toggleRow(
            screenTitle, isOn: $workoutKeepScreenOn,
            info: "Holds the screen awake while you're recording a workout, so your live heart rate stays visible without the device dimming. Only applies during a recording. The screen sleeps normally the rest of the time. Leaving it on does use a bit more battery, and means your unlocked screen stays visible for the whole workout, so flip it off if that's a concern.")))
        rows.append(entry(d, "countdown", countdownTitle, toggleRow(
            countdownTitle, isOn: $workoutCountdown,
            info: "3, 2, 1, Go before a live cardio session; the recording starts at Go. A tap on the countdown skips it.")))
        rows.append(entry(d, "guided", guidedTitle, toggleRow(
            guidedTitle, isOn: $liveSessionsBeta,
            info: "Silence-first strap coaching during workouts.",
            experimental: true)))
        return rows
    }

    // MARK: Today

    private func todayRows() -> [SettingsRowItem] {
        let d = SettingsDomain.today
        let dayTitle = String(localized: "Start of the day")
        let goalTitle = String(localized: "Activity goal")
        let journalTitle = String(localized: "Journal card")
        let dayBinding = Binding<DayCycleMode>(
            get: { DayCycleMode.persisted(dayCycleModeRaw) },
            set: { mode in
                dayCycleModeRaw = mode.rawValue
                Task { await model.intelligence.analyzeRecent(); await model.repo.refresh() }
            })
        let dayOptions: [(String, DayCycleMode)] = [(String(localized: "Main sleep"), .sleepOnset),
                                                    (String(localized: "00:00"), .midnight)]
        let dayRow: AnyView
        if dayCycleModeRaw == DayCycleMode.midnight.rawValue {
            dayRow = AnyView(menuRow(dayTitle,
                                     info: "Uses a conventional local calendar day from 00:00 to 00:00.",
                                     selection: dayBinding, options: dayOptions))
        } else {
            dayRow = AnyView(menuRow(dayTitle,
                                     info: "Default. Steps and in-progress Effort restart at the beginning of detected main sleep. Naps do not start a new day; missing sleep falls back to local midnight.",
                                     selection: dayBinding, options: dayOptions))
        }
        return [
            entry(d, "dayStart", dayTitle, dayRow),
            entry(d, "activityGoal", goalTitle, rowShell(
                goalTitle,
                info: "Calories burned through movement and exercise, on top of what your body burns at rest. Set it to zero to use your average over the last 14 full days."
            ) {
                HStack(spacing: 10) {
                    valueText(activityKcalGoal > 0 ? String(localized: "\(activityKcalGoal) kcal a day")
                                                   : String(localized: "Automatic (14-day average)"))
                    Stepper(goalTitle, value: $activityKcalGoal, in: 0...3000, step: 50)
                        .labelsHidden()
                }
            }),
            entry(d, "journal", journalTitle, toggleRow(
                journalTitle, isOn: $journalReminderEnabled,
                info: "Show a Today card reminding you to log your journal")),
            entry(d, "intakeGoal", String(localized: "Intake goal"),
                  linkRow(String(localized: "Intake goal")) { NutritionGoalsView() }),
        ]
    }

    // MARK: Coach

    private func coachRows() -> [SettingsRowItem] {
        let d = SettingsDomain.coach
        let title = String(localized: "AI Coach")
        // The Coach master switch. With it off the tab (or sidebar row) goes, the Today launcher card
        // goes, and the daily brief is cancelled. The saved provider key is kept, so this is a flip.
        return [
            entry(d, "enabled", title, toggleRow(title, isOn: $coachEnabled)
                .onChangeCompat(of: coachEnabled) { on in
                    // Take down what the brief already published, not just stop the next one.
                    CoachBriefScheduler.applyMasterSwitch(on)
                }),
            entry(d, "settings", String(localized: "Coach settings"),
                  linkRow(String(localized: "Coach settings")) { CoachSettingsView() }),
            entry(d, "reads", String(localized: "What the coach reads"),
                  linkRow(String(localized: "What the coach reads")) { CoachDataView() }),
            entry(d, "profile", String(localized: "Coach profile"),
                  linkRow(String(localized: "Coach profile")) { CoachProfileView() }),
        ]
    }

    // MARK: Notifications & reminders

    private func notificationRows() -> [SettingsRowItem] {
        let d = SettingsDomain.notifications
        var rows: [SettingsRowItem] = [
            entry(d, "reminders", String(localized: "Reminders"),
                  linkRow(String(localized: "Reminders")) { RemindersView() }),
            entry(d, "alerts", String(localized: "Strap alerts"),
                  linkRow(String(localized: "Strap alerts")) { AutomationsView() }),
        ]
        #if os(iOS)
        // Live notifications: one switch each. A switch only decides whether its notification is SHOWN:
        // the heart rate is still measured, a session still runs and buzzes, a sync still runs.
        let live = String(localized: "Live heart rate")
        let lift = String(localized: "Lift Log session")
        let sync = String(localized: "Strap sync")
        rows.append(entry(d, "liveHR", live, toggleRow(live, isOn: $liveActivityEnabled, info: "While the strap is connected.")))
        rows.append(entry(d, "liveLift", lift, toggleRow(lift, isOn: $liftLiveActivityEnabled, info: "Your set, rest and heart rate, and the Lock Screen light-up on a double-tap.")))
        rows.append(entry(d, "liveSync", sync, toggleRow(sync, isOn: $syncLiveActivityEnabled, info: "Progress while NOOP pulls history from the strap.")))
        #endif
        return rows
    }

    // MARK: Language, units & appearance

    private func appearanceRows() -> [SettingsRowItem] {
        let d = SettingsDomain.appearance
        let languageTitle = String(localized: "Language")
        let clockTitle = String(localized: "Clock")
        let bodyTitle = String(localized: "Body measurements")
        let distanceTitle = String(localized: "Exercise distance & pace")
        let temperatureTitle = String(localized: "Temperature")
        let skinTitle = String(localized: "Skin temperature")
        let effortTitle = String(localized: "Effort shown on")
        let themeTitle = String(localized: "Theme")
        let motionTitle = String(localized: "Reduce motion in NOOP")
        var rows: [SettingsRowItem] = [
            // App-owned copy language. Apple binds a bundle localization at launch, so the change lands
            // after NOOP is reopened (the ⓘ says so).
            entry(d, "language", languageTitle, menuRow(
                languageTitle,
                info: "Language changes take effect after you reopen NOOP.",
                selection: $appLanguageRaw,
                options: AppLanguage.allCases.map { language in
                    (language == .system ? String(localized: "System default") : language.autonym, language.rawValue)
                })
                .onChangeCompat(of: appLanguageRaw) { AppLanguage.apply($0) }),
            // #1821: an app-owned display convention, not a unit; "System default" is the device's own switch.
            entry(d, "clock", clockTitle, menuRow(
                clockTitle,
                selection: $clockFormatRaw,
                options: [(String(localized: "System default"), ClockFormatPreference.system.rawValue),
                          (String(localized: "12-hour"), ClockFormatPreference.twelveHour.rawValue),
                          (String(localized: "24-hour"), ClockFormatPreference.twentyFourHour.rawValue)])
                // #1829: the resolved clock is memoised, so the write has to drop the memo.
                .onChangeCompat(of: clockFormatRaw) { _ in AppClock.invalidate() }),
            entry(d, "bodyUnits", bodyTitle, menuRow(
                bodyTitle, selection: $unitSystemRaw,
                options: [(String(localized: "Metric"), UnitSystem.metric.rawValue),
                          (String(localized: "Imperial"), UnitSystem.imperial.rawValue)])),
            entry(d, "distanceUnits", distanceTitle, menuRow(
                distanceTitle, selection: distanceSystemBinding,
                options: [(String(localized: "Kilometres"), UnitSystem.metric.rawValue),
                          (String(localized: "Miles"), UnitSystem.imperial.rawValue)])),
            // Three-way: "Follow body" follows body measurements; °C / °F pin it explicitly.
            entry(d, "temperature", temperatureTitle, menuRow(
                temperatureTitle, selection: $temperatureRaw,
                options: [(String(localized: "Follow body"), ""),
                          ("°C", TemperatureUnit.celsius.rawValue),
                          ("°F", TemperatureUnit.fahrenheit.rawValue)])),
            // #1846: lead with a temperature or with the move from your own baseline. Only a PREFERENCE.
            entry(d, "skinTemp", skinTitle, menuRow(
                skinTitle, selection: $skinTempDisplayRaw,
                options: [(String(localized: "Temperature"), ""),
                          (String(localized: "vs baseline"), SkinTempDisplay.Kind.deviation.rawValue)])),
            // #268: display-only; the stored Effort stays 0–100.
            entry(d, "effortScale", effortTitle, menuRow(
                effortTitle, selection: $effortScaleRaw,
                options: [(String(localized: "0-100"), EffortScale.hundred.rawValue),
                          (String(localized: "0-21"), EffortScale.whoop.rawValue)])),
            entry(d, "theme", themeTitle, menuRow(
                themeTitle, selection: $appearanceRaw,
                options: AppearanceMode.allCases.map { ($0.label, $0.rawValue) })),
        ]
        #if os(iOS)
        let iconTitle = String(localized: "App icon")
        rows.append(entry(d, "appIcon", iconTitle, menuRow(
            iconTitle, selection: $useNavyIcon,
            options: [(String(localized: "Default"), false), (String(localized: "Navy"), true)])
            .onChangeCompat(of: useNavyIcon) { applyAppIcon($0) }))
        // #1841: iOS 26 minimises the tab bar to a pill on scroll; below iOS 26 the row would do nothing.
        if #available(iOS 26.0, *) {
            let barTitle = String(localized: "Hide bar when scrolling")
            rows.append(entry(d, "hideBar", barTitle, toggleRow(barTitle, isOn: $bottomBarAutoHide)))
        }
        #endif
        rows.append(entry(d, "reduceMotion", motionTitle, toggleRow(
            motionTitle, isOn: $quietMotion,
            info: "Holds the looping animations still and turns off the motion sensor that drives them. Saves battery. Low Power Mode and the system Reduce Motion setting already do this.")))
        return rows
    }

    // MARK: Data

    private func dataRows() -> [SettingsRowItem] {
        let d = SettingsDomain.data
        let exportTitle = String(localized: "Export a backup")
        let importTitle = String(localized: "Import a backup")
        let csvTitle = String(localized: "Export to CSV")
        let sensorsTitle = String(localized: "Export sensors (CSV)")
        var rows: [SettingsRowItem] = [
            entry(d, "folder", String(localized: "Backup & Sync to a folder…"),
                  linkRow(String(localized: "Backup & Sync to a folder…"),
                          value: MoreSheetReader.moreBackupText(lastMs: FolderBackup.lastBackupMs, now: Date())) {
                      BackupSyncView()
                  }),
            // #644: .noopbak is a plain ZIP, not an encrypted container; the ⓘ says so next to Export.
            entry(d, "export", exportTitle, actionRow(
                exportTitle,
                info: "This is a plain, unencrypted archive — anyone who gets the file can open it with any zip tool. Store it somewhere you trust.",
                disabled: backupBusy
            ) { runExport() }),
            entry(d, "import", importTitle, actionRow(
                importTitle,
                info: "Importing overwrites everything currently on \(Platform.deviceNounPhrase). Your old data is kept in a side file just in case. NOOP needs a relaunch for an import to take effect. Export CSV writes a WHOOP-format zip of your days, sleeps, workouts and journal that re-imports into NOOP on Mac, iPhone, or Android. On-device computed rows are marked APPROXIMATE in its Source column; the full backup stays the lossless restore path.",
                disabled: backupBusy
            ) { runImport() }),
            entry(d, "csv", csvTitle, actionRow(csvTitle, disabled: backupBusy) { runCsvExport() }),
            entry(d, "sensors", sensorsTitle, VStack(alignment: .leading, spacing: 0) {
                actionRow(
                    rawCsvBusy ? String(localized: "Exporting…") : sensorsTitle,
                    info: "Dumps the last 24 hours of decoded per-sample sensor streams (heart rate, R-R, motion, steps, SpO₂, skin temperature, respiration, events) to a single CSV. All on \(Platform.deviceNounPhrase), nothing uploaded. Share it to help prototype and test sleep, activity and strength algorithms.",
                    disabled: rawCsvBusy
                ) { exportRawSensorCSV() }
                #if os(macOS)
                if let url = lastRawCsvURL {
                    actionRow(String(localized: "Reveal in Finder")) {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
                #endif
            }),
        ]
        if backupBusy {
            rows.append(entry(d, "busy", String(localized: "Working…"), HStack(spacing: NoopMetrics.space2) {
                ProgressView().controlSize(.small)
                Text("Working…")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            .frame(minHeight: 44)))
        }
        #if os(iOS)
        // The export switch, inline (it used to be a screen of one switch).
        rows.append(entry(d, "shortcutsExport", String(localized: "Export for Shortcuts"), ShortcutExportRow()))
        #endif
        rows.append(entry(d, "places", String(localized: "Places and location tracking"),
                          linkRow(String(localized: "Places and location tracking")) { PlacesSettingsView() }))
        rows.append(entry(d, "sources", String(localized: "Data Sources"),
                          linkRow(String(localized: "Data Sources")) { DataSourcesView() }))
        rows.append(entry(d, "storage", String(localized: "Storage"),
                          linkRow(String(localized: "Storage")) { StorageView() }))
        return rows
    }

    // MARK: Help & about

    private func helpRows() -> [SettingsRowItem] {
        let d = SettingsDomain.help
        var rows: [SettingsRowItem] = [
            entry(d, "howItWorks", String(localized: "How NOOP works"),
                  sheetRow(String(localized: "How NOOP works")) { showHowNoopWorks = true }),
            entry(d, "scores", String(localized: "How your scores work"),
                  sheetRow(String(localized: "How your scores work")) { showScoringGuide = true }),
            entry(d, "reads", String(localized: "What NOOP reads"),
                  linkRow(String(localized: "What NOOP reads")) { NoopLimitationsView() }),
        ]
        #if os(iOS)
        // The iOS environment dump (device, build, Data Protection, sideload expiry) with what to expect
        // from a sideloaded build. For bug reports.
        rows.append(entry(d, "iphone", String(localized: "iPhone status"),
                          sheetRow(String(localized: "iPhone status")) { showDiagnostics = true }))
        #endif
        rows.append(entry(d, "testCentre", String(localized: "Test Centre"),
                          linkRow(String(localized: "Test Centre")) { TestCentreView() }))
        let versionTitle = String(localized: "App version")
        rows.append(entry(d, "version", versionTitle, rowShell(versionTitle) { valueText(bundleVersionString) }))
        return rows
    }
}

// MARK: - Advanced disclosure (S3)

/// The persisted defaults for the Settings "Advanced" disclosure. Pulled out so the one fact that must
/// never regress, that a fresh install lands COLLAPSED, is a single testable constant. The key matches
/// the Android `SettingsDisclosurePrefs.KEY` suffix so a backup/restore round-trip carries the choice.
enum SettingsDisclosureDefaults {
    static let advancedOpenKey = "settingsAdvancedOpen"
    static let advancedOpenDefault = false
}


// MARK: - iOS diagnostics sheet

#if os(iOS)
/// A read-only environment dump for bug reports: device, iOS+build, Data Protection (#222),
/// background refresh, low-power, sideload + cert expiry — with a one-tap Copy.
private struct DiagnosticsSheet: View {
    let onClose: () -> Void
    /// « Using NOOP on iPhone »: what to expect from a sideloaded build, shown above the dump.
    let expectations: AnyView

    /// Captured once at presentation; a snapshot, not a live monitor.
    private let lines: [String] = IOSDiagnostics.capture().summaryLines()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("iPhone status").font(StrandFont.title2)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text("Attach this to a bug report.").font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(StrandPalette.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            .padding(20)

            Divider().overlay(StrandPalette.hairline)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    expectations
                    if lines.isEmpty {
                        Text("No iOS diagnostics available.")
                            .font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.textTertiary)
                    } else {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(StrandFont.mono(12))
                                .foregroundStyle(StrandPalette.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(StrandPalette.surfaceInset,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(20)
            }
            #if os(iOS)
            // #697/#horizontal-swipe parity, see ScreenScaffold.
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            #endif

            Divider().overlay(StrandPalette.hairline)

            HStack {
                Spacer()
                Button {
                    // UIPasteboard via the shared cross-platform wrapper.
                    PlatformPasteboard.copy(lines.joined(separator: "\n"))
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .frame(minWidth: 120)
                }
                .buttonStyle(NoopButtonStyle(.primary))
                .disabled(lines.isEmpty)
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(StrandPalette.surfaceBase)
    }
}
#endif

// MARK: - Steps estimate calibration

/// Small shared formatters for the steps-estimate calibration UI — kept apart from the sheet so the
/// Profile-card summary row and the sheet agree on the confidence wording. Mirrors the Android
/// `StepsCalibrationFormat` object.
enum StepsCalibrationFormat {
    /// A 0–1 confidence as Low / Medium / High — the honest read-out the sheet and the summary row share.
    /// Thirds: < 0.34 Low, < 0.67 Medium, else High. A manual coefficient is confidence 1.0 → "High".
    static func confidenceLabel(_ confidence: Double) -> String {
        switch confidence {
        case ..<0.34: return String(localized: "Low")
        case ..<0.67: return String(localized: "Medium")
        default:      return String(localized: "High")
        }
    }
}

/// One recent day's estimated-vs-phone steps comparison row, for the sheet's accuracy table.
private struct StepsComparisonRow: Identifiable {
    let day: String          // yyyy-MM-dd
    let estimated: Int
    let actual: Int
    var id: String { day }
    /// Signed error of the estimate against the phone count, as a percentage (estimate − actual) / actual.
    var errorPct: Double { actual > 0 ? Double(estimated - actual) / Double(actual) * 100 : 0 }
}

/// WHOOP 4.0 steps-ESTIMATE calibration — honest explainer + current fit + a recent estimated-vs-phone
/// table + a manual coefficient override with a live preview. Presented as a sheet from Settings →
/// Profile → "Steps estimate". Reads the SAME data the engine fits against (the computed `steps_est`
/// series and the phone's `steps`), never recomputing the headline. Mirrors Android `StepsCalibrationScreen`.
// Internal (not file-private) so the Today Steps tile can present the SAME calibration sheet directly
// when it's showing an ESTIMATE for a WHOOP 4.0 user — one shared entry point, no duplicated screen (H6).
struct StepsCalibrationSheet: View {
    let repo: Repository
    let onClose: () -> Void
    @EnvironmentObject var profile: ProfileStore

    /// Recent days that have BOTH an estimate and a real phone step count, newest first — the accuracy table.
    @State private var comparison: [StepsComparisonRow] = []
    /// A representative recent motion volume (median of recent days' motion), used so the manual-coefficient
    /// preview reflects a TYPICAL day. nil until loaded / no recent estimated day with a known motion.
    @State private var sampleMotion: Double?

    /// The draft manual coefficient the slider edits, committed to ProfileStore on release. 0 = auto-fit.
    @State private var draftManual: Double = 0
    @State private var didLoad = false

    /// The strap has banked no motion, and we have looked.
    ///
    /// Named once because two places depend on it and they must stay exactly complementary: the
    /// no-motion banner appears, and the calibration countdown does NOT. Written as two separate
    /// expressions they drifted immediately — the guard's first draft tested `sampleMotion == nil`
    /// alone, which is also true during the load, so the countdown vanished in a window where the
    /// banner had not appeared yet and the card explained nothing at all.
    private var strapHasNoMotion: Bool { didLoad && sampleMotion == nil }

    /// #107: the sheet's guidance depends on the strap family. A WHOOP 4.0 streams motion automatically, so
    /// "let it sync" is right; a 5/MG only streams motion once the experimental deep-data unlock is on, so
    /// the 4.0 advice is futile there and the empty state must say so instead.
    @AppStorage("selectedWhoopModel") private var selectedWhoopModelRaw = WhoopModel.whoop4.rawValue
    @AppStorage(PuffinExperiment.deepDataKey) private var deepDataEnabled = false
    private var is5MG: Bool { selectedWhoopModelRaw == WhoopModel.whoop5mg.rawValue }

    /// The coefficient the slider's max anchors to — generous headroom over whatever the auto-fit found so
    /// a manual nudge in either direction is reachable. Floor keeps the slider usable before any fit.
    private var sliderMax: Double {
        max(profile.stepsCalibrationCoefficient, profile.stepsManualCoefficient, 50) * 2
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(StrandPalette.hairline)
            ScrollView {
                VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
                    explainerCard
                    if strapHasNoMotion { noMotionNote }
                    currentFitCard
                    comparisonCard
                    manualAdjustCard
                }
                .padding(20)
            }
            #if os(iOS)
            // #697/#horizontal-swipe parity, see ScreenScaffold.
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            #endif
            Divider().overlay(StrandPalette.hairline)
            footerBar
        }
        #if os(macOS)
        .frame(width: 560, height: 680)
        #else
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .noopSheetPresentation(largeFirst: true)
        #endif
        .background(StrandPalette.surfaceBase)
        .task { await loadIfNeeded() }
    }

    // MARK: Header / footer

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("STEPS ESTIMATE").font(StrandFont.overline)
                    .tracking(StrandFont.overlineTracking)
                    .foregroundStyle(StrandPalette.textTertiary)
                Text("Calibrate your steps").font(StrandFont.screenTitle)
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(is5MG ? "WHOOP 5.0 / MG · motion → steps" : "WHOOP 4.0 · motion → steps").font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(20)
    }

    private var footerBar: some View {
        HStack {
            Spacer()
            Button(action: onClose) {
                Text("Done").frame(minWidth: 120)
            }
            .buttonStyle(NoopButtonStyle(.primary))
            .keyboardShortcut(.defaultAction)
        }
        .padding(NoopMetrics.space4)
    }

    // MARK: Cards

    /// The honest "it's an estimate, not a step counter" framing — reused verbatim from the engine doc.
    private var explainerCard: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("How this works", systemImage: "figure.walk.motion")
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(is5MG
                     ? String(localized: "NOOP estimates your steps from your WHOOP's stored motion, calibrated to your phone's step count. It's an estimate, not a hardware step counter; normal WHOOP 5/MG history sync supplies the motion data.")
                     : String(localized: "NOOP estimates your steps from your WHOOP's motion, calibrated to your phone's step count. It's an estimate, not a step counter. A WHOOP 4.0 doesn't transmit steps."))
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("On the days your phone also counted steps, NOOP learns how much your motion maps to steps, then applies that to the strap-only days. The more matching days it has, the more it trusts the estimate.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Shown when the strap has banked NO motion yet (sampleMotion is nil) — the real reason a fresh
    /// WHOOP 4.0 shows zero steps (#37 bringiton321). Steps are built from the strap's synced motion
    /// history, so without a backfill there is nothing to estimate from — calibration can't help yet.
    ///
    /// #107: family-aware. A 4.0 streams motion automatically → "let it sync" is right. A 5/MG only streams
    /// motion once the experimental deep-data unlock is ON — so on a 5/MG the honest advice is "turn that on
    /// and reconnect", not "wait for a sync" (which never comes). Imports don't supply strap motion either.
    private var noMotionNote: some View {
        NoopCard(tint: StrandPalette.metricAmber) {
            VStack(alignment: .leading, spacing: 10) {
                Label("No motion synced yet", systemImage: "antenna.radiowaves.left.and.right.slash")
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(noMotionLead)
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(noMotionAction)
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The "why it's empty" line — a 5/MG needs the deep-data unlock before it streams motion at all.
    private var noMotionLead: String {
        if is5MG {
            return String(localized: "We're not seeing motion from your WHOOP 5.0 / MG yet. Keep NOOP connected and let strap history finish syncing; the experimental R22 flags are not required. Account or Apple Health imports do not contain the raw strap motion this estimate needs.")
        }
        return String(localized: "We're not seeing any motion from your strap yet. Steps are estimated from your WHOOP's banked motion history, so your strap needs to sync that history before NOOP has anything to count.")
    }

    /// The "what to do" line — 5/MG points at the deep-data toggle (unless it's already on, then just sync).
    private var noMotionAction: String {
        if is5MG && !deepDataEnabled {
            return String(localized: "Open NOOP near the strap and let WHOOP 5/MG history finish syncing. The step estimate and calibration fill in once enough stored motion has arrived; the legacy R22 experiment is not required.")
        }
        if is5MG {
            return String(localized: "Deep data is on — open NOOP near your strap and let it sync its motion history (a full first-run sync can take a while). Once a day or two of motion lands, your step estimate and the calibration below fill in.")
        }
        return String(localized: "Open NOOP near your strap and let it catch up (a full history sync can take a while on first run). Once a day or two of motion lands, your step estimate and the calibration below will start to fill in.")
    }

    /// The current calibration read-out: coefficient, sample days, and a Low/Medium/High confidence —
    /// or, if nothing's fit yet and no manual value is set, an honest "what we still need" prompt.
    private var currentFitCard: some View {
        NoopCard(tint: StrandPalette.accent) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Current calibration").strandOverline()
                if profile.stepsCalibrationCoefficient > 0 || profile.stepsManualCoefficient > 0 {
                    let coeff = profile.stepsManualCoefficient > 0
                        ? profile.stepsManualCoefficient : profile.stepsCalibrationCoefficient
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(String(format: "%.1f", coeff))
                            .font(StrandFont.number(30))
                            .foregroundStyle(StrandPalette.accent)
                        Text("steps per motion unit")
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textTertiary)
                    }
                    if profile.stepsManualCoefficient > 0 {
                        statLine(String(localized: "Source"), String(localized: "Manual (you set this by hand)"))
                    } else {
                        statLine(String(localized: "Fitted from"),
                                 profile.stepsCalibrationSampleDays == 1
                                     ? String(localized: "1 day your phone also counted")
                                     : String(localized: "\(profile.stepsCalibrationSampleDays) days your phone also counted"))
                        statLine(String(localized: "Confidence"), "\(StepsCalibrationFormat.confidenceLabel(profile.stepsCalibrationConfidence)) · \(Int((profile.stepsCalibrationConfidence * 100).rounded()))%")
                    }
                } else {
                    Text("Not calibrated yet")
                        .font(StrandFont.bodyNumber)
                        .foregroundStyle(StrandPalette.textPrimary)
                    // Only ask for phone-step days when phone-step days are what is actually missing.
                    //
                    // A step estimate is `motion * coefficient` (`StepsEstimateEngine.estimate`) and a
                    // calibration point is the ratio `steps / motion`, so BOTH halves are required. With no
                    // banked strap motion neither the estimate nor the fit can move however many days the
                    // phone counts. The countdown below then names the half the user already has and hides
                    // the half they do not — a field report asked whether entering Apple Health steps by
                    // hand would start the calibration, which is exactly the conclusion it invites.
                    //
                    // The no-motion banner at the top of this sheet already explains the real blocker, so
                    // the honest move is to stop competing with it rather than to add more copy.
                    if !strapHasNoMotion {
                    // #589: a concrete countdown instead of a vague "a few days". Headline comes straight
                    // from the engine's needsMoreDays state so the wording matches the Today steps tile.
                    // #693: drive `have` off `profile.stepsCalibrationSampleDays` — the value the engine
                    // persists for the not-yet-calibrated case (IntelligenceEngine.swift sets it to the
                    // usable-day `have`, the SAME source the Today tile reads). `usableMatchedDays` can't be
                    // used here: `loadIfNeeded` early-returns before computing it when coeff == 0 (no fit
                    // yet), so it would always read 0 and the card was stuck on "Need 3 more days".
                    Text(StepsEstimateEngine.CalibrationStatus
                        .needsMoreDays(have: profile.stepsCalibrationSampleDays,
                                       need: StepsEstimateEngine.minCalibrationDays)
                        .headline)
                        .font(StrandFont.bodyNumber)
                        .foregroundStyle(StrandPalette.accent)
                    Text("These are the days where your phone also counted steps, so NOOP can learn how your motion maps to steps. Or set the coefficient manually below.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// The accuracy table: recent days that have BOTH an estimate and a phone count, side by side, so the
    /// user can SEE how close the estimate runs. Empty until enough both-have days exist.
    private var comparisonCard: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Estimated vs your phone").strandOverline()
                if comparison.isEmpty {
                    Text("No days yet where both NOOP and your phone counted steps. Once your phone logs a few days alongside the strap, they'll appear here so you can see how close the estimate is.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    // Column header.
                    HStack {
                        Text("Day").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Est.").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                            .frame(width: 64, alignment: .trailing)
                        Text("Phone").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                            .frame(width: 64, alignment: .trailing)
                        Text("Δ").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                            .frame(width: 52, alignment: .trailing)
                    }
                    ForEach(comparison) { row in
                        HStack {
                            Text(Self.shortDay(row.day))
                                .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(Self.grouped(row.estimated))
                                .font(StrandFont.captionNumber).foregroundStyle(StrandPalette.textPrimary)
                                .frame(width: 64, alignment: .trailing)
                            Text(Self.grouped(row.actual))
                                .font(StrandFont.captionNumber).foregroundStyle(StrandPalette.textPrimary)
                                .frame(width: 64, alignment: .trailing)
                            Text(String(format: "%+.0f%%", row.errorPct))
                                .font(StrandFont.captionNumber)
                                .foregroundStyle(abs(row.errorPct) <= 15
                                                 ? StrandPalette.metricCyan : StrandPalette.statusWarning)
                                .frame(width: 52, alignment: .trailing)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(Self.shortDay(row.day)): estimated \(row.estimated) steps, phone \(row.actual) steps, \(Int(row.errorPct.rounded())) percent difference")
                    }
                    Text("These days are excluded from the estimate (your phone's real count is shown instead). They're here only so you can judge the estimate's accuracy.")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
        }
    }

    /// Manual override: a slider bound to a draft, committed on release, with a live preview of what a
    /// typical recent day would estimate at the chosen coefficient. 0 returns to auto-fit.
    private var manualAdjustCard: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Adjust manually").strandOverline()
                Text("Override the automatic fit with your own steps-per-motion value. Useful if your phone has no step history to learn from, or the estimate runs consistently high or low. Set it back to auto by dragging to the far left.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(draftManual > 0 ? String(format: "%.1f", draftManual) : String(localized: "Auto"))
                        .font(StrandFont.number(24))
                        .foregroundStyle(draftManual > 0 ? StrandPalette.accent : StrandPalette.textSecondary)
                    Text(draftManual > 0 ? "steps / motion unit" : "fit from your phone")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                    Spacer()
                }

                Slider(value: $draftManual, in: 0...sliderMax, step: 0.5) {
                    Text("Manual steps coefficient")
                } minimumValueLabel: {
                    Text("Auto").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                } maximumValueLabel: {
                    Text("High").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                } onEditingChanged: { editing in
                    // Commit on release — snap a tiny drag back to 0 (auto) so "auto" is reachable.
                    if !editing { profile.stepsManualCoefficient = draftManual < 0.5 ? 0 : draftManual }
                }
                .tint(StrandPalette.accent)
                .accessibilityValue(draftManual > 0
                                    ? "\(String(format: "%.1f", draftManual)) steps per motion unit"
                                    : "Automatic")

                // Live preview: a typical recent day re-estimated at the draft coefficient.
                if let motion = sampleMotion {
                    let effective = draftManual > 0 ? draftManual : profile.stepsCalibrationCoefficient
                    if effective > 0 {
                        let preview = Int((motion * effective).rounded())
                        statLine(String(localized: "A typical recent day"),
                                 draftManual > 0
                                     ? String(localized: "≈ \(Self.grouped(preview)) steps at this setting")
                                     : String(localized: "≈ \(Self.grouped(preview)) steps (auto)"))
                    }
                }
                if draftManual > 0 {
                    Text("Takes effect on the next analytics pass (after the next sync).")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
            }
        }
    }

    /// A small "label … value" line shared by the fit + preview cards.
    private func statLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
            Spacer(minLength: 12)
            Text(value).font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: Data

    /// Build the comparison table + a typical-day motion, once. The engine stores `steps_est` ONLY for
    /// strap-only days (a phone-covered day uses the phone's real count), so an estimate and a phone count
    /// never co-exist in storage. To still SHOW "how close the estimate is", we reconstruct what the
    /// estimate WOULD have been on recent phone-covered days: read each day's motion volume the same way
    /// the engine does (gravity over [localMidnight, +24h)) and run the public `StepsEstimateEngine` with
    /// the live calibration. This reuses the engine, never invents a number, and needs no extra storage.
    private func loadIfNeeded() async {
        guard !didLoad else { return }
        didLoad = true
        draftManual = profile.stepsManualCoefficient

        // Effective calibration in force right now: a manual override wins, else the persisted auto-fit.
        let coeff = profile.stepsManualCoefficient > 0
            ? profile.stepsManualCoefficient : profile.stepsCalibrationCoefficient

        // Phone reference steps from Apple Health daily rows (steps > 0 only), newest first.
        let appleRows = await repo.appleDailyRows()
        let phoneDays = appleRows
            .compactMap { row -> (day: String, steps: Int)? in
                guard let s = row.steps, s > 0 else { return nil }
                return (row.day, s)
            }
            .sorted { $0.day > $1.day }

        // Reconstruct the estimate for the most recent phone-covered days, motion-by-motion.
        guard coeff > 0 else { return }
        let cal = StepsEstimateEngine.Calibration(coefficient: coeff,
                                                  sampleDays: profile.stepsCalibrationSampleDays,
                                                  confidence: profile.stepsCalibrationConfidence,
                                                  manual: profile.stepsManualCoefficient > 0)
        let dayParser = DateFormatter(); dayParser.locale = Locale(identifier: "en_US_POSIX"); dayParser.dateFormat = "yyyy-MM-dd"
        let calendar = Calendar.current
        var rows: [StepsComparisonRow] = []
        var motions: [Double] = []
        for entry in phoneDays.prefix(10) {           // scan a few extra to fill 7 after motion gaps
            guard let dayDate = dayParser.date(from: entry.day) else { continue }
            let mid = Int(calendar.startOfDay(for: dayDate).timeIntervalSince1970)
            // #1643: the UNION, not `repo.deviceId` alone — a re-added strap leaves motion under both the
            // active id and the canonical one, and reading either by itself makes this screen disagree
            // with the estimator it is supposed to be reconstructing.
            let grav = await repo.gravitySamplesUnion(from: mid, to: mid + 86_400 - 1)
            let motion = StepsEstimateEngine.dayMotionIntensity(grav)
            guard motion > 0, let est = StepsEstimateEngine.estimate(motion: motion, calibration: cal) else { continue }
            motions.append(motion)
            rows.append(StepsComparisonRow(day: entry.day, estimated: est, actual: entry.steps))
            if rows.count >= 7 { break }
        }
        comparison = rows
        // #693: the "Need N more days…" countdown is now driven by `profile.stepsCalibrationSampleDays`
        // (the engine-persisted usable-day count, read directly in the card) — NOT a local match count
        // computed here. This scan reaches here ONLY when coeff > 0 (already calibrated), so a local count
        // would never reflect the not-yet-calibrated state the countdown describes. The rows still feed the
        // accuracy table (`comparison`) above.

        // Typical recent day's motion for the live preview = median of the motions we just measured.
        if !motions.isEmpty {
            let s = motions.sorted()
            sampleMotion = s[s.count / 2]
        }
    }

    // MARK: Formatting

    private static func grouped(_ n: Int) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
    /// "yyyy-MM-dd" → "EEE d MMM" for the table's day column.
    private static func shortDay(_ key: String) -> String {
        let inF = DateFormatter(); inF.locale = Locale(identifier: "en_US_POSIX"); inF.dateFormat = "yyyy-MM-dd"
        guard let d = inF.date(from: key) else { return key }
        let outF = DateFormatter(); outF.dateFormat = "EEE d MMM"
        return outF.string(from: d)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Settings") {
    let model = AppModel()
    model.live.bonded = true
    model.live.connected = true
    model.live.batteryPct = 64
    return SettingsView()
        .environmentObject(model)
        .environmentObject(model.live)
        .environmentObject(model.profile)
        // iPhone-width (402pt) so the narrow Backup row stays in the preview's blast radius —
        // at 720 the three-up button row had slack and the truncation regression slipped through. (#188)
        .frame(width: 402, height: 900)
        .background(StrandPalette.surfaceBase)
        .preferredColorScheme(.dark)
}
#endif
