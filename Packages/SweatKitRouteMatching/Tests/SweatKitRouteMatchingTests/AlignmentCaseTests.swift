import Foundation
import SweatKitModel
import SweatKitRouteMatching
import Testing

/// Step 2 on whole tracks: every case in the spec's "Cases the tests must
/// cover" list, with the measures and the outcome worked out by hand.
///
/// Unless a test says otherwise the reference is a straight road heading east
/// from the origin with a point every 20 m, so a candidate point at
/// (east, north) maps to route distance `east`, sits `abs(north)` metres from
/// the line, and is to the left when north is positive.
@Suite struct AlignmentCaseTests {
    private struct Result {
        var alignment: Alignment
        var measures: AlignmentMeasures
        var outcome: AlignmentOutcome
        var failed: Set<AlignmentMeasure>
    }

    private func align(
        _ candidate: [P],
        to reference: [P],
        rules: MatchingRules = .standard,
        plane: Plane = .equator
    ) throws -> Result {
        let line = try #require(referenceLine(reference, plane: plane))
        let alignment = RouteAlignment.align(track(candidate, plane: plane), to: line, rules: rules)
        let measures = alignment.measures(rules: rules)
        return Result(
            alignment: alignment,
            measures: measures,
            outcome: measures.outcome(rules: rules),
            failed: measures.failedMeasures(rules: rules)
        )
    }

    /// 2000 m due east, 101 points.
    private let road = Course.eastRoad(to: 2000)

    // MARK: The same course again

    @Test func theSameCourseAgainJoins() throws {
        let result = try align(road, to: road)
        #expect(close(result.measures.proximity, 1, within: 1e-9))
        #expect(close(result.measures.startGap, 0, within: 0.01))
        #expect(close(result.measures.endGap, 0, within: 0.01))
        #expect(close(result.measures.coverage, 1, within: 1e-5))
        #expect(close(result.measures.longestUnmappedStretch, 0, within: 0.01))
        #expect(close(result.measures.lengthRatio, 1, within: 1e-6))
        #expect(close(result.measures.worstSideOffset, 0, within: 0.01))
        #expect(result.failed.isEmpty)
        #expect(result.outcome == .join)
    }

    @Test func anAlignmentCarriesTheLengthsAndThePauseReliability() throws {
        // A 1980 m track on a 2000 m line.
        let line = try #require(referenceLine(road))
        let late = track(Course.eastRoad(from: 20, to: 2000), pausePositionsAreReliable: false)
        let alignment = RouteAlignment.align(late, to: line)
        #expect(alignment.points.count == 100)
        #expect(close(alignment.referenceLength, 2000, within: 0.01))
        #expect(close(alignment.trackLength, 1980, within: 0.01))
        #expect(!alignment.pausePositionsAreReliable)
        #expect(RouteAlignment.align(track(road), to: line).pausePositionsAreReliable)
    }

    @Test func aCurvedRoadSampledAtDifferentPointsJoins() throws {
        // A left-hand bend of radius 300 m. The reference has a point every
        // 1/15 radian, which is 20 m of arc, for 60 steps: 1200 m of arc. The
        // candidate rode the same bend and was sampled half a step later each
        // time, from 10 m to 1190 m of arc.
        //
        // Each candidate point lies on the arc midway between two reference
        // points, so it is off the straight piece between them by the
        // sagitta: 300 * (1 - cos(1/30)) = 0.17 m. Always within 30 m, always
        // on the outside of the bend, which is the right.
        // Ends: about 10 m from each. Coverage: (1200 - 20) / 1200 = 0.983.
        // Length ratio: 59 equal chords against 60 = 0.983.
        func bend(_ step: Double) -> P {
            let angle = step / 15
            return P(300 * sin(angle), 300 - 300 * cos(angle))
        }
        let reference = (0...60).map { bend(Double($0)) }
        let candidate = (0..<60).map { bend(Double($0) + 0.5) }
        let result = try align(candidate, to: reference)
        #expect(close(result.measures.proximity, 1, within: 1e-9))
        #expect(close(result.measures.startGap, 10, within: 0.1))
        #expect(close(result.measures.endGap, 10, within: 0.1))
        #expect(close(result.measures.coverage, 59.0 / 60.0, within: 1e-3))
        #expect(close(result.measures.lengthRatio, 59.0 / 60.0, within: 1e-6))
        #expect(close(result.measures.worstSideOffset, 0.17, within: 0.01))
        #expect(result.outcome == .join)
    }

    // MARK: Parallel roads within 50 m of each other

    /// "A road 20 m away passes a 30 m test, so a consistent offset to one
    /// side is treated as the signature of a parallel course."
    @Test func aParallelRoad20MetresAwayGoesToReview() throws {
        // Every point is 20 m to the left: within 30 m, so proximity is 100%,
        // and the ends, coverage and length are perfect. Only the side offset
        // fails, at -20 against a limit of 10.
        let result = try align(Course.eastRoad(to: 2000, north: 20), to: road)
        #expect(close(result.measures.proximity, 1, within: 1e-9))
        #expect(close(result.measures.coverage, 1, within: 1e-5))
        #expect(close(result.measures.lengthRatio, 1, within: 1e-6))
        #expect(close(result.measures.worstSideOffset, -20, within: 0.01))
        #expect(result.failed == [.sideOffset])
        #expect(result.outcome == .manualReview)
    }

    @Test func aParallelRoadOnTheOtherSideGoesToReviewWithTheOppositeSign() throws {
        let result = try align(Course.eastRoad(to: 2000, north: -20), to: road)
        #expect(close(result.measures.worstSideOffset, 20, within: 0.01))
        #expect(result.outcome == .manualReview)
    }

    @Test func aParallelRoad40MetresAwayIsRejected() throws {
        // No point is within 30 m: proximity 0. No point is on the line, so
        // both end gaps are the whole 2000 m and nothing is mapped.
        let result = try align(Course.eastRoad(to: 2000, north: 40), to: road)
        #expect(result.measures.proximity == 0)
        #expect(close(result.measures.startGap, 2000, within: 0.01))
        #expect(close(result.measures.endGap, 2000, within: 0.01))
        #expect(result.measures.coverage == 0)
        #expect(result.outcome == .reject)
    }

    @Test(arguments: [
        (0.0, AlignmentOutcome.join),
        (8.0, .join),           // the far side of the same road
        (9.5, .join),           // just inside the 10 m limit
        (-9.5, .join),
        (10.5, .manualReview),  // just outside it
        (-10.5, .manualReview),
        (29.0, .manualReview),  // still within the 30 m proximity distance
        (31.0, .reject),        // beyond it: nothing is on the line
        (45.0, .reject),
    ])
    func aSteadyOffsetJoinsUpTo10MetresIsAskedAboutUpTo30AndIsRejectedBeyond(north: Double, outcome: AlignmentOutcome) throws {
        let result = try align(Course.eastRoad(to: 2000, north: north), to: road)
        #expect(result.outcome == outcome)
    }

    // MARK: Two laps against three laps of the same circuit

    @Test func twoLapsOnATwoLapRouteJoin() throws {
        let result = try align(Course.squareLaps(2), to: Course.squareLaps(2))
        #expect(result.failed.isEmpty)
        #expect(result.outcome == .join)
    }

    @Test func threeLapsOnATwoLapRouteAreRejected() throws {
        // The first two laps, points 0...80, map exactly onto the 1600 m
        // line. The line then ends, so every point of the third lap is held
        // at its last point, the corner at (0, 0). Of the third lap's 40
        // points only three are within 30 m of the corner: (20, 0) at the
        // start of the lap, and (0, 20) and (0, 0) at its end.
        // Proximity: (81 + 3) / 121 = 0.694, under 70%.
        // Length ratio: 2400 / 1600 = 1.5.
        let result = try align(Course.squareLaps(3), to: Course.squareLaps(2))
        #expect(close(result.measures.proximity, 84.0 / 121.0, within: 1e-9))
        #expect(close(result.measures.lengthRatio, 1.5, within: 1e-6))
        #expect(result.outcome == .reject)
    }

    @Test func twoLapsOnAThreeLapRouteAreRejected() throws {
        // The two laps map onto the first 1600 m of the 2400 m line and stop
        // there: 800 m short of the end, with 1600 / 2400 = 0.667 covered.
        let result = try align(Course.squareLaps(2), to: Course.squareLaps(3))
        #expect(close(result.measures.proximity, 1, within: 1e-9))
        #expect(close(result.measures.startGap, 0, within: 0.01))
        #expect(close(result.measures.endGap, 800, within: 0.01))
        #expect(close(result.measures.coverage, 2.0 / 3.0, within: 1e-5))
        #expect(close(result.measures.lengthRatio, 2.0 / 3.0, within: 1e-6))
        #expect(result.failed.contains(.ends))
        #expect(result.outcome == .reject)
    }

    // MARK: An out-and-back against a one-way trip on the same road

    @Test func anOutAndBackOnAnOutAndBackRouteJoins() throws {
        let result = try align(Course.outAndBack(), to: Course.outAndBack())
        #expect(result.failed.isEmpty)
        #expect(result.outcome == .join)
    }

    @Test func aOneWayTripOnAnOutAndBackRouteIsRejected() throws {
        // The 1000 m trip maps onto the outbound half of the 2010 m line and
        // ends at the far end: 1010 m short, 1000 / 2010 = 0.498 covered.
        let result = try align(Course.eastRoad(to: 1000, step: 10), to: Course.outAndBack())
        #expect(close(result.measures.proximity, 1, within: 1e-9))
        #expect(close(result.measures.endGap, 1010, within: 0.01))
        #expect(close(result.measures.coverage, 1000.0 / 2010.0, within: 1e-5))
        #expect(close(result.measures.lengthRatio, 1000.0 / 2010.0, within: 1e-6))
        #expect(result.outcome == .reject)
    }

    @Test func anOutAndBackOnAOneWayRouteIsRejected() throws {
        // Points 0...100 ride the 1000 m line out. The line ends there, so
        // the rest are held at its end, (1000, 0). Point 101 is 10 m across
        // the road from it. The return then recedes: 10, 20, 30 m back along
        // a lane 10 m to the side is sqrt(10^2 + 10^2) = 14.1 m,
        // sqrt(20^2 + 10^2) = 22.4 m, then sqrt(30^2 + 10^2) = 31.6 m away.
        // On the line: 101 + 1 + 2 = 104 of 202 points = 0.515, under 70%.
        // Length ratio: 2010 / 1000 = 2.01.
        let result = try align(Course.outAndBack(), to: Course.eastRoad(to: 1000, step: 10))
        #expect(close(result.measures.proximity, 104.0 / 202.0, within: 1e-9))
        #expect(close(result.measures.lengthRatio, 2.01, within: 1e-6))
        #expect(result.outcome == .reject)
    }

    // MARK: A figure-of-eight

    @Test func aFigureOfEightOnItsOwnRouteJoins() throws {
        let result = try align(Course.figureOfEight(), to: Course.figureOfEight())
        #expect(close(result.measures.proximity, 1, within: 1e-9))
        #expect(close(result.measures.coverage, 1, within: 1e-5))
        #expect(result.failed.isEmpty)
        #expect(result.outcome == .join)
    }

    @Test func aFigureOfEightWithItsLobesSwappedIsRejected() throws {
        // The candidate rides the south-west lobe first. The line's first
        // 100 m head east from the centre, so while the candidate is in the
        // south-west lobe the closest position it may search is the centre
        // itself: it is held at 0 m. Only its first point, (0, -20) after it
        // and (-20, 0) before its return are within 30 m of the centre.
        // Back at the centre, point 40, it rides the north-east lobe, which
        // is the line's first 800 m, and maps exactly: points 40...80.
        // On the line: 3 + 41 = 44 of 81 points = 0.543, under 70%.
        // Ends: the last point is at 800 m of 1600 m, 800 m short.
        // Coverage: 800 / 1600 = 0.5.
        let result = try align(Course.figureOfEight(secondLobeFirst: true), to: Course.figureOfEight())
        #expect(close(result.measures.proximity, 44.0 / 81.0, within: 1e-9))
        #expect(close(result.measures.startGap, 0, within: 0.01))
        #expect(close(result.measures.endGap, 800, within: 0.01))
        #expect(close(result.measures.coverage, 0.5, within: 1e-5))
        #expect(result.outcome == .reject)
    }

    // MARK: A reversed ride

    /// "A reversed ride fails alignment, so it becomes a separate route."
    @Test func aRoadRiddenTheOtherWayIsRejected() throws {
        // A 1000 m line and the same road ridden west, point k at east
        // 1000 - 20k. The matched route distance can advance 100 m a point:
        // 100, 200 ... 800 for points 0...7, each far short of the rider.
        // Point 8 is at east 840 and may search 800 to 900: it is on the
        // line. Point 9, at 820, is held at 840, 20 m back. From point 10 on
        // the rider is 40 m and more behind the held position.
        // On the line: 2 of 51 points = 0.039.
        let reference = Course.eastRoad(to: 1000)
        let result = try align(Array(reference.reversed()), to: reference)
        #expect(close(result.measures.proximity, 2.0 / 51.0, within: 1e-9))
        #expect(result.outcome == .reject)
    }

    @Test func aCircuitRunTheOtherWayIsRejected() throws {
        // Same start, finish, distance and cells as the route, so detection
        // lets it through. Alignment does not. The line's first 100 m run
        // east along the south side, while the rider's points 2...10 go 40 to
        // 200 m north up the west side: all held at the start of the line and
        // off it. Points 11...14 ride the north side. The search has advanced
        // at most 100 m a point since point 10, so no further than 400 m,
        // which is the south and east sides: at least 100 m from them. That
        // is 13 of 41 points off the line whatever happens next, so proximity
        // is at most 28 / 41 = 0.683, under 70%.
        let result = try align(Course.squareLapsClockwise(1), to: Course.squareLaps(1))
        #expect(result.measures.proximity <= 28.0 / 41.0)
        #expect(result.failed.contains(.proximity))
        #expect(result.outcome == .reject)
    }

    // MARK: Detours

    /// "A detour under 50 m, which joins."
    @Test func aDetourUnder50MetresJoins() throws {
        // The rider leaves the road after 480 m, passes (500, 32), and is
        // back on it at 520 m. That one point is 32 m from the line.
        // Proximity: 100 of 101 points = 0.990.
        // Coverage: unmapped from 480 to 520, 40 m. 1960 / 2000 = 0.98.
        // Length: each leg of the detour is sqrt(20^2 + 32^2) = 37.736 m in
        //   place of 20 m. 2000 - 40 + 75.472 = 2035.472, ratio 1.0177.
        // Side offset: a 200 m stretch holds 11 points, one of them 32 m to
        //   the left: -32 / 11 = -2.91. The eleventh point sits exactly on
        //   the end of the stretch, so rounding may leave it out: -32 / 10 =
        //   -3.2. Either is far inside the 10 m limit.
        var detour = road
        detour[25] = P(500, 32)
        let result = try align(detour, to: road)
        #expect(close(result.measures.proximity, 100.0 / 101.0, within: 1e-9))
        #expect(close(result.measures.coverage, 0.98, within: 1e-5))
        #expect(close(result.measures.longestUnmappedStretch, 40, within: 0.01))
        #expect(close(result.measures.lengthRatio, 2035.472 / 2000, within: 1e-5))
        #expect((-3.21 ... -2.90).contains(result.measures.worstSideOffset))
        #expect(result.failed.isEmpty)
        #expect(result.outcome == .join)
    }

    /// "A longer detour ... which does not."
    @Test func aDetourOver50MetresIsRejected() throws {
        // The rider leaves after 480 m, passes (500, 32), (520, 32) and
        // (540, 32), and is back at 560 m.
        // Proximity: 98 of 101 = 0.970. Passes.
        // Coverage: unmapped from 480 to 560, 80 m. 1920 / 2000 = 0.96, which
        //   is enough, but the stretch is longer than 50 m. Fails.
        // Length: 2000 - 80 + 37.736 + 20 + 20 + 37.736 = 2035.472. Passes.
        // Side offset: three points 32 m left among 11, or among 10 if
        //   rounding leaves the last out: -96 / 11 = -8.73 or -9.6. Passes.
        var detour = road
        detour[25] = P(500, 32)
        detour[26] = P(520, 32)
        detour[27] = P(540, 32)
        let result = try align(detour, to: road)
        #expect(close(result.measures.proximity, 98.0 / 101.0, within: 1e-9))
        #expect(close(result.measures.coverage, 0.96, within: 1e-5))
        #expect(close(result.measures.longestUnmappedStretch, 80, within: 0.01))
        #expect(close(result.measures.lengthRatio, 2035.472 / 2000, within: 1e-5))
        #expect((-9.61 ... -8.72).contains(result.measures.worstSideOffset))
        #expect(result.failed == [.coverage])
        #expect(result.outcome == .reject)
    }

    @Test func severalShortDetoursCanLeaveTooLittleCovered() throws {
        // Two one-point detours on a 1000 m route, at 200 m and 600 m. Each
        // leaves 40 m unmapped, which no stretch rule forbids, but together
        // they leave 920 / 1000 = 0.92 covered, under 95%.
        let reference = Course.eastRoad(to: 1000)
        var detours = reference
        detours[10] = P(200, 32)
        detours[30] = P(600, 32)
        let result = try align(detours, to: reference)
        #expect(close(result.measures.coverage, 0.92, within: 1e-5))
        #expect(close(result.measures.longestUnmappedStretch, 40, within: 0.01))
        #expect(result.failed.contains(.coverage))
        #expect(result.outcome == .reject)
    }

    /// "A missed turn with a return, which does not."
    @Test func aMissedTurnWithAReturnDoesNotJoin() throws {
        // The route goes 500 m east and turns north for 500 m. The rider
        // misses the turn, carries on east for 160 m, comes back and takes
        // it: 67 points.
        //
        // Past the corner the line heads north, so the closest position the
        // overshooting rider may search is the corner itself, and every
        // overshoot point is held at 500 m. Within 30 m of the corner: (520,
        // 0) going out and coming back, and the corner again. Beyond: 540 to
        // 660 out, seven points, and 640 to 540 back, six.
        // Proximity: (67 - 13) / 67 = 0.806, between 70% and 90%.
        // Ends: both exact. Coverage: nothing is skipped, 100%.
        // Length ratio: (1000 + 320) / 1000 = 1.32.
        // The ends and coverage pass, so it is not rejected; proximity and
        // the length ratio stop it joining. The app asks.
        let reference = Course.polyline([P(0, 0), P(500, 0), P(500, 500)])
        let missed = Course.polyline([P(0, 0), P(500, 0), P(660, 0), P(500, 0), P(500, 500)])
        #expect(missed.count == 67)
        let result = try align(missed, to: reference)
        #expect(close(result.measures.proximity, 54.0 / 67.0, within: 1e-9))
        #expect(close(result.measures.startGap, 0, within: 0.01))
        #expect(close(result.measures.endGap, 0, within: 0.01))
        #expect(close(result.measures.coverage, 1, within: 1e-5))
        #expect(close(result.measures.lengthRatio, 1.32, within: 1e-6))
        #expect(result.failed.isSuperset(of: [.proximity, .lengthRatio]))
        #expect(result.outcome == .manualReview)
    }

    // MARK: Late starts and early finishes

    /// "A start 20 m late joins."
    @Test func aStart20MetresLateJoins() throws {
        // Ends: first point at 20 m, within 25 m.
        // Coverage: 0 to 20 unmapped, 1980 / 2000 = 0.99.
        // Length ratio: 1980 / 2000 = 0.99.
        let result = try align(Course.eastRoad(from: 20, to: 2000), to: road)
        #expect(close(result.measures.startGap, 20, within: 0.01))
        #expect(close(result.measures.endGap, 0, within: 0.01))
        #expect(close(result.measures.coverage, 0.99, within: 1e-5))
        #expect(close(result.measures.longestUnmappedStretch, 20, within: 0.01))
        #expect(close(result.measures.lengthRatio, 0.99, within: 1e-6))
        #expect(result.failed.isEmpty)
        #expect(result.outcome == .join)
    }

    @Test func aStart30MetresLateIsRejected() throws {
        // First point at 30 m, beyond 25 m. Everything else passes: coverage
        // 1970 / 2000 = 0.985 with a 30 m stretch, length ratio 0.985.
        let result = try align(Course.eastRoad(from: 30, to: 2000, step: 10), to: road)
        #expect(close(result.measures.startGap, 30, within: 0.01))
        #expect(result.failed == [.ends])
        #expect(result.outcome == .reject)
    }

    @Test func aFinish20MetresEarlyJoins() throws {
        let result = try align(Course.eastRoad(to: 1980), to: road)
        #expect(close(result.measures.endGap, 20, within: 0.01))
        #expect(result.failed.isEmpty)
        #expect(result.outcome == .join)
    }

    @Test func aFinish30MetresEarlyIsRejected() throws {
        let result = try align(Course.eastRoad(to: 1970, step: 10), to: road)
        #expect(close(result.measures.endGap, 30, within: 0.01))
        #expect(result.failed == [.ends])
        #expect(result.outcome == .reject)
    }

    @Test func aStartAndFinishEach20MetresBeyondTheRouteJoin() throws {
        // The rider starts 20 m before the route's start and stops 20 m past
        // its end. Those two points are held at the ends of the line, 20 m
        // away, so they are on the line: gaps 0, everything mapped.
        // Length ratio: 2040 / 2000 = 1.02.
        let result = try align(Course.eastRoad(from: -20, to: 2020), to: road)
        #expect(close(result.measures.proximity, 1, within: 1e-9))
        #expect(close(result.measures.startGap, 0, within: 0.01))
        #expect(close(result.measures.endGap, 0, within: 0.01))
        #expect(close(result.measures.lengthRatio, 1.02, within: 1e-6))
        #expect(result.outcome == .join)
    }

    /// "A start 1 km into a known route must not join either."
    @Test func aStartOneKilometreIntoTheRouteIsRejected() throws {
        // A 3000 m route joined at 1000 m. The rider is never before 1000 m,
        // so no position before 970 m can be within 30 m of any point: the
        // first point on the line is at least 970 m along. At best the last
        // 2000 m are mapped: 2000 / 3000 = 0.667.
        let reference = Course.eastRoad(to: 3000)
        let result = try align(Course.eastRoad(from: 1000, to: 3000), to: reference)
        #expect(result.measures.startGap >= 970)
        #expect(result.measures.coverage <= 2030.0 / 3000.0)
        #expect(result.measures.longestUnmappedStretch >= 970)
        #expect(result.failed.isSuperset(of: [.ends, .coverage]))
        #expect(result.outcome == .reject)
    }

    // MARK: Length ratio

    @Test func aSideTripThatAddsFourPercentGoesToReview() throws {
        // On a 1000 m road the rider turns 20 m up a side street at 500 m
        // and comes back: 40 m extra, never more than 20 m from the line.
        // Length ratio 1040 / 1000 = 1.04. Everything else passes: all 53
        // points are on the line, nothing is unmapped, and the one point
        // 20 m to the left averages to about -20 / 13 = -1.5 over the 13
        // points of a stretch around it.
        let reference = Course.eastRoad(to: 1000)
        let sideTrip = Course.polyline([P(0, 0), P(500, 0), P(500, 20), P(500, 0), P(1000, 0)])
        let result = try align(sideTrip, to: reference)
        #expect(close(result.measures.lengthRatio, 1.04, within: 1e-6))
        #expect(close(result.measures.proximity, 1, within: 1e-9))
        #expect((-1.7 ... -1.5).contains(result.measures.worstSideOffset))
        #expect(result.failed == [.lengthRatio])
        #expect(result.outcome == .manualReview)
    }

    @Test func aSideTripThatAddsTwoPercentJoins() throws {
        // 10 m up the side street and back: 1020 / 1000 = 1.02.
        let reference = Course.eastRoad(to: 1000, step: 10)
        let sideTrip = Course.polyline([P(0, 0), P(500, 0), P(500, 10), P(500, 0), P(1000, 0)], step: 10)
        let result = try align(sideTrip, to: reference)
        #expect(close(result.measures.lengthRatio, 1.02, within: 1e-6))
        #expect(result.failed.isEmpty)
        #expect(result.outcome == .join)
    }

    // MARK: GPS drift under trees and between tall buildings

    /// Under trees the fix wanders slowly from side to side. The expected
    /// values are bounds that follow from the size of the drift, not from any
    /// one run of it.
    @Test(arguments: [1, 2, 3, 4, 5] as [UInt64])
    func slowDriftUnderTreesStillJoins(seed: UInt64) throws {
        // The same road, each point pushed sideways by a drift that stays
        // within 8 m and changes by at most 2 m between points 20 m apart.
        // Proximity: every point within 8 m, so 100%.
        // Ends: the drift is sideways only, so the first and last points map
        //   to 0 and 2000 m.
        // Coverage: every point on the line, 100%.
        // Length: each 20 m step becomes at most sqrt(20^2 + 2^2) = 20.0998 m,
        //   so the ratio is between 1 and 1.005.
        // Side offset: no average of values within 8 m exceeds 8 m.
        let drift = Noise.drift(count: road.count, maxStep: 2, bound: 8, seed: seed)
        let drifted = zip(road, drift).map { $0.moved(north: $1) }
        let result = try align(drifted, to: road)
        #expect(close(result.measures.proximity, 1, within: 1e-9))
        #expect(close(result.measures.startGap, 0, within: 0.01))
        #expect(close(result.measures.endGap, 0, within: 0.01))
        #expect(close(result.measures.coverage, 1, within: 1e-5))
        #expect(result.measures.lengthRatio >= 1 - 1e-6)
        #expect(result.measures.lengthRatio <= 1.005)
        #expect(abs(result.measures.worstSideOffset) <= 8.01)
        #expect(result.failed.isEmpty)
        #expect(result.outcome == .join)
    }

    /// Between tall buildings the fix can sit to one side for a whole block.
    /// "Where GPS accuracy cannot tell two courses apart, the app asks."
    @Test func aBlockLongShiftBetweenBuildingsGoesToReview() throws {
        // The same road, but from 800 m to 1100 m (points 40...55) every
        // point reads 15 m to the left, easing in over points 38 and 39 and
        // out over points 56 and 57 (5 m and 10 m).
        // Proximity: every point within 15 m, so 100%.
        // Length: six easing steps of sqrt(20^2 + 5^2) = 20.616 m in place of
        //   20 m: 2003.69 / 2000 = 1.0018. Passes.
        // Side offset: the stretch from 800 to 1000 m holds 11 points, all
        //   15 m left: -15. Fails, and is the only measure that does.
        let shifted = road.enumerated().map { index, point -> P in
            switch index {
            case 38, 57: point.moved(north: 5)
            case 39, 56: point.moved(north: 10)
            case 40...55: point.moved(north: 15)
            default: point
            }
        }
        let result = try align(shifted, to: road)
        #expect(close(result.measures.proximity, 1, within: 1e-9))
        #expect(close(result.measures.lengthRatio, 2003.693 / 2000, within: 1e-5))
        #expect(close(result.measures.worstSideOffset, -15, within: 0.01))
        #expect(result.failed == [.sideOffset])
        #expect(result.outcome == .manualReview)
    }

    // MARK: Rules and frames

    @Test func alignmentReadsItsThresholdsFromTheRules() throws {
        let parallel = Course.eastRoad(to: 2000, north: 20)
        // With a 15 m proximity distance the road 20 m away is not on the line.
        var strict = MatchingRules.standard
        strict.proximityDistance = 15
        #expect(try align(parallel, to: road, rules: strict).measures.proximity == 0)
        #expect(try align(parallel, to: road, rules: strict).outcome == .reject)
        // With a 25 m side limit it joins.
        var loose = MatchingRules.standard
        loose.maximumSideOffset = 25
        #expect(try align(parallel, to: road, rules: loose).outcome == .join)
    }

    @Test func matchingWorksAwayFromTheEquator() throws {
        // The same 1000 m road at 48 degrees north, where a degree of
        // longitude is only two thirds as long as a degree of latitude.
        let plane = Plane(origin: Coordinate(latitude: 48, longitude: 7))
        let reference = Course.eastRoad(to: 1000)
        let same = try align(reference, to: reference, plane: plane)
        #expect(same.outcome == .join)
        #expect(close(same.alignment.referenceLength, 1000, within: 0.01))

        let parallel = try align(Course.eastRoad(to: 1000, north: 20), to: reference, plane: plane)
        #expect(close(parallel.measures.proximity, 1, within: 1e-9))
        #expect(close(parallel.measures.worstSideOffset, -20, within: 0.05))
        #expect(parallel.outcome == .manualReview)

        let far = try align(Course.eastRoad(to: 1000, north: 40), to: reference, plane: plane)
        #expect(far.outcome == .reject)
    }
}
