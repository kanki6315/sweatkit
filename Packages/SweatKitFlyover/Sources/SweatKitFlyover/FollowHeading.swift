import Foundation

/// Where the follow camera points: the bearing from the marker to the route
/// 150 to 300 m ahead.
///
/// The bearing is the mean of the bearings to several points spread across
/// the look-ahead range, so one sharp bend changes it gradually as the
/// points pass the bend one by one. `HeadingSmoother` then limits how fast
/// the camera turns towards it.
public struct FollowHeading: Hashable, Sendable {
    /// Metres ahead of the marker to look.
    public var lookAhead: ClosedRange<Double>
    /// How many points across `lookAhead` to average, at least 1.
    public var pointCount: Int
    /// Points closer than this to the marker are skipped, so the bearing does
    /// not swing wildly in the last metres of the route.
    public var minimumSpan: Double

    public init(lookAhead: ClosedRange<Double> = 150...300, pointCount: Int = 4, minimumSpan: Double = 10) {
        self.lookAhead = lookAhead
        self.pointCount = pointCount
        self.minimumSpan = minimumSpan
    }

    /// The bearing in degrees clockwise from north, in `0..<360`, or nil when
    /// there is not enough route ahead to tell, as at the very end. The caller
    /// keeps its previous heading then.
    public func target(on geometry: RouteGeometry, at position: RoutePosition) -> Double? {
        let here = geometry.coordinate(at: position)
        let start = geometry.distance(at: position)
        let count = max(1, pointCount)
        var east = 0.0, north = 0.0
        for step in 0..<count {
            let share = count == 1 ? 0.5 : Double(step) / Double(count - 1)
            let ahead = min(
                geometry.totalDistance,
                start + lookAhead.lowerBound + (lookAhead.upperBound - lookAhead.lowerBound) * share
            )
            guard ahead - start >= minimumSpan else { continue }
            let point = geometry.coordinate(at: geometry.position(atDistance: ahead))
            let bearing = Geodesy.radians(Geodesy.bearing(from: here, to: point))
            east += sin(bearing)
            north += cos(bearing)
        }
        guard (east * east + north * north).squareRoot() > 1e-9 else { return nil }
        return Geodesy.normalizedDegrees(Geodesy.degrees(atan2(east, north)))
    }
}

/// Turns the camera's heading towards a target gradually, always the short way
/// round, so switchbacks and fast scrubs do not whip the view.
public struct HeadingSmoother: Hashable, Sendable {
    /// Seconds for the heading to close about 63% of the gap to its target.
    public var timeConstant: Double
    /// The fastest the heading may turn, in degrees per second.
    public var maximumRate: Double
    /// The heading in degrees, or nil until the first target arrives.
    public private(set) var current: Double?

    public init(timeConstant: Double = 0.8, maximumRate: Double = 90) {
        self.timeConstant = timeConstant
        self.maximumRate = maximumRate
    }

    /// Jumps straight to `heading`, as when follow mode starts.
    public mutating func reset(to heading: Double?) {
        current = heading.map(Geodesy.normalizedDegrees)
    }

    /// Moves `seconds` of time towards `target` and returns the new heading.
    /// The first target is taken as is. A nil target holds the heading.
    @discardableResult
    public mutating func step(towards target: Double?, seconds: Double) -> Double? {
        guard let target, target.isFinite else { return current }
        guard let heading = current else {
            current = Geodesy.normalizedDegrees(target)
            return current
        }
        guard seconds.isFinite, seconds > 0 else { return heading }
        let gap = Geodesy.shortestTurn(from: heading, to: target)
        let eased = timeConstant > 0 ? gap * (1 - exp(-seconds / timeConstant)) : gap
        let limit = maximumRate * seconds
        let turn = min(max(eased, -limit), limit)
        current = Geodesy.normalizedDegrees(heading + turn)
        return current
    }

    /// Whether the heading is within `tolerance` degrees of `target`.
    public func hasSettled(on target: Double?, tolerance: Double = 0.1) -> Bool {
        guard let target, let current else { return true }
        return abs(Geodesy.shortestTurn(from: current, to: target)) <= tolerance
    }
}
