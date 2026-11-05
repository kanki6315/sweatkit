import Foundation
import SweatKitModel
import SweatKitRouteMatching

// Small deterministic builders for synthetic tracks. Every test lays its
// course out in metres on a flat local frame and converts to coordinates
// here, so the expected values can be worked out on paper.

/// A point in a flat local frame: metres east and north of the frame's origin.
struct P: Hashable {
    var e: Double
    var n: Double

    init(_ e: Double, _ n: Double) {
        self.e = e
        self.n = n
    }

    func moved(east: Double = 0, north: Double = 0) -> P {
        P(e + east, n + north)
    }

    func distance(to other: P) -> Double {
        ((other.e - e) * (other.e - e) + (other.n - n) * (other.n - n)).squareRoot()
    }
}

/// A flat local frame laid on the sphere the package measures with.
///
/// One metre north is `1 / (earthRadius * pi / 180)` degrees of latitude, and
/// one metre east is the same divided by the cosine of the origin's latitude.
/// At the equator, over the few kilometres a test covers, a distance in this
/// frame and the great-circle distance between the coordinates differ by well
/// under a millimetre. Away from the equator the east scale drifts with
/// latitude, so a test there keeps its course within 20 m of the origin's
/// latitude, where the difference over 1 km stays under 5 mm.
struct Plane {
    var origin: Coordinate

    /// The frame every test uses unless it says otherwise: its origin is at
    /// latitude 0, longitude 0, so the detection grid's cell (0, 0) has its
    /// south-west corner at the frame's origin.
    static let equator = Plane(origin: Coordinate(latitude: 0, longitude: 0))

    private var metresPerDegree: Double { Geodesy.earthRadius * .pi / 180 }
    private var eastScale: Double { cos(origin.latitude * .pi / 180) }

    func coordinate(_ p: P) -> Coordinate {
        Coordinate(
            latitude: origin.latitude + p.n / metresPerDegree,
            longitude: origin.longitude + p.e / (metresPerDegree * eastScale)
        )
    }

    func point(_ coordinate: Coordinate) -> P {
        P(
            (coordinate.longitude - origin.longitude) * metresPerDegree * eastScale,
            (coordinate.latitude - origin.latitude) * metresPerDegree
        )
    }
}

enum Course {
    /// Points every `step` metres along the straight legs joining `corners`.
    /// Every corner is a point, and each leg must be a whole number of steps.
    static func polyline(_ corners: [P], step: Double = 20) -> [P] {
        guard var previous = corners.first else { return [] }
        var points = [previous]
        for corner in corners.dropFirst() {
            let length = previous.distance(to: corner)
            let count = (length / step).rounded()
            precondition(abs(length - count * step) < 1e-9, "Each leg must be a whole number of steps")
            for k in 1...Int(count) {
                let fraction = Double(k) / count
                points.append(P(
                    previous.e + (corner.e - previous.e) * fraction,
                    previous.n + (corner.n - previous.n) * fraction
                ))
            }
            previous = corner
        }
        return points
    }

    /// A straight road heading east at a fixed northing, with a point every
    /// `step` metres from `from` to `to`.
    static func eastRoad(from: Double = 0, to: Double, north: Double = 0, step: Double = 20) -> [P] {
        polyline([P(from, north), P(to, north)], step: step)
    }

    /// A square circuit of 200 m sides, 800 m a lap, run anticlockwise from
    /// its south-west corner: east, north, west, then south back to the start.
    /// `laps` laps give `40 * laps + 1` points at the default 20 m step.
    static func squareLaps(_ laps: Int, corner: P = P(0, 0), step: Double = 20) -> [P] {
        var corners = [corner]
        for _ in 0..<laps {
            corners += [
                corner.moved(east: 200),
                corner.moved(east: 200, north: 200),
                corner.moved(north: 200),
                corner,
            ]
        }
        return polyline(corners, step: step)
    }

    /// The same square circuit run clockwise: north, east, south, then west.
    static func squareLapsClockwise(_ laps: Int, corner: P = P(0, 0), step: Double = 20) -> [P] {
        var corners = [corner]
        for _ in 0..<laps {
            corners += [
                corner.moved(north: 200),
                corner.moved(east: 200, north: 200),
                corner.moved(east: 200),
                corner,
            ]
        }
        return polyline(corners, step: step)
    }

    /// An out-and-back on one road: 1000 m east along the centre's northing,
    /// 10 m across the road, and 1000 m back west. 2010 m in all. The 10 m
    /// lane offset keeps the two passes apart so that no point is exactly as
    /// close to one pass as to the other. With the 10 m step there are 202
    /// points: 0...100 outbound, 101 the far end of the return lane, and
    /// 102...201 the return, so point `101 + k` is `10 * k` metres back.
    static func outAndBack(start: P = P(0, 0)) -> [P] {
        polyline([
            start,
            start.moved(east: 1000),
            start.moved(east: 1000, north: 10),
            start.moved(north: 10),
        ], step: 10)
    }

    /// A figure-of-eight through `centre`, 1600 m in all. The first lobe is a
    /// 200 m square to the north-east, run east, north, west, south. The path
    /// then carries straight on south through the centre into the second
    /// lobe, a 200 m square to the south-west, run south, west, north, east.
    /// The centre is visited three times: at 0 m, 800 m and 1600 m, which are
    /// points 0, 40 and 80 at the 20 m step.
    static func figureOfEight(centre: P = P(0, 0), secondLobeFirst: Bool = false) -> [P] {
        let northEast = [
            centre.moved(east: 200),
            centre.moved(east: 200, north: 200),
            centre.moved(north: 200),
            centre,
        ]
        let southWest = [
            centre.moved(north: -200),
            centre.moved(east: -200, north: -200),
            centre.moved(east: -200),
            centre,
        ]
        let corners = [centre] + (secondLobeFirst ? southWest + northEast : northEast + southWest)
        return polyline(corners)
    }
}

/// A deterministic generator (SplitMix64), so that noise is the same on every
/// run and on every machine.
struct SeededGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A value in `-1...1`.
    mutating func signedUnit() -> Double {
        Double(next() >> 11) / Double(1 << 53) * 2 - 1
    }
}

enum Noise {
    /// Slow GPS drift: a random walk that starts at 0, moves by at most
    /// `maxStep` metres from one point to the next, and never leaves
    /// `-bound...bound`. Real GPS error wanders like this; it does not jump
    /// independently at every sample.
    static func drift(count: Int, maxStep: Double, bound: Double, seed: UInt64) -> [Double] {
        var generator = SeededGenerator(seed: seed)
        var value = 0.0
        var values: [Double] = []
        for _ in 0..<count {
            values.append(value)
            value = min(bound, max(-bound, value + generator.signedUnit() * maxStep))
        }
        return values
    }
}

/// A cleaned track through `points`, ridden at a steady `speed` in metres per
/// second with no stops, so both clocks agree and the time at a point is the
/// distance to it divided by the speed.
func track(
    _ points: [P],
    speed: Double = 5,
    family: SportFamily = .cycling,
    pausePositionsAreReliable: Bool = true,
    plane: Plane = .equator
) -> CleanedTrack {
    var travelled = 0.0
    var trackPoints: [TrackPoint] = []
    for (index, point) in points.enumerated() {
        if index > 0 { travelled += points[index - 1].distance(to: point) }
        trackPoints.append(TrackPoint(coordinate: plane.coordinate(point), time: travelled / speed))
    }
    return CleanedTrack(
        points: trackPoints,
        sportFamily: family,
        pausePositionsAreReliable: pausePositionsAreReliable
    )
}

/// The reference line through `points`, one line point for each.
func referenceLine(_ points: [P], plane: Plane = .equator) -> ReferenceLine? {
    ReferenceLine(points: points.map(plane.coordinate))
}

/// A mapped point for tests that build a mapping by hand: at route distance
/// `s`, sitting `side` metres to the right of the line (negative for left)
/// and so `abs(side)` metres from it, at time `t` on both clocks.
func mapped(_ s: Double, side: Double = 0, t: TimeInterval = 0) -> MappedPoint {
    MappedPoint(routeDistance: s, distanceFromLine: abs(side), sideOffset: side, elapsedTime: t, movingTime: t)
}

/// A mapped point with a different time on each clock.
func mapped(_ s: Double, elapsed: TimeInterval, moving: TimeInterval) -> MappedPoint {
    MappedPoint(routeDistance: s, distanceFromLine: 0, sideOffset: 0, elapsedTime: elapsed, movingTime: moving)
}

/// An alignment built by hand from mapped points.
func alignment(
    _ points: [MappedPoint],
    referenceLength: Double,
    pausePositionsAreReliable: Bool = true
) -> Alignment {
    Alignment(
        points: points,
        referenceLength: referenceLength,
        trackLength: referenceLength,
        pausePositionsAreReliable: pausePositionsAreReliable
    )
}

extension AlignmentMeasures {
    /// Measures that pass all five rules with room to spare. Tests change one
    /// value at a time from here.
    static let clean = AlignmentMeasures(
        proximity: 1,
        startGap: 0,
        endGap: 0,
        coverage: 1,
        longestUnmappedStretch: 0,
        lengthRatio: 1,
        worstSideOffset: 0
    )

    func with(_ change: (inout AlignmentMeasures) -> Void) -> AlignmentMeasures {
        var copy = self
        change(&copy)
        return copy
    }
}

/// Whether two values agree to within `tolerance`.
func close(_ a: Double, _ b: Double, within tolerance: Double) -> Bool {
    abs(a - b) <= tolerance
}
