//  TodayStressCard.swift
//  NOOP · Today's hour-by-hour stress card (personal fork, chantier 9).
//
//  Its own card, right under the heart-rate card: the shared 0–3 stress proxy (`DaytimeStress`, one point
//  every 30 minutes over a one-hour window) across the waking hours 06:00–22:00, on three bands (Calm,
//  Moderate, High), the hours spent moving in grey, the level of the latest hour large, then High · Avg. ·
//  Peak and « How it's calculated ». It replaces the Liquid Today's old « Stress · Calibrating » row.

import SwiftUI
import StrandDesign
import StrandAnalytics

/// What the stress card draws, resolved once per load (never in body).
struct TodayStressModel: Equatable {
    struct Point: Equatable {
        /// 0…1 across 06:00–22:00.
        var x: Double
        /// 0–3.
        var level: Double
        /// Points sharing a run are joined; a new run starts after an unscored stretch.
        var run: Int
    }

    var points: [Point] = []
    /// Stretches left unscored because the wearer was moving, as 0…1 ranges across the plot.
    var moving: [ClosedRange<Double>] = []
    /// The latest scored point: its level and the unix start of its window.
    var latestLevel: Double?
    var latestStartTs: Int?
    /// True when that window ended within the last half hour of today (« this hour »).
    var latestIsNow = false
    /// Minutes in the High band, the day's mean level and the start of its peak hour.
    var highMinutes = 0
    var mean: Double?
    var peakStartTs: Int?
    /// Local midnight of the day shown (unix seconds), for the axis.
    var dayStart = 0

    var hasData: Bool { !points.isEmpty }
}

/// Pure builders and formatting for the stress card, kept apart from the view so tests can pin them.
enum TodayStressLogic {
    /// The plot spans the waking hours `DaytimeStress` scores.
    static let startHour = DaytimeStress.wakingStartHour
    static let endHour = DaytimeStress.wakingEndHour

    static func model(result: DaytimeStress.Result, dayStart: Int, now: Int, isToday: Bool) -> TodayStressModel {
        let from = dayStart + startHour * 3600
        let span = Double(max(1, (endHour - startHour) * 3600))
        let half = DaytimeStress.bucketSeconds / 2
        let step = DaytimeStress.timelineStepSeconds
        func fx(_ ts: Int) -> Double { min(1, max(0, Double(ts - from) / span)) }

        let timeline = result.timeline.sorted { $0.startTs < $1.startTs }
        var points: [TodayStressModel.Point] = []
        var run = 0
        var lastScoredTs: Int?
        for p in timeline {
            guard let level = p.level else { continue }
            if let last = lastScoredTs, p.startTs - last > step { run += 1 }
            points.append(.init(x: fx(p.startTs + half), level: min(3, max(0, level)), run: run))
            lastScoredTs = p.startTs
        }

        var moving: [ClosedRange<Double>] = []
        for p in timeline where p.maskedForActivity && p.level == nil {
            let a = fx(p.startTs + half - step / 2), b = fx(p.startTs + half + step / 2)
            guard b > a else { continue }
            if let last = moving.last, a <= last.upperBound {
                moving[moving.count - 1] = last.lowerBound...max(last.upperBound, b)
            } else {
                moving.append(a...b)
            }
        }

        let latest = timeline.last { $0.level != nil }
        let latestEnd = latest.map { $0.startTs + DaytimeStress.bucketSeconds }
        return TodayStressModel(
            points: points, moving: moving,
            latestLevel: latest?.level.map { min(3, max(0, $0)) },
            latestStartTs: latest?.startTs,
            latestIsNow: isToday && latestEnd.map { now - $0 <= step } == true,
            highMinutes: result.highStressMinutes,
            mean: result.dayMean,
            peakStartTs: result.peak?.startTs,
            dayStart: dayStart)
    }

    /// The band a level reads in, on the same cut points as the Stress screen (`StressBand`).
    static func stressBand(_ level: Double) -> StressBand { StressBand(score: level) }

    static func bandName(_ band: StressBand) -> String {
        switch band {
        case .low: return String(localized: "Calm")
        case .medium: return String(localized: "Moderate")
        case .high: return String(localized: "High")
        }
    }

    static func bandColor(_ band: StressBand) -> Color {
        switch band {
        case .low: return StrandPalette.stressCalm
        case .medium: return StrandPalette.stressModerate
        case .high: return StrandPalette.stressHigh
        }
    }

    /// A level to one decimal in the app's locale (« 1,4 » in French), clamped to 0–3.
    static func levelText(_ level: Double) -> String {
        UnitFormatter.decimal(min(3, max(0, level)), places: 1)
    }

    /// Minutes in the High band: « 45 min » under an hour, « 1h 20m » from there.
    static func minutesText(_ minutes: Int) -> String {
        minutes < 60 ? String(localized: "\(minutes) min") : SleepDurationText.format(Double(minutes))
    }

    static func stressClock(_ ts: Int) -> String {
        AppClock.hourMinuteFormatter().string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
    }

    /// The axis: 06:00, 10:00, 14:00, 18:00, 22:00 of the day shown.
    static func axisLabels(dayStart: Int) -> [String] {
        stride(from: startHour, through: endHour, by: 4).map { stressClock(dayStart + $0 * 3600) }
    }
}

/// The card. Static: it redraws when its model changes, never on a clock.
struct TodayStressCard: View {
    var model: TodayStressModel
    /// The day is today (the subtitle under the level says « this hour » only then).
    var isToday: Bool = true
    /// Opens the Stress screen from the title; nil keeps the title inert (renders, macOS previews).
    var titleRoute: TabRoute? = .stress

    @State private var showsMethod = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            head
            if let level = model.latestLevel {
                levelLine(level)
                chart
                    .frame(height: 96)
                axis
                legend
                stats
            } else {
                Text("No stress reading for this day yet: an hour needs enough heart rate while you are still.")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 16)
            }
            Button { showsMethod = true } label: {
                HStack(spacing: 4) {
                    Text("How it's calculated")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .accessibilityHidden(true)
                }
                .font(StrandFont.subhead.weight(.semibold))
                .foregroundStyle(StrandPalette.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NoopPanelSurface(cornerRadius: NoopMetrics.cardRadius))
        .sheet(isPresented: $showsMethod) { TodayStressMethodSheet() }
    }

    private var title: some View {
        HStack(spacing: 6) {
            Text("Stress")
                .font(StrandFont.headline.weight(.semibold))
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(StrandPalette.textSecondary)
                .accessibilityHidden(true)
        }
        .foregroundStyle(StrandPalette.stressTitle)
    }

    private var head: some View {
        HStack(alignment: .firstTextBaseline) {
            if let titleRoute {
                NavigationLink(value: titleRoute) { title }
                    .buttonStyle(.plain)
            } else {
                title
            }
            Spacer(minLength: NoopMetrics.space2)
            let labels = TodayStressLogic.axisLabels(dayStart: model.dayStart)
            if let first = labels.first, let last = labels.last {
                Text("from \(first) to \(last)")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
        }
    }

    private func levelLine(_ level: Double) -> some View {
        let band = TodayStressLogic.stressBand(level)
        let value = TodayStressLogic.levelText(level)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(TodayStressLogic.bandName(band))
                .font(StrandFont.rounded(32))
                .foregroundStyle(TodayStressLogic.bandColor(band))
            Group {
                if model.latestIsNow || model.latestStartTs == nil {
                    Text("\(value) of 3 · this hour")
                } else if let ts = model.latestStartTs {
                    Text("\(value) of 3 · at \(TodayStressLogic.stressClock(ts))")
                }
            }
            .font(StrandFont.subhead.weight(.medium))
            .foregroundStyle(StrandPalette.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
        .accessibilityElement(children: .combine)
    }

    private var chart: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let bandH = h / 3
            // Bands top to bottom: High (2–3), Moderate (1–2), Calm (0–1).
            for (i, band) in [StressBand.high, .medium, .low].enumerated() {
                let r = CGRect(x: 0, y: CGFloat(i) * bandH, width: w, height: bandH)
                ctx.fill(Path(r), with: .color(TodayStressLogic.bandColor(band).opacity(0.16)))
            }
            for span in model.moving {
                let r = CGRect(x: CGFloat(span.lowerBound) * w, y: 0,
                               width: max(1, CGFloat(span.upperBound - span.lowerBound) * w), height: h)
                ctx.fill(Path(r), with: .color(StrandPalette.stressMoving.opacity(0.9)))
            }
            func stressPoint(_ p: TodayStressModel.Point) -> CGPoint {
                CGPoint(x: CGFloat(p.x) * w, y: h - CGFloat(p.level / 3) * h)
            }
            var runs: [[TodayStressModel.Point]] = []
            for p in model.points {
                if let last = runs.last?.last, last.run == p.run { runs[runs.count - 1].append(p) } else { runs.append([p]) }
            }
            let style = StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round)
            for run in runs {
                if run.count >= 2 {
                    var path = Path()
                    path.move(to: stressPoint(run[0]))
                    for p in run.dropFirst() { path.addLine(to: stressPoint(p)) }
                    ctx.stroke(path, with: .color(StrandPalette.textPrimary), style: style)
                } else if let only = run.first {
                    let c = stressPoint(only)
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - 3, y: c.y - 3, width: 6, height: 6)),
                             with: .color(StrandPalette.textPrimary))
                }
            }
            if let last = model.points.last {
                let c = stressPoint(last)
                let color = TodayStressLogic.bandColor(TodayStressLogic.stressBand(last.level))
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10)), with: .color(color))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityHidden(true)
    }

    private var axis: some View {
        HStack {
            ForEach(Array(TodayStressLogic.axisLabels(dayStart: model.dayStart).enumerated()), id: \.offset) { i, label in
                if i > 0 { Spacer(minLength: 0) }
                Text(verbatim: label)
            }
        }
        .font(StrandFont.caption)
        .foregroundStyle(StrandPalette.textSecondary)
        .accessibilityHidden(true)
    }

    private var legend: some View {
        HStack(spacing: NoopMetrics.space3) {
            swatch(TodayStressLogic.bandColor(.low).opacity(0.55), TodayStressLogic.bandName(.low))
            swatch(TodayStressLogic.bandColor(.medium).opacity(0.55), TodayStressLogic.bandName(.medium))
            swatch(TodayStressLogic.bandColor(.high).opacity(0.55), TodayStressLogic.bandName(.high))
            swatch(StrandPalette.stressMoving, String(localized: "moving"))
            Spacer(minLength: 0)
        }
        .font(StrandFont.caption)
        .foregroundStyle(StrandPalette.textSecondary)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }

    private func swatch(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 10, height: 10)
                .accessibilityHidden(true)
            Text(verbatim: label)
        }
    }

    private var stats: some View {
        HStack {
            stressStat(String(localized: "High"), TodayStressLogic.minutesText(model.highMinutes))
            Spacer()
            stressStat(String(localized: "Avg"), model.mean.map(TodayStressLogic.levelText) ?? "–")
            Spacer()
            stressStat(String(localized: "Peak"), model.peakStartTs.map(TodayStressLogic.stressClock) ?? "–")
        }
    }

    private func stressStat(_ label: String, _ value: String) -> some View {
        HStack(spacing: 5) {
            Text(verbatim: label).font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
            Text(verbatim: value)
                .font(StrandFont.subhead.weight(.semibold)).foregroundStyle(StrandPalette.textPrimary)
        }
    }
}

/// « How it's calculated »: what the card shows, in three short paragraphs.
struct TodayStressMethodSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NoopMetrics.space4) {
                    Text("Every half hour, NOOP reads your heart rate over the past hour (and your heart-rate variability when it is clean enough) and compares it with your own calm hours of the day. The gap is placed on a 0 to 3 scale: 0 is calm, 1.5 your usual, 3 highly activated.")
                    Text("Calm is below 1, Moderate from 1 to 2, High from 2. Hours when you were moving are left out and shown in grey: exertion is not stress.")
                    Text("Only waking hours from 06:00 to 22:00 are scored, and an hour needs enough heart rate. Everything is computed on your phone; it is an estimate, not a medical measurement.")
                }
                .font(StrandFont.body)
                .foregroundStyle(StrandPalette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(NoopMetrics.screenHPadding)
            }
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .navigationTitle(String(localized: "How it's calculated"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #endif
    }
}
