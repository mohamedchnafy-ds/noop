import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

// MARK: - Stages (read-only Today host card) (#today-hosted-cards)
//
// The Sleep tab's stages card is interactive (night navigation, the bed/wake editor, naps), so the Today
// glance surface hosts a READ-ONLY version: the CURRENT `model.night` (the SAME night + intervals the
// Sleep tab shows) drawn by the SAME `SleepPhasesCard`, with no footer actions.
//
// PARITY IS ON THE DATA: the Kotlin `SleepModel` carries no session timestamps or nap blocks, so the
// Android host shows the same stage split and nothing more. The heart-rate curve is the Sleep tab's own
// read of the night, and the curve switches are the same display preferences.

struct StagesCard: View {
    let model: SleepModel

    var body: some View {
        StageDetailView(night: model.night, intervals: model.intervals)
    }
}

/// The stages card for one night, read-only, with its own transient state (the tapped stage, the night's
/// curves) so tapping a stage in Today never reaches into SleepView.
struct StageDetailView: View {
    let night: Night
    let intervals: [SleepInterval]
    @EnvironmentObject var repo: Repository
    @State private var selectedStage: SleepStage? = nil
    @State private var nightHR: [HRBucket] = []
    @State private var nightHRV: [TrendPoint] = []
    @State private var nightSkinTemp: [TrendPoint] = []
    @AppStorage(SleepChartStyle.storageKey) private var sleepChartStyleRaw = SleepChartStyle.classic.rawValue
    @AppStorage(SleepCurvePrefs.hrKey) private var showHR = true
    @AppStorage(SleepCurvePrefs.hrvKey) private var showHRV = false
    @AppStorage(SleepCurvePrefs.skinTempKey) private var showSkinTemp = false
    @AppStorage(SleepCurvePrefs.motionKey) private var showMotion = false

    var body: some View {
        let s = night.stages
        let percents = StagePercentages.wholePercentages([s.awake, s.light, s.deep, s.rem])
        func percent(_ stage: SleepStage) -> Int {
            guard let p = percents else { return 0 }
            switch stage {
            case .awake: return p[0]
            case .light: return p[1]
            case .deep:  return p[2]
            case .rem:   return p[3]
            }
        }
        func minutes(_ stage: SleepStage) -> Double {
            switch stage {
            case .awake: return s.awake
            case .light: return s.light
            case .deep:  return s.deep
            case .rem:   return s.rem
            }
        }
        return SleepPhasesCard(
            subtitle: String(localized: "\(SleepDurationText.format(night.timeInBed)) in bed · \(SleepDurationText.format(s.asleep)) asleep"),
            source: night.spanLabel,
            intervals: Hypnogram.displaySmoothed(intervals.sorted { $0.start < $1.start }, minDuration: 300),
            nightStart: night.onsetDate,
            palette: SleepChartStyle.resolve(sleepChartStyleRaw).stagePalette,
            stages: [SleepStage.awake, .rem, .light, .deep].map {
                SleepPhasesCard.StageLine(stage: $0, minutes: minutes($0), percent: percent($0), typicalMinutes: nil)
            },
            typicalProgress: nil,
            curves: SleepPhasesCard.Curves(heartRate: nightHR, hrv: nightHRV, skinTemp: nightSkinTemp,
                                           motion: night.motionEpochs),
            selectedStage: $selectedStage,
            showHeartRate: $showHR,
            showHRV: $showHRV,
            showSkinTemp: $showSkinTemp,
            showMotion: $showMotion)
            .onChange(of: night.session.startTs) { _ in selectedStage = nil }
            .task(id: night.session.startTs) {
                let from = night.session.effectiveStartTs
                let to = night.session.endTs
                nightHR = await repo.hrBuckets(from: night.session.startTs, to: to, bucketSeconds: 60)
                nightHRV = await repo.timelineSeries(metric: .hrv, from: from, to: to, targetPoints: 240).points
                nightSkinTemp = await repo.timelineSeries(metric: .skinTemp, from: from, to: to, targetPoints: 240).points
            }
    }
}
