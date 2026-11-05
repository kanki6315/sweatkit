import Foundation
import SweatKitModel
import SweatKitRouteMatching
import Testing

/// The corners of the mapping rule that the first round of tests left open:
/// equally close positions, the direction of the line at a corner and at its
/// end, repeated line points, and a line that crosses the 180 degree meridian.
/// Every expected value is worked out in the comment above it.
@Suite struct MappingEdgeTests {
    private func map(_ points: [P], onto line: ReferenceLine, rules: MatchingRules = .standard) -> [MappedPoint] {
        RouteAlignment.map(track(points), onto: line, rules: rules)
    }

    // MARK: Equally close positions

    /// "Of several equally close positions the one with the smallest route
    /// distance."
    @Test func ofTwoEquallyClosePositionsTheSmallerRouteDistanceWins() throws {
        // A line 100 m east and straight back along itself: 200 m. The spot
        // (60, 0) is on it twice, at 60 m going out and at 200 - 60 = 140 m
        // coming back. With a 200 m window the first point may search the
        // whole line, and both positions are 0 m away: 60 m wins.
        var rules = MatchingRules.standard
        rules.searchWindow = 200
        let line = try #require(referenceLine([P(0, 0), P(100, 0), P(0, 0)]))
        let onTheRoad = map([P(60, 0)], onto: line, rules: rules)
        #expect(close(onTheRoad[0].routeDistance, 60, within: 0.01))
        #expect(close(onTheRoad[0].distanceFromLine, 0, within: 0.01))

        // (60, 7) is 7 m from both passes. Matched to the outbound pass,
        // which heads east, it is 7 m to the left. The return pass heads
        // west and would have put it 7 m to the right.
        let beside = map([P(60, 7)], onto: line, rules: rules)
        #expect(close(beside[0].routeDistance, 60, within: 0.01))
        #expect(close(beside[0].distanceFromLine, 7, within: 0.01))
        #expect(close(beside[0].sideOffset, -7, within: 0.01))
    }

    /// "On an out-and-back ... the same spot maps to different route distances
    /// on each pass", here with no lane offset at all: the return retraces the
    /// outbound line exactly.
    @Test func anExactRetraceMapsEachPassToItsOwnRouteDistance() throws {
        // 1000 m east and 1000 m back along the same line, a point every
        // 10 m: 201 points, point i at 10 * i metres of route.
        //
        // Outbound, point k searches from 10 (k - 1) to 10 (k - 1) + 100.
        // Its own spot is in that range at 10 k. From k = 91 the range also
        // reaches past the turn to the same spot on the return, at
        // 2000 - 10 k, equally close: the smaller route distance, 10 k, wins.
        // On the return every position ahead is on the return leg, so there
        // is nothing to choose between.
        let course = Course.polyline([P(0, 0), P(1000, 0), P(0, 0)], step: 10)
        #expect(course.count == 201)
        let line = try #require(referenceLine(course))
        let mapped = map(course, onto: line)
        for (index, point) in mapped.enumerated() {
            #expect(close(point.routeDistance, 10 * Double(index), within: 0.01), "point \(index)")
            #expect(close(point.distanceFromLine, 0, within: 0.01), "point \(index)")
        }
        let measures = RouteAlignment.align(track(course), to: line).measures()
        #expect(measures.failedMeasures().isEmpty)
        #expect(measures.outcome() == .join)
    }

    @Test func aOneWayTripOnAnExactRetraceStaysOnTheOutboundPass() throws {
        // The 1000 m one-way trip maps to 0 ... 1000 m of the 2000 m line and
        // never onto the return: its last point is 1000 m short of the end.
        let line = try #require(referenceLine(Course.polyline([P(0, 0), P(1000, 0), P(0, 0)], step: 10)))
        let oneWay = Course.eastRoad(to: 1000, step: 10)
        let alignment = RouteAlignment.align(track(oneWay), to: line)
        for (index, point) in alignment.points.enumerated() {
            #expect(close(point.routeDistance, 10 * Double(index), within: 0.01), "point \(index)")
        }
        let measures = alignment.measures()
        #expect(close(measures.endGap, 1000, within: 0.01))
        #expect(close(measures.coverage, 0.5, within: 1e-5))
        #expect(measures.outcome() == .reject)
    }

    // MARK: The direction of the line at a corner and at its end

    /// "Where the matched position is a corner of the line, the direction is
    /// that of the piece that begins at the corner."
    @Test func atACornerTheSideIsTakenFromThePieceThatBeginsThere() throws {
        // 60 m east, then 60 m north. The point (90, -10) is beyond the
        // corner and below it. On the east leg the closest position is the
        // corner (60, 0); on the north leg it is the corner too. It is
        // sqrt(30^2 + 10^2) = 31.623 m away, at 60 m of route.
        // The piece that begins at the corner heads north, so east is to the
        // right: the offset (30 east, 10 south) has a sideways part of +30.
        // Measured against the east leg it would have been +10.
        let line = try #require(referenceLine([P(0, 0), P(60, 0), P(60, 60)]))
        let mapped = map([P(90, -10)], onto: line)
        #expect(close(mapped[0].routeDistance, 60, within: 0.01))
        #expect(close(mapped[0].distanceFromLine, 31.623, within: 0.01))
        #expect(close(mapped[0].sideOffset, 30, within: 0.01))
    }

    /// "...or of the last piece at the line's end."
    @Test func atTheEndOfTheLineTheSideIsTakenFromTheLastPiece() throws {
        // 60 m east, then 30 m north: 90 m. The point (70, 50) is past the
        // end at (60, 30), sqrt(10^2 + 20^2) = 22.361 m from it. The east leg
        // is no closer than sqrt(10^2 + 50^2) = 50.99 m.
        // The last piece heads north, so east is to the right: the offset
        // (10 east, 20 north) has a sideways part of +10.
        let line = try #require(referenceLine([P(0, 0), P(60, 0), P(60, 30)]))
        let mapped = map([P(70, 50)], onto: line)
        #expect(close(mapped[0].routeDistance, 90, within: 0.01))
        #expect(close(mapped[0].distanceFromLine, 22.361, within: 0.01))
        #expect(close(mapped[0].sideOffset, 10, within: 0.01))
    }

    /// The missed turn again, this time with its side offset. The first round
    /// left it unasserted because it hangs on the corner rule above.
    @Test func aMissedTurnSitsToTheRightOfTheLegItShouldHaveTaken() throws {
        // The route goes 500 m east and turns north. The rider overshoots
        // 160 m east and comes back: 67 points. Points 26 ... 33 are at east
        // 520 ... 660 going out, and 34 ... 40 at 640 ... 520 coming back.
        // All are held at the corner, where the line heads north, so each is
        // to the right by its distance past the corner. Point 33, at (660,
        // 0): 160 m away, 160 m to the right.
        //
        // Side offset: 17 points are held at 500 m, the corner twice and the
        // 15 overshoot points. Their side offsets add up to
        //   out: 20 + 40 + ... + 160 = 720, back: 140 + 120 + ... + 20 = 560,
        //   1280 in all.
        // The stretch from 500 m to 700 m holds those 17 and the ten points
        // from 520 m to 700 m up the north leg, 27 points: 1280 / 27 = 47.4.
        // No stretch can do worse, because every one that holds the 17 also
        // holds ten points on the line. If rounding leaves the point on the
        // end of a stretch out, it is 1280 / 26 = 49.2.
        let reference = Course.polyline([P(0, 0), P(500, 0), P(500, 500)])
        let missed = Course.polyline([P(0, 0), P(500, 0), P(660, 0), P(500, 0), P(500, 500)])
        let line = try #require(referenceLine(reference))
        let alignment = RouteAlignment.align(track(missed), to: line)
        #expect(close(alignment.points[33].routeDistance, 500, within: 0.01))
        #expect(close(alignment.points[33].distanceFromLine, 160, within: 0.01))
        #expect(close(alignment.points[33].sideOffset, 160, within: 0.01))
        let measures = alignment.measures()
        #expect((47.3 ... 49.3).contains(measures.worstSideOffset))
        #expect(measures.failedMeasures() == [.proximity, .lengthRatio, .sideOffset])
        #expect(measures.outcome() == .manualReview)
    }

    // MARK: Repeated points

    @Test func aLinePointRecordedTwiceDoesNotChangeTheMapping() throws {
        // The line has (100, 0) twice in a row, a piece with no length. It is
        // 200 m long all the same, and the points map as they would without
        // the repeat: 50, 100 and 150 m. (100, 5) sits over the repeat: the
        // piece that begins there with any length heads east, so north is to
        // the left, -5.
        let line = try #require(referenceLine([P(0, 0), P(100, 0), P(100, 0), P(200, 0)]))
        #expect(close(line.length, 200, within: 0.01))
        let mapped = map([P(50, 0), P(100, 5), P(150, 0)], onto: line)
        #expect(close(mapped[0].routeDistance, 50, within: 0.01))
        #expect(close(mapped[1].routeDistance, 100, within: 0.01))
        #expect(close(mapped[1].distanceFromLine, 5, within: 0.01))
        #expect(close(mapped[1].sideOffset, -5, within: 0.01))
        #expect(close(mapped[2].routeDistance, 150, within: 0.01))
    }

    @Test func aTrackPointRecordedTwiceResamplesAsIfRecordedOnce() {
        // 0, 40, 40 again and 110 m: still a 110 m straight, with points
        // every 25 m at 0, 25, 50, 75 and 100 m.
        let plane = Plane.equator
        let resampled = RouteDetection.resample(track([P(0, 0), P(40, 0), P(40, 0), P(110, 0)])).map(plane.point)
        #expect(resampled.count == 5)
        for (point, east) in zip(resampled, [0.0, 25, 50, 75, 100]) {
            #expect(close(point.e, east, within: 0.01) && close(point.n, 0, within: 0.01), "\(point)")
        }
    }

    @Test func aTrackAnExactNumberOfSpacingsLongKeepsEveryWholeSpacingBeforeItsEnd() {
        // A 100 m straight: 0, 25, 50 and 75 m are certain. Whether the
        // point at 100 m itself appears hangs on rounding in the measured
        // length, so either four or five points are right, and a fifth can
        // only be the end of the track.
        let plane = Plane.equator
        let resampled = RouteDetection.resample(track([P(0, 0), P(100, 0)])).map(plane.point)
        #expect(resampled.count == 4 || resampled.count == 5)
        for (point, east) in zip(resampled, [0.0, 25, 50, 75, 100]) {
            #expect(close(point.e, east, within: 0.01), "\(point)")
        }
    }

    // MARK: Rules that cannot be stepped along

    @Test func aSpacingOfZeroLeavesTheTrackAsItIs() {
        var rules = MatchingRules.standard
        rules.resampleSpacing = 0
        let road = track([P(0, 0), P(40, 0), P(110, 0)])
        #expect(RouteDetection.resample(road, rules: rules) == road.points.map(\.coordinate))
    }

    // MARK: The 180 degree meridian

    @Test func aLineAcrossThe180DegreeMeridianIsOneShortLine() throws {
        // From longitude 179.999 east to 179.999 west along the equator:
        // 0.002 degrees, 0.002 * 111,195.08 = 222.39 m. The track rides it in
        // four equal steps of 55.598 m and writes its longitudes past 180
        // instead of wrapping them.
        let line = try #require(ReferenceLine(points: [
            Coordinate(latitude: 0, longitude: 179.999),
            Coordinate(latitude: 0, longitude: -179.999),
        ]))
        #expect(close(line.length, 222.39, within: 0.01))
        let middle = line.coordinate(atRouteDistance: line.length / 2)
        #expect(Geodesy.distance(from: middle, to: Coordinate(latitude: 0, longitude: 180)) < 0.01)

        let longitudes = [179.999, 179.9995, 180.0, 180.0005, 180.001]
        let ride = CleanedTrack(
            points: longitudes.enumerated().map { index, longitude in
                TrackPoint(coordinate: Coordinate(latitude: 0, longitude: longitude), time: Double(index))
            },
            sportFamily: .cycling
        )
        let mapped = RouteAlignment.map(ride, onto: line)
        for (index, point) in mapped.enumerated() {
            #expect(close(point.routeDistance, 55.598 * Double(index), within: 0.01), "point \(index)")
            #expect(close(point.distanceFromLine, 0, within: 0.01), "point \(index)")
        }

        // The same road ridden west, back across the meridian, on a line
        // that runs west: the same 222.39 m and the same four steps.
        let westLine = try #require(ReferenceLine(points: Array(line.points.reversed())))
        #expect(close(westLine.length, 222.39, within: 0.01))
        let westRide = CleanedTrack(
            points: longitudes.reversed().enumerated().map { index, longitude in
                TrackPoint(coordinate: Coordinate(latitude: 0, longitude: longitude), time: Double(index))
            },
            sportFamily: .cycling
        )
        for (index, point) in RouteAlignment.map(westRide, onto: westLine).enumerated() {
            #expect(close(point.routeDistance, 55.598 * Double(index), within: 0.01), "point \(index)")
            #expect(close(point.distanceFromLine, 0, within: 0.01), "point \(index)")
        }
    }

    // MARK: A stored line

    @Test func aStoredLineReadsBackTheSame() throws {
        let line = try #require(referenceLine(Course.polyline([P(0, 0), P(500, 0), P(500, 500)])))
        let stored = try JSONEncoder().encode(line)
        #expect(try JSONDecoder().decode(ReferenceLine.self, from: stored) == line)
    }

    @Test func aStoredLineIsMeasuredAgainAndRefusedWhenItIsNotALine() throws {
        // A thousandth of a degree along the equator is 111.195 m, whatever
        // length was stored with it.
        let wrongLength = Data(#"{"points":[{"latitude":0,"longitude":0},{"latitude":0,"longitude":0.001}],"length":1}"#.utf8)
        let line = try JSONDecoder().decode(ReferenceLine.self, from: wrongLength)
        #expect(close(line.length, 111.195, within: 0.001))

        // One point is not a line, as in `init(points:)`.
        let onePoint = Data(#"{"points":[{"latitude":0,"longitude":0}],"length":5}"#.utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ReferenceLine.self, from: onePoint)
        }
    }

    @Test func twoPointsInOnePlaceMakeNoRoute() {
        // "nil when the track has fewer than two points or no length."
        #expect(RouteReference(track: track([P(5, 5), P(5, 5)])) == nil)
    }
}
