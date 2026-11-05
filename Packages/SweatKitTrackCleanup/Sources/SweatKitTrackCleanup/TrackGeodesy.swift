import Foundation
import SweatKitModel

/// How this package measures the ground: on a sphere of the mean earth
/// radius, the same model the flyover and route matching use, so a length
/// worked out here agrees with theirs.
public enum TrackGeodesy {
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

    /// The sum of the distances between consecutive positions, in metres. A
    /// line of fewer than two positions has length 0.
    public static func length(of line: [Coordinate]) -> Double {
        zip(line, line.dropFirst()).reduce(0) { $0 + distance(from: $1.0, to: $1.1) }
    }

    /// The shortest distance from `point` to the great-circle segment from
    /// `start` to `end`, in metres. When the nearest place on the circle lies
    /// beyond either end, it is the distance to that end.
    public static func distance(from point: Coordinate, toSegmentFrom start: Coordinate, to end: Coordinate) -> Double {
        let segmentLength = distance(from: start, to: end)
        let toPoint = distance(from: start, to: point)
        guard segmentLength > 0, toPoint > 0 else { return toPoint }
        let angleToPoint = toPoint / earthRadius
        let bearingDifference = bearing(from: start, to: point) - bearing(from: start, to: end)
        // Cross-track and along-track distances on the sphere.
        let crossTrack = asin(max(-1, min(1, sin(angleToPoint) * sin(bearingDifference))))
        // In the right spherical triangle, tan(along) = tan(toPoint) * cos(bearing difference).
        let alongTrack = atan2(sin(angleToPoint) * cos(bearingDifference), cos(angleToPoint))
        if alongTrack <= 0 { return toPoint }
        if alongTrack * earthRadius >= segmentLength { return distance(from: end, to: point) }
        return abs(crossTrack) * earthRadius
    }

    /// The initial bearing from `a` to `b` in radians, clockwise from north.
    static func bearing(from a: Coordinate, to b: Coordinate) -> Double {
        let latitudeA = radians(a.latitude)
        let latitudeB = radians(b.latitude)
        let longitudeDifference = radians(b.longitude - a.longitude)
        return atan2(
            sin(longitudeDifference) * cos(latitudeB),
            cos(latitudeA) * sin(latitudeB) - sin(latitudeA) * cos(latitudeB) * cos(longitudeDifference)
        )
    }

    static func radians(_ degrees: Double) -> Double {
        degrees * .pi / 180
    }
}
