import Foundation
import SweatKitModel
import Testing
@testable import SweatKitAnalysis

/// The spec's "Zones" table and its boundary rule: "A value exactly on a
/// boundary belongs to the higher zone." Zones are counted from 0 here, so
/// index 0 is the spec's first zone.
@Suite struct ZoneBoundaryTests {
    // MARK: Power, seven zones

    @Test(arguments: [
        (0.55, 1), (0.75, 2), (0.90, 3), (1.05, 4), (1.20, 5), (1.50, 6),
    ])
    func aPowerShareExactlyOnABoundaryBelongsToTheHigherZone(share: Double, zone: Int) {
        #expect(ZoneScheme.power.index(of: share) == zone)
    }

    @Test(arguments: [
        (0.5499, 0), (0.7499, 1), (0.8999, 2), (1.0499, 3), (1.1999, 4), (1.4999, 5),
    ])
    func aPowerShareJustUnderABoundaryBelongsToTheLowerZone(share: Double, zone: Int) {
        #expect(ZoneScheme.power.index(of: share) == zone)
    }

    @Test func powerSharesAtTheExtremesFallInTheEndZones() {
        // 0% is under 55%. 300% is over 150%.
        #expect(ZoneScheme.power.index(of: 0) == 0)
        #expect(ZoneScheme.power.index(of: 3) == 6)
    }

    @Test(arguments: [
        // At a 200 W threshold: 55% = 110 W, 75% = 150 W, 90% = 180 W,
        // 105% = 210 W, 120% = 240 W, 150% = 300 W.
        (110.0, 1), (150.0, 2), (180.0, 3), (210.0, 4), (240.0, 5), (300.0, 6),
    ])
    func wattsExactlyOnABoundaryBelongToTheHigherZone(watts: Double, zone: Int) {
        #expect(ZoneScheme.power.index(of: watts / 200) == zone)
    }

    // MARK: Heart rate, five zones

    @Test(arguments: [(0.81, 1), (0.90, 2), (0.94, 3), (1.00, 4)])
    func aHeartRateShareExactlyOnABoundaryBelongsToTheHigherZone(share: Double, zone: Int) {
        #expect(ZoneScheme.heartRate.index(of: share) == zone)
    }

    @Test(arguments: [(0.8099, 0), (0.8999, 1), (0.9399, 2), (0.9999, 3)])
    func aHeartRateShareJustUnderABoundaryBelongsToTheLowerZone(share: Double, zone: Int) {
        #expect(ZoneScheme.heartRate.index(of: share) == zone)
    }

    @Test func heartRateSharesAtTheExtremesFallInTheEndZones() {
        #expect(ZoneScheme.heartRate.index(of: 0.5) == 0)
        #expect(ZoneScheme.heartRate.index(of: 1.3) == 4)
    }

    // MARK: Gradient, five bands

    @Test(arguments: [(-0.02, 1), (0.02, 2), (0.05, 3), (0.08, 4)])
    func aGradientExactlyOnABoundaryBelongsToTheHigherBand(gradient: Double, band: Int) {
        // -2% is flat, not descent. 2% is the first climb, 8% the steepest.
        #expect(ZoneScheme.gradient.index(of: gradient) == band)
    }

    @Test(arguments: [(-0.0201, 0), (0.0199, 1), (0.0499, 2), (0.0799, 3)])
    func aGradientJustUnderABoundaryBelongsToTheLowerBand(gradient: Double, band: Int) {
        #expect(ZoneScheme.gradient.index(of: gradient) == band)
    }

    @Test func gradientsInsideEachBand() {
        // -10% descent, 0% flat, 3% / 6% / 15% the three climbs.
        #expect(ZoneScheme.gradient.index(of: -0.10) == 0)
        #expect(ZoneScheme.gradient.index(of: 0) == 1)
        #expect(ZoneScheme.gradient.index(of: 0.03) == 2)
        #expect(ZoneScheme.gradient.index(of: 0.06) == 3)
        #expect(ZoneScheme.gradient.index(of: 0.15) == 4)
    }
}

/// "Time in zones: seconds per zone from measured and interpolated values;
/// missing seconds are reported as their own bucket."
@Suite struct TimeInZonesTests {
    // MARK: Power

    @Test func powerSecondsFallInTheZoneOfTheirShareOfThreshold() {
        // Threshold 200 W. Shares and zones (counted from 0):
        //   100 W 50%   -> 0        110 W 55%   -> 1 (boundary)
        //   149 W 74.5% -> 1        150 W 75%   -> 2 (boundary)
        //   180 W 90%   -> 3 (b.)   209 W 104.5% -> 3
        //   210 W 105%  -> 4 (b.)   240 W 120%  -> 5 (boundary)
        //   299 W 149.5% -> 5       300 W 150%  -> 6 (boundary)
        // and two missing seconds. Per zone: 1, 2, 1, 2, 1, 2, 1.
        let stream = makeStream(
            count: 12,
            power: [100, 110, 149, 150, 180, 209, 210, 240, 299, 300, nil, nil]
        )
        let metrics = analyse(stream, profile: makeProfile(thresholdPower: 200))
        #expect(metrics.timeInPowerZones == .available(TimeInZones(seconds: [1, 2, 1, 2, 1, 2, 1], missing: 2)))
    }

    @Test func interpolatedSecondsCountAndMissingSecondsDoNot() {
        // 200 W at a 200 W threshold is the fourth zone. One measured, one
        // interpolated, one missing.
        var stream = makeStream(count: 3)
        stream.power = Series(values: [200, 200, 0], quality: [.measured, .interpolated, .missing])
        let metrics = analyse(stream, profile: makeProfile(thresholdPower: 200))
        #expect(metrics.timeInPowerZones == .available(TimeInZones(seconds: [0, 0, 0, 2, 0, 0, 0], missing: 1)))
    }

    @Test func powerZonesUseTheThresholdInEffectOnTheActivityDate() {
        // 200 W from the epoch, 400 W from the day after the activity.
        // 210 W is 105% of 200 W, the fifth zone. Against 400 W it would be
        // 52.5%, the first.
        let history = [
            AthleteProfile.ThresholdPower(effectiveFrom: Date(timeIntervalSince1970: 0), watts: 200),
            AthleteProfile.ThresholdPower(effectiveFrom: testStart.addingTimeInterval(86_400), watts: 400),
        ]
        let stream = makeStream(count: 1, power: [210])
        let metrics = analyse(stream, profile: AthleteProfile(thresholdPowerHistory: history))
        #expect(metrics.timeInPowerZones == .available(TimeInZones(seconds: [0, 0, 0, 0, 1, 0, 0], missing: 0)))
    }

    @Test func powerZonesAreUnavailableWithoutAThresholdOnTheActivityDate() {
        let stream = makeStream(count: 3, power: [200, 200, 200])
        #expect(analyse(stream).timeInPowerZones == .unavailable(.noThresholdPower))
        // A threshold that takes effect only after the activity does not apply.
        let later = AthleteProfile(thresholdPowerHistory: [
            .init(effectiveFrom: testStart.addingTimeInterval(86_400), watts: 200),
        ])
        #expect(analyse(stream, profile: later).timeInPowerZones == .unavailable(.noThresholdPower))
    }

    @Test func powerZonesAreUnavailableForAThresholdOfZero() {
        // "A metric whose denominator is zero or missing is unavailable."
        let stream = makeStream(count: 3, power: [200, 200, 200])
        let metrics = analyse(stream, profile: makeProfile(thresholdPower: 0))
        #expect(metrics.timeInPowerZones == .unavailable(.zeroDenominator))
    }

    @Test func powerZonesAreUnavailableWithoutPower() {
        let stream = makeStream(count: 3, heartRate: [150, 150, 150])
        let metrics = analyse(stream, profile: makeProfile(thresholdPower: 200))
        #expect(metrics.timeInPowerZones == .unavailable(.noPower))
    }

    @Test(arguments: [Sport.walking, .running, .hiking, .other])
    func timeInPowerZonesIsForCyclingOnly(sport: Sport) {
        // "Time in power zones is for cycling only." The zones are shares of
        // cycling threshold power, so a power channel off a bike is not
        // zoned against it, whatever it holds.
        let stream = makeStream(count: 2, power: [200, 200])
        let metrics = analyse(stream, sport: sport, profile: makeProfile(thresholdPower: 200))
        #expect(metrics.timeInPowerZones == .unavailable(.notDefinedForSport))
    }

    @Test func theSameStreamOnABikeIsZoned() {
        // 200 W at a 200 W threshold is 100%, the fourth zone (90 to 105%).
        let stream = makeStream(count: 2, power: [200, 200])
        let metrics = analyse(stream, sport: .cycling, profile: makeProfile(thresholdPower: 200))
        #expect(metrics.timeInPowerZones == .available(TimeInZones(seconds: [0, 0, 0, 2, 0, 0, 0], missing: 0)))
    }

    // MARK: Heart rate

    @Test func heartRateSecondsFallInTheZoneOfTheirShareOfThreshold() {
        // Threshold 200. Shares and zones (counted from 0):
        //   160 80%   -> 0       162 81%   -> 1 (boundary)
        //   179 89.5% -> 1       180 90%   -> 2 (boundary)
        //   187 93.5% -> 2       188 94%   -> 3 (boundary)
        //   199 99.5% -> 3       200 100%  -> 4 (boundary)
        //   210 105%  -> 4
        // and one missing second. Per zone: 1, 2, 2, 2, 2.
        let stream = makeStream(
            count: 10,
            heartRate: [160, 162, 179, 180, 187, 188, 199, 200, 210, nil]
        )
        let metrics = analyse(stream, profile: makeProfile(thresholdHeartRate: 200))
        #expect(metrics.timeInHeartRateZones == .available(TimeInZones(seconds: [1, 2, 2, 2, 2], missing: 1)))
    }

    @Test func thresholdHeartRateDefaultsToNinetyPercentOfMax() {
        // Max 200 gives a threshold of 180.
        //   145 / 180 = 80.6% -> 0
        //   162 / 180 = 90%   -> 2 (boundary)
        //   180 / 180 = 100%  -> 4 (boundary)
        let stream = makeStream(count: 3, heartRate: [145, 162, 180])
        let metrics = analyse(stream, profile: makeProfile(maxHeartRate: 200))
        #expect(metrics.timeInHeartRateZones == .available(TimeInZones(seconds: [1, 0, 1, 0, 1], missing: 0)))
    }

    @Test func aStatedThresholdHeartRateWinsOverTheDefault() {
        // Stated 200, max 200. 180 / 200 = 90%, the third zone. Against the
        // default of 180 it would be 100%, the fifth.
        let stream = makeStream(count: 1, heartRate: [180])
        let metrics = analyse(stream, profile: makeProfile(thresholdHeartRate: 200, maxHeartRate: 200))
        #expect(metrics.timeInHeartRateZones == .available(TimeInZones(seconds: [0, 0, 1, 0, 0], missing: 0)))
    }

    @Test func heartRateZonesAreUnavailableWithoutAThresholdOrMax() {
        let stream = makeStream(count: 3, heartRate: [150, 150, 150])
        #expect(analyse(stream).timeInHeartRateZones == .unavailable(.noThresholdHeartRate))
    }

    @Test func heartRateZonesAreUnavailableWithoutHeartRate() {
        let stream = makeStream(count: 3, power: [200, 200, 200])
        let metrics = analyse(stream, profile: makeProfile(thresholdHeartRate: 160))
        #expect(metrics.timeInHeartRateZones == .unavailable(.noHeartRate))
    }

    @Test func heartRateZonesAreAvailableForEverySport() {
        // 160 / 160 = 100%, the fifth zone.
        let stream = makeStream(count: 2, heartRate: [160, 160])
        let metrics = analyse(stream, sport: .walking, profile: makeProfile(thresholdHeartRate: 160))
        #expect(metrics.timeInHeartRateZones == .available(TimeInZones(seconds: [0, 0, 0, 0, 2], missing: 0)))
    }

    // MARK: Gradient

    @Test func gradientSecondsFallInTheirBand() {
        // Bands (counted from 0):
        //   -5%  -> 0 descent
        //   -2%  -> 1 flat (boundary)     0%   -> 1 flat
        //   2%   -> 2 (boundary)          4.9% -> 2
        //   5%   -> 3 (boundary)
        //   8%   -> 4 (boundary)          12%  -> 4
        // and one missing second. Per band: 1, 2, 2, 1, 2.
        let stream = makeStream(
            count: 9,
            gradient: [-0.05, -0.02, 0, 0.02, 0.049, 0.05, 0.08, 0.12, nil]
        )
        #expect(analyse(stream).timeInGradientBands == .available(TimeInZones(seconds: [1, 2, 2, 1, 2], missing: 1)))
    }

    @Test func gradientBandsAreUnavailableWithoutGradient() {
        let stream = makeStream(count: 3, power: [200, 200, 200])
        #expect(analyse(stream).timeInGradientBands == .unavailable(.noGradient))
    }

    // MARK: Which seconds are counted

    @Test func timeInZonesCountsEverySecondOfTheStream() {
        // The spec does not leave paused seconds out, so they are counted:
        // four seconds at 100% of threshold, two of them paused, and two
        // missing seconds. The buckets add up to the 6 s of elapsed time.
        let stream = makeStream(
            count: 6,
            pauses: .known(paused: [2..<4]),
            heartRate: [200, 200, 200, 200, nil, nil]
        )
        let metrics = analyse(stream, profile: makeProfile(thresholdHeartRate: 200))
        #expect(metrics.timeInHeartRateZones == .available(TimeInZones(seconds: [0, 0, 0, 0, 4], missing: 2)))
    }
}
