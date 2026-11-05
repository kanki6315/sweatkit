import Foundation
import SweatKitModel
import Testing
@testable import SweatKitAnalysis

/// Input a well-built stream never has. None of it may crash, and none of it
/// may turn into a zero that looks like a measurement.
@Suite struct DegenerateInputTests {
    // MARK: An empty stream

    @Test func anEmptyStreamHasZeroTimesAndNothingElse() {
        // No seconds at all: elapsed, timer and moving time are a true 0 s.
        // Coverage divides by timer time, which is zero.
        let metrics = analyse(makeStream(count: 0), profile: makeProfile(thresholdPower: 200, thresholdHeartRate: 200))
        #expect(metrics.time.elapsed == .available(0))
        #expect(metrics.time.timer == .available(0))
        #expect(metrics.time.moving == .available(0))
        #expect(metrics.power.coverage == .unavailable(.zeroDenominator))
        #expect(metrics.heartRate.coverage == .unavailable(.zeroDenominator))
        #expect(metrics.power.average == .unavailable(.noPower))
        #expect(metrics.power.weighted == .unavailable(.noPower))
        #expect(metrics.power.work == .unavailable(.noPower))
        #expect(metrics.heartRate.average == .unavailable(.noHeartRate))
        #expect(metrics.heartRate.load == .unavailable(.zeroDenominator))
        #expect(metrics.load == .unavailable(.zeroDenominator))
        #expect(metrics.distance == .unavailable(.noDistance))
        #expect(metrics.ascent == .unavailable(.noAltitude))
        #expect(metrics.timeInPowerZones == .unavailable(.noPower))
        #expect(metrics.timeInGradientBands == .unavailable(.noGradient))
    }

    @Test func anEmptyRunHasNoSplitsOrBestDistances() {
        let metrics = analyse(makeStream(count: 0), sport: .running)
        #expect(metrics.splits == .unavailable(.noDistance))
        #expect(metrics.bestDistances.map(\.time) == Array(repeating: .unavailable(.noDistance), count: 3))
        #expect(metrics.onFootEfficiency == .unavailable(.noSpeed))
    }

    @Test func anEmptyStreamHasNoPowerCurve() {
        let curve = ActivityAnalysis.powerCurve(for: makeInput(makeStream(count: 0)), durations: [1])
        #expect(curve == [PowerCurvePoint(duration: 1, power: .unavailable(.noPower))])
    }

    // MARK: Paused spans that do not fit the grid

    @Test func aPausedSpanRunningPastTheEndIsCutToTheGrid() {
        // Paused 8..<20 on a 10 s grid: only seconds 8 and 9 exist. 10 - 2 = 8.
        let stream = makeStream(count: 10, pauses: .known(paused: [8..<20]), power: run(200, 10))
        let metrics = analyse(stream)
        #expect(metrics.time.elapsed == .available(10))
        #expect(metrics.time.timer == .available(8))
        // All 8 timer seconds have power.
        expectClose(metrics.power.coverage, 1)
    }

    @Test func aPausedSpanWhollyOutsideTheGridPausesNothing() {
        let after = makeStream(count: 10, pauses: .known(paused: [10..<15]))
        #expect(analyse(after).time.timer == .available(10))
        let before = makeStream(count: 10, pauses: .known(paused: [(-5)..<0]))
        #expect(analyse(before).time.timer == .available(10))
    }

    @Test func aPausedSpanStartingBeforeTheGridIsCutToTheGrid() {
        // Paused -5..<3: seconds 0, 1 and 2. 10 - 3 = 7.
        let stream = makeStream(count: 10, pauses: .known(paused: [(-5)..<3]))
        #expect(analyse(stream).time.timer == .available(7))
    }

    @Test func overlappingPausedSpansAreCountedOnce() {
        // 2..<6 and 4..<8 together pause seconds 2 to 7, six seconds, not
        // eight. 10 - 6 = 4.
        let stream = makeStream(count: 10, pauses: .known(paused: [2..<6, 4..<8]))
        #expect(analyse(stream).time.timer == .available(4))
    }

    @Test func pausedSpansOutOfOrderGiveTheSameTimerTime() {
        // 6..<8 and 2..<4: four paused seconds. 10 - 4 = 6.
        let stream = makeStream(count: 10, pauses: .known(paused: [6..<8, 2..<4]))
        #expect(analyse(stream).time.timer == .available(6))
    }

    @Test func pausedSpansThatTouchPauseTheirWholeLength() {
        // 2..<4 and 4..<7: five paused seconds. 10 - 5 = 5.
        let stream = makeStream(count: 10, pauses: .known(paused: [2..<4, 4..<7]))
        #expect(analyse(stream).time.timer == .available(5))
    }

    @Test func anEmptyPausedSpanDoesNotBreakATimerSpan() {
        // 10..<10 pauses no second, so the 20 s of timer time are one
        // unbroken span and hold a 20 s power-curve window.
        let stream = makeStream(count: 20, pauses: .known(paused: [10..<10]), power: run(200, 20))
        #expect(analyse(stream).time.timer == .available(20))
        let curve = ActivityAnalysis.powerCurve(for: makeInput(stream), durations: [20])
        expectClose(curve[0].power, 200)
    }

    // MARK: A stream whose channels disagree with its length

    @Test func aChannelShorterThanTheStreamIsMissingPastItsEnd() {
        // A 10 s stream whose power channel has only 5 values.
        var stream = makeStream(count: 10)
        stream.power = Series(run(200, 5))
        #expect(stream.isConsistent == false)
        let metrics = analyse(stream, profile: makeProfile(thresholdPower: 200))
        // 5 of 10 timer seconds have power.
        expectClose(metrics.power.coverage, 0.5)
        expectClose(metrics.power.average, 200)
        // 200 W at a 200 W threshold is the fourth zone; 5 seconds missing.
        #expect(metrics.timeInPowerZones == .available(TimeInZones(seconds: [0, 0, 0, 5, 0, 0, 0], missing: 5)))
    }

    @Test func aChannelLongerThanTheStreamIsCutToItsLength() {
        // A 4 s stream whose power channel has 6 values: only the first four
        // are inside elapsed time. (100 + 100 + 100 + 100) / 4 = 100.
        var stream = makeStream(count: 4)
        stream.power = Series([100, 100, 100, 100, 900, 900])
        let metrics = analyse(stream)
        #expect(metrics.time.elapsed == .available(4))
        expectClose(metrics.power.average, 100)
        // 400 J = 0.4 kJ.
        expectWork(metrics.power.work, kilojoules: 0.4, isRecordedOnly: false)
    }

    // MARK: Power-curve durations that are not a duration

    @Test(arguments: [0, -1, -30])
    func aDurationBelowOneSecondHasNoWindow(duration: Int) {
        let stream = makeStream(count: 15, power: run(200, 15))
        let curve = ActivityAnalysis.powerCurve(for: makeInput(stream), durations: [duration])
        #expect(curve == [PowerCurvePoint(duration: duration, power: .unavailable(.noValidWindow))])
    }

    // MARK: Stated metadata that contradicts itself

    @Test func aStatedEndBeforeTheStatedStartStatesNoElapsedTime() {
        // End minus start would be -60 s, which is not a time.
        let stated = StatedSummary(start: testStart, end: testStart.addingTimeInterval(-60), timerTime: 50)
        let metrics = ActivityAnalysis.metrics(for: ActivityInput(
            sport: .cycling, recording: .summaryOnly(stated), activityDate: testStart
        ))
        #expect(metrics.time.elapsed == .unavailable(.notStated))
        #expect(metrics.time.timer == .available(50))
    }

    @Test func aStatedEndEqualToTheStatedStartIsZeroElapsedTime() {
        let stated = StatedSummary(start: testStart, end: testStart)
        let metrics = ActivityAnalysis.metrics(for: ActivityInput(
            sport: .cycling, recording: .summaryOnly(stated), activityDate: testStart
        ))
        #expect(metrics.time.elapsed == .available(0))
    }
}
