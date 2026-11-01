import SwiftUI
import StrandDesign
import WhoopStore

// MARK: - Phases card (personal fork)
//
// The night in one card: the stage lanes with the curves the user switched on (heart rate by default,
// rMSSD, skin temperature, movement), each with its own scale, the four stage totals (tap one to light it
// up on the lanes), the comparison with the usual night once there are enough nights, any honest caveat
// about the staging, and the footer actions (why this sleep, add a nap). A button in the header opens the
// same chart full screen. A pure view: the Sleep tab feeds it, the render test feeds it fixed values.

/// Which curves ride over the stage lanes. Persisted per curve (display-only preferences).
enum SleepCurvePrefs {
    static let hrKey = SleepHROverlay.enabledKey
    static let hrvKey = "sleep.curve.hrv"
    static let skinTempKey = "sleep.curve.skinTemp"
    static let motionKey = "sleep.curve.motion"
}

struct SleepPhasesCard: View {
    struct StageLine {
        let stage: SleepStage
        let minutes: Double
        let percent: Int
        /// The usual minutes for this stage, once there are enough nights; nil before.
        let typicalMinutes: Double?
    }

    struct Curves {
        var heartRate: [HRBucket] = []
        var hrv: [TrendPoint] = []
        var skinTemp: [TrendPoint] = []
        var motion: [Double] = []
    }

    let subtitle: String
    let source: String
    let intervals: [SleepInterval]
    let nightStart: Date
    let palette: SleepStagePalette
    let stages: [StageLine]
    /// Nights counted toward the usual night, and how many it needs; nil once the comparison shows.
    let typicalProgress: (count: Int, needed: Int)?
    let curves: Curves
    @Binding var selectedStage: SleepStage?
    @Binding var showHeartRate: Bool
    @Binding var showHRV: Bool
    @Binding var showSkinTemp: Bool
    @Binding var showMotion: Bool
    var notes: AnyView? = nil
    var whyButton: AnyView? = nil
    var addNap: (() -> Void)? = nil
    /// A reading shown on the chart before any touch, seconds from `nightStart` (the render test sets one).
    var initialReading: TimeInterval? = nil

    @State private var showsFullScreen = false

    var body: some View {
        NoopCard(tint: StrandPalette.restColor) {
            VStack(alignment: .leading, spacing: NoopMetrics.cardInnerSpacing) {
                header
                chips
                if intervals.count >= 2 {
                    chart(laneHeight: 56, stripHeight: 84, bleed: NoopMetrics.cardPadding)
                } else {
                    Text("No stage data recorded for this night.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 80)
                }
                stageGrid
                if let typicalProgress {
                    ProgressNote(text: String(localized: "Comparison with your usual night from \(typicalProgress.needed) nights"),
                                 done: typicalProgress.count, total: typicalProgress.needed)
                } else {
                    Text("Tap a stage to light it up on the chart.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
                if let notes { notes }
                if whyButton != nil || addNap != nil {
                    Divider().overlay(StrandPalette.hairline)
                    footer
                }
            }
        }
        .sleepPhasesFullScreen(isPresented: $showsFullScreen) { fullScreenView }
    }

    // MARK: Parts

    private func chart(laneHeight: CGFloat, stripHeight: CGFloat, bleed: CGFloat) -> SleepPhasesChart {
        SleepPhasesChart(intervals: intervals, nightStart: nightStart, palette: palette,
                         highlighted: selectedStage,
                         heartRate: showHeartRate ? curves.heartRate : [],
                         hrv: showHRV ? curves.hrv : [],
                         skinTemp: showSkinTemp ? curves.skinTemp : [],
                         motion: showMotion ? curves.motion : [],
                         laneHeight: laneHeight, stripHeight: stripHeight, bleed: bleed,
                         initialReading: initialReading)
    }

    /// The same chart on the whole screen: taller lanes and strips, the curve switches above it. Internal
    /// so the render test can draw it.
    var fullScreenView: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.cardInnerSpacing) {
            HStack(alignment: .top, spacing: NoopMetrics.space2) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Night stages").strandOverline()
                    Text(subtitle)
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: NoopMetrics.space2)
                Button { showsFullScreen = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(StrandPalette.textPrimary)
                        .frame(width: 44, height: 44)
                        .background(StrandPalette.surfaceRaised, in: Circle())
                        .overlay(Circle().strokeBorder(StrandPalette.hairlineStrong, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Close"))
            }
            chips
            GeometryReader { geo in
                let lane = fullScreenLaneHeight(available: geo.size.height)
                // Scrolls only when even the shortest lanes do not fit (many strips on a small screen).
                ViewThatFits(in: .vertical) {
                    chart(laneHeight: lane, stripHeight: 110, bleed: 0)
                    ScrollView { chart(laneHeight: lane, stripHeight: 110, bleed: 0) }
                }
            }
        }
        .padding(NoopMetrics.screenHPadding)
        .background(StrandPalette.surfaceBase.ignoresSafeArea())
    }

    /// Lanes as tall as the screen allows once the strips, the reading and the ranges have their room.
    private func fullScreenLaneHeight(available: CGFloat) -> CGFloat {
        var strips = 0
        if showMotion && curves.motion.count >= 2 { strips += 1 }
        let lineCurves = [showHeartRate && curves.heartRate.count >= 2, showHRV && curves.hrv.count >= 2,
                          showSkinTemp && curves.skinTemp.count >= 2].filter { $0 }.count
        let split = SleepCurveLayout.split(heartRate: showHeartRate && curves.heartRate.count >= 2,
                                           hrv: showHRV && curves.hrv.count >= 2,
                                           skinTemp: showSkinTemp && curves.skinTemp.count >= 2)
        strips += split.below.count
        let reserved = 70 + CGFloat(lineCurves) * 22 + CGFloat(strips) * 124 + 60
        return max(56, min(140, (available - reserved) / 4))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: NoopMetrics.space2) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Night stages").strandOverline()
                Text(subtitle)
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: NoopMetrics.space2)
            VStack(alignment: .trailing, spacing: 6) {
                SourceBadge("\(source)", tint: StrandPalette.restColor)
                if intervals.count >= 2 {
                    Button { showsFullScreen = true } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(StrandPalette.restBright)
                            .frame(width: 34, height: 34)
                            .background(StrandPalette.surfaceInset, in: Circle())
                            .overlay(Circle().strokeBorder(StrandPalette.hairlineStrong, lineWidth: 1))
                            .padding(5)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Show the chart full screen"))
                    .padding(-5)
                }
            }
        }
    }

    private var chips: some View {
        HStack(spacing: 6) {
            SleepCurveChip(title: String(localized: "HR"), tint: StrandPalette.liquidHeart, isOn: $showHeartRate,
                           enabled: curves.heartRate.count >= 2)
            SleepCurveChip(title: String(localized: "HRV"), tint: StrandPalette.accent, isOn: $showHRV,
                           enabled: curves.hrv.count >= 2)
            SleepCurveChip(title: String(localized: "Skin temp."), tint: StrandPalette.signalYellow, isOn: $showSkinTemp,
                           enabled: curves.skinTemp.count >= 2)
            SleepCurveChip(title: String(localized: "Movement"), tint: StrandPalette.restColor, isOn: $showMotion,
                           enabled: curves.motion.count >= 2)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Curves shown on the stages"))
    }

    private var stageGrid: some View {
        HStack(alignment: .top, spacing: NoopMetrics.space2) {
            ForEach(stages, id: \.stage) { line in
                stageCell(line)
            }
        }
    }

    private func stageCell(_ line: StageLine) -> some View {
        let selected = selectedStage == line.stage
        let dimmed = selectedStage != nil && !selected
        return Button {
            withAnimation(StrandMotion.fade) { selectedStage = selected ? nil : line.stage }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(StrandPalette.sleepStageColor(line.stage, palette: palette))
                        .frame(width: 9, height: 9)
                    Text(line.stage.label)
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                Text(SleepDurationText.format(line.minutes))
                    .font(StrandFont.number(17))
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(line.typicalMinutes.map { String(localized: "\(line.percent)% · usual \(SleepDurationText.format($0))") }
                     ?? String(localized: "\(line.percent)%"))
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .lineLimit(2)
            }
            .monospacedDigit()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
            .background(StrandPalette.sleepStageColor(line.stage, palette: palette).opacity(selected ? 0.14 : 0),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .opacity(dimmed ? 0.55 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(line.stage.label): \(SleepDurationText.format(line.minutes)), \(line.percent) percent of the night"))
        .accessibilityHint(Text("Highlights this stage on the sleep chart"))
    }

    private var footer: some View {
        HStack {
            if let whyButton { whyButton }
            Spacer(minLength: NoopMetrics.space2)
            if let addNap {
                Button(action: addNap) {
                    Label("Add a nap", systemImage: "plus.circle")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.restBright)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(LiquidPressStyle())
            }
        }
    }
}

extension View {
    /// The chart's full-screen view: a cover on iOS, a sheet on macOS where covers do not exist.
    @ViewBuilder
    func sleepPhasesFullScreen<Content: View>(isPresented: Binding<Bool>,
                                              @ViewBuilder content: @escaping () -> Content) -> some View {
        #if os(iOS)
        fullScreenCover(isPresented: isPresented, content: content)
        #else
        sheet(isPresented: isPresented) { content().frame(minWidth: 640, minHeight: 760) }
        #endif
    }
}

/// One switch above the stage lanes: a capsule with the curve's colour when it is on.
struct SleepCurveChip: View {
    let title: String
    let tint: Color
    @Binding var isOn: Bool
    var enabled: Bool = true

    var body: some View {
        Button {
            withAnimation(StrandMotion.fade) { isOn.toggle() }
        } label: {
            HStack(spacing: 5) {
                Circle().fill(isOn && enabled ? tint : StrandPalette.hairlineStrong).frame(width: 7, height: 7)
                Text(title)
                    .font(StrandFont.caption.weight(.semibold))
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(isOn && enabled ? tint : StrandPalette.textSecondary)
            .padding(.horizontal, 9)
            .frame(height: 30)
            .overlay(Capsule().strokeBorder(isOn && enabled ? tint : StrandPalette.hairlineStrong, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(isOn && enabled ? String(localized: "On") : String(localized: "Off")))
        .accessibilityHint(enabled ? Text("") : Text("No data for this night"))
    }
}

/// "Comparison … from 5 nights" with a row of dots for the nights already counted.
struct ProgressNote: View {
    let text: String
    let done: Int
    let total: Int

    var body: some View {
        HStack(spacing: NoopMetrics.space2) {
            HStack(spacing: 4) {
                ForEach(0..<max(1, total), id: \.self) { i in
                    Circle()
                        .fill(i < done ? StrandPalette.restBright : StrandPalette.hairlineStrong)
                        .frame(width: 7, height: 7)
                }
            }
            Text(text)
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(text). \(done) of \(total)"))
    }
}
