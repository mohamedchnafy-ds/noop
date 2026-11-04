import SwiftUI
import StrandDesign
import StrandAnalytics

// MARK: - Top of the Sleep tab (personal fork)
//
// Everything the tab answers in two seconds, on the plain black canvas: the title with the Alarms button
// and the More avatar, the night picker, then ONE card for the night (fork chantier 9): a switch Ring |
// Curves with ⓘ and, on the curves, the full-screen button; the four stage totals, fixed above both views
// (a tap lights that stage alone in either view); the horseshoe ring (`SleepNightDial`) or the stage lanes
// with their curves (the Sleep tab hands in `SleepPhasesCard` in its embedded form); and bed / wake /
// asleep at the foot (bed and wake open the time editor). A pure view: the Sleep tab feeds it, and the
// render test feeds it the same values without a repository.

struct SleepTopSection: View {
    /// The two views of the night card. The ring is the default; the choice is not stored.
    enum NightView: Hashable { case ring, curves }

    struct Model {
        var nightLabel: String
        var dateLabel: String
        var canGoBack: Bool
        var canGoForward: Bool
        var onset: Date
        var wake: Date
        var intervals: [SleepInterval]
        var palette: SleepStagePalette
        var score: Double?
        var scoreWord: String?
        var asleepMinutes: Double
        var deepMinutes: Double
        var remMinutes: Double
        var lightMinutes: Double
        var needMinutes: Double?
        var timesEdited: Bool
        var canEditTimes: Bool
        /// Awake minutes and each stage's share of the night, from the same funnel as the phases chart
        /// (`SleepView.stageSharePercent`), so the ring's centre and the chart's totals cannot disagree.
        /// Without them the awake total falls back to the intervals and the share is left out.
        var awakeMinutes: Double? = nil
        var stagePercent: [SleepStage: Int] = [:]
        /// What ⓘ says about the night beyond how to read the chart: time in bed and asleep, how the
        /// stages were obtained, where they come from.
        var about: [String] = []
    }

    struct Actions {
        var alarms: () -> Void
        var previous: () -> Void
        var next: () -> Void
        var editTimes: () -> Void
    }

    let data: Model
    let actions: Actions
    /// The stage picked on the totals or the ring (the Sleep tab owns it, shared with the curves). A
    /// constant nil leaves the ring display-only.
    var selection: Binding<SleepStage?>
    /// The « Curves » view; nil shows that the night has no stage chart.
    var curves: AnyView?
    /// Whether the curves can open full screen (a night with stage data), and who opens them.
    var canShowFullScreen: Bool
    var fullScreen: Binding<Bool>

    @State private var nightView: NightView
    @State private var showsGuide = false

    init(data: Model, actions: Actions, selection: Binding<SleepStage?> = .constant(nil),
         curves: AnyView? = nil, canShowFullScreen: Bool = false, fullScreen: Binding<Bool> = .constant(false),
         initialView: NightView = .ring) {
        self.data = data
        self.actions = actions
        self.selection = selection
        self.curves = curves
        self.canShowFullScreen = canShowFullScreen
        self.fullScreen = fullScreen
        _nightView = State(initialValue: initialView)
    }

    private var primary: Color { StrandPalette.textPrimary }
    private var secondary: Color { StrandPalette.textSecondary }

    var body: some View {
        VStack(spacing: 0) {
            titleRow
            nightPicker.padding(.top, NoopMetrics.space1)
            heroCard.padding(.top, NoopMetrics.space2)
        }
        .frame(maxWidth: .infinity)
    }

    /// Minutes awake inside the night: the tab's figure, else summed from the stage intervals.
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

    /// Picks a stage (or clears the pick), with the same fade as the phases chart.
    private func select(_ stage: SleepStage?) {
        withAnimation(StrandMotion.fade) { selection.wrappedValue = stage }
    }

    /// The night card: the view switch, the four totals, the ring or the curves, then bed / wake / asleep.
    private var heroCard: some View {
        VStack(spacing: NoopMetrics.space3) {
            cardHeader
            stageTotals
            switch nightView {
            case .ring:
                SleepNightDial(onset: data.onset, wake: data.wake, intervals: data.intervals,
                               palette: data.palette, needMinutes: data.needMinutes,
                               score: data.score, scoreWord: data.scoreWord,
                               asleepMinutes: data.asleepMinutes,
                               selected: selection.wrappedValue,
                               stageMinutes: Dictionary(uniqueKeysWithValues: SleepStage.allCases.map { ($0, minutes($0)) }),
                               stagePercent: data.stagePercent,
                               onSelect: { select($0) })
            case .curves:
                if let curves {
                    curves
                } else {
                    Text("No stage data recorded for this night.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(secondary)
                        .frame(maxWidth: .infinity, minHeight: 80)
                }
            }
            Rectangle().fill(StrandPalette.hairline).frame(height: NoopMetrics.hairlineWidth)
            timesRow
        }
        .padding(NoopMetrics.cardPadding)
        .frame(maxWidth: .infinity)
        .background(NoopPanelSurface(cornerRadius: NoopMetrics.cardRadius))
    }

    // MARK: Parts

    /// Ring | Curves on the left; ⓘ, and on the curves the full-screen button, on the right.
    private var cardHeader: some View {
        HStack(spacing: NoopMetrics.space2) {
            SegmentedPillControl([NightView.ring, NightView.curves], selection: $nightView) {
                $0 == .ring ? String(localized: "Ring") : String(localized: "Curves")
            }
            .fixedSize()
            .accessibilityLabel(Text("Night view"))
            Spacer(minLength: NoopMetrics.space2)
            circleButton("info.circle", tint: secondary, label: "How to read this chart") { showsGuide = true }
                .popover(isPresented: $showsGuide, arrowEdge: .top) {
                    guide.sleepGuidePopoverAdaptation()
                }
            if nightView == .curves && canShowFullScreen {
                circleButton("arrow.up.left.and.arrow.down.right", tint: StrandPalette.accent,
                             label: "Show the chart full screen") { fullScreen.wrappedValue = true }
            }
        }
    }

    private func circleButton(_ symbol: String, tint: Color, label: LocalizedStringKey,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: NoopMetrics.compactControlSize, height: NoopMetrics.compactControlSize)
                .background(StrandPalette.surfaceRaised, in: Circle())
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Circle())
        }
        .buttonStyle(LiquidPressStyle())
        .accessibilityLabel(Text(label))
    }

    /// ⓘ: how to read the ring and the curves (the two grey lines that sat under the ring), then what is
    /// known about the night.
    private var guide: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            Text("How to read this chart")
                .font(StrandFont.subhead.weight(.semibold))
                .foregroundStyle(primary)
            Text("On the ring, the further in the line sits, the deeper the sleep.")
                .font(StrandFont.footnote)
                .foregroundStyle(secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Tap a stage to see it on its own, on the ring and on the curves.")
                .font(StrandFont.footnote)
                .foregroundStyle(secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(data.about, id: \.self) { line in
                Text(line)
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(NoopMetrics.cardInnerPadding)
        .frame(width: 280, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var titleRow: some View {
        HStack(spacing: NoopMetrics.space2) {
            Text("Sleep")
                .font(StrandFont.screenTitle)
                .foregroundStyle(primary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: NoopMetrics.space2)
            roundButton("alarm.fill", label: "Alarms", action: actions.alarms)
            // The iOS tab shell's More avatar (fork chantier 9); nothing elsewhere. « Customize Sleep »
            // sits at the foot of the tab.
            MoreAvatarButton()
        }
    }

    private func roundButton(_ symbol: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        // Liquid Glass circle on iOS 26 (fork chantier 7), the same chrome as the Today header buttons;
        // macOS keeps a flat surface circle.
        let button = Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(primary)
                .frame(width: NoopMetrics.compactControlSize, height: NoopMetrics.compactControlSize)
                .contentShape(Circle())
        }
        return button
            .nativeLiquidGlassButtonChrome(controlSize: .small) {
                button
                    .buttonStyle(LiquidPressStyle())
                    .background(StrandPalette.surfaceRaised, in: Circle())
            }
            .accessibilityLabel(Text(label))
    }

    private var nightPicker: some View {
        HStack(spacing: 0) {
            chevron("chevron.left", enabled: data.canGoBack, label: "Previous night", action: actions.previous)
                .accessibilityHint(data.canGoBack ? Text("") : Text("No earlier night stored yet. Earlier nights sync in the morning."))
            Spacer(minLength: NoopMetrics.space2)
            VStack(spacing: 1) {
                Text(data.nightLabel)
                    .font(StrandFont.caption)
                    .foregroundStyle(secondary)
                Text(data.dateLabel)
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: NoopMetrics.space2)
            chevron("chevron.right", enabled: data.canGoForward, label: "Next night", action: actions.next)
        }
    }

    private func chevron(_ symbol: String, enabled: Bool, label: LocalizedStringKey,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(secondary.opacity(enabled ? 1 : 0.35))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(LiquidPressStyle())
        .disabled(!enabled)
        .accessibilityLabel(Text(label))
    }

    /// The four stage totals, two by two, deepest first, fixed above both views.
    private var stageTotals: some View {
        let columns = [GridItem(.flexible(), spacing: NoopMetrics.space2),
                       GridItem(.flexible(), spacing: NoopMetrics.space2)]
        return LazyVGrid(columns: columns, spacing: NoopMetrics.space2) {
            ForEach([SleepStage.deep, .rem, .light, .awake], id: \.self) { stage in
                stageTotal(stage, minutes(stage))
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// One total, a button: a tap lights that stage alone (on the ring and the curves), a second tap shows
    /// them all again.
    private func stageTotal(_ stage: SleepStage, _ minutes: Double) -> some View {
        let picked = selection.wrappedValue == stage
        let dimmed = selection.wrappedValue != nil && !picked
        let tint = StrandPalette.sleepStageColor(stage, palette: data.palette)
        return Button { select(picked ? nil : stage) } label: {
            HStack(spacing: NoopMetrics.space2) {
                Circle().fill(tint).frame(width: 10, height: 10)
                Text(stage.label)
                    .font(StrandFont.subhead)
                    .foregroundStyle(secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Text(SleepDurationText.format(minutes))
                    .font(StrandFont.subhead.weight(.bold))
                    .foregroundStyle(primary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .padding(.horizontal, NoopMetrics.space3)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(StrandPalette.surfaceRaised,
                        in: RoundedRectangle(cornerRadius: NoopVisualStyle.compactRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NoopVisualStyle.compactRadius, style: .continuous)
                .strokeBorder(tint.opacity(picked ? 1 : 0), lineWidth: 1))
            .opacity(dimmed ? 0.45 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(stage.label): \(SleepDurationText.format(minutes))"))
        .accessibilityHint(Text("Highlights this stage on the sleep chart"))
        .accessibilityAddTraits(picked ? .isSelected : [])
    }

    /// Bed, wake and asleep as three cells on one fixed grid (label / figure / caption). The bed and wake
    /// cells open the time editor.
    private var timesRow: some View {
        let f = AppClock.hourMinuteFormatter()
        let inBed = max(0, data.wake.timeIntervalSince(data.onset)) / 60
        return HStack(alignment: .top, spacing: 14) {
            Button(action: actions.editTimes) {
                HStack(alignment: .top, spacing: 14) {
                    timeCell(symbol: "moon.fill", tint: StrandPalette.sleepBedtime,
                             label: String(localized: "Bed"), value: f.string(from: data.onset),
                             caption: data.canEditTimes ? String(localized: "Edit") : nil, captionIsAction: true)
                    timeCell(symbol: "sun.max.fill", tint: StrandPalette.sleepWake,
                             label: String(localized: "Wake"), value: f.string(from: data.wake),
                             caption: data.timesEdited ? String(localized: "edited") : nil, captionIsAction: false)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(LiquidPressStyle())
            .disabled(!data.canEditTimes)
            .accessibilityLabel(Text("Bed \(f.string(from: data.onset)), woke \(f.string(from: data.wake))"))
            .accessibilityHint(data.canEditTimes ? Text("Edit sleep times") : Text(""))
            timeCell(symbol: "bed.double.fill", tint: StrandPalette.restColor,
                     label: String(localized: "Asleep"), value: SleepDurationText.format(data.asleepMinutes),
                     caption: String(localized: "\(SleepDurationText.format(inBed)) in bed"), captionIsAction: false)
        }
    }

    private func timeCell(symbol: String, tint: Color, label: String, value: String, caption: String?,
                          captionIsAction: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .accessibilityHidden(true)
                Text(label)
                    .font(StrandFont.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(tint)
            .frame(height: 16)
            Text(value)
                .font(StrandFont.rounded(22, weight: .bold))
                .foregroundStyle(primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(height: 26)
            Text(caption ?? " ")
                .font(StrandFont.caption2)
                .foregroundStyle(captionIsAction ? StrandPalette.accent : secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(height: 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    /// Keep a Sleep tab ⓘ a popover at phone width (iOS); macOS popovers never adapt.
    @ViewBuilder func sleepGuidePopoverAdaptation() -> some View {
        #if os(iOS)
        presentationCompactAdaptation(.popover)
        #else
        self
        #endif
    }
}

/// Tonight's target: the sleep need plus the current debt estimate. Off the page since chantier 9: drawn
/// only when switched back on in « Customize Sleep » (`SleepRestoredBlock.tonight`), for last night.
struct SleepTonightRow: View {
    let needMinutes: Double
    let debtMinutes: Double

    private var hasDebt: Bool { debtMinutes >= SleepDebt.onTargetBandMin }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(StrandPalette.sleepStageColor(.deep))
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Tonight, aim for ≈ \(SleepDurationText.format(needMinutes + (hasDebt ? debtMinutes : 0)))")
                    .font(StrandFont.body.weight(.medium))
                    .foregroundStyle(StrandPalette.textPrimary)
                if hasDebt {
                    Text("\(SleepDurationText.format(needMinutes)) of need + \(SleepDurationText.format(debtMinutes)) of sleep debt")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Your \(SleepDurationText.format(needMinutes)) of need, no sleep debt to make up")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
