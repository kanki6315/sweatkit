import Foundation
import SweatKitModel
import Testing
@testable import SweatKitAnalysis

/// The spec's "When pause positions are unknown" table, row by row.
///
/// One 400-second activity with every channel present, whose pause data is
/// incomplete and whose original states a timer time of 350 s. With known
/// pause positions every metric below would be available.
@Suite struct UnknownPausePositionTests {
    private let count = 400

    private var stream: AnalysisStream {
        makeStream(
            count: count,
            pauses: .unknown(statedTimerTime: 350),
            power: run(200, count),
            heartRate: run(150, count),
            speed: run(8, count),
            // 100 m for 200 s, then 110 m.
            altitude: run(100, 200) + run(110, 200),
            // 8 m/s: second t holds 8t metres, so the last holds 8 x 399 = 3192.
            distance: ramp(count, perSecond: 8),
            gradient: run(0, count)
        )
    }

    private let profile = makeProfile(thresholdPower: 200, thresholdHeartRate: 150)

    private var ride: ActivityMetrics { analyse(stream, sport: .cycling, profile: profile) }
    private var jog: ActivityMetrics { analyse(stream, sport: .running, profile: profile) }

    // MARK: Still available

    @Test func elapsedTimeIsStillAvailable() {
        #expect(ride.time.elapsed == .available(400))
    }

    @Test func theStatedTimerTimeIsStillAvailableAsASummaryFigure() {
        #expect(ride.time.timer == .available(350))
        #expect(ride.time.timerIsSummaryOnly)
    }

    @Test func distanceIsStillAvailable() {
        // The last cumulative distance: 8 x 399 = 3192 m.
        #expect(ride.distance == .available(3192))
    }

    @Test func ascentIsStillAvailable() {
        // One step from 100 m to 110 m: 10 m up, nothing down.
        #expect(ride.ascent == .available(10))
        #expect(ride.descent == .available(0))
    }

    @Test func timeInPowerZonesIsStillAvailable() {
        // 200 W / 200 W = 100%, in 90 to 105%, the fourth zone. All 400 s.
        #expect(ride.timeInPowerZones == .available(TimeInZones(seconds: [0, 0, 0, 400, 0, 0, 0], missing: 0)))
    }

    @Test func timeInHeartRateZonesIsStillAvailable() {
        // 150 / 150 = 100%, in "100% and over", the fifth zone. All 400 s.
        #expect(ride.timeInHeartRateZones == .available(TimeInZones(seconds: [0, 0, 0, 0, 400], missing: 0)))
    }

    @Test func timeInGradientBandsIsStillAvailable() {
        // 0% is flat, the second band. All 400 s.
        #expect(ride.timeInGradientBands == .available(TimeInZones(seconds: [0, 400, 0, 0, 0], missing: 0)))
    }

    @Test func workIsStillAvailableAndLabelledRecorded() {
        // 200 W x 400 s = 80,000 J = 80 kJ. Incomplete pause data makes it "recorded work".
        expectWork(ride.power.work, kilojoules: 80, isRecordedOnly: true)
    }

    @Test func averagePowerIsStillAvailable() {
        // Every second has 200 W.
        expectClose(ride.power.average, 200)
        // Coverage is unavailable, so there is none to show beside it.
        #expect(ride.power.averageShowsCoverage == false)
    }

    @Test func averageHeartRateIsStillAvailable() {
        expectClose(ride.heartRate.average, 150)
    }

    // MARK: Unavailable

    @Test func movingTimeIsUnavailable() {
        #expect(ride.time.moving == .unavailable(.pausePositionsUnknown))
    }

    @Test func coverageIsUnavailable() {
        #expect(ride.power.coverage == .unavailable(.pausePositionsUnknown))
        #expect(ride.heartRate.coverage == .unavailable(.pausePositionsUnknown))
    }

    @Test func weightedPowerIsUnavailable() {
        #expect(ride.power.weighted == .unavailable(.pausePositionsUnknown))
    }

    @Test func intensityIsUnavailable() {
        #expect(ride.power.intensity == .unavailable(.pausePositionsUnknown))
    }

    @Test func variabilityIsUnavailable() {
        #expect(ride.power.variability == .unavailable(.pausePositionsUnknown))
    }

    @Test func bothKindsOfLoadAreUnavailable() {
        #expect(ride.power.load == .unavailable(.pausePositionsUnknown))
        #expect(ride.heartRate.load == .unavailable(.pausePositionsUnknown))
        #expect(ride.load == .unavailable(.pausePositionsUnknown))
        // The threshold is set, and setting one would not help.
        #expect(ride.promptsForThresholdPower == false)
    }

    @Test func thePowerCurveIsUnavailable() {
        let input = makeInput(stream, sport: .cycling, profile: profile)
        let curve = ActivityAnalysis.powerCurve(for: input, durations: [5, 60])
        #expect(curve.map(\.duration) == [5, 60])
        #expect(curve.map(\.power) == [
            .unavailable(.pausePositionsUnknown),
            .unavailable(.pausePositionsUnknown),
        ])
    }

    @Test func splitsAreUnavailable() {
        #expect(jog.splits == .unavailable(.pausePositionsUnknown))
    }

    @Test func bestDistancesAreUnavailable() {
        #expect(jog.bestDistances.map(\.distance) == [1000, 5000, 10_000])
        #expect(jog.bestDistances.map(\.time) == Array(repeating: .unavailable(.pausePositionsUnknown), count: 3))
    }

    // MARK: Not in the table

    @Test func cyclingEfficiencyFollowsWeightedPower() {
        #expect(ride.cyclingEfficiency == .unavailable(.pausePositionsUnknown))
    }

    @Test func onFootEfficiencyDoesNotNeedPausePositions() {
        // Average speed 8 m/s over average heart rate 150: 8 / 150.
        expectClose(jog.onFootEfficiency, 8.0 / 150.0)
    }
}
