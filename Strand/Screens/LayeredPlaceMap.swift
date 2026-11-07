import SwiftUI
import StrandDesign
#if canImport(MapKit)
import MapKit
#endif

// MARK: - The Map's layered map (personal fork, chantier 14, Carte v2)
//
// One map for everything the Map screen shows at once: the workout routes (coloured by heart-rate zone or
// cadence), the places (filled discs, their value written under them), the points of the period (small
// dots joined by a thin line, in the order they were kept) and a cursor (the moment chosen on the day's
// frise). The layers are redrawn only when they change; moving the cursor moves one annotation. Taps
// report the place or the point under the finger. Positions never leave the device; MapKit only fetches
// the tiles of the quiet base (`QuietMapLook`).

/// One place on the layered map.
struct LayeredMapPlace: Equatable {
    var id: String
    var lat: Double
    var lon: Double
    /// Disc diameter on screen, points.
    var diameter: CGFloat
    var color: Color
    /// No verdict (too few, nothing to compare): drawn paler.
    var muted: Bool
    var title: String
    /// « VFC +4 ms », empty when there is nothing to write.
    var value: String
    var selected: Bool = false
}

/// One point on the layered map.
struct LayeredMapPoint: Equatable {
    var ts: Int64
    var lat: Double
    var lon: Double
    var color: Color
    /// No value (no heart rate, stress unscored): a ring only.
    var hollow: Bool
}

/// Everything drawn except the cursor.
struct LayeredMapLayers: Equatable {
    var routes: [ColoredMapRoute] = []
    var routeMode: RouteColorMode = .zones
    var places: [LayeredMapPlace] = []
    var points: [LayeredMapPoint] = []
}

/// Where the frise's moment is on the map.
struct LayeredMapCursor: Equatable {
    var lat: Double
    var lon: Double
}

/// What a tap on the layered map hit.
enum LayeredMapTap: Equatable {
    case place(String)
    case point(Int64)
    case nothing
}

enum LayeredMapGeometry {
    /// A gap this long between two points breaks the thin line (another day, the phone off…).
    static let pathBreakSeconds: Int64 = 3 * 3_600

    /// The points in time order, cut into runs wherever two points are further apart than
    /// `pathBreakSeconds`. PURE: tested in `MapDayStripTests`.
    static func pointPathRuns(_ points: [LayeredMapPoint]) -> [[LayeredMapPoint]] {
        var runs: [[LayeredMapPoint]] = []
        var current: [LayeredMapPoint] = []
        for point in points.sorted(by: { $0.ts < $1.ts }) {
            if let last = current.last, (point.ts - last.ts) / 1000 > pathBreakSeconds {
                if current.count >= 2 { runs.append(current) }
                current = []
            }
            current.append(point)
        }
        if current.count >= 2 { runs.append(current) }
        return runs
    }
}

#if canImport(MapKit)
#if canImport(UIKit)
import UIKit
private typealias LayeredPlatformColor = UIColor
private typealias LayeredPlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
private typealias LayeredPlatformColor = NSColor
private typealias LayeredPlatformImage = NSImage
#endif

private final class LayeredRouteLine: MKPolyline {
    var color: LayeredPlatformColor = .gray
    var width: CGFloat = 4
}

private final class LayeredPathLine: MKPolyline {}

/// Every point of the period in one overlay, drawn as small discs of a fixed size on screen.
private final class LayeredPointCloud: NSObject, MKOverlay {
    struct Dot {
        var mapPoint: MKMapPoint
        var color: CGColor
        var hollow: Bool
    }
    let dots: [Dot]
    var boundingMapRect: MKMapRect
    var coordinate: CLLocationCoordinate2D

    init(dots: [Dot]) {
        self.dots = dots
        var rect = MKMapRect.null
        for dot in dots { rect = rect.union(MKMapRect(origin: dot.mapPoint, size: MKMapSize(width: 1, height: 1))) }
        boundingMapRect = rect
        coordinate = rect.isNull ? CLLocationCoordinate2D() : MKMapPoint(x: rect.midX, y: rect.midY).coordinate
    }
}

private final class LayeredPointCloudRenderer: MKOverlayRenderer {
    /// Disc radius on screen, points.
    static let radius: CGFloat = 4

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let cloud = overlay as? LayeredPointCloud else { return }
        let r = Self.radius / zoomScale
        let reach = Double(r) * 2
        let area = mapRect.insetBy(dx: -reach, dy: -reach)
        context.setLineWidth(1.5 / zoomScale)
        for dot in cloud.dots where area.contains(dot.mapPoint) {
            let centre = point(for: dot.mapPoint)
            let disc = CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2)
            if dot.hollow {
                context.setStrokeColor(dot.color)
                context.strokeEllipse(in: disc.insetBy(dx: 0.75 / zoomScale, dy: 0.75 / zoomScale))
            } else {
                context.setFillColor(dot.color)
                context.fillEllipse(in: disc)
            }
        }
    }
}

private final class LayeredPlaceMark: MKPointAnnotation {
    var placeId = ""
    var image: LayeredPlatformImage?
    var discCentreOffset: CGFloat = 0
}

private final class LayeredCursorMark: MKPointAnnotation {}

/// The disc and the label of a place, drawn once into an image for its annotation view.
private struct LayeredPlaceTag: View {
    let place: LayeredMapPlace

    var body: some View {
        VStack(spacing: 3) {
            Circle()
                .fill(place.color.opacity(place.muted ? 0.45 : 0.92))
                .overlay(Circle().stroke(place.selected ? StrandPalette.textPrimary : StrandPalette.surfaceBase.opacity(0.6),
                                         lineWidth: place.selected ? 2.5 : 1))
                .frame(width: place.diameter, height: place.diameter)
            VStack(spacing: 0) {
                Text(verbatim: place.title)
                    .font(StrandFont.caption.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                if !place.value.isEmpty {
                    Text(verbatim: place.value)
                        .font(StrandFont.number(11, weight: .semibold))
                        .foregroundStyle(place.muted ? StrandPalette.textSecondary : place.color)
                }
            }
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(StrandPalette.surfaceBase.opacity(0.72)))
        }
        .environment(\.colorScheme, .dark)
    }
}

private struct LayeredCursorDot: View {
    var body: some View {
        Circle()
            .fill(StrandPalette.textPrimary)
            .overlay(Circle().stroke(StrandPalette.surfaceBase, lineWidth: 3))
            .frame(width: 18, height: 18)
            .padding(2)
            .environment(\.colorScheme, .dark)
    }
}

struct LayeredPlaceMap: RouteMapRepresentable {
    let layers: LayeredMapLayers
    var cursor: LayeredMapCursor?
    var onTap: ((LayeredMapTap) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    private func makeMap(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.showsUserLocation = false
        QuietMapLook.applyQuietMapLook(to: map)
        context.coordinator.map = map
        #if canImport(UIKit)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        map.addGestureRecognizer(tap)
        #elseif canImport(AppKit)
        let click = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        map.addGestureRecognizer(click)
        #endif
        configure(map, coordinator: context.coordinator, first: true)
        return map
    }

    @MainActor
    private func configure(_ map: MKMapView, coordinator: Coordinator, first: Bool) {
        coordinator.onTap = onTap
        if first || coordinator.drawn != layers {
            redraw(map, coordinator: coordinator)
            coordinator.drawn = layers
        }
        moveCursor(map, coordinator: coordinator)
        // Reframe on first draw and when what is drawn changes (layers, period, selection), not when a
        // value or the cursor changes.
        let key = frameKey
        if first || coordinator.framedKey != key, let target = frameRect {
            coordinator.framedKey = key
            map.setVisibleMapRect(target, edgePadding: edgeInsets, animated: !first)
        }
    }

    private var frameKey: String {
        let routes = layers.routes.map { "\($0.id):\($0.dimmed)" }.joined(separator: ",")
        let places = layers.places.map(\.id).joined(separator: ",")
        let points = "\(layers.points.count):\(layers.points.first?.ts ?? 0):\(layers.points.last?.ts ?? 0)"
        return routes + "|" + places + "|" + points
    }

    private var frameRect: MKMapRect? {
        var rect = MKMapRect.null
        var focus = MKMapRect.null
        func add(_ lat: Double, _ lon: Double) {
            let p = MKMapPoint(CLLocationCoordinate2D(latitude: lat, longitude: lon))
            rect = rect.union(MKMapRect(origin: p, size: MKMapSize(width: 1, height: 1)))
        }
        for route in layers.routes {
            for segment in route.segments {
                for p in segment.points {
                    add(p.lat, p.lon)
                    if !route.dimmed, layers.routes.contains(where: \.dimmed) {
                        let m = MKMapPoint(CLLocationCoordinate2D(latitude: p.lat, longitude: p.lon))
                        focus = focus.union(MKMapRect(origin: m, size: MKMapSize(width: 1, height: 1)))
                    }
                }
            }
        }
        for place in layers.places { add(place.lat, place.lon) }
        for point in layers.points { add(point.lat, point.lon) }
        let target = focus.isNull ? rect : focus
        guard !target.isNull else { return nil }
        // At least about 600 m across, so one place or one point is not drawn at street level.
        let minSide = 600 * MKMapPointsPerMeterAtLatitude(target.origin.coordinate.latitude)
        return target.insetBy(dx: -max(0, (minSide - target.width) / 2), dy: -max(0, (minSide - target.height) / 2))
    }

    @MainActor
    private func redraw(_ map: MKMapView, coordinator: Coordinator) {
        map.removeOverlays(map.overlays)
        map.removeAnnotations(map.annotations.filter { $0 is LayeredPlaceMark })
        // Routes: the faded ones first, so the selected one is on top.
        for route in layers.routes.sorted(by: { $0.dimmed && !$1.dimmed }) {
            for segment in route.segments where segment.points.count >= 2 {
                var coords = segment.points.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
                let line = LayeredRouteLine(coordinates: &coords, count: coords.count)
                line.color = LayeredPlatformColor(layers.routeMode.color(segment.band))
                    .withAlphaComponent(route.dimmed ? 0.25 : 1)
                line.width = route.dimmed ? 3 : 4.5
                map.addOverlay(line, level: .aboveRoads)
            }
        }
        // Points: a thin line in time order, then the dots.
        for run in LayeredMapGeometry.pointPathRuns(layers.points) {
            var coords = run.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
            map.addOverlay(LayeredPathLine(coordinates: &coords, count: coords.count), level: .aboveRoads)
        }
        if !layers.points.isEmpty {
            let dots = layers.points.map { point in
                LayeredPointCloud.Dot(mapPoint: MKMapPoint(CLLocationCoordinate2D(latitude: point.lat, longitude: point.lon)),
                                      color: LayeredPlatformColor(point.color).cgColor, hollow: point.hollow)
            }
            map.addOverlay(LayeredPointCloud(dots: dots), level: .aboveLabels)
        }
        // Places: one annotation each, its disc and label drawn into an image.
        let scale = displayScale(map)
        for place in layers.places.sorted(by: { !$0.selected && $1.selected }) {
            let mark = LayeredPlaceMark()
            mark.coordinate = CLLocationCoordinate2D(latitude: place.lat, longitude: place.lon)
            mark.placeId = place.id
            let renderer = ImageRenderer(content: LayeredPlaceTag(place: place))
            renderer.scale = scale
            #if canImport(UIKit)
            mark.image = renderer.uiImage
            #elseif canImport(AppKit)
            mark.image = renderer.nsImage
            #endif
            let height = mark.image?.size.height ?? place.diameter
            mark.discCentreOffset = (height - place.diameter) / 2
            map.addAnnotation(mark)
        }
    }

    @MainActor
    private func moveCursor(_ map: MKMapView, coordinator: Coordinator) {
        if cursor != nil, coordinator.cursorImage == nil {
            let renderer = ImageRenderer(content: LayeredCursorDot())
            renderer.scale = displayScale(map)
            #if canImport(UIKit)
            coordinator.cursorImage = renderer.uiImage
            #elseif canImport(AppKit)
            coordinator.cursorImage = renderer.nsImage
            #endif
        }
        if let cursor {
            let coordinate = CLLocationCoordinate2D(latitude: cursor.lat, longitude: cursor.lon)
            if let mark = coordinator.cursorMark {
                mark.coordinate = coordinate
            } else {
                let mark = LayeredCursorMark()
                mark.coordinate = coordinate
                coordinator.cursorMark = mark
                map.addAnnotation(mark)
            }
        } else if let mark = coordinator.cursorMark {
            map.removeAnnotation(mark)
            coordinator.cursorMark = nil
        }
    }

    @MainActor
    private func displayScale(_ map: MKMapView) -> CGFloat {
        #if canImport(UIKit)
        return map.traitCollection.displayScale > 0 ? map.traitCollection.displayScale : 3
        #elseif canImport(AppKit)
        return map.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        #endif
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var drawn: LayeredMapLayers?
        var framedKey = ""
        var onTap: ((LayeredMapTap) -> Void)?
        weak var map: MKMapView?
        fileprivate var cursorMark: LayeredCursorMark?
        fileprivate var cursorImage: LayeredPlatformImage?

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let line = overlay as? LayeredRouteLine {
                let renderer = MKPolylineRenderer(polyline: line)
                renderer.strokeColor = line.color
                renderer.lineWidth = line.width
                renderer.lineJoin = .round
                renderer.lineCap = .round
                return renderer
            }
            if let path = overlay as? LayeredPathLine {
                let renderer = MKPolylineRenderer(polyline: path)
                renderer.strokeColor = LayeredPlatformColor(StrandPalette.textSecondary).withAlphaComponent(0.55)
                renderer.lineWidth = 1.5
                renderer.lineJoin = .round
                renderer.lineCap = .round
                return renderer
            }
            if overlay is LayeredPointCloud {
                return LayeredPointCloudRenderer(overlay: overlay)
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let mark = annotation as? LayeredPlaceMark {
                let id = "layered-place"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                    ?? MKAnnotationView(annotation: mark, reuseIdentifier: id)
                view.annotation = mark
                view.image = mark.image
                view.centerOffset = CGPoint(x: 0, y: mark.discCentreOffset)
                view.canShowCallout = false
                // Taps go to the map's own recogniser, which picks places and points alike.
                view.isEnabled = false
                view.displayPriority = .required
                view.zPriority = .defaultUnselected
                return view
            }
            if annotation is LayeredCursorMark {
                let id = "layered-cursor"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                    ?? MKAnnotationView(annotation: annotation, reuseIdentifier: id)
                view.annotation = annotation
                view.image = cursorImage
                view.canShowCallout = false
                view.isEnabled = false
                view.displayPriority = .required
                view.zPriority = .max
                return view
            }
            return nil
        }

        #if canImport(UIKit)
        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let map else { return }
            reportLayeredTap(at: gesture.location(in: map), in: map)
        }
        #elseif canImport(AppKit)
        @objc func tapped(_ gesture: NSClickGestureRecognizer) {
            guard let map else { return }
            reportLayeredTap(at: gesture.location(in: map), in: map)
        }
        #endif

        /// The place whose disc holds the tap, else the nearest point within 22 pt, else nothing.
        private func reportLayeredTap(at location: CGPoint, in map: MKMapView) {
            guard let layers = drawn else { return }
            var bestPlace: (id: String, distance: CGFloat)?
            for place in layers.places {
                let centre = map.convert(CLLocationCoordinate2D(latitude: place.lat, longitude: place.lon), toPointTo: map)
                let distance = hypot(centre.x - location.x, centre.y - location.y)
                guard distance <= max(place.diameter / 2 + 6, 18) else { continue }
                if bestPlace.map({ distance < $0.distance }) ?? true { bestPlace = (place.id, distance) }
            }
            if let bestPlace {
                onTap?(.place(bestPlace.id))
                return
            }
            var bestPoint: (ts: Int64, distance: CGFloat)?
            for point in layers.points {
                let centre = map.convert(CLLocationCoordinate2D(latitude: point.lat, longitude: point.lon), toPointTo: map)
                let distance = hypot(centre.x - location.x, centre.y - location.y)
                guard distance <= 22 else { continue }
                if bestPoint.map({ distance < $0.distance }) ?? true { bestPoint = (point.ts, distance) }
            }
            onTap?(bestPoint.map { .point($0.ts) } ?? .nothing)
        }
    }

    #if canImport(UIKit)
    private var edgeInsets: UIEdgeInsets { UIEdgeInsets(top: 56, left: 32, bottom: 72, right: 32) }
    func makeUIView(context: Context) -> MKMapView { makeMap(context: context) }
    func updateUIView(_ map: MKMapView, context: Context) {
        configure(map, coordinator: context.coordinator, first: false)
    }
    #elseif canImport(AppKit)
    private var edgeInsets: NSEdgeInsets { NSEdgeInsets(top: 56, left: 32, bottom: 72, right: 32) }
    func makeNSView(context: Context) -> MKMapView { makeMap(context: context) }
    func updateNSView(_ map: MKMapView, context: Context) {
        configure(map, coordinator: context.coordinator, first: false)
    }
    #endif
}
#else
struct LayeredPlaceMap: View {
    let layers: LayeredMapLayers
    var cursor: LayeredMapCursor?
    var onTap: ((LayeredMapTap) -> Void)?
    var body: some View { Color.clear }
}
#endif
