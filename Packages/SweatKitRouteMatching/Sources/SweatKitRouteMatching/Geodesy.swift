import Foundation
import SweatKitModel

/// How this package measures the ground.
///
/// The spec does not say how a distance between two positions is measured.
/// This package measures on a sphere of the mean earth radius, the same model
/// the flyover uses. Every length, offset and threshold check goes through
/// it, so two tracks are always compared with one ruler.
public enum Geodesy {
    /// The mean earth radius in metres.
    public static let earthRadius = 6_371_008.8

    /// The great-circle distance between two positions, in metres.
    public static func distance(from a: Coordinate, to b: Coordinate) -> Double {
        let latitudeA = radians(a.latitude)
        let latitudeB = radians(b.latitude)
        let sinHalfLatitude = sin((latitudeB - latitudeA) / 2)
        let sinHalfLongitude = sin(radians(b.longitude - a.longitude) / 2)
        let haversine = sinHalfLatitude * sinHalfLatitude
            + cos(latitudeA) * cos(latitudeB) * sinHalfLongitude * sinHalfLongitude
        return 2 * earthRadius * asin(min(1, haversine.squareRoot()))
    }
}

extension Geodesy {
    /// The length on the ground of one degree of latitude, in metres.
    static let metresPerDegree = earthRadius * .pi / degreesInHalfTurn

    /// The degrees in half a turn. Longitudes run from minus this to plus this.
    static let degreesInHalfTurn = 180.0

    /// Two positions on a line that are closer than this, in metres, are
    /// treated as the same position. It is a thousandth of a millimetre: far
    /// above the rounding error of a distance worked out in double precision,
    /// which is about a millionth of a millimetre, and far below anything a
    /// GPS fix can mean. It is what "equally close" and "at a corner" mean in
    /// the mapping.
    static let samePositionTolerance = 1e-6

    static func radians(_ degrees: Double) -> Double {
        degrees * .pi / degreesInHalfTurn
    }

    /// The change in longitude from `a` to `b` the short way round, in
    /// degrees, so that a step across the 180 degree meridian is a small
    /// step and not a trip round the world.
    static func longitudeDifference(from a: Double, to b: Double) -> Double {
        let fullTurn = 2 * degreesInHalfTurn
        var difference = (b - a).truncatingRemainder(dividingBy: fullTurn)
        if difference > degreesInHalfTurn {
            difference -= fullTurn
        } else if difference < -degreesInHalfTurn {
            difference += fullTurn
        }
        return difference
    }

    /// The position a fraction of the way from `a` to `b`, by straight-line
    /// interpolation of latitude and longitude. A fraction of 0 or below gives
    /// `a` itself and 1 or above gives `b` itself.
    static func interpolate(from a: Coordinate, to b: Coordinate, fraction: Double) -> Coordinate {
        if fraction <= 0 { return a }
        if fraction >= 1 { return b }
        return Coordinate(
            latitude: a.latitude + (b.latitude - a.latitude) * fraction,
            longitude: a.longitude + longitudeDifference(from: a.longitude, to: b.longitude) * fraction
        )
    }
}

/// A flat frame laid on the ground around one position, in metres east and
/// north of it. It is used only to find where on a straight piece of line a
/// nearby point falls, and which side of the piece the point is on. Distances
/// that are reported or compared with a threshold are measured with
/// `Geodesy.distance`.
struct LocalFrame {
    struct Vector {
        var east: Double
        var north: Double

        static func - (a: Vector, b: Vector) -> Vector {
            Vector(east: a.east - b.east, north: a.north - b.north)
        }

        func dot(_ other: Vector) -> Double {
            east * other.east + north * other.north
        }

        var length: Double {
            dot(self).squareRoot()
        }
    }

    let origin: Coordinate
    /// The length on the ground of one degree of longitude at the origin.
    private let metresPerDegreeEast: Double

    init(origin: Coordinate) {
        self.origin = origin
        metresPerDegreeEast = Geodesy.metresPerDegree * cos(Geodesy.radians(origin.latitude))
    }

    func vector(to coordinate: Coordinate) -> Vector {
        Vector(
            east: Geodesy.longitudeDifference(from: origin.longitude, to: coordinate.longitude) * metresPerDegreeEast,
            north: (coordinate.latitude - origin.latitude) * Geodesy.metresPerDegree
        )
    }
}

/// A line through positions, with the distance along it to each one.
struct Polyline {
    let points: [Coordinate]
    /// `cumulative[i]` is the distance along the line from its first point to
    /// `points[i]`, in metres. It never decreases.
    let cumulative: [Double]

    init(_ points: [Coordinate]) {
        self.points = points
        var cumulative: [Double] = []
        cumulative.reserveCapacity(points.count)
        var travelled = 0.0
        for index in points.indices {
            if index > points.startIndex {
                travelled += Geodesy.distance(from: points[index - 1], to: points[index])
            }
            cumulative.append(travelled)
        }
        self.cumulative = cumulative
    }

    /// The length of the whole line. 0 for a line of fewer than two points.
    var length: Double {
        cumulative.last ?? 0
    }

    /// The position at a distance along the line, or nil when the line has no
    /// points. A distance below 0 gives the first point and one beyond the
    /// length gives the last.
    func coordinate(at distance: Double) -> Coordinate? {
        guard let first = points.first, let last = points.last else { return nil }
        if !(distance > 0) { return first }
        if distance >= length { return last }
        // The first point at or beyond the distance. It is never the first
        // point of the line, because the distance is above 0.
        let upper = firstIndex(in: cumulative.count) { cumulative[$0] >= distance }
        guard upper > 0, upper < points.count else { return last }
        let pieceLength = cumulative[upper] - cumulative[upper - 1]
        guard pieceLength > 0 else { return points[upper] }
        return Geodesy.interpolate(
            from: points[upper - 1],
            to: points[upper],
            fraction: (distance - cumulative[upper - 1]) / pieceLength
        )
    }
}

/// The first index in `0..<count` for which `isAtOrBeyond` is true, or `count`
/// when there is none. The condition must be false for every index before
/// some point and true from there on, which holds for anything that never
/// decreases, such as route distance and time along an effort.
func firstIndex(in count: Int, where isAtOrBeyond: (Int) -> Bool) -> Int {
    var low = 0
    var high = count
    while low < high {
        let middle = low + (high - low) / 2
        if isAtOrBeyond(middle) {
            high = middle
        } else {
            low = middle + 1
        }
    }
    return low
}
