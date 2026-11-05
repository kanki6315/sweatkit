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
        guard points.count >= 2 else { return nil }
        let length = Polyline(points).length
        guard length > 0 else { return nil }
        self.points = points
        self.length = length
    }

    /// The reference line of a route whose first activity has this track: the
    /// track's own points, in order. Nil under the same conditions as
    /// `init(points:)`.
    public init?(track: CleanedTrack) {
        self.init(points: track.points.map(\.coordinate))
    }

    /// The position at a route distance, placed by straight-line
    /// interpolation between the two points either side. A distance below 0
    /// gives the first point and one beyond the length gives the last.
    public func coordinate(atRouteDistance distance: Double) -> Coordinate {
        // A line always has at least two points, so there is always a position.
        Polyline(points).coordinate(at: distance) ?? points[0]
    }
}

extension ReferenceLine {
    private enum CodingKeys: String, CodingKey {
        case points
        case length
    }

    /// Reads a stored line. The length is measured again from the points, so
    /// a stored line can never disagree with the ruler, and a stored line
    /// that `init(points:)` would refuse is refused here too.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let points = try container.decode([Coordinate].self, forKey: .points)
        guard let line = ReferenceLine(points: points) else {
            throw DecodingError.dataCorruptedError(
                forKey: .points,
                in: container,
                debugDescription: "A reference line needs at least two points and some length."
            )
        }
        self = line
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(points, forKey: .points)
        try container.encode(length, forKey: .length)
    }
}
