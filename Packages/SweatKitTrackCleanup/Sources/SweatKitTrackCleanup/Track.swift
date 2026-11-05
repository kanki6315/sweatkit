import SweatKitModel

/// One position kept by cleanup, with the grid second it came from.
public struct CleanedPosition: Hashable, Codable, Sendable {
    public var coordinate: Coordinate
    /// The second on the analysis grid this position was recorded in. It is
    /// also the elapsed time in seconds, since the grid is 1 Hz from the
    /// activity start.
    public var sampleIndex: Int
    /// The grid seconds this position stands for. One second, unless a stop
    /// was collapsed into it: then it runs from this position's own second to
    /// the last stopped second, so a scrub anywhere in the stop lands here.
    /// Seconds without a position, and seconds dropped as impossible, are
    /// inside the range only when they fall within a stop.
    public var coveredSamples: ClosedRange<Int>

    public init(coordinate: Coordinate, sampleIndex: Int, coveredSamples: ClosedRange<Int>) {
        precondition(coveredSamples.lowerBound == sampleIndex, "A position covers seconds from its own on")
        self.coordinate = coordinate
        self.sampleIndex = sampleIndex
        self.coveredSamples = coveredSamples
    }

    /// A position that stands for its own second only.
    public init(coordinate: Coordinate, sampleIndex: Int) {
        self.init(coordinate: coordinate, sampleIndex: sampleIndex, coveredSamples: sampleIndex...sampleIndex)
    }
}

/// An activity's positions after steps 1 and 2 of track cleanup: impossible
/// speeds dropped and jitter while stopped collapsed. This is the track route
/// matching reads. It is not simplified.
///
/// Points are in recorded order and their sample indices strictly increase.
public struct CleanedPositions: Hashable, Codable, Sendable {
    public var points: [CleanedPosition]
    public var sport: Sport
    /// False when the stream's pause data is incomplete, so moving time along
    /// the track cannot be trusted. Passed through from the stream.
    public var pausePositionsAreReliable: Bool

    public init(points: [CleanedPosition], sport: Sport, pausePositionsAreReliable: Bool) {
        self.points = points
        self.sport = sport
        self.pausePositionsAreReliable = pausePositionsAreReliable
    }

    /// The distance along the points, in metres. 0 for fewer than two.
    public var length: Double {
        TrackGeodesy.length(of: points.map(\.coordinate))
    }
}

/// The cleaned positions simplified for drawing: step 3 of track cleanup.
/// This is the line the flyover draws.
///
/// Every vertex is one of the cleaned positions, unmoved, so each keeps the
/// grid second it came from. Sample indices strictly increase.
public struct SimplifiedLine: Hashable, Codable, Sendable {
    public var vertices: [CleanedPosition]
    /// The tolerance the line was simplified to, in metres.
    public var tolerance: Double

    public init(vertices: [CleanedPosition], tolerance: Double) {
        self.vertices = vertices
        self.tolerance = tolerance
    }

    public var coordinates: [Coordinate] { vertices.map(\.coordinate) }

    /// The grid second of each vertex, in order.
    public var sampleIndices: [Int] { vertices.map(\.sampleIndex) }

    /// The distance along the vertices, in metres. 0 for fewer than two.
    public var length: Double {
        TrackGeodesy.length(of: coordinates)
    }
}
