import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopProtocol

// MARK: - Map of the workouts (personal fork, chantier 14, step 1)
//
// Mockup « NOOP – Carte », screen 1: every outdoor workout recorded on the phone on one map, each route
// coloured by the heart-rate zone of the moment (or by cadence when the phone counted steps), 30 days ·
// 90 days · all; a tap on a workout draws it alone (the others faded). Opened from More → Analysis. The
// routes, the readings and the heart rate all stay on the device; MapKit only fetches the tiles.

/// One workout on the Map screen.
struct RouteMapEntry: Identifiable, Equatable {
    var id: String
    var startTs: Int
    var sport: String
    var distanceM: Double
    var durationS: Int
    var zoneSegments: [RouteBandSegment]
    var cadenceSegments: [RouteBandSegment]
    /// Share of the route's points in Zone 1…5 (the bar under each row), all zero without heart rate.
    var zoneShares: [Double]
    var steps: Int?
}

enum RouteMapPeriod: String, CaseIterable, Identifiable {
    case days30, days90, all
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .days30: return "30D"
        case .days90: return "90D"
        case .all: return "All"
        }
    }

    var days: Int? {
        switch self {
        case .days30: return 30
        case .days90: return 90
        case .all: return nil
        }
    }
}

enum RouteMapReader {
    /// Most workouts the map draws at once (the latest ones of the period).
    static let maxRoutes = 60

    /// The keys of `RouteStore` that fall in the period, newest first: (key, start, sport).
    static func routeKeysInPeriod(_ keys: [String], period: RouteMapPeriod, now: Date) -> [(key: String, startTs: Int, sport: String)] {
        let floor = period.days.map { Int(now.timeIntervalSince1970) - $0 * 86_400 } ?? Int.min
        let parsed: [(key: String, startTs: Int, sport: String)] = keys.compactMap { key in
            guard let bar = key.firstIndex(of: "|"), let start = Int(key[..<bar]) else { return nil }
            return (key, start, String(key[key.index(after: bar)...]))
        }
        return Array(parsed.filter { $0.startTs >= floor }.sorted { $0.startTs > $1.startTs }.prefix(maxRoutes))
    }

    /// Share of the bands 1…5 among the route's points.
    static func zoneShares(_ bands: [Int]) -> [Double] {
        guard !bands.isEmpty else { return [0, 0, 0, 0, 0] }
        return (1...5).map { zone in Double(bands.filter { $0 == zone }.count) / Double(bands.count) }
    }

    @MainActor
    static func loadRouteMapEntries(repo: Repository, zoneSet: HRZoneSet, period: RouteMapPeriod,
                                    now: Date = Date()) async -> [RouteMapEntry] {
        let routes = RouteStore.loadMap()
        var out: [RouteMapEntry] = []
        for item in routeKeysInPeriod(Array(routes.keys), period: period, now: now) {
            guard let route = routes[item.key] else { continue }
            let plain = RouteMath.decode(route.polyline)
            guard plain.count >= 2 else { continue }
            let points = RoutePointStore.load(for: item.key) ?? []
            let steps = WorkoutStepStore.load(startTs: item.startTs, sport: item.sport) ?? []
            var zoneSegments = RouteColoring.plainSegments(plain)
            var cadenceSegments: [RouteBandSegment] = []
            var shares: [Double] = [0, 0, 0, 0, 0]
            var duration = 0
            if points.count >= 2, let first = points.first, let last = points.last {
                duration = Int((last.tMs - first.tMs) / 1000)
                let hr = await repo.hrSamples(from: Int(first.tMs / 1000) - 60, to: Int(last.tMs / 1000) + 60,
                                              limit: 20_000)
                let bands = RouteColoring.zoneBandsForRoute(points, hr: hr, zoneSet: zoneSet)
                zoneSegments = RouteColoring.routeBandSegments(points, bands: bands)
                shares = zoneShares(bands)
                if !steps.isEmpty {
                    cadenceSegments = RouteColoring.routeBandSegments(
                        points, bands: RouteColoring.cadenceBandsForRoute(points, steps: steps))
                }
            }
            out.append(RouteMapEntry(id: item.key, startTs: item.startTs, sport: item.sport,
                                     distanceM: route.distanceM, durationS: duration,
                                     zoneSegments: zoneSegments, cadenceSegments: cadenceSegments,
                                     zoneShares: shares, steps: steps.last?.steps))
        }
        return out
    }
}

struct RouteMapScreen: View {
    @EnvironmentObject private var repo: Repository
    @StateObject private var profile = ProfileStore()
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.distanceSystemKey) private var distanceSystemRaw = ""

    @State private var period: RouteMapPeriod = .days30
    @State private var mode: RouteColorMode = .zones
    @State private var selected: String?
    @State private var entries: [RouteMapEntry] = []
    @State private var loaded = false

    private var distanceSystem: UnitSystem {
        UnitPrefs.resolveDistance(system: UnitSystem(rawValue: unitSystemRaw) ?? .metric,
                                  override: distanceSystemRaw)
    }

    /// Cadence only when at least one workout of the period has the phone's steps.
    private var hasCadence: Bool { entries.contains { !$0.cadenceSegments.isEmpty } }
    private var effectiveMode: RouteColorMode { hasCadence ? mode : .zones }

    var body: some View {
        ScreenScaffold(title: "Map", subtitle: "Your outdoor workouts") {
            Picker("Period", selection: $period) {
                ForEach(RouteMapPeriod.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if entries.isEmpty {
                if loaded { emptyState }
            } else {
                mapCard
                listCard
            }
            Text("Only outdoor workouts started in NOOP have a route. The routes stay on this iPhone.")
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task(id: period) { await reloadRouteMap() }
    }

    private func reloadRouteMap() async {
        let loadedEntries = await RouteMapReader.loadRouteMapEntries(repo: repo, zoneSet: profile.hrZoneSet,
                                                                     period: period)
        entries = loadedEntries
        if let selected, !loadedEntries.contains(where: { $0.id == selected }) { self.selected = nil }
        loaded = true
    }

    // MARK: - Map

    private var mapRoutes: [ColoredMapRoute] {
        entries.map { entry in
            ColoredMapRoute(id: entry.id,
                            segments: effectiveMode == .cadence && !entry.cadenceSegments.isEmpty
                                ? entry.cadenceSegments : entry.zoneSegments,
                            dimmed: selected != nil && selected != entry.id)
        }
    }

    private var summary: String {
        if let selected, let entry = entries.first(where: { $0.id == selected }) {
            return "\(WorkoutSource.displaySport(entry.sport)) · \(Self.routeDayLabel(entry.startTs))"
        }
        let meters = entries.reduce(0) { $0 + $1.distanceM }
        return String(localized: "\(entries.count) workouts") + " · "
            + UnitFormatter.distanceFromMeters(meters, system: distanceSystem)
    }

    private var mapCard: some View {
        NoopCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                ColoredRouteMap(routes: mapRoutes, mode: effectiveMode, showsEnds: entries.count == 1)
                    .frame(height: 330)
                    .clipShape(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
                    .accessibilityLabel(Text(verbatim: summary))
                VStack(alignment: .leading, spacing: 10) {
                    Text(verbatim: summary)
                        .font(StrandFont.subhead.weight(.semibold))
                        .foregroundStyle(StrandPalette.textPrimary)
                    if hasCadence {
                        Picker("Colour", selection: $mode) {
                            ForEach(RouteColorMode.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    RouteColorLegend(mode: effectiveMode)
                }
                .padding(NoopMetrics.cardPadding)
            }
        }
    }

    // MARK: - List

    private var listCard: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            SectionHeader("Workouts")
            NoopCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(entries) { entry in
                        Button {
                            selected = selected == entry.id ? nil : entry.id
                        } label: {
                            row(entry)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected == entry.id ? .isSelected : [])
                        if entry.id != entries.last?.id {
                            Divider().overlay(StrandPalette.hairline)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
            }
            Text("Tap a workout to see it alone on the map.")
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textTertiary)
        }
    }

    private func row(_ entry: RouteMapEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: WorkoutSource.displaySport(entry.sport))
                    .font(StrandFont.body.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                Spacer(minLength: 8)
                Text(verbatim: Self.routeDayLabel(entry.startTs))
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            Text(verbatim: figures(entry))
                .font(StrandFont.subhead)
                .monospacedDigit()
                .foregroundStyle(StrandPalette.textSecondary)
            if entry.zoneShares.contains(where: { $0 > 0 }) {
                GeometryReader { geometry in
                    HStack(spacing: 2) {
                        ForEach(0..<5, id: \.self) { index in
                            Capsule()
                                .fill(StrandPalette.hrZoneColor(index + 1))
                                .frame(width: max(0, geometry.size.width * entry.zoneShares[index] - 2))
                        }
                    }
                }
                .frame(height: 6)
                .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, NoopMetrics.cardPadding)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected == entry.id ? StrandPalette.textPrimary.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
    }

    private func figures(_ entry: RouteMapEntry) -> String {
        var parts = [UnitFormatter.distanceFromMeters(entry.distanceM, system: distanceSystem)]
        if entry.durationS > 0 { parts.append(ActiveWorkoutClock.clock(entry.durationS)) }
        if let steps = entry.steps { parts.append(String(localized: "\(LiveWorkoutDashboard.groupedSteps(steps)) steps")) }
        return parts.joined(separator: " · ")
    }

    private var emptyState: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("No route yet")
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                Text("Start a walk, a run or a hike outdoors from the + of Today: its route appears here, coloured by your heart-rate zones.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private static func routeDayLabel(_ ts: Int) -> String {
        Date(timeIntervalSince1970: TimeInterval(ts)).formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }
}
