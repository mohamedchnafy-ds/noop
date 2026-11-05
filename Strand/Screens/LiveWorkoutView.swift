import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// Live workout mode (#238) — the in-exercise screen, all from the SAME live feed and scorers the rest
/// of the app uses (no invented numbers). Presented while a manual workout is active, entered from the
/// Start-workout control on Live. End stops the workout and dismisses. Personal fork, chantier 8: the
/// content is `LiveWorkoutDashboard` (design A, a cardio and a strength layout), rebuilt every second
/// from the workout by `LiveWorkoutLiveContent`; the time shows once, and the bottom row holds the three
/// controls alone, so it covers no figure.
///
/// Live HR is the smoothed `AppModel.bpm`; the zone is derived from the user's HR-max via the shared
/// `HRZones` model; elapsed time ticks from the workout's start (a TimelineView, no manual Timer);
/// effort is the running `ActiveWorkout.liveStrain` (StrainScorer over the captured window).
struct LiveWorkoutView: View {
    @EnvironmentObject private var model: AppModel
    // PERF (scroll/recompose): this screen deliberately does NOT observe `LiveState` directly. A connected
    // strap publishes `LiveState` ~1 Hz (HR + each R-R packet, plus sensor frames), and an
    // `@EnvironmentObject live` here would invalidate the WHOLE body on every tick — the HR hero, effort
    // gauge, zone rail and stats grid all re-evaluate even though they read from `model` (smoothed bpm +
    // scorers), not `live`. The only region that genuinely needs `live` is the additive sensor readout
    // (speed / cadence / power), so it's extracted into the small `SensorRowIfPresent` leaf below that
    // owns its OWN `@EnvironmentObject live`. A sensor/R-R packet now re-renders just that row, not the
    // hero. (`model.live` is its own ObservableObject, so the leaf's `live` is the one that sees the
    // @Published changes — exactly as the parent's direct observation did before.)
    let onClose: () -> Void
    /// Fork chantier 12, effect E: the sport to start when the screen opens, after 3 · 2 · 1 · Go when the
    /// countdown is on (`WorkoutCountdownPrefs`): the recording starts at the « Go ». Nil when the workout
    /// already runs.
    var startingSport: String? = nil

    /// Keep the screen awake while recording (#703). Opt-in, default off; the toggle lives in Settings.
    /// Read here so we can hold the idle timer off only while this in-exercise screen is up and release it
    /// the moment it leaves, which is exactly the bounded usage Apple asks for. iOS-only (no-op on Mac).
    @AppStorage("workoutKeepScreenOn") private var keepScreenOn = false

    /// Guards the destructive End action behind a confirm (#517) — a stray tap on the compact exit
    /// control must not end the workout instantly with no way back.
    @State private var showEndConfirm = false
    @State private var showDeleteConfirm = false
    /// Fork chantier 12: the countdown running, and the scoreboard shown once the workout is saved.
    @State private var countingDown = false
    @State private var scoreboard: LiveWorkoutScoreboard?
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                LiveWorkoutLiveContent(recorder: model.gpsRecorder)
                // Live-observing leaf: renders the sensor row only when a standard fitness sensor is
                // feeding metrics, refreshing on its own packets (scroll-stutter isolation).
                SensorRowIfPresent()
            }
            .screenPadding()
            .padding(.top, NoopMetrics.space4)
            .padding(.bottom, NoopMetrics.space8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        #if os(iOS)
        // #697/#horizontal-swipe parity, see ScreenScaffold. This is the full-screen in-exercise
        // tracker, up for the whole workout, so worth the same defensive fix.
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        #endif
        // The three controls sit in the bottom safe area, so the scroll content ends above them and no
        // figure is ever under a button.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomControlRow
        }
        // Fork chantier 7/8: the flat black base of style F, no scenic backdrop.
        .background(StrandPalette.surfaceBase.ignoresSafeArea())
        // If the workout ended elsewhere (process restart cleared it), close the screen; not while the
        // scoreboard of the workout just saved is up (fork chantier 12).
        .onChangeCompat(of: model.activeWorkout == nil) { gone in if gone && scoreboard == nil { onClose() } }
        .overlay {
            if countingDown, let sport = startingSport {
                NoopCountdown(goLabel: Text("Go"),
                              onGo: { if model.activeWorkout == nil { model.startWorkout(sport: sport) } },
                              onEnd: { withAnimation(.easeOut(duration: 0.25)) { countingDown = false } })
                    .transition(.opacity)
            }
        }
        .overlay {
            if let scoreboard {
                LiveWorkoutScoreboardView(figures: scoreboard, onClose: onClose)
                    .transition(.opacity)
            }
        }
        // Arm the realtime HR stream while the in-exercise screen is up (#681). On a WHOOP 5/MG live HR
        // only flows while the puffin realtime stream is armed; previously only the Live tab armed it, so
        // starting a manual workout straight from Workouts (Live never opened) left `model.bpm == nil` —
        // captureWorkoutSample bailed on every sample and endWorkout silently discarded the empty
        // session. Ref-counted in AppModel, so when this sheet sits over an already-armed Live tab the
        // two balance and neither disarms the other (mirrors Android LiveWorkoutScreen's DisposableEffect
        // requestRealtimeHr/releaseRealtimeHr). Balanced: one start on appear, one stop on disappear.
        .onAppear {
            // Fork chantier 12, effect E: the recording starts at the « Go » of the countdown, or now.
            if let sport = startingSport, model.activeWorkout == nil {
                if WorkoutCountdownPrefs.isOn() { countingDown = true } else { model.startWorkout(sport: sport) }
            }
            model.startRealtimeHR()
            // Hold the display awake for the session only if the user opted in (#703).
            if keepScreenOn { ScreenIdle.keepAwake(true) }
        }
        .onDisappear {
            model.stopRealtimeHR()
            // Always release on the way out so the system idle timer resumes. Even if the toggle was
            // flipped off mid-workout, this clears any hold we placed.
            ScreenIdle.keepAwake(false)
        }
        // Confirm before ending (#517): ending still requires an explicit confirm so a stray tap on the
        // compact exit control cannot discard the in-progress recording with no way back.
        .alert("End this workout?",
               isPresented: $showEndConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("End", role: .destructive) {
                // Fork chantier 12, effect F: the figures as they stand, shown once the workout is saved.
                let shown = model.activeWorkout.map {
                    LiveWorkoutScoreboard.liveScoreboard($0, scale: UnitPrefs.resolveEffortScale(effortScaleRaw))
                }
                scoreboard = shown
                model.endWorkout()
                if shown == nil { onClose() }
            }
        } message: {
            Text("This stops recording and saves what's captured so far. It can't be resumed.")
        }
        .confirmationDialog("Delete", isPresented: $showDeleteConfirm,
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                model.discardWorkout()
                onClose()
            }
            Button("Cancel", role: .cancel) { }
        }
    }

    // MARK: - Bottom floating controls

    /// Diameter of the two side controls; Pause, in the middle, is larger and white.
    private static let bottomControlDiameter: CGFloat = 56
    private static let pauseDiameter: CGFloat = 72

    /// Delete · Pause · End, centred, alone in the bottom safe area (fork chantier 8, design A). The
    /// elapsed time is no longer repeated here: it shows once, at the top of the content, so nothing in
    /// this row can collide with or cover a figure (the earlier bar truncated its own clock to « 0: »).
    private var bottomControlRow: some View {
        HStack(spacing: 22) {
            deleteWorkoutGlassButton
            pauseWorkoutButton
            endWorkoutGlassButton
        }
        .frame(maxWidth: .infinity)
        .padding(.top, NoopMetrics.space3)
        .padding(.bottom, NoopMetrics.space3)
        .background(StrandPalette.surfaceBase.opacity(0.92).ignoresSafeArea(edges: .bottom))
    }

    private var endWorkoutGlassButton: some View {
        Button { showEndConfirm = true } label: {
            Image(systemName: "stop.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(StrandPalette.textPrimary)
                .frame(width: Self.bottomControlDiameter, height: Self.bottomControlDiameter)
                .contentShape(Circle())
        }
        .nativeLiquidGlassWorkoutControl()
        .accessibilityLabel(Text("End workout"))
        .accessibilityHint(Text("Stops recording and saves what's captured so far"))
    }

    private var pauseWorkoutButton: some View {
        let paused = model.activeWorkout?.isPaused == true
        return Button { model.toggleWorkoutPause() } label: {
            Image(systemName: paused ? "play.fill" : "pause.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(StrandPalette.surfaceBase)
                .frame(width: Self.pauseDiameter, height: Self.pauseDiameter)
                .background(StrandPalette.textPrimary, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(LiquidPressStyle())
        .accessibilityLabel(Text(paused ? "Resume" : "Pause"))
    }

    private var deleteWorkoutGlassButton: some View {
        Button { showDeleteConfirm = true } label: {
            Image(systemName: "trash")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(StrandPalette.statusCritical)
                .frame(width: Self.bottomControlDiameter, height: Self.bottomControlDiameter)
                .contentShape(Circle())
        }
        .nativeLiquidGlassWorkoutControl()
        .accessibilityLabel(Text("Delete"))
    }
}

// MARK: - Native Liquid Glass workout controls

private extension View {
    /// Platform-owned circular chrome for the live-workout bottom controls. iOS 26 uses the interactive
    /// Liquid Glass button material; macOS and older iOS keep the same circular geometry with the
    /// same native-system material fallback the Home header buttons already use.
    @ViewBuilder
    func nativeLiquidGlassWorkoutControl() -> some View {
        self.nativeLiquidGlassButtonChrome(controlSize: .large) {
            self
                .buttonStyle(LiquidPressStyle())
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.16), lineWidth: 0.8))
        }
    }
}

// MARK: - Live-observing leaf (scroll-stutter isolation)

/// Additive readout for a connected standard fitness sensor (a footpod / bike speed-cadence sensor /
/// power meter) feeding RSC/CSC/CPS ALONGSIDE heart rate. Only the fields the sensor actually sent
/// render — each metric is dropped when its value is absent, and the WHOLE block (panel + entrance stagger)
/// is hidden when nothing is present (`live.hasSensorMetrics`), so a plain HR-only workout looks exactly
/// as before. Speed follows the exercise-distance preference; cadence stays per-minute and power in watts.
/// Tinted with the Effort world so it reads as part of the hero, not a competing accent. Nothing
/// here touches HR / zone / effort.
///
/// This is a standalone leaf that owns its OWN `@EnvironmentObject live` (the parent `LiveWorkoutView`
/// no longer observes `LiveState`), so an incoming sensor / R-R packet re-renders only this row, not the
/// HR hero / effort gauge / zone rail above. The gate, layout and `staggeredAppear(index: 5)` are
/// preserved verbatim (index bumped to 7 — 6 after the glanceable layout split TIME / HR / Effort / zone
/// into separate stagger slots, then 7 after the live distance/pace card #1195 took the slot before it),
/// so the rendered output matches the previous inline code.
private struct SensorRowIfPresent: View {
    @EnvironmentObject private var live: LiveState
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.distanceSystemKey) private var distanceSystemRaw = ""
    private var distanceUnitSystem: UnitSystem {
        UnitPrefs.resolveDistance(
            system: UnitSystem(rawValue: unitSystemRaw) ?? .metric,
            override: distanceSystemRaw)
    }

    var body: some View {
        if live.hasSensorMetrics {
            let speed = UnitFormatter.speedFromKilometersPerHour(
                live.sensorSpeedKmh, system: distanceUnitSystem)
            let cadence = LiveState.formatCadence(live.sensorCadence)
            let power = LiveState.formatPowerWatts(live.sensorPowerWatts)
            NoopCard(padding: NoopMetrics.cardInnerPadding) {
                VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                    Text("SENSOR")
                        .font(StrandFont.overline)
                        .foregroundStyle(StrandPalette.textSecondary)
                    HStack(spacing: NoopMetrics.gap) {
                        if let speed { stat(String(localized: "SPEED"), speed, tint: StrandPalette.effortColor) }
                        if let cadence { stat(String(localized: "CADENCE"), "\(cadence)/min", tint: StrandPalette.effortColor) }
                        if let power { stat(String(localized: "POWER"), "\(power) W", tint: StrandPalette.effortColor) }
                    }
                }
            }
            .staggeredAppear(index: 7)
        }
    }

    /// Compact sensor value used inside this leaf's shared panel, keeping its high-frequency updates
    /// isolated from the rest of the workout screen.
    private func stat(_ title: String, _ value: String, tint: Color = StrandPalette.textPrimary) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space1) {
            Text(title)
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textSecondary)
            Text(value)
                .font(StrandFont.number(26))
                .foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - The dashboard, rebuilt every second (personal fork, chantier 8)

/// Builds `LiveWorkoutFigures` from the workout in progress once a second and draws them. It observes the
/// GPS recorder itself, so a fix refreshes the distance, the splits and the pace of the moment.
private struct LiveWorkoutLiveContent: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var recorder: GpsWorkoutRecorder
    /// Effort display scale (#268): the live Effort reads through the shared helper, one format.
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.distanceSystemKey) private var distanceSystemRaw = ""

    private var distanceSystem: UnitSystem {
        UnitPrefs.resolveDistance(system: UnitSystem(rawValue: unitSystemRaw) ?? .metric,
                                  override: distanceSystemRaw)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let workout = model.activeWorkout {
                LiveWorkoutDashboard(figures: liveFigures(workout, now: context.date),
                                     distanceSystem: distanceSystem, animated: true)
            }
        }
    }

    private func liveFigures(_ workout: AppModel.ActiveWorkout, now: Date) -> LiveWorkoutFigures {
        let samples = workout.samples
        let scale = UnitPrefs.resolveEffortScale(effortScaleRaw)
        let effortValue = UnitFormatter.effortValue(workout.liveStrain, scale: scale)
        let effortMax = scale == .whoop ? 21.0 : 100.0
        // The same calories estimate, with the same measured resting heart rate, that `endWorkout` saves.
        let restingHR = model.repo.today?.restingHr.map(Double.init) ?? StrainScorer.defaultRestingHR
        let profile = UserProfile(weightKg: model.profile.weightKg, heightCm: model.profile.heightCm,
                                  age: Double(model.profile.age), sex: model.profile.sex)
        let kcal = samples.count >= 2
            ? Calories.estimateBoutCalories(samples, profile: profile, hrmax: Double(model.profile.hrMax),
                                            restingHR: restingHR).0
            : 0
        let zoneSet = model.profile.hrZoneSet
        let recording = recorder.isRecording && recorder.pointCount > 0
        let route = recorder.liveRoute
        let unitMeters = distanceSystem == .imperial ? 1609.344 : 1000
        return LiveWorkoutFigures(
            layout: LiveWorkoutMath.layout(sport: workout.sport, recordingRoute: recording),
            sportName: WorkoutSource.displaySport(workout.sport),
            isPaused: workout.isPaused,
            elapsedSeconds: Int(workout.elapsed(at: now)),
            bpm: model.bpm,
            zone: model.bpm.map { zoneSet.zoneNumber(forBPM: Double($0)) } ?? 0,
            effort: UnitFormatter.effortDisplay(workout.liveStrain, scale: scale),
            effortState: StrainGauge.stateLabel(forFraction: min(max(effortValue / effortMax, 0), 1)),
            kcal: kcal > 0 ? Int(kcal.rounded()) : nil,
            averageHr: workout.avgHr > 0 ? workout.avgHr : nil,
            peakHr: workout.savedPeak,
            distanceM: recording ? recorder.distanceM : nil,
            currentPaceSecPerKm: recording ? LiveWorkoutMath.currentPace(route, pauses: recorder.pauseSpans) : nil,
            splits: recording ? LiveWorkoutMath.splits(route, unitMeters: unitMeters, pauses: recorder.pauseSpans) : [],
            zoneSeconds: LiveWorkoutMath.zoneSeconds(samples, zoneSet: zoneSet),
            curve: LiveWorkoutMath.recentCurve(samples, now: Int(now.timeIntervalSince1970)))
    }
}
