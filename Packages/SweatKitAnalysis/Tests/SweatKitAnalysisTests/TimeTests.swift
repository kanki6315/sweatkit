import Foundation
import SweatKitModel
import Testing
@testable import SweatKitAnalysis

/// The spec's "Time" table, for an activity with a stream.
@Suite struct TimeTests {
    // MARK: Elapsed and timer time

    @Test func elapsedIsTheLengthOfTheStream() {
        // The stream is a 1 Hz grid over elapsed time: 100 samples are 100 s.
        let metrics = analyse(makeStream(count: 100))
        #expect(metrics.time.elapsed == .available(100))
    }

    @Test func timerIsElapsedMinusThePausedSpans() {
        // Paused 20..<30 (10 s) and 50..<70 (20 s): 100 - 10 - 20 = 70.
        let stream = makeStream(count: 100, pauses: .known(paused: [20..<30, 50..<70]))
        let metrics = analyse(stream)
        #expect(metrics.time.elapsed == .available(100))
        #expect(metrics.time.timer == .available(70))
        #expect(metrics.time.timerIsSummaryOnly == false)
    }

    @Test func timerWithoutPausesEqualsElapsed() {
        let metrics = analyse(makeStream(count: 60))
        #expect(metrics.time.timer == .available(60))
    }

    @Test func timerWithUnknownPausePositionsIsTheStatedFigure() {
        // The stated 80 s is used as it is; the stream still gives 100 s elapsed.
        let stream = makeStream(count: 100, pauses: .unknown(statedTimerTime: 80))
        let metrics = analyse(stream)
        #expect(metrics.time.elapsed == .available(100))
        #expect(metrics.time.timer == .available(80))
        #expect(metrics.time.timerIsSummaryOnly)
    }

    @Test func timerWithUnknownPausePositionsAndNoStatedFigureIsUnavailable() {
        let stream = makeStream(count: 100, pauses: .unknown(statedTimerTime: nil))
        let metrics = analyse(stream)
        #expect(metrics.time.timer == .unavailable(.notStated))
        #expect(metrics.time.timerIsSummaryOnly == false)
        #expect(metrics.time.elapsed == .available(100))
    }

    // MARK: Moving time

    @Test func movingOnABikeLeavesOutSecondsBelowOneMetrePerSecond() {
        // Below 1.0 m/s: 0.9, 0 and 0.5, three seconds. 10 - 3 = 7.
        let stream = makeStream(count: 10, speed: [5, 5, 5, 0.9, 0, 0.5, 5, 5, 5, 5])
        #expect(analyse(stream, sport: .cycling).time.moving == .available(7))
    }

    @Test(arguments: [Sport.walking, .running, .hiking])
    func movingOnFootLeavesOutSecondsBelowHalfAMetrePerSecond(sport: Sport) {
        // Below 0.5 m/s: 0.4 and 0.3, two seconds. 0.9 is moving on foot. 5 - 2 = 3.
        let stream = makeStream(count: 5, speed: [0.6, 0.6, 0.4, 0.9, 0.3])
        #expect(analyse(stream, sport: sport).time.moving == .available(3))
    }

    @Test func aSecondExactlyAtTheFloorIsMoving() {
        // "Below" is strict. Bike: only 0.99 is below 1.0, so 4 - 1 = 3.
        let ride = makeStream(count: 4, speed: [1.0, 1.0, 0.99, 5])
        #expect(analyse(ride, sport: .cycling).time.moving == .available(3))
        // Foot: 0.49 and 0.4 are below 0.5, so 4 - 2 = 2.
        let walk = makeStream(count: 4, speed: [0.5, 0.49, 0.4, 2])
        #expect(analyse(walk, sport: .walking).time.moving == .available(2))
    }

    @Test func aSecondWithMissingSpeedCountsAsMoving() {
        // Only the recorded 0 m/s is stopped: 5 - 1 = 4.
        let stream = makeStream(count: 5, speed: [5, nil, nil, 0, 5])
        #expect(analyse(stream).time.moving == .available(4))
    }

    @Test func movingSubtractsSlowSecondsFromTimerTimeOnly() {
        // Paused 2..<5, so timer = 10 - 3 = 7. Slow seconds are 2, 3, 4 and 5,
        // but 2, 3 and 4 are already out as paused. Moving = 7 - 1 = 6.
        let stream = makeStream(
            count: 10,
            pauses: .known(paused: [2..<5]),
            speed: [5, 5, 0, 0, 0, 0, 5, 5, 5, 5]
        )
        let metrics = analyse(stream)
        #expect(metrics.time.timer == .available(7))
        #expect(metrics.time.moving == .available(6))
    }

    @Test func indoorMovingTimeEqualsTimerTime() {
        // Paused 0..<2, so timer = 8. Indoors the speed, all 0 here, is not read.
        let stream = makeStream(count: 10, pauses: .known(paused: [0..<2]), speed: run(0, 10))
        let metrics = analyse(stream, indoor: true)
        #expect(metrics.time.timer == .available(8))
        #expect(metrics.time.moving == .available(8))
    }

    @Test func movingTimeWithoutSpeedEqualsTimerTime() {
        // Outdoors, no speed channel at all. Paused 3..<5, so timer = 8.
        let stream = makeStream(count: 10, pauses: .known(paused: [3..<5]), power: run(200, 10))
        let metrics = analyse(stream)
        #expect(metrics.time.moving == .available(8))
    }

    @Test func movingTimeForASportWithNoFloorEqualsTimerTime() {
        // The spec gives a floor on foot and on a bike only.
        let stream = makeStream(count: 10, speed: run(0.1, 10))
        #expect(analyse(stream, sport: .other).time.moving == .available(10))
    }

    @Test func movingTimeIsUnavailableWithUnknownPausePositionsEvenIndoors() {
        let stream = makeStream(count: 100, pauses: .unknown(statedTimerTime: 80), speed: run(5, 100))
        #expect(analyse(stream, indoor: false).time.moving == .unavailable(.pausePositionsUnknown))
        #expect(analyse(stream, indoor: true).time.moving == .unavailable(.pausePositionsUnknown))
    }

    // MARK: Sensor gaps are not pauses

    @Test func aSensorGapNeverShortensElapsedTimerOrMovingTime() {
        // Every sensor drops out for seconds 5..<15. Nothing was paused.
        let dropout = run(5, 5) + run(nil, 10) + run(5, 5)
        let stream = makeStream(
            count: 20,
            power: run(200, 5) + run(nil, 10) + run(200, 5),
            heartRate: run(150, 5) + run(nil, 10) + run(150, 5),
            speed: dropout
        )
        let metrics = analyse(stream)
        #expect(metrics.time.elapsed == .available(20))
        #expect(metrics.time.timer == .available(20))
        #expect(metrics.time.moving == .available(20))
    }

    @Test func aStreamWithNoReadingsStillHasItsTimes() {
        let metrics = analyse(makeStream(count: 30))
        #expect(metrics.time.elapsed == .available(30))
        #expect(metrics.time.timer == .available(30))
        #expect(metrics.time.moving == .available(30))
    }
}
