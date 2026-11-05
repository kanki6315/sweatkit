import SweatKitModel
@testable import SweatKitTrackCleanup
import Testing

/// Step 3: simplify to about 2 m, keeping each vertex's sample.
@Suite struct SimplificationTests {
    @Test func theToleranceIsTwoMetres() {
        #expect(CleanupRules.simplificationTolerance == 2)
    }

    @Test func aStraightLineKeepsOnlyItsEnds() {
        // Eleven points due east, 10 m apart. Every inner point is 0 m off
        // the line from first to last, so only seconds 0 and 10 are drawn.
        let cleaned = TrackCleanup.clean(makeStream(steadyEast(count: 11, speed: 10)), sport: .cycling)
        let line = TrackCleanup.simplify(cleaned)
        #expect(line.vertices.map(\.sampleIndex) == [0, 10])
        #expect(line.vertices.map(\.coordinate) == [Ground.at(east: 0), Ground.at(east: 100)])
        #expect(close(line.length, 100))
    }

    @Test func aPointWithinTheToleranceIsDropped() {
        // The middle point is 1.9 m north of the line from 0 to 100 m east,
        // and 1.9 m is within 2 m.
        let seconds = [
            Second(east: 0, speed: 5),
            Second(east: 50, north: 1.9, speed: 5),
            Second(east: 100, speed: 5),
        ]
        let points = TrackCleanup.positions(in: makeStream(seconds))
        #expect(TrackCleanup.simplified(points, tolerance: 2).map(\.sampleIndex) == [0, 2])
    }

    @Test func aPointBeyondTheToleranceIsKept() {
        // 2.1 m north of the line is beyond 2 m, so it stays.
        let seconds = [
            Second(east: 0, speed: 5),
            Second(east: 50, north: 2.1, speed: 5),
            Second(east: 100, speed: 5),
        ]
        let points = TrackCleanup.positions(in: makeStream(seconds))
        #expect(TrackCleanup.simplified(points, tolerance: 2).map(\.sampleIndex) == [0, 1, 2])
    }

    @Test func distanceIsToTheSegmentNotTheWholeLine() {
        // The middle point is 0 m north but 5 m beyond the far end of the
        // segment from 0 to 100 m east, so its distance is 5 m to that end
        // and it is kept.
        let seconds = [
            Second(east: 0, speed: 5),
            Second(east: 105, speed: 5),
            Second(east: 100, speed: 5),
        ]
        let points = TrackCleanup.positions(in: makeStream(seconds))
        #expect(TrackCleanup.simplified(points, tolerance: 2).map(\.sampleIndex) == [0, 1, 2])
    }

    @Test func aCornerIsKeptAndTheMapPointsAtItsSecond() {
        // East 0 -> 20 m, then north 0 -> 20 m, with no position at seconds 1
        // and 5. The corner at second 3 (20, 0) is 14.1 m from the line from
        // first to last, so it stays; seconds 2 and 6 lie on the two legs and
        // go. Every vertex keeps the grid second it came from.
        let seconds = [
            Second(east: 0, speed: 5),
            .noPosition(speed: 5),
            Second(east: 10, speed: 5),
            Second(east: 20, speed: 5),
            .noPosition(speed: 5),
            .noPosition(speed: 5),
            Second(east: 20, north: 10, speed: 5),
            Second(east: 20, north: 20, speed: 5),
        ]
        let cleaned = TrackCleanup.clean(makeStream(seconds), sport: .cycling)
        #expect(cleaned.points.map(\.sampleIndex) == [0, 2, 3, 6, 7])
        let line = TrackCleanup.simplify(cleaned)
        #expect(line.vertices.map(\.sampleIndex) == [0, 3, 7])
        #expect(line.vertices.map(\.coordinate) == [
            Ground.at(east: 0), Ground.at(east: 20), Ground.at(east: 20, north: 20),
        ])
        // 20 m east then 20 m north.
        #expect(close(line.length, 40))
    }

    @Test func theMapSurvivesAllThreeSteps() {
        // A ride: seconds 0-4 east at 5 m/s, a spike at 2 (300 m north,
        // dropped by step 1), a stop at seconds 5-8 near 25 m (collapsed into
        // second 5 by step 2), then a turn north from 25 m at 5 m/s for
        // seconds 9-12. Cleaned: 0, 1, 3, 4, 5, 9, 10, 11, 12. Simplified:
        // the legs are straight, so first, corner and last remain: 0, 5, 12.
        var seconds = steadyEast(count: 5, speed: 5)
        seconds[2].north = 300
        for wobble in StopTests.jitter.prefix(4) {
            seconds.append(Second(east: 25 + wobble.east, north: wobble.north, speed: 0.3))
        }
        for step in 1...4 {
            seconds.append(Second(east: 25, north: Double(step) * 5, speed: 5))
        }
        let cleaned = TrackCleanup.clean(makeStream(seconds), sport: .cycling)
        #expect(cleaned.points.map(\.sampleIndex) == [0, 1, 3, 4, 5, 9, 10, 11, 12])
        let line = TrackCleanup.simplify(cleaned)
        #expect(line.vertices.map(\.sampleIndex) == [0, 5, 12])
        #expect(line.vertices[1].coveredSamples == 5...8)
        // Strictly increasing, as the flyover requires.
        #expect(zip(line.sampleIndices, line.sampleIndices.dropFirst()).allSatisfy { $0 < $1 })
        // 25 m east then 20 m north.
        #expect(close(line.length, 45))
    }

    @Test func repeatedPositionsDoNotBreakSimplification() {
        // Seconds 1 and 2 share a position, so one piece has no length. The
        // line is still straight from 0 to 20 m, so only the ends remain.
        let seconds = [
            Second(east: 0, speed: 5),
            Second(east: 10, speed: 5),
            Second(east: 10, speed: 5),
            Second(east: 20, speed: 5),
        ]
        let points = TrackCleanup.positions(in: makeStream(seconds))
        #expect(TrackCleanup.simplified(points, tolerance: 2).map(\.sampleIndex) == [0, 3])
    }

    @Test func aClosedLoopKeepsItsShape() {
        // A 20 m square that returns to its start: first and last are the
        // same position. The far corners are 20 m and 28.3 m away and stay.
        let corners: [(Double, Double)] = [(0, 0), (20, 0), (20, 20), (0, 20), (0, 0)]
        let seconds = corners.map { Second(east: $0.0, north: $0.1, speed: 5) }
        let points = TrackCleanup.positions(in: makeStream(seconds))
        #expect(TrackCleanup.simplified(points, tolerance: 2).map(\.sampleIndex) == [0, 1, 2, 3, 4])
    }
}
