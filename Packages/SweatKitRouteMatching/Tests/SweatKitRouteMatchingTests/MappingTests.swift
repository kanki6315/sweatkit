import Foundation
import SweatKitModel
import SweatKitRouteMatching
import Testing

/// Step 2.2: "Each point of the candidate is mapped to a position along the
/// reference line, in order. Route distance may only move forward, and each
/// point searches a limited window ahead of the previous match."
///
/// On a straight line heading east from the origin, the position closest to
/// a point at (east, north) is (east, 0), so its route distance is its
/// easting, its distance from the line is its northing, and north is to the
/// left.
@Suite struct MappingTests {
    /// 1000 m due east from the origin.
    private func eastLine() throws -> ReferenceLine {
        try #require(referenceLine(Course.eastRoad(to: 1000)))
    }

    private func map(_ points: [P], onto line: ReferenceLine, rules: MatchingRules = .standard) -> [MappedPoint] {
        RouteAlignment.map(track(points), onto: line, rules: rules)
    }

    // MARK: Closest position

    @Test func aPointOnTheLineMapsToItsOwnRouteDistance() throws {
        let mapped = map([P(0, 0), P(20, 0), P(40, 0), P(60, 0)], onto: try eastLine())
        #expect(mapped.count == 4)
        for (point, expected) in zip(mapped, [0.0, 20, 40, 60]) {
            #expect(close(point.routeDistance, expected, within: 0.01))
            #expect(close(point.distanceFromLine, 0, within: 0.01))
            #expect(close(point.sideOffset, 0, within: 0.01))
        }
    }

    @Test func aPointBetweenTwoLinePointsMapsOntoTheStraightPieceBetweenThem() throws {
        // The line has only its two ends, 1000 m apart. (63, 7) is closest to
        // (63, 0): route distance 63, 7 m away. (133, -4) is closest to
        // (133, 0), 70 m further on and so inside the window: 4 m away.
        let line = try #require(referenceLine([P(0, 0), P(1000, 0)]))
        let mapped = map([P(63, 7), P(133, -4)], onto: line)
        #expect(close(mapped[0].routeDistance, 63, within: 0.01))
        #expect(close(mapped[0].distanceFromLine, 7, within: 0.01))
        #expect(close(mapped[1].routeDistance, 133, within: 0.01))
        #expect(close(mapped[1].distanceFromLine, 4, within: 0.01))
    }

    // MARK: Side

    @Test func leftOfTravelIsNegativeAndRightIsPositive() throws {
        // Heading east, north is on the left and south on the right.
        let line = try eastLine()
        let north = map([P(0, 12), P(20, 12), P(40, 12)], onto: line)
        let south = map([P(0, -12), P(20, -12), P(40, -12)], onto: line)
        for (point, expected) in zip(north, [0.0, 20, 40]) {
            #expect(close(point.routeDistance, expected, within: 0.01))
            #expect(close(point.distanceFromLine, 12, within: 0.01))
            #expect(close(point.sideOffset, -12, within: 0.01))
        }
        for point in south {
            #expect(close(point.distanceFromLine, 12, within: 0.01))
            #expect(close(point.sideOffset, 12, within: 0.01))
        }
    }

    @Test func theSideFollowsTheLinesDirectionOfTravel() throws {
        // Heading north, east is on the right.
        let northbound = try #require(referenceLine(Course.polyline([P(0, 0), P(0, 1000)])))
        #expect(close(map([P(12, 40)], onto: northbound)[0].sideOffset, 12, within: 0.01))
        #expect(close(map([P(-12, 40)], onto: northbound)[0].sideOffset, -12, within: 0.01))
        #expect(close(map([P(12, 40)], onto: northbound)[0].routeDistance, 40, within: 0.01))

        // Heading west from (1000, 0), north is on the right. (960, 12) is
        // 40 m along the line.
        let westbound = try #require(referenceLine(Course.polyline([P(1000, 0), P(0, 0)])))
        let mapped = map([P(960, 12)], onto: westbound)
        #expect(close(mapped[0].routeDistance, 40, within: 0.01))
        #expect(close(mapped[0].sideOffset, 12, within: 0.01))
    }

    // MARK: Forward only

    @Test func routeDistanceNeverMovesBackward() throws {
        // The fourth point doubles back 10 m. Its search starts at the
        // previous match, 40 m, so it stays at 40 m and sits 10 m from that
        // position, straight back along the line: no sideways part.
        let mapped = map([P(0, 0), P(20, 0), P(40, 0), P(30, 0), P(60, 0)], onto: try eastLine())
        let expected = [0.0, 20, 40, 40, 60]
        for (point, distance) in zip(mapped, expected) {
            #expect(close(point.routeDistance, distance, within: 0.01))
        }
        #expect(close(mapped[3].distanceFromLine, 10, within: 0.01))
        #expect(close(mapped[3].sideOffset, 0, within: 0.01))
        #expect(close(mapped[4].distanceFromLine, 0, within: 0.01))
    }

    // MARK: Limited window

    @Test func aPointSearchesOnlyTheWindowAheadOfThePreviousMatch() throws {
        // The second point is 300 m on. It may search 0 to 100 m, where the
        // closest position is the 100 m point, 200 m short of it.
        let mapped = map([P(0, 0), P(300, 0)], onto: try eastLine())
        #expect(close(mapped[1].routeDistance, 100, within: 0.01))
        #expect(close(mapped[1].distanceFromLine, 200, within: 0.01))
    }

    @Test func theFirstPointSearchesFromTheStartOfTheLine() throws {
        // A track that begins 250 m along may search only 0 to 100 m: it maps
        // to 100 m, 150 m away.
        let mapped = map([P(250, 0)], onto: try eastLine())
        #expect(close(mapped[0].routeDistance, 100, within: 0.01))
        #expect(close(mapped[0].distanceFromLine, 150, within: 0.01))
    }

    @Test func theWindowComesFromTheRules() throws {
        // With a 500 m window the point 300 m on is reached.
        var rules = MatchingRules.standard
        rules.searchWindow = 500
        let mapped = map([P(0, 0), P(300, 0)], onto: try eastLine(), rules: rules)
        #expect(close(mapped[1].routeDistance, 300, within: 0.01))
        #expect(close(mapped[1].distanceFromLine, 0, within: 0.01))
    }

    // MARK: Ends of the line

    @Test func aPointPastTheEndMapsToTheEnd() throws {
        // The road ridden from its start to 40 m beyond the end of the 1000 m
        // line, straight on: 53 points. Point 50 is the end of the line.
        // Points 51 and 52 are held there, 20 m and 40 m beyond it, with no
        // sideways part.
        let mapped = map(Course.eastRoad(to: 1040), onto: try eastLine())
        #expect(mapped.count == 53)
        #expect(close(mapped[50].routeDistance, 1000, within: 0.01))
        #expect(close(mapped[50].distanceFromLine, 0, within: 0.01))
        #expect(close(mapped[51].routeDistance, 1000, within: 0.01))
        #expect(close(mapped[51].distanceFromLine, 20, within: 0.01))
        #expect(close(mapped[52].routeDistance, 1000, within: 0.01))
        #expect(close(mapped[52].distanceFromLine, 40, within: 0.01))
        #expect(close(mapped[52].sideOffset, 0, within: 0.01))
    }

    @Test func aPointBeforeTheStartMapsToTheStart() throws {
        let mapped = map([P(-40, 0)], onto: try eastLine())
        #expect(close(mapped[0].routeDistance, 0, within: 0.01))
        #expect(close(mapped[0].distanceFromLine, 40, within: 0.01))
    }

    // MARK: Shape of the result

    @Test func thereIsOneMappedPointForEachTrackPointInOrder() throws {
        let line = try eastLine()
        #expect(map(Course.eastRoad(to: 1000), onto: line).count == 51)
        #expect(map([], onto: line).isEmpty)
    }

    @Test func bothClocksAreCarriedOver() throws {
        let plane = Plane.equator
        let points = [
            TrackPoint(coordinate: plane.coordinate(P(0, 0)), elapsedTime: 100, movingTime: 90),
            TrackPoint(coordinate: plane.coordinate(P(20, 0)), elapsedTime: 130, movingTime: 94),
        ]
        let mapped = RouteAlignment.map(CleanedTrack(points: points, sportFamily: .cycling), onto: try eastLine())
        #expect(mapped.map(\.elapsedTime) == [100, 130])
        #expect(mapped.map(\.movingTime) == [90, 94])
    }

    // MARK: Lines with corners

    @Test func routeDistanceRunsOnRoundACorner() throws {
        // 500 m east then 500 m north. A track along it with a point every
        // 20 m maps point i to 20 * i metres.
        let course = Course.polyline([P(0, 0), P(500, 0), P(500, 500)])
        let mapped = map(course, onto: try #require(referenceLine(course)))
        #expect(mapped.count == 51)
        for (index, point) in mapped.enumerated() {
            #expect(close(point.routeDistance, 20 * Double(index), within: 0.01))
            #expect(close(point.distanceFromLine, 0, within: 0.01))
        }
        // (500, 20) is the first point past the corner: 500 + 20.
        #expect(close(mapped[26].routeDistance, 520, within: 0.01))
    }

    // MARK: Places visited twice

    /// "The ordered mapping handles places visited twice. On an out-and-back
    /// or a lapped circuit, the same spot maps to different route distances on
    /// each pass."
    @Test func onALappedCircuitEachPassHasItsOwnRouteDistance() throws {
        let laps = Course.squareLaps(2)
        let mapped = map(laps, onto: try #require(referenceLine(laps)))
        // The corner is passed at 0, 800 and 1600 m.
        #expect(close(mapped[0].routeDistance, 0, within: 0.01))
        #expect(close(mapped[40].routeDistance, 800, within: 0.01))
        #expect(close(mapped[80].routeDistance, 1600, within: 0.01))
        // (100, 0) is passed 100 m into each lap: at 100 m and at 900 m.
        #expect(laps[5] == laps[45])
        #expect(close(mapped[5].routeDistance, 100, within: 0.01))
        #expect(close(mapped[45].routeDistance, 900, within: 0.01))
        #expect(mapped.allSatisfy { $0.distanceFromLine < 0.01 })
    }

    @Test func onAnOutAndBackEachPassHasItsOwnRouteDistance() throws {
        let course = Course.outAndBack()
        let mapped = map(course, onto: try #require(referenceLine(course)))
        // Point 50 is 500 m out. Point 151 is beside it on the way back:
        // 1000 m out + 10 m across + 500 m back = 1510 m.
        #expect(close(mapped[50].routeDistance, 500, within: 0.01))
        #expect(close(mapped[151].routeDistance, 1510, within: 0.01))
        #expect(close(mapped[201].routeDistance, 2010, within: 0.01))
        #expect(mapped.allSatisfy { $0.distanceFromLine < 0.01 })
    }

    /// A figure-of-eight.
    @Test func onAFigureOfEightTheCrossingMapsToEachPassInTurn() throws {
        let course = Course.figureOfEight()
        let mapped = map(course, onto: try #require(referenceLine(course)))
        // The centre is the start, the crossing after the 800 m first lobe,
        // and the finish after the 800 m second lobe.
        #expect(close(mapped[0].routeDistance, 0, within: 0.01))
        #expect(close(mapped[40].routeDistance, 800, within: 0.01))
        #expect(close(mapped[80].routeDistance, 1600, within: 0.01))
        for (index, point) in mapped.enumerated() {
            #expect(close(point.routeDistance, 20 * Double(index), within: 0.01))
        }
        #expect(mapped.allSatisfy { $0.distanceFromLine < 0.01 })
    }
}
