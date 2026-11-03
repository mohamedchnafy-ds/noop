import SwiftUI
import StrandDesign
import StrandAnalytics

// MARK: - Top of the Sleep tab (personal fork)
//
// Everything the tab answers in two seconds, on the plain black canvas (fork chantier 7, design F): the
// title with the Alarms and Customize buttons, the night picker, then one card holding the night ring
// (a circular hypnogram, see `SleepNightDial`), the four stage totals and the bed / wake / asleep cells
// (bed and wake open the time editor), and tonight's target when the night shown is last night. A pure
// view: the Sleep tab feeds it, and the render test feeds it the same values without a repository.

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

    /// The night photo was retired (fork chantier 7): the top always sits on the plain black canvas
    /// and uses the regular text tokens.
    private var showScene: Bool { false }

    private var primary: Color { showScene ? StrandPalette.onDarkPrimary : StrandPalette.textPrimary }
    private var secondary: Color { showScene ? StrandPalette.onDarkSecondary : StrandPalette.textSecondary }

    var body: some View {
        VStack(spacing: 0) {
            titleRow
            nightPicker.padding(.top, NoopMetrics.space1)
            heroCard.padding(.top, NoopMetrics.space2)
            if let tonight = data.tonight {
                SleepTonightCard(needMinutes: tonight.needMinutes, debtMinutes: tonight.debtMinutes)
                    .padding(.top, NoopMetrics.space3)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Minutes awake inside the night, from the stage intervals (the legend's fourth entry).
    private var awakeMinutes: Double {
        data.intervals.filter { $0.stage == .awake }.reduce(0) { $0 + max(0, $1.end - $1.start) } / 60
    }

    /// The ring, the four stage totals, its one-line key, then bed / wake / asleep (fork chantier 7).
    private var heroCard: some View {
        VStack(spacing: NoopMetrics.space3) {
            SleepNightDial(onset: data.onset, wake: data.wake, intervals: data.intervals,
                           palette: data.palette, needMinutes: data.needMinutes,
                           score: data.score, scoreWord: data.scoreWord,
                           asleepMinutes: data.asleepMinutes, onScene: showScene)
            stageLegend
            Text("The further in the line sits, the deeper the sleep")
                .font(StrandFont.caption)
                .foregroundStyle(secondary)
                .multilineTextAlignment(.center)
            Rectangle().fill(StrandPalette.hairline).frame(height: NoopMetrics.hairlineWidth)
            timesRow
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(NoopPanelSurface(cornerRadius: NoopMetrics.cardRadius))
    }

    // MARK: Parts

    private var titleRow: some View {
        HStack(spacing: NoopMetrics.space2) {
            Text("Sleep")
                .font(StrandFont.screenTitle)
                .foregroundStyle(primary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: NoopMetrics.space2)
            roundButton("alarm.fill", label: "Alarms", action: actions.alarms)
            roundButton("slider.horizontal.3", label: "Customize Sleep", action: actions.customize)
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

    private var stageLegend: some View {
        // Two rows of two, deepest first, so four totals fit the card at any text size.
        VStack(spacing: 6) {
            HStack(spacing: NoopMetrics.space3) {
                legendItem(.deep, data.deepMinutes)
                legendItem(.rem, data.remMinutes)
            }
            HStack(spacing: NoopMetrics.space3) {
                legendItem(.light, data.lightMinutes)
                legendItem(.awake, awakeMinutes)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func legendItem(_ stage: SleepStage, _ minutes: Double) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(StrandPalette.sleepStageColor(stage, palette: data.palette))
                .frame(width: 8, height: 8)
            Text(stage.label)
                .font(StrandFont.footnote)
                .foregroundStyle(secondary)
            Text(SleepDurationText.format(minutes))
                .font(StrandFont.footnote.weight(.semibold))
                .foregroundStyle(primary)
                .monospacedDigit()
        }
    }

    /// Bed, wake and asleep as three cells on one fixed grid (label / figure / caption). The bed and wake
    /// cells open the time editor, as the old « Bed → Woke » row did.
    private var timesRow: some View {
        let f = AppClock.hourMinuteFormatter()
        let inBed = max(0, data.wake.timeIntervalSince(data.onset)) / 60
        return HStack(alignment: .top, spacing: 14) {
            Button(action: actions.editTimes) {
                HStack(alignment: .top, spacing: 14) {
                    timeCell(symbol: "moon.fill", tint: StrandPalette.sleepStageColor(.deep, palette: data.palette),
                             label: String(localized: "Bed"), value: f.string(from: data.onset),
                             caption: data.canEditTimes ? String(localized: "Edit") : nil, captionIsAction: true)
                    timeCell(symbol: "sun.max.fill", tint: StrandPalette.sleepStageColor(.awake, palette: data.palette),
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

/// Tonight's target: the sleep need plus the current debt estimate. Shown for last night only.
struct SleepTonightCard: View {
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
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(NoopPanelSurface(cornerRadius: NoopMetrics.cardRadius))
        .accessibilityElement(children: .combine)
    }
}
