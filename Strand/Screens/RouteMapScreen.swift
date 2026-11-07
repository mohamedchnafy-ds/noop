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
    case day, week, days30, days90, all
    var id: String { rawValue }

    /// The periods the layered map offers (Carte v2): the points stop at 90 days.
    static let mapChoices: [RouteMapPeriod] = [.day, .week, .days30, .days90]

    var title: LocalizedStringKey {
        switch self {
        case .day: return "Day"
        case .week: return "7D"
        case .days30: return "30D"
        case .days90: return "90D"
        case .all: return "All"
        }
    }

    var days: Int? {
        switch self {
        case .day: return 1
        case .week: return 7
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


/// What the layered map colours by (Carte v2): one choice for every layer that can show it.
enum MapTint: String, CaseIterable, Identifiable {
    case heartRate, stress, hrv, recovery, cadence
    var id: String { rawValue }

    var chipTitle: LocalizedStringKey {
        switch self {
        case .heartRate: return "HR"
        case .stress: return "Stress"
        case .hrv: return "HRV"
        case .recovery: return "Recov."
        case .cadence: return "Cadence"
        }
    }

    /// The place figure shown for this choice (cadence has none: places keep HRV).
    var placeLayer: PlaceLayer {
        switch self {
        case .heartRate: return .heartRate
        case .stress: return .stress
        case .hrv, .cadence: return .hrv
        case .recovery: return .recovery
        }
    }

    /// Points are coloured by stress or, for every other choice, by heart rate.
    var pointsByStress: Bool { self == .stress }
}

struct RouteMapScreen: View {
    @EnvironmentObject private var repo: Repository
    @StateObject private var profile = ProfileStore()
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.distanceSystemKey) private var distanceSystemRaw = ""
    @AppStorage(PlaceTrackingSettings.enabledKey) private var placesEnabled = false

    // Layers and colour, kept between openings.
    @AppStorage("map.layers.routes") private var showRoutes = true
    @AppStorage("map.layers.places") private var showPlaces = true
    @AppStorage("map.layers.points") private var showPoints = true
    @AppStorage("map.tint") private var tintRaw = MapTint.heartRate.rawValue

    @State private var period: RouteMapPeriod = .week
    @State private var entries: [RouteMapEntry] = []
    @State private var routesLoaded = false
    @State private var selectedRoute: String?

    @State private var placeSummaries: [PlaceSummary] = []
    @State private var placesLoaded = false
    /// Stress is scored only once it has been asked for (the slowest read).
    @State private var placesStressScored = false
    @State private var selectedPlace: String?
    @AppStorage(PlaceLog.revisionKey) private var placesRevision = 0
    @AppStorage(PlaceLog.placeRevisionKey) private var placeRevision = 0

    @State private var pointMarks: [PlacePointMark] = []
    @State private var selectedTs: Int?

    // The day's frise.
    @State private var stripDay = Calendar.current.startOfDay(for: Date())
    @State private var stripMode: MapStripMode = .heartRate
    @State private var timeline: PlaceDayTimeline?
    @State private var dayPoints: [PlacePointMark] = []

    @State private var fullScreen = false

    private var tint: MapTint { MapTint(rawValue: tintRaw) ?? .heartRate }

    private var distanceSystem: UnitSystem {
        UnitPrefs.resolveDistance(system: UnitSystem(rawValue: unitSystemRaw) ?? .metric,
                                  override: distanceSystemRaw)
    }

    /// Cadence only when at least one workout of the period has the phone's steps.
    private var hasCadence: Bool { entries.contains { !$0.cadenceSegments.isEmpty } }
    private var routeMode: RouteColorMode { tint == .cadence && hasCadence ? .cadence : .zones }
    private var placesOn: Bool { showPlaces && placesEnabled }
    private var pointsOn: Bool { showPoints && placesEnabled }

    var body: some View {
        ScreenScaffold(title: "Map", trailing: {
            NavigationLink {
                PlacesSettingsView()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Places settings"))
        }) {
            mapCard
            tintChips
            Picker("Period", selection: $period) {
                ForEach(RouteMapPeriod.mapChoices) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if placesEnabled { stripCard } else { PlacesEnableCard() }
            if placesOn { standoutsCard }
            if placesOn, !placeSummaries.isEmpty {
                PlacesListCard(summaries: placeSummaries, layer: tint.placeLayer)
            }
            if showRoutes { routesSection }
            Text("Places cover the last 90 days. A difference is not a cause: a place mostly reflects what you do there. Everything stays on this iPhone.")
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task(id: period) { await reloadRoutes() }
        .task(id: placesTaskKey) { await reloadPlaces() }
        .task(id: pointsTaskKey) { await reloadPoints() }
        .task(id: stripTaskKey) { await reloadStrip() }
        #if os(iOS)
        .fullScreenCover(isPresented: $fullScreen) { fullScreenMap }
        #else
        .sheet(isPresented: $fullScreen) { fullScreenMap.frame(minWidth: 720, minHeight: 560) }
        #endif
    }

    // MARK: - Loading

    private var placeStressWanted: Bool { tint == .stress || placesStressScored }

    private var placesTaskKey: String {
        placesOn ? "places-\(placeRevision)-\(placeStressWanted)" : "places-off"
    }

    private var pointsTaskKey: String {
        pointsOn ? "points-\(period.rawValue)-\(placesRevision)-\(tint.pointsByStress)" : "points-off"
    }

    private var stripTaskKey: String {
        placesEnabled ? "strip-\(Int(stripDay.timeIntervalSince1970))-\(stripMode.rawValue)-\(placesRevision)" : "strip-off"
    }

    private func reloadRoutes() async {
        let loaded = await RouteMapReader.loadRouteMapEntries(repo: repo, zoneSet: profile.hrZoneSet, period: period)
        guard !Task.isCancelled else { return }
        entries = loaded
        if let selectedRoute, !loaded.contains(where: { $0.id == selectedRoute }) { self.selectedRoute = nil }
        routesLoaded = true
    }

    /// The last figures are drawn at once, then the fresh ones (past days come from the day store).
    private func reloadPlaces() async {
        guard placesOn else { return }
        if placeSummaries.isEmpty, let snapshot = PlaceMapCacheFiles.loadPlaceSnapshot() {
            placeSummaries = snapshot.summaries
            placesLoaded = true
        }
        let withStress = placeStressWanted
        var summaries = await PlaceMapReader.loadPlaceSummaries(repo: repo, includeStress: withStress)
        guard !Task.isCancelled else { return }
        if !withStress { summaries = PlaceMapFreeze.carryPlaceStress(from: placeSummaries, into: summaries) }
        placeSummaries = summaries
        placesLoaded = true
        if withStress { placesStressScored = true }
        PlaceMapCacheFiles.savePlaceSnapshot(summaries)
    }

    private func reloadPoints() async {
        guard pointsOn else {
            pointMarks = []
            return
        }
        let days = min(period.days ?? 90, 90)
        let marks = await PlaceMapReader.loadPointMarks(repo: repo, days: days, includeStress: tint.pointsByStress)
        guard !Task.isCancelled else { return }
        pointMarks = marks
    }

    private func reloadStrip() async {
        guard placesEnabled else { return }
        let day = stripDay
        let calendar = Calendar.current
        let end = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
        let loaded = await PlaceMapReader.loadDayTimeline(repo: repo, dayStart: day, includeStress: stripMode == .stress)
        let marks = await PlaceMapReader.loadPointMarks(repo: repo, from: day, to: end, includeStress: false)
        guard !Task.isCancelled, day == stripDay else { return }
        timeline = loaded
        dayPoints = marks
    }

    // MARK: - Layers

    private var mapLayers: LayeredMapLayers {
        var layers = LayeredMapLayers(routeMode: routeMode)
        if showRoutes {
            layers.routes = entries.map { entry in
                ColoredMapRoute(id: entry.id,
                                segments: routeMode == .cadence && !entry.cadenceSegments.isEmpty
                                    ? entry.cadenceSegments : entry.zoneSegments,
                                dimmed: selectedRoute != nil && selectedRoute != entry.id)
            }
        }
        if placesOn {
            let layer = tint.placeLayer
            layers.places = placeSummaries.map { summary in
                let figure = summary.figure(layer)
                return LayeredMapPlace(id: summary.id, lat: summary.place.lat, lon: summary.place.lon,
                                       diameter: Self.discDiameter(visits: summary.visits),
                                       color: PlaceVerdictStyle.color(figure.verdict),
                                       muted: PlaceVerdictStyle.hollow(figure.verdict), title: summary.name,
                                       value: PlaceFigureFormat.tagText(figure, layer: layer),
                                       selected: selectedPlace == summary.id)
            }
        }
        if pointsOn {
            layers.points = pointMarks.map { mark in
                LayeredMapPoint(ts: mark.ts, lat: mark.lat, lon: mark.lon,
                                color: PointMarkStyle.color(mark, byStress: tint.pointsByStress),
                                hollow: PointMarkStyle.hollow(mark, byStress: tint.pointsByStress))
            }
        }
        return layers
    }

    /// A disc from 14 to 28 pt across, by the number of stays.
    static func discDiameter(visits: Int) -> CGFloat {
        14 + min(CGFloat(Double(max(visits, 0)).squareRoot()) * 3, 14)
    }

    private var stripPoints: [MapStripPoint] {
        dayPoints.map { MapStripPoint(ts: Int($0.ts / 1000), lat: $0.lat, lon: $0.lon) }
    }

    private var cursor: LayeredMapCursor? {
        guard let selectedTs else { return nil }
        return MapDayStripMath.cursorPosition(at: selectedTs, points: stripPoints)
    }

    private func handleMapTap(_ tap: LayeredMapTap) {
        switch tap {
        case .place(let id):
            selectedPlace = selectedPlace == id ? nil : id
        case .point(let ts):
            selectedPlace = nil
            let seconds = Int(ts / 1000)
            let date = Date(timeIntervalSince1970: TimeInterval(seconds))
            let day = Calendar.current.startOfDay(for: date)
            if day != stripDay { stripDay = day }
            selectedTs = seconds
        case .nothing:
            selectedPlace = nil
            selectedTs = nil
        }
    }

    // MARK: - Map card

    private var mapCard: some View {
        NoopCard(padding: 0) {
            mapStack(fullScreen: false)
                .frame(height: 380)
                .clipShape(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
        }
    }

    private func mapStack(fullScreen: Bool) -> some View {
        ZStack {
            LayeredPlaceMap(layers: mapLayers, cursor: cursor, onTap: { handleMapTap($0) })
                .ignoresSafeArea(.container, edges: fullScreen ? .all : [])
                .accessibilityLabel(Text("Map"))
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 8) {
                    selectionCard(linked: !fullScreen)
                    Spacer(minLength: 0)
                    VStack(spacing: 8) {
                        layersMenu
                        if fullScreen {
                            mapButton("xmark", label: "Close") { self.fullScreen = false }
                        } else {
                            mapButton("arrow.up.left.and.arrow.down.right", label: "Full screen") { self.fullScreen = true }
                        }
                    }
                }
                Spacer(minLength: 0)
                HStack {
                    MapLayersLegend(routes: showRoutes && !entries.isEmpty, routeMode: routeMode,
                                    places: placesOn && !placeSummaries.isEmpty, placeLayer: tint.placeLayer,
                                    points: pointsOn && !pointMarks.isEmpty, pointsByStress: tint.pointsByStress)
                    Spacer(minLength: 0)
                }
            }
            .padding(10)
            // In full screen the colour chips sit at the bottom: the legend stays above them.
            .padding(.bottom, fullScreen ? 76 : 0)
        }
    }

    private func mapButton(_ symbol: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(StrandPalette.textPrimary)
                .frame(width: 38, height: 38)
                .background(Circle().fill(StrandPalette.surfaceBase.opacity(0.78)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }

    private var layersMenu: some View {
        Menu {
            Toggle(isOn: $showRoutes) { Label("Routes", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
            if placesEnabled {
                Toggle(isOn: $showPlaces) { Label("Places", systemImage: "mappin.circle") }
                Toggle(isOn: $showPoints) { Label("Points", systemImage: "circle.grid.2x1") }
            }
        } label: {
            Image(systemName: "square.3.layers.3d")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(StrandPalette.textPrimary)
                .frame(width: 38, height: 38)
                .background(Circle().fill(StrandPalette.surfaceBase.opacity(0.78)))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(Text("Layers"))
    }

    @ViewBuilder
    private func selectionCard(linked: Bool) -> some View {
        if let id = selectedPlace, let summary = placeSummaries.first(where: { $0.id == id }) {
            PlaceSelectionCard(summary: summary, layer: tint.placeLayer, linked: linked)
        } else if let ts = selectedTs, let mark = nearestMark(to: ts) {
            PointSelectionCard(mark: mark)
        }
    }

    /// The point of the period or of the frise's day nearest the moment shown, within 15 minutes.
    private func nearestMark(to ts: Int) -> PlacePointMark? {
        let pool = dayPoints.isEmpty ? pointMarks : dayPoints
        guard let best = pool.min(by: { abs(Int($0.ts / 1000) - ts) < abs(Int($1.ts / 1000) - ts) }),
              abs(Int(best.ts / 1000) - ts) <= 15 * 60 else { return nil }
        return best
    }

    private var tintChips: some View {
        HStack(spacing: 6) {
            ForEach(MapTint.allCases.filter { $0 != .cadence || hasCadence }) { item in
                Button { tintRaw = item.rawValue } label: {
                    Text(item.chipTitle)
                        .font(StrandFont.subhead.weight(.semibold))
                        .foregroundStyle(tint == item ? StrandPalette.surfaceBase : StrandPalette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(Capsule().fill(tint == item ? StrandPalette.textPrimary : StrandPalette.surfaceOverlay))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tint == item ? .isSelected : [])
            }
        }
    }

    // MARK: - Full screen

    private var fullScreenMap: some View {
        ZStack(alignment: .bottom) {
            mapStack(fullScreen: true)
            tintChips
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
        }
        .background(StrandPalette.surfaceBase.ignoresSafeArea())
        .environmentObject(repo)
    }

    // MARK: - Frise

    private var stripCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button { shiftStripDay(-1) } label: { Image(systemName: "chevron.left").frame(width: 32, height: 32) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Previous day"))
                Text(verbatim: stripDayLabel)
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .lineLimit(1)
                Button { shiftStripDay(1) } label: { Image(systemName: "chevron.right").frame(width: 32, height: 32) }
                    .buttonStyle(.plain)
                    .disabled(Calendar.current.isDateInToday(stripDay))
                    .accessibilityLabel(Text("Next day"))
                Spacer(minLength: 8)
                Picker("Curve", selection: $stripMode) {
                    Text("HR").tag(MapStripMode.heartRate)
                    Text("Stress").tag(MapStripMode.stress)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 150)
            }
            .foregroundStyle(StrandPalette.textPrimary)
            if let timeline, !(timeline.heartRate.isEmpty && timeline.stress.isEmpty && dayPoints.isEmpty) {
                MapDayStrip(timeline: timeline, mode: stripMode, points: stripPoints, selectedTs: $selectedTs)
            } else if timeline != nil {
                Text("Nothing recorded this day.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
        }
        .padding(16)
        .background(NoopPanelSurface(cornerRadius: 26))
    }

    private var stripDayLabel: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(stripDay) { return String(localized: "Today") }
        if calendar.isDateInYesterday(stripDay) { return String(localized: "Yesterday") }
        return stripDay.formatted(Date.FormatStyle().weekday(.abbreviated).day().month(.abbreviated))
    }

    private func shiftStripDay(_ by: Int) {
        let calendar = Calendar.current
        guard let next = calendar.date(byAdding: .day, value: by, to: stripDay),
              next <= calendar.startOfDay(for: Date()) else { return }
        stripDay = next
        selectedTs = nil
    }

    // MARK: - Ce qui ressort

    private var standoutsCard: some View {
        let standouts = PlaceStandouts.placeStandouts(placeSummaries)
        return VStack(alignment: .leading, spacing: 10) {
            Text("What stands out").font(StrandFont.sectionTitle).foregroundStyle(StrandPalette.textPrimary)
            if standouts.isEmpty {
                Group {
                    if placesLoaded {
                        Text("Nothing stands out beyond the noise yet.")
                    } else {
                        Text("Reading your places…")
                    }
                }
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(standouts.enumerated()), id: \.element.id) { index, standout in
                        if index > 0 { Rectangle().fill(StrandPalette.hairline).frame(height: 1) }
                        StandoutRow(standout: standout)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .background(NoopPanelSurface(cornerRadius: 26))
            }
            Text("A difference is listed only when it is larger than its margin of error and than the usual spread around your normal.")
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Routes list

    @ViewBuilder
    private var routesSection: some View {
        if entries.isEmpty {
            if routesLoaded { noRouteCard }
        } else {
            VStack(alignment: .leading, spacing: NoopMetrics.gap) {
                SectionHeader("Workouts", trailing: routesSummary)
                NoopCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(entries) { entry in
                            Button {
                                selectedRoute = selectedRoute == entry.id ? nil : entry.id
                            } label: {
                                routeRow(entry)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selectedRoute == entry.id ? .isSelected : [])
                            if entry.id != entries.last?.id {
                                Divider().overlay(StrandPalette.hairline)
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
                }
                Text("Tap a workout to see it alone on the map. Only outdoor workouts started in NOOP have a route.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var routesSummary: String {
        let meters = entries.reduce(0) { $0 + $1.distanceM }
        return String(localized: "\(entries.count) workouts") + " · "
            + UnitFormatter.distanceFromMeters(meters, system: distanceSystem)
    }

    private func routeRow(_ entry: RouteMapEntry) -> some View {
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
            Text(verbatim: routeFigures(entry))
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
        .background(selectedRoute == entry.id ? StrandPalette.textPrimary.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
    }

    private func routeFigures(_ entry: RouteMapEntry) -> String {
        var parts = [UnitFormatter.distanceFromMeters(entry.distanceM, system: distanceSystem)]
        if entry.durationS > 0 { parts.append(ActiveWorkoutClock.clock(entry.durationS)) }
        if let steps = entry.steps { parts.append(String(localized: "\(LiveWorkoutDashboard.groupedSteps(steps)) steps")) }
        return parts.joined(separator: " · ")
    }

    private var noRouteCard: some View {
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
