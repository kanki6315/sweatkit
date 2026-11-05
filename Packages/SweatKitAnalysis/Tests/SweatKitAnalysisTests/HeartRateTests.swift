import Foundation
import SweatKitModel
import Testing
@testable import SweatKitAnalysis

/// The spec's "Heart rate" table, and average heart rate from the
/// availability table.
@Suite struct HeartRateTests {
    private let threshold200 = makeProfile(thresholdHeartRate: 200)

    // MARK: Coverage

    @Test func coverageIsTheShareOfTimerSecondsWithHeartRate() {
        // 9 of 10 seconds: 0.9.
        let stream = makeStream(count: 10, heartRate: run(150, 9) + run(nil, 1))
        expectClose(analyse(stream).heartRate.coverage, 0.9)
    }

    @Test func interpolatedHeartRateCountsTowardsCoverage() {
        // One measured, two interpolated, one missing: 3 of 4 = 0.75.
        var stream = makeStream(count: 4)
        stream.heartRate = Series(
            values: [150, 151, 152, 0],
            quality: [.measured, .interpolated, .interpolated, .missing]
        )
        expectClose(analyse(stream).heartRate.coverage, 0.75)
    }

    @Test func coverageIsMeasuredAgainstTimerSecondsNotElapsed() {
        // Paused 0..<10, where the strap kept reporting. Of the 10 timer
        // seconds, 5 have heart rate: 0.5, not 15 of 20.
        let stream = makeStream(
            count: 20,
            pauses: .known(paused: [0..<10]),
            heartRate: run(150, 15) + run(nil, 5)
        )
        expectClose(analyse(stream).heartRate.coverage, 0.5)
    }

    @Test func coverageIsUnavailableWhenTimerTimeIsZero() {
        let stream = makeStream(count: 5, pauses: .known(paused: [0..<5]), heartRate: run(150, 5))
        #expect(analyse(stream).heartRate.coverage == .unavailable(.zeroDenominator))
    }

    // MARK: Average

    @Test func averageHeartRateIsOverTheSecondsThatHaveIt() {
        // (120 + 140 + 160) / 3 = 140. Counting the gap as zero would give 105.
        let stream = makeStream(count: 4, heartRate: [120, nil, 140, 160])
        expectClose(analyse(stream).heartRate.average, 140)
    }

    @Test func averageHeartRateCountsEverySecondThatHasItEvenWhilePaused() {
        // The spec averages "over the seconds that have them" and does not
        // leave paused seconds out. Paused 2..<4:
        // (100 + 100 + 160 + 160) / 4 = 130.
        let stream = makeStream(count: 4, pauses: .known(paused: [2..<4]), heartRate: [100, 100, 160, 160])
        expectClose(analyse(stream).heartRate.average, 130)
    }

    @Test func averageHeartRateIsUnavailableWithoutHeartRate() {
        let stream = makeStream(count: 10, power: run(200, 10))
        #expect(analyse(stream).heartRate.average == .unavailable(.noHeartRate))
    }

    // MARK: Load

    @Test func oneHourAtThresholdIsOneHundred() {
        // The spec's own check: 3,600 s each scoring (160 / 160)^2 = 1.
        // 3600 / 3600 x 100 = 100.
        let stream = makeStream(count: 3600, heartRate: run(160, 3600))
        let metrics = analyse(stream, profile: makeProfile(thresholdHeartRate: 160))
        expectClose(metrics.heartRate.load, 100)
    }

    @Test func eachSecondScoresTheSquareOfItsShareOfThreshold() {
        // 10 s at 150 against a threshold of 200: each scores 0.75^2 = 0.5625.
        // 10 x 0.5625 = 5.625. 5.625 / 3600 x 100 = 0.15625.
        let stream = makeStream(count: 10, heartRate: run(150, 10))
        expectClose(analyse(stream, profile: threshold200).heartRate.load, 0.15625)
    }

    @Test func secondsAreScoredOneByOneNotFromTheAverage() {
        // 5 s at 100 and 5 s at 200, threshold 200.
        // Scores: 5 x 0.25 + 5 x 1 = 6.25. 6.25 / 3600 x 100 = 0.173611...
        // Scoring the average of 150 would give 0.15625.
        let stream = makeStream(count: 10, heartRate: run(100, 5) + run(200, 5))
        expectClose(analyse(stream, profile: threshold200).heartRate.load, 6.25 / 3600 * 100)
    }

    @Test func loadIsSummedOverTimerTimeOnly() {
        // 10 s running then 10 s paused, with heart rate at threshold
        // throughout. Only the 10 timer seconds score: 10 / 3600 x 100.
        let stream = makeStream(
            count: 20,
            pauses: .known(paused: [10..<20]),
            heartRate: run(200, 20)
        )
        expectClose(analyse(stream, profile: threshold200).heartRate.load, 10.0 / 3600.0 * 100)
    }

    @Test func coverageOfExactlyNinetyPercentIsEnoughAndGapsScoreNothing() {
        // 9 of 10 seconds at threshold: coverage is exactly 90%. The missing
        // second is not estimated: 9 / 3600 x 100 = 0.25.
        let stream = makeStream(count: 10, heartRate: run(200, 9) + run(nil, 1))
        expectClose(analyse(stream, profile: threshold200).heartRate.load, 0.25)
    }

    @Test func coverageUnderNinetyPercentMakesLoadUnavailable() {
        // 89 of 100 seconds: 89%.
        let stream = makeStream(count: 100, heartRate: run(200, 89) + run(nil, 11))
        #expect(analyse(stream, profile: threshold200).heartRate.load == .unavailable(.lowHeartRateCoverage))
    }

    @Test func loadIsUnavailableWithoutHeartRate() {
        let stream = makeStream(count: 10, power: run(200, 10))
        #expect(analyse(stream, profile: threshold200).heartRate.load == .unavailable(.noHeartRate))
    }

    @Test func loadIsUnavailableWithoutAThresholdOrMax() {
        // "A metric whose denominator is zero or missing is unavailable."
        let stream = makeStream(count: 10, heartRate: run(150, 10))
        #expect(analyse(stream).heartRate.load == .unavailable(.noThresholdHeartRate))
    }

    @Test func loadIsUnavailableForAThresholdOfZero() {
        let stream = makeStream(count: 10, heartRate: run(150, 10))
        let metrics = analyse(stream, profile: makeProfile(thresholdHeartRate: 0))
        #expect(metrics.heartRate.load == .unavailable(.zeroDenominator))
    }

    @Test func loadUsesNinetyPercentOfMaxUntilAThresholdIsSet() {
        // Max 200 gives a threshold of 180. 10 s at 180 each score 1:
        // 10 / 3600 x 100.
        let stream = makeStream(count: 10, heartRate: run(180, 10))
        let metrics = analyse(stream, profile: makeProfile(maxHeartRate: 200))
        expectClose(metrics.heartRate.load, 10.0 / 3600.0 * 100)
    }

    @Test(arguments: [Sport.cycling, .walking, .running, .hiking, .other])
    func heartRateMetricsAreForEverySport(sport: Sport) {
        // 10 s at threshold: coverage 1, average 200, load 10 / 3600 x 100.
        let stream = makeStream(count: 10, heartRate: run(200, 10))
        let heartRate = analyse(stream, sport: sport, profile: threshold200).heartRate
        expectClose(heartRate.coverage, 1)
        expectClose(heartRate.average, 200)
        expectClose(heartRate.load, 10.0 / 3600.0 * 100)
    }
}
