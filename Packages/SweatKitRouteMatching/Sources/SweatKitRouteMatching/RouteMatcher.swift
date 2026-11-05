import SweatKitModel

/// What matching needs to know about a known route: the detection signature
/// and the reference line of its first activity.
///
/// An activity with no match waits as a possible new route. It waits as one of
/// these, built from its own track, and becomes a route when a second activity
/// joins it.
public struct RouteReference: Hashable, Codable, Sendable {
    public var signature: TrackSignature
    public var line: ReferenceLine

    public init(signature: TrackSignature, line: ReferenceLine) {
        self.signature = signature
        self.line = line
    }

    /// The reference for a route whose first activity has this track, or nil
    /// when the track has fewer than two points or no length.
    public init?(track: CleanedTrack, rules: MatchingRules = .standard) {
        fatalError("unimplemented")
    }
}

/// The result of aligning one activity with one shortlisted route.
public struct RouteMatch: Hashable, Sendable {
    /// The index of the route in the list that was passed in.
    public var routeIndex: Int
    public var alignment: Alignment
    public var measures: AlignmentMeasures
    public var outcome: AlignmentOutcome

    public init(routeIndex: Int, alignment: Alignment, measures: AlignmentMeasures, outcome: AlignmentOutcome) {
        self.routeIndex = routeIndex
        self.alignment = alignment
        self.measures = measures
        self.outcome = outcome
    }
}

/// Both steps of matching for one activity.
public enum RouteMatcher {
    /// Matches an activity's track against every known route.
    ///
    /// Detection runs first. A route the track is not shortlisted against is
    /// left out of the result: alignment is never run on it. Each shortlisted
    /// route gets one match, in ascending order of route index, with the
    /// outcome that `RouteAlignment.outcomes` gives across all of them, so an
    /// activity that aligns with two routes is sent to review on both.
    ///
    /// A track with fewer than two points matches nothing.
    public static func match(
        _ track: CleanedTrack,
        against routes: [RouteReference],
        rules: MatchingRules = .standard
    ) -> [RouteMatch] {
        fatalError("unimplemented")
    }
}
