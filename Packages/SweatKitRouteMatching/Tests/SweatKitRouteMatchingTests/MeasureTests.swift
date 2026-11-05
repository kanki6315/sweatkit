import Foundation
import SweatKitRouteMatching
import Testing

/// The five measures, worked out from mappings written by hand so that each
/// definition is pinned without any geometry. `mapped(s, side:)` is a point at
/// route distance `s`, `abs(side)` metres from the line, to the right when
/// positive.
@Suite struct MeasureTests {
    private func measures(
        _ points: [MappedPoint],
        referenceLength: Double = 1000,
        trackLength: Double = 1000
    ) -> AlignmentMeasures {
        AlignmentMeasures(points: points, referenceLength: referenceLength, trackLength: trackLength)
    }

    /// Points every 20 m from 0 to `length`, each with the side offset `side`
    /// gives for its route distance.
    private func every20(to length: Double, side: (Double) -> Double) -> [MappedPoint] {
        stride(from: 0.0, through: length, by: 20).map { mapped($0, side: side($0)) }
    }

    // MARK: Proximity - "Share of points within 30 m of the reference line"

    @Test func proximityIsTheShareOfPointsWithin30Metres() {
        // Ten points. Nine are within 30 m, one of them exactly 30 m away,
        // and one is 30.5 m away. 9 / 10 = 0.9.
        let sides: [Double] = [0, 5, -10, 30, 0, 30.5, 0, -29, 0, 0]
        let points = sides.enumerated().map { mapped(100 * Double($0.offset), side: $0.element) }
        #expect(close(measures(points).proximity, 0.9, within: 1e-12))
    }

    @Test func exactly30MetresIsWithin30Metres() {
        let on = [mapped(0, side: -30), mapped(300, side: 30), mapped(600, side: -30), mapped(900, side: 30)]
        #expect(measures(on).proximity == 1)
        let off = [mapped(0, side: -30.01), mapped(300, side: 30.01), mapped(600, side: -30.01), mapped(900, side: 30.01)]
        #expect(measures(off).proximity == 0)
    }

    @Test func proximityUsesTheDistanceToTheMatchedPositionNotTheSidewaysPart() {
        // Two points on the line, and two held at the end of the line 100 m
        // and 200 m straight beyond it: far away with no sideways part.
        // 2 / 4 = 0.5.
        let points = [
            mapped(900),
            mapped(1000),
            MappedPoint(routeDistance: 1000, distanceFromLine: 100, sideOffset: 0, trackDistance: 1000, elapsedTime: 0, movingTime: 0),
            MappedPoint(routeDistance: 1000, distanceFromLine: 200, sideOffset: 0, trackDistance: 1000, elapsedTime: 0, movingTime: 0),
        ]
        #expect(close(measures(points).proximity, 0.5, within: 1e-12))
    }

    @Test func anEffortWithNoPointsHasNoProximity() {
        #expect(measures([]).proximity == 0)
    }

    // MARK: Ends - "How close the mapping gets to each end of the reference line"

    @Test func theEndGapsAreMeasuredAlongTheRoute() {
        // First point on the line at 25 m; last at 975 m of a 1000 m line:
        // 25 m from each end.
        let result = measures([mapped(25), mapped(500), mapped(975)])
        #expect(close(result.startGap, 25, within: 1e-9))
        #expect(close(result.endGap, 25, within: 1e-9))
    }

    @Test func pointsOffTheLineDoNotCountAsReachingAnEnd() {
        // The first and last points are 40 m from the line. The first point
        // on the line is at 40 m and the last at 960 m.
        let result = measures([
            mapped(0, side: 40),
            mapped(40),
            mapped(500),
            mapped(960),
            mapped(1000, side: -40),
        ])
        #expect(close(result.startGap, 40, within: 1e-9))
        #expect(close(result.endGap, 40, within: 1e-9))
    }

    @Test func withNoPointOnTheLineBothGapsAreTheWholeLine() {
        let result = measures([mapped(0, side: 50), mapped(500, side: 50), mapped(1000, side: 50)])
        #expect(result.startGap == 1000)
        #expect(result.endGap == 1000)
        #expect(measures([]).startGap == 1000)
        #expect(measures([]).endGap == 1000)
    }

    // MARK: Coverage - "Share of the timed section's length that was mapped"
    //
    // The default line is 1000 m, so its timed section runs from 25 m to
    // 975 m and is 950 m long.

    @Test func theStretchBetweenTwoPointsOnTheLineIsMapped() {
        // Five points on the line, 250 m apart, from end to end. However far
        // apart the samples are, the line between them was travelled.
        let result = measures([mapped(0), mapped(250), mapped(500), mapped(750), mapped(1000)])
        #expect(close(result.coverage, 1, within: 1e-12))
        #expect(close(result.longestUnmappedStretch, 0, within: 1e-9))
    }

    @Test func aPointOffTheLineLeavesTheStretchAroundItUnmapped() {
        // On the line at 0, 200 and 400 m; 35 m off it at 420 m; on it again
        // at 450, 700 and 1000 m. Mapped: 0 to 400 and 450 to 1000, of which
        // 25 to 400 (375 m) and 450 to 975 (525 m) are in the timed section.
        // Unmapped: 400 to 450, 50 m. Coverage (375 + 525) / 950.
        let result = measures([
            mapped(0), mapped(200), mapped(400),
            mapped(420, side: 35),
            mapped(450), mapped(700), mapped(1000),
        ])
        #expect(close(result.coverage, 900.0 / 950.0, within: 1e-12))
        #expect(close(result.longestUnmappedStretch, 50, within: 1e-9))
    }

    @Test func theEndsOutsideTheTimedSectionDoNotCountAgainstCoverage() {
        // On the line from 20 m to 990 m. Unmapped: 0 to 20 and 990 to 1000.
        // Both lie outside the timed section of 25 to 975, which is mapped
        // from end to end: coverage 950 / 950 = 1, nothing unmapped in it.
        // The ends rule is what judges a late start and an early finish.
        let result = measures([mapped(20), mapped(500), mapped(990)])
        #expect(close(result.coverage, 1, within: 1e-12))
        #expect(close(result.longestUnmappedStretch, 0, within: 1e-9))
    }

    @Test func theLineBeforeTheFirstPointAndAfterTheLastIsUnmappedInsideTheSection() {
        // On the line from 60 m to 940 m. Unmapped: 0 to 60, of which 25 to
        // 60 (35 m) is in the section, and 940 to 1000, of which 940 to 975
        // (35 m) is. Mapped: 60 to 940, 880 m. Coverage 880 / 950.
        let result = measures([mapped(60), mapped(500), mapped(940)])
        #expect(close(result.coverage, 880.0 / 950.0, within: 1e-12))
        #expect(close(result.longestUnmappedStretch, 35, within: 1e-9))
    }

    @Test func severalUnmappedStretchesAddUpAndTheLongestIsReported() {
        // Unmapped: 100 to 180 (80 m, one point off the line) and 500 to 600
        // (100 m, two points off the line). Mapped in the timed section: 25
        // to 100 (75 m), 180 to 500 (320 m) and 600 to 975 (375 m).
        // Coverage (75 + 320 + 375) / 950 = 770 / 950.
        let result = measures([
            mapped(0), mapped(100),
            mapped(150, side: -40),
            mapped(180), mapped(500),
            mapped(520, side: 45), mapped(560, side: 45),
            mapped(600), mapped(1000),
        ])
        #expect(close(result.coverage, 770.0 / 950.0, within: 1e-12))
        #expect(close(result.longestUnmappedStretch, 100, within: 1e-9))
    }

    @Test func pointsHeldAtOneRouteDistanceLeaveNothingUnmapped() {
        // A spur off the line at 500 m: three points off the line, all held
        // at 500 m by the forward-only rule, then back on the line at 500 m.
        // The stretch they bridge runs from 500 to 500, which has no length.
        let result = measures([
            mapped(0), mapped(500),
            mapped(500, side: 60), mapped(500, side: 120), mapped(500, side: 60),
            mapped(500), mapped(1000),
        ])
        #expect(close(result.coverage, 1, within: 1e-12))
        #expect(close(result.longestUnmappedStretch, 0, within: 1e-9))
    }

    @Test func aLonePointOnTheLineMapsNothing() {
        // One point on the line at 300 m: nothing either side of it is mapped.
        // The unmapped stretches are 0 to 300, of which 25 to 300 (275 m) is
        // in the timed section, and 300 to 1000, of which 300 to 975 (675 m)
        // is.
        let result = measures([mapped(300)])
        #expect(result.coverage == 0)
        #expect(close(result.longestUnmappedStretch, 675, within: 1e-9))
    }

    @Test func withNoPointOnTheLineTheWholeSectionIsUnmapped() {
        // The timed section is 975 - 25 = 950 m long.
        let result = measures([mapped(0, side: 50), mapped(1000, side: 50)])
        #expect(result.coverage == 0)
        #expect(result.longestUnmappedStretch == 950)
        #expect(measures([]).coverage == 0)
        #expect(measures([]).longestUnmappedStretch == 950)
    }

    @Test func aLineTooShortForATimedSectionIsMeasuredWhole() {
        // A 40 m line cannot hold two marks 25 m in from each end, so the
        // whole line is measured. On the line from 10 m to 40 m: unmapped 0
        // to 10. Coverage 30 / 40 = 0.75. Length ratio 44 / 40 = 1.1.
        let result = measures([mapped(10), mapped(40)], referenceLength: 40, trackLength: 44)
        #expect(close(result.coverage, 0.75, within: 1e-12))
        #expect(close(result.longestUnmappedStretch, 10, within: 1e-9))
        #expect(close(result.lengthRatio, 1.1, within: 1e-12))
    }

    // MARK: Length ratio - "Distance travelled between the marks against the section's length"

    @Test func lengthRatioIsTheTrackDistanceBetweenTheMarksOverTheSectionLength() {
        // Two points, at the start and the end of the line, with the track
        // having travelled 1030 m between them. Read in a straight line, the
        // track is at 25 x 1.03 = 25.75 m at the first mark and at
        // 975 x 1.03 = 1004.25 m at the second: 978.5 / 950 = 1.03.
        #expect(close(measures([mapped(0), mapped(1000, travelled: 1030)]).lengthRatio, 1.03, within: 1e-12))
        // 970 m: (975 - 25) x 0.97 / 950 = 0.97.
        #expect(close(measures([mapped(0), mapped(1000, travelled: 970)]).lengthRatio, 0.97, within: 1e-12))
        // 2010 m: (975 - 25) x 2.01 / 950 = 2.01.
        #expect(close(measures([mapped(0), mapped(1000, travelled: 2010)]).lengthRatio, 2.01, within: 1e-12))
        // A 1200 m line has marks at 25 and 1175 m, 1150 m apart. 900 m of
        // track over it: (1175 - 25) x 0.75 / 1150 = 0.75.
        let longer = measures([mapped(0), mapped(1200, travelled: 900)], referenceLength: 1200)
        #expect(close(longer.lengthRatio, 0.75, within: 1e-12))
    }

    @Test func ridingBeforeTheFirstMarkAndPastTheSecondDoesNotCount() {
        // 300 m ridden to reach the start of the line (held at route
        // distance 0), 1000 m along it, then 200 m more past its end (held
        // at 1000). The track is at 300 + 25 = 325 m at the first mark and
        // at 300 + 975 = 1275 m when it first reaches the second:
        // 950 / 950 = 1. The whole track is 1500 m, which is not used.
        let points = [
            mapped(0, travelled: 0), mapped(0, travelled: 300),
            mapped(1000, travelled: 1300), mapped(1000, travelled: 1500),
        ]
        #expect(close(measures(points, trackLength: 1500).lengthRatio, 1, within: 1e-12))
    }

    @Test func anEffortThatMissesAMarkIsMeasuredOverWhatItSpans() {
        // The first point is at 100 m, past the first mark, so the ratio is
        // taken from 100 m to the second mark at 975 m. The track is at 0 m
        // at its first point and at 875 m at the mark: 875 / 875 = 1. The
        // late start is for the ends rule to fail, not this one.
        let late = measures([mapped(100, travelled: 0), mapped(1000, travelled: 900)])
        #expect(close(late.lengthRatio, 1, within: 1e-12))
        #expect(late.startGap == 100)
    }

    @Test func anEffortThatSpansNoneOfTheSectionHasNoLengthRatio() {
        // No points, and a single point, span no stretch of the section.
        #expect(measures([]).lengthRatio == 0)
        #expect(measures([mapped(300)]).lengthRatio == 0)
    }

    // MARK: Side offset - "Average sideways distance ... over any 200 m stretch, with its sign"

    @Test func aSteadyOffsetAveragesToItself() {
        // A 200 m line with 11 points, all 10 m to the right. One stretch,
        // mean 10.
        let right = every20(to: 200) { _ in 10 }
        #expect(close(measures(right, referenceLength: 200).worstSideOffset, 10, within: 1e-9))
        // All 10.5 m to the left: mean -10.5.
        let left = every20(to: 200) { _ in -10.5 }
        #expect(close(measures(left, referenceLength: 200).worstSideOffset, -10.5, within: 1e-9))
    }

    @Test func theWorstStretchIsFoundWhereverItLies() {
        // 51 points on a 1000 m line. The 11 points from 400 to 600 m are
        // 12 m to the right and the rest are on the line. The stretch that
        // starts at 400 m holds exactly those 11: mean 12.
        let points = every20(to: 1000) { (400...600).contains($0) ? 12 : 0 }
        #expect(close(measures(points).worstSideOffset, 12, within: 1e-9))
    }

    @Test func leftIsReportedAsNegative() {
        let points = every20(to: 1000) { (400...600).contains($0) ? -12 : 0 }
        #expect(close(measures(points).worstSideOffset, -12, within: 1e-9))
    }

    @Test func anExcursionShorterThanTheStretchIsAveragedDown() {
        // Only the 6 points from 400 to 500 m are 12 m to the right. Every
        // 200 m stretch holds 11 points, and at most those 6 of them:
        // 6 * 12 / 11 = 6.545.
        let points = every20(to: 1000) { (400...500).contains($0) ? 12 : 0 }
        #expect(close(measures(points).worstSideOffset, 72.0 / 11.0, within: 1e-9))
    }

    @Test func offsetsOnEitherSideCancel() {
        // Points alternate 15 m right and 15 m left. Any 11 consecutive
        // points hold 6 of one side and 5 of the other: 15 / 11 = 1.364 one
        // way or the other. Scatter is not a parallel course.
        let points = every20(to: 1000) { Int($0 / 20) % 2 == 0 ? 15 : -15 }
        #expect(close(abs(measures(points).worstSideOffset), 15.0 / 11.0, within: 1e-9))
    }

    @Test func aStretchMustFitInsideTheLine() {
        // Only the last two points, at 980 and 1000 m, are 30 m to the right.
        // The last stretch that fits starts at 800 m and holds 11 points:
        // 2 * 30 / 11 = 5.455. A shorter stretch starting at 980 m would
        // average 30, and does not count.
        let points = every20(to: 1000) { $0 >= 980 ? 30 : 0 }
        #expect(close(measures(points).worstSideOffset, 60.0 / 11.0, within: 1e-9))
    }

    @Test func aLineShorterThanOneStretchIsAveragedWhole() {
        // A 120 m line with 7 points, the middle three 12 m to the right:
        // 3 * 12 / 7 = 5.143.
        let sides: [Double] = [0, 0, 12, 12, 12, 0, 0]
        let points = sides.enumerated().map { mapped(20 * Double($0.offset), side: $0.element) }
        #expect(close(measures(points, referenceLength: 120).worstSideOffset, 36.0 / 7.0, within: 1e-9))
    }

    @Test func pointsOffTheLineStillCountTowardsTheAverage() {
        // A 200 m line with 11 points, one of them 60 m to the right:
        // 60 / 11 = 5.455.
        let points = every20(to: 200) { $0 == 100 ? 60 : 0 }
        #expect(close(measures(points, referenceLength: 200).worstSideOffset, 60.0 / 11.0, within: 1e-9))
    }

    @Test func theAverageUsesTheSidewaysPartNotTheDistance() {
        // The last point is held at the end of the line, 100 m straight
        // beyond it. It is far from the line and not to either side.
        var points = every20(to: 200) { _ in 0 }
        points.append(MappedPoint(routeDistance: 200, distanceFromLine: 100, sideOffset: 0, trackDistance: 200, elapsedTime: 0, movingTime: 0))
        #expect(close(measures(points, referenceLength: 200).worstSideOffset, 0, within: 1e-9))
    }

    @Test func anEffortWithNoPointsHasNoSideOffset() {
        #expect(measures([]).worstSideOffset == 0)
    }

    // MARK: All five together

    @Test func oneMappingGivesAllFiveMeasures() {
        // A 400 m line with 21 points, one every 20 m from 20 m to 400 m plus
        // one more at 400 m. The point at 200 m is 40 m to the left; every
        // other point is 2 m to the right. The track travels 1.01 m for
        // every metre of line. The timed section runs from 25 m to 375 m and
        // is 350 m long.
        //
        // Proximity: 20 of 21 points within 30 m = 0.952.
        // Ends: first point on the line at 20 m, last at 400 m: gaps 20 and 0.
        // Coverage: unmapped 0 to 20, which is outside the section, and 180
        //   to 220 (40 m). Mapped in the section: 25 to 180 (155 m) and 220
        //   to 375 (155 m): 310 / 350, longest 40 m.
        // Length ratio: (375 - 25) x 1.01 / 350 = 1.01.
        // Side offset: the stretches that fit start at 20, 40 ... 200 m. Each
        //   one from 20 to 180 m holds 11 points, the point at 200 m among
        //   them: (10 * 2 - 40) / 11 = -1.818. The one from 200 m holds the
        //   10 points from 200 to 380 m and both points at 400 m, 12 in all:
        //   (11 * 2 - 40) / 12 = -1.5. Furthest from zero: -20 / 11.
        var points = stride(from: 20.0, through: 400, by: 20).map {
            mapped($0, side: $0 == 200 ? -40 : 2, travelled: $0 * 1.01)
        }
        points.append(mapped(400, side: 2, travelled: 404))
        let result = measures(points, referenceLength: 400, trackLength: 404)
        #expect(close(result.proximity, 20.0 / 21.0, within: 1e-12))
        #expect(close(result.startGap, 20, within: 1e-9))
        #expect(close(result.endGap, 0, within: 1e-9))
        #expect(close(result.coverage, 310.0 / 350.0, within: 1e-12))
        #expect(close(result.longestUnmappedStretch, 40, within: 1e-9))
        #expect(close(result.lengthRatio, 1.01, within: 1e-9))
        #expect(close(result.worstSideOffset, -20.0 / 11.0, within: 1e-9))
    }

    @Test func anAlignmentReportsTheMeasuresOfItsOwnMapping() {
        let points = [mapped(20), mapped(500, side: 4), mapped(990)]
        let alignment = Alignment(points: points, referenceLength: 1000, trackLength: 985)
        #expect(alignment.measures() == AlignmentMeasures(points: points, referenceLength: 1000, trackLength: 985))
    }

    @Test func theProximityDistanceComesFromTheRules() {
        // With a 10 m proximity distance only the two points on the line
        // count: 2 / 4.
        var rules = MatchingRules.standard
        rules.proximityDistance = 10
        let points = [mapped(0), mapped(300, side: 20), mapped(600, side: -20), mapped(1000)]
        let result = AlignmentMeasures(points: points, referenceLength: 1000, trackLength: 1000, rules: rules)
        #expect(close(result.proximity, 0.5, within: 1e-12))
    }
}
