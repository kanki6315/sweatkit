/// Every number the route rules use. Each is the spec's starting value, to be
/// tuned against real history, so none of them is written inline anywhere
/// else. Distances are metres and shares are fractions of 1.
public struct MatchingRules: Hashable, Sendable {
    // MARK: Step 1, detection

    /// A cleaned track is resampled to one point every this many metres.
    public var resampleSpacing: Double = 25
    /// The side of a grid cell.
    public var cellSize: Double = 50
    /// A candidate's total distance is within this share of the reference's.
    public var distanceTolerance: Double = 0.10
    /// A candidate's start and finish are each within this distance of the
    /// reference's.
    public var endpointTolerance: Double = 200
    /// A candidate is shortlisted when it shares at least this share of grid
    /// cells.
    public var minimumSharedCells: Double = 0.85

    // MARK: Step 2, alignment

    /// How far ahead of the previous match a point may search.
    ///
    /// The spec says the window is limited and gives no number. 100 m is this
    /// package's starting value: longer than the gap between two samples of a
    /// cleaned track, and shorter than any lap or lobe that should be told
    /// apart.
    public var searchWindow: Double = 100
    /// A point within this distance of its matched position is on the line.
    public var proximityDistance: Double = 30
    /// Proximity needed to join automatically.
    public var joinProximity: Double = 0.90
    /// Proximity below this rejects.
    public var reviewProximity: Double = 0.70
    /// How far along the line a full effort may begin, and how far before its
    /// end it may stop. The timed section is cut back from both ends by the
    /// same distance, which is what guarantees every full effort covers it.
    public var endTolerance: Double = 25
    /// The share of the timed section's length that must be mapped.
    public var minimumCoverage: Double = 0.95
    /// No unmapped stretch of the timed section may be longer than this.
    public var longestUnmappedStretch: Double = 50
    /// The length ratio, measured over the timed section, must be within
    /// this of 1.
    public var lengthRatioTolerance: Double = 0.03
    /// The length of route over which the side offset is averaged.
    public var sideOffsetStretch: Double = 200
    /// No stretch may average more than this to one side.
    public var maximumSideOffset: Double = 10
    /// Modest, localized drift is tolerated only with near-complete agreement.
    public var maximumDriftOffset: Double = 18
    public var maximumDriftFraction: Double = 0.15

    // MARK: Comparison

    /// The spacing of the route-distance grid two efforts are compared on.
    public var comparisonGridSpacing: Double = 10

    /// The spec's starting values.
    public static let standard = MatchingRules()

    public init() {}
}
