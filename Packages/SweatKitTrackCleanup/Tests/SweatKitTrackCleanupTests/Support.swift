import Foundation
import SweatKitModel

/// Ground positions for synthetic tracks, laid out in metres on the equator.
///
/// One degree of arc on a sphere of radius 6,371,008.8 m is
/// 6,371,008.8 * pi / 180 = 111,195.080 m. Along the equator a degree of
/// longitude is that same arc, so `east` metres is exactly `east` metres of
/// great circle, and for the short `north` offsets used here the flat
/// Pythagorean distance differs from the spherical one by far less than a
/// micrometre.
enum Ground {
    static let metresPerDegree = 6_371_008.8 * Double.pi / 180

    static func at(east: Double, north: Double = 0) -> Coordinate {
        Coordinate(latitude: north / metresPerDegree, longitude: east / metresPerDegree)
    }
}

/// One second of a synthetic stream: a position in metres, or none, and a
/// speed in metres per second, or none.
struct Second {
    var east: Double?
    var north: Double
    var speed: Double?

    init(east: Double?, north: Double = 0, speed: Double?) {
        self.east = east
        self.north = north
        self.speed = speed
    }

    /// A second with no position.
    static func noPosition(speed: Double? = nil) -> Second {
        Second(east: nil, speed: speed)
    }
}

/// A stream with one grid second per element of `seconds`. Every other
/// channel is missing.
func makeStream(_ seconds: [Second], pauses: PauseData = .known(paused: [])) -> AnalysisStream {
    var stream = AnalysisStream(
        rulesVersion: 1,
        start: Date(timeIntervalSince1970: 0),
        count: seconds.count,
        pauses: pauses
    )
    stream.latitude = Series(seconds.map { $0.east == nil ? nil : $0.north / Ground.metresPerDegree })
    stream.longitude = Series(seconds.map { $0.east.map { $0 / Ground.metresPerDegree } })
    stream.speed = Series(seconds.map(\.speed))
    return stream
}

/// `count` seconds moving due east at `speed` metres per second from
/// `startEast`, one second apart, so second i is at startEast + i * speed.
func steadyEast(count: Int, speed: Double, startEast: Double = 0) -> [Second] {
    (0..<count).map { Second(east: startEast + Double($0) * speed, speed: speed) }
}

func close(_ a: Double, _ b: Double, within tolerance: Double = 1e-6) -> Bool {
    abs(a - b) <= tolerance
}
