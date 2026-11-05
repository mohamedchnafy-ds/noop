import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

// MARK: - Your nights: sleep debt + hours per night (#today-hosted-cards)
//
// The Sleep tab's debt card, a standalone view so the Today tab can host it too. Both surfaces render
// THIS view from the SAME `SleepModel`, so the recency-weighted estimate can never differ between them
// (the parity contract). Nothing is recomputed here: the ledger, the 30-day series and the per-night
// stages come from `SleepModel.build` (its daily rows).
//
// Personal fork, chantier 9: the head is the average time asleep over the span shown, with the debt on
// the right (ⓘ says how it is counted). One stacked bar per night: deep at the bottom, then REM, then
// light, the bar as tall as the time asleep, against the need's dashed line; awake time stays outside the
// bar. A night without stages is one grey bar. Touching a bar puts that night in the head (date, asleep,
// each stage, awake) with « See this night », which shows it in the night card; touching it again goes
// back to the average. 14 nights or 30 days.
//
// 5 Nov.: on the Sleep tab the bars and the night card above are one selection. Touching a bar also shows
// that night in the night card (« See this night » then only scrolls up to it), and the night the card
// shows is always marked by a dot above its bar, whichever control picked it.

struct SleepDebtLedgerCard: View {
    let model: SleepModel
    /// Shows the night of a day key in the night card; nil (the Today host) hides « See this night ».
    var onOpenNight: ((String) -> Void)? = nil
    /// Whether a day has a night the night card can show; « See this night » shows only for those.
    var canOpenNight: (String) -> Bool = { _ in true }
    /// The wake day of the night the night card shows (marked on its bar); nil on the Today host.
    var shownDay: String? = nil
    /// Shows a day's night in the night card without scrolling; nil on the Today host.
    var onShowNight: ((String) -> Void)? = nil
    /// Fork chantier 12: the bars rise once per launch; false draws them at once (Today host, renders).
    var animated: Bool = false

    var body: some View {
        SleepNightsCard(data: SleepNightsData(ledger: model.sleepDebtLedger, month: model.trendPoints,
                                              splits: model.nightStageSplits),
                        onOpenNight: onOpenNight, canOpenNight: canOpenNight,
                        shownDay: shownDay, onShowNight: onShowNight, animated: animated)
    }
}

/// What the card draws, built from the ledger, the 30-day series and the daily stage minutes, without new
/// arithmetic beyond lining nights up by day.
struct SleepNightsData {
    struct Night: Equatable {
        let day: String
        let minutes: Double
    }

    /// One night's stages, in minutes, as the daily row stores them. Awake is derived from the stored
    /// efficiency (asleep ÷ in bed) when there is one, else nil.
    struct Split: Equatable {
        let deep: Double
        let rem: Double
        let light: Double
        let awake: Double?

        var asleep: Double { deep + rem + light }
    }

    var debtMinutes: Double
    var isDebt: Bool
    var needMinutes: Double
    /// How far the latest counted night fell short of the need, when it did.
    var lastShortfallMinutes: Double?
    var recent: [Night]
    var month: [Night]
    /// The stages of each night by day key; a night missing here is drawn as one grey bar.
    var splits: [String: Split]

    init(debtMinutes: Double, isDebt: Bool, needMinutes: Double, lastShortfallMinutes: Double?,
         recent: [Night], month: [Night], splits: [String: Split] = [:]) {
        self.debtMinutes = debtMinutes
        self.isDebt = isDebt
        self.needMinutes = needMinutes
        self.lastShortfallMinutes = lastShortfallMinutes
        self.recent = recent
        self.month = month
        self.splits = splits
    }

    init(ledger: SleepDebtLedger, month: [TrendPoint], splits: [String: Split] = [:]) {
        let last = ledger.nights.last
        self.init(debtMinutes: ledger.magnitudeMin,
                  isDebt: ledger.isDebt && ledger.magnitudeMin >= SleepDebt.onTargetBandMin,
                  needMinutes: ledger.needMin,
                  lastShortfallMinutes: last.flatMap { $0.deltaMin < 0 ? -$0.deltaMin : nil },
                  recent: ledger.nights.map { Night(day: $0.day, minutes: $0.sleptMin) },
                  month: month.map { Night(day: SleepNightsData.dayKey($0.date), minutes: $0.value * 60) },
                  splits: splits)
    }

    /// The stages of every daily row that has them (deep + REM + light above zero), by day. Awake = time
    /// in bed − asleep, time in bed being asleep ÷ efficiency (stored as a fraction or a percent, the same
    /// reading as `SleepModel.efficiencySeries`).
    static func nightStageSplits(days: [DailyMetric]) -> [String: Split] {
        var out: [String: Split] = [:]
        for d in days {
            let deep = d.deepMin ?? 0, rem = d.remMin ?? 0, light = d.lightMin ?? 0
            guard deep + rem + light > 0 else { continue }
            var awake: Double?
            if let e = d.efficiency, let total = d.totalSleepMin, total > 0 {
                let fraction = e <= 1.0 ? e : e / 100
                if fraction > 0, fraction <= 1 { awake = max(0, total / fraction - total) }
            }
            out[d.day] = Split(deep: deep, rem: rem, light: light, awake: awake)
        }
        return out
    }

    var nightCount: Int { recent.count }

    /// `n` calendar days ending on the newest night of either series, each with its minutes or nil.
    func slots(_ n: Int, from nights: [Night]) -> [(day: String, minutes: Double?)] {
        let newest = (recent.map(\.day) + month.map(\.day)).max()
        guard let newest, let end = Self.parser.date(from: newest) else { return [] }
        let byDay = Dictionary(nights.map { ($0.day, $0.minutes) }, uniquingKeysWith: { _, b in b })
        return (0..<n).reversed().map { back in
            let date = Self.utc.date(byAdding: .day, value: -back, to: end) ?? end
            let key = Self.dayKey(date)
            return (key, byDay[key])
        }
    }

    static func dayKey(_ date: Date) -> String { parser.string(from: date) }

    private static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC") ?? .current
        return c
    }()

    private static let parser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

/// One bar of « Your nights »: the night's minutes asleep (bar height) and its stages, when known.
struct SleepNightBar: Equatable {
    let day: String
    let minutes: Double?
    let split: SleepNightsData.Split?

    /// The stacked segments bottom to top (deep, REM, light, then any minutes the stages do not cover,
    /// e.g. a nap, as `nil`), summing to `minutes`. Stages that add up to more than the bar are scaled
    /// down to it. No stages: one `nil` segment, the grey bar.
    var segments: [(stage: SleepStage?, minutes: Double)] {
        guard let minutes, minutes > 0 else { return [] }
        guard let split, split.asleep > 0 else { return [(nil, minutes)] }
        let k = min(1, minutes / split.asleep)
        var out: [(stage: SleepStage?, minutes: Double)] = [
            (.deep, split.deep * k), (.rem, split.rem * k), (.light, split.light * k),
        ]
        let rest = minutes - split.asleep * k
        if rest >= 1 { out.append((nil, rest)) }
        return out
    }
}

struct SleepNightsCard: View {
    enum Span: Hashable { case nights14, days30 }

    let data: SleepNightsData
    var onOpenNight: ((String) -> Void)? = nil
    var canOpenNight: (String) -> Bool = { _ in true }
    /// The night the night card shows, marked on its bar, and who shows a touched night there.
    var shownDay: String? = nil
    var onShowNight: ((String) -> Void)? = nil
    /// Fork chantier 12: the bars rise one after the other, once per launch.
    var animated: Bool = false
    @State var range: Span = .nights14
    /// The night touched on the bars (its day key), or nil for the average.
    @State var picked: String? = nil
    @State var showsDebtInfo = false

    private var carryPercent: Int { Int((SleepDebt.debtCarryFactor * 100).rounded()) }

    var body: some View {
        NoopCard(tint: StrandPalette.restColor) {
            VStack(alignment: .leading, spacing: NoopMetrics.cardInnerSpacing) {
                HStack(spacing: NoopMetrics.space2) {
                    Text("Your nights")
                        .font(StrandFont.headline)
                        .foregroundStyle(StrandPalette.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: NoopMetrics.space2)
                    SegmentedPillControl([Span.nights14, Span.days30], selection: $range) {
                        $0 == .nights14 ? String(localized: "14 nights") : String(localized: "30 days")
                    }
                    .fixedSize()
                }
                if data.recent.isEmpty && data.month.isEmpty {
                    Text("No nights with sleep data yet. Your ledger fills in as you wear the strap to bed.")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    let n = range == .nights14 ? 14 : 30
                    let bars = data.slots(n, from: range == .nights14 ? data.recent : data.month).map {
                        SleepNightBar(day: $0.day, minutes: $0.minutes, split: data.splits[$0.day])
                    }
                    let shownPick = bars.first { $0.day == picked && ($0.minutes ?? 0) > 0 }
                    head(bars, picked: shownPick)
                    NoopFirstDraw(key: "sleep.nights.bars", armed: animated) { phase in
                        SleepNightsBars(bars: bars, needMinutes: data.needMinutes, picked: shownPick?.day,
                                        marked: shownDay, onPick: { day in
                            withAnimation(StrandMotion.fade) { picked = picked == day ? nil : day }
                            if let onShowNight, canOpenNight(day) { onShowNight(day) }
                        }, rise: phase.drawn ? 1 : 0)
                        .animation(phase.motion(.linear(duration: SleepNightsBars.riseDuration(bars.count))),
                                   value: phase.drawn)
                    }
                    .frame(height: 132)
                    dateRow(bars.map(\.day))
                    legend
                }
            }
        }
        .onChange(of: range) { _ in picked = nil }
        // A night picked above (‹ ›) moves the touched bar with it, so the head never names another night.
        .onChange(of: shownDay) { day in
            if picked != nil, let day { picked = day }
        }
    }

    // MARK: Parts

    /// The average and the debt, or the touched night with its stages.
    @ViewBuilder
    private func head(_ bars: [SleepNightBar], picked: SleepNightBar?) -> some View {
        if let picked, let minutes = picked.minutes {
            VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                HStack(alignment: .lastTextBaseline) {
                    figure(label: String(localized: "\(SleepModel.shortDayLabel(picked.day)) · asleep"),
                           value: SleepDurationText.format(minutes))
                    Spacer(minLength: NoopMetrics.space2)
                    if let split = picked.split {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text([SleepStage.deep, .rem, .light].map(\.label).joined(separator: " · "))
                                .font(StrandFont.caption)
                                .foregroundStyle(StrandPalette.textSecondary)
                            Text([split.deep, split.rem, split.light].map(SleepDurationText.format)
                                .joined(separator: " · "))
                                .font(StrandFont.subhead.weight(.semibold))
                                .foregroundStyle(StrandPalette.textPrimary)
                                .monospacedDigit()
                        }
                    }
                }
                HStack {
                    if let awake = picked.split?.awake {
                        Text("Awake \(SleepDurationText.format(awake)) (outside the bars)")
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                    Spacer(minLength: NoopMetrics.space2)
                    if let onOpenNight, canOpenNight(picked.day) {
                        Button { onOpenNight(picked.day) } label: {
                            Text("See this night ›")
                                .font(StrandFont.footnote.weight(.semibold))
                                .foregroundStyle(StrandPalette.accent)
                                .frame(minHeight: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } else {
            let values = bars.compactMap { $0.minutes }.filter { $0 > 0 }
            let mean = values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
            HStack(alignment: .lastTextBaseline) {
                figure(label: String(localized: "Average asleep"), value: mean.map(SleepDurationText.format) ?? "—")
                Spacer(minLength: NoopMetrics.space2)
                VStack(alignment: .trailing, spacing: 2) {
                    Button { showsDebtInfo = true } label: {
                        HStack(spacing: 4) {
                            Text("Sleep debt")
                            Image(systemName: "info.circle").accessibilityHidden(true)
                        }
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .frame(minHeight: 24)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("How the sleep debt is counted"))
                    .popover(isPresented: $showsDebtInfo, arrowEdge: .top) {
                        debtInfo.sleepGuidePopoverAdaptation()
                    }
                    if data.isDebt {
                        Text(approximately(data.debtMinutes))
                            .font(StrandFont.rounded(17, weight: .semibold))
                            .foregroundStyle(StrandPalette.restColor)
                    } else {
                        Text("No debt")
                            .font(StrandFont.rounded(17, weight: .semibold))
                            .foregroundStyle(StrandPalette.textPrimary)
                    }
                }
            }
        }
    }

    private func figure(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
            Text(value)
                .font(StrandFont.rounded(26, weight: .bold))
                .foregroundStyle(StrandPalette.textPrimary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    /// ⓘ beside the debt: how it is counted (the sentence that used to sit under the headline).
    private var debtInfo: some View {
        Group {
            if data.isDebt, let short = data.lastShortfallMinutes {
                Text("You were \(SleepDurationText.format(short)) short of \(SleepDurationText.format(data.needMinutes)) on the last night. \(carryPercent)% of a shortfall carries over to the next night: that is your debt.")
            } else if data.isDebt {
                Text("\(carryPercent)% of a shortfall carries over to the next night. Sleeping your need plus the debt clears it.")
            } else {
                Text("Your recent nights covered your \(SleepDurationText.format(data.needMinutes)) of need.")
            }
        }
        .font(StrandFont.footnote)
        .foregroundStyle(StrandPalette.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(NoopMetrics.cardInnerPadding)
        .frame(width: 280, alignment: .leading)
    }

    /// "≈ 2h 23m": the debt is an estimate, and says so.
    private func approximately(_ minutes: Double) -> String {
        String(localized: "≈ \(SleepDurationText.format(minutes))")
    }

    private func dateRow(_ days: [String]) -> some View {
        HStack {
            Text(days.first.map(SleepModel.shortDayLabel) ?? "")
            Spacer()
            Text(days.isEmpty ? "" : SleepModel.shortDayLabel(days[days.count / 2]))
            Spacer()
            Text(days.last.map(SleepModel.shortDayLabel) ?? "")
        }
        .font(StrandFont.caption)
        .foregroundStyle(StrandPalette.textSecondary)
        .accessibilityHidden(true)
    }

    private var legend: some View {
        HStack(spacing: NoopMetrics.space3) {
            ForEach([SleepStage.deep, .rem, .light], id: \.self) { stage in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(StrandPalette.sleepStageColor(stage))
                        .frame(width: 10, height: 10)
                    Text(stage.label)
                }
            }
        }
        .font(StrandFont.caption)
        .foregroundStyle(StrandPalette.textSecondary)
        .accessibilityHidden(true)
    }
}

/// The bars: one slot per day, the minutes asleep as a stacked bar (deep, REM, light from the bottom),
/// the need as a dashed line, an empty day as a dot. Each night with a bar is a button.
struct SleepNightsBars: View, Animatable {
    let bars: [SleepNightBar]
    let needMinutes: Double
    var picked: String? = nil
    /// The night shown in the night card above, marked by a dot over its bar; nil marks nothing.
    var marked: String? = nil
    /// The colour of a bar without stages: grey on « Your nights »; the plain hours trend passes its own.
    var plainColor: Color? = nil
    var onPick: ((String) -> Void)? = nil
    /// Fork chantier 12: 0…1, run linearly; each bar rises in 0.55 s, 0.045 s after the one before it.
    var rise: Double = 1

    var animatableData: Double {
        get { rise }
        set { rise = newValue }
    }

    static let barRise: Double = 0.55
    static let barStagger: Double = 0.045

    /// How long the whole row takes to rise, for the linear animation of `rise`.
    static func riseDuration(_ count: Int) -> Double {
        barRise + barStagger * Double(max(0, count - 1))
    }

    /// The height share of bar `index` at the current `rise`, with a strong ease-out of its own.
    private func grown(_ index: Int) -> CGFloat {
        guard rise < 1 else { return 1 }
        let total = Self.riseDuration(bars.count)
        let local = min(1, max(0, (rise * total - Self.barStagger * Double(index)) / Self.barRise))
        return CGFloat(1 - pow(1 - local, 4))
    }

    var body: some View {
        Canvas { ctx, size in
            guard !bars.isEmpty else { return }
            let top: CGFloat = 18
            let maxMin = max(needMinutes * 1.12, (bars.compactMap { $0.minutes }.max() ?? 0) * 1.08, 60)
            func y(_ m: Double) -> CGFloat { size.height - CGFloat(m / maxMin) * (size.height - top) }
            let slot = size.width / CGFloat(bars.count)
            let barW = max(3, slot - (bars.count > 20 ? 3 : 6))

            var base = Path()
            base.move(to: CGPoint(x: 0, y: size.height - 0.5))
            base.addLine(to: CGPoint(x: size.width, y: size.height - 0.5))
            ctx.stroke(base, with: .color(StrandPalette.hairline), lineWidth: 1)

            for (i, bar) in bars.enumerated() {
                let cx = slot * (CGFloat(i) + 0.5)
                let segments = bar.segments
                guard let value = bar.minutes, value > 0, !segments.isEmpty else {
                    ctx.fill(Path(ellipseIn: CGRect(x: cx - 2, y: size.height - 6, width: 4, height: 4)),
                             with: .color(StrandPalette.hairlineStrong))
                    continue
                }
                let share = grown(i)
                let barTop = size.height - (size.height - y(value)) * share
                let rect = CGRect(x: cx - barW / 2, y: barTop, width: barW, height: size.height - barTop)
                ctx.drawLayer { layer in
                    layer.opacity = picked == nil || picked == bar.day ? 1 : 0.35
                    layer.clip(to: Path(roundedRect: rect, cornerRadius: min(4, barW / 2)))
                    var bottom = size.height
                    for segment in segments {
                        let h = CGFloat(segment.minutes / maxMin) * (size.height - top) * share
                        let color = segment.stage.map { StrandPalette.sleepStageColor($0) }
                            ?? plainColor ?? StrandPalette.textTertiary
                        layer.fill(Path(CGRect(x: rect.minX, y: bottom - h, width: barW, height: h)),
                                   with: .color(color))
                        bottom -= h
                    }
                }
                if bar.day == marked {
                    ctx.fill(Path(ellipseIn: CGRect(x: cx - 3, y: rect.minY - 10, width: 6, height: 6)),
                             with: .color(StrandPalette.textPrimary))
                }
            }

            let needY = y(needMinutes)
            var needLine = Path()
            needLine.move(to: CGPoint(x: 0, y: needY))
            needLine.addLine(to: CGPoint(x: size.width, y: needY))
            ctx.stroke(needLine, with: .color(StrandPalette.textSecondary.opacity(0.8)),
                       style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            let needText = ctx.resolve(Text("need \(SleepDurationText.format(needMinutes))")
                .font(StrandFont.caption2).foregroundColor(StrandPalette.textSecondary))
            ctx.draw(needText, at: CGPoint(x: size.width, y: needY - 3), anchor: .bottomTrailing)
        }
        .overlay {
            HStack(spacing: 0) {
                ForEach(bars, id: \.day) { bar in
                    Button { onPick?(bar.day) } label: {
                        Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(onPick == nil || (bar.minutes ?? 0) <= 0)
                    .accessibilityLabel(Text(barLabel(bar)))
                    .accessibilityAddTraits(picked == bar.day ? .isSelected : [])
                    .accessibilityHidden((bar.minutes ?? 0) <= 0)
                }
            }
        }
    }

    private func barLabel(_ bar: SleepNightBar) -> String {
        String(localized: "\(SleepModel.shortDayLabel(bar.day)), \(SleepDurationText.format(bar.minutes ?? 0)) asleep")
    }
}
