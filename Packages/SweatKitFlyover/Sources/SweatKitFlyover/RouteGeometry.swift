import SweatKitModel

/// A point on the drawn line: a fraction of the way along one segment.
public struct RoutePosition: Hashable, Sendable {
    /// The segment from vertex `segment` to vertex `segment + 1`.
    public var segment: Int
    /// How far along that segment, in `0...1`.
    public var fraction: Double

    public init(segment: Int, fraction: Double) {
        self.segment = segment
        self.fraction = fraction
    }
}

/// Measurements of a route, worked out once, that map a scrub position to a
/// point on the line and back.
///
/// A scrub position is a source sample index, which may be fractional while
/// playing. Samples that simplification dropped fall between two drawn
/// vertices and are placed on that segment in proportion to their index.
public struct RouteGeometry: Sendable {
    public let route: FlyoverRoute
    /// Metres along the route at each vertex, starting at 0.
    public let cumulativeDistance: [Double]
    /// Projected length along the route at each vertex, in Web Mercator units.
    /// MapKit measures `strokeStart` and `strokeEnd` this way.
    let cumulativeProjectedLength: [Double]

    public init(route: FlyoverRoute) {
        self.route = route
        var distance = [0.0]
        var projected = [0.0]
        distance.reserveCapacity(route.vertices.count)
        projected.reserveCapacity(route.vertices.count)
        var previous = Geodesy.mercator(route.vertices[0])
        for index in 1..<route.vertices.count {
            let a = route.vertices[index - 1], b = route.vertices[index]
            distance.append(distance[index - 1] + Geodesy.distance(a, b))
            let point = Geodesy.mercator(b)
            let dx = point.x - previous.x, dy = point.y - previous.y
            projected.append(projected[index - 1] + (dx * dx + dy * dy).squareRoot())
            previous = point
        }
        cumulativeDistance = distance
        cumulativeProjectedLength = projected
    }

    /// Metres from the first vertex to the last.
    public var totalDistance: Double { cumulativeDistance[cumulativeDistance.count - 1] }

    var segmentCount: Int { route.vertices.count - 1 }

    // MARK: Scrub position and the line

    /// Where sample `sample` sits on the line. Samples before the first vertex
    /// or after the last are held at the ends.
    public func position(atSample sample: Double) -> RoutePosition {
        let indices = route.sampleIndices
        guard sample.isFinite, sample > Double(indices[0]) else {
            return RoutePosition(segment: 0, fraction: 0)
        }
        guard sample < Double(indices[indices.count - 1]) else {
            return RoutePosition(segment: segmentCount - 1, fraction: 1)
        }
        // The last vertex whose sample index is at or before `sample`.
        var low = 0, high = indices.count - 1
        while high - low > 1 {
            let middle = (low + high) / 2
            if Double(indices[middle]) <= sample { low = middle } else { high = middle }
        }
        let start = Double(indices[low]), end = Double(indices[low + 1])
        return RoutePosition(segment: low, fraction: (sample - start) / (end - start))
    }

    /// The sample index at a point on the line, the inverse of
    /// `position(atSample:)` between the ends.
    public func sample(at position: RoutePosition) -> Double {
        let segment = clampedSegment(position.segment)
        let start = Double(route.sampleIndices[segment])
        let end = Double(route.sampleIndices[segment + 1])
        return start + (end - start) * clampedFraction(position.fraction)
    }

    /// The vertex nearest to a point on the line.
    public func nearestVertex(to position: RoutePosition) -> Int {
        let segment = clampedSegment(position.segment)
        return clampedFraction(position.fraction) < 0.5 ? segment : segment + 1
    }

    /// The source sample a vertex was taken from, or nil when there is no such
    /// vertex.
    public func sample(atVertex vertex: Int) -> Int? {
        route.sampleIndices.indices.contains(vertex) ? route.sampleIndices[vertex] : nil
    }

    // MARK: Points on the line

    public func coordinate(at position: RoutePosition) -> Coordinate {
        let segment = clampedSegment(position.segment)
        return Geodesy.interpolate(
            route.vertices[segment], route.vertices[segment + 1], clampedFraction(position.fraction)
        )
    }

    /// Metres along the route to a point on the line.
    public func distance(at position: RoutePosition) -> Double {
        let segment = clampedSegment(position.segment)
        let start = cumulativeDistance[segment], end = cumulativeDistance[segment + 1]
        return start + (end - start) * clampedFraction(position.fraction)
    }

    /// The point `metres` along the route, held at the ends.
    public func position(atDistance metres: Double) -> RoutePosition {
        guard metres.isFinite, metres > 0 else { return RoutePosition(segment: 0, fraction: 0) }
        guard metres < totalDistance else { return RoutePosition(segment: segmentCount - 1, fraction: 1) }
        var low = 0, high = cumulativeDistance.count - 1
        while high - low > 1 {
            let middle = (low + high) / 2
            if cumulativeDistance[middle] <= metres { low = middle } else { high = middle }
        }
        let start = cumulativeDistance[low], length = cumulativeDistance[low + 1] - start
        return RoutePosition(segment: low, fraction: length > 0 ? (metres - start) / length : 0)
    }

    /// How far along the drawn line a point is, as a fraction of its projected
    /// length: the value MapKit's `strokeEnd` takes to stop the line there.
    public func strokeFraction(at position: RoutePosition) -> Double {
        strokeFraction(at: position, vertices: 0...segmentCount)
    }

    /// The same, measured along only the part of the line from
    /// `vertices.lowerBound` to `vertices.upperBound`, held to `0...1`. A
    /// polyline drawn for one band run takes this as its `strokeEnd`.
    public func strokeFraction(at position: RoutePosition, vertices: ClosedRange<Int>) -> Double {
        let segment = clampedSegment(position.segment)
        let a = cumulativeProjectedLength[segment], b = cumulativeProjectedLength[segment + 1]
        let here = a + (b - a) * clampedFraction(position.fraction)
        let start = cumulativeProjectedLength[vertices.lowerBound]
        let end = cumulativeProjectedLength[vertices.upperBound]
        guard end > start else { return here >= end ? 1 : 0 }
        return min(1, max(0, (here - start) / (end - start)))
    }

    /// Each vertex's position along the line in `0...1`, for gradient stops.
    public func vertexLocations(_ parameter: GradientStops.Parameter) -> [Double] {
        switch parameter {
        case .vertexIndex:
            let last = Double(segmentCount)
            return route.vertices.indices.map { Double($0) / last }
        case .projectedLength:
            let total = cumulativeProjectedLength[segmentCount]
            guard total > 0 else { return vertexLocations(.vertexIndex) }
            return cumulativeProjectedLength.map { $0 / total }
        }
    }

    private func clampedSegment(_ segment: Int) -> Int { min(max(segment, 0), segmentCount - 1) }
    private func clampedFraction(_ fraction: Double) -> Double {
        fraction.isFinite ? min(max(fraction, 0), 1) : 0
    }
}
