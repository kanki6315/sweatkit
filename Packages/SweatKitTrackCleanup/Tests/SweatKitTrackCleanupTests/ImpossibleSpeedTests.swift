import SweatKitModel
@testable import SweatKitTrackCleanup
import Testing

/// Step 1: drop points that imply an impossible speed.
@Suite struct ImpossibleSpeedTests {
    @Test func theLimitsArePerSportFamily() {
        #expect(CleanupRules.impossibleSpeed(for: .cycling) == 30)
        #expect(CleanupRules.impossibleSpeed(for: .onFoot) == 12)
        #expect(CleanupRules.impossibleSpeed(for: .other) == nil)
    }

    @Test func aSingleSpikeIsDropped() {
        // A ride east at 10 m/s. Second 3 jumps 500 m north: from second 2
        // that is sqrt(10^2 + 500^2) = 500.1 m in 1 s, far above 30 m/s, so
        // it goes. Second 4 is then measured from second 2, the last point
        // kept: 20 m in 2 s = 10 m/s, so it stays.
        var seconds = steadyEast(count: 6, speed: 10)
        seconds[3].north = 500
        let points = TrackCleanup.positions(in: makeStream(seconds))
        let kept = TrackCleanup.droppingImpossibleSpeeds(points, limit: 30)
        #expect(kept.map(\.sampleIndex) == [0, 1, 2, 4, 5])
        // Length 0 -> 50 m along the road: 5 steps of 10 m with the spike gone.
        #expect(close(TrackGeodesy.length(of: kept.map(\.coordinate)), 50))
    }

    @Test func aRunOfImpossiblePointsIsDroppedWhole() {
        // Seconds 3, 4 and 5 sit 500 m north. Each is measured from second 2,
        // the last point kept: about 500 m in 1, 2 and 3 s, all above 30 m/s.
        // Second 6 is 40 m east of second 2 in 4 s = 10 m/s and stays.
        var seconds = steadyEast(count: 8, speed: 10)
        for index in 3...5 { seconds[index].north = 500 }
        let cleaned = TrackCleanup.clean(makeStream(seconds), sport: .cycling)
        #expect(cleaned.points.map(\.sampleIndex) == [0, 1, 2, 6, 7])
    }

    @Test func speedAtTheLimitIsKeptAndAboveItIsDropped() {
        // On foot, limit 12 m/s. Second 1 is 11 m on (11 m/s, kept). Second 2
        // is 13 m past second 1 (13 m/s, dropped). Second 3 is 24 m past
        // second 1 in 2 s (12 m/s, exactly the limit, kept).
        let seconds = [
            Second(east: 0, speed: 3),
            Second(east: 11, speed: 3),
            Second(east: 24, speed: 3),
            Second(east: 35, speed: 3),
        ]
        let cleaned = TrackCleanup.clean(makeStream(seconds), sport: .running)
        #expect(cleaned.points.map(\.sampleIndex) == [0, 1, 3])
    }

    @Test func timeAcrossMissingSecondsCounts() {
        // 30 m between seconds 0 and 3, with no position in between, is
        // 30 m / 3 s = 10 m/s: possible on foot, though a single second's
        // 30 m would not be.
        let seconds = [
            Second(east: 0, speed: 3),
            .noPosition(speed: 3),
            .noPosition(speed: 3),
            Second(east: 30, speed: 3),
        ]
        let cleaned = TrackCleanup.clean(makeStream(seconds), sport: .walking)
        #expect(cleaned.points.map(\.sampleIndex) == [0, 3])
    }

    @Test func otherSportsKeepEveryPoint() {
        // No limit for "other": the 500 m spike stays.
        var seconds = steadyEast(count: 4, speed: 10)
        seconds[2].north = 500
        let cleaned = TrackCleanup.clean(makeStream(seconds), sport: .other)
        #expect(cleaned.points.map(\.sampleIndex) == [0, 1, 2, 3])
    }
}
