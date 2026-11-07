import SwiftUI
import StrandDesign

/// The in-progress workout screen's content (personal fork, chantier 8 — design A of the fork's canvas):
/// the state and the sport, the time once, four tiles (heart rate with its zone, Effort, calories, then
/// the pace of the moment for cardio or average · max heart rate for strength), then for cardio the
/// distance with the time of each kilometre, the zones and the last ten minutes of heart rate, and for
/// strength the curve before the zones (sets and rests show on it). Pure: it draws a
/// `LiveWorkoutFigures`, so the render test draws it; `LiveWorkoutView` builds the figures every second.
struct LiveWorkoutDashboard: View {
    let figures: LiveWorkoutFigures
    var distanceSystem: UnitSystem = .metric
    /// Fork chantier 12, effect C: the heart beats at the live rhythm and figures roll; false draws a still
    /// frame (renders).
    var animated: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            timeBlock
            tiles
            switch figures.layout {
            case .cardio:
                distanceCard
                zonesCard
                curveCard
            case .strength:
                curveCard
                zonesCard
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Header and time

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(figures.isPaused ? StrandPalette.textSecondary : StrandPalette.metricRose)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Group {
                if figures.isPaused { Text("Paused") } else { Text("Recording workout") }
            }
            .font(StrandFont.subhead)
            .foregroundStyle(StrandPalette.textSecondary)
            Spacer(minLength: 8)
            Text(verbatim: figures.sportName)
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
                .lineLimit(1)
        }
    }

    private var timeBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Duration")
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textSecondary)
            Text(verbatim: ActiveWorkoutClock.clock(figures.elapsedSeconds))
                .font(StrandFont.rounded(64))
                .monospacedDigit()
                .foregroundStyle(StrandPalette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Tiles

    private var tiles: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                heartRateTile
                effortTile
            }
            GridRow {
                caloriesTile
                switch figures.layout {
                case .cardio: paceTile
                case .strength: averageTile
                }
            }
            // Chantier 14: the phone's steps on an outdoor walk, run or hike.
            if figures.layout == .cardio, figures.steps != nil {
                GridRow {
                    stepsTile
                    cadenceTile
                }
            }
        }
    }

    private var stepsTile: some View {
        tile(title: "Steps", tint: StrandPalette.metricCyan,
             value: figures.steps.map { LiveWorkoutDashboard.groupedSteps($0) } ?? "—", unit: nil) {
            Text("phone").foregroundStyle(StrandPalette.textSecondary)
        }
    }

    /// Steps per minute of the moment: « — » until there is half a minute of readings.
    private var cadenceTile: some View {
        tile(title: "Cadence", tint: StrandPalette.metricCyan,
             value: figures.cadence.map { "\($0)" } ?? "—", unit: "steps/min") { EmptyView() }
    }

    /// « 4 512 » with the locale's grouping.
    static func groupedSteps(_ steps: Int) -> String {
        steps.formatted(.number.grouping(.automatic))
    }

    private var zoneTint: Color {
        figures.zone >= 1 ? StrandPalette.hrZoneColor(figures.zone) : StrandPalette.textSecondary
    }

    private var heartRateTile: some View {
        tile(title: "Heart rate", tint: StrandPalette.metricRose,
             value: figures.bpm.map { "\($0)" } ?? "—", unit: "bpm") {
            VStack(alignment: .leading, spacing: 5) {
                Group {
                    if figures.zone >= 1 {
                        Text("Zone \(figures.zone) · \(LiveWorkoutDashboard.zoneName(figures.zone))")
                    } else {
                        Text("Below Zone 1")
                    }
                }
                .foregroundStyle(zoneTint)
                // Fork chantier 12, effect C: the five zones, the active one lit.
                NoopZoneStrip(zone: figures.zone, colors: (1...5).map { StrandPalette.hrZoneColor($0) })
            }
        }
        // The heart at the live rhythm, and the tile's outline in the zone's colour.
        .overlay(alignment: .topTrailing) {
            NoopHeartbeat(bpm: figures.bpm, tint: StrandPalette.metricRose, size: 18,
                          beating: animated && !figures.isPaused)
                .padding(14)
        }
        .overlay(RoundedRectangle(cornerRadius: NoopVisualStyle.cardRadius, style: .continuous)
            .strokeBorder(zoneTint.opacity(figures.zone >= 1 ? 0.6 : 0), lineWidth: 1.5))
        .animation(animated ? .easeOut(duration: 0.35) : nil, value: figures.zone)
        // Entering zone 4 or 5 is felt as well as seen.
        .strandHaptic(.light, trigger: figures.zone, when: { $0 >= 4 })
    }

    private var effortTile: some View {
        tile(title: "Effort", tint: StrandPalette.effortColor, value: figures.effort, unit: nil) {
            Text(verbatim: figures.effortState).foregroundStyle(StrandPalette.textSecondary)
        }
    }

    private var caloriesTile: some View {
        tile(title: "Calories", tint: StrandPalette.caloriesActivity,
             value: figures.kcal.map { "\($0)" } ?? "—", unit: "kcal") { EmptyView() }
    }

    /// The pace of the moment: « — » until there is a real stretch to measure.
    private var paceTile: some View {
        tile(title: "Current pace", tint: StrandPalette.metricCyan,
             value: UnitFormatter.paceFromSecPerKm(figures.currentPaceSecPerKm, system: distanceSystem),
             unit: nil) { EmptyView() }
    }

    private var averageTile: some View {
        let value = figures.averageHr.map { "\($0)" } ?? "—"
        let peak = figures.peakHr.map { "/ \($0)" }
        return tile(title: "Average · max", tint: StrandPalette.metricRose, value: value, unitText: peak) {
            Text("since the start").foregroundStyle(StrandPalette.textSecondary)
        }
    }

    private func tile<Detail: View>(title: LocalizedStringKey, tint: Color, value: String,
                                    unit: LocalizedStringKey?,
                                    @ViewBuilder detail: () -> Detail) -> some View {
        tileBody(title: title, tint: tint, value: value, unit: unit.map { AnyView(Text($0)) }, detail: detail)
    }

    private func tile<Detail: View>(title: LocalizedStringKey, tint: Color, value: String, unitText: String?,
                                    @ViewBuilder detail: () -> Detail) -> some View {
        tileBody(title: title, tint: tint, value: value, unit: unitText.map { AnyView(Text(verbatim: $0)) },
                 detail: detail)
    }

    private func tileBody<Detail: View>(title: LocalizedStringKey, tint: Color, value: String, unit: AnyView?,
                                        @ViewBuilder detail: () -> Detail) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(StrandFont.footnote.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(verbatim: value)
                    .font(StrandFont.rounded(34))
                    .monospacedDigit()
                    .foregroundStyle(StrandPalette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                    .animation(animated ? NoopMotion.value : nil, value: value)
                if let unit {
                    unit
                        .font(StrandFont.subhead.weight(.semibold))
                        .foregroundStyle(StrandPalette.textSecondary)
                }
            }
            detail()
                .font(StrandFont.footnote)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .background(NoopPanelSurface())
    }

    // MARK: - Distance and splits

    private var distanceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Distance")
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                Spacer(minLength: 8)
                Text(verbatim: figures.distanceM.map { UnitFormatter.distanceFromMeters($0, system: distanceSystem) } ?? "—")
                    .font(StrandFont.rounded(22))
                    .monospacedDigit()
                    .foregroundStyle(StrandPalette.textPrimary)
            }
            if !figures.splits.isEmpty {
                VStack(spacing: 6) {
                    ForEach(Array(figures.splits.enumerated()), id: \.offset) { index, seconds in
                        // Fork chantier 12: a kilometre just done slides in.
                        HStack {
                            Group {
                                if distanceSystem == .imperial { Text("Mile \(index + 1)") } else { Text("Kilometre \(index + 1)") }
                            }
                            .foregroundStyle(StrandPalette.textSecondary)
                            Spacer(minLength: 8)
                            Text(verbatim: LiveWorkoutMath.splitText(seconds))
                                .monospacedDigit()
                                .foregroundStyle(StrandPalette.textPrimary)
                        }
                        .font(StrandFont.subhead)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(animated ? NoopMotion.card : nil, value: figures.splits.count)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NoopPanelSurface())
    }

    // MARK: - Zones

    private var zonesCard: some View {
        let total = max(1, figures.zoneSeconds.reduce(0, +))
        return VStack(alignment: .leading, spacing: 10) {
            Text("Time in zones")
                .font(StrandFont.headline)
                .foregroundStyle(StrandPalette.textPrimary)
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                ForEach(1...5, id: \.self) { zone in
                    let seconds = figures.zoneSeconds.indices.contains(zone - 1) ? figures.zoneSeconds[zone - 1] : 0
                    let current = zone == figures.zone
                    GridRow {
                        Text("Z\(zone)")
                            .font(StrandFont.footnote.weight(current ? .semibold : .regular))
                            .foregroundStyle(current ? StrandPalette.textPrimary : StrandPalette.textSecondary)
                        Capsule()
                            .fill(StrandPalette.surfaceOverlay)
                            .frame(height: 8)
                            .overlay(alignment: .leading) {
                                GeometryReader { proxy in
                                    Capsule()
                                        .fill(StrandPalette.hrZoneColor(zone))
                                        .frame(width: proxy.size.width * CGFloat(seconds) / CGFloat(total))
                                }
                            }
                            .gridColumnAlignment(.leading)
                        Text(verbatim: LiveWorkoutMath.splitText(seconds))
                            .font(StrandFont.footnote)
                            .monospacedDigit()
                            .foregroundStyle(StrandPalette.textPrimary)
                            .gridColumnAlignment(.trailing)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NoopPanelSurface())
    }

    // MARK: - Curve

    private var curveCard: some View {
        let values = figures.curve.compactMap { $0 }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("HR · last 10 minutes")
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.metricRose)
                Spacer(minLength: 8)
                if let range = Self.bpmRange(values) {
                    Text(verbatim: range)
                        .font(StrandFont.footnote)
                        .monospacedDigit()
                        .foregroundStyle(StrandPalette.textSecondary)
                }
            }
            LiveWorkoutCurve(values: figures.curve)
                .frame(height: 90)
                .accessibilityHidden(true)
            HStack {
                Text("10 min ago")
                Spacer(minLength: 8)
                Text("now")
            }
            .font(StrandFont.caption)
            .foregroundStyle(StrandPalette.textSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NoopPanelSurface())
    }

    /// « 138–161 »: the curve's lowest and highest bucket, nil without a sample.
    static func bpmRange(_ values: [Double]) -> String? {
        guard let low = values.min(), let high = values.max() else { return nil }
        return [Int(low.rounded()), Int(high.rounded())].map(String.init).joined(separator: "–")
    }

    static func zoneName(_ zone: Int) -> String {
        switch zone {
        case 1: return String(localized: "Recovery")
        case 2: return String(localized: "Fat burn")
        case 3: return String(localized: "Aerobic")
        case 4: return String(localized: "Threshold")
        case 5: return String(localized: "Maximum")
        default: return ""
        }
    }
}

/// The last ten minutes of heart rate as one pink line, broken where there is no sample, scaled to its
/// own range (with a little room), over two hairlines.
struct LiveWorkoutCurve: View {
    let values: [Double?]

    var body: some View {
        GeometryReader { proxy in
            let known = values.compactMap { $0 }
            let low = (known.min() ?? 60) - 4
            let high = max((known.max() ?? 120) + 4, low + 10)
            let step = values.count > 1 ? proxy.size.width / CGFloat(values.count - 1) : 0
            ZStack {
                VStack {
                    Rectangle().fill(StrandPalette.hairline).frame(height: 1)
                    Spacer()
                    Rectangle().fill(StrandPalette.hairline).frame(height: 1)
                }
                Path { path in
                    var drawing = false
                    for (index, value) in values.enumerated() {
                        guard let value else { drawing = false; continue }
                        let point = CGPoint(x: CGFloat(index) * step,
                                            y: proxy.size.height * CGFloat(1 - (value - low) / (high - low)))
                        if drawing { path.addLine(to: point) } else { path.move(to: point) }
                        drawing = true
                    }
                }
                .stroke(StrandPalette.metricRose, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
            }
        }
    }
}
