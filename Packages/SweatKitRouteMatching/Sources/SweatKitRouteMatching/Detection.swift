import SweatKitModel

/// One cell of the detection grid.
///
/// The grid is fixed to the Earth, not to a track, so a position falls in the
/// same cell whichever activity passes through it. The spec says only "50 m
/// grid cells". This package's reading: with latitude and longitude in
/// radians, a position's northing is `earthRadius * latitude` and its easting
/// is `earthRadius * longitude * cos(latitude)`. The row is the northing
/// divided by the cell size, rounded down, and the column is the easting
/// divided by the cell size, rounded down. Rounding is towards negative
/// infinity, so the cells either side of the equator and the prime meridian
/// are distinct.
public struct GridCell: Hashable, Codable, Sendable {
    /// Counts cells east of longitude 0. Negative to the west.
    public var column: Int
    /// Counts cells north of the equator. Negative to the south.
    public var row: Int

    public init(column: Int, row: Int) {
        self.column = column
        self.row = row
    }
}

/// What detection keeps about one track. It is cheap to store and to compare,
/// so the whole library can be screened without touching the tracks again.
public struct TrackSignature: Hashable, Codable, Sendable {
    public var sportFamily: SportFamily
    /// The track's total distance in metres.
    public var length: Double
    /// The track's first point.
    public var start: Coordinate
    /// The track's last point.
    public var finish: Coordinate
    /// The grid cells the track passes through.
    public var cells: Set<GridCell>

    public init(
        sportFamily: SportFamily,
        length: Double,
        start: Coordinate,
        finish: Coordinate,
        cells: Set<GridCell>
    ) {
        self.sportFamily = sportFamily
        self.length = length
        self.start = start
        self.finish = finish
        self.cells = cells
    }

    /// The signature of a cleaned track, or nil when the track has fewer than
    /// two points and so has no course to detect.
    public init?(track: CleanedTrack, rules: MatchingRules = .standard) {
        fatalError("unimplemented")
    }
}

/// How one candidate fared against one reference in detection. Each gate is
/// reported on its own, so a caller can see which one turned a candidate away.
public struct DetectionGates: Hashable, Sendable {
    /// Both tracks are in the same sport family.
    public var sameSportFamily: Bool
    /// The candidate's total distance is within the tolerance of the
    /// reference's.
    public var distanceWithinTolerance: Bool
    /// The two starts are within the endpoint tolerance of each other.
    public var startWithinTolerance: Bool
    /// The two finishes are within the endpoint tolerance of each other.
    public var finishWithinTolerance: Bool
    /// The share of grid cells the two tracks have in common. See
    /// `RouteDetection.sharedCellFraction`.
    public var sharedCellFraction: Double
    /// The shared share is at least the minimum.
    public var sharesEnoughCells: Bool

    public init(
        sameSportFamily: Bool,
        distanceWithinTolerance: Bool,
        startWithinTolerance: Bool,
        finishWithinTolerance: Bool,
        sharedCellFraction: Double,
        sharesEnoughCells: Bool
    ) {
        self.sameSportFamily = sameSportFamily
        self.distanceWithinTolerance = distanceWithinTolerance
        self.startWithinTolerance = startWithinTolerance
        self.finishWithinTolerance = finishWithinTolerance
        self.sharedCellFraction = sharedCellFraction
        self.sharesEnoughCells = sharesEnoughCells
    }

    /// The spec's step 1.2: same sport family, total distance within
    /// tolerance, and start and finish each within tolerance.
    public var isCandidate: Bool {
        fatalError("unimplemented")
    }

    /// The spec's step 1.3: a candidate that also shares enough cells. Only a
    /// shortlisted candidate goes on to alignment.
    public var isShortlisted: Bool {
        fatalError("unimplemented")
    }
}

/// Step 1 of matching. Detection is cheap and deliberately loose: cell overlap
/// ignores order, so it only nominates candidates for alignment.
public enum RouteDetection {
    /// The track resampled to one point every `rules.resampleSpacing` metres
    /// of its own distance.
    ///
    /// The first point is the track's first point. Each later point lies on
    /// the track's line, a whole number of spacings along it, placed by
    /// straight-line interpolation between the two track points either side.
    ///
    /// The spec does not say what happens to the remainder past the last
    /// whole spacing. The literal reading is taken: nothing is added for it,
    /// so a 110 m track gives points at 0, 25, 50, 75 and 100 m. A track with
    /// one point gives that point, and an empty track gives nothing.
    public static func resample(_ track: CleanedTrack, rules: MatchingRules = .standard) -> [Coordinate] {
        fatalError("unimplemented")
    }

    /// The grid cell that holds a position. `GridCell` defines the grid.
    public static func cell(containing coordinate: Coordinate, rules: MatchingRules = .standard) -> GridCell {
        fatalError("unimplemented")
    }

    /// The grid cells a track passes through.
    ///
    /// The spec's "passes through" is read as the cells that hold the track's
    /// resampled points. A cell the line only clips between two resampled
    /// points is not recorded.
    public static func cells(of track: CleanedTrack, rules: MatchingRules = .standard) -> Set<GridCell> {
        fatalError("unimplemented")
    }

    /// The share of grid cells two tracks have in common: the number of cells
    /// in both, divided by the number of cells in whichever has more.
    ///
    /// The spec says candidates "share at least 85% of their grid cells"
    /// without naming the base. This reading requires the shared cells to be
    /// at least that share of each track's own cells, which is the same as
    /// dividing by the larger set. Two tracks with no cells share 0.
    public static func sharedCellFraction(_ a: Set<GridCell>, _ b: Set<GridCell>) -> Double {
        fatalError("unimplemented")
    }

    /// Every detection gate for one candidate against one reference.
    ///
    /// - Distance: `abs(candidate.length - reference.length)` is at most
    ///   `rules.distanceTolerance * reference.length`. The spec says "within
    ///   10%" without naming the base; the reference is the base, because a
    ///   candidate is always measured against a route's first activity.
    /// - Start and finish: each pair is at most `rules.endpointTolerance`
    ///   apart.
    /// - Cells: `sharedCellFraction` is at least `rules.minimumSharedCells`.
    public static func gates(
        candidate: TrackSignature,
        reference: TrackSignature,
        rules: MatchingRules = .standard
    ) -> DetectionGates {
        fatalError("unimplemented")
    }

    /// The indices of the references the candidate is shortlisted against, in
    /// ascending order.
    public static func shortlist(
        candidate: TrackSignature,
        references: [TrackSignature],
        rules: MatchingRules = .standard
    ) -> [Int] {
        fatalError("unimplemented")
    }
}
