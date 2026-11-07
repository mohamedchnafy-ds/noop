import SwiftUI
import StrandDesign
#if canImport(MapKit)
import MapKit
#endif

// MARK: - A route map drawn by colour (personal fork, chantier 14)
//
// The route cut into stretches of one band (`RouteColoring`): each stretch is its own polyline, stroked in
// the band's colour, so a run reads its heart-rate zones (or its cadence) on the map itself. One map for
// the workout detail (one route, start and finish marked) and for the Map screen (every route, the one
// selected drawn full, the others faded). The route never leaves the device; MapKit only fetches tiles.

/// One route on the map.
struct ColoredMapRoute: Equatable {
    var id: String
    var segments: [RouteBandSegment]
    /// Drawn faded (another route is selected).
    var dimmed: Bool = false
}

/// What the bands of a map mean, and so their colours.
enum RouteColorMode: String, CaseIterable, Identifiable {
    case zones, cadence
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .zones: return "Heart-rate zones"
        case .cadence: return "Cadence"
        }
    }

    /// The colour of a band: the app's zone colours, or one cyan from pale (slow) to full (fast). Band 0
    /// (no value) is grey.
    func color(_ band: Int) -> Color {
        guard band >= 1 else { return StrandPalette.textTertiary }
        switch self {
        case .zones: return StrandPalette.hrZoneColor(band)
        case .cadence: return StrandPalette.metricCyan.opacity(RouteColorMode.cadenceOpacity[min(band, 5) - 1])
        }
    }

    static let cadenceOpacity: [Double] = [0.35, 0.5, 0.65, 0.82, 1.0]
}

/// The legend under a coloured map: Z1…Z5, or slow → fast.
struct RouteColorLegend: View {
    let mode: RouteColorMode

    var body: some View {
        HStack(spacing: 10) {
            switch mode {
            case .zones:
                ForEach(1...5, id: \.self) { zone in
                    swatch(mode.color(zone))
                    Text("Z\(zone)")
                }
            case .cadence:
                Text("Slow")
                ForEach(1...5, id: \.self) { band in swatch(mode.color(band)) }
                Text("Fast")
            }
            Spacer(minLength: 0)
        }
        .font(StrandFont.footnote)
        .foregroundStyle(StrandPalette.textSecondary)
        .accessibilityElement(children: .combine)
    }

    private func swatch(_ color: Color) -> some View {
        Capsule().fill(color).frame(width: 14, height: 5).accessibilityHidden(true)
    }
}

#if canImport(MapKit)
#if canImport(UIKit)
import UIKit
private typealias ColoredPlatformColor = UIColor
#elseif canImport(AppKit)
import AppKit
private typealias ColoredPlatformColor = NSColor
#endif

/// A polyline that knows its band and whether it is faded, so the renderer can stroke it.
private final class BandPolyline: MKPolyline {
    var band = 0
    var dimmed = false
}

/// `RouteMapRepresentable` is the platform representable `WorkoutDetailView.swift` declares.
struct ColoredRouteMap: RouteMapRepresentable {
    let routes: [ColoredMapRoute]
    var mode: RouteColorMode = .zones
    /// Start and finish markers (one route only).
    var showsEnds = true

    func makeCoordinator() -> Coordinator { Coordinator() }

    private func makeMap(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.showsUserLocation = false
        configure(map, coordinator: context.coordinator, reframe: true)
        return map
    }

    private func configure(_ map: MKMapView, coordinator: Coordinator, reframe: Bool) {
        coordinator.mode = mode
        map.removeOverlays(map.overlays)
        map.removeAnnotations(map.annotations)
        var frame: MKMapRect?
        var focus: MKMapRect?
        // Faded routes first, so the selected one is drawn on top.
        for route in routes.sorted(by: { $0.dimmed && !$1.dimmed }) {
            for segment in route.segments where segment.points.count >= 2 {
                var coords = segment.points.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
                let line = BandPolyline(coordinates: &coords, count: coords.count)
                line.band = segment.band
                line.dimmed = route.dimmed
                map.addOverlay(line)
                frame = frame.map { $0.union(line.boundingMapRect) } ?? line.boundingMapRect
                if !route.dimmed { focus = focus.map { $0.union(line.boundingMapRect) } ?? line.boundingMapRect }
            }
        }
        if showsEnds, routes.count == 1, let first = routes[0].segments.first?.points.first,
           let last = routes[0].segments.last?.points.last {
            let start = MKPointAnnotation()
            start.coordinate = CLLocationCoordinate2D(latitude: first.lat, longitude: first.lon)
            start.title = String(localized: "Start")
            let end = MKPointAnnotation()
            end.coordinate = CLLocationCoordinate2D(latitude: last.lat, longitude: last.lon)
            end.title = String(localized: "Finish")
            map.addAnnotations([start, end])
        }
        let target = routes.contains(where: \.dimmed) ? (focus ?? frame) : frame
        // Reframe on first draw and when the routes or the selection change, not on every update.
        let key = routes.map { "\($0.id):\($0.dimmed)" }.joined(separator: ",")
        if let target, reframe || coordinator.framedKey != key {
            coordinator.framedKey = key
            map.setVisibleMapRect(target, edgePadding: edgeInsets, animated: !reframe)
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var mode: RouteColorMode = .zones
        var framedKey = ""

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? BandPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolylineRenderer(polyline: line)
            renderer.strokeColor = ColoredPlatformColor(mode.color(line.band))
                .withAlphaComponent(line.dimmed ? 0.25 : 1)
            renderer.lineWidth = line.dimmed ? 3 : 5
            renderer.lineJoin = .round
            renderer.lineCap = .round
            return renderer
        }
    }

    #if canImport(UIKit)
    private var edgeInsets: UIEdgeInsets { UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24) }
    func makeUIView(context: Context) -> MKMapView { makeMap(context: context) }
    func updateUIView(_ map: MKMapView, context: Context) {
        configure(map, coordinator: context.coordinator, reframe: false)
    }
    #elseif canImport(AppKit)
    private var edgeInsets: NSEdgeInsets { NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24) }
    func makeNSView(context: Context) -> MKMapView { makeMap(context: context) }
    func updateNSView(_ map: MKMapView, context: Context) {
        configure(map, coordinator: context.coordinator, reframe: false)
    }
    #endif
}
#else
struct ColoredRouteMap: View {
    let routes: [ColoredMapRoute]
    var mode: RouteColorMode = .zones
    var showsEnds = true
    var body: some View { Color.clear }
}
#endif
