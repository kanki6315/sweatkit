import Foundation
import SweatKitModel
import SweatKitRouteMatching
import Testing

/// Whole-track cases the first round of tests named as uncovered: shortcuts,
/// short routes, GPS noise that is not a slow drift, and a virtual ride's
/// part of the world. Every expected value is worked out in the comment
/// above it, from the spec's rules as this package reads them.
@Suite struct FurtherAlignmentCaseTests {
    private struct Result {
        var alignment: Alignment
        var measures: AlignmentMeasures
        var outcome: AlignmentOutcome
        var failed: Set<AlignmentMeasure>
    }

    private func align(_ candidate: [P], to reference: [P]) throws -> Result {
        let line = try #require(referenceLine(reference))
        let alignment = RouteAlignment.align(track(candidate), to: line)
        let measures = alignment.measures()
        return Result(
            alignment: alignment,
            measures: measures,
            outcome: measures.outcome(),
            failed: measures.failedMeasures()
        )
    }

    /// 2000 m due east, 101 points.
    private let road = Course.eastRoad(to: 2000)

    /// 500 m east then 500 m north, 51 points: point k is at (20 k, 0) up to
    /// k = 25, the corner, and at (500, 20 (k - 25)) after it.
    private let corner = Course.polyline([P(0, 0), P(500, 0), P(500, 500)])

    // MARK: Shortcuts

    /// A shortcut that stays within 30 m of the line leaves nothing unmapped,
    /// so coverage does not see it. Only the length ratio can.
    @Test func aClippedCornerThatSavesOnePercentJoins() throws {
        // The rider goes straight from (480, 0) to (500, 20), missing the
        // corner point. Both are on the line, at 480 m and 520 m, so the
        // stretch between them is mapped: coverage 100%.
        // Length: sqrt(20^2 + 20^2) = 28.284 m in place of 40 m. Between the
        //   marks at 25 m and 975 m: 950 - 40 + 28.284 = 938.284,
        //   ratio 938.284 / 950 = 0.98767. Within 3%.
        var clipped = corner
        clipped.remove(at: 25)
        let result = try align(clipped, to: corner)
        #expect(close(result.measures.proximity, 1, within: 1e-9))
        #expect(close(result.measures.coverage, 1, within: 1e-5))
        #expect(close(result.measures.lengthRatio, 938.284 / 950, within: 1e-5))
        #expect(result.failed.isEmpty)
        #expect(result.outcome == .join)
    }

    @Test func aCutCornerThatSavesMoreThanThreePercentGoesToReview() throws {
        // The rider goes straight from (440, 0) to (500, 60), leaving out
        // points 23 ... 27. (500, 60) may search 440 to 540 m, which ends at
        // (500, 40): it maps there, 20 m away, on the line. The next point,
        // (500, 80), searches 540 to 640 m and maps to 580 m exactly.
        // Proximity: every point within 30 m, 100%.
        // Coverage: every point is on the line, so nothing is unmapped.
        // Length: sqrt(60^2 + 60^2) = 84.853 m in place of 120 m. Between the
        //   marks: 950 - 120 + 84.853 = 914.853, ratio 914.853 / 950 =
        //   0.96300. Fails.
        // Side offset: (500, 60) is straight ahead of its matched position
        //   on the north leg, with no sideways part. 0 everywhere.
        var cut = corner
        cut.removeSubrange(23...27)
        let result = try align(cut, to: corner)
        #expect(close(result.alignment.points[23].routeDistance, 540, within: 0.01))
        #expect(close(result.alignment.points[23].distanceFromLine, 20, within: 0.01))
        #expect(close(result.alignment.points[24].routeDistance, 580, within: 0.01))
        #expect(close(result.measures.proximity, 1, within: 1e-9))
        #expect(close(result.measures.coverage, 1, within: 1e-5))
        #expect(close(result.measures.lengthRatio, 914.853 / 950, within: 1e-5))
        #expect(close(result.measures.worstSideOffset, 0, within: 0.01))
        #expect(result.failed == [.lengthRatio])
        #expect(result.outcome == .manualReview)
    }

    @Test func aHairpinCutShortIsRejected() throws {
        // The route goes 500 m east, 20 m north and 500 m back west: 1020 m.
        // The rider turns back early, at 300 m: 300 m east, 20 m north and
        // 300 m west, 620 m, 32 points.
        //
        // Points 0 ... 15 map to 0 ... 300 m. Point 16, (300, 20), may search
        // 300 to 400 m, all on the outbound leg: it is held at 300 m, 20 m
        // away. Point 17, (280, 20), is held there too, sqrt(20^2 + 20^2) =
        // 28.3 m away. Point 18, (260, 20), is sqrt(40^2 + 20^2) = 44.7 m
        // away and the rest are further. The return leg of the line is 420 m
        // of route ahead, out of reach of the window.
        // Proximity: 18 of 32 = 0.5625, under 70%.
        // Ends: the last point on the line is at 300 m, 720 m short.
        // Coverage: the timed section runs from 25 m to 995 m, 970 m long,
        // and 25 to 300 of it is mapped: 275 / 970 = 0.284.
        // Length ratio: over what the rider spans, 25 m to 300 m, where the
        // track runs along the line: 275 / 275 = 1.
        let hairpin = Course.polyline([P(0, 0), P(500, 0), P(500, 20), P(0, 20)])
        let cutShort = Course.polyline([P(0, 0), P(300, 0), P(300, 20), P(0, 20)])
        #expect(cutShort.count == 32)
        let result = try align(cutShort, to: hairpin)
        #expect(close(result.measures.proximity, 18.0 / 32.0, within: 1e-9))
        #expect(close(result.measures.startGap, 0, within: 0.01))
        #expect(close(result.measures.endGap, 720, within: 0.01))
        #expect(close(result.measures.coverage, 275.0 / 970.0, within: 1e-5))
        #expect(close(result.measures.lengthRatio, 1, within: 1e-6))
        #expect(result.outcome == .reject)
    }

    // MARK: Late starts either side of 25 m

    @Test func aStart24MetresLateJoins() throws {
        // First point at 24 m, within 25 m. The unmapped 24 m lies before
        // the first mark, so the timed section is covered whole: coverage 1.
        let result = try align(Course.eastRoad(from: 24, to: 2000, step: 26), to: road)
        #expect(close(result.measures.startGap, 24, within: 0.01))
        #expect(close(result.measures.coverage, 1, within: 1e-5))
        #expect(close(result.measures.lengthRatio, 1, within: 1e-6))
        #expect(result.failed.isEmpty)
        #expect(result.outcome == .join)
    }

    @Test func aStart26MetresLateIsRejected() throws {
        // First point at 26 m, beyond 25 m. The other measures pass: 1 m of
        // the section is unmapped, coverage 1949 / 1950, and the length
        // ratio over what the rider spans is 1.
        let result = try align(Course.eastRoad(from: 26, to: 2000, step: 42), to: road)
        #expect(close(result.measures.startGap, 26, within: 0.01))
        #expect(result.failed == [.ends])
        #expect(result.outcome == .reject)
    }

    // MARK: Short routes

    /// "A start 20 m late joins", on a route of any length. Coverage and the
    /// length ratio are measured over the timed section, which starts at
    /// 25 m, so the 20 m the rider missed counts against neither. Measured
    /// over the whole line it would be more than 3% of any route under
    /// 667 m, and more than 5% of any route under 400 m.
    @Test func aStart20MetresLateOnA600MetreRouteJoins() throws {
        // Ends: first point at 20 m, within 25 m. Passes.
        // The timed section runs from 25 m to 575 m, 550 m long. The rider
        // is on the line from 20 m, so all of it is mapped: coverage 1.
        // Length ratio: 550 m travelled between the marks: 550 / 550 = 1.
        let result = try align(Course.eastRoad(from: 20, to: 600), to: Course.eastRoad(to: 600))
        #expect(close(result.measures.startGap, 20, within: 0.01))
        #expect(close(result.measures.coverage, 1, within: 1e-5))
        #expect(close(result.measures.lengthRatio, 1, within: 1e-6))
        #expect(result.failed.isEmpty)
        #expect(result.outcome == .join)
    }

    @Test func aStart20MetresLateOnA300MetreRouteJoins() throws {
        // The timed section runs from 25 m to 275 m, 250 m long, all of it
        // mapped and all of it travelled: coverage 1, length ratio 1.
        let result = try align(Course.eastRoad(from: 20, to: 300), to: Course.eastRoad(to: 300))
        #expect(close(result.measures.startGap, 20, within: 0.01))
        #expect(close(result.measures.coverage, 1, within: 1e-5))
        #expect(close(result.measures.lengthRatio, 1, within: 1e-6))
        #expect(result.failed.isEmpty)
        #expect(result.outcome == .join)
    }

    @Test func aStart30MetresLateOnA300MetreRouteIsStillRejected() throws {
        // The first point is at 30 m, beyond the 25 m the ends rule allows.
        // 25 to 30 m of the section is unmapped: coverage 245 / 250 = 0.98.
        // Only the ends fail, and a failed end rejects.
        let result = try align(Course.eastRoad(from: 30, to: 300, step: 10), to: Course.eastRoad(to: 300))
        #expect(close(result.measures.startGap, 30, within: 0.01))
        #expect(close(result.measures.coverage, 245.0 / 250.0, within: 1e-5))
        #expect(result.failed == [.ends])
        #expect(result.outcome == .reject)
    }

    // MARK: GPS noise that is not a slow drift

    /// Each fix thrown sideways on its own, by up to 2 m. The expected values
    /// are bounds that follow from the size of the noise, not from one run.
    @Test(arguments: [1, 2, 3, 4, 5] as [UInt64])
    func smallSampleToSampleJitterStillJoins(seed: UInt64) throws {
        // Proximity: every point within 2 m, 100%.
        // Ends and coverage: the jitter is sideways only, so the points keep
        //   their route distances: gaps 0, everything mapped.
        // Length: neighbours differ by at most 4 m sideways, so a 20 m step
        //   becomes at most sqrt(20^2 + 4^2) = 20.396 m: ratio 1 to 1.0198.
        // Side offset: no average of values within 2 m exceeds 2 m.
        var generator = SeededGenerator(seed: seed)
        let jittered = road.map { $0.moved(north: generator.signedUnit() * 2) }
        let result = try align(jittered, to: road)
        #expect(close(result.measures.proximity, 1, within: 1e-9))
        #expect(close(result.measures.startGap, 0, within: 0.01))
        #expect(close(result.measures.endGap, 0, within: 0.01))
        #expect(close(result.measures.coverage, 1, within: 1e-5))
        #expect(result.measures.lengthRatio >= 1 - 1e-6)
        #expect(result.measures.lengthRatio <= 1.0198 + 1e-6)
        #expect(abs(result.measures.worstSideOffset) <= 2.01)
        #expect(result.failed.isEmpty)
        #expect(result.outcome == .join)
    }

    /// Jitter stretches the distance travelled. A track cleaned too little
    /// fails the length ratio and is asked about; it does not join.
    @Test func heavyJitterInflatesTheLengthAndGoesToReview() throws {
        // Every other fix 8 m left, the rest 8 m right. Each 20 m step
        // becomes sqrt(20^2 + 16^2) = 25.612 m: ratio 1.2806. Fails.
        // Proximity: every point within 8 m, 100%. Ends and coverage pass.
        // Side offset: a stretch holds 11 points, six on one side and five
        //   on the other: 8 / 11 = 0.73 one way or the other, or 0 if
        //   rounding leaves the last point out. Passes.
        let zigzag = road.enumerated().map { index, point in
            point.moved(north: index.isMultiple(of: 2) ? 8 : -8)
        }
        let result = try align(zigzag, to: road)
        #expect(close(result.measures.proximity, 1, within: 1e-9))
        #expect(close(result.measures.lengthRatio, 2561.25 / 2000, within: 1e-5))
        #expect(abs(result.measures.worstSideOffset) <= 8.0 / 11.0 + 0.01)
        #expect(result.failed == [.lengthRatio])
        #expect(result.outcome == .manualReview)
    }

    /// Error along the road instead of across it.
    @Test(arguments: [1, 2, 3, 4, 5] as [UInt64])
    func alongTrackErrorStillJoins(seed: UInt64) throws {
        // Each fix is moved up to 2 m forward or back along the road, so
        // neighbours stay at least 16 m apart and in order.
        // Proximity: every point is on the road itself, or within 2 m of one
        //   of its ends: 100%.
        // Ends: the first and last points on the line are within 2 m of the
        //   ends. Coverage: at least (2000 - 4) / 2000 = 0.998.
        // Length: 2000 m give or take 4 m, ratio 0.998 to 1.002.
        // Side offset: nothing is sideways. 0.
        var generator = SeededGenerator(seed: seed)
        let shifted = road.map { $0.moved(east: generator.signedUnit() * 2) }
        let result = try align(shifted, to: road)
        #expect(close(result.measures.proximity, 1, within: 1e-9))
        #expect(result.measures.startGap <= 2.01)
        #expect(result.measures.endGap <= 2.01)
        #expect(result.measures.coverage >= 0.998 - 1e-6)
        #expect(result.measures.lengthRatio >= 0.998 - 1e-6)
        #expect(result.measures.lengthRatio <= 1.002 + 1e-6)
        #expect(close(result.measures.worstSideOffset, 0, within: 0.01))
        #expect(result.failed.isEmpty)
        #expect(result.outcome == .join)
    }

    // MARK: Virtual rides

    /// "Virtual rides match the same way, because Zwift's coordinates are
    /// consistent between rides." Nothing in the rules reads whether a ride
    /// is virtual, so this is the same repeat as on any road, placed where
    /// Zwift puts its main world: about 11.7 degrees south and 167 degrees
    /// east, the other side of the equator and far from longitude 0.
    @Test func aRepeatedVirtualRideJoinsThroughBothSteps() throws {
        // The origin's latitude is chosen so the road runs along the middle
        // of a row of the grid: 25 m above the bottom edge of row -25,926,
        // which is -25,926 * 50 + 25 = -1,296,275 m north of the equator.
        // The second ride reads 3 m further north: the same row, and the
        // same columns bar perhaps one at each end.
        // Alignment: every point 3 m to the left, all else perfect. Joins.
        let northing = -25_926.0 * 50 + 25
        let plane = Plane(origin: Coordinate(
            latitude: northing / (Geodesy.earthRadius * .pi / 180),
            longitude: 166.95
        ))
        let first = track(Course.eastRoad(from: 10, to: 2010), plane: plane)
        let second = track(Course.eastRoad(from: 10, to: 2010, north: 3), plane: plane)
        let route = try #require(RouteReference(track: first))
        let matches = RouteMatcher.match(second, against: [route])
        #expect(matches.map(\.outcome) == [.join])
        let measures = try #require(matches.first?.measures)
        #expect(close(measures.proximity, 1, within: 1e-9))
        #expect(close(measures.worstSideOffset, -3, within: 0.05))
        #expect(close(measures.lengthRatio, 1, within: 1e-4))
    }
}

/// The starting values the first round did not exercise with another value.
/// "Every threshold here is a starting value to tune against real history",
/// so each one has to be read from the rules, not written into the code.
@Suite struct RulesCustomisationTests {
    let plane = Plane.equator
    private let clean = AlignmentMeasures.clean

    private func row(_ first: Int, count: Int) -> Set<GridCell> {
        Set((first..<first + count).map { GridCell(column: $0, row: 0) })
    }

    private func signature(
        length: Double = 1000,
        start: P = P(0, 0),
        cells: Set<GridCell>? = nil
    ) -> TrackSignature {
        TrackSignature(
            sportFamily: .cycling,
            length: length,
            start: plane.coordinate(start),
            finish: plane.coordinate(P(1000, 0)),
            cells: cells ?? row(0, count: 20)
        )
    }

    @Test func theDistanceToleranceComesFromTheRules() {
        // 1150 m against 1000 m is 150 m apart. At 10% the limit is 100 m;
        // at 20% it is 200 m.
        var rules = MatchingRules.standard
        rules.distanceTolerance = 0.20
        let candidate = signature(length: 1150)
        #expect(!RouteDetection.gates(candidate: candidate, reference: signature()).distanceWithinTolerance)
        #expect(RouteDetection.gates(candidate: candidate, reference: signature(), rules: rules).distanceWithinTolerance)
    }

    @Test func theEndpointToleranceComesFromTheRules() {
        // A start 300 m away: outside 200 m, inside 400 m.
        var rules = MatchingRules.standard
        rules.endpointTolerance = 400
        let candidate = signature(start: P(300, 0))
        #expect(!RouteDetection.gates(candidate: candidate, reference: signature()).startWithinTolerance)
        #expect(RouteDetection.gates(candidate: candidate, reference: signature(), rules: rules).startWithinTolerance)
    }

    @Test func theSharedCellMinimumComesFromTheRules() {
        // 16 of 20 cells shared is 0.80: under 85%, over 75%.
        var rules = MatchingRules.standard
        rules.minimumSharedCells = 0.75
        let candidate = signature(cells: row(4, count: 20))
        #expect(!RouteDetection.gates(candidate: candidate, reference: signature()).isShortlisted)
        #expect(RouteDetection.gates(candidate: candidate, reference: signature(), rules: rules).isShortlisted)
        #expect(RouteDetection.shortlist(candidate: candidate, references: [signature()], rules: rules) == [0])
    }

    @Test func theCoverageMinimumComesFromTheRules() {
        // 92% covered: under 95%, over 90%.
        var rules = MatchingRules.standard
        rules.minimumCoverage = 0.90
        let measures = clean.with { $0.coverage = 0.92 }
        #expect(measures.failedMeasures() == [.coverage])
        #expect(measures.outcome() == .reject)
        #expect(measures.failedMeasures(rules: rules).isEmpty)
        #expect(measures.outcome(rules: rules) == .join)
    }

    @Test func theLongestUnmappedStretchComesFromTheRules() {
        // An 80 m unmapped stretch: over 50 m, under 100 m.
        var rules = MatchingRules.standard
        rules.longestUnmappedStretch = 100
        let measures = clean.with {
            $0.coverage = 0.96
            $0.longestUnmappedStretch = 80
        }
        #expect(measures.failedMeasures() == [.coverage])
        #expect(measures.failedMeasures(rules: rules).isEmpty)
    }

    @Test func theLengthRatioToleranceComesFromTheRules() {
        // 4% long or 4% short: outside 3%, inside 5%.
        var rules = MatchingRules.standard
        rules.lengthRatioTolerance = 0.05
        for ratio in [1.04, 0.96] {
            let measures = clean.with { $0.lengthRatio = ratio }
            #expect(measures.outcome() == .manualReview)
            #expect(measures.outcome(rules: rules) == .join)
        }
    }

    @Test func theEndToleranceComesFromTheRules() {
        // A start 40 m late: beyond 25 m, within 50 m.
        var rules = MatchingRules.standard
        rules.endTolerance = 50
        let measures = clean.with { $0.startGap = 40 }
        #expect(measures.outcome() == .reject)
        #expect(measures.outcome(rules: rules) == .join)
    }

    @Test func theSideOffsetStretchComesFromTheRules() {
        // 51 points every 20 m on a 1000 m line. The six points from 400 to
        // 500 m are 12 m to the right. Over 200 m they are six of eleven
        // points, 72 / 11 = 6.545. Over 100 m the stretch that starts at
        // 400 m holds exactly those six: 12.
        var rules = MatchingRules.standard
        rules.sideOffsetStretch = 100
        let points = stride(from: 0.0, through: 1000, by: 20).map { mapped($0, side: (400...500).contains($0) ? 12 : 0) }
        let standard = AlignmentMeasures(points: points, referenceLength: 1000, trackLength: 1000)
        let shorter = AlignmentMeasures(points: points, referenceLength: 1000, trackLength: 1000, rules: rules)
        #expect(close(standard.worstSideOffset, 72.0 / 11.0, within: 1e-9))
        #expect(close(shorter.worstSideOffset, 12, within: 1e-9))
    }

    @Test func theGridSpacingComesFromTheRules() throws {
        // A 250 m line: section 25 to 225 m. The subject rides at 10 m/s and
        // the baseline at 5 m/s, so at `d` metres the gap is
        // (d - 25) / 10 - (d - 25) / 5 = -(d - 25) / 10.
        let fast = alignment([mapped(0, t: 0), mapped(250, t: 25)], referenceLength: 250)
        let slow = alignment([mapped(0, t: 0), mapped(250, t: 50)], referenceLength: 250)

        // Every 50 m: 25, 75, 125, 175, 225. Gaps 0, -5, -10, -15, -20.
        var rules = MatchingRules.standard
        rules.comparisonGridSpacing = 50
        let coarse = try #require(RouteComparison.compare(fast, against: slow, rules: rules).value)
        #expect(coarse.grid.map(\.routeDistance) == [25, 75, 125, 175, 225])
        for (point, gap) in zip(coarse.grid, [0.0, -5, -10, -15, -20]) {
            #expect(close(point.gap, gap, within: 1e-9))
        }

        // Every 80 m: 25, 105, 185. The next step, 265 m, is past the end
        // mark, so the end mark itself closes the grid.
        rules.comparisonGridSpacing = 80
        let uneven = try #require(RouteComparison.compare(fast, against: slow, rules: rules).value)
        #expect(uneven.grid.map(\.routeDistance) == [25, 105, 185, 225])

        // A spacing of zero cannot be stepped along: the two marks alone.
        rules.comparisonGridSpacing = 0
        let marks = try #require(RouteComparison.compare(fast, against: slow, rules: rules).value)
        #expect(marks.grid.map(\.routeDistance) == [25, 225])
        #expect(close(marks.grid[1].gap, -20, within: 1e-9))
    }
}

/// Comparison rules the first round documented without a test.
@Suite struct FurtherComparisonTests {
    /// A steady 10 m/s from end to end of a 250 m line.
    private let steady = alignment(
        [mapped(0, t: 0), mapped(50, t: 5), mapped(100, t: 10), mapped(150, t: 15), mapped(200, t: 20), mapped(250, t: 25)],
        referenceLength: 250
    )

    /// "Where several points share one clock time, the marker is at the
    /// furthest of them."
    @Test func whenSeveralPointsShareOneClockTimeTheMarkerIsAtTheFurthest() throws {
        // The subject is at 100 m and at 150 m in the same second, 10 s, as
        // a track can be after a gap in the recording.
        //   Start mark, 25 m: a quarter of the way from (0 m, 0 s) to
        //     (100 m, 10 s): 2.5 s.
        //   End mark, 225 m: three quarters of the way from (150 m, 10 s) to
        //     (250 m, 20 s): 17.5 s. Route time 15 s.
        // Clock 7.4 s is 9.9 s: 99% of the way to 100 m, at 99 m.
        // Clock 7.5 s is 10 s exactly: the furthest point reached, 150 m.
        // Clock 8.5 s is 11 s: a tenth of the way from 150 m to 250 m, 160 m.
        // The steady baseline, entering at 2.5 s, is at 99 m, 100 m and
        // 110 m at those moments.
        let jumped = alignment(
            [mapped(0, t: 0), mapped(100, t: 10), mapped(150, t: 10), mapped(250, t: 20)],
            referenceLength: 250
        )
        let comparison = try #require(RouteComparison.compare(jumped, against: steady).value)
        #expect(close(comparison.subjectTimes.start, 2.5, within: 1e-9))
        #expect(close(comparison.subjectTimes.duration, 15, within: 1e-9))

        let before = comparison.ghost(at: 7.4)
        #expect(close(before.subjectRouteDistance, 99, within: 1e-9))
        #expect(close(before.baselineRouteDistance, 99, within: 1e-9))

        let atTheJump = comparison.ghost(at: 7.5)
        #expect(close(atTheJump.subjectRouteDistance, 150, within: 1e-9))
        #expect(close(atTheJump.baselineRouteDistance, 100, within: 1e-9))
        #expect(close(atTheJump.separation, -50, within: 1e-9))

        let after = comparison.ghost(at: 8.5)
        #expect(close(after.subjectRouteDistance, 160, within: 1e-9))
        #expect(close(after.baselineRouteDistance, 110, within: 1e-9))
    }

    /// "Both alignments must have the same reference length; the subject's
    /// is the one used."
    @Test func theSubjectsReferenceLengthSetsTheTimedSection() {
        // The same mapped points filed against a 400 m line.
        let longer = Alignment(points: steady.points, referenceLength: 400, trackLength: 250)

        // Subject on the 250 m line: section 25 to 225 m, which both cover.
        let comparison = RouteComparison.compare(steady, against: longer).value
        #expect(comparison?.section == TimedSection(start: 25, end: 225))
        #expect(comparison?.grid.count == 21)

        // Subject on the 400 m line: section 25 to 375 m. Neither effort
        // goes past 250 m, so neither covers it.
        #expect(RouteComparison.compare(longer, against: steady).reason == .timedSectionNotCovered)
    }

    /// The moving clock of an effort without reliable pause positions is
    /// never read, even when only the route time is asked for.
    @Test func comparingTwoEffortsWithoutReliablePausePositionsUsesElapsedTime() throws {
        // Both at 10 m/s by elapsed time, with moving times that say 0.
        let unreliable = alignment(
            [mapped(0, elapsed: 0, moving: 0), mapped(250, elapsed: 25, moving: 0)],
            referenceLength: 250,
            pausePositionsAreReliable: false
        )
        let comparison = try #require(RouteComparison.compare(unreliable, against: unreliable).value)
        #expect(comparison.clock == .elapsed)
        #expect(!comparison.movingTimeIsAvailable)
        // 200 m at 10 m/s.
        #expect(close(comparison.subjectTimes.duration, 20, within: 1e-9))
        #expect(comparison.grid.allSatisfy { abs($0.gap) < 1e-9 })
    }
}
