import SweatKitModel

/// A route's reference line: the course every effort on the route is mapped
/// onto. It is taken from the route's first activity.
///
/// The line runs straight between consecutive points. A position on it is
/// named by its route distance, the metres travelled along the line from its
/// first point.
public struct ReferenceLine: Hashable, Codable, Sendable {
    /// The line's points in order.
    public let points: [Coordinate]
    /// The line's total length in metres.
    public let length: Double

    /// A line through these points, or nil when there are fewer than two
    /// points or the line has no length.
    public init?(points: [Coordinate]) {
        fatalError("unimplemented")
    }

    /// The reference line of a route whose first activity has this track: the
    /// track's own points, in order. Nil under the same conditions as
    /// `init(points:)`.
    public init?(track: CleanedTrack) {
        fatalError("unimplemented")
    }

    /// The position at a route distance, placed by straight-line
    /// interpolation between the two points either side. A distance below 0
    /// gives the first point and one beyond the length gives the last.
    public func coordinate(atRouteDistance distance: Double) -> Coordinate {
        fatalError("unimplemented")
    }
}
