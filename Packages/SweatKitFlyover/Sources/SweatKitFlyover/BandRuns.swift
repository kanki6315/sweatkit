/// A stretch of the route drawn in one band: the segments from vertex
/// `vertices.lowerBound` to vertex `vertices.upperBound`. Neighbouring runs
/// share their boundary vertex, so the drawn line has no gaps.
public struct BandRun: Hashable, Sendable {
    public var band: Int
    public var vertices: ClosedRange<Int>

    public init(band: Int, vertices: ClosedRange<Int>) {
        self.band = band
        self.vertices = vertices
    }
}

public enum BandRuns {
    /// Splits a route into maximal runs of segments in the same band. Segment
    /// `i` takes `bands[i]`, so the last vertex's band does not start a run.
    /// Returns no runs for fewer than two vertices.
    public static func split(_ bands: [Int]) -> [BandRun] {
        guard bands.count >= 2 else { return [] }
        var runs: [BandRun] = []
        var start = 0
        for vertex in 1..<(bands.count - 1) where bands[vertex] != bands[start] {
            runs.append(BandRun(band: bands[start], vertices: start...vertex))
            start = vertex
        }
        runs.append(BandRun(band: bands[start], vertices: start...(bands.count - 1)))
        return runs
    }
}

/// Colour stops for drawing the whole route as one gradient polyline with
/// hard edges between bands.
public enum GradientStops {
    /// How a stop's location along the line is measured. MapKit's gradient
    /// renderer documents locations as running from 0 at the start to 1 at the
    /// end without saying whether by vertex or by length, so both are offered
    /// and the device check settles which lines up with the band runs.
    public enum Parameter: String, Hashable, Sendable, CaseIterable {
        /// Vertex `i` of `n` sits at `i / (n - 1)`.
        case vertexIndex
        /// Each vertex sits at its fraction of the projected length.
        case projectedLength
    }

    /// One colour stop.
    public struct Stop: Hashable, Sendable {
        public var location: Double
        public var band: Int

        public init(location: Double, band: Int) {
            self.location = location
            self.band = band
        }
    }

    /// Two stops per run, at its first and last vertex. Where runs meet, the
    /// end of one and the start of the next share a location, which draws a
    /// hard edge instead of a blend.
    public static func make(runs: [BandRun], vertexLocations: [Double]) -> [Stop] {
        runs.flatMap { run -> [Stop] in
            guard vertexLocations.indices.contains(run.vertices.lowerBound),
                  vertexLocations.indices.contains(run.vertices.upperBound)
            else { return [] }
            return [
                Stop(location: vertexLocations[run.vertices.lowerBound], band: run.band),
                Stop(location: vertexLocations[run.vertices.upperBound], band: run.band),
            ]
        }
    }
}
