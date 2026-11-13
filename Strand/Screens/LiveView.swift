import SwiftUI
#if os(macOS)
import AppKit
#endif
import StrandDesign
import StrandAnalytics
import WhoopProtocol
import WhoopStore
import OuraProtocol

/// Live — the connected strap in real time, in the liquid finish. Built on the shared design system
/// (ScreenScaffold chrome + day-of-sky backdrop, StrandPalette, StrandFont) and the liquid vocabulary
/// (LiquidVessel for the live BPM gauge, LiquidThread for the live HR trace, LiquidTube for the effort
/// bars, frosted `card {}` surfaces, LiquidPressStyle on tappable rows) so it lines up with the Today
/// screen instead of the old flat-card layout.
///
/// LiveState (which publishes at ~1 Hz while a strap streams) is observed ONLY in leaf views
/// (`LiveHeartReadout`, `LivePhysiology`, `LiveHeaderStats`, `ActiveWorkoutLive`,
/// `StrapLogRecentCard`, …) — the Today pattern — so a fresh HR / R-R / frame notify re-renders just that leaf,
/// never the whole screen. The parent only observes the coarse connection transitions it needs to re-arm
/// the stream and gate the layout.
struct LiveView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState
    /// Cross-screen navigation — drives the "Manage devices" affordance to the first-class Devices
    /// manager (where bands are paired / switched). The shell (sidebar on macOS, a sheet on iOS) routes
    /// the request; LiveView never needs to know which.
    @EnvironmentObject private var router: NavRouter

    /// Which strap the user is pairing — persists across launches. Drives which
    /// BLE service we scan for so a WHOOP 4.0 scan never hangs on a WHOOP 5 wrist.
    @AppStorage("selectedWhoopModel") private var selectedModelRaw = WhoopModel.whoop4.rawValue
    private var selectedModel: WhoopModel { WhoopModel(rawValue: selectedModelRaw) ?? .whoop4 }


    /// Maps the picked strap model to the HRV-reading source so the spot caveat is honest (#537): a
    /// WHOOP 5/MG's R-R is optical PPG (noisier), a WHOOP 4 is electrical R-R. Mirrors the Android
    /// `LiveScreen` mapping.
    private var hrvSnapshotSource: SpotHrvReading.Source {
        switch selectedModel {
        case .whoop5mg: return .opticalPPG
        case .whoop4:   return .chestStrap
        }
    }

    /// Effort display scale (#268) — routes the live + saved workout Effort read-outs. Display-only.
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    private var effortScale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }

    /// Whether the ACTIVE registry device is a WHOOP, resolved once and handed to the leaves.
    private var activeIsWhoop: Bool {
        LiveConsoleReadout.activeIsWhoop(
            devices: model.deviceRegistry?.devices ?? [],
            activeId: model.deviceRegistry?.activeDeviceId,
        )
    }

    /// Whether the ACTIVE registry device is an Oura ring (#2305) — the ring-only affordances below.
    private var activeIsOura: Bool {
        LiveConsoleReadout.activeIsOura(
            devices: model.deviceRegistry?.devices ?? [],
            activeId: model.deviceRegistry?.activeDeviceId,
        )
    }

    /// The live ring's link phase, mirrored off the Oura source (#2305). Meaningful only under
    /// `activeIsOura`; `.disconnected` otherwise.
    private var ringPhase: OuraLiveSource.LinkPhase { model.ouraLinkPhase }

    /// A trusted WHOOP link, for the console readouts and the bond-only controls.
    ///
    /// Gated on the active device actually BEING a WHOOP (#2075). `LiveState` is one object that every
    /// live source writes into, so `connected && bonded` stays true for a bonded strap while an Oura
    /// ring is the device on screen. That showed the WHOOP pill, the WHOOP charge and live WHOOP-only
    /// controls under the ring's name, and made the pill's own ring branch unreachable, because this one
    /// is tested first.
    private var activeConnection: Bool { activeIsWhoop && live.connected && live.bonded }

    /// A non-WHOOP live source (the Oura ring) that is connected and actively streaming live HR. It
    /// authenticates and streams but never reaches a WHOOP encrypted bond, so `bonded` stays false and
    /// `activeConnection` never trips — which left the console reading "stream not yet trusted" for a
    /// perfectly good ring stream. The status copy below treats this as a trusted live stream; the
    /// bond-only feature gates (buzz, alarm, HRV snapshot) keep keying off `activeConnection`. (#69 twin.)
    private var ringStreaming: Bool { live.connected && live.streamingLiveHR }

    /// The display name of the active device from the registry ("WHOOP", a strap's nickname, …) — what
    /// the user is connected to, or would connect to. Falls back to "WHOOP" before the registry opens or
    /// when none is resolvable, keeping the WHOOP-first tone. Drives the active-device readout + copy.
    private var activeDeviceName: String {
        guard let registry = model.deviceRegistry,
              let active = registry.devices.first(where: { $0.id == registry.activeDeviceId })
        else { return "WHOOP" }
        return active.displayName
    }

    /// Live workout mode (#238) — presents the full in-exercise screen while a manual workout is
    /// active. Auto-opens when a workout begins; closing just hides it (the workout keeps recording).
    @State private var showLiveWorkout = false
    /// The sport picked, started by the live workout at the « Go » of its countdown (fork chantier 12).
    @State private var pendingSport: String?
    @State private var showStartSport = false
    @State private var confirmingEndWorkout = false

    /// Manual HRV snapshot (#127) — presents the "Take an HRV reading" screen as a sheet. Entry sits in
    /// the Session console and is only enabled while bonded (the reading needs the live R-R stream).
    @State private var showHRVSnapshot = false

    var body: some View {
        // Personal fork (Démarrer tools, board 2): the screen is named as its entry, « Live HR ».
        ScreenScaffold(title: "Live HR", subtitle: "Your heart right now, beat by beat.") {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                consoleHeader
                // Can't-connect-at-all guidance: the strap wiped its bond (firmware update / WHOOP app
                // re-bond), so connects loop on "Peer removed pairing information". Show the re-pair steps
                // right here instead of silently retrying. (5/MG firmware reset, 2026-06)
                if let guide = live.reconnectGuide { reconnectGuideBanner(guide) }
                // Bond-refused guidance, shown right here on Live where people actually connect (it
                // also appears in Settings). A 5/MG strap still bonded to the WHOOP app refuses pairing
                // with "Encryption is insufficient" — this tells the user to free it and re-pair.
                if let hint = live.pairingHint { pairingHintBanner(hint) }
                // Primary Connect affordance, surfaced ABOVE the fold whenever there's no link. The real
                // Scan & Connect control otherwise lives in `controls` (below the Signal Trust grid), so
                // an offline user saw only inert copy up top. Gated purely on `!live.connected`, so it
                // disappears the instant the radio connects. Shared with macOS — it reuses `scanButton`,
                // which the wide layout already renders in `controls`.
                // WHOOP only (#2305): under a ring this card named the ring over a button that ran a
                // WHOOP scan — the #2303 reporter's Re-scan ran a full 5/MG handshake with the ring active.
                if activeIsWhoop, !live.connected { offlineConnectCallout }
                // The ring's own above-the-fold affordance: its link phase and a reconnect, shown until
                // `auth OK` — the same "no link yet" slot the WHOOP callout fills.
                if activeIsOura, ringPhase != .authenticated { ringConnectCallout }
                bodyConsole
                // Low-bandwidth fallback note (#80): the radio couldn't sustain the WHOOP 4 R10/R11 raw
                // realtime burst, so live HR is riding the standard BLE Heart-Rate profile instead. Live HR
                // still works — this is informational, not an error — so it sits right under the readout in
                // a calm accent treatment rather than the amber warning banners above.
                if Self.shouldShowStandardHRNote(live.standardHRMode) {
                    standardHRNote(live.standardHRMode ?? "")
                }
                sessionConsole
                // Show the strap picker whenever we're not actively streaming, so a user with both a
                // WHOOP 4 and a 5/MG can switch between them. (It used to hide once `bonded`, which is
                // sticky across disconnects — so after the first pairing the picker vanished for good.)
                // WHOOP only (#2305): `activeConnection` is false for a ring BY CONSTRUCTION, so without
                // the brand gate the WHOOP picker was shown MORE readily under a ring than under a strap.
                if activeIsWhoop, !activeConnection { modelPicker }
                // Scan / Buzz / Disconnect are the WHOOP path (`model.scan` → `BLEManager.connect`, the
                // explicit user-connect that bypasses the #1881 active-device gate on purpose). A ring
                // gets its own row; any other brand keeps the Devices row alone.
                if activeIsWhoop {
                    controls
                } else if activeIsOura {
                    ringControls
                }
                #if os(iOS)
                // What the Lock Screen banner shows beside the bpm outside a gym session (personal fork).
                LiveHRBannerSideSetting()
                #endif
                manageDevicesRow
                // The strap log in plain words (personal fork): the last sentences, « See all » opens the screen.
                StrapLogRecentCard()
            }
        }
        .onAppear { refreshLiveSession(); consumeActiveWorkoutRequest() }
        .onDisappear { model.stopRealtimeHR() }
        // A fresh bond/connection re-arms the BLE stream (Apple must re-send startRealtime on a new
        // connection) WITHOUT bumping the ref-count — `refreshLiveSession`'s `startRealtimeHR` already
        // counted this screen once on `.onAppear`, balanced by the single `stopRealtimeHR` above.
        // Re-counting here (multiple bonded/connected events per appearance, one disappear) would leave
        // the stream stuck armed after leaving Live (#681 ref-count balance).
        .onChangeCompat(of: live.bonded) { _ in reconnectLiveSession() }
        .onChangeCompat(of: live.connected) { _ in reconnectLiveSession() }
        // Live workout mode (#238): open the in-exercise screen the moment a workout starts.
        .onChangeCompat(of: model.activeWorkout != nil) { active in if active { showLiveWorkout = true } }
        .sheet(isPresented: $showLiveWorkout) {
            LiveWorkoutView(onClose: { showLiveWorkout = false }, startingSport: pendingSport)
                .environmentObject(model)
                .environmentObject(live)
        }
        // Pick a named sport before starting (#519) — the live workout view then opens
        // off the activeWorkout change above, so no extra navigation is needed here.
        .workoutSelectionCover(isPresented: $showStartSport) {
            // Fork chantier 12: the live workout starts it at the « Go » of its countdown.
            StartWorkoutSheet { name in
                pendingSport = name
                showLiveWorkout = true
            }
        }
        // Manual HRV snapshot (#127) — a still, seated 60s R-R reading.
        .sheet(isPresented: $showHRVSnapshot) {
            // Tell the reading where its R-R is coming from so the caveat is honest (#537): a WHOOP 5/MG
            // derives R-R from the optical pulse signal (noisier) while a WHOOP 4 / chest strap is
            // electrical R-R. Driven off the picked strap model, mirroring the Android twin.
            HRVSnapshotView(onClose: { showHRVSnapshot = false }, source: hrvSnapshotSource)
                .environmentObject(model)
                .environmentObject(live)
        }
        .alert("End this workout?", isPresented: $confirmingEndWorkout) {
            Button("Cancel", role: .cancel) { }
            Button("End workout", role: .destructive) {
                model.endWorkout()
            }
        } message: {
            Text("This stops recording and saves what's captured so far. It can't be resumed.")
        }
    }

    // MARK: - Frosted card helper (matches LiquidTodayView.card: rounded 22 + resting hairline)

    private func card<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NoopPanelSurface())
    }

    // MARK: - Console header

    /// The console's top band: the connection pill + a connection-mode badge (+ a live SYNCING badge
    /// while a history offload runs), with battery / worn / last-sync stats pushed to the trailing edge.
    /// The high-frequency stats (battery / worn / sync) live in the `LiveHeaderStats` leaf so their
    /// notifies don't re-render the whole screen.
    /// The link's state in one line (the same resolver as the strap log screen), then battery, wrist and
    /// history. Personal fork (Démarrer tools): this replaces the pill, the FULL BOND / SYNCING badges and the
    /// four squeezed stats, which said the same facts in jargon and truncated on a phone.
    private var consoleHeader: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                StrapLinkSummaryRow(showsDetail: false)
                LiveHeaderStats(activeConnection: activeConnection, activeIsWhoop: activeIsWhoop)
            }
        }
    }

    // MARK: - Body console (live BPM vessel + live physiology)

    /// The console's centrepiece: a live BPM LiquidVessel beside a live-physiology stack (R-R tube,
    /// rolling RMSSD, last frame/event). Side-by-side on a wide window (Mac), stacked on a narrow one
    /// (iPhone) via ViewThatFits. Both halves are leaf views that own LiveState so the 1 Hz HR / R-R
    /// notifies re-render only them, not the whole console. The card carries the Effort tint world.
    private var bodyConsole: some View {
        card {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: NoopMetrics.space6) {
                    LiveHeartReadout(activeIsWhoop: activeIsWhoop, activeIsOura: activeIsOura, hrMax: model.profile.hrMax)
                        .frame(minWidth: 260, maxWidth: 340)
                    Divider().overlay(StrandPalette.hairline)
                    LivePhysiology(activeIsWhoop: activeIsWhoop)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: 18) {
                    LiveHeartReadout(activeIsWhoop: activeIsWhoop, activeIsOura: activeIsOura, hrMax: model.profile.hrMax)
                    Divider().overlay(StrandPalette.hairline)
                    LivePhysiology(activeIsWhoop: activeIsWhoop)
                }
            }
        }
    }

    // MARK: - Session console (record / inspect the current stream)

    @ViewBuilder private var sessionConsole: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            if let w = model.activeWorkout {
                activeWorkoutCard(w)
            } else {
                sessionActions
                if let last = model.lastWorkout {
                    workoutSavedRow(last)
                }
            }
        }
    }

    /// The screen's actions without the explanatory paragraph: start a session, take a 60-second HRV reading
    /// (#127), sync now. Buzz, Scan and Disconnect stay in `controls`.
    private var sessionActions: some View {
        VStack(spacing: NoopMetrics.rowSpacing) {
            NoopButton("Start workout", systemImage: "figure.run", kind: .primary, fullWidth: true) {
                showStartSport = true
            }
            .disabled(!activeConnection)
            .help("Track a workout manually. Records heart rate and effort until you end it.")
            HStack(spacing: NoopMetrics.rowSpacing) {
                // Manual HRV snapshot (#127) — a still, seated 60s R-R reading. Needs the live R-R stream.
                NoopButton("Measure my HRV", systemImage: "waveform.path.ecg", kind: .secondary, fullWidth: true) {
                    showHRVSnapshot = true
                }
                .disabled(!activeConnection)
                // The same gate as Health's « Sync now »: BLEManager.syncNow() ignores it when not connected.
                NoopButton("Sync now", systemImage: "arrow.triangle.2.circlepath", kind: .secondary, fullWidth: true) {
                    model.ble.syncNow()
                }
                .disabled(!activeConnection)
            }
        }
    }

    private func activeWorkoutCard(_ w: AppModel.ActiveWorkout) -> some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Circle().fill(StrandPalette.metricRose).frame(width: 8, height: 8)
                    // "RECORDING" is a factual claim, and while paused nothing IS being recorded — the
                    // sample capture drops every reading. So the label swaps rather than gaining a tag
                    // beside it, which would leave the card asserting both at once. Reuses the "Paused"
                    // string #1533 already localized. (The Today card says "IN PROGRESS", which stays
                    // true while paused, so it keeps its label and takes the tag instead.)
                    Text(w.isPaused ? "Paused" : "RECORDING WORKOUT").font(StrandFont.overline)
                        .tracking(StrandFont.overlineTracking)
                        .foregroundStyle(w.isPaused ? StrandPalette.textSecondary : StrandPalette.metricRose)
                    Spacer()
                    // Re-render once a second so the elapsed clock ticks without a manual Timer.
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(ActiveWorkoutClock.clock(Int(w.elapsed(at: context.date))))
                            .font(StrandFont.number(17)).monospacedDigit()
                            .foregroundStyle(StrandPalette.textPrimary)
                    }
                }
                // Live HR / avg / peak / effort — the leaf owns LiveState + the active workout so the
                // 1 Hz stat refresh re-renders only these tiles, plus a liquid effort tube under them.
                ActiveWorkoutLive(workout: w, effortScale: effortScale)
                // The card used to offer End and nothing else, so the only IRREVERSIBLE control was the
                // one reachable without opening the live view, while Pause — the reversible one — was
                // not. Pause/Resume is one toggle (a paused session has exactly one sensible action), and
                // End moves to its own row so a destructive tap is not adjacent to a routine one.
                HStack(spacing: NoopMetrics.rowSpacing) {
                    NoopButton(w.isPaused ? "Resume" : "Pause",
                               systemImage: w.isPaused ? "play.fill" : "pause.fill",
                               kind: .secondary, fullWidth: true) {
                        model.toggleWorkoutPause()
                    }
                    // Re-open the full live workout screen (#238) after it's been dismissed.
                    NoopButton("Open live view", systemImage: "rectangle.expand.vertical",
                               kind: .secondary, fullWidth: true) {
                        showLiveWorkout = true
                    }
                }
                NoopButton("End workout", systemImage: "stop.circle.fill",
                           kind: .destructive, fullWidth: true) {
                    confirmingEndWorkout = true
                }
            }
        }
    }

    private func workoutSavedRow(_ row: WorkoutRow) -> some View {
        let mins = Int((row.durationS ?? 0) / 60)
        let parts = [String(localized: "\(mins) min"), row.avgHr.map { String(localized: "\($0) avg bpm") },
                     row.strain.map { String(localized: "effort \(UnitFormatter.effortDisplay($0, scale: effortScale))") }].compactMap { $0 }
        return HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(StrandPalette.accent)
            Text("Workout saved · \(parts.joined(separator: " · "))")
                .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }

    private func reconnectGuideBanner(_ guide: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(StrandPalette.statusWarning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Can't connect: your strap's pairing was reset")
                    .font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                Text(guide)
                    .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(NoopMetrics.space3)
        .background(NoopPanelSurface(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(StrandPalette.statusWarning.opacity(0.5), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Reconnect help: \(guide)")
    }

    private func pairingHintBanner(_ hint: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(StrandPalette.statusWarning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Live HR works. Free the strap to unlock buzz, alarms & sync")
                    .font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                Text(hint)
                    .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(NoopMetrics.space3)
        .background(NoopPanelSurface(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(StrandPalette.statusWarning.opacity(0.5), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Pairing help: \(hint)")
    }

    /// Whether the low-bandwidth standard-HR fallback note should render. The note explains that live HR
    /// is coming over the standard BLE Heart-Rate profile because the radio couldn't sustain the full
    /// stream (#80). Shown only when LiveState carries a non-empty note string; pure so it's unit-testable
    /// without standing up a SwiftUI view.
    static func shouldShowStandardHRNote(_ note: String?) -> Bool {
        guard let note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return true
    }

    /// Calm inline note for the #80 low-bandwidth fallback. Unlike the amber pairing/reconnect banners this
    /// is NOT a warning — live HR is working — so it uses the accent (health-green) treatment with a signal
    /// glyph. Mirrors the banner layout (icon + headline + one-line explanation) for visual consistency.
    private func standardHRNote(_ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .foregroundStyle(StrandPalette.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Standard HR mode (low bandwidth)")
                    .font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                Text(detail)
                    .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Other metrics (R-R, frames, battery, history) need a full sync.")
                    .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(NoopMetrics.space3)
        .background(NoopPanelSurface(tint: StrandPalette.accent, cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(StrandPalette.accent.opacity(0.4), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Standard HR mode, low bandwidth. \(detail)")
    }

    // MARK: - Strap picker

    /// Pick the strap family to scan for. Switching the selection drops the current strap's bond so the
    /// newly-picked one connects fresh — letting a user move between a WHOOP 4 and a 5/MG.
    private var modelPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Strap").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                SegmentedPillControl(
                    WhoopModel.allCases,
                    selection: Binding(
                        get: { selectedModel },
                        set: { newModel in
                            guard newModel.rawValue != selectedModelRaw else { return }
                            selectedModelRaw = newModel.rawValue
                            // Clear the previous strap's sticky bond/connection so the next scan targets the
                            // new family's service and bonds it fresh.
                            model.prepareStrapSwitch()
                        }
                    ),
                    label: { $0.displayName }
                )
                Spacer()
            }
            // Proactive 5/MG guidance: the strap bonds to one host at a time, so if it's still paired in
            // the official WHOOP app a scan here finds nothing. Shown the moment 5/MG is picked — not only
            // after a failed scan (#130) or a bond-refusal (which is the separate `pairingHint` banner).
            if selectedModel == .whoop5mg { whoop5PairingNote }
        }
    }

    private var whoop5PairingNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle").foregroundStyle(StrandPalette.accent)
            Text("WHOOP 5.0/MG pairs with one app at a time. If a scan finds nothing, unpair it in the official WHOOP app and fully close that app, then Scan again.")
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Offline connect callout

    /// The above-the-fold primary Connect affordance, shown only while `!live.connected`. Promotes the
    /// formerly-inert "Scan and connect…" caption into a frosted card with a real, full-width
    /// `scanButton` (the same one `controls` renders below), so the offline state has an obvious action
    /// up top instead of burying it past the Signal Trust grid. Shared with macOS — the wide layout
    /// shows it stacked above the console, and `scanButton` already styles full-width.
    @ViewBuilder private var offlineConnectCallout: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(StrandPalette.accent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Start a live stream")
                            .font(StrandFont.headline)
                            .foregroundStyle(StrandPalette.textPrimary)
                        // Name the band Scan will connect to, and point pairing/switching at Devices — so
                        // an offline user knows both what this button does and where to add a different band.
                        Text("Scan connects to \(activeDeviceName). To pair or switch bands, open Devices.")
                            .font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                scanButton
            }
        }
        .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
            .strokeBorder(StrandPalette.accent.opacity(0.30), lineWidth: 1))
    }

    // MARK: - Manage devices link

    /// A persistent "where to pair / switch bands" row beneath the Scan / Disconnect controls. It sends
    /// the user to the first-class Devices manager and stays one tap away in every connection state,
    /// naming the active band so the link reads in context. The shell routes the request via `NavRouter` —
    /// macOS selects the Devices sidebar item, iOS presents the Devices screen.
    private var manageDevicesRow: some View {
        Button { router.openDevices() } label: {
            HStack(spacing: 12) {
                Image(systemName: "badge.plus.radiowaves.right")
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Devices")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text(manageDevicesDetail)
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(NoopMetrics.space3)
            .background(NoopPanelSurface(cornerRadius: 18))
            .contentShape(Rectangle())
        }
        .buttonStyle(LiquidPressStyle())
        .accessibilityLabel("Manage devices")
        .accessibilityHint("Opens the Devices screen, where you pair and switch bands.")
    }

    /// One-line subtitle for the Manage-devices row — names the active band and reads correctly whether
    /// it's the live link ("Connected to …") or just the band Scan would target ("… is your active band").
    private var manageDevicesDetail: String {
        // The connection itself is stated once, in the header (personal fork).
        String(localized: "Pair or switch straps")
    }

    // MARK: - Controls

    private var controls: some View {
        // Three equal thirds can't hold all three labels at a legible size on a phone — the longest
        // ("Scan & Connect") truncates to "Scan &…" even after shrink-to-fit (#175). So on iOS the
        // primary action takes a full-width row and the two secondary actions share the row beneath;
        // macOS keeps the single three-up row, where the window is always wide enough. (#175)
        #if os(iOS)
        VStack(spacing: NoopMetrics.rowSpacing) {
            scanButton
            HStack(spacing: NoopMetrics.rowSpacing) {
                buzzButton
                disconnectButton
            }
        }
        #else
        HStack(spacing: NoopMetrics.rowSpacing) {
            scanButton
            buzzButton
            disconnectButton
        }
        #endif
    }

    // MARK: - Ring controls (#2305)

    /// The ring's above-the-fold card while it is not yet authenticated: the honest phase line and the
    /// only ring reconnect in the app. Same slot and shape as `offlineConnectCallout`, which is WHOOP-only.
    @ViewBuilder private var ringConnectCallout: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(StrandPalette.accent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(LiveRingCopy.status(ringPhase, streaming: false))
                            .font(StrandFont.headline)
                            .foregroundStyle(StrandPalette.textPrimary)
                        Text("Reconnect drops the current link, if any, and connects to the ring again. To pair or switch bands, open Devices.")
                            .font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                ringReconnectButton
            }
        }
        .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
            .strokeBorder(StrandPalette.accent.opacity(0.30), lineWidth: 1))
    }

    /// The ring's row in the `controls` slot: one primary action. No Buzz (the ring has no haptic) and no
    /// Disconnect (a stopped ring source would not reconnect for the night; Devices is where a ring is
    /// deactivated).
    private var ringControls: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.rowSpacing) {
            Text(LiveRingCopy.status(ringPhase, streaming: ringStreaming))
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            ringReconnectButton
        }
    }

    /// Drops the current ring link, if any, and connects again — `OuraLiveSource.reconnect()` through the
    /// coordinator, so it can only reach the ring that is the live source. Enabled in every phase: a ring
    /// parked in `.authenticating` (#2303) is exactly the case this exists for.
    private var ringReconnectButton: some View {
        NoopButton("Reconnect ring", systemImage: "arrow.clockwise",
                   kind: .primary, fullWidth: true) {
            model.reconnectOuraRing()
        }
    }

    // The connect / buzz / disconnect controls, all routed through the unified NOOP button system:
    // a filled primary for the lead Scan action, a secondary surface for Buzz, and the destructive
    // role for Disconnect — sentence-case, single line, optical-centred at controlHeight.
    private var scanButton: some View {
        NoopButton(live.connected ? "Re-scan" : "Scan & connect",
                   systemImage: "antenna.radiowaves.left.and.right",
                   kind: .primary, fullWidth: true) {
            model.scan(model: selectedModel)
        }
    }

    private var buzzButton: some View {
        NoopButton("Buzz strap", systemImage: "waveform.path",
                   kind: .secondary, fullWidth: true) {
            // #921: the confirmed one-shot sequence (pattern + RUN_ALARM, acked). A bare pattern
            // write here was the same silent no-buzz path the Siri shortcut hit on a WHOOP 4.0.
            model.buzzStrapOnce()
        }
        .disabled(!activeConnection)
        .help("Fire a test haptic buzz on the strap (requires an active strap connection)")
    }

    private var disconnectButton: some View {
        NoopButton("Disconnect", systemImage: "xmark.circle",
                   kind: .destructive, fullWidth: true) {
            model.disconnect()
        }
        .disabled(!live.connected)
    }

    /// Live tab appeared: take a ref-count on the realtime stream (arms it on the 0→1 edge) and pull a
    /// battery reading. Balanced by the single `stopRealtimeHR()` on `.onDisappear`.
    private func refreshLiveSession() {
        guard activeConnection else { return }
        model.startRealtimeHR()
        model.getBattery()
    }

    /// Honour a one-shot "Return to workout" from the Today indicator card: present the in-exercise screen
    /// for an already-running workout, then clear the flag. The #238 "a workout just started" transition
    /// trigger never fires for a session that is already in flight, so this is the path that re-opens it.
    /// Guarded on a live `activeWorkout` so a stale flag can never present an empty live-workout sheet, and
    /// it sets the SAME `showLiveWorkout` one-shot the manual re-open button uses (no new sheet machinery).
    private func consumeActiveWorkoutRequest() {
        guard router.presentActiveWorkout else { return }
        router.presentActiveWorkout = false
        if model.activeWorkout != nil { showLiveWorkout = true }
    }

    /// A fresh bond/connection landed while the Live tab is up: re-arm the BLE stream (Apple re-sends
    /// startRealtime on a new connection) and refresh battery — WITHOUT taking another ref-count, since
    /// these events can fire several times per appearance against the single `.onDisappear` release.
    private func reconnectLiveSession() {
        guard activeConnection else { return }
        model.rearmRealtimeIfWanted()
        model.getBattery()
    }
}

// MARK: - Live leaves (each owns LiveState so a 1 Hz notify re-renders only the leaf — the Today pattern)

/// The header stats strip (device / battery / worn / last sync). Owns LiveState so battery + wear + sync
/// updates re-render only this row, never the whole console header.
private struct LiveHeaderStats: View {
    @EnvironmentObject private var live: LiveState
    let activeConnection: Bool
    /// Resolved by the parent (#2075), so the charge below can belong to the device being named.
    let activeIsWhoop: Bool
    /// #218: an Oura ring streams live HR WITHOUT a WHOOP bond, so `activeConnection` (which needs the bond)
    /// is false for it and the wear stat read "—" mid-stream. A live HR stream is itself the wear signal
    /// (Oura only emits PPG HR while worn). `streamingLiveHR` is Oura-only, so this never widens WHOOP.
    private var ringStreaming: Bool { live.connected && live.streamingLiveHR }
    private var liveLink: Bool { activeConnection || ringStreaming }

    /// The ACTIVE device's charge (#2075). A non-WHOOP active device never falls back to the strap's
    /// number: an em dash says "not reported", where the strap's charge under the ring's name is a
    /// confident lie, and was exactly what the report saw.
    private var batteryLabel: String {
        LiveConsoleReadout.batteryPercent(
            activeIsWhoop: activeIsWhoop, whoopPct: live.batteryPct, ringPct: live.ouraBatteryPct,
        ).map { StrapLogReader.strapLogPercent($0) } ?? "—"
    }

    /// A streaming Oura ring is definitionally worn (PPG needs skin contact), and `worn` isn't reset on a
    /// source switch — so a stale `worn=false` from a prior WHOOP WRIST_OFF must not read "Off wrist"
    /// mid-stream. For WHOOP `ringStreaming` is always false, so this is just `live.worn`. #218.
    private var wornNow: Bool {
        // An Oura ring reports a precise live wear/charge state (live-HR presence + charger STATE + a
        // removal watchdog), so prefer it — it drops to not-worn the moment the ring is off the finger or
        // on the charger, unlike `ringStreaming`, which lingers. WHOOP has no such signal (ouraWearState
        // stays nil), so it keeps the bond-worn / stream fallback. #218.
        if let w = live.ouraWearState { return w == .worn }
        return live.worn || ringStreaming
    }

    /// Three equal columns, each a label over its value (the device's name is in the line above). The last
    /// sync error, when there is one, sits under them: it was the only fact of the former Signal Trust rail
    /// that nothing else on the screen states.
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                stat(String(localized: "Battery"), batteryLabel)
                stat(String(localized: "On wrist"),
                     liveLink ? (wornNow ? String(localized: "Yes") : String(localized: "No")) : "—")
                stat(String(localized: "History"), historyLabel)
            }
            if let error = live.lastSyncError {
                Text(error)
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.statusWarning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textSecondary)
            Text(value)
                .font(StrandFont.headline)
                .foregroundStyle(StrandPalette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var historyLabel: String {
        live.backfilling ? String(localized: "Syncing…") : LiveSyncFormat.lastSyncLabel(live.lastSyncedAt)
    }
}

/// The console centrepiece's HR half: a live BPM LiquidVessel (fills to the HR-zone fraction) with the
/// count-up numeral over it, the zone label, and the trust caption. Owns LiveState so the ~1 Hz HR notify
/// re-renders only this leaf. The vessel replaces the old flat pulse-ring, the count-up number replaces
/// the CountUpText numeral.
private struct LiveHeartReadout: View {
    /// Resolved by the parent (#2075); this leaf does not re-derive it.
    let activeIsWhoop: Bool
    /// Resolved by the parent (#2305), same reason.
    let activeIsOura: Bool
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState
    let hrMax: Int

    /// Smoothed, spike-filtered live HR from AppModel (median over a short window).
    private var displayHR: Int? { model.bpm }
    private var activeConnection: Bool { activeIsWhoop && live.connected && live.bonded }

    /// The live HR zone for the focal readout's colour world (presentation only). 0 = below Zone 1.
    private var liveZone: Int {
        guard let bpm = displayHR else { return 0 }
        return model.profile.hrZoneSet.zoneNumber(forBPM: Double(bpm))
    }

    /// The focal vessel / numeral colour: the live HR-zone hue when streaming, the Effort world otherwise.
    private var hrTint: Color {
        guard displayHR != nil else { return StrandPalette.textTertiary }
        return liveZone >= 1 ? StrandPalette.hrZoneColor(liveZone) : StrandPalette.effortColor
    }

    /// The vessel fill: HR as a fraction of the profile's max HR (nil = empty, no data yet).
    private var hrFrac: Double? {
        guard let bpm = displayHR, hrMax > 0 else { return nil }
        return max(0.02, min(1, Double(bpm) / Double(hrMax)))
    }

    @State private var shown: Double = 0

    var body: some View {
        let tint = hrTint
        return VStack(alignment: .center, spacing: NoopMetrics.space2) {
            ZStack {
                // The live BPM gauge: a liquid vessel that fills to the HR-zone fraction and sloshes.
                LiquidVessel(value: hrFrac, tint: tint, animated: displayHR != nil)
                    .frame(width: 210, height: 210)
                VStack(spacing: 0) {
                    // The big focal HR numeral counts up to the live value (the hero number); a crisp
                    // em-dash while there's no HR yet.
                    if displayHR != nil {
                        CountUpNumber(value: shown, font: StrandFont.rounded(88, weight: .semibold))
                            .foregroundStyle(tint)
                            .shadow(color: .black.opacity(0.4), radius: 6, y: 1)
                    } else {
                        Text("—")
                            .font(StrandFont.rounded(88, weight: .semibold))
                            .foregroundStyle(StrandPalette.textTertiary)
                    }
                    Text("bpm")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                    if liveZone >= 1 {
                        HStack(spacing: 4) {
                            Text("Zone")
                            Text(liveZone, format: .number)
                        }
                            .font(StrandFont.subhead.weight(.semibold))
                            .foregroundStyle(tint)
                            .padding(.top, NoopMetrics.space1)
                    }
                }
                .allowsHitTesting(false)   // taps fall through to the vessel → splash
            }
            .frame(width: 210, height: 210)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(displayHR.map { "Heart rate \($0) beats per minute" } ?? "Heart rate not available")
            if let caption = signalTrustSummary {
                Text(caption)
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear { rollTo(displayHR) }
        .onChangeCompat(of: displayHR) { rollTo($0) }
    }

    /// Roll the count-up numeral to the new HR, matching the vessel's fill animation.
    private func rollTo(_ v: Int?) {
        guard let v else { shown = 0; return }
        withAnimation(.easeOut(duration: 0.6)) { shown = Double(v) }
    }

    /// What the number does not say by itself, in plain words; nothing when the link is complete, since the
    /// header already states it (personal fork, Démarrer tools).
    private var signalTrustSummary: String? {
        if activeConnection && live.encryptedBond { return nil }
        if activeConnection { return String(localized: "Live heart rate works. Buzz, alarm and history sync need a full pairing.") }
        // A ring reads its OWN phase (#2305, #2304): `live.connected` here is whichever source last
        // wrote it, and under a ring parked in the nonce handshake it read "Connected, waiting for a
        // streaming state" for an hour (#2303). The ring's phase is what the console should say.
        if activeIsOura { return LiveRingCopy.status(model.ouraLinkPhase, streaming: live.connected && live.streamingLiveHR) }
        if live.connected { return String(localized: "Connected, waiting for the heart rate.") }
        // The actionable "Scan and connect…" CTA now lives in `offlineConnectCallout` above the fold, so
        // this caption stays a calm empty-state descriptor rather than a second, competing CTA.
        return String(localized: "Your heart rate appears here once the strap is connected.")
    }
}

/// The console centrepiece's physiology half: the live R-R thread/tube, rolling RMSSD, and the
/// R-R / Frame / Event proof tiles. Owns LiveState so the ~1 Hz R-R / frame notifies re-render only
/// this leaf, never the whole console.
private struct LivePhysiology: View {
    @EnvironmentObject private var live: LiveState
    /// Resolved by the parent (#2075). Passed rather than observed so this leaf keeps owning only
    /// LiveState, which is what makes the ~1 Hz R-R / frame notifies re-render it alone.
    let activeIsWhoop: Bool

    private var activeConnection: Bool { activeIsWhoop && live.connected && live.bonded }
    /// Oura ring actively streaming live HR — trusted stream without a WHOOP bond (see LiveView.ringStreaming).
    private var ringStreaming: Bool { live.connected && live.streamingLiveHR }

    /// The HRV of the last beats, shown only when it is believable, over the time between beats. The former
    /// headline (« Full strap stream is active ») repeated the header, and the R-R / Frame / Event tiles were
    /// protocol internals (the strap log keeps them).
    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space3) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("HRV right now")
                        .font(StrandFont.headline)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text(hrvNote)
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if let rmssd = shownRMSSD {
                    Text("\(Int(rmssd.rounded())) ms")
                        .font(StrandFont.number(24))
                        .foregroundStyle(StrandPalette.metricCyan)
                } else {
                    Text("—")
                        .font(StrandFont.number(24))
                        .foregroundStyle(StrandPalette.textTertiary)
                }
            }
            .accessibilityElement(children: .combine)
            rrTrace
        }
    }

    /// The rolling RMSSD when it is believable (`LiveHRVReadout`).
    private var shownRMSSD: Double? { LiveHRVReadout.shownRMSSD(rollingRMSSD) }

    private var hrvNote: String {
        if shownRMSSD != nil { return String(localized: "Over the last beats: an indication, not your night HRV.") }
        if rollingRMSSD != nil { return String(localized: "Too unsettled for a reliable figure: stay still for a minute.") }
        if activeConnection || ringStreaming { return String(localized: "Waiting for enough beats.") }
        return String(localized: "Needs the live stream.")
    }

    /// The recent R-R buffer as a liquid thread — the proof the console is genuinely live (a single HR
    /// number can look frozen; a moving trace can't). Empty state shows a calm caption.
    private var rrTrace: some View {
        let values = Array(live.rrRecent.suffix(18)).map(Double.init)
        return VStack(alignment: .leading, spacing: 8) {
            if values.count >= 2 {
                // The liquid HR thread, tinted cyan for R-R — matches the Today live-HR trace.
                LiquidThread(bpm: values, tint: StrandPalette.metricCyan, height: 44, animated: true)
                    .accessibilityHidden(true)
            } else {
                // Empty: a muted static tube so the strip reads as "waiting", not broken.
                LiquidTube(frac: 0, tint: StrandPalette.metricCyan, height: 12, animated: false)
                    .accessibilityHidden(true)
            }
            Text(values.isEmpty
                 ? String(localized: "Waiting for the time between beats.")
                 : String(localized: "Time between beats: \(values.suffix(5).map { String(Int($0)) }.joined(separator: " · ")) ms"))
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    /// A "feel" RMSSD over the recent R-R buffer — time-gap-unaware on purpose (a live indicator, not a
    /// clinical figure; it's blanked on disconnect by clearBiometrics). nil until ≥3 intervals land.
    private var rollingRMSSD: Double? {
        let values = Array(live.rrRecent.suffix(12)).map(Double.init)
        guard values.count >= 3 else { return nil }
        let diffs = zip(values.dropFirst(), values).map { $0 - $1 }
        let meanSquare = diffs.map { $0 * $0 }.reduce(0, +) / Double(diffs.count)
        return sqrt(meanSquare)
    }
}

/// The active-workout live stats (HR / avg / peak / effort) + a liquid effort tube. Owns LiveState +
/// AppModel so the 1 Hz HR/effort refresh re-renders only this block.
private struct ActiveWorkoutLive: View {
    @EnvironmentObject private var model: AppModel
    let workout: AppModel.ActiveWorkout
    let effortScale: EffortScale

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: NoopMetrics.gap) {
                stat("HR", model.bpm.map { "\($0)" } ?? "—",
                     tint: model.bpm == nil ? StrandPalette.textPrimary : StrandPalette.metricRose)
                stat(String(localized: "Avg"), workout.avgHr > 0 ? "\(workout.avgHr)" : "—")
                stat(String(localized: "Peak"), workout.peakHr > 0 ? "\(workout.peakHr)" : "—")
                stat(String(localized: "Effort"), UnitFormatter.effortDisplay(workout.liveStrain, scale: effortScale),
                     tint: StrandPalette.strainColor(workout.liveStrain))
            }
            // A liquid effort tube — the live effort as a fraction of the 0–100 strain axis.
            LiquidTube(frac: max(0, min(1, workout.liveStrain / 100)),
                       tint: StrandPalette.strainColor(workout.liveStrain), height: 10, animated: true)
                .accessibilityHidden(true)
        }
    }

    private func stat(_ title: String, _ value: String, tint: Color = StrandPalette.textPrimary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(StrandFont.overline).tracking(StrandFont.overlineTracking)
                .foregroundStyle(StrandPalette.textSecondary)
            Text(value).font(StrandFont.number(17))
                .foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Shared sync-label formatting

/// The "last sync" relative-time label of the header stats.
private enum LiveSyncFormat {
    static func lastSyncLabel(_ ts: TimeInterval?) -> String {
        guard let ts else { return String(localized: "Never") }
        let date = Date(timeIntervalSince1970: ts)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Ring status copy (#2305)

/// One line per ring link phase, shared by the console centrepiece caption, the above-the-fold callout
/// and the controls row so the three never disagree about what the ring is doing.
enum LiveRingCopy {
    static func status(_ phase: OuraLiveSource.LinkPhase, streaming: Bool) -> String {
        switch phase {
        case .disconnected:   return String(localized: "Ring not connected.")
        case .connecting:     return String(localized: "Connecting to the ring…")
        case .authenticating: return String(localized: "Connected, authenticating…")
        case .authenticated:
            return streaming
                ? String(localized: "Live heart rate is flowing from the ring.")
                : String(localized: "Connected, waiting for live heart rate.")
        }
    }
}

/// Whether the Live screen's rolling RMSSD is shown (personal fork, Démarrer tools). It is a « feel » figure
/// over the last twelve beats, so one missed or doubled beat throws it to several hundred milliseconds (a
/// 454 ms reading was seen beside a resting 95 bpm). Above the ceiling it reads « too unsettled » instead of
/// a number: resting RMSSD rarely exceeds about 200 ms even in very fit adults.
enum LiveHRVReadout {
    static let ceilingMs: Double = 250

    static func shownRMSSD(_ rmssd: Double?) -> Double? {
        guard let rmssd, rmssd.isFinite, rmssd > 0, rmssd <= ceilingMs else { return nil }
        return rmssd
    }
}
