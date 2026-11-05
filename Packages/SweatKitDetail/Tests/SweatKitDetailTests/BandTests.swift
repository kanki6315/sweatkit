import SweatKitAnalysis
import SweatKitModel
import Testing
@testable import SweatKitDetail

@Suite("Colour bands per second")
struct BandTests {
    /// Constant power, so the 10-second mean equals the reading and only the
    /// zone boundary is under test. Threshold 200 W; the spec's bounds are
    /// 55, 75, 90, 105, 120 and 150%, and a share exactly on a bound belongs
    /// to the higher zone.
    @Test(arguments: [
        (109.0, 0), // 0.545: under 55%
        (110.0, 1), // 0.55 exactly: second zone
        (149.0, 1), // 0.745
        (150.0, 2), // 0.75 exactly
        (180.0, 3), // 0.90 exactly
        (210.0, 4), // 1.05 exactly
        (240.0, 5), // 1.20 exactly
        (299.0, 5), // 1.495
        (300.0, 6), // 1.50 exactly: over 150%
    ])
    func powerZoneBoundaries(watts: Double, zone: Int) throws {
        let stream = makeStream(count: 3, power: run(watts, 3))
        let bands = try #require(ColourBanding.bands(for: .power, input: makeInput(stream, profile: makeProfile(thresholdPower: 200))).value)
        #expect(bands.bandCount == 7)
        #expect(bands.bands == [zone, zone, zone])
    }

    @Test func smoothingAtTheStartAndAcrossAGap() {
        // Trailing 10-second mean of the values present; a second with no
        // value of its own has none.
        let series = Series([100, 200, 300, nil, 400])
        let smoothed = ColourBanding.trailingMean(series, seconds: 10)
        #expect(smoothed == [
            100,                         // window cut at second 0: 100 / 1
            150,                         // (100 + 200) / 2
            200,                         // (100 + 200 + 300) / 3
            nil,                         // no value of its own
            250,                         // (100 + 200 + 300 + 400) / 4: the gap is in neither sum nor count
        ])
    }

    @Test func smoothingWindowDropsSecondsOlderThanTen() {
        // 1000 W at second 0, then nine of 100 W, then two of 300 W.
        let series = Series([1000] + run(100, 9) + run(300, 2))
        let smoothed = ColourBanding.trailingMean(series, seconds: 10)
        #expect(smoothed[9] == 190)  // seconds 0...9: (1000 + 9 × 100) / 10
        #expect(smoothed[10] == 120) // seconds 1...10: (9 × 100 + 300) / 10, second 0 has left the window
        #expect(smoothed[11] == 140) // seconds 2...11: (8 × 100 + 2 × 300) / 10
    }

    @Test func powerIsZonedOnSmoothedPower() throws {
        // Nine seconds of 100 W then one of 400 W, threshold 200 W.
        let stream = makeStream(count: 10, power: run(100, 9) + [400])
        let bands = try #require(ColourBanding.bands(for: .power, input: makeInput(stream, profile: makeProfile(thresholdPower: 200))).value)
        // 100 / 200 = 0.5: zone 0 for the first nine seconds.
        // Second 9: (9 × 100 + 400) / 10 = 130 W, 0.65: zone 1, not the
        // zone 6 that 400 W alone would be.
        #expect(bands.bands == [Int?](repeating: 0, count: 9) + [1])
    }

    @Test func aSecondWithNoPowerHasNoBand() throws {
        let stream = makeStream(count: 3, power: [100, nil, 100])
        let bands = try #require(ColourBanding.bands(for: .power, input: makeInput(stream, profile: makeProfile(thresholdPower: 200))).value)
        #expect(bands.bands == [0, nil, 0])
        #expect(bands.viewBands == [0, 7, 0]) // nil becomes noValueBand, 7, one past the last zone
    }

    /// Threshold heart rate 200; bounds 81, 90, 94 and 100%.
    @Test func heartRateZoneBoundaries() throws {
        let stream = makeStream(count: 7, heartRate: [161, 162, 179, 180, 188, 200, nil])
        let bands = try #require(ColourBanding.bands(for: .heartRate, input: makeInput(stream, profile: makeProfile(thresholdHeartRate: 200))).value)
        #expect(bands.bandCount == 5)
        #expect(bands.bands == [
            0,   // 0.805
            1,   // 0.81 exactly
            1,   // 0.895
            2,   // 0.90 exactly
            3,   // 0.94 exactly
            4,   // 1.00 exactly
            nil, // no value
        ])
    }

    @Test func heartRateUsesNinetyPercentOfMaxWhenNoThresholdIsSet() throws {
        // Max 200, so threshold 180. 162 / 180 = 0.9: zone 2.
        let stream = makeStream(count: 1, heartRate: [162])
        let bands = try #require(ColourBanding.bands(for: .heartRate, input: makeInput(stream, profile: makeProfile(maxHeartRate: 200))).value)
        #expect(bands.bands == [2])
    }

    /// Bounds -2, 2, 5 and 8%.
    @Test func gradientBandBoundaries() throws {
        let stream = makeStream(count: 8, gradient: [-0.03, -0.02, 0, 0.0199, 0.02, 0.05, 0.08, nil])
        let bands = try #require(ColourBanding.bands(for: .gradient, input: makeInput(stream)).value)
        #expect(bands.bandCount == 5)
        #expect(bands.bands == [0, 1, 1, 1, 2, 3, 4, nil])
    }

    @Test func paceBandsSpanTheActivitysOwnRange() throws {
        // Ten seconds at 1 m/s then ten at 6 m/s. The 10-second mean is 1.0
        // for seconds 0...9, then climbs by 0.5 a second: 1.5, 2.0, ..., 6.0.
        let stream = makeStream(count: 20, speed: run(1, 10) + run(6, 10))
        let bands = try #require(ColourBanding.bands(for: .paceOrSpeed, input: makeInput(stream, sport: .walking)).value)
        // All 20 are above the 0.5 m/s floor. Nearest rank: the 10th
        // percentile is rank ceil(2) = 2, the second smallest, 1.0; the 90th
        // is rank ceil(18) = 18, which is 5.0. Five bands of 0.8 m/s from
        // 1.0: band = floor((v - 1) × 5 / 4), clamped to 0...4.
        #expect(bands.bandCount == 5)
        #expect(bands.bands == [Int?](repeating: 0, count: 10) + [
            0, // 1.5: 0.625
            1, // 2.0: 1.25
            1, // 2.5: 1.875
            2, // 3.0: 2.5
            3, // 3.5: 3.125
            3, // 4.0: 3.75
            4, // 4.5: 4.375
            4, // 5.0: exactly 5, the top of the range, clamped to the top band
            4, // 5.5: above the range
            4, // 6.0: above the range
        ])
    }

    @Test func paceRangeLeavesStoppedSecondsOut() throws {
        // Three stopped seconds, three at 2 m/s and three at 4 m/s, each
        // group more than ten seconds from the last so no window spans two.
        let speed: [Double?] = run(0, 3) + run(nil, 9) + run(2, 3) + run(nil, 9) + run(4, 3)
        let stream = makeStream(count: speed.count, speed: speed)
        let bands = try #require(ColourBanding.bands(for: .paceOrSpeed, input: makeInput(stream, sport: .walking)).value)
        // Moving seconds, at or above 0.5 m/s: 2, 2, 2, 4, 4, 4. Nearest
        // rank: 10th percentile rank ceil(0.6) = 1 → 2; 90th rank ceil(5.4)
        // = 6 → 4. 2 m/s is band 0. Had the stopped seconds counted, the
        // range would be 0 to 4 and 2 m/s would be band floor(2.5) = 2.
        #expect(bands.bands[0] == 0)  // stopped: below the range
        #expect(bands.bands[3] == nil)
        #expect(bands.bands[12] == 0) // 2 m/s
        #expect(bands.bands[24] == 4) // 4 m/s, the top of the range
    }

    @Test func steadySpeedIsAllInTheMiddleBand() throws {
        let stream = makeStream(count: 4, speed: run(3, 4))
        let bands = try #require(ColourBanding.bands(for: .paceOrSpeed, input: makeInput(stream, sport: .running)).value)
        #expect(bands.bands == [2, 2, 2, 2])
    }

    @Test func plainIsOneBand() throws {
        let bands = try #require(ColourBanding.bands(for: .plain, input: makeInput(makeStream(count: 3))).value)
        #expect(bands.bandCount == 1)
        #expect(bands.bands == [0, 0, 0])
    }
}

@Suite("Unavailable overlays")
struct UnavailableOverlayTests {
    @Test func powerWithNoThresholdSet() {
        let stream = makeStream(count: 3, power: run(200, 3))
        #expect(ColourBanding.bands(for: .power, input: makeInput(stream)).value?.bands == [3, 3, 3])
    }

    @Test func powerWithAThresholdSetOnlyAfterTheActivity() {
        let stream = makeStream(count: 3, power: run(200, 3))
        let profile = AthleteProfile(thresholdPowerHistory: [.init(effectiveFrom: testStart.addingTimeInterval(86_400), watts: 250)])
        #expect(ColourBanding.bands(for: .power, input: makeInput(stream, profile: profile)).value?.bands == [3, 3, 3])
    }

    @Test func powerWithAZeroThreshold() {
        let stream = makeStream(count: 3, power: run(200, 3))
        #expect(ColourBanding.bands(for: .power, input: makeInput(stream, profile: makeProfile(thresholdPower: 0))).reason == .zeroDenominator)
    }

    @Test func noPowerChannel() {
        let stream = makeStream(count: 3, heartRate: run(140, 3))
        #expect(ColourBanding.bands(for: .power, input: makeInput(stream, profile: makeProfile(thresholdPower: 200))).reason == .noPower)
    }

    @Test func powerOffABike() {
        let stream = makeStream(count: 3, power: run(200, 3))
        #expect(ColourBanding.bands(for: .power, input: makeInput(stream, sport: .running, profile: makeProfile(thresholdPower: 200))).reason == .notDefinedForSport)
    }

    @Test func heartRateWithNoThreshold() {
        let stream = makeStream(count: 3, heartRate: run(140, 3))
        #expect(ColourBanding.bands(for: .heartRate, input: makeInput(stream)).value?.bands == [1, 1, 1])
    }

    @Test func missingChannels() {
        let input = makeInput(makeStream(count: 3), profile: makeProfile(thresholdPower: 200, thresholdHeartRate: 170))
        #expect(ColourBanding.bands(for: .heartRate, input: input).reason == .noHeartRate)
        #expect(ColourBanding.bands(for: .paceOrSpeed, input: input).reason == .noSpeed)
        #expect(ColourBanding.bands(for: .gradient, input: input).reason == .noGradient)
        #expect(ColourBanding.bands(for: .plain, input: input).value != nil)
    }
}

@Suite("Default overlay")
struct DefaultOverlayTests {
    @Test func theSpecsTable() {
        #expect(RouteOverlay.tableDefault(sport: .cycling, hasPowerMeter: true) == .power)
        #expect(RouteOverlay.tableDefault(sport: .cycling, hasPowerMeter: false) == .heartRate)
        #expect(RouteOverlay.tableDefault(sport: .walking, hasPowerMeter: false) == .paceOrSpeed)
        #expect(RouteOverlay.tableDefault(sport: .running, hasPowerMeter: true) == .paceOrSpeed)
        #expect(RouteOverlay.tableDefault(sport: .hiking, hasPowerMeter: false) == .paceOrSpeed)
        #expect(RouteOverlay.tableDefault(sport: .other, hasPowerMeter: false) == .plain)
    }

    @Test func aRideWithPowerOpensOnPower() {
        let stream = makeStream(count: 3, power: run(200, 3), heartRate: run(140, 3))
        let detail = DetailPreparation.prepare(makeInput(stream, profile: makeProfile(thresholdPower: 250, thresholdHeartRate: 170)))
        #expect(detail.defaultOverlay == .power)
    }

    @Test func aRideWithPowerButNoThresholdUsesStarterPower() {
        let stream = makeStream(count: 3, power: run(200, 3), heartRate: run(140, 3))
        let detail = DetailPreparation.prepare(makeInput(stream, profile: makeProfile(thresholdHeartRate: 170)))
        #expect(detail.defaultOverlay == .power)
        #expect(detail.bands[.power]?.value?.bands == [3, 3, 3])
    }

    @Test func aRideWithoutPowerOpensOnHeartRate() {
        let stream = makeStream(count: 3, heartRate: run(140, 3))
        let detail = DetailPreparation.prepare(makeInput(stream, profile: makeProfile(thresholdPower: 250, thresholdHeartRate: 170)))
        #expect(detail.defaultOverlay == .heartRate)
    }

    @Test func aRideWithNothingToZoneIsPlain() {
        let stream = makeStream(count: 3)
        #expect(DetailPreparation.prepare(makeInput(stream)).defaultOverlay == .plain)
    }

    @Test func aWalkOpensOnPace() {
        let stream = makeStream(count: 3, power: run(200, 3), speed: run(1.4, 3))
        let detail = DetailPreparation.prepare(makeInput(stream, sport: .walking, profile: makeProfile(thresholdPower: 250)))
        #expect(detail.defaultOverlay == .paceOrSpeed)
    }

    @Test func otherSportsArePlain() {
        let stream = makeStream(count: 3, speed: run(1.4, 3))
        #expect(DetailPreparation.prepare(makeInput(stream, sport: .other)).defaultOverlay == .plain)
    }
}

@Suite struct CustomBandTests {
    @Test func customZonesMatchTotals() throws {
        let profile = AthleteProfile(powerZoneBounds: [100, 130, 160, 190, 220, 250],
                                     heartRateZoneBounds: [100, 120, 140, 160])
        let input = makeInput(makeStream(count: 3, power: run(250, 3), heartRate: run(140, 3)), profile: profile)
        #expect(ColourBanding.bands(for: .power, input: input).value?.bands == [6, 6, 6])
        #expect(ColourBanding.bands(for: .heartRate, input: input).value?.bands == [3, 3, 3])
    }
}
