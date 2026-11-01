import SwiftUI
import Foundation
import StrandDesign
import StrandAnalytics
import WhoopStore
#if canImport(UIKit)
import UIKit
#endif

// MARK: - SleepView
//
// Personal fork, redesigned (canvas "NOOP – Écran Sommeil", direction A). Scannable in two seconds:
//   0. The top section over the night scene: title + Alarms / Customize buttons, the night picker, the
//      night dial (score, time asleep, bed → wake, the stages on a 12-hour face, the need counted back
//      from the wake time), the stage totals, the bed/wake row that opens the editor, tonight's target.
//   1. The stages card: the stage lanes with the curves the user switches on (heart rate by default,
//      rMSSD, skin temperature, movement), the stage totals, honest caveats, why / add-a-nap.
//   2. The indicators: efficiency, restorative, breathing, lowest heart rate, each in its own colour.
//   3. "Your nights": the sleep debt and the hours of each night against the need, 14 nights or 30 days.
//   "Stages vs typical" joins once there are five nights to compare with.
//
// One stage palette (Settings → Appearance → Sleep chart), one duration format, one sleep need. Data
// wiring is unchanged from the previous screen (stagesJSON minutes, typical = mean of repo.days).

struct SleepView: View {
    @EnvironmentObject var repo: Repository
    @EnvironmentObject private var router: NavRouter
    // NOTE: SleepView itself deliberately does NOT observe `LiveState` OR `AppModel`. A connected strap
    // publishes at ~1 Hz, and `AppModel` itself publishes `bpm` at that same ~1 Hz (AppModel.swift:202) —
    // `@EnvironmentObject` subscribes to the WHOLE object's `objectWillChange` regardless of which
    // properties are read, so holding either here would re-evaluate this heavy ~3000-line body on every
    // tick. The live dependencies — the "going to sleep / awake" mark card (appends to the strap log),
    // the "Syncing strap history…" note, and the body-clock dial's `circadianPhase` (#1680) — each own
    // their OWN `@EnvironmentObject var live`/`appModel` in a small leaf below (mirrors the Today
    // leaf-scoping pattern and HealthView.swift:17-22), so a tick refreshes only that leaf.
    @EnvironmentObject var intelligence: IntelligenceEngine

    /// Memoized snapshot of every expensive derivation (latest Night with its intervals
    /// resolved once, the seven metric series, the trend points, the typical means). Rebuilt
    /// only when the underlying repo data actually changes — NOT on hover/animation/1Hz HR
    /// ticks that merely re-evaluate `body`. `nil` until first build or when there's no night.
    @State private var model: SleepModel?
    /// The Sleep tab's stage-chart shape (Settings → Appearance → Sleep chart). Display-only; Filled/Ribbon
    /// draw the WHOOP-style stepped hypnogram, Classic keeps the per-stage rows. Mirrors Android. (#sleep-chart-style)
    @AppStorage(SleepChartStyle.storageKey) private var sleepChartStyleRaw = SleepChartStyle.classic.rawValue
    /// Personal fork: the curves over the stage lanes. Heart rate is on by default; rMSSD, skin
    /// temperature and movement are switched on from the chips above the lanes. Display-only.
    @AppStorage(SleepCurvePrefs.hrKey) private var showSleepHR = true
    @AppStorage(SleepCurvePrefs.hrvKey) private var showHRVCurve = false
    @AppStorage(SleepCurvePrefs.skinTempKey) private var showSkinTempCurve = false
    @AppStorage(SleepCurvePrefs.motionKey) private var showMotionCurve = false
    /// The displayed night's windowed rMSSD and skin temperature, loaded with its heart rate.
    @State private var nightHRV: [TrendPoint] = []
    @State private var nightSkinTemp: [TrendPoint] = []
    /// The repo signature the cached `model` was built from. Cheap to compute every render;
    /// when it differs from the current inputs we rebuild the model.
    @State private var modelKey: SleepInputKey?
    @State private var loadedSleepRefresh: Int?
    @State private var resultTracker = SleepResultChangeTracker()
    @State private var resultNoticeVisible = false
    @State private var resultNoticeRevision = 0
    @State private var resultNoticeScope: String?

    /// Which night the hero hypnogram shows: 0 = last night, N = N sleep-sessions back.
    /// Snaps back to 0 whenever the data key changes — a stale offset would silently point
    /// at a different session after a sync. The memoized trend `model` stays cached since
    /// the trends are night-independent. (#160)
    @State private var nightOffset = 0
    /// Memoized decode of the NAVIGATED night (nil when `nightOffset == 0` — the hero reads
    /// `model.night` then). Rebuilt only in the `nightOffset` / data-key onChange handlers;
    /// `decodedNight` JSON-decodes, which must never run per body pass (1Hz HR ticks). (#160)
    @State private var navNight: Night?

    /// Every sleep BLOCK across both sources, UN-deduplicated (`repo.allSleepSessions`) — `repo.sleeps`
    /// keeps one winner per night for the dashboard, collapsing split-sleep days (a nap + a main
    /// sleep on the same day) into a single block. The hero groups these by day (`navDays`) and
    /// merges each day into one Night, so a split day reads as one correctly-totalled night with the
    /// gaps preserved. Oldest→newest. Falls back to `repo.sleeps` until loaded. (#170)
    @State private var allSessions: [CachedSleepSession] = []
    /// `navDays` memoized, rebuilt where `model` is.
    ///
    /// Grouping calls `Calendar.startOfDay` once per session, and the browsable history is every block
    /// ever recorded, so recomputing it per render is a per-frame pass over years of nights. Body reaches
    /// it more than once (the wake-timestamp list, and `dayBlocks(at:)` for the source blocks), so a
    /// scroll paid it repeatedly. Invalidated by the same two paths that rebuild `model`: `dataKey`
    /// covers a `repo.sleeps` change, and the refresh task covers `allSessions` reloading. Nil falls back
    /// to computing it, so a first render before either has run is correct rather than empty.
    @State private var navDaysCache: [[CachedSleepSession]]?

    /// The user's LEARNED habitual midsleep (local time-of-day seconds), or nil under the cold-start
    /// threshold. Loaded from `repo.habitualMidsleepSec()` — the SAME value `AnalyticsEngine.analyzeDay`
    /// threads into the daily total — and fed into the main-night selector so the hero, the naps split,
    /// and the edit target pick the SAME block the analytics rollup did, for a shift/late sleeper too. nil
    /// keeps the existing cold-start overnight-band fallback. (#547) Refreshed with `allSessions`.
    @State private var habitualMidsleepSec: Int? = nil

    /// Persisted per-epoch MOTION series keyed by each session's detected `startTs` (#407). Loaded in the
    /// same `.task` as `allSessions` from `repo.sessionMotions(sessions:)`, then laid along the hypnogram for
    /// the SAME main-night GROUP blocks the hero resolved (mergeDay's group) — we do NOT re-resolve the
    /// night, only read the already-chosen group's stored motion. A block with no stored series stays absent
    /// (honest empty state for older rows whose `motionJSON` is NULL). Refreshed with `allSessions`.
    @State private var motionByStart: [Int: [Double]] = [:]

    /// Non-nil while the wake-time editor sheet is open. Carries the night's stable key (`startTs`) and
    /// current wake time so the editor seeds its picker; saving routes through `repo.editSleepWakeTime`,
    /// which marks the session `userEdited` so a later strap sync can't revert the correction. (#318)
    @State private var wakeEdit: WakeEdit?

    /// Non-nil while the "Add nap" picker sheet is open (#508). Carries a seed bed/wake for the picker;
    /// saving routes through `repo.addManualNap`, which stages the chosen window from raw and writes it as
    /// its OWN separate session row (`userEdited = 1`) — never folded into the night's main sleep.
    @State private var addNap: AddNapSeed?

    /// True while the hero's "why this is your main sleep" popover is open. The reason text comes
    /// straight from the foundation `MainNightReason` for the displayed night's blocks — never
    /// re-derived here — so the explainer says exactly what the selector decided. (spec 2026-06-20 C1)
    @State private var showMainSleepWhy = false
    /// The stable detected key of the nap whose "why this is a nap" popover is open, or nil. Keyed by
    /// the nap's own `startTs` so one popover shows at a time even with several nap rows. (C1)
    @State private var napWhyStartTs: Int?

    /// WHOOP-style stage highlight: tapping a stage row under the timeline lights that stage up on the
    /// chart and recedes the rest (tap again to clear). Display-only selection state. (ryanAtriumAi #988)
    @State private var selectedStage: SleepStage? = nil

    /// Sleeping heart-rate for the displayed night (1-min buckets), for the WHOOP-style HR chart above
    /// the stage rows. Loaded once per night via `.task(id:)` on the stage card. (ryanAtriumAi #988)
    @State private var nightHR: [HRBucket] = []

    /// The transient UNDO banner shown after a suppressing delete (#65). Non-nil for ~7 seconds: carries
    /// the snapshot needed to restore the deleted night into its ORIGINAL namespace and the window text
    /// for the message. A user-created/edited delete writes no tombstone but still offers undo (restore).
    @State private var sleepUndo: SleepUndoBanner?
    /// The pending auto-dismiss task for `sleepUndo`, cancelled when a new delete replaces the banner or
    /// the user hits Undo, so a stale timer can't clear a fresh banner.
    @State private var sleepUndoTask: Task<Void, Never>?

    // #sleep-layout: the arrangeable analytical-card order + explicit hidden set, byte-identical to the
    // Android SleepLayoutPrefs keys. Reordered via the Arrange sheet; display-only, no metric changes.
    @AppStorage(SleepLayoutPrefs.orderKey) private var sleepSectionOrderRaw = ""
    @AppStorage(SleepLayoutPrefs.hiddenKey) private var sleepHiddenSectionsRaw = ""
    @State private var showSleepCustomize = false

    /// The analytical cards to render, in saved order minus the hidden set.
    private var sleepVisibleSections: [SleepSection] {
        SleepLayoutPrefs.visibleOrder(orderRaw: sleepSectionOrderRaw, hiddenRaw: sleepHiddenSectionsRaw)
    }

    var body: some View {
        // Resolve the memoized model for THIS render. `dataKey` is O(1)-ish (counts + last-row
        // identity), so comparing it every render is cheap. When it matches the cached key we
        // reuse the cached model untouched — the many body re-evaluations from hover/animation/
        // 1Hz HR ticks pay nothing. When it differs (or on first render) we build once, here,
        // synchronously, so the very first frame already shows content (no empty-state flash).
        let key = dataKey
        let resolved: SleepModel? = (key == modelKey) ? model : buildModel()
        // Title lives inside the top section (personal fork): the night dial, the night picker and the
        // Alarms / Customize buttons, over the night scene. The scene now scrolls away with that section
        // instead of staying fixed behind the cards. Empty state still gets a plain scaffold title.
        ScreenScaffold(title: resolved == nil ? "Sleep" : nil,
                       subtitle: resolved == nil ? "Last night, read in two seconds." : nil,
                       // PERF (scroll): lazy column — byte-identical layout (LazyVStack == eager VStack
                       // alignment/spacing/header), builds trailing trend/ledger cards on demand. Combined
                       // with dropping the top-level LiveState observation (the sleep-mark card + the
                       // syncing note now own `live` in their own leaves), so a 1 Hz HR tick no longer
                       // re-evaluates this heavy body.
                       onRefresh: { await repo.refresh() },
                       lazy: true,
                       topBackground: nil) {
            Group {
                if let resolved {
                    // Each top-level section fades + rises in sequence on first appear (Reduce-Motion safe).
                    VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
                        if let sleepUndo { sleepUndoBanner(sleepUndo) }
                        SleepFreshnessNote(latestWakeTs: resolved.night.session.endTs)
                        if resultNoticeVisible {
                            DataPendingNote(title: "Sleep result updated",
                                            message: "This night's sleep times or total asleep changed by at least five minutes.",
                                            symbol: "checkmark.circle")
                        }
                        // The top section answers the night in two seconds; the Alarms and Customize
                        // entries are its round buttons, so no separate Alarms card follows it.
                        // zIndex: the section's night scene reaches up behind the notes above it.
                        sleepTop(resolved)
                            .padding(.top, -12)
                            .zIndex(-1)
                            .staggeredAppear(index: 0)
                        // #sleep-layout: the analytical cards render in the user's saved order minus the
                        // hidden set, below the pinned Rest hero. Reordered via the Arrange sheet.
                        ForEach(Array(sleepVisibleSections.enumerated()), id: \.element) { idx, section in
                            sleepSectionView(section, resolved).staggeredAppear(index: idx + 1)
                        }
                    }
                } else {
                    emptyState
                    alarmsEntry
                }
            }
            // Persist the freshly-built model so subsequent renders with the same inputs hit
            // the cache. Writing State during body is not allowed, so commit it after layout;
            // `resolved` already drives THIS frame, so there is no flash and no extra rebuild.
            .onChangeCompat(of: key) { newKey in
                modelKey = newKey
                navDaysCache = SleepModel.navDays(navSessions: navSessions)
                model = buildModel()
                // New data invalidates a navigated offset — the same offset would silently
                // point at a different session. Snap back to last night. (#160)
                nightOffset = 0
                navNight = nil
            }
            // The navigated night is decoded once per ◀/▶ press, never per body pass —
            // `decodedNight` JSON-decodes and body re-evaluates at 1Hz while HR streams. (#160)
            .onChangeCompat(of: nightOffset) { newOffset in
                navNight = newOffset == 0 ? nil : decodedNight(at: newOffset)
                resetResultNotice()
                observeResultChange()
            }
            .onAppear {
                if modelKey != key {
                    modelKey = key
                    model = resolved
                    nightOffset = 0
                    navNight = nil
                }
            }
            .onChangeCompat(of: intelligence.computing) { _ in observeResultChange() }
            .onDisappear { resetResultNotice() }
            .task(id: resultNoticeRevision) {
                guard resultNoticeVisible else { return }
                do { try await Task.sleep(nanoseconds: 8_000_000_000) }
                catch { return }
                resultNoticeVisible = false
            }
            // Load EVERY sleep block across BOTH sources (un-deduplicated) so the hero's ◀/▶ can
            // browse split-sleep days the dashboard collapses — including Bluetooth-only nights,
            // whose blocks live under the computed source. Re-runs whenever a sync/import bumps
            // refreshSeq; snaps back to the newest day and rebuilds the model so offset 0 reflects
            // the freshly-loaded blocks. (#170)
            .task(id: repo.refreshSeq) {
                let refresh = repo.refreshSeq
                let sessions = await repo.allSleepSessions()
                // Load the learned habitual midsleep the engine used, so the main-night pick aligns to it
                // (a shift/late sleeper) instead of only the cold-start band. nil under threshold. (#547)
                let habitual = await repo.habitualMidsleepSec()
                // Per-epoch motion for every block (#407), keyed by detected start. mergeDay reads only the
                // already-resolved group's entries — this just pre-fetches them all so the model build is sync.
                let motions = await repo.sessionMotions(sessions: sessions)
                guard !Task.isCancelled, refresh == repo.refreshSeq else { return }
                allSessions = sessions
                habitualMidsleepSec = habitual
                motionByStart = motions
                nightOffset = 0
                navNight = nil
                modelKey = dataKey
                navDaysCache = SleepModel.navDays(navSessions: navSessions)
                model = buildModel()
                loadedSleepRefresh = refresh
                observeResultChange()
            }
            .sheet(item: $wakeEdit) { edit in
                // The night's RECORDED coverage for the #940 guards: from the immutable detected
                // onset (where the strap actually saw the night; an earlier hand-set onset widens
                // it) through the current wake. A corrected window that abandons this range has no
                // data to stage from, so the editor confirms the move instead of silently creating
                // a phantom night.
                let coverageLo = min(edit.detectedStartTs, edit.bedTs)
                SleepTimeEditor(bedTs: edit.bedTs, wakeTs: edit.wakeTs,
                                coverage: coverageLo...max(edit.wakeTs, coverageLo + 1),
                                suppressesReDetection: !edit.userEdited,
                                onSave: { newBedTs, newWakeTs in
                    await repo.editSleepTimes(detectedStartTs: edit.detectedStartTs, oldEndTs: edit.wakeTs,
                                              storedStagesJSON: edit.stagesJSON,
                                              newStartTs: newBedTs, newEndTs: newWakeTs)
                    // Re-score the day so the dashboard aggregates (Rest / recovery) honor the corrected
                    // sleep window, not just the Sleep tab's session view; then refresh the read cache.
                    await intelligence.analyzeRecent()
                    await repo.refresh()
                }, onDelete: {
                    // Delete = the edit path minus the re-insert: drop this session so every metric
                    // recomputes immediately as if the night were never recorded, durably tombstoned so a
                    // re-detect doesn't bring it back, then re-score + refresh exactly like an edit. (#68)
                    // #65: the returned snapshot lets the user UNDO within a few seconds. It restores the
                    // deleted row into its ORIGINAL namespace and lifts the tombstone.
                    let snapshot = await repo.deleteSleepSession(detectedStartTs: edit.detectedStartTs,
                                                                 endTs: edit.wakeTs)
                    await intelligence.analyzeRecent()
                    await repo.refresh()
                    // `edit.bedTs` is the effective (displayed) onset, so the banner shows the same clock
                    // time the user saw for this night.
                    if let snapshot { presentSleepUndo(snapshot, displayStart: edit.bedTs, windowEnd: edit.wakeTs) }
                })
            }
            // Manually add a missed nap (#508): same picker, but the chosen window is staged from raw and
            // stored as its OWN separate session — never folded into main sleep (which would mislabel the
            // awake daytime gap as light sleep).
            .sheet(isPresented: $showSleepCustomize) {
                SleepCustomizationSheet(
                    sectionOrderRaw: $sleepSectionOrderRaw,
                    hiddenSectionsRaw: $sleepHiddenSectionsRaw
                )
            }
            .sheet(item: $addNap) { seed in
                SleepTimeEditor(bedTs: seed.bedTs, wakeTs: seed.wakeTs,
                                title: "Add a nap",
                                blurb: "Pick when the nap started and ended. NOOP stages it from your data as its own session, separate from the night's sleep.",
                                bedLabel: "Nap started", wakeLabel: "Nap ended") { startTs, endTs in
                    await repo.addManualNap(startTs: startTs, endTs: endTs)
                    // Re-score so the day's aggregates pick up the new session, exactly like an edit.
                    await intelligence.analyzeRecent()
                    await repo.refresh()
                }
            }
        }
    }

    /// A direct route to the one alarm screen, available even before a night is recorded.
    private var alarmsEntry: some View {
        // Button OUTSIDE the card, as `InsightsView.whatMovesYouLink` and `LabBookView` do: with it inside,
        // only the row content answers a tap and the card's own padding is dead, so the same edge tap works
        // on Android (where the whole `NoopCard` is clickable) and does nothing here.
        Button { router.openAlarms() } label: {
            NoopCard(tint: StrandPalette.restColor) {
                HStack(spacing: NoopMetrics.gap) {
                    Image(systemName: "alarm.fill")
                        .foregroundStyle(StrandPalette.restColor)
                        .accessibilityHidden(true)
                    Text("Alarms")
                        .font(StrandFont.headline)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(StrandPalette.textTertiary)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        // The settle-inward every tappable liquid card gets (`InsightsView.whatMovesYouLink`,
        // `LabBookView`, `TodayView`). `.plain` would leave an edge tap with no feedback at all, where
        // Android's `Modifier.clickable` ripples.
        .buttonStyle(LiquidPressStyle())
    }

    // MARK: - 0. Top section — night dial, picker, times, tonight

    /// The top of the tab for the displayed night: the dial (score, asleep, bed → wake, stages, the
    /// need), the stage totals, the bed/wake row that opens the editor, and tonight's target on last
    /// night. Every number comes from the same model the cards below read.
    @ViewBuilder
    private func sleepTop(_ model: SleepModel) -> some View {
        let night = heroNight(model)
        let hasStages = night.stages.total > 0
        let raw = hasStages ? (nightOffset == 0 ? model.intervals : night.intervals) : []
        let score = performanceScore(for: night)
        let ledger = model.sleepDebtLedger
        let need: Double? = ledger.needMin > 0 ? ledger.needMin : nil
        let lastIndex = max(navDays.count - 1, 0)
        let target = night.editTarget
        SleepTopSection(
            data: SleepTopSection.Model(
                nightLabel: nightRelativeLabel,
                dateLabel: night.spanLabel,
                canGoBack: nightOffset < lastIndex,
                canGoForward: nightOffset > 0,
                onset: night.onsetDate,
                wake: Date(timeIntervalSince1970: TimeInterval(night.session.endTs)),
                intervals: Hypnogram.displaySmoothed(raw.sorted { $0.start < $1.start }, minDuration: 300),
                palette: stagePalette,
                score: score,
                scoreWord: score.map { sleepScoreWord($0) },
                asleepMinutes: night.stages.asleep,
                deepMinutes: night.stages.deep,
                remMinutes: night.stages.rem,
                lightMinutes: night.stages.light,
                needMinutes: need,
                timesEdited: target?.userEdited ?? false,
                canEditTimes: target != nil,
                tonight: nightOffset == 0 ? need.map { (needMinutes: $0, debtMinutes: ledger.isDebt ? ledger.magnitudeMin : 0) } : nil),
            actions: SleepTopSection.Actions(
                alarms: { router.openAlarms() },
                customize: { showSleepCustomize = true },
                previous: { if nightOffset < lastIndex { nightOffset += 1 } },
                next: { if nightOffset > 0 { nightOffset -= 1 } },
                editTimes: { openTimeEditor(night) }))
    }

    /// Open the bed/wake editor on the night's real stored main block (the hero shows a merged Night whose
    /// session is synthetic), seeded with its current effective times. A filled pencil marks a night
    /// already corrected. (#318)
    private func openTimeEditor(_ night: Night) {
        guard let target = night.editTarget else { return }
        wakeEdit = WakeEdit(detectedStartTs: target.startTs,
                            bedTs: target.effectiveStartTs,
                            wakeTs: target.endTs,
                            stagesJSON: target.stagesJSON,
                            userEdited: target.userEdited)
    }

    /// The one stage palette of the tab: the ramp of Settings → Appearance → Sleep chart, applied to the
    /// dial, the lanes, the totals and the "vs typical" card alike.
    private var stagePalette: SleepStagePalette {
        SleepChartStyle.resolve(sleepChartStyleRaw).stagePalette
    }

    /// The night's lowest sleeping heart rate and when, from the heart rate already loaded for the card.
    private var lowestHR: SleepLowestHR? {
        guard let low = nightHR.min(by: { $0.bpm < $1.bpm }) else { return nil }
        return SleepLowestHR(bpm: low.bpm, at: Date(timeIntervalSince1970: TimeInterval(low.ts)))
    }

    /// Nights the usual stage ranges are drawn from: the same trailing-30 rows `stageTypical` reads.
    private var typicalNightCount: Int {
        repo.days.suffix(30).filter { ($0.totalSleepMin ?? 0) > 0 }.count
    }

    /// `stageTypical`'s cold-start floor: no usual range from fewer nights than this.
    static let typicalMinNights = 5

    // MARK: - Delete undo (#65)

    /// Show the transient UNDO banner after a suppressing delete, and arm the 7-second auto-dismiss. A
    /// second delete replaces the banner (its old auto-dismiss task is cancelled first) so only the most
    /// recent delete is undoable. Single-level and transient, matching the WorkoutsView postLogNote idiom.
    private func presentSleepUndo(_ snapshot: SleepDeletionSnapshot, displayStart: Int, windowEnd: Int) {
        sleepUndoTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) {
            sleepUndo = SleepUndoBanner(snapshot: snapshot, identityStart: snapshot.session.startTs,
                                        displayStart: displayStart, windowEnd: windowEnd)
        }
        let armed = snapshot.session.startTs
        sleepUndoTask = Task {
            try? await Task.sleep(nanoseconds: 7_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                // Only clear if this is still the banner we armed (a newer delete would have replaced it).
                if sleepUndo?.identityStart == armed {
                    withAnimation(.easeOut(duration: 0.2)) { sleepUndo = nil }
                }
            }
        }
    }

    /// Undo the most recent suppressing delete: restore the row into its ORIGINAL namespace, lift the
    /// tombstone, re-score, then dismiss the banner.
    private func undoSleepDelete(_ banner: SleepUndoBanner) async {
        sleepUndoTask?.cancel()
        await repo.undoDeleteSleepSession(banner.snapshot)
        await intelligence.analyzeRecent()
        await repo.refresh()
        await MainActor.run { withAnimation(.easeOut(duration: 0.2)) { sleepUndo = nil } }
    }

    /// Locale-formatted clock time (no date) for the banner's window range.
    private func clockTime(_ ts: Int) -> String {
        Date(timeIntervalSince1970: TimeInterval(ts))
            .formatted(Date.FormatStyle(date: .omitted, time: .shortened)
                .locale(AppClock.formattingLocale))   // #1821
    }

    /// The transient undo strip: a Rest-tinted frosted banner with the suppressed window and a real Undo
    /// Button. role-alert-ish for VoiceOver; the Undo button carries its own explicit label.
    @ViewBuilder
    private func sleepUndoBanner(_ banner: SleepUndoBanner) -> some View {
        // Branch the copy on userEdited: a hand-edited/added night writes NO tombstone (it is never
        // re-detected), so the suppression promise would be false for it. Only a DETECTED delete writes a
        // tombstone, so only it gets the "won't detect ... again" wording. (#65 banner honesty.)
        let message = banner.snapshot.session.userEdited
            ? String(localized: "Sleep deleted.")
            : String(localized: "Sleep deleted. NOOP won't detect sleep between \(clockTime(banner.displayStart)) and \(clockTime(banner.windowEnd)) again.")
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "moon.zzz")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(StrandPalette.restColor)
                .accessibilityHidden(true)
            Text(message)
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button {
                Task { await undoSleepDelete(banner) }
            } label: {
                Text("Undo").font(StrandFont.footnote.weight(.semibold))
            }
            .buttonStyle(LiquidPressStyle())
            .foregroundStyle(StrandPalette.restColor)
            .accessibilityLabel("Undo sleep deletion")
        }
        .padding(NoopMetrics.space3)
        .background(StrandPalette.restColor.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
            .strokeBorder(StrandPalette.restColor.opacity(0.22), lineWidth: 1))
        .transition(.opacity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(message)
    }

    /// A short night-relative label ("Last night" / "1 night ago" / "N nights ago") for the
    /// ◀/▶-navigated night. Shared by the Rest hero overline and the hypnogram nav header so both
    /// name the SAME night the hero's score is now resolved for.
    private var nightRelativeLabel: String {
        let n = nightsAgo(nightOffset)
        return n == 0 ? String(localized: "Last night")
            : (n == 1 ? String(localized: "1 night ago") : String(localized: "\(n) nights ago"))
    }

    /// #1311: how many nights back the carousel night at `offset` is, counted in CALENDAR nights rather
    /// than carousel index. The ◀/▶ carousel steps by RECORDED night (`navDays`, newest-first), so a
    /// night with no data (strap off-body) is a gap the flat index can't see — labelling by index makes
    /// two nights either side of a skipped night read as consecutive and desyncs the "N nights ago"
    /// labels (and the Rest value they name).
    ///
    /// Counted FROM TODAY, not from the newest recorded night.
    ///
    /// Delegates to `SleepNightLabel.nightsAgo`, which is where this logic is tested. It lived inline
    /// and private here, which is why the newest-anchored defect went uncaught on this platform.
    /// Kotlin twin: `calendarNightsAgo`.
    private func nightsAgo(_ offset: Int, now: Date = Date()) -> Int {
        SleepNightLabel.nightsAgo(
            // Optional per entry, NOT `?? 0`: a day group with no session must fall back to the offset
            // the way the Kotlin twin does. Zero would be 1970 and would read as ~20,000 nights ago.
            wakeTimestamps: navDays.map { $0.first.map { s in Int(s.endTs) } },
            offset: offset,
            today: Repository.logicalDay(now)
        )
    }

    /// The night the Rest hero reflects: the ◀/▶-navigated night while browsing (falling back to
    /// last night only if that navigated night hasn't decoded yet), else last night. Keeps the
    /// hero's score, vessel fill, state word, provenance badge and overline on the SAME night the
    /// hypnogram shows — the fix for the score freezing on last night's value during navigation.
    private func heroNight(_ model: SleepModel) -> Night {
        (nightOffset == 0 ? model.night : navNight) ?? model.night
    }

    /// The sleep-performance score (0–100) for a SPECIFIC night: the imported WHOOP figure for that
    /// night's LOCAL wake-day when the export carried one, else the resolved Rest composite for that
    /// day. Mirrors `performanceSeries`'s per-day transform exactly (the same single source of truth
    /// the Today Rest score reads), keyed by the wake-day (sleep is filed under the day you woke) so
    /// a navigated past night reads ITS OWN score, never last night's. nil when that day has no score.
    private func performanceScore(for night: Night) -> Double? {
        let wakeDay = Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval(night.session.endTs)))
        if let p = repo.importedSleep[wakeDay]?.performancePct { return p }
        guard let daily = repo.days.last(where: { $0.day == wakeDay }) else { return nil }
        return AnalyticsEngine.Rest.composite(daily: daily)
    }

    /// Dispatch a reorderable Sleep section to its card. Naps rides with `.stages` (drawn inside the stages
    /// hero); the Rest hero is pinned outside this list. Mirrors the Android SleepScreen `when(section)`.
    @ViewBuilder
    private func sleepSectionView(_ section: SleepSection, _ model: SleepModel) -> some View {
        switch section {
        case .sleepMarks:      SleepMarkCard()
        case .stages:          hero(model)
        case .bodyClock:       bodyClockDial(model)
        // The indicators describe the latest night, so the lowest heart rate joins them only there.
        case .nightDetail:     NightDetailCard(model: model, lowestHR: nightOffset == 0 ? lowestHR : nil)
        case .sleepDebt:       SleepDebtLedgerCard(model: model)
        // Personal fork: "vs typical" only once there is a typical to compare with; before that the
        // stages card says how many nights are still needed.
        case .stagesVsTypical:
            if typicalNightCount >= Self.typicalMinNights { StagesVsTypicalCard(model: model) }
        // The 30-day hours trend is the "30 days" view of the debt card on this tab.
        case .asleepDuration:  EmptyView()
        }
    }

    /// The 24 h dial (#1680), or nothing at all.
    ///
    /// Drawn only for a fit that is at least `.wide`: an `.unreadable` rhythm has no phase to compare a
    /// night against, and an empty ring would read as a broken chart rather than as "not enough data". The
    /// card is a reorderable Sleep section, so anyone who does not want it hides it in Arrange — the same
    /// affordance every other card on this screen already has, rather than a new setting of its own.
    @ViewBuilder
    private func bodyClockDial(_ model: SleepModel) -> some View {
        // PERF: `circadianPhase` lives on `AppModel`, isolated into its own leaf (`BodyClockDialSection`)
        // rather than read via an `appModel: AppModel` property on this screen — see the NOTE above.
        BodyClockDialSection(actualBedHour: Self.localClockHour(model.night.session.effectiveStartTs),
                              actualWakeHour: Self.localClockHour(model.night.session.endTs))
    }

    /// A unix second as a fractional local clock hour — the dial's only input beyond the phase estimate.
    static func localClockHour(_ ts: Int) -> Double {
        let c = Calendar.current.dateComponents([.hour, .minute],
                                                from: Date(timeIntervalSince1970: TimeInterval(ts)))
        return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60.0
    }

    /// A short Rest state word for the hero gauge — same banding the synthesis hero uses.
    private func sleepScoreWord(_ score: Double) -> String {
        switch score {
        case ..<50:  return String(localized: "Poor")
        case ..<70:  return String(localized: "Fair")
        case ..<85:  return String(localized: "Good")
        default:     return String(localized: "Optimal")
        }
    }

    // MARK: - Provenance for the displayed night (COMPONENT 4, spec 2026-06-20)

    /// The REAL per-day merge winner for the DISPLAYED night's sleep numbers, as the same brand wording the
    /// By-Day badge / Today / Intelligence use ("On-device" / "Whoop"). A WHOOP export covering the night's
    /// wake-day wins the dashboard merge (imports win field-by-field, Repository.mergeDaily), so the badge
    /// says "Whoop"; otherwise the night was scored on-device by NOOP. Keyed by the night's LOCAL wake-day
    /// (the `mergeSleep` / importer convention, sleep is filed under the day you woke), so a navigated past
    /// night reads its OWN provenance, not last night's. Honest: never a blanket "on-device". Apple Health
    /// carries no sleep into `importedSleep`, so the sleep merge winner is only ever Whoop vs on-device. (C4)
    private func nightSource(_ night: Night) -> String {
        let wakeDay = Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval(night.session.endTs)))
        if repo.importedSleep[wakeDay] != nil { return String(localized: "Whoop") }
        // An Oura ring PROVIDES the night's stages (its own SleepNet hypnogram, banked as the imported
        // session that wins the merge), so name it "Oura" — not the generic "On-device" that implies a
        // NOOP computation. WHOOP import still wins above; only a night surfaced under a live Oura strap
        // reaches here as "Oura".
        if repo.activeDeviceIsOura { return String(localized: "Oura") }
        return String(localized: "On-device")
    }

    // MARK: - 0b. SLEEP MARKS — tap to log "going to sleep" / "I'm awake" (#461, Phase 1)
    //
    // Extracted to the `SleepMarkCard` leaf at the foot of this file. It owns its OWN `@EnvironmentObject
    // var live` (it appends to the shareable strap log) + `repo`, plus the `lastMark` confirmation state,
    // so SleepView itself no longer observes LiveState and a 1 Hz HR tick can't re-render this body. The
    // card renders byte-for-byte what the inline `sleepMarkCard` did (same copy, buttons, haptic, layout).

    // MARK: - 1. Stages card

    @ViewBuilder
    private func hero(_ model: SleepModel) -> some View {
        // Offset 0 reads the memoized latest night; navigated offsets read the cached `navNight`, never a
        // fresh decode here. A navigated session with no usable stages keeps its REAL times with an honest
        // "no stage data" card, never the latest night under a navigated label. (#160) The night picker and
        // the bed/wake row live in the top section now.
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            // #940: a NEWEST day that failed to merge (model.isStubNight) takes the same stage-less path.
            if nightOffset == 0, !model.isStubNight {
                stageCard(model.night, intervals: model.intervals)
                napSection(model.night)
            } else if let night = navNight {
                stageCard(night, intervals: night.intervals)
                napSection(night)
            } else if let stub = stubNight(at: nightOffset) {
                stageCard(stub, intervals: [])
                napSection(stub)
            }
        }
        // Stale-highlight guard: browsing to another night clears the stage selection.
        .onChange(of: nightOffset) { _ in selectedStage = nil }
    }

    /// A stage-less night for a session that did not decode, purely to reuse Night's date/time formatting.
    private func stubNight(at offset: Int) -> Night? {
        guard let session = sessionRow(at: offset) else { return nil }
        return Night(session: session, stages: Stages(awake: 0, light: 0, deep: 0, rem: 0),
                     sourceBlocks: dayBlocks(at: offset), habitualMidsleepSec: habitualMidsleepSec)
    }

    /// Naps card (#508): each of the day's sleep blocks OTHER than the night's main block, individually
    /// editable + deletable with the SAME durable mechanism main sleep uses, plus an "Add nap" affordance.
    /// A nap is always its own session row (never folded into main sleep), so editing or adding one here
    /// never touches the night's main hypnogram and the awake daytime is never mislabelled as light sleep.
    @ViewBuilder
    private func napSection(_ night: Night) -> some View {
        // The day's main sleep is the bridged main-night GROUP (#561): a briefly-interrupted / biphasic
        // night's sibling fragments are part of the night, NOT naps. Only blocks OUTSIDE that group are
        // naps. This matches the hero and AnalyticsEngine.analyzeDay; the old `!= editTarget.startTs` split
        // labelled the bridged siblings as phantom naps (#555). The summary stays explainable: Main X /
        // Nap(s) Y / Total Z, with Main = the whole bridged night. (#508, #518, #555)
        let groupStarts = night.mainGroupStarts
        let naps = night.sourceBlocks
            .filter { !groupStarts.contains($0.startTs) }
            .sorted { $0.effectiveStartTs < $1.effectiveStartTs }
        let mainMin = night.stages.total
        let napMin = naps.reduce(0.0) { $0 + Double($1.endTs - $1.effectiveStartTs) / 60.0 }
        // Personal fork: the card shows only when the day HAS naps; "Add a nap" sits in the stages card's
        // footer, so an empty "no naps" card no longer takes a slot.
        if !naps.isEmpty {
            NoopCard(padding: NoopMetrics.cardInnerPadding, tint: StrandPalette.restColor) {
                VStack(alignment: .leading, spacing: NoopMetrics.cardInnerSpacing) {
                    HStack {
                        SectionHeader("Naps", overline: "Daytime sleep", trailing: nil)
                        Spacer(minLength: 8)
                        Button { addNap = AddNapSeed(forNight: night) } label: {
                            Label("Add nap", systemImage: "plus.circle.fill")
                                .font(StrandFont.subhead)
                                .foregroundStyle(StrandPalette.restColor)
                        }
                        .buttonStyle(LiquidPressStyle())
                        .accessibilityLabel("Add a nap")
                    }
                    // Daily split (#518): Total = main + naps, the time that drives the day's Rest.
                    napSummaryRow(mainMin: mainMin, napMin: napMin)
                    Divider().overlay(StrandPalette.hairline)
                    ForEach(naps, id: \.startTs) { nap in
                        napRow(nap)
                        if nap.startTs != naps.last?.startTs {
                            Divider().overlay(StrandPalette.hairline)
                        }
                    }
                }
            }
        }
    }

    /// The Main / Naps / Total split for a day that has at least one nap, so what drives the day's Rest
    /// total is explainable at a glance. Minutes formatted with the shared `durationText`. (#518)
    @ViewBuilder
    private func napSummaryRow(mainMin: Double, napMin: Double) -> some View {
        HStack(spacing: 0) {
            napSummaryCell(label: "Main sleep", value: durationText(mainMin))
            Spacer(minLength: 8)
            napSummaryCell(label: "Nap(s)", value: durationText(napMin))
            Spacer(minLength: 8)
            napSummaryCell(label: "Total", value: durationText(mainMin + napMin))
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func napSummaryCell(label: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).strandOverline()
            Text(value).font(StrandFont.number(18)).foregroundStyle(StrandPalette.textPrimary)
        }
    }

    /// One nap row: its clock window + an edit affordance opening the SAME `SleepTimeEditor` main sleep
    /// uses. Editing a nap re-stages it from raw over the corrected window and sticks (`userEdited`), and
    /// can never spawn a duplicate (the detected `startTs` PK is immutable) — exactly the #318/#395 path,
    /// here keyed on the nap's own row. (#508)
    @ViewBuilder
    private func napRow(_ nap: CachedSleepSession) -> some View {
        let isEdited = nap.userEdited
        HStack(spacing: 10) {
            Image(systemName: "powersleep")
                .font(StrandFont.headline)
                .foregroundStyle(StrandPalette.restColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(napWindowText(nap)).font(StrandFont.body).foregroundStyle(StrandPalette.textPrimary)
                Text(durationText(Double(nap.endTs - nap.effectiveStartTs) / 60.0))
                    .strandOverline()
            }
            Spacer(minLength: 8)
            // C1 — "why this is a nap" explainer: the nap-row nudge that everything other than the chosen
            // main block is logged as a nap, with the Edit next-step. Keyed by the nap's stable startTs so
            // one popover shows at a time across several nap rows. (spec 2026-06-20)
            Button { napWhyStartTs = (napWhyStartTs == nap.startTs) ? nil : nap.startTs } label: {
                Image(systemName: "info.circle")
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.restColor)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(LiquidPressStyle())
            .help("Why this is logged as a nap")
            .accessibilityLabel("Why this is logged as a nap")
            .popover(isPresented: Binding(
                get: { napWhyStartTs == nap.startTs },
                set: { if !$0 { napWhyStartTs = nil } }), arrowEdge: .bottom) {
                whyPopover(text: "", napSuffix: true)
            }
            Button {
                wakeEdit = WakeEdit(detectedStartTs: nap.startTs,
                                    bedTs: nap.effectiveStartTs,
                                    wakeTs: nap.endTs,
                                    stagesJSON: nap.stagesJSON,
                                    userEdited: true)   // a nap row is always manually added → no tombstone on delete
            } label: {
                Image(systemName: isEdited ? "pencil.circle.fill" : "pencil.circle")
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.restColor)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(LiquidPressStyle())
            .help("Edit nap times")
            .accessibilityLabel(isEdited ? "Edit nap times (edited)" : "Edit nap times")
        }
    }

    /// "HH:mm–HH:mm" clock window for a nap row (device 12-/24-h setting via the shared Night formatter).
    private func napWindowText(_ nap: CachedSleepSession) -> String {
        let start = Night.clockString(nap.effectiveStartTs)
        let end = Night.clockString(nap.endTs)
        return "\(start)-\(end)"
    }

    /// The stages card for a decoded night (an empty `intervals` draws the honest "no stage data" card):
    /// the lanes with the curves the user switched on, the stage totals, the usual night once there is
    /// one, any caveat about the staging, and the why / add-a-nap footer. Intervals are passed in so
    /// offset 0 uses the memoized `model.intervals` rather than re-deriving them. (#160)
    @ViewBuilder
    private func stageCard(_ night: Night, intervals: [SleepInterval]) -> some View {
        let s = night.stages
        let isPersisted = (night.realSegments?.count ?? 0) >= 2
        // An Oura night's stages are the ring's RAW on-device classification, not a NOOP approximation,
        // so it gets its own honest caption.
        let stageCaption = repo.activeDeviceIsOura
            ? String(localized: "Raw on-device stages")
            : String(localized: "Stages estimated on the device")
        let base = String(localized: "\(durationText(night.timeInBed)) in bed · \(durationText(s.asleep)) asleep")
        let typicalCount = typicalNightCount
        let hasTypical = typicalCount >= Self.typicalMinNights
        SleepPhasesCard(
            subtitle: isPersisted ? "\(base)\n\(stageCaption)" : base,
            source: nightSource(night),
            intervals: Hypnogram.displaySmoothed(intervals.sorted { $0.start < $1.start }, minDuration: 300),
            nightStart: night.onsetDate,
            palette: stagePalette,
            stages: [SleepStage.awake, .rem, .light, .deep].map { stage in
                SleepPhasesCard.StageLine(stage: stage, minutes: stageMinutes(stage, in: s),
                                          percent: stageSharePercent(stage, s),
                                          typicalMinutes: hasTypical ? stageTypical(stage)?.mean : nil)
            },
            typicalProgress: hasTypical ? nil : (count: typicalCount, needed: Self.typicalMinNights),
            curves: SleepPhasesCard.Curves(heartRate: nightHR, hrv: nightHRV, skinTemp: nightSkinTemp,
                                           motion: night.motionEpochs),
            selectedStage: $selectedStage,
            showHeartRate: $showSleepHR,
            showHRV: $showHRVCurve,
            showSkinTemp: $showSkinTempCurve,
            showMotion: $showMotionCurve,
            notes: stageNotes(night),
            whyButton: mainSleepReasonText(night) == nil ? nil : AnyView(whyButton(night)),
            addNap: { addNap = AddNapSeed(forNight: night) })
        // The night's curves (1-min sleeping HR, windowed rMSSD, skin temperature), reloaded only when the
        // displayed night changes. All three are the existing reads: no new computation.
        .task(id: night.session.startTs) {
            let from = night.session.effectiveStartTs
            let to = night.session.endTs
            nightHR = await repo.hrBuckets(from: night.session.startTs, to: to, bucketSeconds: 60)
            nightHRV = await repo.timelineSeries(metric: .hrv, from: from, to: to, targetPoints: 240).points
            nightSkinTemp = await repo.timelineSeries(metric: .skinTemp, from: from, to: to, targetPoints: 240).points
        }
    }

    /// The honest caveats about this night's staging, stacked under the stage totals; nil when none apply.
    /// H9 low confidence, #345 may be incomplete, #1716 partly recorded, and the Oura raw-stages note.
    private func stageNotes(_ night: Night) -> AnyView? {
        let lowConfidence = stageStagingIsLowConfidence(night)
        let incomplete = stageShowsIncompleteNote(night)
        let coverage = stageCoverage(night).flatMap { $0 < HypnogramCoverage.minCoverage ? $0 : nil }
        let oura = repo.activeDeviceIsOura
        guard lowConfidence || incomplete || coverage != nil || oura else { return nil }
        return AnyView(VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            if lowConfidence { stageLowConfidenceNote }
            if incomplete { stageIncompleteNote }
            if let coverage { stagePartialNote(coverage) }
            if oura { ouraRawStagesNote }
        })
    }

    /// "Why this sleep?": the foundation `MainNightReason` copy for the pick, in a popover. (spec 2026-06-20 C1)
    private func whyButton(_ night: Night) -> some View {
        Button { showMainSleepWhy.toggle() } label: {
            Label("Why this sleep?", systemImage: "info.circle")
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.restBright)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(LiquidPressStyle())
        .help("Why this is your main sleep")
        .accessibilityLabel("Why this is your main sleep")
        .popover(isPresented: $showMainSleepWhy, arrowEdge: .bottom) {
            whyPopover(text: mainSleepReasonText(night) ?? "", napSuffix: false)
        }
    }

    /// H9 — true when this night's staging is LOW-CONFIDENCE: a high-efficiency night (lots of measured
    /// sleep) whose restorative (deep+REM) share is implausibly low, which the EEG-free classifier is far
    /// more likely to have mis-staged than a genuine night with no deep or REM. Delegates to the engine's
    /// pure `ScoreConfidence.rest(...)` H9 overload (efficiency in [0,1], seconds for the totals) so the UI
    /// and the persisted Rest confidence agree by construction. Needs staged sleep + a real efficiency
    /// reading; a pooled/no-stage or unknown-efficiency night is never flagged (its base tier already
    /// reads honestly). (#H9)
    private func stageStagingIsLowConfidence(_ night: Night) -> Bool {
        let s = night.stages
        guard let effPct = efficiencyPct(night) else { return false }
        return SleepView.isStagingLowConfidence(
            asleepMin: s.asleep, deepMin: s.deep, remMin: s.rem, efficiency: effPct / 100.0)
    }

    /// True when this night earns the "May be incomplete" caveat: staged on SPARSE motion coverage AND
    /// actually reading short (#345). The rule itself lives in `stageSparseNoteApplies` below, which carries
    /// the reasoning and is what Kotlin mirrors; this wrapper only supplies the two inputs. Reads the day's
    /// REAL stored blocks (each carries the day's value), never the synthetic merged `session`; a nil flag
    /// (imported / pre-migration night) is never flagged.
    private func stageShowsIncompleteNote(_ night: Night) -> Bool {
        SleepView.stageSparseNoteApplies(
            stagingSparse: night.sourceBlocks.contains { $0.stagingSparse == true },
            asleepMin: night.stages.asleep)
    }

    /// Pure #345 gate (unit-testable without a live view) — whether the "May be incomplete" caveat applies.
    /// Mirror EXACTLY in Kotlin.
    ///
    /// `stagingSparse` alone is NOT the question the note asks. It is a STAGING-MECHANISM verdict:
    /// `SleepStager.isGravitySparse` returns true when the gravity span is short against the HR span OR when
    /// the LARGEST inter-sample gap exceeds `maxGapMin`, and its own doc calls that second branch "the
    /// typical WHOOP 4.0 backfill (#28)" whose only consequence is to ENABLE `buildRuns`' HR-vouched bridge.
    /// So a single long motion dropout sets it on a night of ANY length, including a complete twelve-hour
    /// one, and the flag is raised precisely where the engine has already applied its own mitigation.
    ///
    /// The note's copy, though, claims something narrower and checkable: that the night "may be
    /// under-detected and the sleep total can read short". So require the total to actually read short. A
    /// night at or above the wearer's need cannot honestly be captioned as possibly reading short, whatever
    /// the motion trace looked like.
    ///
    /// A night that staged to NOTHING keeps the caveat: zero asleep is the strongest form of the collapse
    /// this note exists to explain, not an exemption from it.
    ///
    /// `needHours` is a parameter rather than a constant so a personalised need
    /// (`AnalyticsEngine.Rest.personalizedNeedHours`) can be threaded in later without moving the rule. It
    /// is computed per pass today and not persisted on the row a screen can reach, so the shared default
    /// stands in.
    static func stageSparseNoteApplies(stagingSparse: Bool,
                                       asleepMin: Double,
                                       needHours: Double = AnalyticsEngine.Rest.defaultNeedHours) -> Bool {
        guard stagingSparse else { return false }
        return asleepMin < needHours * 60.0
    }

    /// How much of this night's window its stage timeline actually accounts for, or nil when coverage is
    /// not a measurable question for the payloads it was built from (#1716). Asked of the bridged main-night
    /// GROUP via the SAME shared accumulation `analyzeDay` uses, threading the same learned habitual so the
    /// group resolves identically to the hero's — a per-row answer would be the wrong question for a
    /// fragmented night. Mirror in Kotlin.
    private func stageCoverage(_ night: Night) -> Double? {
        let group = SleepView.mainNightGroup(night.sourceBlocks,
                                             habitualMidsleepSec: night.habitualMidsleepSec)
        return HypnogramCoverage.groupFraction(group.isEmpty ? night.sourceBlocks : group)
    }

    /// Pure H9 gate (unit-testable without a live view) — true when a night's staging is low-confidence:
    /// a high-efficiency night whose deep+REM share is below the restorative floor. Built on the engine's
    /// own `ScoreConfidence.rest(...)` so the UI flag and the persisted Rest confidence agree. `asleepMin`,
    /// `deepMin`, `remMin` are minutes; `efficiency` is asleep/in-bed in [0,1]. Returns false for an unstaged
    /// or zero-asleep night (no staging to doubt). Mirror EXACTLY in Kotlin. (#H9)
    static func isStagingLowConfidence(asleepMin: Double, deepMin: Double, remMin: Double,
                                       efficiency: Double) -> Bool {
        guard asleepMin > 0 else { return false }
        let restorativeMin = max(0, deepMin) + max(0, remMin)
        // An UNSTAGED night (no deep+REM at all) has no staging split to doubt — its base Rest
        // confidence already reads honestly as `.building` (NOT a downgrade), so it must never be
        // flagged. Only a night that DID stage some sleep can be a suspicious "high efficiency yet
        // implausibly little restorative" staging miss.
        guard restorativeMin > 0 else { return false }
        let tier = ScoreConfidence.rest(
            hasSession: true,
            hasStagedSleep: true,
            asleepSeconds: asleepMin * 60.0,
            restorativeSeconds: restorativeMin * 60.0,
            efficiency: efficiency)
        // The H9 overload only DOWNGRADES solid → building on the suspicious case; a genuinely
        // low-restorative-AND-low-efficiency night keeps its honest base tier and isn't flagged here.
        return tier == .building
            && (restorativeMin / asleepMin) < ScoreConfidence.restorativeLowConfidenceShare
            && efficiency >= ScoreConfidence.highEfficiencyThreshold
    }

    /// The H9 low-confidence note shown beneath the stage breakdown — a warning-tinted badge plus a
    /// one-line honest explanation. No faked stages, no tanked score; just a clear "treat this split with
    /// care" so a user doesn't read a likely staging miss as a real deep/REM drought. (#H9)
    private var stageLowConfidenceNote: some View {
        HStack(alignment: .top, spacing: 8) {
            SourceBadge("Low confidence", tint: StrandPalette.statusWarning)
            Text("This night scored high efficiency but very little deep or REM, more likely a staging estimate miss than a real restorative shortfall. The totals are kept as-is; read the split with care.")
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Low confidence staging. This night scored high efficiency but very little deep or REM, more likely an estimate miss than a real restorative shortfall.")
    }

    /// The sparse-coverage caveat: a night staged on thin motion data can under-detect and collapse a real
    /// night to a fraction ("slept 8h, shows 1h"). Honest + actionable — tells the user to make sure the
    /// strap fully synced. Distinct from the H9 note (an off deep/REM split, not a short total). (#345)
    private var stageIncompleteNote: some View {
        HStack(alignment: .top, spacing: 8) {
            SourceBadge("May be incomplete", tint: StrandPalette.statusWarning)
            Text("Your strap recorded little movement overnight (common on WHOOP 4.0), so this night may be under-detected and the sleep total can read short. Make sure the strap fully synced; the numbers are kept as-is.")
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 2)
        // `.combine` builds the a11y label from the badge + body Text (no separate localized string).
        .accessibilityElement(children: .combine)
    }

    /// The PARTIAL-TIMELINE caveat (#1716): this night's stage segments account for less than
    /// `HypnogramCoverage.minCoverage` of the window the session claims, so the stage totals describe only
    /// the part of the night the timeline accounts for. Distinct from BOTH notes above — H9 doubts the
    /// deep/REM SPLIT of a fully-described night, #345 doubts a night staged on thin motion, and this one
    /// says plainly that some of the night is MISSING rather than doubted. It is the visible half of the
    /// engine-side guard: `analyzeDay` already downgrades Rest to `.building` on exactly this condition,
    /// but that tier is transient engine output no screen reads, so without this the gate was inert.
    ///
    /// HONEST-DATA: it reports only what was observed and changes no number. The percentage is floored,
    /// never rounded — 94.8% must not print as "95%" and appear to contradict the gate that flagged it.
    /// The copy names NO cause and offers NO remedy, deliberately: on the 08-29/30 and 08-30/31 captures the
    /// missing codes DID reach NOOP — the ring reported them unwritten (0xFF), the persist log trimmed
    /// exactly as many as the hole is wide — and re-persisting the same night 5 and 8 times left the hole
    /// intact. "The rest never reached NOOP" and "syncing again can fill in" were both wrong. Nor does the
    /// copy point at the totals by DIRECTION: both hosts render this note below the stage-breakdown card
    /// that carries them, so "the totals below" pointed the wrong way on every screen that shipped it.
    private func stagePartialNote(_ coverage: Double) -> some View {
        let pct = Int((coverage * 100).rounded(.down))
        return HStack(alignment: .top, spacing: 8) {
            SourceBadge("Partly recorded", tint: StrandPalette.statusWarning)
            Text("Only \(pct)% of this night's window has stage data. The stage totals cover only that part of the night.")
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .combine)
    }

    /// Honest caveat for an Oura-provided night: the stage split shown here is the ring's RAW on-device
    /// SleepNet classification, read straight off the BLE phase stream — NOT the adjusted stages the Oura
    /// app displays. The app post-processes the same night, so its Deep/REM run higher and its Awake lower;
    /// cross-checks put our Awake well above the app's. Surfaced so the breakdown isn't taken for the app's.
    private var ouraRawStagesNote: some View {
        HStack(alignment: .top, spacing: 8) {
            SourceBadge("Raw on-device stages", tint: StrandPalette.restColor)
            Text("This split is the ring's raw on-device classification read over Bluetooth, not the adjusted stages the Oura app shows. Expect more Awake and less Deep/REM here than in the Oura app for the same night.")
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Raw on-device stages. This split is the ring's raw on-device classification read over Bluetooth, not the adjusted stages the Oura app shows. Expect more awake and less deep or REM here than in the Oura app for the same night.")
    }

    /// A compact explainer popover: the verbatim foundation reason text, with the nap suffix appended for a
    /// nap row. Plain English, no jargon, no em-dashes (the words come straight from `mainSleepReasonText`
    /// and the spec's nap-row suffix). Sized for both macOS and iOS. (spec 2026-06-20 C1)
    @ViewBuilder
    private func whyPopover(text: String, napSuffix: Bool) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            HStack(spacing: NoopMetrics.space2) {
                Image(systemName: "moon.stars.fill")
                    .foregroundStyle(StrandPalette.restColor)
                    .accessibilityHidden(true)
                Text(napSuffix ? "About this nap" : "About your main sleep")
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
            }
            if !text.isEmpty {
                Text(text)
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if napSuffix {
                Text("Logged as a nap. Wrong? Tap Edit to adjust your sleep and wake times.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(NoopMetrics.cardInnerPadding)
        .frame(width: 260)
        .background(NoopPanelSurface(cornerRadius: NoopVisualStyle.compactRadius, elevated: true))
        .accessibilityElement(children: .combine)
    }

    // MARK: - WHOOP stage rows (swatch + UPPERCASE stage + coloured % + bar + duration)

    /// The night's four stages as whole percentages that sum to exactly 100 (largest-remainder), so the
    /// breakdown rows, the timeline rows and the stage-bar read-out all print ONE apportionment: they agree
    /// with each other and add up. The bar fills still track the raw `minutes / total` fraction. Falls back
    /// to 0 for a night with no minutes. Twin of Android `stageSharePercent`. (tanarchytan)
    private func stageSharePercent(_ stage: SleepStage, _ s: Stages) -> Int {
        guard let p = StagePercentages.wholePercentages([s.awake, s.light, s.deep, s.rem]) else { return 0 }
        switch stage {
        case .awake: return p[0]
        case .light: return p[1]
        case .deep:  return p[2]
        case .rem:   return p[3]
        }
    }

    // MARK: - WHOOP stage-timeline rows (the sleep-details reference design, ryanAtriumAi #988)

    /// Tonight's minutes for one stage out of the decoded totals.
    private func stageMinutes(_ stage: SleepStage, in s: Stages) -> Double {
        switch stage {
        case .awake: return s.awake
        case .light: return s.light
        case .deep:  return s.deep
        case .rem:   return s.rem
        }
    }

    /// Per-stage typical minutes over the trailing 30 scored days: the 25th–75th percentile band
    /// plus the mean — WHOOP's "typical range". Pass nil for total asleep. Returns nil below 5
    /// scored nights (honest cold-start: no fabricated range from a few days).
    private func stageTypical(_ stage: SleepStage?) -> (lo: Double, hi: Double, mean: Double)? {
        let values: [Double] = repo.days.suffix(30).compactMap { d in
            switch stage {
            case nil:     return d.totalSleepMin
            case .light?: return d.lightMin
            case .deep?:  return d.deepMin
            case .rem?:   return d.remMin
            case .awake?:
                // Awake isn't a stored daily column; derive from in-bed minus asleep via efficiency.
                guard let asleep = d.totalSleepMin, asleep > 0, var e = d.efficiency, e > 0 else { return nil }
                if e > 1.5 { e /= 100 }   // efficiency arrives as % on some import paths
                guard e > 0.3, e <= 1 else { return nil }
                return asleep * (1 - e) / e
            }
        }.filter { $0 > 0 }.sorted()
        guard values.count >= Self.typicalMinNights else { return nil }
        func pct(_ p: Double) -> Double {
            let idx = p * Double(values.count - 1)
            let l = Int(idx.rounded(.down)), u = Int(idx.rounded(.up))
            let frac = idx - Double(l)
            return values[l] * (1 - frac) + values[u] * frac
        }
        let mean = values.reduce(0, +) / Double(values.count)
        return (pct(0.25), pct(0.75), mean)
    }

    // MARK: - 2. Metric grid (UNIFORM fixed-height StatTiles, each with sparkline)
    //
    // The "Night detail" grid now lives in `NightDetailCard` (a standalone view) so it can ALSO be hosted
    // in the Today tab from the SAME `SleepModel`. `sleepSectionView(.nightDetail)` renders `NightDetailCard`
    // directly; the grid body and its tile-formatting helpers (`pctValue` / `rrValue` / `vsTypical` /
    // `debtCaption` / `debtColor` / `spark` / `tileColumns`) moved there with it.

    // The "Sleep-debt ledger" card now lives in `SleepDebtLedgerCard` (a standalone view) so it can ALSO
    // be hosted in the Today tab from the SAME `SleepModel`. `sleepSectionView(.sleepDebt)` renders
    // `SleepDebtLedgerCard` directly; the card body, its `debtDeltaBars` strip and the debt-only
    // formatters (`debtHeadline` / `debtTag` / `debtRead` / `debtBalanceColor` / `debtSigned`) moved there
    // with it — they had no other caller in SleepView.

    // MARK: - 4. 30-day asleep-hours trend

    /// Compare only after the screen has loaded the refreshed blocks and scoring has settled.
    /// The observer lives on the screen, so a hidden notice cannot stop change observation.
    private func observeResultChange() {
        guard loadedSleepRefresh == repo.refreshSeq, !intelligence.computing else { return }
        guard let model else { resetResultNotice(); return }
        let snapshot = resultSnapshot(heroNight(model))
        if resultNoticeScope != snapshot.scope { resultNoticeVisible = false }
        resultNoticeScope = snapshot.scope
        if resultTracker.observe(snapshot, ready: true) {
            resultNoticeVisible = true
            resultNoticeRevision += 1
        }
    }

    private func resetResultNotice() {
        resultTracker = SleepResultChangeTracker()
        resultNoticeVisible = false
        resultNoticeScope = nil
    }

    private func resultSnapshot(_ night: Night) -> SleepResultSnapshot {
        let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: Double(night.session.endTs)))
        let sources = Set(night.sourceBlocks.compactMap(\.deviceId)).sorted().joined(separator: ",")
        return SleepResultSnapshot(
            scope: "\(repo.deviceId):\(sources):\(day.timeIntervalSince1970)",
            onset: night.session.effectiveStartTs, wake: night.session.endTs,
            asleepMinutes: night.stages.asleep,
            edited: night.session.userEdited || night.sourceBlocks.contains { $0.userEdited })
    }

    // MARK: - Memoization plumbing

    /// A cheap fingerprint of the repo inputs this screen derives from. Recomputed every
    /// render but only contains counts + the identity of the newest/oldest rows, so equality
    /// is fast. When it changes we know `repo.days`/`repo.sleeps` actually changed and the
    /// memoized `model` must be rebuilt; otherwise hover/animation/1Hz HR re-renders are free.
    private var dataKey: SleepInputKey {
        SleepInputKey(
            loaded: repo.loaded,
            daysCount: repo.days.count,
            sleepsCount: repo.sleeps.count,
            firstDay: repo.days.first?.day,
            lastDay: repo.days.last?.day,
            lastDayUpdated: repo.days.last,
            lastSleep: repo.sleeps.last,
            refreshSeq: repo.refreshSeq)
    }

    /// Build every expensive derivation exactly once. Called only when `dataKey` changes, so each
    /// full pass over repo.days / repo.sleeps runs once per data change rather than once per render.
    /// A thin wrapper: it snapshots the view's current state into `SleepModelInputs` and hands off to
    /// the pure `SleepModel.build(_:)` (SleepModel.swift), which the Today host also calls. Returns
    /// nil when there is no usable latest night (renders empty state).
    private func buildModel() -> SleepModel? {
        SleepModel.build(SleepModelInputs(
            days: repo.days,
            sleeps: repo.sleeps,
            allSessions: allSessions,
            importedSleep: repo.importedSleep,
            habitualMidsleepSec: habitualMidsleepSec,
            motionByStart: motionByStart))
    }

    // MARK: - Derived model

    /// The browsable block list: every sleep session un-deduplicated (incl. same-day naps / split
    /// sleep). Falls back to `repo.sleeps` (one-per-night) until the fuller list loads, so the hero
    /// is never empty during the first frame. (#170)
    private var navSessions: [CachedSleepSession] {
        allSessions.isEmpty ? repo.sleeps : allSessions
    }

    /// The browsable DAY list — a thin wrapper over the shared `SleepModel.navDays`, which is the
    /// source of truth the builder and the ◀/▶ nav both read (no duplicated grouping). (#170)
    private var navDays: [[CachedSleepSession]] {
        navDaysCache ?? SleepModel.navDays(navSessions: navSessions)
    }

    /// The device's current UTC offset (seconds east), evaluated once per pick. Feeds the selector's
    /// `offsetSec` so the timing test reads the user's clock via the SAME `offsetSec` math the engine
    /// uses (`SleepStageTotals.localSecOfDay`), instead of `Calendar.current.component(.hour:)` which was
    /// the duplicated, DST-fragile gate the audit flagged. (#547)
    static var tzOffsetSec: Int { TimeZone.current.secondsFromGMT() }

    /// The day's single WINNING main block — the durable-edit anchor (`editTarget`) and the one block whose
    /// learned-timing score won. Scores by learned timing on each block's EFFECTIVE onset (what the user
    /// sees) and returns the owning session. This is the BARE single-block pick (no gap-bridge), because the
    /// edit affordance writes against ONE real row so it must resolve to one block. The HERO display and the
    /// nap split do NOT use this alone: they use `mainNightGroup`, which bridges the winner's adjacent
    /// fragments (a wake gap shorter than `gapBridgeMaxMin`) into ONE night the way `AnalyticsEngine`
    /// does (#561), so a biphasic / briefly-interrupted night is shown as one continuous sleep instead of
    /// phantom naps (#555). `habitualMidsleepSec` is the SAME learned value the engine threads into the
    /// persisted totals (loaded via `repo.habitualMidsleepSec()`), so a shift/late sleeper's pick matches
    /// the analytics rollup; nil keeps the cold-start overnight-band bonus. (#525 / #547 / #561)
    static func mainNightSession(_ sessions: [CachedSleepSession],
                                 habitualMidsleepSec: Int? = nil) -> CachedSleepSession? {
        SleepStageTotals.mainNightIndex(
            sessions.map { SleepStageTotals.NightBlock(start: $0.effectiveStartTs, end: $0.endTs) },
            offsetSec: tzOffsetSec, habitualMidsleepSec: habitualMidsleepSec).map { sessions[$0] }
    }

    /// The day's MAIN-night GROUP — the winning block PLUS any adjacent fragments bridged into it (a wake
    /// gap shorter than `gapBridgeMaxMin`), so a briefly-interrupted / biphasic night reads as ONE
    /// continuous sleep exactly the way `AnalyticsEngine.analyzeDay` rolls it up for the daily total (#561).
    /// The hero aggregates this whole group and ONLY blocks outside it are naps. Without it the tab used the
    /// un-bridged single-block pick and rendered the bridged siblings as phantom naps (#555). A night with
    /// no bridgeable gap collapses to the single block `mainNightSession` picks, so the common case is byte-
    /// identical. Returns ascending by effective onset. (#561 / #555)
    static func mainNightGroup(_ sessions: [CachedSleepSession],
                               habitualMidsleepSec: Int? = nil) -> [CachedSleepSession] {
        guard let idx = SleepStageTotals.mainNightGroupIndices(
            sessions.map { SleepStageTotals.NightBlock(start: $0.effectiveStartTs, end: $0.endTs) },
            offsetSec: tzOffsetSec, habitualMidsleepSec: habitualMidsleepSec) else { return [] }
        return idx.map { sessions[$0] }.sorted { $0.effectiveStartTs < $1.effectiveStartTs }
    }

    /// Actual asleep minutes in blocks outside a day's canonical main-night group. The Repository's
    /// all-session union has already removed cross-namespace duplicates; this helper only applies the
    /// same main-vs-nap classification the hero uses and decodes persisted stages. A stage-less nap
    /// contributes nothing rather than substituting its in-bed window. Mirrors Android
    /// `napSleepMinutesByDay`.
    static func napSleepMinutes(_ sessions: [CachedSleepSession],
                                habitualMidsleepSec: Int? = nil) -> Double {
        let mainStarts = Set(mainNightGroup(sessions, habitualMidsleepSec: habitualMidsleepSec)
            .map { $0.startTs })
        return sessions
            .filter { !mainStarts.contains($0.startTs) }
            .reduce(0) { total, nap in
                total + decodedAsleepMinutes(nap.stagesJSON, effectiveStartTs: nap.effectiveStartTs)
            }
    }

    /// The day's main-night bridged SPAN (onset → wake), the same window `mainNightGroup` bridges into
    /// one continuous night. The ONE canonical bed/wake read every glance screen (Coupled, Today's HR
    /// band) should show — never a screen-local "freshest" or "longest single block" heuristic, which
    /// can silently disagree with each other and with the Sleep tab hero on a night stored as more than
    /// one block (#294). nil only when `sessions` has nothing bridgeable.
    static func mainNightSpan(_ sessions: [CachedSleepSession],
                              habitualMidsleepSec: Int? = nil) -> (start: Int, end: Int)? {
        let group = mainNightGroup(sessions, habitualMidsleepSec: habitualMidsleepSec)
        guard let first = group.first, let last = group.last else { return nil }
        return (first.effectiveStartTs, last.endTs)
    }

    /// Classify a block as a nap: it's a nap exactly when it is NOT the day's chosen main block. Derived
    /// from the pick (never an independent onset/duration gate), so the label can't contradict the
    /// selection — the contradiction the audit flagged. The main block is never a nap. (#518/#547)
    static func isNap(_ s: CachedSleepSession, main: CachedSleepSession?) -> Bool {
        guard let main else { return false }
        return s.startTs != main.startTs
    }

    // MARK: - Why-this-is-your-main-sleep explainer (COMPONENT 1, spec 2026-06-20)

    /// The verbatim reason copy for the displayed night, with {DUR} filled as "Xh Ym" from the chosen
    /// block's asleep duration — driven entirely by the foundation `MainNightReason`, so the explainer
    /// states exactly what the selector decided (never a re-derived guess). Resolved over the day's blocks
    /// via the same `mainNightSelection` API the analytics pick uses, with the SAME learned habitual the
    /// hero used, so the words match the block the hero shows. nil only when the day has no blocks. (C1)
    private func mainSleepReasonText(_ night: Night) -> String? {
        guard let sel = SleepStageTotals.mainNightSelection(
            night.sourceBlocks.map { SleepStageTotals.NightBlock(start: $0.effectiveStartTs, end: $0.endTs) },
            offsetSec: SleepView.tzOffsetSec, habitualMidsleepSec: habitualMidsleepSec) else { return nil }
        let dur = durationText(sel.asleepMinutes)
        switch sel.reason {
        case .onlyBlock:
            return String(localized: "This is your only sleep block today.")
        case .longest:
            return String(localized: "Picked as your main sleep because it was your longest block (\(dur)).")
        case .longestNearUsual:
            return String(localized: "Picked as your main sleep because it was your longest block (\(dur)), near your usual bedtime.")
        case .alignedToUsual:
            return String(localized: "Picked as your main sleep because it started near your usual sleep time.")
        }
    }

    // `mergeDay` / `nightOnsetTs` / the fragment-level `isPreOnsetAwakeStub(_:)` moved to
    // SleepModel.swift (pure statics reused by the builder and the ◀/▶ nav). The pure rule statics and
    // tuning constants below stay here — they are the shared source of truth reused by tests and by
    // those moved helpers.

    /// Longest a leading block can be and still be treated as a spurious pre-sleep awake stub (lying in bed
    /// before sleep). Generous (a few hours) because the reporter's stub ran 21:41 → 00:27 — ~2h45m of
    /// pre-sleep awake — so a tight cap missed it (#736). The real guard against swallowing a genuine first
    /// sleep fragment is `preOnsetStubAsleepMaxMin`: a stub must be essentially SLEEPLESS, which a real sleep
    /// block never is. The cap only stops a pathological all-day awake block from being silently dropped.
    static let preOnsetStubMaxMin: Double = 240
    /// Most asleep minutes a fragment can carry and still count as a (sleepless) pre-onset awake stub. A real
    /// first sleep fragment of a biphasic night carries far more, so it's never mistaken for a stub. (#736)
    static let preOnsetStubAsleepMaxMin: Double = 3
    /// A leading pre-onset fragment carrying SOME sleep is still spurious when it is minor RELATIVE to the
    /// night's main block: its asleep minutes are below this fraction of the largest fragment's. A genuine
    /// biphasic first sleep is comparable to the main block (well above this) and is kept; only a small stray
    /// lead is dropped. Extends the essentially-sleepless `preOnsetStubAsleepMaxMin` rule (#736), which missed
    /// a lead carrying a few minutes more than 3. Mirrors Android PRE_ONSET_STUB_MINOR_FRAC. (#259)
    static let preOnsetStubMinorFrac: Double = 0.15

    /// Absolute floor (ASLEEP minutes) under the #259 relative "minor lead" test: a leading fragment that
    /// carries at least this much real sleep is a genuine first sleep — a real sleep episode — and is NEVER
    /// a spurious pre-onset lead, however large the main block is. Without it a long main sleep inflates the
    /// 15% relative bar (a 6h night → ~54 min) so a genuine ~34-min first sleep was swallowed and the shown
    /// bedtime jumped hours late, hiding the real onset the bridged night (and the Health write-back, #364)
    /// already spans. 20 min ≈ the shortest standalone sleep episode; below it a handful of asleep minutes
    /// beside a long night is a stray lead. Mirrors Android PRE_ONSET_STUB_MINOR_ASLEEP_FLOOR_MIN.
    /// (bridged-night headline: a real 2026-07-14 12:16 first sleep hidden behind the 1:29 main block)
    static let preOnsetStubMinorAsleepFloorMin: Double = 20

    /// Pure stub test on a fragment's span + asleep minutes, so the rule is unit-testable without decoding
    /// JSON or building a view. Spurious when BRIEF and EITHER essentially sleepless OR minor relative to the
    /// main block (`refAsleepMin`, the group's largest asleep span): asleep below `preOnsetStubMinorFrac` of
    /// it AND below the absolute `preOnsetStubMinorAsleepFloorMin` real-sleep-episode floor. `refAsleepMin`
    /// defaults to 0 (relative test off) so existing callers/tests are byte-identical. (#736 / #259)
    static func isPreOnsetAwakeStub(spanMin: Double, asleepMin: Double, refAsleepMin: Double = 0) -> Bool {
        guard spanMin <= preOnsetStubMaxMin else { return false }
        if asleepMin <= preOnsetStubAsleepMaxMin { return true }
        // #259 relative "minor lead" test, floored: a real sleep episode (>= the floor) is never a stray
        // lead, so a long main block can't inflate the 15% bar past a genuine short first sleep.
        return refAsleepMin > 0
            && asleepMin < preOnsetStubMinorFrac * refAsleepMin
            && asleepMin < preOnsetStubMinorAsleepFloorMin
    }

    /// The index into an ascending-by-onset group whose fragment supplies the DISPLAYED bedtime: the first
    /// fragment that is NOT a spurious leading pre-onset awake stub, falling back to 0 when every fragment is
    /// stub-like. Pure mirror of `nightOnsetTs`'s walk, driven by per-fragment (spanMin, asleepMin) so a
    /// golden test can pin the #736 behaviour without view internals. (#736)
    static func nightOnsetIndex(spansMin: [Double], asleepsMin: [Double]) -> Int {
        let refAsleepMin = asleepsMin.max() ?? 0
        for i in spansMin.indices {
            let asleep = i < asleepsMin.count ? asleepsMin[i] : 0
            if !isPreOnsetAwakeStub(spanMin: spansMin[i], asleepMin: asleep, refAsleepMin: refAsleepMin) { return i }
        }
        return 0
    }

    /// The real stored blocks composing the day at `offset` (for the stage-less stub Night, so its edit
    /// affordance still targets a real row). Empty when out of range.
    private func dayBlocks(at offset: Int) -> [CachedSleepSession] {
        let days = navDays
        return offset >= 0 && offset < days.count ? days[offset] : []
    }

    /// The merged Night for the DAY `offset` stops back from the most recent (0 = last night). Backs the
    /// hero's ◀/▶ navigation via the `navNight` cache — a thin wrapper over the shared
    /// `SleepModel.decodedNight`, which JSON-decodes, so it only runs from the builder and the onChange
    /// handlers, never per render. (#160, #170)
    private func decodedNight(at offset: Int) -> Night? {
        SleepModel.decodedNight(at: offset, navDays: navDays,
                                habitualMidsleepSec: habitualMidsleepSec, motionByStart: motionByStart)
    }

    /// A synthetic session for the DAY `offset` stops back, spanning the MAIN block's window (not the
    /// whole day), for the honest no-stage-data header when the day's blocks don't decode to usable
    /// stages. Using the main block (#518) keeps the stub header on the real night rather than a
    /// 1 AM→5 PM overnight+nap span. (#160, #170)
    private func sessionRow(at offset: Int) -> CachedSleepSession? {
        SleepView.stubDaySession(dayBlocks(at: offset), habitualMidsleepSec: habitualMidsleepSec)
    }

    /// The stage-less stub SESSION for a day whose blocks decode to no usable sleep: the MAIN
    /// block's effective window (the same pick `sessionRow` always made), falling back to the day's
    /// first block so a day with ANY stored block renders a header. Static and pure so the #940
    /// no-blank rule is unit-testable without view internals (SleepPhantomNightFallbackTests): as
    /// long as a day has a block, the tab has something honest to show and `buildModel` never
    /// collapses the whole screen to the first-run empty state. nil only for an empty day.
    static func stubDaySession(_ blocks: [CachedSleepSession],
                               habitualMidsleepSec: Int? = nil) -> CachedSleepSession? {
        guard let main = mainNightSession(blocks, habitualMidsleepSec: habitualMidsleepSec) ?? blocks.first
        else { return nil }
        return CachedSleepSession(startTs: main.effectiveStartTs, endTs: main.endTs,
                                  efficiency: nil, restingHr: nil, avgHrv: nil, stagesJSON: nil)
    }

    // The typical/need values, the per-tile `Metric` series (performance / efficiency / consistency /
    // hoursVsNeeded / restorative / respiratory / sleepDebt), the `napSleepMinutesByDay` credit map,
    // `durationTrendPoints`, and the `mean` helper moved to SleepModel.swift as pure statics over
    // explicit inputs. `buildModel()` calls them via `SleepModel.build(_:)`; the renderers read the
    // resulting `SleepModel` fields.


    // MARK: - Empty / sparse states

    @ViewBuilder
    private var emptyState: some View {
        SleepFreshnessNote(latestWakeTs: nil)
        if repo.loaded {
            ComingSoon(what: "No nights here yet. Import your WHOOP export in Data Sources to see every night, your sleep stages and trends straight away. Or open Intelligence to see last night computed from the strap after you wear it to bed.")
        } else {
            ComingSoon(what: "Loading your sleep history…")
        }
    }


    // MARK: - Formatting helpers

    // The metric-grid tile formatters (`pctValue` / `rrValue` / `vsTypical` / `debtCaption` / `debtColor`)
    // moved to `NightDetailCard` with the grid; they had no other caller in SleepView.

    // The Sleep-debt ledger formatters (`debtHeadline` / `debtTag` / `debtRead` / `debtBalanceColor` /
    // `debtSigned`) moved to `SleepDebtLedgerCard` with the card; they had no other caller in SleepView.

    /// Efficiency in percent. Prefer the stored session value, else asleep / time-in-bed.
    private func efficiencyPct(_ night: Night) -> Double? {
        if let stored = night.session.efficiency ?? repo.today?.efficiency {
            return stored <= 1.0 ? stored * 100 : stored
        }
        let bed = night.timeInBed
        guard bed > 0 else { return nil }
        return Swift.min(100, night.stages.asleep / bed * 100)
    }

    private func durationText(_ minutes: Double) -> String {
        SleepDurationText.format(minutes)
    }

    // The metric-grid `spark(_:)` sparkline helper moved to `NightDetailCard` with the grid.

    // MARK: - Stage decoding

    /// Asleep minutes decoded from a stored `stagesJSON` in EITHER of the two formats that exist in the
    /// DB: on-device COMPUTED nights store a SEGMENT ARRAY `[{"start":epoch,"end":epoch,"stage":…}]`
    /// (`AnalyticsEngine.encodeStages`); imported nights store a dict of MINUTES
    /// `{"light","deep","rem","awake"}`. The displayed-onset stub test (`nightOnsetTs` /
    /// `isPreOnsetAwakeStub`) MUST read asleep minutes format-agnostically: it previously used the
    /// dict-only `decodeStages`, which returns nil for a computed night's segment array, so every
    /// fragment of an on-device night read as 0 asleep minutes — a real ~54-min first sleep tripped the
    /// "essentially sleepless stub" branch and the shown bedtime jumped from the true 12:16 onset to the
    /// 1:29 main block, bypassing the #259 real-sleep-episode floor entirely (the 2026-07-14 night).
    /// `effectiveStartTs` threads the fragment's effective onset into the segment decode's #259
    /// pre-onset trim. Internal (not private) so the golden test pins the DECODE PATH itself, not a
    /// pre-computed minute count. Android twin: SleepScreen's onset stub-test caller needs the same
    /// both-format decode.
    static func decodedAsleepMinutes(_ json: String?, effectiveStartTs: Int) -> Double {
        decodeStages(json)?.asleep
            ?? decodeSegments(json, sessionStart: effectiveStartTs)?.stages.asleep
            ?? 0
    }

    /// Decode the imported stagesJSON dict of MINUTES {"light","deep","rem","awake"}.
    /// Internal (not private) so `SleepModel.mergeDay` (SleepModel.swift) can call it.
    static func decodeStages(_ json: String?) -> Stages? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data),
              let dict = obj as? [String: Any] else { return nil }
        func val(_ key: String) -> Double {
            if let n = dict[key] as? NSNumber { return n.doubleValue }
            if let d = dict[key] as? Double { return d }
            if let i = dict[key] as? Int { return Double(i) }
            return 0
        }
        let s = Stages(awake: val("awake"), light: val("light"),
                       deep: val("deep"), rem: val("rem"))
        return s.total > 0 ? s : nil
    }

    /// Decode the COMPUTED stagesJSON segment array [{"start":epoch,"end":epoch,"stage":"wake"|
    /// "light"|"deep"|"rem"}] into stage totals plus the real timeline (seconds relative to the
    /// session start, the Hypnogram's domain). The on-device SleepStager calls awake "wake". (#77)
    /// Internal (not private) so `SleepModel.mergeDay` (SleepModel.swift) can call it.
    static func decodeSegments(
        _ json: String?, sessionStart: Int
    ) -> (stages: Stages, intervals: [SleepInterval])? {
        guard let json, let data = json.data(using: .utf8),
              let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]],
              !arr.isEmpty else { return nil }
        var stages = Stages(awake: 0, light: 0, deep: 0, rem: 0)
        var intervals: [SleepInterval] = []
        for seg in arr {
            guard let rawStart = (seg["start"] as? NSNumber)?.intValue,
                  let end = (seg["end"] as? NSNumber)?.intValue,
                  let name = seg["stage"] as? String else { continue }
            // #259: trim each segment to the effective onset (`sessionStart`) so a hand-edited bedtime the
            // raw was too sparse to re-stage (WHOOP 4.0) can't sum pre-onset stages past time-in-bed — nor
            // draw bars before the onset. No-op when segments already start at/after it (the common case).
            let start = max(rawStart, sessionStart)
            guard end > start else { continue }
            let minutes = Double(end - start) / 60.0
            let stage: SleepStage
            switch name {
            case "wake", "awake": stage = .awake; stages.awake += minutes
            case "light": stage = .light; stages.light += minutes
            case "deep": stage = .deep; stages.deep += minutes
            case "rem": stage = .rem; stages.rem += minutes
            default: continue
            }
            intervals.append(SleepInterval(
                stage: stage,
                start: TimeInterval(start - sessionStart),
                end: TimeInterval(end - sessionStart)))
        }
        return stages.total > 0 ? (stages, intervals) : nil
    }

}

/// Original atmospheric night hero — photographic moonlit lake plus lightweight static depth layers.
/// Drawn as ScreenScaffold.topBackground (fixed under the status bar / overscroll); bottom fades into
/// `surfaceBase` before the first card. No TimelineView, no animation loops.
/// Cheap: one Image + static Canvas/shapes.
struct SleepPerformanceNightScene: View {
    private struct Star {
        let x: CGFloat
        let y: CGFloat
        let size: CGFloat
        let opacity: Double
    }

    /// Dense-enough star field for a readable night sky without particles.
    private let stars: [Star] = [
        .init(x: 0.04, y: 0.06, size: 1.1, opacity: 0.50),
        .init(x: 0.09, y: 0.14, size: 0.8, opacity: 0.36),
        .init(x: 0.15, y: 0.05, size: 1.2, opacity: 0.55),
        .init(x: 0.21, y: 0.18, size: 0.9, opacity: 0.40),
        .init(x: 0.28, y: 0.08, size: 1.0, opacity: 0.46),
        .init(x: 0.34, y: 0.16, size: 0.7, opacity: 0.32),
        .init(x: 0.41, y: 0.04, size: 1.1, opacity: 0.48),
        .init(x: 0.47, y: 0.13, size: 0.8, opacity: 0.38),
        .init(x: 0.54, y: 0.07, size: 1.0, opacity: 0.44),
        .init(x: 0.60, y: 0.19, size: 0.9, opacity: 0.36),
        .init(x: 0.67, y: 0.05, size: 1.2, opacity: 0.52),
        .init(x: 0.73, y: 0.15, size: 0.8, opacity: 0.34),
        .init(x: 0.80, y: 0.09, size: 1.0, opacity: 0.46),
        .init(x: 0.86, y: 0.17, size: 0.7, opacity: 0.30),
        .init(x: 0.92, y: 0.06, size: 1.1, opacity: 0.48),
        .init(x: 0.96, y: 0.14, size: 0.8, opacity: 0.34),
        .init(x: 0.12, y: 0.26, size: 0.7, opacity: 0.26),
        .init(x: 0.38, y: 0.24, size: 0.8, opacity: 0.28),
        .init(x: 0.58, y: 0.28, size: 0.7, opacity: 0.24),
        .init(x: 0.82, y: 0.25, size: 0.8, opacity: 0.28),
        .init(x: 0.25, y: 0.32, size: 0.6, opacity: 0.20),
        .init(x: 0.70, y: 0.31, size: 0.6, opacity: 0.18)
    ]

    /// #1319: honour the Settings "Day-cycle background" toggle on the Sleep tab too. The bundled
    /// moonlit-lake scene used to draw unconditionally here, so an iOS user who turned the toggle off
    /// still saw it on Sleep — while Home/Today (and the Android Sleep screen) already went plain.
    @AppStorage(SceneBackgroundPrefs.enabledKey) private var showDayCycleBackground = true

    var body: some View {
        if showDayCycleBackground { nightScene } else { StrandPalette.surfaceBase }
    }

    /// The bundled night scene (moonlit lake + procedural fallback). Shown only when the day-cycle
    /// background is enabled; off swaps it for the plain surfaceBase canvas, parity with Home/Today.
    private var nightScene: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack(alignment: .bottom) {
                // Guaranteed atmospheric base (lake / hills / sky) if the photo asset is missing.
                proceduralNightBase(width: w, height: h)

                // Photographic original (moonlit lake). Ships in StrandiOS Assets.xcassets.
                Group {
                    if let img = resolvedNightHeroImage {
                        img
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color.clear
                    }
                }
                .frame(width: w, height: h, alignment: .center)
                .clipped()
                .allowsHitTesting(false)

                // Light readability wash — keep the photo visible, don't flatten to a blue gradient.
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.18),
                        Color.black.opacity(0.04),
                        Color.black.opacity(0.10)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)

                // Soft moonlight bloom (upper-right) — restrained periwinkle, not purple.
                RadialGradient(
                    colors: [
                        StrandPalette.restGlow.opacity(0.12),
                        StrandPalette.restColor.opacity(0.04),
                        .clear
                    ],
                    center: UnitPoint(x: 0.78, y: 0.12),
                    startRadius: 2,
                    endRadius: max(w, h) * 0.42
                )
                .allowsHitTesting(false)

                // Extra star sparkle over the photo sky.
                Canvas { context, size in
                    for star in stars {
                        let rect = CGRect(
                            x: size.width * star.x,
                            y: size.height * star.y,
                            width: star.size,
                            height: star.size
                        )
                        context.fill(Path(ellipseIn: rect),
                                     with: .color(Color.white.opacity(star.opacity)))
                    }
                }
                .allowsHitTesting(false)

                // Near-shore pine silhouettes — original, not Yosemite peaks.
                pineSilhouette(width: w, height: h)
                    .fill(Color.black.opacity(0.34))
                    .allowsHitTesting(false)

                // Soft haze near the waterline / mid-band.
                LinearGradient(
                    colors: [
                        .clear,
                        StrandPalette.restDeep.opacity(0.06),
                        Color.black.opacity(0.10)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: h * 0.30)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(false)

                // Fade into the Sleep tab canvas BEFORE the first card.
                LinearGradient(
                    colors: [
                        .clear,
                        StrandPalette.surfaceBase.opacity(0.25),
                        StrandPalette.surfaceBase.opacity(0.78),
                        StrandPalette.surfaceBase
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: max(48, h * 0.20))
                .frame(maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(false)
            }
        }
    }

    /// Prefer the catalog image; fall back to the bundled HEIC resource if needed.
    private var resolvedNightHeroImage: Image? {
        #if canImport(UIKit)
        if let ui = UIImage(named: "sleepNightHero") {
            return Image(uiImage: ui)
        }
        if let url = Bundle.main.url(forResource: "SleepNightHero", withExtension: "heic"),
           let ui = UIImage(contentsOfFile: url.path) {
            return Image(uiImage: ui)
        }
        return nil
        #else
        return Image("sleepNightHero")
        #endif
    }

    /// Static procedural night environment — calm lake, low hills, pines, moon glow.
    /// Visible when the photo fails to load; also peeks through translucent photo edges.
    @ViewBuilder
    private func proceduralNightBase(width w: CGFloat, height h: CGFloat) -> some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.06, blue: 0.14),
                    Color(red: 0.06, green: 0.09, blue: 0.18),
                    Color(red: 0.03, green: 0.05, blue: 0.10)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Moon + soft halo (upper right).
            Circle()
                .fill(Color.white.opacity(0.78))
                .frame(width: 18, height: 18)
                .blur(radius: 0.4)
                .overlay(
                    Circle()
                        .fill(StrandPalette.restGlow.opacity(0.18))
                        .frame(width: 90, height: 90)
                        .blur(radius: 22)
                )
                .position(x: w * 0.78, y: h * 0.14)

            // Distant low hills.
            Path { p in
                let y0 = h * 0.48
                p.move(to: CGPoint(x: 0, y: h))
                p.addLine(to: CGPoint(x: 0, y: y0 + 18))
                p.addCurve(to: CGPoint(x: w * 0.28, y: y0 - 6),
                           control1: CGPoint(x: w * 0.10, y: y0 + 6),
                           control2: CGPoint(x: w * 0.18, y: y0 - 14))
                p.addCurve(to: CGPoint(x: w * 0.55, y: y0 + 10),
                           control1: CGPoint(x: w * 0.38, y: y0 + 8),
                           control2: CGPoint(x: w * 0.46, y: y0 + 16))
                p.addCurve(to: CGPoint(x: w * 0.82, y: y0 - 2),
                           control1: CGPoint(x: w * 0.66, y: y0 + 2),
                           control2: CGPoint(x: w * 0.74, y: y0 - 12))
                p.addCurve(to: CGPoint(x: w, y: y0 + 14),
                           control1: CGPoint(x: w * 0.90, y: y0 + 6),
                           control2: CGPoint(x: w * 0.96, y: y0 + 12))
                p.addLine(to: CGPoint(x: w, y: h))
                p.closeSubpath()
            }
            .fill(Color.black.opacity(0.42))

            // Lake band with faint moonlight reflection.
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.08, blue: 0.16).opacity(0.90),
                    Color(red: 0.08, green: 0.12, blue: 0.22).opacity(0.75),
                    Color(red: 0.03, green: 0.05, blue: 0.10)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: h * 0.38)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [
                        StrandPalette.restGlow.opacity(0.10),
                        StrandPalette.restGlow.opacity(0.03),
                        .clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: w * 0.14, height: h * 0.28)
                .offset(x: w * 0.18)
                .blur(radius: 8)
            }

            // Soft cloud / haze wisps.
            Ellipse()
                .fill(Color.white.opacity(0.04))
                .frame(width: w * 0.55, height: 28)
                .blur(radius: 16)
                .position(x: w * 0.35, y: h * 0.22)
            Ellipse()
                .fill(StrandPalette.restColor.opacity(0.05))
                .frame(width: w * 0.45, height: 22)
                .blur(radius: 14)
                .position(x: w * 0.70, y: h * 0.18)
        }
        .allowsHitTesting(false)
    }

    private func pineSilhouette(width w: CGFloat, height h: CGFloat) -> Path {
        Path { p in
            let base = h * 0.72
            // Left shoreline pines.
            p.move(to: CGPoint(x: 0, y: h))
            p.addLine(to: CGPoint(x: 0, y: base - 8))
            for i in 0..<7 {
                let x = w * (0.02 + CGFloat(i) * 0.045)
                let tip = base - (18 + CGFloat(i % 3) * 10)
                p.addLine(to: CGPoint(x: x - 6, y: base + 4))
                p.addLine(to: CGPoint(x: x, y: tip))
                p.addLine(to: CGPoint(x: x + 6, y: base + 4))
            }
            p.addLine(to: CGPoint(x: w * 0.38, y: base + 10))
            // Low mid shoreline.
            p.addCurve(to: CGPoint(x: w * 0.72, y: base + 6),
                       control1: CGPoint(x: w * 0.50, y: base + 16),
                       control2: CGPoint(x: w * 0.62, y: base))
            // Right pines.
            for i in 0..<5 {
                let x = w * (0.78 + CGFloat(i) * 0.045)
                let tip = base - (14 + CGFloat((i + 1) % 3) * 9)
                p.addLine(to: CGPoint(x: x - 5, y: base + 4))
                p.addLine(to: CGPoint(x: x, y: tip))
                p.addLine(to: CGPoint(x: x + 5, y: base + 4))
            }
            p.addLine(to: CGPoint(x: w, y: base + 8))
            p.addLine(to: CGPoint(x: w, y: h))
            p.closeSubpath()
        }
    }
}

// MARK: - Live-observing leaf subviews (scroll-stutter isolation)
//
// SleepView itself does NOT observe `LiveState` (a connected strap publishes at ~1 Hz, which would
// re-evaluate the heavy Sleep body on every tick). These two small leaves each hold their OWN
// `@EnvironmentObject var live`, so a live tick re-renders only the mark card / syncing note — never
// the hero hypnogram, the stage chart, the metric grid or the trends. They render byte-for-byte what
// the inline code did before the extraction (mirrors the Today leaf-scoping pattern).

/// The "going to sleep / I'm awake" sleep-mark card (#461, Phase 1). Tapping logs a timestamped mark —
/// persisted to the `sleep_mark` metric series AND appended to the shareable strap log — then confirms
/// with a haptic and a transient line. LOGGING ONLY: a mark never touches the sleep detector or the
/// night boundaries. Owns `live` (it appends to the strap log) + `repo` (the metric-series write) and
/// the `lastMark` confirmation state, so its strap-log write keeps working without SleepView observing.
/// The "Sleep marks" tap-to-log card. Lives in the Sleep tab but is also hostable in Today
/// (#today-hosted-cards), so it is `internal` (not `private`) and self-contained — it reads only the
/// shared `repo`/`live` environment objects, both present on Today too.
struct SleepMarkCard: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var live: LiveState

    /// The most recent sleep-mark the user tapped, shown as a transient confirmation line under the
    /// two buttons. Drives the SwiftUI haptic landing too. LOGGING-ONLY: a mark never feeds the sleep
    /// detector — it's persisted to the metric series + strap log. (#461)
    @State private var lastMark: SleepMark?

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            SectionHeader("Sleep marks", overline: "Tap to log")
            NoopCard(tint: StrandPalette.restColor) {
                VStack(alignment: .leading, spacing: NoopMetrics.cardInnerSpacing) {
                    Text("Tap when you're heading to bed or when you wake. Each tap is logged with the time. It doesn't change tonight's detected sleep.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: NoopMetrics.gap) {
                        // Routed through the unified NoopButton system so the two marks sit identically
                        // (sentence-case label, leading icon at 8pt, controlHeight=48, no glow).
                        NoopButton("Going to sleep", systemImage: "moon.zzz.fill",
                                   kind: .secondary, fullWidth: true) { logMark(.bedtime) }
                            .accessibilityLabel("Log going to sleep")

                        NoopButton("I'm awake", systemImage: "sun.max.fill",
                                   kind: .secondary, fullWidth: true) { logMark(.wake) }
                            .accessibilityLabel("Log waking up")
                    }
                    if let lastMark {
                        Text(lastMark.confirmation)
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.restColor)
                            .transition(.opacity)
                            .accessibilityLabel(lastMark.confirmation)
                    }
                }
            }
        }
        // A success haptic lands when a new mark is captured (value-driven, not per-tap), matching the
        // app's sparse tactile vocabulary. No-op on macOS.
        .strandHaptic(.success, trigger: lastMark?.tsMs ?? 0)
    }

    /// Persist + log a tapped mark. Optimistically shows the confirmation immediately, fires the
    /// haptic via `lastMark`, appends the human-readable strap-log line, then writes the metric-series
    /// row through the repo's live store handle (no new Repository API, no schema change). The write is
    /// idempotent by (deviceId, day, key). (#461)
    private func logMark(_ type: SleepMarkType) {
        let mark = SleepMark(type: type)
        withAnimation(.easeOut(duration: 0.2)) { lastMark = mark }
        // The shareable strap log is the human-readable surface that lands in a debug export.
        live.append(log: mark.logLine)
        Task {
            guard let store = await repo.storeHandle() else { return }
            try? await store.upsertMetricSeries([mark.metricPoint], deviceId: repo.deviceId)
        }
    }
}

/// The "Syncing strap history…" note, shown only while a historical offload is running (#77). Owns the
/// `LiveState` observation so the chunk count ticks without re-rendering the rest of the Sleep screen.
enum SleepFreshnessStatus: Equatable {
    case syncing, calculating, syncFailed, awaitingSync, notDetected
}

/// Pure priority ladder behind the Sleep status banner. "Missing" is deliberately held until morning so
/// opening Sleep during the night does not claim a still-in-progress night was missed.
func resolveSleepFreshness(hasCurrentNight: Bool, morningReady: Bool, syncing: Bool,
                           calculating: Bool, syncedSinceDayStart: Bool,
                           syncFailed: Bool) -> SleepFreshnessStatus? {
    if syncing { return .syncing }
    // #2108: a night already in hand outranks .calculating. It used to sit below, so `hasCurrentNight`
    // could only silence the missing-night states and a finished night was structurally unable to
    // silence this one: the banner said "detecting and staging the night now" directly above that same
    // night scored, timed and staged on screen. A note that contradicts the content beside it is worse
    // than no note, and one that is always on is read by nobody the day it matters. .syncing stays
    // above, because data still arriving can genuinely change what is shown.
    if hasCurrentNight { return nil }
    if calculating { return .calculating }
    if !morningReady { return nil }
    if syncFailed { return .syncFailed }
    return syncedSinceDayStart ? .notDetected : .awaitingSync
}

/// Explicit state for the expected current night. Older sleep can remain available underneath, but it is
/// never left to impersonate today's result while a sync, calculation, or failed detection is unresolved.
private struct SleepFreshnessNote: View {
    @EnvironmentObject private var live: LiveState
    @EnvironmentObject private var intelligence: IntelligenceEngine
    let latestWakeTs: Int?

    var body: some View {
        let calendar = Calendar.current
        let now = Date()
        let start = calendar.startOfDay(for: now)
        let current = latestWakeTs.map {
            calendar.isDate(Date(timeIntervalSince1970: TimeInterval($0)), inSameDayAs: now)
        } ?? false
        // AppModel intentionally waits two quiet seconds after HISTORY_COMPLETE before starting the
        // scoring pass. Treat that debounce as calculation too; otherwise the banner can flash the final
        // "wasn't detected" verdict between sync completion and `intelligence.computing` becoming true.
        let calculationQueued = live.lastSyncedAt.map {
            (0..<5).contains(now.timeIntervalSince1970 - $0)
        } ?? false
        let status = resolveSleepFreshness(
            hasCurrentNight: current,
            morningReady: calendar.component(.hour, from: now) >= 6,
            syncing: live.backfilling,
            calculating: intelligence.computing || calculationQueued,
            syncedSinceDayStart: (live.lastSyncedAt ?? 0) >= start.timeIntervalSince1970,
            syncFailed: live.lastSyncError != nil
        )
        switch status {
        case .syncing:
            SyncingHistoryNote(chunks: live.syncChunksThisSession)
        case .calculating:
            DataPendingNote(title: "Calculating last night's sleep…",
                            message: "Your strap history is in. NOOP is detecting and staging the night now.",
                            symbol: "waveform.path.ecg")
        case .syncFailed:
            DataPendingNote(title: "Last night's sleep hasn't synced",
                            message: "The history sync stopped before it finished. Keep the strap nearby and try Sync again.",
                            symbol: "exclamationmark.arrow.triangle.2.circlepath")
        case .awaitingSync:
            DataPendingNote(title: "Waiting for last night's sleep",
                            message: "Connect the strap and sync its history. NOOP will calculate the night when the overnight data arrives.",
                            symbol: "arrow.triangle.2.circlepath")
        case .notDetected:
            DataPendingNote(title: "Last night's sleep wasn't detected",
                            message: "Sync finished, but NOOP couldn't confidently identify a sleep window. Keep the strap connected and try Sync again; the older night below is still your latest detected sleep.",
                            symbol: "moon.zzz")
        case nil:
            EmptyView()
        }
    }
}

// MARK: - Local value types

/// Cheap, Equatable fingerprint of the repo inputs SleepView derives from. Two snapshots are
/// equal iff the data the screen reads is unchanged, so the heavy `SleepModel` rebuild is
/// skipped on the many `body` re-evaluations that don't touch sleep data.
private struct SleepInputKey: Equatable {
    let loaded: Bool
    let daysCount: Int
    let sleepsCount: Int
    let firstDay: String?
    let lastDay: String?
    /// Newest day row (Equatable) — catches in-place edits to the latest day's values.
    let lastDayUpdated: DailyMetric?
    /// Newest sleep session (Equatable) — catches a re-import of the latest night.
    let lastSleep: CachedSleepSession?
    /// Bumped on every Repository.refresh — catches a re-import that changes only the
    /// imported metricSeries figures (importedSleep) without touching days/sleeps.
    let refreshSeq: Int
}

// SleepModel / Night / Stages and the pure `SleepModel.build(_:)` derivation pipeline now live in
// SleepModel.swift, so the Today host can build the same model without a SleepView instance.

// MARK: - Wake-time editor

/// Identifies the night being edited for `.sheet(item:)`. A night's `startTs` is its stable natural
/// key (wake-time edits never move it), so it doubles as the sheet identity.
/// The transient UNDO banner state after a suppressing delete (#65). `identityStart` is the immutable
/// detected key so a stale auto-dismiss task can tell whether it still owns the current banner;
/// `displayStart` is the effective (shown) onset for the message clock.
private struct SleepUndoBanner {
    let snapshot: SleepDeletionSnapshot
    let identityStart: Int
    let displayStart: Int
    let windowEnd: Int
}

private struct WakeEdit: Identifiable {
    let detectedStartTs: Int   // immutable detected key the edit writes against
    let bedTs: Int             // current effective onset (seeds the bed picker)
    let wakeTs: Int            // current wake (seeds the wake picker)
    let stagesJSON: String?
    /// True for a hand-edited / manually-added (nap) night. Such a delete writes NO tombstone (it is
    /// never re-detected), so the editor's delete-confirm copy must NOT promise re-detection suppression
    /// for it. Mirrors the undo-banner branch (#65 banner/confirm honesty).
    let userEdited: Bool
    var id: Int { detectedStartTs }
}

/// Seeds the "Add nap" picker (#508). A nap is short, so seed a 30-minute window anchored to the night's
/// wake (a natural place to look for a missed afternoon nap), clamped to never start before the night's
/// onset. The identity is the seed start so `.sheet(item:)` presents once per request.
private struct AddNapSeed: Identifiable {
    let bedTs: Int
    let wakeTs: Int
    var id: Int { bedTs }
    init(forNight night: Night) {
        // Anchor an hour after the night's wake; a 30-min default window the user adjusts.
        let anchor = night.session.endTs + 3_600
        self.bedTs = anchor
        self.wakeTs = anchor + 30 * 60
    }
}

/// A small sheet to hand-correct a night's bed (onset) and wake (end) instants. Seeds both pickers with
/// the current values, including each calendar date. Hands the chosen unix-second (bed, wake) back via
/// `onSave`. Pure presentation + a single async save — persistence lives in the repo.
private struct SleepTimeEditor: View {
    let onSave: (Int, Int) async -> Void
    /// Optional destructive delete (#68). Non-nil for an existing main-sleep / nap edit (the editor then
    /// shows a "Delete this sleep" button gated behind a confirmation); nil for the "Add a nap" sheet,
    /// which has nothing to delete yet.
    let onDelete: (() async -> Void)?
    private let title: LocalizedStringKey
    private let blurb: LocalizedStringKey
    private let bedLabel: LocalizedStringKey
    private let wakeLabel: LocalizedStringKey
    private let deleteLabel: LocalizedStringKey
    /// The night's RECORDED coverage (detected onset ... current wake, unix seconds) for the #940
    /// guards: a time-only bed roll past the wake auto-decrements the date, and a corrected window
    /// fully outside this range gets an explicit confirm instead of silent acceptance. nil for the
    /// "Add a nap" sheet, whose window deliberately sits outside the night (only the future-bed
    /// guard applies there).
    private let coverage: ClosedRange<Int>?
    /// True when deleting THIS session writes a re-detection tombstone (a DETECTED night). false for a
    /// userEdited/nap row, which is never re-detected, so the delete-confirm copy drops the suppression
    /// promise for it, matching the undo banner. (#65 confirm honesty.)
    private let suppressesReDetection: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var bed: Date
    @State private var wake: Date
    @State private var saving = false
    @State private var confirmingDelete = false
    /// The bed value BEFORE the in-flight picker change, so the #940 auto-correct can tell a
    /// time-only roll (same calendar day: rescue it) from a deliberate date change (respect it).
    @State private var previousBed: Date
    /// True while the #940 "no recorded data there" confirm is up; Save proceeds only on consent.
    @State private var confirmingDisjoint = false

    /// `title`/`blurb`/`bedLabel`/`wakeLabel` default to the edit-an-existing-night wording; the
    /// "Add a nap" caller (#508) overrides them. The save logic is identical either way — adding a nap
    /// is just an edit whose "existing" window is a seed. `onDelete` (#68) is the optional destructive
    /// action; `deleteLabel` lets the nap editor say "Delete this nap".
    init(bedTs: Int, wakeTs: Int,
         title: LocalizedStringKey = "Edit sleep times",
         blurb: LocalizedStringKey = "Correct when you went to bed and woke. Stages are re-derived from your data; the edit is kept through the next strap sync.",
         bedLabel: LocalizedStringKey = "Asleep",
         wakeLabel: LocalizedStringKey = "Woke",
         deleteLabel: LocalizedStringKey = "Delete this sleep",
         coverage: ClosedRange<Int>? = nil,
         suppressesReDetection: Bool = true,
         onSave: @escaping (Int, Int) async -> Void,
         onDelete: (() async -> Void)? = nil) {
        self.onSave = onSave
        self.onDelete = onDelete
        self.title = title; self.blurb = blurb
        self.bedLabel = bedLabel; self.wakeLabel = wakeLabel
        self.deleteLabel = deleteLabel
        self.coverage = coverage
        self.suppressesReDetection = suppressesReDetection
        // A bed can never be seeded in the future (#940): the "Add a nap" anchor is wake+1h, which is
        // ahead of the clock right after a morning sync; clamp so the picker opens inside its bound.
        let seedBed = min(bedTs, Int(Date().timeIntervalSince1970))
        _bed = State(initialValue: Date(timeIntervalSince1970: TimeInterval(seedBed)))
        _previousBed = State(initialValue: Date(timeIntervalSince1970: TimeInterval(seedBed)))
        _wake = State(initialValue: Date(timeIntervalSince1970: TimeInterval(wakeTs)))
    }

    /// The current edit window after the same future/inverted/duration guards used by persistence.
    private var validatedWindow: (start: Int, end: Int)? {
        SleepEditGuard.clampedEditWindow(
            start: Int(bed.timeIntervalSince1970),
            end: Int(wake.timeIntervalSince1970),
            now: Int(Date().timeIntervalSince1970))
    }

    /// The single save funnel: both the direct Save and the #940 disjoint confirm land here.
    private func commit(start: Int, end: Int) {
        saving = true
        Task {
            await onSave(start, end)
            dismiss()
        }
    }

    var body: some View {
        let canSave = validatedWindow != nil

        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            Text(title).font(StrandFont.title2).foregroundStyle(StrandPalette.textPrimary)
            Text(blurb)
                .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            NoopCard(padding: NoopMetrics.cardPadding, tint: StrandPalette.restColor) {
                VStack(alignment: .leading, spacing: 10) {
                    // Bed is bounded to the PAST (#940): a sleep can't start in the future, and an
                    // unbounded picker let a cross-midnight time roll land the bed on the coming
                    // evening, creating a future-dated night the tab couldn't render.
                    DatePicker(bedLabel, selection: $bed, in: ...Date(),
                               displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.compact)
                        .font(StrandFont.body)
                        .tint(StrandPalette.restColor)
                    Divider().overlay(StrandPalette.hairline)
                    // The wake date and time are both editable so corrections preserve the exact
                    // endpoint selected by the user (#970).
                    DatePicker(wakeLabel, selection: $wake, in: ...Date(),
                               displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.compact)
                        .font(StrandFont.body)
                        .tint(StrandPalette.restColor)
                }
            }

            // Destructive delete for an existing night/nap (#68). Confirmation-gated so a tap can't clear
            // a night by accident; nil for the "Add a nap" sheet (nothing to delete). Sits below the
            // pickers, visually separated from the primary Save action.
            if onDelete != nil {
                Button(role: .destructive) { confirmingDelete = true } label: {
                    Label(deleteLabel, systemImage: "trash")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.statusCritical)
                }
                .buttonStyle(.plain)
                .disabled(saving)
                .accessibilityLabel(deleteLabel)
            }

            HStack(spacing: NoopMetrics.gap) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.noopGhost)
                    .disabled(saving)
                Spacer()
                Button(saving ? "Saving…" : "Save") {
                    // #940 guard 2: a corrected window that no longer touches the night's recorded
                    // coverage has no data to stage from. Silently accepting it fabricated an
                    // all-awake phantom night; ask first.
                    guard let window = validatedWindow else { return }
                    if let coverage, SleepEditGuard.isDisjoint(
                        newStart: window.start, newEnd: window.end,
                        coverageStart: coverage.lowerBound, coverageEnd: coverage.upperBound) {
                        confirmingDisjoint = true
                    } else {
                        commit(start: window.start, end: window.end)
                    }
                }
                .buttonStyle(.noopPrimary)
                .disabled(saving || !canSave)
                .opacity(canSave ? 1 : 0.55)
            }
        }
        .padding(NoopMetrics.screenPadding)
        .frame(minWidth: 360)
        .background(NoopChromeSurface())
        // #940 guard 1: a time-only roll that lands the bed in the future, or at/after the night's
        // wake, almost always means the PREVIOUS evening (23:00 "yesterday", not tonight). Snap the
        // date back a day so the picker visibly shows the night the user meant. Pure rule + tests:
        // SleepEditGuard.autoCorrectedBed (Android twin in com.noop.analytics).
        .onChangeCompat(of: bed) { newBed in
            let corrected = SleepEditGuard.autoCorrectedBed(
                previousBed: previousBed, candidateBed: newBed,
                originalWake: coverage.map { Date(timeIntervalSince1970: TimeInterval($0.upperBound)) },
                now: Date())
            previousBed = corrected
            if corrected != newBed { bed = corrected }
        }
        // #940 guard 2's consent step. On-brand role-tagged .alert, same shape as the delete confirm.
        .alert("Move this sleep?", isPresented: $confirmingDisjoint) {
            Button("Cancel", role: .cancel) { }
            Button("Move anyway") {
                guard let window = SleepEditGuard.clampedEditWindow(
                    start: Int(bed.timeIntervalSince1970),
                    end: Int(wake.timeIntervalSince1970),
                    now: Int(Date().timeIntervalSince1970)) else { return }
                commit(start: window.start, end: window.end)
            }
        } message: {
            Text("This moves the night to a time with no recorded data. Stages can't be derived there, so it may show as empty until data covers it.")
        }
        // On-brand destructive confirm — the same role-tagged .alert DevicesView uses for "Remove this
        // device?", not a bare default. (#68 — Android parity: "Delete this sleep session?")
        .alert("Delete this sleep session?", isPresented: $confirmingDelete) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                saving = true
                Task {
                    await onDelete?()
                    dismiss()
                }
            }
        } message: {
            // A detected night is tombstoned so it won't re-detect; a userEdited/nap row writes no
            // tombstone, so its copy drops that (false) promise. Mirrors the undo banner. (#65)
            Text(suppressesReDetection
                 ? "Removes this recorded sleep and recomputes the day without it. NOOP won't re-detect sleep in this window. You can undo for a few seconds after."
                 : "Removes this sleep and recomputes the day without it. You can undo for a few seconds after.")
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Sleep") {
    let repo = Repository.previewSleep()
    return SleepView()
        .environmentObject(repo)
        .environmentObject(LiveState())
        .environmentObject(AppModel())
        .environmentObject(IntelligenceEngine(repo: repo, profile: ProfileStore(), deviceId: "preview"))
        .frame(width: 980, height: 1180)
        .preferredColorScheme(.dark)
}

@MainActor
private extension Repository {
    /// Sample repository populated with imported-style nights for previews.
    static func previewSleep() -> Repository {
        let repo = Repository(deviceId: "preview")
        let cal = Calendar.current
        let now = Date()

        var days: [DailyMetric] = []
        var sleeps: [CachedSleepSession] = []
        let fmt: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd"
            return f
        }()

        for i in (0..<30).reversed() {
            let date = cal.date(byAdding: .day, value: -i, to: now)!
            let jitter = Double((i * 23) % 11) - 5
            let light = 210.0 + jitter
            let deep = 80.0 + jitter * 0.5
            let rem = 95.0 + jitter * 0.7
            let awake = 25.0 + Double((i * 7) % 9)
            let asleep = light + deep + rem
            let stagesJSON = "{\"light\":\(light),\"deep\":\(deep),\"rem\":\(rem),\"awake\":\(awake)}"

            days.append(DailyMetric(
                day: fmt.string(from: date),
                totalSleepMin: asleep,
                efficiency: 88 + jitter * 0.3,
                deepMin: deep, remMin: rem, lightMin: light,
                disturbances: Int(awake / 6), restingHr: 50 + (i % 4),
                avgHrv: 65 - Double(i % 5), recovery: 60 + jitter,
                strain: 10 + Double(i % 6), exerciseCount: i % 2,
                spo2Pct: 96, skinTempDevC: 33.4, respRateBpm: 14.6 + jitter * 0.1))

            var onset = cal.date(bySettingHour: 22, minute: 50 + Int(jitter), second: 0, of: date) ?? date
            onset = cal.date(byAdding: .day, value: -1, to: onset) ?? onset
            let end = onset.addingTimeInterval((asleep + awake) * 60)
            sleeps.append(CachedSleepSession(
                startTs: Int(onset.timeIntervalSince1970),
                endTs: Int(end.timeIntervalSince1970),
                efficiency: 88 + jitter * 0.3,
                restingHr: 50 + (i % 4),
                avgHrv: 65 - Double(i % 5),
                stagesJSON: stagesJSON))
        }

        repo.days = days
        repo.sleeps = sleeps
        repo.loaded = true
        return repo
    }
}
#endif
