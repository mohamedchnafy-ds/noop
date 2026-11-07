import SwiftUI
import StrandDesign
#if canImport(MapKit)
import MapKit
#endif

// MARK: - A map of coloured dots (personal fork, chantier 14 step 2)
//
// The Lieux view (one disc per place, sized by its visits, coloured by its difference to the normal,
// hollow when there is too little data, its name under it) and the Points view (one small dot per point,
// coloured by heart rate or stress). Tapping a dot reports its id. Positions never leave the device;
// MapKit only fetches tiles.

/// One dot on the map.
struct MapDot: Equatable, Identifiable {
    var id: String
    var lat: Double
    var lon: Double
    /// Radius on the ground, metres.
    var radiusM: Double
    var color: Color
    /// Drawn as a ring only (no data, too few).
    var hollow: Bool = false
    var selected: Bool = false
    /// A name drawn under the dot (places only).
    var label: String?
}

#if canImport(MapKit)
#if canImport(UIKit)
private typealias DotPlatformColor = UIColor
#elseif canImport(AppKit)
private typealias DotPlatformColor = NSColor
#endif

private final class DotCircle: MKCircle {
    var dotId = ""
    var color: Color = .gray
    var hollow = false
    var selected = false
}

private final class DotLabel: MKPointAnnotation {}

struct PlaceDotsMap: RouteMapRepresentable {
    let dots: [MapDot]
    var onTap: ((String?) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator() }

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
        configure(map, coordinator: context.coordinator, reframe: true)
        return map
    }

    private func configure(_ map: MKMapView, coordinator: Coordinator, reframe: Bool) {
        coordinator.onTap = onTap
        coordinator.dots = dots
        map.removeOverlays(map.overlays)
        map.removeAnnotations(map.annotations)
        var frame: MKMapRect?
        for dot in dots.sorted(by: { !$0.selected && $1.selected }) {
            let circle = DotCircle(center: CLLocationCoordinate2D(latitude: dot.lat, longitude: dot.lon),
                                   radius: dot.radiusM)
            circle.dotId = dot.id
            circle.color = dot.color
            circle.hollow = dot.hollow
            circle.selected = dot.selected
            map.addOverlay(circle)
            frame = frame.map { $0.union(circle.boundingMapRect) } ?? circle.boundingMapRect
            if let label = dot.label {
                let mark = DotLabel()
                mark.coordinate = CLLocationCoordinate2D(latitude: dot.lat, longitude: dot.lon)
                mark.title = label
                map.addAnnotation(mark)
            }
        }
        let key = dots.map(\.id).joined(separator: ",")
        if let frame, reframe || coordinator.framedKey != key {
            coordinator.framedKey = key
            map.setVisibleMapRect(frame, edgePadding: edgeInsets, animated: !reframe)
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var framedKey = ""
        var dots: [MapDot] = []
        var onTap: ((String?) -> Void)?
        weak var map: MKMapView?

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let circle = overlay as? DotCircle else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKCircleRenderer(circle: circle)
            let color = DotPlatformColor(circle.color)
            renderer.fillColor = circle.hollow ? color.withAlphaComponent(0) : color.withAlphaComponent(0.85)
            renderer.strokeColor = circle.selected ? DotPlatformColor(StrandPalette.textPrimary) : color
            renderer.lineWidth = circle.selected ? 3 : 2
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard annotation is DotLabel else { return nil }
            let id = "dot-label"
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView)
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
            view.annotation = annotation
            view.glyphText = ""
            view.markerTintColor = .clear
            view.titleVisibility = .visible
            view.displayPriority = .required
            view.canShowCallout = false
            return view
        }

        /// The dot under the tap (the nearest whose disc, at least 22 pt wide, holds it), or nil.
        #if canImport(UIKit)
        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let map else { return }
            reportDotTap(at: gesture.location(in: map), in: map)
        }
        #elseif canImport(AppKit)
        @objc func tapped(_ gesture: NSClickGestureRecognizer) {
            guard let map else { return }
            reportDotTap(at: gesture.location(in: map), in: map)
        }
        #endif

        private func reportDotTap(at point: CGPoint, in map: MKMapView) {
            var best: (id: String, distance: CGFloat)?
            for dot in dots {
                let centre = map.convert(CLLocationCoordinate2D(latitude: dot.lat, longitude: dot.lon), toPointTo: map)
                let edge = map.convert(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: dot.lat, longitude: dot.lon),
                                                          latitudinalMeters: dot.radiusM * 2,
                                                          longitudinalMeters: dot.radiusM * 2),
                                       toRectTo: map)
                let reach = max(edge.width / 2, 11)
                let distance = hypot(centre.x - point.x, centre.y - point.y)
                guard distance <= reach else { continue }
                if best == nil || distance < best!.distance { best = (dot.id, distance) }
            }
            onTap?(best?.id)
        }
    }

    #if canImport(UIKit)
    private var edgeInsets: UIEdgeInsets { UIEdgeInsets(top: 40, left: 40, bottom: 56, right: 40) }
    func makeUIView(context: Context) -> MKMapView { makeMap(context: context) }
    func updateUIView(_ map: MKMapView, context: Context) {
        configure(map, coordinator: context.coordinator, reframe: false)
    }
    #elseif canImport(AppKit)
    private var edgeInsets: NSEdgeInsets { NSEdgeInsets(top: 40, left: 40, bottom: 56, right: 40) }
    func makeNSView(context: Context) -> MKMapView { makeMap(context: context) }
    func updateNSView(_ map: MKMapView, context: Context) {
        configure(map, coordinator: context.coordinator, reframe: false)
    }
    #endif
}
#else
struct PlaceDotsMap: View {
    let dots: [MapDot]
    var onTap: ((String?) -> Void)?
    var body: some View { Color.clear }
}
#endif
