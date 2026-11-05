import Foundation
import SweatKitModel
import SweatKitRouteMatching
import Testing

/// "Each route has a reference line, taken from its first activity."
@Suite struct ReferenceLineTests {
    let plane = Plane.equator

    /// 500 m east, then 500 m north.
    private let corner = Course.polyline([P(0, 0), P(500, 0), P(500, 500)])

    private func expectPoint(_ coordinate: Coordinate, _ expected: P) {
        let point = plane.point(coordinate)
        #expect(close(point.e, expected.e, within: 0.01) && close(point.n, expected.n, within: 0.01), "\(point) is not \(expected)")
    }

    @Test func theLineIsTheFirstActivitysTrack() throws {
        let first = track(corner)
        let line = try #require(ReferenceLine(track: first))
        #expect(line.points == first.points.map(\.coordinate))
        // 500 + 500 = 1000 m.
        #expect(close(line.length, 1000, within: 0.01))
        #expect(close(line.length, first.length, within: 1e-6))
    }

    @Test func aLineNeedsTwoPointsAndSomeLength() {
        #expect(ReferenceLine(points: []) == nil)
        #expect(ReferenceLine(points: [plane.coordinate(P(0, 0))]) == nil)
        #expect(ReferenceLine(points: [plane.coordinate(P(5, 5)), plane.coordinate(P(5, 5))]) == nil)
        #expect(ReferenceLine(track: track([P(0, 0)])) == nil)
        #expect(ReferenceLine(points: [plane.coordinate(P(0, 0)), plane.coordinate(P(1, 0))]) != nil)
    }

    @Test func aRouteDistanceNamesAPositionOnTheLine() throws {
        let line = try #require(referenceLine(corner))
        // 300 m: on the first leg. 520 m: 20 m up the second leg.
        expectPoint(line.coordinate(atRouteDistance: 300), P(300, 0))
        expectPoint(line.coordinate(atRouteDistance: 500), P(500, 0))
        expectPoint(line.coordinate(atRouteDistance: 520), P(500, 20))
        // 333 m falls between the line points at 320 m and 340 m.
        expectPoint(line.coordinate(atRouteDistance: 333), P(333, 0))
    }

    @Test func positionsAreInterpolatedBetweenDistantLinePoints() throws {
        // Only the two ends, 1000 m apart: a quarter of the way is (250, 0).
        let line = try #require(referenceLine([P(0, 0), P(1000, 0)]))
        expectPoint(line.coordinate(atRouteDistance: 250), P(250, 0))
    }

    @Test func distancesOffEitherEndGiveTheEnds() throws {
        let line = try #require(referenceLine(corner))
        expectPoint(line.coordinate(atRouteDistance: 0), P(0, 0))
        expectPoint(line.coordinate(atRouteDistance: -10), P(0, 0))
        expectPoint(line.coordinate(atRouteDistance: 1000), P(500, 500))
        expectPoint(line.coordinate(atRouteDistance: 1200), P(500, 500))
    }

    /// The ghost marker is drawn at the position its route distance names.
    @Test func aLineVisitingASpotTwiceNamesItByEitherRouteDistance() throws {
        // Two laps of the 800 m square: 100 m and 900 m are both (100, 0).
        let line = try #require(referenceLine(Course.squareLaps(2)))
        expectPoint(line.coordinate(atRouteDistance: 100), P(100, 0))
        expectPoint(line.coordinate(atRouteDistance: 900), P(100, 0))
        expectPoint(line.coordinate(atRouteDistance: 1300), P(100, 200))
    }
}
