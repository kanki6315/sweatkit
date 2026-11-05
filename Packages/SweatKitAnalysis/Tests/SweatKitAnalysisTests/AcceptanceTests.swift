import Foundation
import SweatKitModel
import Testing
@testable import SweatKitAnalysis

/// The cases in the spec's "Acceptance" list that apply to a stream, each as
/// one whole activity. Pauses, unknown pause positions and an activity with
/// no stream have their own files.
@Suite struct AcceptanceTests {
    private let profile = makeProfile(thresholdPower: 200, thresholdHeartRate: 200)

    // MARK: A short activity

    @Test func aShortRideHasItsSimpleMetricsAndNoWeightedPower() {
        // 120 s at 200 W and a heart rate of 150.
        let stream = makeStream(count: 120, power: run(200, 120), heartRate: run(150, 120))
        let metrics = analyse(stream, profile: profile)
        #expect(metrics.time.timer == .available(120))
        expectClose(metrics.power.coverage, 1)
        expectClose(metrics.power.average, 200)
        // 200 W x 120 s = 24,000 J = 24 kJ.
        expectWork(metrics.power.work, kilojoules: 24, isRecordedOnly: false)
        // Under 5 minutes of power.
        #expect(metrics.power.weighted == .unavailable(.tooLittlePower))
        #expect(metrics.power.intensity == .unavailable(.tooLittlePower))
        #expect(metrics.power.variability == .unavailable(.tooLittlePower))
        // Load falls through to heart rate: 120 x 0.75^2 / 3600 x 100 = 1.875.
        #expect(metrics.load.value?.source == .heartRate)
        expectClose(metrics.heartRate.load, 1.875)
    }

    @Test func aShortRideStillHasAPowerCurveUpToItsLength() {
        let stream = makeStream(count: 120, power: run(200, 120))
        let curve = ActivityAnalysis.powerCurve(for: makeInput(stream), durations: [5, 60, 120, 300])
        expectClose(curve[0].power, 200)
        expectClose(curve[1].power, 200)
        expectClose(curve[2].power, 200)
        #expect(curve[3].power == .unavailable(.noValidWindow))
    }

    // MARK: An activity of exactly 30 seconds

    @Test func atThirtySecondsTheFirstThirtySecondWindowIsComplete() {
        // "The first window is samples 0 to 29, and it is complete at a
        // timer time of 30 seconds." Power rises 10 W a second from 10 W to
        // 300 W: the one window's mean is (10 + 300) / 2 = 155 W.
        let power = (1...30).map { Optional(Double($0) * 10) }
        let stream = makeStream(count: 30, power: power)
        let curve = ActivityAnalysis.powerCurve(for: makeInput(stream), durations: [30, 31])
        expectClose(curve[0].power, 155)
        #expect(curve[1].power == .unavailable(.noValidWindow))
    }

    @Test func atTwentyNineSecondsThereIsNoThirtySecondWindow() {
        let stream = makeStream(count: 29, power: run(200, 29))
        let curve = ActivityAnalysis.powerCurve(for: makeInput(stream), durations: [29, 30])
        expectClose(curve[0].power, 200)
        #expect(curve[1].power == .unavailable(.noValidWindow))
    }

    @Test func aThirtySecondRideHasTimesAverageAndWorkButNoWeightedPower() {
        // 30 s at 250 W. One possible window, and it is valid, but 30 s of
        // power is under 5 minutes.
        let stream = makeStream(count: 30, power: run(250, 30), heartRate: run(200, 30))
        let metrics = analyse(stream, profile: profile)
        #expect(metrics.time.elapsed == .available(30))
        #expect(metrics.time.timer == .available(30))
        expectClose(metrics.power.average, 250)
        // 250 W x 30 s = 7,500 J = 7.5 kJ.
        expectWork(metrics.power.work, kilojoules: 7.5, isRecordedOnly: false)
        #expect(metrics.power.weighted == .unavailable(.tooLittlePower))
        // Heart rate at threshold for 30 s: 30 / 3600 x 100 = 0.8333.
        #expect(metrics.load.value?.source == .heartRate)
        expectClose(metrics.heartRate.load, 30.0 / 3600.0 * 100)
    }

    // MARK: An indoor ride without speed

    @Test func anIndoorRideWithoutSpeedMovesForItsWholeTimerTime() {
        // 300 s on a trainer with a 60 s pause: power and heart rate only.
        // Timer 360 - 60 = 300 s, and moving time equals it.
        let stream = makeStream(
            count: 360,
            pauses: .known(paused: [100..<160]),
            power: run(200, 100) + run(nil, 60) + run(200, 200),
            heartRate: run(150, 360)
        )
        let metrics = analyse(stream, indoor: true, profile: profile)
        #expect(metrics.time.elapsed == .available(360))
        #expect(metrics.time.timer == .available(300))
        #expect(metrics.time.moving == .available(300))
        // The metrics that need position are unavailable, not zero.
        #expect(metrics.distance == .unavailable(.noDistance))
        #expect(metrics.ascent == .unavailable(.noAltitude))
        #expect(metrics.descent == .unavailable(.noAltitude))
        #expect(metrics.timeInGradientBands == .unavailable(.noGradient))
        // Power is whole: 300 timer seconds at 200 W, threshold 200 W.
        expectClose(metrics.power.coverage, 1)
        expectClose(metrics.power.weighted, 200, tolerance: 1e-6)
        expectClose(metrics.power.intensity, 1, tolerance: 1e-6)
        // (300 / 3600) x 1 x 100 = 8.3333.
        #expect(metrics.load.value?.source == .power)
        expectClose(metrics.power.load, 300.0 / 3600.0 * 100, tolerance: 1e-6)
    }

    // MARK: Sensor dropouts

    @Test func aDropoutAffectsOnlyItsOwnChannel() {
        // 100 s with the heart-rate strap silent for seconds 40..<60. Power
        // is whole throughout.
        let stream = makeStream(
            count: 100,
            power: run(200, 100),
            heartRate: run(150, 40) + run(nil, 20) + run(150, 40)
        )
        let metrics = analyse(stream, profile: profile)
        #expect(metrics.time.timer == .available(100))
        expectClose(metrics.power.coverage, 1)
        expectClose(metrics.power.average, 200)
        // 80 of 100 seconds have heart rate.
        expectClose(metrics.heartRate.coverage, 0.8)
        // The average is over the 80 seconds that have it: 150, not 120.
        expectClose(metrics.heartRate.average, 150)
        // The 20 silent seconds are their own bucket. 150 / 200 = 75%, the
        // first heart-rate zone.
        #expect(metrics.timeInHeartRateZones == .available(TimeInZones(seconds: [80, 0, 0, 0, 0], missing: 20)))
    }

    // MARK: Sparse power

    @Test func aRideWithSparsePowerKeepsItsAverageAndFlagsItsCoverage() {
        // 600 s with power for the first 60 s only, heart rate throughout.
        let stream = makeStream(
            count: 600,
            power: run(200, 60) + run(nil, 540),
            heartRate: run(150, 600)
        )
        let metrics = analyse(stream, profile: profile)
        // 60 of 600 seconds: 10%.
        expectClose(metrics.power.coverage, 0.1)
        // Over the seconds that have power: 200 W, with coverage beside it.
        expectClose(metrics.power.average, 200)
        #expect(metrics.power.averageShowsCoverage)
        // 200 W x 60 s = 12 kJ, labelled recorded work.
        expectWork(metrics.power.work, kilojoules: 12, isRecordedOnly: true)
        // 60 s of power is under 5 minutes.
        #expect(metrics.power.weighted == .unavailable(.tooLittlePower))
        // Load from heart rate: 600 x 0.75^2 / 3600 x 100 = 9.375.
        #expect(metrics.load.value?.source == .heartRate)
        expectClose(metrics.heartRate.load, 9.375)
        // The 540 seconds without power are missing, not the lowest zone.
        // 200 W at a 200 W threshold is the fourth zone.
        #expect(metrics.timeInPowerZones == .available(TimeInZones(seconds: [0, 0, 0, 60, 0, 0, 0], missing: 540)))
    }

    // MARK: Pauses

    @Test func aPausedRideKeepsElapsedTimeAndShortensTimerTime() {
        // 150 s riding at 8 m/s, a 100 s stop, 150 s riding. Speed reads 0
        // through the stop and power is not recorded.
        let stream = makeStream(
            count: 400,
            pauses: .known(paused: [150..<250]),
            power: run(200, 150) + run(nil, 100) + run(200, 150),
            heartRate: run(150, 400),
            speed: run(8, 150) + run(0, 100) + run(8, 150)
        )
        let metrics = analyse(stream, profile: profile)
        #expect(metrics.time.elapsed == .available(400))
        // 400 - 100 = 300.
        #expect(metrics.time.timer == .available(300))
        // No timer second is below 1 m/s; the stopped seconds are paused.
        #expect(metrics.time.moving == .available(300))
        // All 300 timer seconds have power.
        expectClose(metrics.power.coverage, 1)
        expectClose(metrics.power.weighted, 200, tolerance: 1e-6)
        // (300 / 3600) x (200 / 200)^2 x 100 = 8.3333.
        expectClose(metrics.power.load, 300.0 / 3600.0 * 100, tolerance: 1e-6)
        // Heart-rate load is summed over the 300 timer seconds only:
        // 300 x 0.75^2 / 3600 x 100 = 4.6875.
        expectClose(metrics.heartRate.load, 4.6875)
    }
}
