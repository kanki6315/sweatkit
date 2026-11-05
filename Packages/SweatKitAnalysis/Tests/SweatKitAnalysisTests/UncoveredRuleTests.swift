import Foundation
import SweatKitModel
import Testing
@testable import SweatKitAnalysis

/// Rules of the spec's "Analysis metrics" section that the first set of
/// tests left without a case. Every expected value is worked out beside it.
@Suite struct SplitEdgeTests {
    @Test func anActivityEndingExactlyOnAKilometreMarkEndsWithAZeroDistanceSplit() throws {
        // 251 s at 4 m/s: second 250 holds exactly 1000 m, and a second on a
        // mark opens the next split. Split 0 is seconds 0...249: 250 s over
        // 1000 m, 250 s/km. Split 1 is second 250 alone: 1 s, and
        // 1000 - 1000 = 0 m, so its pace has a zero denominator.
        let stream = makeStream(count: 251, distance: ramp(251, perSecond: 4))
        let splits = try #require(analyse(stream, sport: .running).splits.value)
        #expect(splits.map(\.index) == [0, 1])
        #expect(splits.map(\.distance) == [1000, 0])
        #expect(splits.map(\.duration) == [250, 1])
        try #require(splits.count == 2)
        expectClose(splits[0].pace, 250)
        #expect(splits[1].pace == .unavailable(.zeroDenominator))
    }

    @Test func secondsBeforeTheFirstDistanceBelongToTheFirstSplit() throws {
        // No distance for the first 10 s, then 4 m/s from 0 m: second 10 + k
        // holds 4k metres, so the last second, 135, holds 4 x 125 = 500 m.
        // One part split holding all 136 seconds: 136 s over 0.5 km = 272 s/km.
        let stream = makeStream(count: 136, distance: run(nil, 10) + ramp(126, perSecond: 4))
        let splits = try #require(analyse(stream, sport: .running).splits.value)
        try #require(splits.count == 1)
        #expect(splits[0].index == 0)
        #expect(splits[0].distance == 500)
        #expect(splits[0].duration == 136)
        expectClose(splits[0].pace, 272)
    }

    @Test func aClimbCountedDuringAPauseIsStillCreditedToItsSplit() throws {
        // 376 s whose distance is 4 m/s (second 250 holds 1000 m, the last
        // holds 1500 m), paused for seconds 90..<110. Altitude steps from
        // 100 m to 110 m at second 100, inside the pause. Ascent reads every
        // second, so the activity climbs 10 m, counted at second 100, whose
        // distance of 400 m is in split 0.
        //
        // Split 0 is seconds 0...249 less the 20 paused: 230 s. Split 1 is
        // seconds 250...375: 126 s.
        let stream = makeStream(
            count: 376,
            pauses: .known(paused: [90..<110]),
            altitude: run(100, 100) + run(110, 276),
            distance: ramp(376, perSecond: 4)
        )
        let metrics = analyse(stream, sport: .hiking)
        let splits = try #require(metrics.splits.value)
        try #require(splits.count == 2)
        #expect(splits.map(\.duration) == [230, 126])
        #expect(splits[0].ascent == .available(10))
        #expect(splits[1].ascent == .available(0))
        #expect(metrics.ascent == .available(10))
    }

    @Test func aSplitWithHeartRateOnSomeSecondsAveragesOnlyThose() throws {
        // One part split of 126 s (500 m). Heart rate 140 for 26 s, missing
        // for 50 s, 160 for 50 s: (26 x 140 + 50 x 160) / 76 = 11640 / 76.
        let stream = makeStream(
            count: 126,
            heartRate: run(140, 26) + run(nil, 50) + run(160, 50),
            distance: ramp(126, perSecond: 4)
        )
        let splits = try #require(analyse(stream, sport: .walking).splits.value)
        try #require(splits.count == 1)
        expectClose(splits[0].averageHeartRate, 11640.0 / 76.0)
    }
}

@Suite struct BestDistanceEdgeTests {
    private func best(_ stream: AnalysisStream) -> [Metric<TimeInterval>] {
        analyse(stream, sport: .running).bestDistances.map(\.time)
    }

    @Test func aSecondWithNoDistanceIsNotAnEndPoint() {
        // 5 m/s, where second t holds 5t metres. Second 200 would hold
        // 1000 m but is missing, so the last end point is second 199 at
        // 995 m: the kilometre is not covered.
        let lostEnd = makeStream(count: 201, distance: ramp(200, perSecond: 5) + run(nil, 1))
        #expect(best(lostEnd)[0] == .unavailable(.distanceNotCovered))
        // Second 0 is missing, so the first end point is second 1 at 5 m.
        // Second 200 holds 1000 m: 995 m apart, not covered.
        let lostStart = makeStream(count: 201, distance: run(nil, 1) + (1...200).map { Optional(5 * Double($0)) })
        #expect(best(lostStart)[0] == .unavailable(.distanceNotCovered))
        // One more second: second 201 holds 1005 m, 1000 m after second 1
        // and 200 s later.
        let longer = makeStream(count: 202, distance: run(nil, 1) + (1...201).map { Optional(5 * Double($0)) })
        #expect(best(longer)[0] == .available(200))
    }

    @Test func aGapInDistanceInsideTheStretchChangesNothing() {
        // 5 m/s with seconds 50..<150 missing. Second 0 holds 0 m and second
        // 200 holds 1000 m: 200 s, as without the gap.
        let distance = ramp(50, perSecond: 5) + run(nil, 100) + (150...200).map { Optional(5 * Double($0)) }
        let stream = makeStream(count: 201, distance: distance)
        #expect(best(stream)[0] == .available(200))
    }

    @Test func theRuleIsAppliedAsWrittenToAChannelThatGoesDown() {
        // A cumulative channel should never go down. If it does, the rule is
        // still "the fewest timer seconds between two seconds whose distances
        // differ by at least the distance". Distances 0, 600, 100, 1100:
        //   seconds 0 and 3: 1100 m apart, 3 s
        //   seconds 1 and 3:  500 m apart, not enough
        //   seconds 2 and 3: 1000 m apart, 1 s
        // The fewest is 1 s.
        let stream = makeStream(count: 4, distance: [0, 600, 100, 1100])
        #expect(best(stream)[0] == .available(1))
    }

    @Test func aPausedStartSecondIsNotCounted() {
        // Paused 0..<10 at 0 m, then 5 m/s: second 10 + k holds 5k metres,
        // so second 210 holds 1000 m. From second 0 to second 210 there are
        // 210 seconds, 10 of them paused: 200 s.
        let stream = makeStream(
            count: 211,
            pauses: .known(paused: [0..<10]),
            distance: run(0, 10) + ramp(201, perSecond: 5)
        )
        #expect(best(stream)[0] == .available(200))
    }
}

@Suite struct EfficiencyEdgeTests {
    @Test func onFootEfficiencyReadsPausedSecondsToo() {
        // The definition is "over the seconds that have both" and names no
        // timer time. Paused 2..<4. Every second: speed (2 + 2 + 4 + 4) / 4
        // = 3 m/s over a heart rate of 100: 0.03. Timer seconds alone would
        // give 2 / 100 = 0.02.
        let stream = makeStream(
            count: 4,
            pauses: .known(paused: [2..<4]),
            heartRate: run(100, 4),
            speed: [2, 2, 4, 4]
        )
        expectClose(analyse(stream, sport: .running).onFootEfficiency, 0.03)
    }

    @Test func onFootEfficiencyIsUnavailableWhenNoSecondHasBoth() {
        // Both channels exist, but never in the same second.
        let stream = makeStream(
            count: 4,
            heartRate: [150, 150, nil, nil],
            speed: [nil, nil, 3, 3]
        )
        #expect(analyse(stream, sport: .running).onFootEfficiency == .unavailable(.noHeartRate))
    }

    @Test func onFootEfficiencyIsUnavailableWhenAverageHeartRateIsZero() {
        // "A metric whose denominator is zero or missing is unavailable."
        let stream = makeStream(count: 10, heartRate: run(0, 10), speed: run(3, 10))
        #expect(analyse(stream, sport: .running).onFootEfficiency == .unavailable(.zeroDenominator))
    }

    @Test func cyclingEfficiencyIsUnavailableWhenAverageHeartRateIsZero() {
        // 300 s at 200 W has a weighted power of 200 W; a strap reporting 0
        // throughout averages 0.
        let stream = makeStream(count: 300, power: run(200, 300), heartRate: run(0, 300))
        let metrics = analyse(stream)
        expectClose(metrics.power.weighted, 200, tolerance: 1e-6)
        #expect(metrics.heartRate.average == .available(0))
        #expect(metrics.cyclingEfficiency == .unavailable(.zeroDenominator))
    }
}

@Suite struct FlagEdgeTests {
    @Test func theTimerOfAnActivityWithNoStreamIsNotMarkedSummaryOnly() {
        // The flag is for a stream whose pause positions are unknown. With
        // no stream there is nothing else to build on the timer time.
        let stated = StatedSummary(start: testStart, end: testStart.addingTimeInterval(600), timerTime: 500)
        let metrics = ActivityAnalysis.metrics(for: ActivityInput(
            sport: .cycling, recording: .summaryOnly(stated), activityDate: testStart
        ))
        #expect(metrics.time.timer == .available(500))
        #expect(metrics.time.timerIsSummaryOnly == false)
    }

    @Test func aThresholdPowerOfZeroIsSetSoThereIsNoPrompt() {
        // Weighted power is available and a threshold was in effect, though
        // it is zero: intensity has a zero denominator, and the prompt is
        // only for a threshold that is not set.
        let stream = makeStream(count: 300, power: run(200, 300), heartRate: run(150, 300))
        let metrics = analyse(stream, profile: makeProfile(thresholdPower: 0, thresholdHeartRate: 200))
        #expect(metrics.power.intensity == .unavailable(.zeroDenominator))
        #expect(metrics.promptsForThresholdPower == false)
        // Load falls through to heart rate: 300 x 0.75^2 / 3600 x 100 = 4.6875.
        #expect(metrics.load.value?.source == .heartRate)
        expectClose(metrics.heartRate.load, 4.6875)
    }

    @Test func workIsNotLabelledRecordedWhenCoverageHasNoDenominator() {
        // The whole recording is paused, so coverage is unavailable rather
        // than under 98%, and pause data is complete. Neither condition for
        // "recorded work" holds. 200 W x 5 s = 1000 J = 1 kJ.
        let stream = makeStream(count: 5, pauses: .known(paused: [0..<5]), power: run(200, 5))
        let metrics = analyse(stream)
        #expect(metrics.power.coverage == .unavailable(.zeroDenominator))
        expectWork(metrics.power.work, kilojoules: 1, isRecordedOnly: false)
        // There is no coverage to show beside the average.
        expectClose(metrics.power.average, 200)
        #expect(metrics.power.averageShowsCoverage == false)
    }

    @Test func aThresholdPowerTakingEffectOnTheActivityDateApplies() {
        // "The threshold power in effect on the activity date": one set at
        // the very start of the activity is in effect. 200 / 250 = 0.8.
        let profile = AthleteProfile(thresholdPowerHistory: [
            .init(effectiveFrom: testStart, watts: 250),
        ])
        let metrics = analyse(makeStream(count: 300, power: run(200, 300)), profile: profile)
        expectClose(metrics.power.intensity, 0.8)
        #expect(metrics.promptsForThresholdPower == false)
    }
}

@Suite struct ChannelOnlyWhilePausedTests {
    @Test func powerOnlyInsideAPauseGivesAnAverageButNoCoverage() {
        // 300 s riding with no power, then 300 s paused with the meter
        // reporting 200 W. Coverage is 0 of 300 timer seconds: a true 0.
        // Average and work read every second: 200 W, and
        // 200 W x 300 s = 60 kJ, "recorded" because coverage is under 98%.
        // No timer second has power, which is under 5 minutes.
        let stream = makeStream(
            count: 600,
            pauses: .known(paused: [300..<600]),
            power: run(nil, 300) + run(200, 300)
        )
        let metrics = analyse(stream)
        #expect(metrics.power.coverage == .available(0))
        expectClose(metrics.power.average, 200)
        #expect(metrics.power.averageShowsCoverage)
        expectWork(metrics.power.work, kilojoules: 60, isRecordedOnly: true)
        #expect(metrics.power.weighted == .unavailable(.tooLittlePower))
        let curve = ActivityAnalysis.powerCurve(for: makeInput(stream), durations: [5])
        #expect(curve[0].power == .unavailable(.noValidWindow))
    }

    @Test func heartRateOnlyInsideAPauseGivesNoLoad() {
        // 10 s running with no heart rate, 10 s paused at 200. Coverage is
        // 0 of 10 timer seconds, which is under 90%.
        let stream = makeStream(
            count: 20,
            pauses: .known(paused: [10..<20]),
            heartRate: run(nil, 10) + run(200, 10)
        )
        let metrics = analyse(stream, profile: makeProfile(thresholdHeartRate: 200))
        #expect(metrics.heartRate.coverage == .available(0))
        expectClose(metrics.heartRate.average, 200)
        #expect(metrics.heartRate.load == .unavailable(.lowHeartRateCoverage))
    }
}

@Suite struct LongWindowTests {
    private func best(_ stream: AnalysisStream, _ duration: Int) -> Metric<Double> {
        ActivityAnalysis.powerCurve(for: makeInput(stream), durations: [duration])[0].power
    }

    @Test func aTenMinuteWindowNeedsFiveHundredAndSeventySecondsOfPower() {
        // 95% of 600 is 570. 570 of 600 is exactly 95%: valid, and the mean
        // is over the 570 present seconds, 200 W. 569 of 600 is 94.8%.
        let valid = makeStream(count: 600, power: run(200, 570) + run(nil, 30))
        expectClose(best(valid, 600), 200)
        let invalid = makeStream(count: 600, power: run(200, 569) + run(nil, 31))
        #expect(best(invalid, 600) == .unavailable(.noValidWindow))
    }

    @Test func aTwentyMinuteWindowNeedsElevenHundredAndFortySecondsOfPower() {
        // 95% of 1200 is 1140. 1139 of 1200 is 94.9%.
        let valid = makeStream(count: 1200, power: run(250, 1140) + run(nil, 60))
        expectClose(best(valid, 1200), 250)
        let invalid = makeStream(count: 1200, power: run(250, 1139) + run(nil, 61))
        #expect(best(invalid, 1200) == .unavailable(.noValidWindow))
    }

    @Test func theBestWindowCanSitInALaterTimerSpan() {
        // 10 s at 100 W, 5 s paused, 10 s at 300 W. The best 10 s is the
        // second span.
        let stream = makeStream(
            count: 25,
            pauses: .known(paused: [10..<15]),
            power: run(100, 10) + run(nil, 5) + run(300, 10)
        )
        expectClose(best(stream, 10), 300)
    }

    @Test func aLongWindowSlidesToItsBestPosition() {
        // 100 s at 100 W, 600 s at 300 W, 100 s at 100 W. The best 600 s is
        // the 300 W block: 300 W. The best 700 s holds the block and 100 s
        // at 100 W: (600 x 300 + 100 x 100) / 700 = 190000 / 700.
        let stream = makeStream(count: 800, power: run(100, 100) + run(300, 600) + run(100, 100))
        expectClose(best(stream, 600), 300)
        expectClose(best(stream, 700), 190_000.0 / 700.0)
    }

    @Test func weightedPowerOfAnHourInTwoHalves() {
        // 1800 s at 0 W then 1800 s at 300 W. T = 3600, so 3571 possible
        // windows, starting at 0...3570, and all are valid.
        //   s = 0...1770 (1771 windows) hold only 0 W: mean 0.
        //   s = 1771...1799 (29 windows) hold k = s - 1770 samples of 300 W,
        //     k = 1...29: mean 300k / 30 = 10k W.
        //   s = 1800...3570 (1771 windows) hold only 300 W: mean 300.
        // Sum of k^4 for 1...29 = 5,273,999 - 30^4 = 5,273,999 - 810,000
        //                       = 4,463,999 (the sum to 30 is worked in
        //                       WeightedPowerTests).
        // Sum of fourth powers = 10^4 x 4,463,999 + 1771 x 300^4
        //                      = 10^4 x 4,463,999 + 1771 x 81 x 10^8.
        // Weighted power = (that / 3571)^(1/4), about 252 W.
        let stream = makeStream(count: 3600, power: run(0, 1800) + run(300, 1800))
        let expected = pow((1e4 * 4_463_999 + 1771 * 81e8) / 3571, 0.25)
        expectClose(analyse(stream).power.weighted, expected, tolerance: 1e-6)
    }
}

@Suite struct ZoneEdgeTests {
    @Test func heartRateZonesAreUnavailableForAThresholdOfZero() {
        // "A metric whose denominator is zero or missing is unavailable."
        let stream = makeStream(count: 3, heartRate: [150, 150, 150])
        let metrics = analyse(stream, profile: makeProfile(thresholdHeartRate: 0))
        #expect(metrics.timeInHeartRateZones == .unavailable(.zeroDenominator))
    }

    @Test func theZonesAndTheMissingBucketAddUpToElapsedTime() throws {
        // 12 s: 5 with power, 7 without. 100 W at 200 W is 50%, the first zone.
        let stream = makeStream(count: 12, power: run(100, 5) + run(nil, 7))
        let zones = try #require(analyse(stream, profile: makeProfile(thresholdPower: 200)).timeInPowerZones.value)
        #expect(zones == TimeInZones(seconds: [5, 0, 0, 0, 0, 0, 0], missing: 7))
        #expect(zones.seconds.reduce(0, +) + zones.missing == 12)
    }

    @Test func anySchemeFollowsTheBoundaryRule() {
        // Bounds 10 and 20 make three zones: under 10, 10 to 20, 20 and over.
        let scheme = ZoneScheme(lowerBounds: [10, 20])
        #expect(scheme.zoneCount == 3)
        #expect(scheme.index(of: 9.99) == 0)
        #expect(scheme.index(of: 10) == 1)
        #expect(scheme.index(of: 19.99) == 1)
        #expect(scheme.index(of: 20) == 2)
        #expect(scheme.index(of: -5) == 0)
    }

    @Test func aSchemeWithNoBoundsHasOneZone() {
        let scheme = ZoneScheme(lowerBounds: [])
        #expect(scheme.zoneCount == 1)
        #expect(scheme.index(of: 42) == 0)
    }

    @Test func aNegativeGradientBelowEveryBoundIsDescent() {
        // -30% is under -2%.
        #expect(ZoneScheme.gradient.index(of: -0.30) == 0)
    }
}

@Suite struct MovingTimeEdgeTests {
    @Test func aSlowSecondInsideAPauseIsNotSubtractedTwice() {
        // Paused 0..<4 with speed 0 throughout the pause and 5 m/s after.
        // Timer = 10 - 4 = 6, and no timer second is slow: moving = 6.
        let stream = makeStream(count: 10, pauses: .known(paused: [0..<4]), speed: run(0, 4) + run(5, 6))
        #expect(analyse(stream).time.moving == .available(6))
    }

    @Test func aRideThatNeverMovesHasZeroMovingTime() {
        // Every timer second is below 1 m/s: 5 - 5 = 0, a true zero.
        let stream = makeStream(count: 5, speed: run(0.2, 5))
        #expect(analyse(stream).time.moving == .available(0))
    }

    @Test func theBikeFloorDoesNotApplyOnFoot() {
        // 0.7 m/s is stopped on a bike (under 1.0) and moving on foot (at
        // least 0.5).
        let stream = makeStream(count: 4, speed: run(0.7, 4))
        #expect(analyse(stream, sport: .cycling).time.moving == .available(0))
        #expect(analyse(stream, sport: .hiking).time.moving == .available(4))
    }
}
