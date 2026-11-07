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
        case .worse: return StrandPalette.deviationOrange
        case .close, .tooFew: return StrandPalette.textSecondary
        case .none: return StrandPalette.textTertiary
        }
    }

    static func hollow(_ verdict: PlaceVerdict) -> Bool { verdict == .tooFew || verdict == .none }

    /// A signed difference: « +5 bpm », « −7 ms », « 0 bpm ».
    static func signedPlaceDelta(_ delta: Double, unit: String, decimals: Int = 0) -> String {
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
    static func valueText(_ figure: PlaceFigure, layer: PlaceLayer) -> String {
        guard let v = figure.value else { return "—" }
        switch layer {
        case .heartRate: return String(localized: "\(Int(v.rounded())) bpm")
        case .stress: return "\(Int(v.rounded())) %"
        case .hrv: return String(localized: "\(Int(v.rounded())) ms")
        case .recovery: return "\(Int(v.rounded())) %"
        }
    }

    /// The difference, « trop peu » when there is not enough data, empty when nothing to compare.
    static func deltaText(_ figure: PlaceFigure, layer: PlaceLayer) -> String {
        if figure.verdict == .tooFew { return String(localized: "too few") }
        guard let d = figure.delta else { return "" }
        switch layer {
        case .heartRate: return PlaceVerdictStyle.signedPlaceDelta(d, unit: "bpm")
        case .stress: return PlaceVerdictStyle.signedPlaceDelta(d, unit: String(localized: "pts"))
        case .hrv: return PlaceVerdictStyle.signedPlaceDelta(d, unit: "ms")
        case .recovery: return PlaceVerdictStyle.signedPlaceDelta(d, unit: String(localized: "pts"))
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

// MARK: - Map pieces (Carte v2)

extension PlaceLayer {
    /// « VFC », « FC »… before a value on the map.
    var tagName: String {
        switch self {
        case .heartRate: return String(localized: "HR")
        case .stress: return String(localized: "Stress")
        case .hrv: return String(localized: "HRV")
        case .recovery: return String(localized: "Recov.")
        }
    }
}

extension PlaceFigureFormat {

    /// « VFC +4 ms » under a place on the map, « VFC · trop peu », empty with nothing to compare.
    static func tagText(_ figure: PlaceFigure, layer: PlaceLayer) -> String {
        let delta = deltaText(figure, layer: layer)
        guard !delta.isEmpty else { return "" }
        return layer.tagName + (figure.verdict == .tooFew ? " · " : " ") + delta
    }
}

/// « Activer les Lieux » when Places is off.
struct PlacesEnableCard: View {
    var body: some View {
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
}

/// The places, worse first, each opening its screen.
struct PlacesListCard: View {
    let summaries: [PlaceSummary]
    let layer: PlaceLayer

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
        VStack(alignment: .leading, spacing: 10) {
            Text("Places").font(StrandFont.sectionTitle).foregroundStyle(StrandPalette.textPrimary)
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
            explain
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

    private func placeRow(_ summary: PlaceSummary) -> some View {
        let figure = summary.figure(layer)
        let color = PlaceVerdictStyle.color(figure.verdict)
        return HStack(spacing: 12) {
            Circle()
                .fill(PlaceVerdictStyle.hollow(figure.verdict) ? color.opacity(0.45) : color)
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
                Text(verbatim: PlaceFigureFormat.valueText(figure, layer: layer))
                    .font(StrandFont.number(17, weight: .semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(verbatim: PlaceFigureFormat.deltaText(figure, layer: layer))
                    .font(StrandFont.number(13))
                    .foregroundStyle(color)
            }
        }
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }
}

/// The card over the map for the place touched.
struct PlaceSelectionCard: View {
    let summary: PlaceSummary
    let layer: PlaceLayer
    /// Opens the place's screen (not in full screen, which has no navigation).
    var linked = true

    var body: some View {
        if linked {
            NavigationLink {
                PlaceDetailView(summary: summary)
            } label: {
                card
            }
            .buttonStyle(.plain)
        } else {
            card
        }
    }

    private var card: some View {
        let figure = summary.figure(layer)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: summary.name)
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .lineLimit(1)
                Text(verbatim: PlaceFigureFormat.countLine(summary, layer: layer))
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            VStack(alignment: .trailing, spacing: 2) {
                Text(verbatim: PlaceFigureFormat.valueText(figure, layer: layer))
                    .font(StrandFont.number(15, weight: .semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(verbatim: PlaceFigureFormat.deltaText(figure, layer: layer))
                    .font(StrandFont.number(12))
                    .foregroundStyle(PlaceVerdictStyle.color(figure.verdict))
            }
            if linked {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(StrandPalette.textTertiary)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(StrandPalette.surfaceRaised.opacity(0.94)))
        .frame(maxWidth: 280, alignment: .leading)
    }
}

/// The legend posed on the map: one line per layer drawn.
struct MapLayersLegend: View {
    let routes: Bool
    let routeMode: RouteColorMode
    let places: Bool
    let placeLayer: PlaceLayer
    let points: Bool
    let pointsByStress: Bool

    var body: some View {
        if routes || places || points {
            VStack(alignment: .leading, spacing: 5) {
                if routes { routesLine }
                if places {
                    line(title: String(localized: "Places") + " · " + placeLayer.tagName, items: [
                        (StrandPalette.metricCyan, String(localized: "Better")),
                        (StrandPalette.textSecondary, String(localized: "Close to it")),
                        (StrandPalette.deviationOrange, String(localized: "Worse"))
                    ])
                }
                if points {
                    if pointsByStress {
                        line(title: String(localized: "Points") + " · " + String(localized: "Stress"), items: [
                            (StrandPalette.stressCalm, String(localized: "Calm")),
                            (StrandPalette.stressModerate, String(localized: "Moderate")),
                            (StrandPalette.stressHigh, String(localized: "High")),
                            (StrandPalette.stressMoving, String(localized: "Moving"))
                        ])
                    } else {
                        line(title: String(localized: "Points") + " · " + String(localized: "HR"), items: [
                            (StrandPalette.metricCyan, String(localized: "Lower")),
                            (StrandPalette.textSecondary, String(localized: "Normal")),
                            (StrandPalette.deviationOrange, String(localized: "Higher"))
                        ])
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(StrandPalette.surfaceBase.opacity(0.78)))
            .accessibilityElement(children: .combine)
        }
    }

    private var routesLine: some View {
        HStack(spacing: 6) {
            Text("Routes").font(StrandFont.caption2.weight(.semibold)).foregroundStyle(StrandPalette.textPrimary)
            switch routeMode {
            case .zones:
                ForEach(1...5, id: \.self) { zone in
                    Capsule().fill(routeMode.color(zone)).frame(width: 12, height: 4).accessibilityHidden(true)
                }
                Text("Heart-rate zones").font(StrandFont.caption2).foregroundStyle(StrandPalette.textSecondary)
            case .cadence:
                Text("Slow").font(StrandFont.caption2).foregroundStyle(StrandPalette.textSecondary)
                ForEach(1...5, id: \.self) { band in
                    Capsule().fill(routeMode.color(band)).frame(width: 12, height: 4).accessibilityHidden(true)
                }
                Text("Fast").font(StrandFont.caption2).foregroundStyle(StrandPalette.textSecondary)
            }
        }
    }

    private func line(title: String, items: [(Color, String)]) -> some View {
        HStack(spacing: 6) {
            Text(verbatim: title).font(StrandFont.caption2.weight(.semibold)).foregroundStyle(StrandPalette.textPrimary)
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 3) {
                    Circle().fill(item.0).frame(width: 7, height: 7).accessibilityHidden(true)
                    Text(verbatim: item.1).font(StrandFont.caption2).foregroundStyle(StrandPalette.textSecondary)
                }
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

/// One line of « Ce qui ressort ».
struct StandoutRow: View {
    let standout: PlaceStandout

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: standout.name)
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .lineLimit(1)
                Text(verbatim: StandoutFormat.metricTitle(standout.metric) + " · " + StandoutFormat.countText(standout))
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(verbatim: StandoutFormat.deltaText(standout))
                    .font(StrandFont.number(17, weight: .semibold))
                    .foregroundStyle(PlaceVerdictStyle.color(standout.verdict))
                Text(verbatim: StandoutFormat.marginText(standout))
                    .font(StrandFont.number(12))
                    .foregroundStyle(StrandPalette.textSecondary)
            }
        }
        .frame(minHeight: 56)
        .accessibilityElement(children: .combine)
    }
}

/// The words and numbers of a stand-out.
enum StandoutFormat {

    static func metricTitle(_ metric: PlaceStandoutMetric) -> String {
        switch metric {
        case .hrv: return String(localized: "Night HRV")
        case .recovery: return String(localized: "Recovery")
        case .sleep: return String(localized: "Sleep")
        case .heartRate: return String(localized: "Heart rate during visits")
        case .stress: return String(localized: "High stress")
        }
    }

    /// « 6 nuits », « 12 visites ».
    static func countText(_ standout: PlaceStandout) -> String {
        switch standout.metric {
        case .hrv, .recovery, .sleep:
            return standout.count == 1 ? String(localized: "1 night") : String(localized: "\(standout.count) nights")
        case .heartRate, .stress:
            return standout.count == 1 ? String(localized: "1 visit") : String(localized: "\(standout.count) visits")
        }
    }

    private static func unit(_ metric: PlaceStandoutMetric) -> String {
        switch metric {
        case .hrv: return "ms"
        case .heartRate: return "bpm"
        case .recovery, .stress: return String(localized: "pts")
        case .sleep: return ""
        }
    }

    /// « −7 ms », « +35 min ».
    static func deltaText(_ standout: PlaceStandout) -> String {
        if standout.metric == .sleep {
            let minutes = Int(standout.delta.rounded())
            let sign = minutes > 0 ? "+" : (minutes < 0 ? "−" : "")
            return sign + PlaceFigureFormat.sleepLength(Double(abs(minutes)))
        }
        return PlaceVerdictStyle.signedPlaceDelta(standout.delta, unit: unit(standout.metric))
    }

    /// « ± 4 ms », the margin of error.
    static func marginText(_ standout: PlaceStandout) -> String {
        let margin = max(standout.margin.rounded(), 1)
        if standout.metric == .sleep { return "± " + PlaceFigureFormat.sleepLength(margin) }
        let u = unit(standout.metric)
        return "± " + String(Int(margin)) + (u.isEmpty ? "" : " " + u)
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
                Text(verbatim: PlaceFigureFormat.valueText(figure, layer: layer))
                    .font(StrandFont.number(20, weight: .bold))
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(verbatim: PlaceFigureFormat.deltaText(figure, layer: layer))
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
        return PlaceVerdictStyle.color(PlaceMetrics.placeVerdict(delta: hrv - normal, band: PlaceMetrics.closeBand(.hrv),
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

/// The colour of a point on the map: its heart rate against the same hour, or the stress of its hour.
enum PointMarkStyle {
    static func color(_ mark: PlacePointMark, byStress: Bool) -> Color {
        if !byStress {
            return mark.bpm == nil ? StrandPalette.textTertiary : PlaceVerdictStyle.color(mark.hrVerdict)
        }
        if mark.moving { return StrandPalette.stressMoving }
        guard let level = mark.stressLevel else { return StrandPalette.textTertiary }
        switch StressBand(score: level) {
        case .low: return StrandPalette.stressCalm
        case .medium: return StrandPalette.stressModerate
        case .high: return StrandPalette.stressHigh
        }
    }

    static func hollow(_ mark: PlacePointMark, byStress: Bool) -> Bool {
        byStress ? (!mark.moving && mark.stressLevel == nil) : mark.bpm == nil
    }
}

/// The card over the map for the point touched or the moment of the frise.
struct PointSelectionCard: View {
    let mark: PlacePointMark

    var body: some View {
        let date = Date(timeIntervalSince1970: Double(mark.ts) / 1000)
        var when = date.formatted(Date.FormatStyle().weekday(.abbreviated).day().month(.abbreviated).hour().minute())
        if let place = mark.placeName { when += " · " + place }
        let main: String
        let sub: String
        if let bpm = mark.bpm {
            var line = String(localized: "\(Int(bpm.rounded())) bpm")
            if let usual = mark.habitual { line += " · " + PlaceVerdictStyle.signedPlaceDelta(bpm - usual, unit: "bpm") }
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
            Text(verbatim: when).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            Text(verbatim: main).font(StrandFont.number(15, weight: .semibold)).foregroundStyle(StrandPalette.textPrimary)
            Text(verbatim: sub).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(StrandPalette.surfaceRaised.opacity(0.94)))
        .frame(maxWidth: 280, alignment: .leading)
    }
}
