import Foundation
import SweatKitModel
import SweatKitRouteMatching
import Testing

/// The ruler. One degree of arc on a sphere of radius 6,371,008.8 m is
/// 6,371,008.8 * pi / 180 = 111,195.080 m.
@Suite struct GeodesyTests {
    @Test func earthRadiusIsTheMeanRadius() {
        #expect(Geodesy.earthRadius == 6_371_008.8)
    }

    @Test func aThousandthOfADegreeAlongTheEquator() {
        // 111,195.080 m / 1000 = 111.195 m.
        let distance = Geodesy.distance(
            from: Coordinate(latitude: 0, longitude: 0),
            to: Coordinate(latitude: 0, longitude: 0.001)
        )
        #expect(close(distance, 111.195, within: 0.001))
    }

    @Test func aThousandthOfADegreeAlongAMeridian() {
        // A meridian is a great circle, so the same 111.195 m at any latitude.
        let distance = Geodesy.distance(
            from: Coordinate(latitude: 48, longitude: 7),
            to: Coordinate(latitude: 48.001, longitude: 7)
        )
        #expect(close(distance, 111.195, within: 0.001))
    }

    @Test func longitudeShrinksWithTheCosineOfLatitude() {
        // cos(60 degrees) = 0.5, so 111.195 * 0.5 = 55.598 m.
        let distance = Geodesy.distance(
            from: Coordinate(latitude: 60, longitude: 10),
            to: Coordinate(latitude: 60, longitude: 10.001)
        )
        #expect(close(distance, 55.598, within: 0.001))
    }

    @Test func distanceIsSymmetricAndZeroToItself() {
        let a = Coordinate(latitude: 51.5, longitude: -0.12)
        let b = Coordinate(latitude: 51.501, longitude: -0.121)
        #expect(Geodesy.distance(from: a, to: a) == 0)
        #expect(close(Geodesy.distance(from: a, to: b), Geodesy.distance(from: b, to: a), within: 1e-9))
    }

    /// The test frame and the package's ruler agree: 300 m east and 400 m
    /// north is 500 m away (a 3-4-5 triangle).
    @Test func theTestFrameAgreesWithTheRuler() {
        let plane = Plane.equator
        let distance = Geodesy.distance(from: plane.coordinate(P(0, 0)), to: plane.coordinate(P(300, 400)))
        #expect(close(distance, 500, within: 0.001))
    }

    @Test func theTestFrameAgreesWithTheRulerAwayFromTheEquator() {
        // 1000 m due east of an origin at 48 degrees north.
        let plane = Plane(origin: Coordinate(latitude: 48, longitude: 7))
        let distance = Geodesy.distance(from: plane.coordinate(P(0, 0)), to: plane.coordinate(P(1000, 0)))
        #expect(close(distance, 1000, within: 0.005))
    }

    @Test func trackLengthIsTheSumOfItsLegs() {
        // 300 m east, then 400 m north: 300 + 400 = 700 m.
        let lShaped = track([P(0, 0), P(300, 0), P(300, 400)])
        #expect(close(lShaped.length, 700, within: 0.001))
    }

    @Test func aTrackOfFewerThanTwoPointsHasNoLength() {
        #expect(track([]).length == 0)
        #expect(track([P(5, 5)]).length == 0)
    }
}
