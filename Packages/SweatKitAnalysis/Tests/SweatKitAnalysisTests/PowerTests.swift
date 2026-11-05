import Foundation
import SweatKitModel
import Testing
@testable import SweatKitAnalysis

/// The spec's "Power, cycling only" table, apart from weighted power's
/// window rules and the power curve, which have their own files.
@Suite struct PowerCoverageTests {
    @Test func coverageIsTheShareOfTimerSecondsWithPower() {
        // 8 of 10 seconds have power: 0.8.
        let stream = makeStream(count: 10, power: run(200, 8) + run(nil, 2))
        expectClose(analyse(stream).power.coverage, 0.8)
    }

    @Test func interpolatedPowerCountsTowardsCoverage() {
        // Two measured, one interpolated, one missing: 3 of 4 = 0.75.
        var stream = makeStream(count: 4)
        stream.power = Series(
            values: [200, 200, 200, 0],
            quality: [.measured, .measured, .interpolated, .missing]
        )
        expectClose(analyse(stream).power.coverage, 0.75)
    }

    @Test func aRecordedZeroCountsTowardsCoverage() {
        // 0 W while coasting is measured, not missing: 4 of 4.
        let stream = makeStream(count: 4, power: [200, 0, 0, 200])
        expectClose(analyse(stream).power.coverage, 1)
    }

    @Test func coverageIsMeasuredAgainstTimerSecondsNotElapsed() {
        // Paused 0..<5 with no power there. Timer seconds are 5..<10, and 4
        // of those 5 have power: 0.8, not 4 of 10.
        let stream = makeStream(
            count: 10,
            pauses: .known(paused: [0..<5]),
            power: run(nil, 5) + run(200, 4) + run(nil, 1)
        )
        expectClose(analyse(stream).power.coverage, 0.8)
    }

    @Test func powerInsideAPausedSpanDoesNotCountTowardsCoverage() {
        // Paused 0..<5, where the meter kept reporting. Of the 5 timer
        // seconds, 3 have power: 0.6, not 8 of 10.
        let stream = makeStream(
            count: 10,
            pauses: .known(paused: [0..<5]),
            power: run(200, 5) + run(200, 3) + run(nil, 2)
        )
        expectClose(analyse(stream).power.coverage, 0.6)
    }

    @Test func coverageOfARideWithNoPowerIsZero() {
        // 0 of 10 seconds have power. That is a true zero, not an unknown.
        let stream = makeStream(count: 10, heartRate: run(150, 10))
        #expect(analyse(stream).power.coverage == .available(0))
    }

    @Test func coverageIsUnavailableWhenTimerTimeIsZero() {
        // The whole recording is paused, so the share has no denominator.
        let stream = makeStream(count: 5, pauses: .known(paused: [0..<5]), power: run(200, 5))
        #expect(analyse(stream).power.coverage == .unavailable(.zeroDenominator))
    }
}

@Suite struct AveragePowerAndWorkTests {
    @Test func averagePowerIncludesZerosAndLeavesOutMissingSeconds() {
        // (100 + 200 + 0 + 300) / 4 = 150. Counting the missing second as
        // zero would give 120, and dropping the recorded 0 would give 200.
        let stream = makeStream(count: 5, power: [100, 200, nil, 0, 300])
        expectClose(analyse(stream).power.average, 150)
    }

    @Test func averagePowerOfARideThatOnlyCoastedIsZero() {
        // Power exists, and all of it is 0 W: the average is a true zero.
        let stream = makeStream(count: 3, power: [0, 0, 0])
        #expect(analyse(stream).power.average == .available(0))
    }

    @Test func averagePowerIsUnavailableWithoutPower() {
        let stream = makeStream(count: 10, heartRate: run(150, 10))
        #expect(analyse(stream).power.average == .unavailable(.noPower))
    }

    @Test func averagePowerCountsEverySecondThatHasPowerEvenWhilePaused() {
        // The spec divides by "the number of seconds that have power" and
        // does not leave paused seconds out. Paused 2..<4:
        // (100 + 100 + 300 + 300) / 4 = 200.
        let stream = makeStream(count: 4, pauses: .known(paused: [2..<4]), power: [100, 100, 300, 300])
        expectClose(analyse(stream).power.average, 200)
    }

    @Test func coverageIsShownBesideAveragePowerOnlyUnderNinetyPercent() {
        // 8 of 10 = 80%: shown.
        #expect(analyse(makeStream(count: 10, power: run(200, 8) + run(nil, 2))).power.averageShowsCoverage)
        // 9 of 10 = exactly 90%, which is not under 90%: not shown.
        #expect(!analyse(makeStream(count: 10, power: run(200, 9) + run(nil, 1))).power.averageShowsCoverage)
        // 10 of 10: not shown.
        #expect(!analyse(makeStream(count: 10, power: run(200, 10))).power.averageShowsCoverage)
    }

    @Test func workIsTheSumOfPowerInKilojoules() {
        // 250 W for 100 s = 25,000 J = 25 kJ. Full coverage: plain "work".
        let stream = makeStream(count: 100, power: run(250, 100))
        expectWork(analyse(stream).power.work, kilojoules: 25, isRecordedOnly: false)
    }

    @Test func workSumsOnlyTheSecondsThatHavePower() {
        // 100 + 200 + 0 + 300 = 600 J = 0.6 kJ. 4 of 5 seconds is 80% coverage.
        let stream = makeStream(count: 5, power: [100, 200, nil, 0, 300])
        expectWork(analyse(stream).power.work, kilojoules: 0.6, isRecordedOnly: true)
    }

    @Test func workIsLabelledRecordedOnlyWhenCoverageIsUnderNinetyEightPercent() {
        // 49 of 50 = exactly 98%, which is not under 98%: plain work.
        // 200 W x 49 s = 9,800 J = 9.8 kJ.
        let onTheEdge = makeStream(count: 50, power: run(200, 49) + run(nil, 1))
        expectWork(analyse(onTheEdge).power.work, kilojoules: 9.8, isRecordedOnly: false)
        // 97 of 100 = 97%: recorded work. 200 W x 97 s = 19,400 J = 19.4 kJ.
        let under = makeStream(count: 100, power: run(200, 97) + run(nil, 3))
        expectWork(analyse(under).power.work, kilojoules: 19.4, isRecordedOnly: true)
    }

    @Test func workIsUnavailableWithoutPower() {
        let stream = makeStream(count: 10, heartRate: run(150, 10))
        #expect(analyse(stream).power.work == .unavailable(.noPower))
    }
}

@Suite struct CyclingOnlyTests {
    @Test(arguments: [Sport.walking, .running, .hiking, .other])
    func everyPowerMetricIsUnavailableOffABike(sport: Sport) {
        // A full 300 s of power with a threshold set: on a bike all of these
        // would be available.
        let stream = makeStream(count: 300, power: run(200, 300))
        let power = analyse(stream, sport: sport, profile: makeProfile(thresholdPower: 200)).power
        #expect(power.coverage == .unavailable(.notDefinedForSport))
        #expect(power.average == .unavailable(.notDefinedForSport))
        #expect(power.averageShowsCoverage == false)
        #expect(power.weighted == .unavailable(.notDefinedForSport))
        #expect(power.intensity == .unavailable(.notDefinedForSport))
        #expect(power.load == .unavailable(.notDefinedForSport))
        #expect(power.variability == .unavailable(.notDefinedForSport))
        #expect(power.work == .unavailable(.notDefinedForSport))
    }

    @Test func thePowerCurveIsUnavailableOffABike() {
        let input = makeInput(makeStream(count: 300, power: run(200, 300)), sport: .running)
        let curve = ActivityAnalysis.powerCurve(for: input, durations: [5])
        #expect(curve == [PowerCurvePoint(duration: 5, power: .unavailable(.notDefinedForSport))])
    }

    @Test func aRideOffTheBikeDoesNotPromptForAThresholdPower() {
        let stream = makeStream(count: 300, power: run(200, 300))
        #expect(analyse(stream, sport: .running).promptsForThresholdPower == false)
    }
}

/// Intensity, load from power and variability, on rides whose weighted power
/// is plain to see: 300 s at a constant power has a weighted power of that
/// power, because every 30-second window has the same mean.
@Suite struct IntensityLoadAndVariabilityTests {
    private let steady = makeStream(count: 300, power: run(200, 300))

    @Test func intensityIsWeightedPowerOverThresholdPower() {
        // 200 W / 250 W = 0.8.
        let metrics = analyse(steady, profile: makeProfile(thresholdPower: 250))
        expectClose(metrics.power.intensity, 0.8)
    }

    @Test func intensityUsesTheThresholdInEffectOnTheActivityDate() {
        // 200 W from the epoch, 250 W from the day after the activity:
        // 200 / 200 = 1.0, not 0.8.
        let history = [
            AthleteProfile.ThresholdPower(effectiveFrom: Date(timeIntervalSince1970: 0), watts: 200),
            AthleteProfile.ThresholdPower(effectiveFrom: testStart.addingTimeInterval(86_400), watts: 250),
        ]
        let metrics = analyse(steady, profile: AthleteProfile(thresholdPowerHistory: history))
        expectClose(metrics.power.intensity, 1.0)
    }

    @Test func intensityIsUnavailableWithoutAThresholdPower() {
        let metrics = analyse(steady)
        expectClose(metrics.power.weighted, 200)
        #expect(metrics.power.intensity == .unavailable(.noThresholdPower))
        #expect(metrics.power.load == .unavailable(.noThresholdPower))
    }

    @Test func intensityIsUnavailableForAThresholdOfZero() {
        // "A metric whose denominator is zero or missing is unavailable."
        let metrics = analyse(steady, profile: makeProfile(thresholdPower: 0))
        #expect(metrics.power.intensity == .unavailable(.zeroDenominator))
        #expect(metrics.power.load == .unavailable(.zeroDenominator))
    }

    @Test func intensityCarriesTheReasonWeightedPowerIsUnavailable() {
        // 100 s of power is under 5 minutes.
        let short = makeStream(count: 100, power: run(200, 100))
        let metrics = analyse(short, profile: makeProfile(thresholdPower: 250))
        #expect(metrics.power.intensity == .unavailable(.tooLittlePower))
        #expect(metrics.power.load == .unavailable(.tooLittlePower))
        #expect(metrics.power.variability == .unavailable(.tooLittlePower))
    }

    @Test func loadFromPowerIsTimerHoursTimesIntensitySquaredTimesOneHundred() {
        // Timer 300 s = 1/12 h. Intensity 200 / 250 = 0.8, squared 0.64.
        // (1/12) x 0.64 x 100 = 5.3333...
        let metrics = analyse(steady, profile: makeProfile(thresholdPower: 250))
        expectClose(metrics.power.load, 300.0 / 3600.0 * 0.64 * 100)
    }

    @Test func loadFromPowerUsesTimerHoursNotElapsedHours() {
        // 150 s riding, 300 s paused, 150 s riding. Timer 300 s, elapsed 600 s.
        // Intensity 200 / 200 = 1. (300 / 3600) x 1 x 100 = 8.3333...
        // Elapsed hours would give 16.67.
        let stream = makeStream(
            count: 600,
            pauses: .known(paused: [150..<450]),
            power: run(200, 150) + run(nil, 300) + run(200, 150)
        )
        let metrics = analyse(stream, profile: makeProfile(thresholdPower: 200))
        expectClose(metrics.power.load, 300.0 / 3600.0 * 100)
    }

    @Test func variabilityIsWeightedPowerOverAveragePower() {
        // 150 s at 100 W, a 7 s dropout, 150 s at 300 W. The weighted power
        // is the fourth root of 41 x 10^8 (worked in WeightedPowerTests).
        // Average power = (150 x 100 + 150 x 300) / 300 = 200 W.
        let stream = makeStream(count: 307, power: run(100, 150) + run(nil, 7) + run(300, 150))
        let metrics = analyse(stream)
        expectClose(metrics.power.average, 200)
        expectClose(metrics.power.variability, pow(41e8, 0.25) / 200, tolerance: 1e-6)
    }

    @Test func variabilityOfASteadyRideIsOne() {
        // Weighted 200 W over average 200 W.
        expectClose(analyse(steady).power.variability, 1)
    }

    @Test func variabilityIsUnavailableWhenAveragePowerIsZero() {
        // 300 s of recorded 0 W. Weighted power is a true 0 W and so is the
        // average, which leaves variability with a zero denominator.
        let coasting = makeStream(count: 300, power: run(0, 300))
        let metrics = analyse(coasting)
        #expect(metrics.power.weighted == .available(0))
        #expect(metrics.power.average == .available(0))
        #expect(metrics.power.variability == .unavailable(.zeroDenominator))
    }
}
