import SweatKitModel

/// A route ready to draw: already cleaned, simplified and coloured by the
/// caller. The flyover draws it as given and does no decoding, cleanup,
/// simplification or zone calculation of its own.
///
/// Vertex `i` starts the segment to vertex `i + 1`, and that segment is drawn
/// in the colour of `bands[i]`. The last vertex's band is kept for symmetry
/// but colours nothing.
public struct FlyoverRoute: Hashable, Sendable {
    /// Why a route was rejected.
    public enum Problem: Error, Hashable, Sendable {
        /// A route needs at least two vertices to draw a line.
        case tooFewVertices
        /// Vertices, bands and sample indices must have the same count.
        case countMismatch
        /// A coordinate is not finite or is outside the valid range.
        case invalidCoordinate(vertex: Int)
        /// Band indices are zero or greater.
        case negativeBand(vertex: Int)
        /// Sample indices are zero or greater and strictly increasing.
        case sampleIndicesNotIncreasing(vertex: Int)
    }

    /// The drawn vertices, in route order.
    public let vertices: [Coordinate]
    /// The colour band of the segment that starts at each vertex. The caller
    /// supplies one colour per band.
    public let bands: [Int]
    /// The index of the source sample each vertex was taken from, strictly
    /// increasing. A scrub position is a sample index, so this maps it to the
    /// line and back.
    public let sampleIndices: [Int]

    public init(vertices: [Coordinate], bands: [Int], sampleIndices: [Int]) throws(Problem) {
        guard vertices.count >= 2 else { throw .tooFewVertices }
        guard bands.count == vertices.count, sampleIndices.count == vertices.count else {
            throw .countMismatch
        }
        for (index, vertex) in vertices.enumerated() {
            guard vertex.latitude.isFinite, vertex.longitude.isFinite,
                  abs(vertex.latitude) <= 90, abs(vertex.longitude) <= 180
            else { throw .invalidCoordinate(vertex: index) }
        }
        if let index = bands.firstIndex(where: { $0 < 0 }) {
            throw .negativeBand(vertex: index)
        }
        guard let first = sampleIndices.first, first >= 0 else {
            throw .sampleIndicesNotIncreasing(vertex: 0)
        }
        for index in 1..<sampleIndices.count where sampleIndices[index] <= sampleIndices[index - 1] {
            throw .sampleIndicesNotIncreasing(vertex: index)
        }
        self.vertices = vertices
        self.bands = bands
        self.sampleIndices = sampleIndices
    }

    /// The first and last source samples the route covers.
    public var sampleRange: ClosedRange<Int> {
        sampleIndices[0]...sampleIndices[sampleIndices.count - 1]
    }
}
