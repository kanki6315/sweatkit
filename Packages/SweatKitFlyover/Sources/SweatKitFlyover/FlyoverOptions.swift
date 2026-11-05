/// How the flyover map looks and moves. The defaults follow the spec and are
/// revisited once the M0 flyover gates have results.
public struct FlyoverOptions: Hashable, Sendable {
    public enum MapStyle: String, Hashable, Sendable, CaseIterable {
        /// Satellite imagery.
        case satellite
        /// The standard map.
        case standard
    }

    /// How the coloured route is drawn. The frame-rate gate chooses between
    /// these.
    public enum LineDrawing: String, Hashable, Sendable, CaseIterable {
        /// One polyline with a colour gradient that has hard edges between
        /// bands.
        case gradient
        /// One single-colour polyline per run of the same band.
        case bandRuns
    }

    public enum CameraMode: String, Hashable, Sendable, CaseIterable {
        /// Fits the whole route. The map can be panned, zoomed and rotated.
        case overview
        /// A chase camera behind the marker, facing along the route. With
        /// Reduce Motion on it is replaced by overview.
        case follow
    }

    /// Where the route sits among the map's layers.
    public enum LineLevel: String, Hashable, Sendable, CaseIterable {
        /// Above roads and below labels.
        case aboveRoads
        /// Above everything, labels included.
        case aboveLabels
    }

    public var mapStyle: MapStyle
    /// Whether the map shows terrain and buildings in 3D. Off draws the map
    /// flat, which the terrain gate falls back to.
    public var realisticElevation: Bool
    public var lineDrawing: LineDrawing
    /// How gradient stop locations are measured. Only used when drawing a
    /// gradient.
    public var gradientLocations: GradientStops.Parameter
    public var lineLevel: LineLevel
    /// Points.
    public var lineWidth: Double
    /// Whether the part of the route ahead of the marker is drawn faded.
    public var dimsAhead: Bool
    /// The opacity of the faded part, in `0...1`.
    public var dimmedOpacity: Double
    public var cameraMode: CameraMode
    /// Degrees from straight down for the overview camera.
    public var overviewPitch: Double
    /// Metres from the camera to the marker in follow mode.
    public var followDistance: Double
    /// Degrees from straight down for the follow camera.
    public var followPitch: Double
    public var followHeading: FollowHeading
    public var headingSmoothing: HeadingSmoother

    public init(
        mapStyle: MapStyle = .satellite,
        realisticElevation: Bool = true,
        lineDrawing: LineDrawing = .gradient,
        gradientLocations: GradientStops.Parameter = .vertexIndex,
        lineLevel: LineLevel = .aboveRoads,
        lineWidth: Double = 5,
        dimsAhead: Bool = false,
        dimmedOpacity: Double = 0.35,
        cameraMode: CameraMode = .overview,
        overviewPitch: Double = 45,
        followDistance: Double = 600,
        followPitch: Double = 60,
        followHeading: FollowHeading = FollowHeading(),
        headingSmoothing: HeadingSmoother = HeadingSmoother()
    ) {
        self.mapStyle = mapStyle
        self.realisticElevation = realisticElevation
        self.lineDrawing = lineDrawing
        self.gradientLocations = gradientLocations
        self.lineLevel = lineLevel
        self.lineWidth = lineWidth
        self.dimsAhead = dimsAhead
        self.dimmedOpacity = dimmedOpacity
        self.cameraMode = cameraMode
        self.overviewPitch = overviewPitch
        self.followDistance = followDistance
        self.followPitch = followPitch
        self.followHeading = followHeading
        self.headingSmoothing = headingSmoothing
    }

    /// The camera mode actually used: follow becomes overview with a moving
    /// marker when Reduce Motion is on.
    public func effectiveCameraMode(reduceMotion: Bool) -> CameraMode {
        reduceMotion ? .overview : cameraMode
    }
}
