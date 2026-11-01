import SwiftUI
import StrandDesign
import StrandAnalytics

// MARK: - Top of the Sleep tab (personal fork)
//
// Everything the tab answers in two seconds, over the night scene: the title with the Alarms and
// Customize buttons, the night picker, the night dial (score, time asleep, bed and wake times, stages,
// the sleep need), the stage totals, the bed → wake row that opens the time editor, and tonight's target
// when the night shown is last night. A pure view: the Sleep tab feeds it, and the render test feeds it
// the same values without a repository.

struct SleepTopSection: View {
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
        /// Tonight's target, only for last night: the need and the debt to add to it.
        var tonight: (needMinutes: Double, debtMinutes: Double)?
    }

    struct Actions {
        var alarms: () -> Void
        var customize: () -> Void
        var previous: () -> Void
        var next: () -> Void
        var editTimes: () -> Void
    }

    let data: Model
    let actions: Actions

    /// #1319: the night scene honours the Settings "Day-cycle background" toggle; off, the top sits on
    /// the plain canvas and the text switches to the regular tokens.
    @AppStorage(SceneBackgroundPrefs.enabledKey) private var showScene = true

    private var primary: Color { showScene ? StrandPalette.onDarkPrimary : StrandPalette.textPrimary }
    private var secondary: Color { showScene ? StrandPalette.onDarkSecondary : StrandPalette.textSecondary }

    var body: some View {
        VStack(spacing: 0) {
            titleRow
            nightPicker.padding(.top, NoopMetrics.space1)
            SleepNightDial(onset: data.onset, wake: data.wake, intervals: data.intervals,
                           palette: data.palette, needMinutes: data.needMinutes,
                           score: data.score, scoreWord: data.scoreWord,
                           asleepMinutes: data.asleepMinutes, onScene: showScene)
                .padding(.top, NoopMetrics.space1)
            stageLegend.padding(.top, NoopMetrics.space2)
            if let need = data.needMinutes {
                needLegend(need).padding(.top, NoopMetrics.space3)
            }
            timesRow.padding(.top, NoopMetrics.space3)
            if let tonight = data.tonight {
                SleepTonightCard(needMinutes: tonight.needMinutes, debtMinutes: tonight.debtMinutes)
                    .padding(.top, NoopMetrics.space3)
            }
        }
        .frame(maxWidth: .infinity)
        .background(alignment: .top) {
            // The night scene sits behind this section only and scrolls away with it: it bleeds past the
            // screen gutters and up under the status bar, and its own bottom fade meets the canvas.
            if showScene {
                GeometryReader { geo in
                    SleepPerformanceNightScene()
                        .frame(width: geo.size.width + 2 * Self.sceneBleed,
                               height: geo.size.height + Self.sceneRise)
                        .offset(x: -Self.sceneBleed, y: -Self.sceneRise)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }

    /// How far the scene reaches past the screen gutters, and up above the section.
    static let sceneBleed: CGFloat = NoopMetrics.screenHPadding
    static let sceneRise: CGFloat = 220

    // MARK: Parts

    private var titleRow: some View {
        HStack(spacing: NoopMetrics.space2) {
            Text("Sleep")
                .font(StrandFont.rounded(30, weight: .bold))
                .foregroundStyle(primary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: NoopMetrics.space2)
            roundButton("alarm.fill", label: "Alarms", action: actions.alarms)
            roundButton("slider.horizontal.3", label: "Customize Sleep", action: actions.customize)
        }
    }

    private func roundButton(_ symbol: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(primary)
                .frame(width: 44, height: 44)
                .background(StrandPalette.heroFill, in: Circle())
                .overlay(Circle().strokeBorder(StrandPalette.heroBorder, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(LiquidPressStyle())
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
                .foregroundStyle(primary.opacity(enabled ? 1 : 0.35))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(LiquidPressStyle())
        .disabled(!enabled)
        .accessibilityLabel(Text(label))
    }

    private var stageLegend: some View {
        HStack(spacing: NoopMetrics.space3) {
            legendItem(.deep, data.deepMinutes)
            legendItem(.rem, data.remMinutes)
            legendItem(.light, data.lightMinutes)
        }
        .accessibilityElement(children: .combine)
    }

    private func legendItem(_ stage: SleepStage, _ minutes: Double) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(StrandPalette.sleepStageColor(stage, palette: data.palette))
                .frame(width: 9, height: 9)
            Text(stage.label)
                .font(StrandFont.footnote)
                .foregroundStyle(secondary)
            Text(SleepDurationText.format(minutes))
                .font(StrandFont.footnote.weight(.semibold))
                .foregroundStyle(primary)
                .monospacedDigit()
        }
    }

    private func needLegend(_ need: Double) -> some View {
        HStack(spacing: NoopMetrics.space2) {
            DashedLegendSwatch(color: secondary)
            Text("Your \(SleepDurationText.format(need)) of need before waking at \(AppClock.hourMinuteFormatter().string(from: data.wake))")
                .font(StrandFont.footnote)
                .foregroundStyle(secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
    }

    private var timesRow: some View {
        let f = AppClock.hourMinuteFormatter()
        return Button(action: actions.editTimes) {
            HStack(spacing: NoopMetrics.space2) {
                Image(systemName: "moon.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(secondary)
                Text("Bed \(f.string(from: data.onset))")
                Image(systemName: "arrow.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(secondary)
                Image(systemName: "sun.max.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(secondary)
                Text("Woke \(f.string(from: data.wake))")
                if data.canEditTimes {
                    Image(systemName: data.timesEdited ? "pencil.circle.fill" : "pencil")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(secondary)
                }
            }
            .font(StrandFont.subhead.weight(.semibold))
            .foregroundStyle(primary)
            .monospacedDigit()
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(StrandPalette.heroFill, in: RoundedRectangle(cornerRadius: NoopVisualStyle.compactRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NoopVisualStyle.compactRadius, style: .continuous)
                .strokeBorder(StrandPalette.heroBorder, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(LiquidPressStyle())
        .disabled(!data.canEditTimes)
        .accessibilityLabel(Text("Bed \(f.string(from: data.onset)), woke \(f.string(from: data.wake))"))
        .accessibilityHint(data.canEditTimes ? Text("Edit sleep times") : Text(""))
    }
}

/// A short dashed line: the legend key for the dial's need arc.
private struct DashedLegendSwatch: View {
    let color: Color
    var body: some View {
        Canvas { ctx, size in
            var p = Path()
            p.move(to: CGPoint(x: 0, y: size.height / 2))
            p.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [4, 4]))
        }
        .frame(width: 20, height: 4)
        .accessibilityHidden(true)
    }
}

/// Tonight's target: the sleep need plus the current debt estimate. Shown for last night only.
struct SleepTonightCard: View {
    let needMinutes: Double
    let debtMinutes: Double

    private var hasDebt: Bool { debtMinutes >= SleepDebt.onTargetBandMin }

    var body: some View {
        NoopCard(padding: NoopMetrics.space3, tint: StrandPalette.restColor) {
            HStack(spacing: NoopMetrics.space3) {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(StrandPalette.restBright)
                    .frame(width: 38, height: 38)
                    .background(StrandPalette.restBright.opacity(0.14), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tonight, aim for ≈ \(SleepDurationText.format(needMinutes + (hasDebt ? debtMinutes : 0)))")
                        .font(StrandFont.headline)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text(hasDebt
                         ? String(localized: "\(SleepDurationText.format(needMinutes)) of need + \(SleepDurationText.format(debtMinutes)) of sleep debt")
                         : String(localized: "Your \(SleepDurationText.format(needMinutes)) of need, no sleep debt to make up"))
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
