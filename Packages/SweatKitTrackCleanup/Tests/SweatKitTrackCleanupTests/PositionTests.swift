import SweatKitModel
import SweatKitTrackCleanup
import Testing

/// Reading positions off the grid, before any of the three steps.
@Suite struct PositionTests {
    @Test func secondsWithoutAPositionAreSkipped() {
        // Seconds 2 and 3 have no position. They are left out, not placed at
        // 0, 0, so the points are seconds 0, 1, 4 and 5.
        let stream = makeStream([
            Second(east: 0, speed: 5),
            Second(east: 5, speed: 5),
            .noPosition(speed: 5),
            .noPosition(),
            Second(east: 20, speed: 5),
            Second(east: 25, speed: 5),
        ])
        let points = TrackCleanup.positions(in: stream)
        #expect(points.map(\.sampleIndex) == [0, 1, 4, 5])
        #expect(points.map(\.coveredSamples) == [0...0, 1...1, 4...4, 5...5])
        #expect(points[2].coordinate == Ground.at(east: 20))
    }

    @Test func aStreamWithNoPositionsGivesNoPoints() {
        let stream = makeStream([.noPosition(speed: 3), .noPosition(speed: 3)])
        let cleaned = TrackCleanup.clean(stream, sport: .cycling)
        #expect(cleaned.points.isEmpty)
        #expect(cleaned.length == 0)
        let line = TrackCleanup.simplify(cleaned)
        #expect(line.vertices.isEmpty)
        #expect(line.length == 0)
    }

    @Test func aSinglePositionSurvivesEveryStep() {
        // One point: nothing to compare its speed with, nothing to collapse
        // it into, nothing to simplify. It stays, and the length is 0.
        let stream = makeStream([.noPosition(), Second(east: 7, speed: 0), .noPosition()])
        let cleaned = TrackCleanup.clean(stream, sport: .walking)
        #expect(cleaned.points.map(\.sampleIndex) == [1])
        #expect(cleaned.length == 0)
        let line = TrackCleanup.simplify(cleaned)
        #expect(line.vertices.map(\.sampleIndex) == [1])
        #expect(line.length == 0)
    }

    @Test func twoPointsAreKeptAsTheyAre() {
        // 10 m in 2 s is 5 m/s on a bike, possible and moving.
        let stream = makeStream([Second(east: 0, speed: 5), .noPosition(speed: 5), Second(east: 10, speed: 5)])
        let cleaned = TrackCleanup.clean(stream, sport: .cycling)
        #expect(cleaned.points.map(\.sampleIndex) == [0, 2])
        #expect(close(cleaned.length, 10))
        #expect(TrackCleanup.simplify(cleaned).vertices.map(\.sampleIndex) == [0, 2])
    }

    @Test func theTrackCarriesSportAndPauseReliability() {
        let known = makeStream(steadyEast(count: 3, speed: 5), pauses: .known(paused: [1..<2]))
        let unknown = makeStream(steadyEast(count: 3, speed: 5), pauses: .unknown(statedTimerTime: nil))
        #expect(TrackCleanup.clean(known, sport: .running).sport == .running)
        #expect(TrackCleanup.clean(known, sport: .running).pausePositionsAreReliable)
        #expect(!TrackCleanup.clean(unknown, sport: .running).pausePositionsAreReliable)
    }
}
