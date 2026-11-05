import Foundation
import SweatKitModel
import Testing
@testable import SweatKitAnalysis

/// The order of reasons documented on `ActivityAnalysis`, where more than one
/// applies to the same metric: no stream, not defined for the sport, pause
/// positions unknown, the channel has no values, then the metric's own
/// conditions in the order its documentation lists them.
@Suite struct ReasonPrecedenceTests {
    private let profile = makeProfile(thresholdPower: 200, thresholdHeartRate: 200)

    private func unknownPauses(
        count: Int = 400,
        power: [Double?]? = nil,
        heartRate: [Double?]? = nil,
        distance: [Double?]? = nil
    ) -> AnalysisStream {
        makeStream(
            count: count,
            pauses: .unknown(statedTimerTime: 350),
            power: power,
            heartRate: heartRate,
            distance: distance
        )
    }

    // MARK: No stream comes first

    @Test func noStreamWinsOverTheSport() {
        // A run has no power metrics and a ride no splits, but with no
        // stream the reason is the missing stream.
        let stated = StatedSummary(start: testStart, end: testStart.addingTimeInterval(600), timerTime: 600)
        let run = ActivityAnalysis.metrics(for: ActivityInput(
            sport: .running, recording: .summaryOnly(stated), activityDate: testStart
        ))
        #expect(run.power.coverage == .unavailable(.noStream))
        #expect(run.power.weighted == .unavailable(.noStream))
        #expect(run.cyclingEfficiency == .unavailable(.noStream))
        let ride = ActivityAnalysis.metrics(for: ActivityInput(
            sport: .cycling, recording: .summaryOnly(stated), activityDate: testStart
        ))
        #expect(ride.splits == .unavailable(.noStream))
        #expect(ride.onFootEfficiency == .unavailable(.noStream))
        #expect(ride.bestDistances.map(\.time) == Array(repeating: .unavailable(.noStream), count: 3))
        let curve = ActivityAnalysis.powerCurve(
            for: ActivityInput(sport: .running, recording: .summaryOnly(stated), activityDate: testStart),
            durations: [5]
        )
        #expect(curve == [PowerCurvePoint(duration: 5, power: .unavailable(.noStream))])
    }

    // MARK: The sport comes before unknown pause positions

    @Test func powerOffABikeIsNotDefinedEvenWithUnknownPausePositions() {
        let stream = unknownPauses(power: run(200, 400), heartRate: run(150, 400))
        let metrics = analyse(stream, sport: .running, profile: profile)
        #expect(metrics.power.coverage == .unavailable(.notDefinedForSport))
        #expect(metrics.power.weighted == .unavailable(.notDefinedForSport))
        #expect(metrics.power.intensity == .unavailable(.notDefinedForSport))
        #expect(metrics.power.load == .unavailable(.notDefinedForSport))
        #expect(metrics.power.variability == .unavailable(.notDefinedForSport))
        #expect(metrics.cyclingEfficiency == .unavailable(.notDefinedForSport))
        let curve = ActivityAnalysis.powerCurve(
            for: makeInput(stream, sport: .running, profile: profile),
            durations: [5]
        )
        #expect(curve == [PowerCurvePoint(duration: 5, power: .unavailable(.notDefinedForSport))])
    }

    @Test func splitsAndBestDistancesOffFootAreNotDefinedEvenWithUnknownPausePositions() {
        let stream = unknownPauses(distance: ramp(400, perSecond: 8))
        let ride = analyse(stream, sport: .cycling)
        #expect(ride.splits == .unavailable(.notDefinedForSport))
        #expect(ride.bestDistances.map(\.time) == Array(repeating: .unavailable(.notDefinedForSport), count: 3))
        // Hiking has splits and no best distances.
        let hike = analyse(stream, sport: .hiking)
        #expect(hike.splits == .unavailable(.pausePositionsUnknown))
        #expect(hike.bestDistances.map(\.time) == Array(repeating: .unavailable(.notDefinedForSport), count: 3))
    }

    // MARK: Unknown pause positions come before an empty channel

    @Test func unknownPausePositionsWinOverAnEmptyPowerChannel() {
        // No power at all. The metrics that read timer seconds say the pause
        // positions are unknown; the ones that read every second say there
        // is no power.
        let stream = unknownPauses(heartRate: run(150, 400))
        let metrics = analyse(stream, profile: profile)
        #expect(metrics.power.coverage == .unavailable(.pausePositionsUnknown))
        #expect(metrics.power.weighted == .unavailable(.pausePositionsUnknown))
        #expect(metrics.power.intensity == .unavailable(.pausePositionsUnknown))
        #expect(metrics.power.load == .unavailable(.pausePositionsUnknown))
        #expect(metrics.power.variability == .unavailable(.pausePositionsUnknown))
        #expect(metrics.power.average == .unavailable(.noPower))
        #expect(metrics.power.work == .unavailable(.noPower))
        #expect(metrics.timeInPowerZones == .unavailable(.noPower))
        let curve = ActivityAnalysis.powerCurve(for: makeInput(stream, profile: profile), durations: [5])
        #expect(curve == [PowerCurvePoint(duration: 5, power: .unavailable(.pausePositionsUnknown))])
    }

    @Test func unknownPausePositionsWinOverAnEmptyHeartRateChannel() {
        let stream = unknownPauses(power: run(200, 400))
        let metrics = analyse(stream, profile: profile)
        #expect(metrics.heartRate.coverage == .unavailable(.pausePositionsUnknown))
        #expect(metrics.heartRate.load == .unavailable(.pausePositionsUnknown))
        #expect(metrics.load == .unavailable(.pausePositionsUnknown))
        #expect(metrics.heartRate.average == .unavailable(.noHeartRate))
    }

    @Test func unknownPausePositionsWinOverAnEmptyDistanceChannel() {
        let stream = unknownPauses(heartRate: run(150, 400))
        let metrics = analyse(stream, sport: .running)
        #expect(metrics.splits == .unavailable(.pausePositionsUnknown))
        #expect(metrics.bestDistances.map(\.time) == Array(repeating: .unavailable(.pausePositionsUnknown), count: 3))
        #expect(metrics.distance == .unavailable(.noDistance))
    }

    // MARK: An empty channel comes before the metric's own conditions

    @Test func anEmptyChannelWinsOverAMissingThreshold() {
        // No power, no heart rate and no thresholds.
        let metrics = analyse(makeStream(count: 10, speed: run(5, 10)))
        #expect(metrics.timeInPowerZones == .unavailable(.noPower))
        #expect(metrics.timeInHeartRateZones == .unavailable(.noHeartRate))
        #expect(metrics.heartRate.load == .unavailable(.noHeartRate))
        #expect(metrics.power.weighted == .unavailable(.noPower))
        #expect(metrics.power.intensity == .unavailable(.noPower))
    }

    @Test func thePowerCurveSaysNoPowerBeforeItLooksAtTheDuration() {
        // A duration of 0 has no window, but with no power that is the reason.
        let stream = makeStream(count: 10, heartRate: run(150, 10))
        let curve = ActivityAnalysis.powerCurve(for: makeInput(stream), durations: [0])
        #expect(curve == [PowerCurvePoint(duration: 0, power: .unavailable(.noPower))])
    }

    // MARK: The metric's own conditions, in documented order

    @Test func tooLittlePowerIsCheckedBeforeTheShareOfValidWindows() {
        // 23 s of power then 7 missing, repeated 6 times: 180 s, 138 of them
        // with power. That is under 5 minutes, and every 30-second window
        // holds exactly 23 present seconds, so no window is valid either.
        // The 5-minute rule is listed first.
        let pattern = run(200, 23) + run(nil, 7)
        let power = Array(repeating: pattern, count: 6).flatMap { $0 }
        let metrics = analyse(makeStream(count: 180, power: power))
        #expect(metrics.power.weighted == .unavailable(.tooLittlePower))
    }

    @Test func lowHeartRateCoverageIsCheckedBeforeTheThreshold() {
        // 5 of 10 seconds have heart rate, and no threshold is set.
        let stream = makeStream(count: 10, heartRate: run(150, 5) + run(nil, 5))
        #expect(analyse(stream).heartRate.load == .unavailable(.lowHeartRateCoverage))
    }

    @Test func zeroTimerTimeIsCheckedBeforeEverythingElseInLoadFromHeartRate() {
        // The whole recording is paused: coverage has no denominator, and
        // load from heart rate carries that reason.
        let stream = makeStream(count: 5, pauses: .known(paused: [0..<5]), heartRate: run(150, 5))
        #expect(analyse(stream).heartRate.load == .unavailable(.zeroDenominator))
    }

    @Test func intensityCarriesWeightedPowersReasonBeforeTheMissingThreshold() {
        // 100 s of power is under 5 minutes, and no threshold power is set.
        // The root cause is the short ride, and setting a threshold would not
        // help, so there is no prompt.
        let metrics = analyse(makeStream(count: 100, power: run(200, 100)))
        #expect(metrics.power.intensity == .unavailable(.tooLittlePower))
        #expect(metrics.power.load == .unavailable(.tooLittlePower))
        #expect(metrics.promptsForThresholdPower == false)
    }

    @Test func cyclingEfficiencyCarriesWeightedPowersReasonBeforeHeartRates() {
        // Under 5 minutes of power and no heart rate.
        let metrics = analyse(makeStream(count: 100, power: run(200, 100)))
        #expect(metrics.cyclingEfficiency == .unavailable(.tooLittlePower))
    }
}
