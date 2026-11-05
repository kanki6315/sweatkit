import Foundation
import SweatKitModel

/// One point of an effort after it has been mapped onto a reference line.
public struct MappedPoint: Hashable, Codable, Sendable {
    /// The route distance of the position this point was matched to, in
    /// metres from the start of the reference line. It never decreases from
    /// one point to the next.
    public var routeDistance: Double
    /// The straight-line distance from the point to its matched position, in
    /// metres. Never negative.
    public var distanceFromLine: Double
    /// The sideways distance from the reference line, with its sign: positive
    /// when the point is to the right of the line's direction of travel and
    /// negative when it is to the left.
    ///
    /// It is the part of the offset from the matched position to the point
    /// that is perpendicular to the line there. For a point matched inside a
    /// straight piece of the line its size equals `distanceFromLine`. For a
    /// point matched to an end of the line, or held back by the forward-only
    /// rule, it can be smaller. Where the matched position is a corner of the
    /// line, the direction is that of the piece that begins at the corner, or
    /// of the last piece at the line's end.
    public var sideOffset: Double
    /// The point's elapsed time, carried over from the track.
    public var elapsedTime: TimeInterval
    /// The point's moving time, carried over from the track.
    public var movingTime: TimeInterval

    public init(
        routeDistance: Double,
        distanceFromLine: Double,
        sideOffset: Double,
        elapsedTime: TimeInterval,
        movingTime: TimeInterval
    ) {
        self.routeDistance = routeDistance
        self.distanceFromLine = distanceFromLine
        self.sideOffset = sideOffset
        self.elapsedTime = elapsedTime
        self.movingTime = movingTime
    }
}

/// An effort mapped onto a route's reference line. This is what an effort
/// stores, and what timing and comparison read.
public struct Alignment: Hashable, Codable, Sendable {
    /// One mapped point for each point of the track, in the track's order.
    public var points: [MappedPoint]
    /// The length of the reference line the track was mapped onto, in metres.
    public var referenceLength: Double
    /// The distance the track itself travelled, in metres.
    public var trackLength: Double
    /// Carried over from the track.
    public var pausePositionsAreReliable: Bool

    public init(
        points: [MappedPoint],
        referenceLength: Double,
        trackLength: Double,
        pausePositionsAreReliable: Bool = true
    ) {
        self.points = points
        self.referenceLength = referenceLength
        self.trackLength = trackLength
        self.pausePositionsAreReliable = pausePositionsAreReliable
    }

    /// The five measures of this alignment.
    public func measures(rules: MatchingRules = .standard) -> AlignmentMeasures {
        fatalError("unimplemented")
    }
}

/// The five measures the spec takes from a mapping.
public enum AlignmentMeasure: String, Codable, Sendable, CaseIterable {
    case proximity
    case ends
    case coverage
    case lengthRatio
    case sideOffset
}

/// The values of the five measures for one alignment.
///
/// The spec names the measures and their thresholds but not how each is
/// worked out from the mapping. The definitions here are this package's
/// reading. They all rest on one idea: a mapped point is **on the line** when
/// its `distanceFromLine` is at most `rules.proximityDistance`. The spec's
/// "mapped point" and "mapped stretch" are read as a point on the line and a
/// stretch between two of them.
public struct AlignmentMeasures: Hashable, Codable, Sendable {
    /// Proximity: the share of the effort's points that are on the line. An
    /// effort with no points has proximity 0.
    public var proximity: Double
    /// Ends, at the start: the route distance of the first point on the line.
    /// The spec's "within 25 m of the start" is read along the route, because
    /// the timed section depends on it. The reference length when no point is
    /// on the line.
    public var startGap: Double
    /// Ends, at the finish: the reference length minus the route distance of
    /// the last point on the line. The reference length when no point is on
    /// the line.
    public var endGap: Double
    /// Coverage: the share of the reference line's length that was mapped.
    ///
    /// The stretch of line between the route distances of two consecutive
    /// points is mapped when both points are on the line. Everything else is
    /// unmapped: the stretch before the first point on the line, the stretch
    /// after the last, and the stretch between two points on the line that
    /// have points off the line between them.
    ///
    /// Read literally, the ends count against coverage. On a reference line
    /// shorter than 500 m a start 25 m late passes the ends rule and fails
    /// this one.
    public var coverage: Double
    /// The longest unmapped stretch of the reference line, in metres. 0 when
    /// the whole line is mapped.
    public var longestUnmappedStretch: Double
    /// Length ratio: the distance the track travelled divided by the length
    /// of the reference line.
    public var lengthRatio: Double
    /// Side offset: the average signed `sideOffset` over the 200 m stretch
    /// where that average is furthest from zero. Positive is to the right.
    ///
    /// A stretch starts at the route distance of a point and runs
    /// `rules.sideOffsetStretch` metres forward. It counts only when it fits
    /// inside the reference line. Its average is the plain mean of the side
    /// offsets of every point, on the line or not, whose route distance lies
    /// in the stretch, both ends included. When the reference line is shorter
    /// than one stretch, a single stretch covers the whole line. 0 when no
    /// stretch counts or the effort has no points.
    public var worstSideOffset: Double

    public init(
        proximity: Double,
        startGap: Double,
        endGap: Double,
        coverage: Double,
        longestUnmappedStretch: Double,
        lengthRatio: Double,
        worstSideOffset: Double
    ) {
        self.proximity = proximity
        self.startGap = startGap
        self.endGap = endGap
        self.coverage = coverage
        self.longestUnmappedStretch = longestUnmappedStretch
        self.lengthRatio = lengthRatio
        self.worstSideOffset = worstSideOffset
    }

    /// The measures of a mapping, by the definitions on each property.
    public init(
        points: [MappedPoint],
        referenceLength: Double,
        trackLength: Double,
        rules: MatchingRules = .standard
    ) {
        fatalError("unimplemented")
    }

    /// The measures that fall short of what joining automatically needs.
    ///
    /// - Proximity passes when `proximity >= rules.joinProximity`.
    /// - Ends pass when `startGap <= rules.endTolerance` and
    ///   `endGap <= rules.endTolerance`.
    /// - Coverage passes when `coverage >= rules.minimumCoverage` and
    ///   `longestUnmappedStretch <= rules.longestUnmappedStretch`.
    /// - Length ratio passes when `lengthRatio >= 1 - rules.lengthRatioTolerance`
    ///   and `lengthRatio <= 1 + rules.lengthRatioTolerance`.
    /// - Side offset passes when the size of `worstSideOffset` is at most
    ///   `rules.maximumSideOffset`.
    ///
    /// The comparisons are written exactly this way so that a value sitting
    /// on a threshold passes.
    public func failedMeasures(rules: MatchingRules = .standard) -> Set<AlignmentMeasure> {
        fatalError("unimplemented")
    }

    /// Whether all five measures pass. This is what the spec means by an
    /// activity aligning with a route.
    public func allPass(rules: MatchingRules = .standard) -> Bool {
        fatalError("unimplemented")
    }

    /// The outcome for these measures.
    ///
    /// The spec's table does not say which row wins when two apply. This
    /// reading makes the three outcomes cover every case exactly once:
    ///
    /// 1. Reject when proximity is under `rules.reviewProximity`, or the ends
    ///    or coverage fail. Rejection comes first: a late start, an early
    ///    finish or a long detour is never offered for review.
    /// 2. Otherwise join when all five measures pass and the activity aligns
    ///    with no other route.
    /// 3. Otherwise manual review. What is left is exactly the spec's review
    ///    row: proximity from 70% up to but not including 90%, a stretch
    ///    consistently to one side, a failed length ratio, or a second route.
    ///
    /// - Parameter alignsWithAnotherRoute: True when all five measures also
    ///   pass against a different route.
    public func outcome(
        alignsWithAnotherRoute: Bool = false,
        rules: MatchingRules = .standard
    ) -> AlignmentOutcome {
        fatalError("unimplemented")
    }
}

/// What alignment decides about an activity and a route.
public enum AlignmentOutcome: String, Codable, Sendable, CaseIterable {
    /// The activity joins the route.
    case join
    /// The app asks the user. It does not guess.
    case manualReview
    /// The activity does not belong to the route. It stays an ordinary
    /// activity, and may wait as a possible new route.
    case reject
}

/// Step 2 of matching.
public enum RouteAlignment {
    /// Maps each point of a track to a position along a reference line, in
    /// order.
    ///
    /// The spec's "each point of the candidate" is read as each point of the
    /// cleaned track itself, not the 25 m resampling that detection uses, so
    /// that every sample keeps its time for the timed section and the
    /// comparison grid.
    ///
    /// The first point searches route distances from 0 to
    /// `rules.searchWindow`. Every later point searches from the previous
    /// point's route distance to that distance plus `rules.searchWindow`. The
    /// search never runs past the end of the line. Within its range a point is
    /// matched to the position on the line closest to it, and of several
    /// equally close positions the one with the smallest route distance. Route
    /// distance therefore only moves forward, and a spot the line visits twice
    /// maps to a different route distance on each pass.
    ///
    /// The result has one mapped point for each point of the track.
    public static func map(
        _ track: CleanedTrack,
        onto line: ReferenceLine,
        rules: MatchingRules = .standard
    ) -> [MappedPoint] {
        fatalError("unimplemented")
    }

    /// The alignment of a track with a reference line: the mapping from
    /// `map`, with the line's length, the track's length and the track's
    /// pause reliability.
    public static func align(
        _ track: CleanedTrack,
        to line: ReferenceLine,
        rules: MatchingRules = .standard
    ) -> Alignment {
        fatalError("unimplemented")
    }

    /// The outcome of one activity against each of several routes, given its
    /// measures against each. The result is in the same order.
    ///
    /// An activity aligns with a route when all five measures pass. When it
    /// aligns with two or more routes, each of those is sent to manual review
    /// instead of joining. A route it does not align with gets the outcome its
    /// own measures give, whatever happens on the others.
    public static func outcomes(
        for measures: [AlignmentMeasures],
        rules: MatchingRules = .standard
    ) -> [AlignmentOutcome] {
        fatalError("unimplemented")
    }
}
