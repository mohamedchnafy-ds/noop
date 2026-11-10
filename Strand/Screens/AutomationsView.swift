import SwiftUI
import StrandDesign

/// Automations — turn the strap's physical inputs (double-tap, wrist on/off) and live biometrics
/// into actions (Shortcuts, and Mac-only screen lock) and haptic coaching. All on-device.
struct AutomationsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var behavior: BehaviorStore
    // PERF: this screen does NOT observe `LiveState`. Its only live-dependent pixel is the "Strap
    // bonded / not connected" pill inside the double-tap card, which is now the `BondStatePill` leaf
    // that owns its own `@EnvironmentObject live`. Observing `live` at this level would re-render the
    // whole 8-9 card automations column on every ~1 Hz strap tick (bond state changes only rarely);
    // scoping it means a tick re-renders just the one pill.
    /// Deep-link into the experimental Rhythm visualization (it self-gates on its own consent).
    @EnvironmentObject var router: NavRouter

    /// v5 cycle-awareness opt-in (default OFF — the most sensitive health category, manual-first).
    @AppStorage(AppModel.cycleAwarenessKey) private var cycleAwareness = false
    /// #hide-cycle: the user's "not for me" opt-out (never age-based). Master visibility control lives here
    /// so it stays reachable to un-hide even after the offer is gone from Today + Health.
    @AppStorage(AppModel.cycleAwarenessHiddenKey) private var cycleHidden = false

    /// Whether the cycle-awareness opt-in is offered for this profile (#801). Delegates to the shared
    /// ``ProfileStore/cycleAwarenessApplies`` gate (mirrors HealthView's opt-in gate) so a male profile
    /// can't enable the feature here when it can't see the Health card either.
    private var cycleOptInApplies: Bool { model.profile.cycleAwarenessApplies }
    /// v5 Rhythm experimental gate (the screen still shows its own consent clickwrap when opened).
    @AppStorage(RhythmConsent.enabledKey) private var rhythmEnabled = false
    /// Inactivity reminder (#419) — UI-local store, persisted in UserDefaults. The buzz itself fires
    /// from the BLE offload path (BLEManager.maybeBuzzInactivity → the shipped SedentaryDetector); this
    /// screen only edits the prefs the engine reads.
    @StateObject private var inactivity = InactivityPrefs()
    #if os(iOS)
    /// Wrist-alerts master gate (PR #572). On iOS the NotificationSettingsView (and its store) are
    /// excluded by project.yml, so `notif.masterEnabled` — the key SedentaryDetector + the wrist-buzz
    /// posting read — has no UI to flip and is stuck at its default OFF. Bind the SAME raw key here so
    /// iPhone users can actually turn wrist alerts on. Default OFF, matching the store's default.
    @AppStorage("notif.masterEnabled") private var wristAlertsMaster = false
    #endif

    // #haptics (#1115): per-event toggles for NOOP's IN-SESSION strap buzzes. Default ON (opt-out) — these
    // are feedback to a feature you started, so a fresh install buzzes as before and a user turns off any
    // cue. Ambient cues (inactivity / stress / coaching) keep their own opt-in cards; double-tap is gated by
    // its action picker. Same keys the buzz sites read via HapticPrefs (which also defaults an unset key on).
    @AppStorage(HapticPrefs.breathing) private var breathingHaptic = true
    @AppStorage(HapticPrefs.intervals) private var intervalsHaptic = true
    @AppStorage(HapticPrefs.liveSession) private var liveSessionHaptic = true
    @AppStorage(HapticPrefs.workout) private var workoutHaptic = true

    var body: some View {
        // Fork chantier 17: the cards become groups of rows (the same rows as the Settings domains), the
        // paragraphs move into popovers, and the groups that can reach the wrist or the lock screen as an
        // alert carry an « Alert » mark. The strap's silent wake-alarm is on the Alarms screen (#766).
        ScreenScaffold(title: "Automations",
                       subtitle: "Make the strap act: vibrations, double-tap, reminders and alerts.") {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
                #if os(iOS)
                wristAlertsGroup
                #endif
                hapticsGroup
                doubleTapGroup
                wearGroup
                coachingGroup
                inactivityGroup
                healthGroup
                batteryEffortGroup
            }
        }
        .noopEntranceRoot()
    }

    // MARK: - Wrist alerts master (iOS only — PR #572)

    #if os(iOS)
    /// The master switch for wrist-buzz notifications. On macOS this lives in its own Notifications
    /// screen; that screen is excluded from the iOS target, so without this the gate is unreachable on
    /// iPhone and every wrist alert (inactivity, app notifications) stays silently off. Binds the same
    /// `notif.masterEnabled` key the SedentaryDetector and the notification posting read.
    private var wristAlertsGroup: some View {
        SettingsListGroup(caption: String(localized: "Wrist alerts")) {
            SettingsListToggle(
                title: String(localized: "Enable wrist alerts"),
                info: String(localized: "The master switch for every wrist buzz (inactivity, stress, alerts). Off keeps the strap quiet no matter what else is on."),
                badge: .alert,
                isOn: $wristAlertsMaster)
        }
    }
    #endif

    // MARK: - Haptics (#1115)

    /// Per-event toggles for NOOP's in-session strap buzzes. Parity with the Android Automations
    /// "Haptics" section; ambient cues and the Android-only call/notification buzzes are not shown here.
    private var hapticsGroup: some View {
        SettingsListGroup(caption: String(localized: "Haptics")) {
            SettingsListToggle(title: String(localized: "Breathing pacer"),
                               info: String(localized: "Buzz each inhale and exhale during a breathing or resonance session."),
                               isOn: $breathingHaptic)
            SettingsListDivider()
            SettingsListToggle(title: String(localized: "Interval timer"),
                               info: String(localized: "Buzz on each interval change."),
                               isOn: $intervalsHaptic)
            SettingsListDivider()
            SettingsListToggle(title: String(localized: "Live Session cues"),
                               info: String(localized: "Coaching buzzes during a live workout session."),
                               isOn: $liveSessionHaptic)
            SettingsListDivider()
            SettingsListToggle(title: String(localized: "Workout start & end"),
                               info: String(localized: "A buzz confirms a workout starting and saving."),
                               isOn: $workoutHaptic)
        }
    }

    // MARK: - Double tap

    private var doubleTapGroup: some View {
        SettingsListGroup(caption: String(localized: "Double-tap"),
                          note: String(localized: "Double-tap the strap to trigger an action on \(Platform.deviceNounPhrase). (The strap exposes a single double-tap gesture.)")) {
            SettingsListMenu(title: String(localized: "When I double-tap"),
                             selection: $behavior.doubleTapAction,
                             options: doubleTapOptions.map { ($0.label, $0) })
            if behavior.doubleTapAction == .runShortcut {
                SettingsListDivider()
                SettingsListRow(title: String(localized: "Shortcut name")) {
                    shortcutField(String(localized: "Shortcut name"), text: $behavior.doubleTapShortcut)
                }
            }
            SettingsListDivider()
            SettingsListRow(title: String(localized: "Test action")) {
                HStack(spacing: 10) {
                    // Live-observing leaf: re-renders on its own when the strap's bond state flips, so a
                    // ~1 Hz strap tick doesn't re-render the whole automations column.
                    BondStatePill()
                    Button {
                        model.runMacAction(behavior.doubleTapAction, shortcut: behavior.doubleTapShortcut)
                    } label: { Label("Test action", systemImage: "play.fill") }
                    .buttonStyle(.bordered).tint(StrandPalette.accent)
                    .disabled(behavior.doubleTapAction == .none)
                }
            }
            if !model.moments.isEmpty {
                SettingsListDivider()
                momentsView.padding(.vertical, NoopMetrics.space3)
            }
        }
    }

    private var momentsView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Recent moments")
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.textPrimary)
                Spacer()
                Button("Clear") {
                    model.moments.removeAll()
                    UserDefaults.standard.removeObject(forKey: "moments")
                }
                .buttonStyle(.plain).font(StrandFont.caption).foregroundStyle(StrandPalette.accent)
            }
            ForEach(Array(model.moments.suffix(5).reversed().enumerated()), id: \.offset) { _, d in
                Text(Self.momentFormatter.string(from: d))
                    .font(StrandFont.captionNumber).foregroundStyle(StrandPalette.textSecondary)
            }
        }
    }
    private static let momentFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = AppLanguage.activeLocale
        // Keep the "EEE d MMM ·" layout but honor the device's 12-/24-hour clock (#337): the "j"
        // template resolves to a 12-hour pattern (contains "a") only where the user prefers it.
        let uses24h = !(DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: AppLanguage.activeLocale) ?? "H").contains("a")
        f.dateFormat = "EEE d MMM · " + (uses24h ? "HH:mm" : "h:mm a")
        return f
    }()

    // MARK: - Wear & presence

    private var wearGroup: some View {
        SettingsListGroup(caption: String(localized: "Wear & presence"), note: wearBlurb) {
            #if os(macOS)
            SettingsListToggle(title: String(localized: "Lock the Mac when I take the strap off"),
                               info: String(localized: "Fires the moment the strap leaves your wrist."),
                               isOn: $behavior.autoLockOnWristOff)
            SettingsListDivider()
            #endif
            SettingsListRow(title: String(localized: "Run a Shortcut when taken off"),
                            info: String(localized: "Presence automation: set a Focus, pause media, set away…")) {
                shortcutField(String(localized: "Shortcut name"), text: $behavior.wristOffShortcut)
            }
            SettingsListDivider()
            SettingsListRow(title: String(localized: "Run a Shortcut when put back on"),
                            info: String(localized: "Reverse the above when you return.")) {
                shortcutField(String(localized: "Shortcut name"), text: $behavior.wristOnShortcut)
            }
        }
    }

    // MARK: - Coaching

    private var coachingGroup: some View {
        SettingsListGroup(caption: String(localized: "Haptic coaching"),
                          note: String(localized: "Train by feel. The strap buzzes so you don't have to watch a screen.")) {
            SettingsListToggle(title: String(localized: "HR-zone coaching"),
                               info: String(localized: "Buzz when you hit your top zone (ease off) and again when you recover. Uses your max HR from Settings."),
                               isOn: $behavior.zoneCoaching)
            SettingsListDivider()
            // v5 L3 closed-loop check-in (master + sub toggles). Default OFF, manual-first. The keys
            // mirror BiofeedbackPrefs, which the central detector (AppModel.evaluateStress) reads.
            SettingsListToggle(title: String(localized: "Stress check-ins (haptic)"),
                               info: String(localized: "When a fresh, non-exercise HRV dip is detected while you're still, NOOP offers a one-minute guided breath: a single confirming buzz and a dismissible card. Never an alarm, never a diagnosis."),
                               isOn: $behavior.stressCheckIn)
            if behavior.stressCheckIn {
                SettingsListDivider()
                SettingsListToggle(title: String(localized: "Auto-nudge"),
                                   info: String(localized: "Let the check-in fire on its own. Off keeps it manual: you start a breath from Breathe yourself."),
                                   isOn: $behavior.stressAutoNudge)
                SettingsListDivider()
                SettingsListToggle(title: String(localized: "Respect quiet hours"),
                                   info: String(localized: "Suppress auto-nudges overnight (10pm-7am)."),
                                   isOn: $behavior.stressQuietHours)
                SettingsListDivider()
                SettingsListToggle(title: String(localized: "Use my resonance pace"),
                                   info: String(localized: "Breathe at the pace your last \u{201C}find my pace\u{201D} sweep locked in, if you have one. Otherwise a calm 5.5 breaths/min."),
                                   isOn: $behavior.stressUseResonancePace)
            }
        }
    }

    // MARK: - Inactivity reminder (#419)

    private var inactivityGroup: some View {
        SettingsListGroup(caption: String(localized: "Inactivity reminder"),
                          note: inactivity.enabled && !notifMasterOn
                            ? String(localized: "Notifications are off, so this can't buzz yet. Turn on the master switch in Notifications to let it through.")
                            : nil) {
            SettingsListToggle(title: String(localized: "Enable inactivity reminder"),
                               info: String(localized: "A gentle wrist buzz when you've been sitting too long, a nudge to get up and move. Inferred from the strap's motion on each history sync, so it lags real time by a sync or two."),
                               badge: .alert,
                               isOn: $inactivity.enabled)
            if inactivity.enabled {
                SettingsListDivider()
                SettingsListStepper(title: String(localized: "Sitting for"),
                                    info: String(localized: "Minutes seated before the first nudge."),
                                    value: $inactivity.thresholdMinutes, suffix: String(localized: "min"),
                                    range: 15...120, step: 15)
                SettingsListDivider()
                SettingsListStepper(title: String(localized: "Re-nudge every"),
                                    info: String(localized: "If you're still seated, buzz again this often."),
                                    value: $inactivity.reNudgeMinutes, suffix: String(localized: "min"),
                                    range: 15...120, step: 15)
                SettingsListDivider()
                SettingsListStepper(title: String(localized: "Buzz strength"),
                                    info: String(localized: "How strong the buzz is."),
                                    value: $inactivity.buzzLoops, suffix: "×", range: 1...4, step: 1)
                SettingsListDivider()
                SettingsListToggle(title: String(localized: "Only during active hours"),
                                   info: String(localized: "Only nudge during your active hours."),
                                   isOn: $inactivity.activeHoursEnabled)
                if inactivity.activeHoursEnabled {
                    SettingsListDivider()
                    SettingsListRow(title: String(localized: "From")) {
                        HStack(spacing: 12) {
                            DatePicker("", selection: activeStartBinding, displayedComponents: .hourAndMinute)
                                .labelsHidden().datePickerStyle(.compact)
                                .accessibilityLabel("Active hours start")
                            Text("to").font(StrandFont.body).foregroundStyle(StrandPalette.textSecondary)
                            DatePicker("", selection: activeEndBinding, displayedComponents: .hourAndMinute)
                                .labelsHidden().datePickerStyle(.compact)
                                .accessibilityLabel("Active hours end")
                        }
                    }
                }
            }
        }
    }

    /// The reused global notification master (notif.masterEnabled, default OFF) — drives the inert-feature
    /// warning so enabling the reminder while master is off isn't silently a no-op.
    private var notifMasterOn: Bool {
        UserDefaults.standard.object(forKey: "notif.masterEnabled") as? Bool ?? false
    }
    private var activeStartBinding: Binding<Date> {
        Binding(get: { Self.date(fromMinutes: inactivity.activeStartMinutes) },
                set: { inactivity.activeStartMinutes = Self.minutes(from: $0) })
    }
    private var activeEndBinding: Binding<Date> {
        Binding(get: { Self.date(fromMinutes: inactivity.activeEndMinutes) },
                set: { inactivity.activeEndMinutes = Self.minutes(from: $0) })
    }

    // MARK: - Health: illness early-warning, cycle awareness, Rhythm

    private var healthGroup: some View {
        SettingsListGroup(caption: String(localized: "Health insights"),
                          note: String(localized: "Optional, on-device reads from your nightly signals. Each is off by default: for awareness only, never a diagnosis.")) {
            SettingsListToggle(title: String(localized: "Watch for early-illness signs"),
                               info: String(localized: "Watches your resting HR, HRV, skin temperature and respiration against your own 28-day baseline. On-device and approximate: informational only, not a diagnosis. Needs at least 14 days of history. When two or more signals drift together you get a banner on the dashboard and a notification, at most once a day."),
                               badge: .alert,
                               isOn: $behavior.illnessWatch)
                .onChangeCompat(of: behavior.illnessWatch) { _ in
                    model.reevaluateIllness()
                    if behavior.illnessWatch { IllnessNotifier.requestAuthorization() }
                }
            // #801: cycle awareness reads the MENSTRUAL temperature shift, so the toggle is only offered
            // to profiles it applies to (gated like the Health opt-in card, not shown for male profiles).
            if cycleOptInApplies {
                SettingsListDivider()
                // #hide-cycle: the master visibility control — a USER opt-out, never age-based. Turning
                // it off hides the cycle-awareness offer on Today + Health AND stops active tracking.
                SettingsListToggle(title: String(localized: "Show cycle awareness"),
                                   info: String(localized: "Shows the cycle-awareness card on Today and in Health. Turn off to hide it entirely — a private choice, never based on your age. You can turn it back on here any time."),
                                   isOn: Binding(get: { !cycleHidden },
                                                 set: { show in
                                                     cycleHidden = !show
                                                     if !show {
                                                         cycleAwareness = false
                                                         model.cycleAwarenessEnabled = false
                                                         Task { await model.refreshV5Signals() }
                                                     }
                                                 }))
                if !cycleHidden {
                    SettingsListDivider()
                    SettingsListToggle(title: String(localized: "Cycle awareness"),
                                       info: String(localized: "Reads a coarse menstrual-cycle phase from your nightly skin temperature, entirely on \(Platform.deviceNounPhrase). Awareness only: not contraception, not a fertility predictor, not a medical service. The card appears in Health."),
                                       isOn: $cycleAwareness)
                        .onChangeCompat(of: cycleAwareness) { on in
                            model.cycleAwarenessEnabled = on
                            Task { await model.refreshV5Signals() }
                        }
                }
            }
            SettingsListDivider()
            SettingsListToggle(title: String(localized: "Rhythm visualization (experimental)"),
                               info: String(localized: "An experimental picture of your beat-to-beat heart timing. Not an ECG and not a diagnosis. You'll read and accept an experimental note before it shows anything."),
                               badge: .experimental,
                               isOn: $rhythmEnabled)
            if rhythmEnabled {
                SettingsListDivider()
                // The link to Rhythm now lives only here (it left the Plus sheet in step 2).
                Button {
                    router.openRhythm()
                } label: {
                    SettingsListRow(title: String(localized: "Open Rhythm")) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(StrandPalette.textTertiary)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(LiquidPressStyle())
            }
        }
    }

    // MARK: - Strap battery alerts, strain target nudge (#593)

    private var batteryEffortGroup: some View {
        SettingsListGroup(caption: String(localized: "Battery alerts")) {
            SettingsListToggle(title: String(localized: "Notify on low and full battery"),
                               info: String(localized: "A reminder to recharge before bed when the strap drops to 15%, and a heads-up when it reaches 100%, each at most once per charge cycle."),
                               badge: .alert,
                               isOn: $behavior.batteryAlerts)
                .onChangeCompat(of: behavior.batteryAlerts) { on in
                    if on { BatteryNotifier.requestAuthorization() }
                }
            if behavior.batteryAlerts {
                SettingsListDivider()
                SettingsListToggle(title: String(localized: "Predictive runtime warning"),
                                   info: String(localized: "An early \"recharge tonight\" heads-up when the strap has about a day of estimated runtime left, at most once per discharge cycle. Turn off to keep only the 15% warning."),
                                   isOn: $behavior.batteryPredictiveAlerts)
            }
            SettingsListDivider()
            SettingsListToggle(title: String(localized: "Notify when optimal strain is reached"),
                               info: String(localized: "Posts after your strap syncs and NOOP scores the day — not the exact second you cross it. At most once per day."),
                               badge: .alert,
                               isOn: $behavior.strainTargetNudge)
                .onChangeCompat(of: behavior.strainTargetNudge) { on in
                    if on {
                        StrainTargetNotifier.requestAuthorization()
                        // The repo.$days sink only fires on data changes, so if today's target is
                        // already reached, evaluate now rather than waiting for the next refresh.
                        model.evaluateStrainTarget()
                    }
                }
        }
    }

    // MARK: - Helpers

    /// Double-tap actions offered in the picker. The "Lock the Mac" action can't work on iPhone
    /// (a third-party app can't lock iOS), so it's dropped there.
    private var doubleTapOptions: [MacActionKind] {
        #if os(iOS)
        MacActionKind.allCases.filter { $0 != .lockScreen }
        #else
        MacActionKind.allCases
        #endif
    }

    /// Wear & presence blurb. macOS mentions the auto-lock affordance (and the Apple-Watch unlock
    /// caveat); iOS, where that toggle is hidden, describes the Shortcut-driven presence reactions.
    /// Wear & presence is "active" when any of its reactions are configured: a wrist-on/off Shortcut,
    /// or (macOS) the auto-lock toggle. Presentation-only — drives the card's accent state.
    private var wearActive: Bool {
        let shortcuts = !behavior.wristOffShortcut.isEmpty || !behavior.wristOnShortcut.isEmpty
        #if os(macOS)
        return shortcuts || behavior.autoLockOnWristOff
        #else
        return shortcuts
        #endif
    }

    private var wearBlurb: String {
        #if os(macOS)
        String(localized: "React when the strap comes off or goes on. Note: macOS reserves true auto-UNLOCK for Apple Watch, so this can lock, not unlock.")
        #else
        String(localized: "React when the strap comes off or goes on. Run a Shortcut to set a Focus, pause media, mark yourself away.")
        #endif
    }

    // `date(fromMinutes:)` / `minutes(from:)` stay: the inactivity active-hours pickers above use them.
    // (The strap-alarm time binding moved to SmartAlarmView with the rest of the alarm UI, #766.)
    private static func date(fromMinutes m: Int) -> Date {
        Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
    }
    private static func minutes(from d: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    private func shortcutField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.roundedBorder)
            .font(StrandFont.body)
            .frame(maxWidth: 320)
    }
}

// MARK: - Live-observing leaf (scroll-stutter isolation)

/// The strap bond-status pill in the double-tap card ("Strap bonded" / "Strap not connected"). It owns
/// its OWN `@EnvironmentObject live` so a ~1 Hz strap publish re-renders only this pill, not the whole
/// automations column (the parent `AutomationsView` no longer observes `LiveState`). Renders
/// byte-for-byte the previous inline `StatePill(live.bonded ? …)`.
private struct BondStatePill: View {
    @EnvironmentObject private var live: LiveState
    var body: some View {
        StatePill(live.bonded ? "Strap bonded" : "Strap not connected",
                  tone: live.bonded ? .positive : .warning, showsDot: true)
    }
}
