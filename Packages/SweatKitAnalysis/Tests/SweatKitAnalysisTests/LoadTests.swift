import Foundation
import SweatKitModel
import Testing
@testable import SweatKitAnalysis

/// The spec's "Which load an activity gets", one step of the fall-through at
/// a time.
///
/// Heart rate is 150 against a threshold of 200 throughout, so each second
/// scores 0.75^2 = 0.5625 and load from heart rate is
/// seconds x 0.5625 / 3600 x 100.
@Suite struct LoadFallThroughTests {
    private let profile = makeProfile(thresholdPower: 200, thresholdHeartRate: 200)
    private let heartRateOnly = makeProfile(thresholdHeartRate: 200)

    private func heartRateLoad(seconds: Double) -> Double {
        seconds * 0.5625 / 3600 * 100
    }

    private func expectLoad(
        _ metrics: ActivityMetrics,
        _ value: Double,
        from source: LoadSource,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        guard let load = metrics.load.value else {
            Issue.record(
                "Expected a load of \(value), but it is unavailable: \(metrics.load.reason?.rawValue ?? "no reason")",
                sourceLocation: sourceLocation
            )
            return
        }
        #expect(load.source == source, sourceLocation: sourceLocation)
        #expect(abs(load.value - value) <= 1e-6, "\(load.value) is not \(value)", sourceLocation: sourceLocation)
    }

    // MARK: 1. Load from power, when intensity is available

    @Test func aRideWithIntensityGetsLoadFromPower() {
        // 300 s at 200 W with a 200 W threshold: intensity 1.
        // (300 / 3600) x 1 x 100 = 8.3333. Heart rate would give
        // 300 x 0.5625 / 3600 x 100 = 4.6875, and is not used.
        let stream = makeStream(count: 300, power: run(200, 300), heartRate: run(150, 300))
        let metrics = analyse(stream, profile: profile)
        expectLoad(metrics, 300.0 / 3600.0 * 100, from: .power)
        expectClose(metrics.heartRate.load, 4.6875)
        #expect(metrics.promptsForThresholdPower == false)
    }

    @Test func loadFromPowerDoesNotNeedHeartRate() {
        let stream = makeStream(count: 300, power: run(200, 300))
        expectLoad(analyse(stream, profile: profile), 300.0 / 3600.0 * 100, from: .power)
    }

    // MARK: 2. Otherwise load from heart rate

    @Test func aRideWithSparsePowerFallsThroughToHeartRate() {
        // 23 s of power then 7 missing, repeated 14 times over 420 s: no
        // 30-second window is valid (see WeightedPowerTests), so there is no
        // intensity. Heart rate: 420 x 0.5625 / 3600 x 100 = 6.5625.
        let pattern = run(200, 23) + run(nil, 7)
        let power = Array(repeating: pattern, count: 14).flatMap { $0 }
        let stream = makeStream(count: 420, power: power, heartRate: run(150, 420))
        let metrics = analyse(stream, profile: profile)
        #expect(metrics.power.load == .unavailable(.tooFewValidWindows))
        expectLoad(metrics, 6.5625, from: .heartRate)
        #expect(metrics.promptsForThresholdPower == false)
    }

    @Test func aRideUnderFiveMinutesFallsThroughToHeartRate() {
        // 299 s of power is one second short of 5 minutes.
        // Heart rate: 299 x 0.5625 / 3600 x 100 = 4.671875.
        let stream = makeStream(count: 299, power: run(200, 299), heartRate: run(150, 299))
        let metrics = analyse(stream, profile: profile)
        #expect(metrics.power.load == .unavailable(.tooLittlePower))
        expectLoad(metrics, 4.671875, from: .heartRate)
        #expect(metrics.promptsForThresholdPower == false)
    }

    @Test func aRideWithNoThresholdPowerFallsThroughToHeartRateAndPrompts() {
        // Weighted power is available, but there is no threshold to divide
        // by. Heart rate: 300 x 0.5625 / 3600 x 100 = 4.6875.
        let stream = makeStream(count: 300, power: run(200, 300), heartRate: run(150, 300))
        let metrics = analyse(stream, profile: heartRateOnly)
        #expect(metrics.power.load == .unavailable(.noThresholdPower))
        expectLoad(metrics, 4.6875, from: .heartRate)
        #expect(metrics.promptsForThresholdPower)
    }

    @Test func aRideWithoutAPowerMeterGetsLoadFromHeartRateWithoutAPrompt() {
        // No power, so a threshold power would change nothing.
        let stream = makeStream(count: 300, heartRate: run(150, 300))
        let metrics = analyse(stream, profile: heartRateOnly)
        expectLoad(metrics, 4.6875, from: .heartRate)
        #expect(metrics.promptsForThresholdPower == false)
    }

    @Test func anActivityOnFootGetsLoadFromHeartRateEvenWithPower() {
        // Power is cycling only, so a run with a power channel and a
        // threshold power set still has no intensity.
        let stream = makeStream(count: 300, power: run(200, 300), heartRate: run(150, 300))
        let metrics = analyse(stream, sport: .running, profile: profile)
        expectLoad(metrics, 4.6875, from: .heartRate)
    }

    // MARK: 3. Otherwise unavailable, never estimated

    @Test func noIntensityAndNoHeartRateLeavesLoadUnavailable() {
        // A ride under 5 minutes with no heart rate.
        let stream = makeStream(count: 120, power: run(200, 120))
        let metrics = analyse(stream, profile: profile)
        #expect(metrics.load == .unavailable(.noHeartRate))
    }

    @Test func loadIsNeverEstimatedFromPartialHeartRate() {
        // No power, and heart rate for 80 of 100 seconds: under 90% coverage.
        let stream = makeStream(count: 100, heartRate: run(150, 80) + run(nil, 20))
        let metrics = analyse(stream, profile: heartRateOnly)
        #expect(metrics.load == .unavailable(.lowHeartRateCoverage))
    }

    @Test func aRideWithNoThresholdsAtAllHasNoLoadAndPrompts() {
        // Weighted power is available and no threshold power is set, so the
        // prompt still applies. Load from heart rate lacks its own threshold.
        let stream = makeStream(count: 300, power: run(200, 300), heartRate: run(150, 300))
        let metrics = analyse(stream)
        #expect(metrics.load == .unavailable(.noThresholdHeartRate))
        #expect(metrics.promptsForThresholdPower)
    }
}
