import Foundation
import SweatKitModel
import Testing
@testable import SweatKitAnalysis

/// Weighted power and the spec's "Window rules" for 30-second windows.
///
/// A stream of T timer seconds has T - 29 possible windows, starting at
/// seconds 0 to T - 30. The window starting at s covers samples s to s + 29.
@Suite struct WeightedPowerTests {
    // MARK: The formula

    @Test func weightedPowerOfASteadyRideIsThatPower() {
        // Every one of the 271 windows has a mean of 200 W, so the fourth
        // root of the mean fourth power is 200 W.
        let stream = makeStream(count: 300, power: run(200, 300))
        expectClose(analyse(stream).power.weighted, 200, tolerance: 1e-6)
    }

    @Test func weightedPowerTakesTheFourthRootOfTheMeanFourthPower() {
        // 150 s at 100 W, 7 s with no power (seconds 150 to 156), 150 s at
        // 300 W. T = 307, so 278 possible windows, starting at 0 to 277.
        //
        // A window is invalid with 7 or more missing seconds, so only when it
        // holds the whole dropout: s <= 150 and s + 29 >= 156, s = 127...150,
        // 24 windows. 254 of 278 are valid, 91.4%, which is at least 90%.
        // Power is present for 300 s, which is at least 5 minutes.
        //
        // Windows 0...126 hold only 100 W samples (window 126 covers 126 to
        // 155: 24 samples of 100 W and 6 missing, mean 100 W, not 80 W).
        // Windows 151...277 hold only 300 W samples. That is 127 of each.
        //
        // Mean fourth power = (127 x 100^4 + 127 x 300^4) / 254
        //                   = (10^8 + 81 x 10^8) / 2 = 41 x 10^8.
        // Weighted power = (41 x 10^8)^(1/4) = 100 x 41^(1/4), about 253.04 W.
        let stream = makeStream(count: 307, power: run(100, 150) + run(nil, 7) + run(300, 150))
        expectClose(analyse(stream).power.weighted, pow(41e8, 0.25), tolerance: 1e-6)
    }

    @Test func weightedPowerAveragesOverEveryWindowStart() {
        // 270 s at 0 W, then 30 s at 300 W. T = 300, so 271 windows, 0...270.
        // The window starting at s holds k = s - 240 samples of 300 W once
        // s >= 241, so its mean is 300k / 30 = 10k W. Windows 0...240 have a
        // mean of 0 W; windows 241...270 have k = 1...30.
        //
        // Sum of fourth powers = 10^4 x (1^4 + 2^4 + ... + 30^4).
        // Sum of k^4 to n = n(n+1)(2n+1)(3n^2+3n-1)/30
        //                 = 30 x 31 x 61 x 2789 / 30 = 5,273,999.
        // Weighted power = (10^4 x 5,273,999 / 271)^(1/4), about 118.1 W.
        let stream = makeStream(count: 300, power: run(0, 270) + run(300, 30))
        expectClose(analyse(stream).power.weighted, pow(1e4 * 5_273_999 / 271, 0.25), tolerance: 1e-6)
    }

    // MARK: Windows run over timer time

    @Test func pausedSpansAreRemovedAndTheSeriesJoined() {
        // 150 s riding, 100 s paused, 150 s riding, all at 200 W. Joined, the
        // series is 300 s at 200 W: 5 minutes of power and 271 valid windows.
        // Taken apart, neither 150 s span would reach 5 minutes.
        let stream = makeStream(
            count: 400,
            pauses: .known(paused: [150..<250]),
            power: run(200, 150) + run(nil, 100) + run(200, 150)
        )
        expectClose(analyse(stream).power.weighted, 200, tolerance: 1e-6)
    }

    @Test func windowsRunAcrossTheJoin() {
        // 270 s at 0 W, 60 s paused, 30 s at 300 W. With the pause removed
        // this is the series of weightedPowerAveragesOverEveryWindowStart,
        // and the 29 windows that straddle the join count like any other.
        let stream = makeStream(
            count: 360,
            pauses: .known(paused: [270..<330]),
            power: run(0, 270) + run(nil, 60) + run(300, 30)
        )
        expectClose(analyse(stream).power.weighted, pow(1e4 * 5_273_999 / 271, 0.25), tolerance: 1e-6)
    }

    @Test func powerInsideAPausedSpanIsNotRead() {
        // The meter reports 1000 W through a 50 s pause. Weighted power runs
        // over timer time only: 300 s at 200 W.
        let stream = makeStream(
            count: 350,
            pauses: .known(paused: [150..<200]),
            power: run(200, 150) + run(1000, 50) + run(200, 150)
        )
        expectClose(analyse(stream).power.weighted, 200, tolerance: 1e-6)
    }

    // MARK: At least 5 minutes of power

    @Test func exactlyFiveMinutesOfPowerIsEnough() {
        let stream = makeStream(count: 300, power: run(200, 300))
        #expect(analyse(stream).power.weighted.value != nil)
    }

    @Test func oneSecondUnderFiveMinutesIsNotEnough() {
        let stream = makeStream(count: 299, power: run(200, 299))
        #expect(analyse(stream).power.weighted == .unavailable(.tooLittlePower))
    }

    @Test func fiveMinutesMeansSecondsWithPowerNotTimerSeconds() {
        // Timer 310 s, but the first 11 s have no power: 299 s of power.
        // (Only windows 0...4 hold 7 or more missing seconds, so 276 of 281
        // windows are valid and the window rule is not what fails.)
        let stream = makeStream(count: 310, power: run(nil, 11) + run(200, 299))
        #expect(analyse(stream).power.weighted == .unavailable(.tooLittlePower))
    }

    @Test func fiveMinutesIsCountedOverTimerTimeOnly() {
        // 299 timer seconds with power, and a 50 s pause through which the
        // meter kept reporting. The paused seconds do not make up the 5 minutes.
        let stream = makeStream(
            count: 349,
            pauses: .known(paused: [150..<200]),
            power: run(200, 349)
        )
        #expect(analyse(stream).power.weighted == .unavailable(.tooLittlePower))
    }

    @Test func weightedPowerIsUnavailableWithoutPower() {
        let stream = makeStream(count: 600, heartRate: run(150, 600))
        #expect(analyse(stream).power.weighted == .unavailable(.noPower))
    }

    // MARK: A window is valid with at least 24 of its 30 seconds

    @Test func aWindowWithExactlyTwentyFourSecondsOfPowerIsValid() {
        // Four seconds of power then one missing, repeated 75 times: 375 s,
        // 300 of them with power. 5 divides 30, so every window of 30 holds
        // exactly 6 missing seconds and 24 present ones. Every window is
        // valid, and each has a mean of 200 W.
        let pattern = run(200, 4) + run(nil, 1)
        let power = Array(repeating: pattern, count: 75).flatMap { $0 }
        let stream = makeStream(count: 375, power: power)
        expectClose(analyse(stream).power.weighted, 200, tolerance: 1e-6)
    }

    @Test func aWindowWithTwentyThreeSecondsOfPowerIsInvalid() {
        // 23 seconds of power then 7 missing, repeated 14 times: 420 s, 322
        // of them with power, which is over 5 minutes. The pattern repeats
        // every 30 s, so every window of 30 holds exactly 23 present seconds.
        // No window is valid: 0% is under 90%.
        let pattern = run(200, 23) + run(nil, 7)
        let power = Array(repeating: pattern, count: 14).flatMap { $0 }
        let stream = makeStream(count: 420, power: power)
        #expect(analyse(stream).power.weighted == .unavailable(.tooFewValidWindows))
    }

    // MARK: At least 90% of the possible windows are valid

    @Test func exactlyNinetyPercentValidWindowsIsEnough() {
        // 329 s at 200 W with power missing for the 13 s from 150 to 162.
        // 300 possible windows, 0...299. A window has 7 or more missing
        // seconds when s + 29 >= 156 and s <= 156, s = 127...156: 30 windows.
        // 270 of 300 valid is exactly 90%. Power is present for 316 s.
        // Every valid window holds only 200 W samples.
        let stream = makeStream(count: 329, power: run(200, 150) + run(nil, 13) + run(200, 166))
        expectClose(analyse(stream).power.weighted, 200, tolerance: 1e-6)
    }

    @Test func justUnderNinetyPercentValidWindowsIsNotEnough() {
        // The same ride with one more missing second, 150 to 163. Windows
        // 127...157 are invalid: 31. 269 of 300 valid is 89.7%. Power is
        // present for 315 s, so the 5-minute rule is met.
        let stream = makeStream(count: 329, power: run(200, 150) + run(nil, 14) + run(200, 165))
        #expect(analyse(stream).power.weighted == .unavailable(.tooFewValidWindows))
    }
}
