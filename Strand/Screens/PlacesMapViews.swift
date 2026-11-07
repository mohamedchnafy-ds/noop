import SwiftUI
import StrandDesign
import WhoopStore

// Personal fork, chantier 14 step 2: the Map's Lieux and Points views and a place's screen (mockup v1
// screens 3, 4 and 7). Figures come from `PlaceMapReader`; the colours say better (light blue), close
// (grey) or worse (orange) than the wearer's own normal, never good or bad in themselves.

/// The colours of a verdict.
enum PlaceVerdictStyle {
    static func color(_ verdict: PlaceVerdict) -> Color {
        switch verdict {
        case .better: return StrandPalette.metricCyan
        case .worse: return StrandPalette.statusWarning
        case .close, .tooFew: return StrandPalette.textSecondary
        case .none: return StrandPalette.textTertiary
        }
    }

    static func hollow(_ verdict: PlaceVerdict) -> Bool { verdict == .tooFew || verdict == .none }

    /// A signed difference: « +5 bpm », « −7 ms », « 0 bpm ».
    static func signed(_ delta: Double, unit: String, decimals: Int = 0) -> String {
        let rounded = decimals == 0 ? delta.rounded() : (delta * 10).rounded() / 10
        let magnitude = abs(rounded)
        let number = decimals == 0 ? String(Int(magnitude)) : UnitFormatter.decimal(magnitude, places: decimals)
        let sign = rounded > 0 ? "+" : (rounded < 0 ? "−" : "")
        return sign + number + (unit.isEmpty ? "" : " " + unit)
    }
}

/// The layer chips' titles.
extension PlaceLayer {
    var chipTitle: LocalizedStringKey {
        switch self {
        case .heartRate: return "HR"
        case .stress: return "Stress"
        case .hrv: return "HRV"
        case .recovery: return "Recov."
        }
    }
}

// MARK: - Formatting

enum PlaceFigureFormat {

    /// The value of a figure in its unit, or « — ».
    static func value(_ figure: PlaceFigure, layer: PlaceLayer) -> String {
        guard let v = figure.value else { return "—" }
        switch layer {
        case .heartRate: return String(localized: "\(Int(v.rounded())) bpm")
        case .stress: return "\(Int(v.rounded())) %"
        case .hrv: return String(localized: "\(Int(v.rounded())) ms")
        case .recovery: return "\(Int(v.rounded())) %"
        }
    }

    /// The difference, « trop peu » when there is not enough data, empty when nothing to compare.
    static func delta(_ figure: PlaceFigure, layer: PlaceLayer) -> String {
        if figure.verdict == .tooFew { return String(localized: "too few") }
        guard let d = figure.delta else { return "" }
        switch layer {
        case .heartRate: return PlaceVerdictStyle.signed(d, unit: "bpm")
        case .stress: return PlaceVerdictStyle.signed(d, unit: String(localized: "pts"))
        case .hrv: return PlaceVerdictStyle.signed(d, unit: "ms")
        case .recovery: return PlaceVerdictStyle.signed(d, unit: String(localized: "pts"))
        }
    }

    /// « 88 visites » / « 58 nuits » / « aucune nuit », under a place's name.
    static func countLine(_ summary: PlaceSummary, layer: PlaceLayer) -> String {
        switch layer {
        case .heartRate, .stress:
            return summary.visits == 1 ? String(localized: "1 visit") : String(localized: "\(summary.visits) visits")
        case .hrv, .recovery:
            switch summary.nights {
            case 0: return String(localized: "no night")
            case 1: return String(localized: "1 night")
            default: return String(localized: "\(summary.nights) nights")
            }
        }
    }

    /// « 7 h 05 min » for a sleep length.
    static func sleepLength(_ minutes: Double) -> String {
        WorkoutHistoryLogic.historyDuration(minutes: Int(minutes.rounded()))
    }
}

// MARK: - Lieux

struct PlacesLayerView: View {
    let summaries: [PlaceSummary]
    let loaded: Bool
    @Binding var layer: PlaceLayer
    @AppStorage(PlaceTrackingSettings.enabledKey) private var enabled = false

    private func dotRadius(_ summary: PlaceSummary) -> Double {
        40 + sqrt(Double(summary.visits)) * 14
    }

    private var sorted: [PlaceSummary] {
        func rank(_ v: PlaceVerdict) -> Int {
            switch v { case .worse: return 0; case .better: return 1; case .close: return 2; case .tooFew: return 3; case .none: return 4 }
        }
        return summaries.sorted {
            let a = rank($0.figure(layer).verdict), b = rank($1.figure(layer).verdict)
            return a != b ? a < b : $0.visits > $1.visits
        }
    }

    var body: some View {
        if !enabled {
            enableCard
        } else if summaries.isEmpty {
            if loaded {
                Text("No place yet. iOS reports a place after you have stayed there a while; the first differences show after about two weeks.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            layerChips
            mapCard
            explain
            listCard
            Text("Last 90 days · a difference is not a cause: a place mostly reflects what you do there.")
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var enableCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("See your metrics by place")
                .font(StrandFont.sectionTitle)
                .foregroundStyle(StrandPalette.textPrimary)
            Text("Turn on Places so the iPhone spots where you stay. Your heart rate, stress, HRV and recovery are then compared place by place.")
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            NavigationLink {
                PlacesSettingsView()
            } label: {
                Text("Turn on Places")
                    .font(StrandFont.body.weight(.semibold))
                    .foregroundStyle(StrandPalette.surfaceBase)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(StrandPalette.textPrimary))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(NoopPanelSurface(cornerRadius: 26))
    }

    private var layerChips: some View {
        HStack(spacing: 6) {
            ForEach(PlaceLayer.allCases) { item in
                Button { layer = item } label: {
                    Text(item.chipTitle)
                        .font(StrandFont.subhead.weight(.semibold))
                        .foregroundStyle(layer == item ? StrandPalette.surfaceBase : StrandPalette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(Capsule().fill(layer == item ? StrandPalette.textPrimary : StrandPalette.surfaceOverlay))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(layer == item ? .isSelected : [])
            }
        }
    }

    private var mapCard: some View {
        NoopCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                PlaceDotsMap(dots: summaries.map { summary in
                    let figure = summary.figure(layer)
                    return MapDot(id: summary.id, lat: summary.place.lat, lon: summary.place.lon,
                                  radiusM: dotRadius(summary), color: PlaceVerdictStyle.color(figure.verdict),
                                  hollow: PlaceVerdictStyle.hollow(figure.verdict), label: summary.name)
                })
                .frame(height: 320)
                .clipShape(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
                .accessibilityHidden(true)
                HStack(spacing: 12) {
                    legendItem(StrandPalette.metricCyan, "Better than your normal")
                    legendItem(StrandPalette.textSecondary, "Close to it")
                    legendItem(StrandPalette.statusWarning, "Worse")
                }
                .padding(NoopMetrics.cardPadding)
            }
        }
    }

    private func legendItem(_ color: Color, _ title: LocalizedStringKey) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 10, height: 10).accessibilityHidden(true)
            Text(title)
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    @ViewBuilder
    private var explain: some View {
        Group {
            switch layer {
            case .heartRate:
                Text("Mean heart rate during your visits, compared with your heart rate at the same hours elsewhere. Workouts and sleep are left out.")
            case .stress:
                Text("Share of the time in High stress during your visits (hours on the move left out), compared with your mean. Last 14 days.")
            case .hrv:
                Text("HRV of the nights slept at this place, compared with your normal. At least 3 nights are needed to show a difference.")
            case .recovery:
                Text("Morning recovery after a night spent at this place, compared with your mean.")
            }
        }
        .font(StrandFont.footnote)
        .foregroundStyle(StrandPalette.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var listCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(sorted.enumerated()), id: \.element.id) { index, summary in
                if index > 0 { Rectangle().fill(StrandPalette.hairline).frame(height: 1) }
                NavigationLink {
                    PlaceDetailView(summary: summary)
                } label: {
                    placeRow(summary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(NoopPanelSurface(cornerRadius: 26))
    }

    private func placeRow(_ summary: PlaceSummary) -> some View {
        let figure = summary.figure(layer)
        let color = PlaceVerdictStyle.color(figure.verdict)
        return HStack(spacing: 12) {
            Circle()
                .strokeBorder(color, lineWidth: 2)
                .background(Circle().fill(PlaceVerdictStyle.hollow(figure.verdict) ? Color.clear : color))
                .frame(width: 12, height: 12)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: summary.name)
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .lineLimit(1)
                Text(verbatim: PlaceFigureFormat.countLine(summary, layer: layer))
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(verbatim: PlaceFigureFormat.value(figure, layer: layer))
                    .font(StrandFont.number(17, weight: .semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(verbatim: PlaceFigureFormat.delta(figure, layer: layer))
                    .font(StrandFont.number(13))
                    .foregroundStyle(color)
            }
        }
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }
}

// MARK: - Un lieu

struct PlaceDetailView: View {
    @EnvironmentObject private var repo: Repository
    @Environment(\.dismiss) private var dismiss
    let summary: PlaceSummary
    @State private var renaming = false
    @State private var draftName = ""
    @State private var confirmForget = false
    @State private var shownName: String?

    var body: some View {
        ScreenScaffold(title: LocalizedStringKey(shownName ?? summary.name), trailing: {
            Button("Rename") {
                draftName = summary.place.name ?? ""
                renaming = true
            }
            .font(StrandFont.body)
        }) {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                Text(verbatim: header)
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                mapCard
                compareSection
                if !summary.nightBars.isEmpty { nightsSection }
                Text("A difference, not a cause: what you do at a place, and when, weighs more than the place itself. A few nights are enough for a difference, not for a conclusion.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(role: .destructive) { confirmForget = true } label: {
                    Text("Forget this place")
                        .font(StrandFont.body)
                        .foregroundStyle(StrandPalette.statusCritical)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(NoopPanelSurface(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
        }
        .alert("Rename", isPresented: $renaming) {
            TextField("Name", text: $draftName)
            Button("Save") {
                let name = draftName
                shownName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : name
                Task {
                    guard let store = await repo.storeHandle() else { return }
                    await PlaceLog.renameKnownPlace(store, id: summary.place.id, name: name)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Forget this place?", isPresented: $confirmForget, titleVisibility: .visible) {
            Button("Forget", role: .destructive) {
                Task {
                    guard let store = await repo.storeHandle() else { return }
                    await PlaceLog.forgetKnownPlace(store, id: summary.place.id)
                    dismiss()
                }
            }
        } message: {
            Text("The place and its visits are deleted from this iPhone. iOS may find it again at your next stay.")
        }
    }

    private var header: String {
        var parts = [summary.visits == 1 ? String(localized: "1 visit") : String(localized: "\(summary.visits) visits")]
        switch summary.nights {
        case 0: break
        case 1: parts.append(String(localized: "1 night"))
        default: parts.append(String(localized: "\(summary.nights) nights"))
        }
        if let last = summary.lastArrival {
            parts.append(String(localized: "last on \(Self.dayLabel(last))"))
        }
        return parts.joined(separator: " · ")
    }

    /// « 62 % », passed as an argument so no key holds a literal percent sign.
    static func percent(_ value: Double) -> String { "\(Int(value.rounded())) %" }

    static func dayLabel(_ ts: Int) -> String {
        let style = Date.FormatStyle().weekday(.abbreviated).day().month(.abbreviated)
        return Date(timeIntervalSince1970: TimeInterval(ts)).formatted(style)
    }

    private var mapCard: some View {
        NoopCard(padding: 0) {
            ZStack(alignment: .bottomLeading) {
                PlaceDotsMap(dots: [MapDot(id: summary.id, lat: summary.place.lat, lon: summary.place.lon,
                                           radiusM: summary.place.radiusM,
                                           color: PlaceVerdictStyle.color(summary.hrv.verdict == .none
                                                                          ? summary.heartRate.verdict : summary.hrv.verdict),
                                           hollow: true)])
                    .frame(height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
                    .accessibilityHidden(true)
                Text("Zone of about \(Int(summary.place.radiusM)) m · found by the iPhone")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(StrandPalette.surfaceRaised))
                    .padding(10)
            }
        }
    }

    private var compareSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Compared with your normal").font(StrandFont.sectionTitle).foregroundStyle(StrandPalette.textPrimary)
            VStack(alignment: .leading, spacing: 0) {
                compareRow(title: "Night HRV", color: StrandPalette.metricCyan,
                           normal: summary.hrv.normal.map { String(localized: "normal \(Int($0.rounded())) ms") },
                           figure: summary.hrv, layer: .hrv)
                Rectangle().fill(StrandPalette.hairline).frame(height: 1)
                compareRow(title: "Recovery", color: StrandPalette.textPrimary,
                           normal: summary.recovery.normal.map { String(localized: "mean \(Self.percent($0))") },
                           figure: summary.recovery, layer: .recovery)
                Rectangle().fill(StrandPalette.hairline).frame(height: 1)
                sleepRow
                Rectangle().fill(StrandPalette.hairline).frame(height: 1)
                compareRow(title: "Heart rate during visits", color: StrandPalette.metricRose,
                           normal: summary.heartRate.normal.map { String(localized: "same hours elsewhere \(Int($0.rounded())) bpm") },
                           figure: summary.heartRate, layer: .heartRate)
                Rectangle().fill(StrandPalette.hairline).frame(height: 1)
                compareRow(title: "High stress", color: StrandPalette.stressHigh,
                           normal: summary.stress.normal.map { String(localized: "mean \(Self.percent($0)) of the time") },
                           figure: summary.stress, layer: .stress)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .background(NoopPanelSurface(cornerRadius: 26))
        }
    }

    private func compareRow(title: LocalizedStringKey, color: Color, normal: String?, figure: PlaceFigure,
                            layer: PlaceLayer) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(StrandFont.body).foregroundStyle(color)
                if let normal {
                    Text(verbatim: normal).font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(verbatim: PlaceFigureFormat.value(figure, layer: layer))
                    .font(StrandFont.number(20, weight: .bold))
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(verbatim: PlaceFigureFormat.delta(figure, layer: layer))
                    .font(StrandFont.number(13))
                    .foregroundStyle(PlaceVerdictStyle.color(figure.verdict))
            }
        }
        .frame(minHeight: 60)
    }

    private var sleepRow: some View {
        let figure = summary.sleep
        let delta: String = {
            if figure.verdict == .tooFew { return String(localized: "too few") }
            guard let d = figure.delta else { return "" }
            let minutes = Int(d.rounded())
            let sign = minutes > 0 ? "+" : (minutes < 0 ? "−" : "")
            return sign + PlaceFigureFormat.sleepLength(Double(abs(minutes)))
        }()
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Sleep").font(StrandFont.body).foregroundStyle(StrandPalette.metricPurple)
                if let normal = figure.normal {
                    Text(verbatim: String(localized: "mean \(PlaceFigureFormat.sleepLength(normal))"))
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(verbatim: figure.value.map(PlaceFigureFormat.sleepLength) ?? "—")
                    .font(StrandFont.number(20, weight: .bold))
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(verbatim: delta)
                    .font(StrandFont.number(13))
                    .foregroundStyle(PlaceVerdictStyle.color(figure.verdict))
            }
        }
        .frame(minHeight: 60)
    }

    private var nightsSection: some View {
        let bars = Array(summary.nightBars.suffix(12))
        let top = max(bars.compactMap(\.hrv).max() ?? 1, 1)
        let normal = summary.hrv.normal
        return VStack(alignment: .leading, spacing: 10) {
            Text("Nights here").font(StrandFont.sectionTitle).foregroundStyle(StrandPalette.textPrimary)
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(bars.enumerated()), id: \.offset) { _, bar in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(barColor(bar.hrv, normal: normal))
                            .frame(width: 18, height: max(4, 70 * CGFloat((bar.hrv ?? 0) / top)))
                        Text(verbatim: Self.shortDay(bar.day))
                            .font(StrandFont.caption2)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 100, alignment: .bottom)
            .padding(16)
            .background(NoopPanelSurface(cornerRadius: 26))
            Text("HRV of each night, in light blue when above your normal, orange when below.")
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func barColor(_ hrv: Double?, normal: Double?) -> Color {
        guard let hrv, let normal else { return StrandPalette.textTertiary }
        return PlaceVerdictStyle.color(PlaceMetrics.verdict(delta: hrv - normal, band: PlaceMetrics.closeBand(.hrv),
                                                            higherIsBetter: true))
    }

    /// « 14 sept. » from "2026-09-14".
    static func shortDay(_ key: String) -> String {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let date = Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        else { return key }
        return date.formatted(Date.FormatStyle().day().month(.abbreviated))
    }
}

// MARK: - Points

/// The Points view's period.
enum PlacePointsPeriod: Int, CaseIterable, Identifiable {
    case day = 1, week = 7, month = 30
    var id: Int { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .day: return "Day"
        case .week: return "7 D"
        case .month: return "30 D"
        }
    }
}

/// The Points view's layer.
enum PlacePointsLayer: String, CaseIterable, Identifiable {
    case heartRate, stress
    var id: String { rawValue }
}

struct PointsLayerView: View {
    let marks: [PlacePointMark]
    let loaded: Bool
    @Binding var layer: PlacePointsLayer
    @Binding var period: PlacePointsPeriod
    @State private var picked: Int64?
    @AppStorage(PlaceTrackingSettings.enabledKey) private var enabled = false

    private func color(_ mark: PlacePointMark) -> Color {
        switch layer {
        case .heartRate:
            return mark.bpm == nil ? StrandPalette.textTertiary : PlaceVerdictStyle.color(mark.hrVerdict)
        case .stress:
            if mark.moving { return StrandPalette.stressMoving }
            guard let level = mark.stressLevel else { return StrandPalette.textTertiary }
            switch StressBand(score: level) {
            case .low: return StrandPalette.stressCalm
            case .medium: return StrandPalette.stressModerate
            case .high: return StrandPalette.stressHigh
            }
        }
    }

    private func isHollow(_ mark: PlacePointMark) -> Bool {
        switch layer {
        case .heartRate: return mark.bpm == nil
        case .stress: return !mark.moving && mark.stressLevel == nil
        }
    }

    var body: some View {
        if !enabled {
            Text("Turn on Places to keep a point every 15 minutes and colour it by heart rate or stress.")
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            HStack(spacing: 8) {
                Picker("Layer", selection: $layer) {
                    Text("HR").tag(PlacePointsLayer.heartRate)
                    Text("Stress").tag(PlacePointsLayer.stress)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Picker("Period", selection: $period) {
                    ForEach(PlacePointsPeriod.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            if marks.isEmpty {
                if loaded {
                    Text("No point in this period yet.")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
            } else {
                mapCard
                explain
                tiles
            }
        }
    }

    private var pickedMark: PlacePointMark? { marks.first { $0.ts == picked } }

    private var mapCard: some View {
        NoopCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .top) {
                    PlaceDotsMap(dots: marks.map { mark in
                        MapDot(id: String(mark.ts), lat: mark.lat, lon: mark.lon,
                               radiusM: picked == mark.ts ? 45 : 30, color: color(mark),
                               hollow: isHollow(mark), selected: picked == mark.ts)
                    }, onTap: { id in
                        let ts = id.flatMap { Int64($0) }
                        picked = (ts == picked) ? nil : ts
                    })
                    .frame(height: 340)
                    .clipShape(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
                    if let mark = pickedMark { pickCard(mark) }
                }
                legend.padding(NoopMetrics.cardPadding)
            }
        }
    }

    private func pickCard(_ mark: PlacePointMark) -> some View {
        let date = Date(timeIntervalSince1970: Double(mark.ts) / 1000)
        var when = date.formatted(Date.FormatStyle().weekday(.abbreviated).day().month(.abbreviated).hour().minute())
        if let place = mark.placeName { when += " · " + place }
        let main: String
        let sub: String
        if let bpm = mark.bpm {
            var line = String(localized: "\(Int(bpm.rounded())) bpm")
            if let usual = mark.habitual { line += " · " + PlaceVerdictStyle.signed(bpm - usual, unit: "bpm") }
            main = line
            if mark.moving {
                sub = String(localized: "On the move · difference to your heart rate at the same hour")
            } else if let level = mark.stressLevel {
                sub = String(localized: "Stress \(TodayStressLogic.bandName(StressBand(score: level))) · difference to your heart rate at the same hour")
            } else {
                sub = String(localized: "Difference to your heart rate at the same hour")
            }
        } else {
            main = String(localized: "No heart rate")
            sub = String(localized: "Strap off, or not synced yet")
        }
        return VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: when).font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
            Text(verbatim: main).font(StrandFont.number(17, weight: .semibold)).foregroundStyle(StrandPalette.textPrimary)
            Text(verbatim: sub).font(StrandFont.footnote).foregroundStyle(StrandPalette.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(StrandPalette.surfaceRaised))
        .padding(12)
    }

    @ViewBuilder
    private var legend: some View {
        HStack(spacing: 12) {
            switch layer {
            case .heartRate:
                legendItem(StrandPalette.metricCyan, "Lower")
                legendItem(StrandPalette.textSecondary, "Normal")
                legendItem(StrandPalette.statusWarning, "Higher")
            case .stress:
                legendItem(StrandPalette.stressCalm, "Calm")
                legendItem(StrandPalette.stressModerate, "Moderate")
                legendItem(StrandPalette.stressHigh, "High")
                legendItem(StrandPalette.stressMoving, "Moving")
            }
        }
    }

    private func legendItem(_ color: Color, _ title: LocalizedStringKey) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 10, height: 10).accessibilityHidden(true)
            Text(title)
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    @ViewBuilder
    private var explain: some View {
        Group {
            if layer == .heartRate {
                Text("Each dot is one point. Its colour is your heart rate then, compared with your usual heart rate at the same hour (±3 bpm = normal). Hollow: no heart rate.")
            } else {
                Text("Each dot is one point. Its colour is the stress of that hour; dark grey when you were moving. Stress covers the last 14 days.")
            }
        }
        .font(StrandFont.footnote)
        .foregroundStyle(StrandPalette.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var tiles: some View {
        let withHR = marks.filter { $0.bpm != nil }.count
        let higher = marks.filter { $0.hrVerdict == .worse }.count
        let lower = marks.filter { $0.hrVerdict == .better }.count
        let steps = marks.compactMap(\.steps).reduce(0, +)
        return HStack(spacing: 8) {
            tile(title: "Points", value: "\(marks.count)", sub: String(localized: "with HR: \(withHR)"))
            if layer == .heartRate {
                tile(title: "Higher", value: "\(higher)", sub: String(localized: "above your usual"))
                tile(title: "Lower", value: "\(lower)", sub: String(localized: "below your usual"))
            } else {
                let high = marks.filter { !$0.moving && ($0.stressLevel ?? 0) >= 2 }.count
                tile(title: "High", value: "\(high)", sub: String(localized: "points in High"))
                tile(title: "Steps", value: steps > 0 ? steps.formatted() : "—",
                     sub: String(localized: "between points"))
            }
        }
    }

    private func tile(title: LocalizedStringKey, value: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
            Text(verbatim: value).font(StrandFont.number(22, weight: .bold)).foregroundStyle(StrandPalette.textPrimary)
            Text(verbatim: sub).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(NoopPanelSurface(cornerRadius: 16))
    }
}
