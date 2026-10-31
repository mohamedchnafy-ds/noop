import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopProtocol
import WhoopStore

// The two numbers on the session's surfaces that change on their own — the running clock and the live heart
// rate — each as its own small view, so a tick or a heartbeat redraws that one number and nothing around it.
//
// They used to be read by the screens that show them: the whole session sheet and the minimised bar watched
// the session's once-a-second tick and every change the app model published, and the sheet also watched the
// strap's live state, which changes with every log line and every beat. So the sheet — a hundred text fields —
// was redrawn several times a second for as long as it was open, even with NOOP off screen, and iOS killed
// NOOP for background CPU four times in one gym session (21 Sep 2026).

/// A running clock that ticks by itself while it is shown and costs nothing while it is not: a `TimelineView`
/// redraws this one text each second, aligned to the whole second, and SwiftUI runs a timeline only for a view
/// on screen. `seconds` turns the current unix second into what the clock reads; the format is NOOP's
/// `ActiveWorkoutClock.clock`, the one the Lock Screen's clock also reads as.
struct LiftRunningClock: View {
    let seconds: (Int) -> Int

    var body: some View {
        TimelineView(.periodic(from: Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970)), by: 1)) {
            context in
            Text(ActiveWorkoutClock.clock(seconds(Int(context.date.timeIntervalSince1970))))
                .monospacedDigit()
        }
    }
}

/// The live heart rate: the smoothed, spike-filtered `AppModel.bpm` every screen shows, never the raw per-beat
/// number. ALWAYS shown, a dash when the strap is not reading: an earlier version hid it with no reading, and
/// the first thing that produced was "there is no HR in the minimised tab" — an absent readout is
/// indistinguishable from an absent feature, while a dash says the strap is not reading, which is something to
/// act on. Display only: nothing here feeds a score; Effort stays what the strap measured.
struct LiftHeartRate: View {
    enum Style {
        /// Heart and number in caption size — the minimised bar.
        case compact
        /// The number alone in body size, under the sheet's "HR" label.
        case plain
    }

    let style: Style
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let tint = model.bpm == nil ? StrandPalette.textTertiary : StrandPalette.metricRose
        let value = Text(model.bpm.map(String.init) ?? "—").monospacedDigit()
        switch style {
        case .compact:
            HStack(spacing: 3) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 10, weight: .semibold))
                value.font(StrandFont.captionNumber)
            }
            .foregroundStyle(tint)
            .accessibilityLabel(model.bpm.map { String(localized: "Heart rate \($0)") }
                                ?? String(localized: "Heart rate"))
        case .plain:
            value
                .font(StrandFont.bodyNumber)
                .foregroundStyle(tint)
        }
    }
}

// MARK: - The guided superset screens' live parts (personal fork)
//
// The row of three tiles under a round and under a rest, and the strap line of a block's ready screen —
// the parts of `LiftSupersetScreen` that change on their own. Each stays the only thing that redraws
// when its number moves: the heart-rate tile with every beat, the Effort and energy tiles every fifteen
// seconds, and the screen around them never.

/// The live tiles of a round (heart rate and zone, Effort, energy) or of a rest (heart rate coming down,
/// the round's length, Effort).
struct LiftLiveVitalsRow: View {
    let vitals: LiftGuideVitals
    let sessionStart: Int

    /// Effort and energy so far, recomputed every few seconds by `LiftLiveEffortFeeder`. Owned here and
    /// read only by this row, so its refresh redraws three tiles and nothing else.
    @StateObject private var effort = LiftLiveEffort()
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue

    var body: some View {
        HStack(spacing: 10) {
            switch vitals {
            case .working:
                LiftLiveHeartRateTile(caption: .zone)
                effortTile
                LiftGuideTile(label: String(localized: "kcal"),
                              value: effort.kcal.map { "\(Int($0.rounded()))" } ?? "—",
                              caption: effort.avgHr.map { String(localized: "Avg HR \($0)") } ?? String(localized: "Live"))
            case .resting(let lastRoundSec):
                LiftLiveHeartRateTile(caption: .recovery)
                LiftGuideTile(label: String(localized: "Last round"),
                              value: lastRoundSec.map(ActiveWorkoutClock.clock) ?? "—",
                              caption: String(localized: "set length"))
                effortTile
            }
        }
        .background(LiftLiveEffortFeeder(effort: effort, sessionStart: sessionStart))
    }

    private var effortTile: some View {
        let scale = UnitPrefs.resolveEffortScale(effortScaleRaw)
        let value = effort.strain.map { strain -> String in
            let shown = UnitFormatter.effortValue(strain, scale: scale)
            return scale == .whoop ? String(format: "%.1f", shown) : "\(Int(shown.rounded()))"
        }
        return LiftGuideTile(label: String(localized: "Effort"), value: value ?? "—",
                             caption: String(localized: "live"))
    }
}

/// The session's Effort and energy so far, from the heart rate the strap has recorded since it began.
@MainActor
final class LiftLiveEffort: ObservableObject {
    @Published var strain: Double?
    @Published var kcal: Double?
    @Published var avgHr: Int?

    /// How often the figures are recomputed. Effort moves slowly; once a second would be work for nothing.
    static let refreshSec: UInt64 = 15
}

/// Fills a `LiftLiveEffort` while it is on screen. A view of its own, drawing nothing, so the app model and
/// the repository it reads — both of which change all the time — are watched by this empty view alone.
///
/// The figures are the SAME scorers a live workout and a saved one use (`StrainScorer`, `Calories`), over
/// the strap's recorded heart rate since the session began, with the wearer's resting heart rate, so the
/// number here is the number the saved workout will be filled with. Display only: nothing is stored.
private struct LiftLiveEffortFeeder: View {
    let effort: LiftLiveEffort
    let sessionStart: Int
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var repo: Repository

    var body: some View {
        Color.clear
            .task(id: sessionStart) {
                while !Task.isCancelled {
                    await refresh()
                    try? await Task.sleep(nanoseconds: LiftLiveEffort.refreshSec * 1_000_000_000)
                }
            }
    }

    private func refresh() async {
        let now = Int(Date().timeIntervalSince1970)
        let samples = await repo.hrSamples(from: sessionStart, to: now)
        guard samples.count >= 2 else { return }
        let profile = model.profile
        let restingHR = repo.today?.restingHr.map(Double.init) ?? StrainScorer.defaultRestingHR
        let body = UserProfile(weightKg: profile.weightKg, heightCm: profile.heightCm,
                               age: Double(profile.age), sex: profile.sex)
        let strain = StrainScorer.strain(samples, maxHR: Double(profile.hrMax), restingHR: restingHR,
                                         method: PuffinExperiment.effortMethod, sex: profile.sex)
        let energy = Calories.estimateBoutCalories(samples, profile: body, hrmax: Double(profile.hrMax),
                                                   restingHR: restingHR).0
        let kcal: Double? = energy > 0 ? energy : nil
        let average = Int((Double(samples.map(\.bpm).reduce(0, +)) / Double(samples.count)).rounded())
        // Only what moved is published, so a still figure does not redraw its tile.
        if effort.strain != strain { effort.strain = strain }
        if effort.kcal != kcal { effort.kcal = kcal }
        if effort.avgHr != average { effort.avgHr = average }
    }
}

/// The heart-rate tile: the live `AppModel.bpm`, with the zone while lifting and the way down while
/// resting — down from where it stood when the rest began.
struct LiftLiveHeartRateTile: View {
    enum Caption { case zone, recovery }

    let caption: Caption
    @EnvironmentObject private var model: AppModel
    /// The heart rate as the rest began, for "↓".
    @State private var atStart: Int?

    var body: some View {
        LiftGuideTile(label: String(localized: "HR"),
                      value: model.bpm.map(String.init) ?? "—",
                      tint: model.bpm == nil ? StrandPalette.textTertiary : StrandPalette.metricRose,
                      caption: captionText)
            .onAppear { if atStart == nil { atStart = model.bpm } }
    }

    private var captionText: String {
        switch caption {
        case .zone:
            guard let bpm = model.bpm else { return "bpm" }
            let zone = model.profile.hrZoneSet.zoneNumber(forBPM: Double(bpm))
            return zone >= 1 ? String(localized: "bpm · zone \(zone)") : "bpm"
        case .recovery:
            if let start = atStart, let bpm = model.bpm, bpm < start { return String(localized: "↓ recovering") }
            return String(localized: "recovering")
        }
    }
}

/// The ready screen's strap line, live.
struct LiftStrapCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        LiftStrapCardContent(bpm: model.bpm)
    }
}
