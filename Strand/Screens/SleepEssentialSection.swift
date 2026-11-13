import SwiftUI
import StrandDesign
import StrandAnalytics

// MARK: - Sleep, essential mode (personal fork, chantier 20)
//
// The night's horseshoe in the middle (it traces itself from bedtime to wake, a white dot leading), the
// night's breathing going round it, then the four stages and tonight's aim. Every figure is the night
// card's own (`SleepTopSection.Model`), so the two layouts cannot disagree.

struct SleepEssentialSection: View {
    let data: SleepTopSection.Model
    /// Tonight's sleep need and the debt to make up (Sleep's ledger), nil need when there is none.
    var needMinutes: Double?
    var debtMinutes: Double
    /// The night's breaths per minute, nil when none was measured.
    var breathsPerMinute: Double?

    private static let dialDiameter: CGFloat = 220
    private static let traceDiameter: CGFloat = 322
    private static let traceRadius: CGFloat = 150

    private var awakeMinutes: Double {
        data.awakeMinutes
            ?? data.intervals.filter { $0.stage == .awake }.reduce(0) { $0 + max(0, $1.end - $1.start) } / 60
    }

    private func minutes(_ stage: SleepStage) -> Double {
        switch stage {
        case .awake: return awakeMinutes
        case .rem: return data.remMinutes
        case .light: return data.lightMinutes
        case .deep: return data.deepMinutes
        }
    }

    /// The stages as the night card lists them: deepest first.
    let stages: [SleepStage] = [.deep, .rem, .light, .awake]

    private var caption: String {
        [data.nightLabel, data.dateLabel].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var body: some View {
        VStack(spacing: 0) {
            EssentialHeader(caption: caption)
            Spacer(minLength: NoopMetrics.space3)
            ZStack {
                EssentialBreathTrace(diameter: Self.traceDiameter, radius: Self.traceRadius,
                                     breathsPerMinute: breathsPerMinute)
                NoopFirstDraw(key: "essential.sleep.dial", armed: true) { phase in
                    SleepNightDial(onset: data.onset, wake: data.wake, intervals: data.intervals,
                                   palette: data.palette, needMinutes: data.needMinutes,
                                   score: data.score, scoreWord: data.scoreWord,
                                   asleepMinutes: data.asleepMinutes,
                                   diameter: Self.dialDiameter,
                                   stageMinutes: Dictionary(uniqueKeysWithValues: SleepStage.allCases.map {
                                       ($0, minutes($0))
                                   }),
                                   stagePercent: data.stagePercent,
                                   trace: phase.drawn ? 1 : 0,
                                   armed: true)
                        .animation(phase.motion(SleepNightDialMotion.trace), value: phase.drawn)
                }
            }
            .frame(width: Self.traceDiameter, height: Self.traceDiameter)
            HStack(spacing: 4) {
                ForEach(stages, id: \.self) { stage in
                    EssentialFigure(label: stage.label,
                                    tint: StrandPalette.sleepStageColor(stage, palette: data.palette),
                                    value: SleepDurationText.format(minutes(stage)))
                }
            }
            .padding(.top, NoopMetrics.space2)
            VStack(spacing: 4) {
                if let need = needMinutes, need > 0 {
                    let aim = need + (debtMinutes >= SleepDebt.onTargetBandMin ? debtMinutes : 0)
                    Text("Tonight, aim for ≈ \(SleepDurationText.format(aim))")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
                if let rate = breathsPerMinute, rate > 0 {
                    Text("\(rate.formatted(.number.precision(.fractionLength(1)).locale(AppLanguage.activeLocale))) breaths/min")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.metricCyan)
                }
            }
            .multilineTextAlignment(.center)
            .padding(.top, NoopMetrics.space3)
            Spacer(minLength: NoopMetrics.space3)
        }
        .frame(maxWidth: .infinity, minHeight: 600)
    }
}
