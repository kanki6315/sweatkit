#if canImport(UIKit)
import MapKit
import SweatKitModel
import SwiftUI
import UIKit

/// The flyover map: a route coloured by band over satellite imagery or the
/// standard map, a marker at the scrub position, and an overview or follow
/// camera.
///
/// The scrub position is a source sample index, driven from outside. With
/// Reduce Motion on, follow mode becomes overview and only the marker moves.
public struct FlyoverMap: View {
    private let route: FlyoverRoute
    private let bandColors: [Color]
    @Binding private var scrubSample: Double
    private let options: FlyoverOptions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - bandColors: One colour per band. A band with no colour is drawn
    ///     grey.
    ///   - scrubSample: The source sample under the marker. Fractional values
    ///     place the marker between samples.
    public init(route: FlyoverRoute, bandColors: [Color], scrubSample: Binding<Double>, options: FlyoverOptions = FlyoverOptions()) {
        self.route = route
        self.bandColors = bandColors
        self._scrubSample = scrubSample
        self.options = options
    }

    public var body: some View {
        FlyoverMapRepresentable(
            route: route,
            bandColors: bandColors,
            scrubSample: scrubSample,
            options: options,
            cameraMode: options.effectiveCameraMode(reduceMotion: reduceMotion)
        )
    }
}

private struct FlyoverMapRepresentable: UIViewRepresentable {
    var route: FlyoverRoute
    var bandColors: [Color]
    var scrubSample: Double
    var options: FlyoverOptions
    var cameraMode: FlyoverOptions.CameraMode

    func makeCoordinator() -> FlyoverMapCoordinator { IdleMapCache.shared.take() ?? FlyoverMapCoordinator() }

    func makeUIView(context: Context) -> FlyoverMapViewport {
        if let mapView = context.coordinator.mapView { return FlyoverMapViewport(mapView: mapView) }
        let mapView = LayoutReportingMapView()
        mapView.delegate = context.coordinator
        mapView.showsCompass = true
        mapView.pointOfInterestFilter = .excludingAll
        mapView.register(MarkerView.self, forAnnotationViewWithReuseIdentifier: MarkerView.reuseIdentifier)
        let coordinator = context.coordinator
        mapView.onResize = { [weak coordinator] in coordinator?.mapViewDidResize() }
        coordinator.mapView = mapView
        return FlyoverMapViewport(mapView: mapView)
    }

    func updateUIView(_ viewport: FlyoverMapViewport, context: Context) {
        viewport.followsRoute = cameraMode == .follow
        viewport.layoutIfNeeded()
        context.coordinator.update(
            route: route,
            bandColors: bandColors,
            scrubSample: scrubSample,
            options: options,
            cameraMode: cameraMode
        )
    }

    static func dismantleUIView(_ viewport: FlyoverMapViewport, coordinator: FlyoverMapCoordinator) {
        coordinator.stop()
        IdleMapCache.shared.put(coordinator)
    }
}

/// Keeps one idle map (including its geometry and renderers) warm briefly.
/// NSCache may discard it under memory pressure; MapKit owns its tile cache.
@MainActor
private final class IdleMapCache {
    static let shared = IdleMapCache()
    private let cache = NSCache<NSString, FlyoverMapCoordinator>()
    private var generation = UUID()

    func take() -> FlyoverMapCoordinator? {
        let coordinator = cache.object(forKey: "idle")
        cache.removeAllObjects()
        generation = UUID()
        return coordinator
    }

    func put(_ coordinator: FlyoverMapCoordinator) {
        cache.countLimit = 1
        cache.setObject(coordinator, forKey: "idle")
        let token = UUID()
        generation = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
            guard let self, self.generation == token else { return }
            self.cache.removeAllObjects()
        }
    }
}

/// MapKit has no public base-map prefetch API. Give the renderer a bounded
/// apron outside the visible follow viewport so approaching tiles can load
/// before they enter the crop. Overview keeps its normal fitting/gesture area.
final class FlyoverMapViewport: UIView {
    let mapView: LayoutReportingMapView
    var followsRoute = false {
        didSet {
            if followsRoute != oldValue { setNeedsLayout() }
        }
    }

    init(mapView: LayoutReportingMapView) {
        self.mapView = mapView
        super.init(frame: .zero)
        clipsToBounds = true
        addSubview(mapView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !bounds.isEmpty else { return }
        // 25% on each edge: 2.25x the visible area, independent of playback
        // speed. Avoid resizing the renderer on every scrub/playback tick.
        let scale: CGFloat = followsRoute ? 1.5 : 1
        let dx = bounds.width * (scale - 1) / 2
        let dy = bounds.height * (scale - 1) / 2
        mapView.renderScale = Double(scale)
        // Keep MapKit's compass and attribution inside the visible crop.
        mapView.layoutMargins = UIEdgeInsets(top: dy + 8, left: dx + 8, bottom: dy + 8, right: dx + 8)
        mapView.frame = bounds.insetBy(dx: -dx, dy: -dy)
    }
}

/// An `MKMapView` that says when its size changes, so the overview camera can
/// fit the route once there is something to fit it into.
final class LayoutReportingMapView: MKMapView {
    var renderScale = 1.0
    var onResize: (() -> Void)?
    private var lastSize: CGSize = .zero

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != lastSize {
            lastSize = bounds.size
            onResize?()
        }
    }
}

/// A polyline that knows which part of the route it draws and how.
final class RoutePolyline: MKPolyline {
    enum Role {
        /// Full colour. With dimming on, stops at the marker.
        case full
        /// The whole route, faded, under the full-colour line.
        case dimmed
    }

    var role = Role.full
    /// The route vertices this polyline draws.
    var vertices: ClosedRange<Int> = 0...1
    /// The stroke colour when drawn as a band run.
    var color: UIColor = .gray
    /// Gradient colours and their locations when drawn as one gradient.
    var gradient: (colors: [UIColor], locations: [CGFloat])?
}

/// The dot at the scrub position.
final class MarkerView: MKAnnotationView {
    static let reuseIdentifier = "SweatKitFlyover.marker"
    private static let diameter: CGFloat = 18

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: Self.diameter, height: Self.diameter)
        backgroundColor = .white
        layer.cornerRadius = Self.diameter / 2
        layer.borderColor = UIColor.black.withAlphaComponent(0.6).cgColor
        layer.borderWidth = 3
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.35
        layer.shadowRadius = 3
        layer.shadowOffset = .zero
        displayPriority = .required
        collisionMode = .none
        zPriority = .max
        isAccessibilityElement = true
        accessibilityLabel = "Position"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}

@MainActor
final class FlyoverMapCoordinator: NSObject, MKMapViewDelegate {
    /// Everything that, when changed, means the lines are drawn again.
    private struct LineSettings: Equatable {
        var route: FlyoverRoute
        var bandColors: [Color]
        var drawing: FlyoverOptions.LineDrawing
        var gradientLocations: GradientStops.Parameter
        var level: FlyoverOptions.LineLevel
        var width: Double
        var dimsAhead: Bool
        var dimmedOpacity: Double
    }

    private struct MapSettings: Equatable {
        var style: FlyoverOptions.MapStyle
        var realisticElevation: Bool
    }

    var mapView: LayoutReportingMapView?

    private var geometry: RouteGeometry?
    private var options = FlyoverOptions()
    private var lineSettings: LineSettings?
    private var mapSettings: MapSettings?
    private var cameraMode: FlyoverOptions.CameraMode?
    private var position = RoutePosition(segment: 0, fraction: 0)

    private var routeOverlays: [RoutePolyline] = []
    /// The full-colour lines, whose `strokeEnd` follows the marker.
    private var fullLines: [RoutePolyline] = []
    private var renderers: [ObjectIdentifier: MKPolylineRenderer] = [:]
    private let marker = MKPointAnnotation()
    private var markerAdded = false
    private var needsOverviewFit = false

    private var smoother = HeadingSmoother()
    private var pacing = CameraPacing()
    private var headingTarget: Double?
    private var cameraNeedsUpdate = false
    private var displayLink: CADisplayLink?
    private var lastFrameTimestamp: CFTimeInterval?

    func update(
        route: FlyoverRoute,
        bandColors: [Color],
        scrubSample: Double,
        options: FlyoverOptions,
        cameraMode: FlyoverOptions.CameraMode
    ) {
        guard let mapView else { return }
        self.options = options

        let routeChanged = geometry?.route != route
        if routeChanged {
            geometry = RouteGeometry(route: route)
        }
        guard let geometry else { return }
        position = geometry.position(atSample: scrubSample)

        let newMapSettings = MapSettings(style: options.mapStyle, realisticElevation: options.realisticElevation)
        if newMapSettings != mapSettings {
            mapSettings = newMapSettings
            mapView.preferredConfiguration = Self.configuration(for: newMapSettings)
        }

        let newLineSettings = LineSettings(
            route: route,
            bandColors: bandColors,
            drawing: options.lineDrawing,
            gradientLocations: options.gradientLocations,
            level: options.lineLevel,
            width: options.lineWidth,
            dimsAhead: options.dimsAhead,
            dimmedOpacity: options.dimmedOpacity
        )
        if newLineSettings != lineSettings {
            lineSettings = newLineSettings
            drawLines(geometry: geometry, settings: newLineSettings, in: mapView)
        }

        marker.coordinate = CLLocationCoordinate2D(geometry.coordinate(at: position))
        if !markerAdded {
            mapView.addAnnotation(marker)
            markerAdded = true
        }
        updateStrokeEnds()

        if routeChanged || cameraMode != self.cameraMode {
            self.cameraMode = cameraMode
            switch cameraMode {
            case .overview:
                stopDisplayLink()
                fitOverview()
            case .follow:
                pacing.reset(to: geometry.distance(at: position))
                smoother = options.headingSmoothing
                headingTarget = options.followHeading.target(on: geometry, at: position)
                smoother.reset(to: headingTarget ?? mapView.camera.heading)
            }
        }
        if cameraMode == .follow {
            smoother.timeConstant = options.headingSmoothing.timeConstant
            smoother.maximumRate = options.headingSmoothing.maximumRate
            headingTarget = options.followHeading.target(on: geometry, at: position) ?? headingTarget
            cameraNeedsUpdate = true
            startDisplayLink()
        }
    }

    func stop() {
        stopDisplayLink()
    }

    func mapViewDidResize() {
        if needsOverviewFit || cameraMode == .overview {
            fitOverview()
        } else if cameraMode == .follow {
            cameraNeedsUpdate = true
            startDisplayLink()
        }
    }

    // MARK: Map

    private static func configuration(for settings: MapSettings) -> MKMapConfiguration {
        let elevation: MKMapConfiguration.ElevationStyle = settings.realisticElevation ? .realistic : .flat
        switch settings.style {
        case .satellite: return MKImageryMapConfiguration(elevationStyle: elevation)
        case .standard: return MKStandardMapConfiguration(elevationStyle: elevation)
        }
    }

    // MARK: Lines

    private func drawLines(geometry: RouteGeometry, settings: LineSettings, in mapView: MKMapView) {
        mapView.removeOverlays(routeOverlays)
        renderers.removeAll()

        let route = geometry.route
        let colors = settings.bandColors.map { UIColor($0) }
        func color(_ band: Int) -> UIColor { colors.indices.contains(band) ? colors[band] : .gray }

        let runs = BandRuns.split(route.bands)
        var full: [RoutePolyline] = []
        switch settings.drawing {
        case .gradient:
            let stops = GradientStops.make(runs: runs, vertexLocations: geometry.vertexLocations(settings.gradientLocations))
            let line = makePolyline(route.vertices, 0...(route.vertices.count - 1))
            line.gradient = (stops.map { color($0.band) }, stops.map { CGFloat($0.location) })
            full = [line]
        case .bandRuns:
            full = runs.map { run in
                let line = makePolyline(route.vertices, run.vertices)
                line.color = color(run.band)
                return line
            }
        }

        var dimmed: [RoutePolyline] = []
        if settings.dimsAhead {
            dimmed = full.map { source in
                let line = makePolyline(route.vertices, source.vertices)
                line.role = .dimmed
                line.color = source.color
                line.gradient = source.gradient
                return line
            }
        }

        fullLines = full
        routeOverlays = dimmed + full
        let level: MKOverlayLevel = settings.level == .aboveLabels ? .aboveLabels : .aboveRoads
        // Dimmed lines go first so the full-colour line is drawn over them.
        mapView.addOverlays(routeOverlays, level: level)
    }

    private func makePolyline(_ vertices: [Coordinate], _ range: ClosedRange<Int>) -> RoutePolyline {
        let coordinates = vertices[range].map(CLLocationCoordinate2D.init)
        let line = RoutePolyline(coordinates: coordinates, count: coordinates.count)
        line.vertices = range
        return line
    }

    private func strokeEnd(for line: RoutePolyline) -> CGFloat {
        guard lineSettings?.dimsAhead == true, let geometry else { return 1 }
        return CGFloat(geometry.strokeFraction(at: position, vertices: line.vertices))
    }

    private func updateStrokeEnds() {
        guard lineSettings?.dimsAhead == true else { return }
        for line in fullLines {
            guard let renderer = renderers[ObjectIdentifier(line)] else { continue }
            let end = strokeEnd(for: line)
            if renderer.strokeEnd != end {
                renderer.strokeEnd = end
                renderer.setNeedsDisplay()
            }
        }
    }

    func mapView(_ mapView: MKMapView, rendererFor overlay: any MKOverlay) -> MKOverlayRenderer {
        guard let line = overlay as? RoutePolyline else { return MKOverlayRenderer(overlay: overlay) }
        let renderer: MKPolylineRenderer
        if let gradient = line.gradient {
            let gradientRenderer = MKGradientPolylineRenderer(polyline: line)
            gradientRenderer.setColors(gradient.colors, locations: gradient.locations)
            renderer = gradientRenderer
        } else {
            renderer = MKPolylineRenderer(polyline: line)
            renderer.strokeColor = line.color
        }
        renderer.lineWidth = CGFloat(options.lineWidth)
        renderer.lineCap = .round
        renderer.lineJoin = .round
        switch line.role {
        case .full:
            renderer.strokeEnd = strokeEnd(for: line)
            renderers[ObjectIdentifier(line)] = renderer
        case .dimmed:
            renderer.alpha = CGFloat(min(max(options.dimmedOpacity, 0), 1))
        }
        return renderer
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
        guard annotation === marker else { return nil }
        return mapView.dequeueReusableAnnotationView(withIdentifier: MarkerView.reuseIdentifier, for: annotation)
    }

    // MARK: Camera

    private func fitOverview() {
        guard let mapView, let geometry else { return }
        guard !mapView.bounds.isEmpty else {
            needsOverviewFit = true
            return
        }
        needsOverviewFit = false
        let coordinates = geometry.route.vertices.map(CLLocationCoordinate2D.init)
        let rect = MKPolyline(coordinates: coordinates, count: coordinates.count).boundingMapRect
        mapView.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: 60, left: 40, bottom: 60, right: 40), animated: false)
        let fitted = mapView.camera
        mapView.setCamera(
            MKMapCamera(
                lookingAtCenter: fitted.centerCoordinate,
                fromDistance: fitted.centerCoordinateDistance,
                pitch: CGFloat(options.overviewPitch),
                heading: 0
            ),
            animated: false
        )
    }

    private func startDisplayLink() {
        if let displayLink {
            displayLink.isPaused = false
            return
        }
        let link = CADisplayLink(target: self, selector: #selector(stepCamera(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 30, preferred: 30)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        lastFrameTimestamp = nil
    }

    @objc private func stepCamera(_ link: CADisplayLink) {
        guard cameraMode == .follow, let mapView, let geometry else {
            stopDisplayLink()
            return
        }
        let targetDistance = geometry.distance(at: position)
        guard cameraNeedsUpdate || !pacing.hasSettled(on: targetDistance) || !smoother.hasSettled(on: headingTarget) else {
            link.isPaused = true
            lastFrameTimestamp = nil
            return
        }
        // Long gaps, such as after a pause, count as one frame.
        let seconds = lastFrameTimestamp.map { min(link.timestamp - $0, 1.0 / 30) } ?? link.duration
        lastFrameTimestamp = link.timestamp
        cameraNeedsUpdate = false
        let cameraDistance = pacing.step(towards: targetDistance, seconds: seconds)
        let cameraPosition = geometry.position(atDistance: cameraDistance)
        headingTarget = options.followHeading.target(on: geometry, at: cameraPosition) ?? headingTarget
        guard let heading = smoother.step(towards: headingTarget, seconds: seconds) else { return }
        mapView.setCamera(
            MKMapCamera(
                lookingAtCenter: CLLocationCoordinate2D(geometry.coordinate(at: cameraPosition)),
                // Compensate for the larger render surface so the cropped
                // map retains the follow camera's scale at the marker.
                fromDistance: options.followDistance * mapView.renderScale,
                pitch: CGFloat(options.followPitch),
                heading: heading
            ),
            animated: false
        )
    }
}

private extension CLLocationCoordinate2D {
    init(_ coordinate: Coordinate) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}
#endif
