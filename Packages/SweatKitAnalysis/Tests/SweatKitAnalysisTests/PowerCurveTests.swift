import Foundation
import SweatKitModel
import Testing
@testable import SweatKitAnalysis

/// "Power curve: best mean over the valid windows of each duration", and the
/// window rule: "A power-curve window is valid when it sits inside one
/// unbroken timer span and at least 95% of its seconds have power. A window
/// shorter than 20 seconds must be complete."
@Suite struct PowerCurveTests {
    private func curve(_ stream: AnalysisStream, _ durations: [Int]) -> [Metric<Double>] {
        ActivityAnalysis.powerCurve(for: makeInput(stream), durations: durations).map(\.power)
    }

    private func best(_ stream: AnalysisStream, _ duration: Int) -> Metric<Double> {
        curve(stream, [duration])[0]
    }

    // MARK: Best mean

    @Test func eachDurationGetsItsBestWindow() {
        // 5 s at 100 W, 5 s at 400 W, 5 s at 100 W.
        //   1 s: one 400 W sample                                -> 400
        //   5 s: the five 400 W samples                          -> 400
        //  10 s: every window holds at most the five 400 W
        //        samples and five 100 W: (2000 + 500) / 10       -> 250
        //  15 s: the whole ride: (500 + 2000 + 500) / 15         -> 200
        let stream = makeStream(count: 15, power: run(100, 5) + run(400, 5) + run(100, 5))
        let points = curve(stream, [1, 5, 10, 15])
        expectClose(points[0], 400)
        expectClose(points[1], 400)
        expectClose(points[2], 250)
        expectClose(points[3], 200)
    }

    @Test func pointsComeBackInTheOrderAsked() {
        let stream = makeStream(count: 15, power: run(100, 5) + run(400, 5) + run(100, 5))
        let points = ActivityAnalysis.powerCurve(for: makeInput(stream), durations: [15, 1])
        #expect(points.map(\.duration) == [15, 1])
        expectClose(points[0].power, 200)
        expectClose(points[1].power, 400)
    }

    @Test func noDurationsGiveNoPoints() {
        let stream = makeStream(count: 15, power: run(200, 15))
        #expect(ActivityAnalysis.powerCurve(for: makeInput(stream), durations: []).isEmpty)
    }

    @Test func aDurationLongerThanTheRideHasNoWindow() {
        // "At least one valid window of that duration exists": 15 s of ride
        // has a 15 s window and no 16 s window.
        let stream = makeStream(count: 15, power: run(200, 15))
        expectClose(best(stream, 15), 200)
        #expect(best(stream, 16) == .unavailable(.noValidWindow))
    }

    @Test func thePowerCurveIsUnavailableWithoutPower() {
        let stream = makeStream(count: 60, heartRate: run(150, 60))
        #expect(best(stream, 5) == .unavailable(.noPower))
    }

    // MARK: Inside one unbroken timer span

    @Test func aWindowCannotStraddleAPause() {
        // 10 s at 300 W, 5 s paused, 10 s at 100 W. Each timer span is 10 s
        // long, so the best 10 s is the first span, and no 11 s window sits
        // inside one span even though timer time is 20 s.
        let stream = makeStream(
            count: 25,
            pauses: .known(paused: [10..<15]),
            power: run(300, 10) + run(nil, 5) + run(100, 10)
        )
        expectClose(best(stream, 10), 300)
        #expect(best(stream, 11) == .unavailable(.noValidWindow))
    }

    @Test func powerInsideAPausedSpanIsNotOnTheCurve() {
        // The meter reports 900 W through the pause. The best 5 s of timer
        // time is 100 W.
        let stream = makeStream(
            count: 25,
            pauses: .known(paused: [10..<15]),
            power: run(100, 10) + run(900, 5) + run(100, 10)
        )
        expectClose(best(stream, 5), 100)
    }

    // MARK: At least 95% of its seconds have power

    @Test func aTwentySecondWindowWithNineteenSecondsOfPowerIsValid() {
        // 19 of 20 is exactly 95%. The mean is over the 19 present seconds:
        // 19 x 200 / 19 = 200 W. Counting the missing second as zero would
        // give 190 W.
        let stream = makeStream(count: 20, power: run(200, 19) + run(nil, 1))
        expectClose(best(stream, 20), 200)
    }

    @Test func aTwentySecondWindowWithEighteenSecondsOfPowerIsInvalid() {
        // 18 of 20 is 90%.
        let stream = makeStream(count: 20, power: run(200, 18) + run(nil, 2))
        #expect(best(stream, 20) == .unavailable(.noValidWindow))
    }

    @Test func aFortySecondWindowNeedsThirtyEightSecondsOfPower() {
        // 38 of 40 is exactly 95%: valid. 37 of 40 is 92.5%: invalid.
        let valid = makeStream(count: 40, power: run(200, 38) + run(nil, 2))
        expectClose(best(valid, 40), 200)
        let invalid = makeStream(count: 40, power: run(200, 37) + run(nil, 3))
        #expect(best(invalid, 40) == .unavailable(.noValidWindow))
    }

    @Test func aTwentyOneSecondWindowNeedsTwentySecondsOfPower() {
        // 95% of 21 is 19.95, so 20 of 21 (95.2%) is valid and 19 of 21
        // (90.5%) is not.
        let valid = makeStream(count: 21, power: run(200, 20) + run(nil, 1))
        expectClose(best(valid, 21), 200)
        let invalid = makeStream(count: 21, power: run(200, 19) + run(nil, 2))
        #expect(best(invalid, 21) == .unavailable(.noValidWindow))
    }

    @Test func theBestIsTakenOverValidWindowsOnly() {
        // 22 s: three missing seconds, one at 900 W, eighteen at 100 W.
        // 20 s windows:
        //   0...19 holds 3 missing seconds, 17 of 20 present: invalid
        //   1...20 holds 2 missing seconds, 18 of 20 present: invalid
        //   2...21 holds 1 missing second, 19 of 20 present: valid,
        //          mean (900 + 18 x 100) / 19 = 2700 / 19, about 142.1 W
        let stream = makeStream(count: 22, power: run(nil, 3) + run(900, 1) + run(100, 18))
        expectClose(best(stream, 20), 2700.0 / 19.0)
    }

    // MARK: A window shorter than 20 seconds must be complete

    @Test func aWindowUnderTwentySecondsWithAMissingSecondIsInvalid() {
        // 18 of 19 present, and 9 of 10 present.
        let nineteen = makeStream(count: 19, power: run(200, 18) + run(nil, 1))
        #expect(best(nineteen, 19) == .unavailable(.noValidWindow))
        let ten = makeStream(count: 10, power: run(200, 9) + run(nil, 1))
        #expect(best(ten, 10) == .unavailable(.noValidWindow))
    }

    @Test func aCompleteWindowUnderTwentySecondsIsValid() {
        // The first 9 s are complete, so the 9 s point exists even though
        // the 10 s point does not.
        let stream = makeStream(count: 10, power: run(200, 9) + run(nil, 1))
        expectClose(best(stream, 9), 200)
    }

    @Test func aShortWindowSkipsPastADropoutToACompleteStretch() {
        // 400 W for 4 s, one missing second, 150 W for 5 s. A 5 s window
        // must be complete, so the only valid one is the 150 W stretch. The
        // four 400 W seconds are on the curve at 4 s but not at 5 s.
        let stream = makeStream(count: 10, power: run(400, 4) + run(nil, 1) + run(150, 5))
        expectClose(best(stream, 4), 400)
        expectClose(best(stream, 5), 150)
    }
}
