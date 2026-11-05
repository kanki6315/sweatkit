import Foundation
import SweatKitModel
import SweatKitRouteMatching
import Testing

/// Both steps together: detection nominates, alignment decides, and "an
/// activity joins a route only if alignment succeeds".
///
/// Roads here run from east 10 to east 2010 at a northing inside row 0 of the
/// grid, so that tracks a few metres apart record the same cells.
@Suite struct MatcherTests {
    private func road(north: Double, from: Double = 10, to: Double = 2010) -> [P] {
        Course.eastRoad(from: from, to: to, north: north)
    }

    private func route(_ points: [P], family: SportFamily = .cycling) throws -> RouteReference {
        try #require(RouteReference(track: track(points, family: family)))
    }

    // MARK: Building a reference

    @Test func aRouteReferenceHoldsTheSignatureAndLineOfItsFirstActivity() throws {
        let first = track(road(north: 20), family: .onFoot)
        let reference = try #require(RouteReference(track: first))
        #expect(reference.signature == TrackSignature(track: first))
        #expect(reference.line == ReferenceLine(track: first))
        #expect(reference.signature.sportFamily == .onFoot)
        #expect(close(reference.line.length, 2000, within: 0.01))
    }

    @Test func aTrackWithoutACourseMakesNoReference() {
        #expect(RouteReference(track: track([])) == nil)
        #expect(RouteReference(track: track([P(0, 0)])) == nil)
    }

    // MARK: One route

    /// "A commute or a regular loop becomes a route the second time it is
    /// done." The first activity matches nothing and waits; the second is
    /// matched against it and joins.
    @Test func theSecondActivityOnACourseJoinsTheFirst() throws {
        let first = track(road(north: 20))
        #expect(RouteMatcher.match(first, against: []).isEmpty)

        let waiting = try #require(RouteReference(track: first))
        // The second ride reads 3 m further north: side offset -3, all else
        // perfect.
        let matches = RouteMatcher.match(track(road(north: 23)), against: [waiting])
        #expect(matches.count == 1)
        #expect(matches.first?.routeIndex == 0)
        #expect(matches.first?.outcome == .join)
        let measures = try #require(matches.first?.measures)
        #expect(close(measures.worstSideOffset, -3, within: 0.01))
        #expect(matches.first?.alignment.points.count == 101)
    }

    @Test func anActivityInAnotherSportFamilyIsNeverAligned() throws {
        let matches = RouteMatcher.match(
            track(road(north: 20), family: .onFoot),
            against: [try route(road(north: 20))]
        )
        #expect(matches.isEmpty)
    }

    /// The M6 exit test: "every alignment test case passes, with the
    /// parallel-road case sent to review".
    @Test func aParallelRoad20MetresAwayIsSentToReview() throws {
        // North 5 and north 25 are in the same row of cells, so detection
        // shortlists the pair. Alignment finds every point 20 m to the left.
        let matches = RouteMatcher.match(track(road(north: 25)), against: [try route(road(north: 5))])
        #expect(matches.map(\.outcome) == [.manualReview])
        #expect(matches.first?.measures.failedMeasures() == [.sideOffset])
    }

    @Test func aParallelRoad40MetresAwayIsShortlistedThenRejected() throws {
        // North 5 and north 45: same cells, but no point within 30 m.
        let matches = RouteMatcher.match(track(road(north: 45)), against: [try route(road(north: 5))])
        #expect(matches.map(\.outcome) == [.reject])
    }

    @Test func aCircuitRunTheOtherWayIsShortlistedThenRejected() throws {
        let matches = RouteMatcher.match(
            track(Course.squareLapsClockwise(1, corner: P(10, 10))),
            against: [try route(Course.squareLaps(1, corner: P(10, 10)))]
        )
        #expect(matches.map(\.outcome) == [.reject])
    }

    @Test func aFigureOfEightWithItsLobesSwappedIsShortlistedThenRejected() throws {
        let matches = RouteMatcher.match(
            track(Course.figureOfEight(centre: P(10, 10), secondLobeFirst: true)),
            against: [try route(Course.figureOfEight(centre: P(10, 10)))]
        )
        #expect(matches.map(\.outcome) == [.reject])
    }

    @Test func threeLapsAreNeverAlignedWithATwoLapRoute() throws {
        // Detection's distance gate turns it away, so there is no match at
        // all, not a rejected one.
        let matches = RouteMatcher.match(
            track(Course.squareLaps(3, corner: P(10, 10))),
            against: [try route(Course.squareLaps(2, corner: P(10, 10)))]
        )
        #expect(matches.isEmpty)
    }

    @Test func aStart20MetresLateJoinsThroughBothSteps() throws {
        let matches = RouteMatcher.match(
            track(road(north: 20, from: 30)),
            against: [try route(road(north: 20))]
        )
        #expect(matches.map(\.outcome) == [.join])
        let measures = try #require(matches.first?.measures)
        #expect(close(measures.startGap, 20, within: 0.01))
    }

    @Test func aStartOneKilometreInMatchesNothing() throws {
        let matches = RouteMatcher.match(
            track(road(north: 20, from: 1010, to: 3010)),
            against: [try route(road(north: 20, to: 3010))]
        )
        #expect(matches.isEmpty)
    }

    @Test func aTrackWithoutACourseMatchesNothing() throws {
        let routes = [try route(road(north: 20))]
        #expect(RouteMatcher.match(track([]), against: routes).isEmpty)
        #expect(RouteMatcher.match(track([P(10, 20)]), against: routes).isEmpty)
    }

    // MARK: Several routes

    /// "...or the activity also aligns with a second route."
    @Test func anActivityThatAlignsWithTwoRoutesIsSentToReviewOnBoth() throws {
        // Two routes on roads 8 m apart, at north 20 and north 28, and a ride
        // between them at north 24. It is 4 m left of the first and 4 m right
        // of the second: all five measures pass against each.
        let routes = [try route(road(north: 20)), try route(road(north: 28))]
        let matches = RouteMatcher.match(track(road(north: 24)), against: routes)
        #expect(matches.map(\.routeIndex) == [0, 1])
        #expect(matches.map(\.outcome) == [.manualReview, .manualReview])
        #expect(matches.allSatisfy { $0.measures.allPass() })
        let first = try #require(matches.first), second = try #require(matches.last)
        #expect(close(first.measures.worstSideOffset, -4, within: 0.01))
        #expect(close(second.measures.worstSideOffset, 4, within: 0.01))
    }

    @Test func theSameActivityJoinsWhenOnlyOneOfThoseRoutesExists() throws {
        let matches = RouteMatcher.match(track(road(north: 24)), against: [try route(road(north: 20))])
        #expect(matches.map(\.outcome) == [.join])
    }

    @Test func aMatchNamesItsRouteByItsPlaceInTheList() throws {
        // Route 0 is 5 km away and route 2 is another sport. Only route 1 is
        // shortlisted, and the activity joins it.
        let routes = [
            try route(road(north: 20, from: 5010, to: 7010)),
            try route(road(north: 20)),
            try route(road(north: 20), family: .onFoot),
        ]
        let matches = RouteMatcher.match(track(road(north: 20)), against: routes)
        #expect(matches.map(\.routeIndex) == [1])
        #expect(matches.map(\.outcome) == [.join])
    }

    @Test func aRejectedRouteDoesNotStopAJoinOnAnother() throws {
        // Route 0 is the parallel road 40 m away: shortlisted, rejected.
        // Route 1 is the road itself.
        let routes = [try route(road(north: 45)), try route(road(north: 5))]
        let matches = RouteMatcher.match(track(road(north: 5)), against: routes)
        #expect(matches.map(\.routeIndex) == [0, 1])
        #expect(matches.map(\.outcome) == [.reject, .join])
    }
}
