import SweatKitModel
@testable import SweatKitTrackCleanup
import Testing

/// Step 2: collapse jitter while stopped into a single point.
@Suite struct StopTests {
    @Test func stoppedMeansBelowTheMovingTimeFloor() {
        #expect(CleanupRules.stoppedSpeed(for: .cycling) == 1.0)
        #expect(CleanupRules.stoppedSpeed(for: .onFoot) == 0.5)
        #expect(CleanupRules.stoppedSpeed(for: .other) == nil)
    }

    /// Jitter around a fixed spot: within a metre each way, never the same
    /// twice in a row.
    static let jitter: [(east: Double, north: Double)] = [
        (0, 0), (0.8, -0.6), (-0.5, 0.9), (0.3, 0.4), (-0.9, -0.2), (0.6, 0.7),
    ]

    @Test func aStopInTheMiddleOfARide() {
        // Seconds 0-4 ride east at 5 m/s to 20 m. Seconds 5-9 stand at about
        // 25 m with speed 0.2 m/s (below the 1.0 m/s bike floor) and jitter.
        // Seconds 10-14 ride on from 30 m at 5 m/s.
        var seconds = steadyEast(count: 5, speed: 5)
        for index in 0..<5 {
            let wobble = Self.jitter[index]
            seconds.append(Second(east: 25 + wobble.east, north: wobble.north, speed: 0.2))
        }
        seconds += steadyEast(count: 5, speed: 5, startEast: 30)
        let cleaned = TrackCleanup.clean(makeStream(seconds), sport: .cycling)
        // The stop's five points become one: the first, second 5, standing
        // for seconds 5 to 9.
        #expect(cleaned.points.map(\.sampleIndex) == [0, 1, 2, 3, 4, 5, 10, 11, 12, 13, 14])
        let stop = cleaned.points[5]
        #expect(stop.coordinate == Ground.at(east: 25))
        #expect(stop.coveredSamples == 5...9)
        #expect(cleaned.points.filter { $0.sampleIndex != 5 }.allSatisfy { $0.coveredSamples.count == 1 })
        // Length: 0 -> 25 -> 30 -> 50 along one line is 50 m. The jitter's
        // extra travel is gone.
        #expect(close(cleaned.length, 50))
    }

    @Test func stopsAtTheStartAndEndCollapse() {
        // A walk. Seconds 0-3 stand at 0 with speed 0, seconds 4-8 walk east
        // from 2 m at 1.5 m/s to 8 m, and seconds 9-12 stand near 9 m with
        // speed 0.1 m/s: the tangle at the end of a recording.
        var seconds: [Second] = []
        for index in 0..<4 {
            let wobble = Self.jitter[index]
            seconds.append(Second(east: wobble.east, north: wobble.north, speed: 0))
        }
        seconds += steadyEast(count: 5, speed: 1.5, startEast: 2)
        for index in 0..<4 {
            let wobble = Self.jitter[index]
            seconds.append(Second(east: 9 + wobble.east, north: wobble.north, speed: 0.1))
        }
        let cleaned = TrackCleanup.clean(makeStream(seconds), sport: .walking)
        #expect(cleaned.points.map(\.sampleIndex) == [0, 4, 5, 6, 7, 8, 9])
        #expect(cleaned.points.first?.coveredSamples == 0...3)
        #expect(cleaned.points.last?.coveredSamples == 9...12)
        // 0 -> 2 -> 8 -> 9 along the line: 9 m.
        #expect(close(cleaned.length, 9))
    }

    @Test func speedAtTheFloorIsMoving() {
        // Exactly 0.5 m/s on foot is not below the floor, so nothing
        // collapses.
        let seconds = steadyEast(count: 4, speed: 0.5)
        let cleaned = TrackCleanup.clean(makeStream(seconds), sport: .hiking)
        #expect(cleaned.points.map(\.sampleIndex) == [0, 1, 2, 3])
    }

    @Test func missingSpeedIsNotStopped() {
        // Seconds 1-3 jitter but have no speed. The spec counts a second with
        // missing speed as moving, so they are not collapsed.
        var seconds = [Second(east: 0, speed: 0)]
        for index in 1...3 {
            let wobble = Self.jitter[index]
            seconds.append(Second(east: wobble.east, north: wobble.north, speed: nil))
        }
        let cleaned = TrackCleanup.clean(makeStream(seconds), sport: .walking)
        #expect(cleaned.points.map(\.sampleIndex) == [0, 1, 2, 3])
    }

    @Test func aStopSpansSecondsWithoutAPosition() {
        // Stopped seconds 1, 2 and 4 with second 3 lacking a position: the
        // three stopped points are consecutive on the track, so they become
        // one point standing for seconds 1 to 4.
        let seconds = [
            Second(east: 0, speed: 3),
            Second(east: 3, speed: 0),
            Second(east: 3.5, speed: 0),
            .noPosition(speed: 0),
            Second(east: 3.2, north: 0.4, speed: 0),
            Second(east: 6, speed: 3),
        ]
        let cleaned = TrackCleanup.clean(makeStream(seconds), sport: .running)
        #expect(cleaned.points.map(\.sampleIndex) == [0, 1, 5])
        #expect(cleaned.points[1].coveredSamples == 1...4)
    }

    @Test func otherSportsDoNotCollapse() {
        let seconds = (0..<4).map { Second(east: Self.jitter[$0].east, north: Self.jitter[$0].north, speed: 0) }
        let cleaned = TrackCleanup.clean(makeStream(seconds), sport: .other)
        #expect(cleaned.points.map(\.sampleIndex) == [0, 1, 2, 3])
    }

    @Test func aDroppedSpikeInsideAStopDoesNotSplitIt() {
        // Step 1 runs first. Second 3, inside a stop, jumps 400 m (400 m/s on
        // foot) and is dropped, so seconds 2, 4 and 5 are consecutive and
        // collapse into second 2.
        let seconds = [
            Second(east: 0, speed: 2),
            Second(east: 2, speed: 2),
            Second(east: 4, speed: 0),
            Second(east: 4, north: 400, speed: 0),
            Second(east: 4.5, speed: 0),
            Second(east: 4.2, north: 0.3, speed: 0),
            Second(east: 6, speed: 2),
        ]
        let cleaned = TrackCleanup.clean(makeStream(seconds), sport: .walking)
        #expect(cleaned.points.map(\.sampleIndex) == [0, 1, 2, 6])
        #expect(cleaned.points[2].coveredSamples == 2...5)
    }
}
