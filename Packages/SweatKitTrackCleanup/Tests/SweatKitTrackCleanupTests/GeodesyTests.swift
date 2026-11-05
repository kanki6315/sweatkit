import Foundation
import SweatKitModel
import SweatKitTrackCleanup
import Testing

/// The ruler. One degree of arc is 6,371,008.8 * pi / 180 = 111,195.080 m.
@Suite struct GeodesyTests {
    @Test func earthRadiusIsTheMeanRadius() {
        #expect(TrackGeodesy.earthRadius == 6_371_008.8)
    }

    @Test func aThousandthOfADegreeAlongTheEquator() {
        // 111,195.080 m / 1000 = 111.195 m.
        let distance = TrackGeodesy.distance(
            from: Coordinate(latitude: 0, longitude: 0),
            to: Coordinate(latitude: 0, longitude: 0.001)
        )
        #expect(close(distance, 111.195, within: 0.001))
    }

    @Test func distanceToAMeridianSegmentAwayFromTheEquator() {
        // A segment due north along longitude 7 at latitude 48. A point at
        // its middle, 2 m east: a degree of longitude there is
        // 111,195.080 * cos(48 degrees) = 111,195.080 * 0.669131 = 74,404.1 m,
        // so 2 m is 2 / 74,404.1 degrees.
        let start = Coordinate(latitude: 48, longitude: 7)
        let end = Coordinate(latitude: 48.001, longitude: 7)
        let point = Coordinate(latitude: 48.0005, longitude: 7 + 2 / 74_404.1)
        let distance = TrackGeodesy.distance(from: point, toSegmentFrom: start, to: end)
        #expect(close(distance, 2, within: 0.001))
    }

    @Test func distanceBeforeTheStartIsToTheStart() {
        // 3 m west of the start and 4 m north of the line: 5 m to the start.
        let distance = TrackGeodesy.distance(
            from: Ground.at(east: -3, north: 4),
            toSegmentFrom: Ground.at(east: 0),
            to: Ground.at(east: 100)
        )
        #expect(close(distance, 5))
    }

    @Test func lengthOfFewerThanTwoPointsIsZero() {
        #expect(TrackGeodesy.length(of: []) == 0)
        #expect(TrackGeodesy.length(of: [Ground.at(east: 5)]) == 0)
    }
}
