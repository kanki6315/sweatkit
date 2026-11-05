import Foundation
import SweatKitModel

/// Spherical-earth helpers. Accurate to well under a metre over the few
/// hundred metres the follow camera looks ahead.
enum Geodesy {
    /// The mean earth radius in metres.
    static let earthRadius = 6_371_008.8

    /// The great-circle distance in metres.
    static func distance(_ a: Coordinate, _ b: Coordinate) -> Double {
        let lat1 = radians(a.latitude), lat2 = radians(b.latitude)
        let dLat = lat2 - lat1
        let dLon = radians(b.longitude - a.longitude)
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadius * asin(min(1, sqrt(h)))
    }

    /// The initial bearing from `a` to `b` in degrees clockwise from north,
    /// in `0..<360`.
    static func bearing(from a: Coordinate, to b: Coordinate) -> Double {
        let lat1 = radians(a.latitude), lat2 = radians(b.latitude)
        let dLon = radians(b.longitude - a.longitude)
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return normalizedDegrees(degrees(atan2(y, x)))
    }

    /// The point a fraction of the way from `a` to `b`, interpolated in
    /// degrees. Drawn segments are short enough that this matches the line
    /// MapKit draws.
    static func interpolate(_ a: Coordinate, _ b: Coordinate, _ fraction: Double) -> Coordinate {
        Coordinate(
            latitude: a.latitude + (b.latitude - a.latitude) * fraction,
            longitude: a.longitude + (b.longitude - a.longitude) * fraction
        )
    }

    /// The Web Mercator projection, in units where the full circle of
    /// longitude is 1. MapKit's map points are this scaled by a constant, so
    /// fractions of length measured here match fractions MapKit measures.
    static func mercator(_ c: Coordinate) -> (x: Double, y: Double) {
        let lat = radians(max(-85.051_128_78, min(85.051_128_78, c.latitude)))
        return (c.longitude / 360, log(tan(.pi / 4 + lat / 2)) / (2 * .pi))
    }

    /// `angle` wrapped into `0..<360`.
    static func normalizedDegrees(_ angle: Double) -> Double {
        let wrapped = angle.truncatingRemainder(dividingBy: 360)
        return wrapped < 0 ? wrapped + 360 : wrapped
    }

    /// The signed shortest turn from `from` to `to`, in `-180..<180`.
    static func shortestTurn(from: Double, to: Double) -> Double {
        normalizedDegrees(to - from + 180) - 180
    }

    static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }
    static func degrees(_ radians: Double) -> Double { radians * 180 / .pi }
}
