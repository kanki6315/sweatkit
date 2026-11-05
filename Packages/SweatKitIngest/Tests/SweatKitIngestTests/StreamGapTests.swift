import Foundation
import SweatKitIngest
import SweatKitModel
import Testing

/// Stream rules 3 to 7: every value is marked, gaps of up to 5 seconds are
/// filled (linear or hold-last by channel), nothing is filled across a pause
/// boundary, longer gaps are missing, a recorded zero is measured, and a
/// sensor dropout touches only its own channel and never the activity length.
@Suite struct StreamGapTests {
    /// A sample at `second` holding one channel.
    private static func sample(_ second: TimeInterval, _ channel: Channel, _ value: Double) -> NativeSample {
        var sample = NativeSample(timestamp: Synthetic.at(second))
        switch channel {
        case .altitude: sample.altitude = value
        case .distance: sample.distance = value
        case .speed: sample.speed = value
        case .heartRate: sample.heartRate = value
        case .power: sample.power = value
        case .cadence: sample.cadence = value
        case .temperature: sample.temperature = value
        case .runningStrideLength: sample.runningStrideLength = value
        case .runningGroundContactTime: sample.runningGroundContactTime = value
        case .runningVerticalOscillation: sample.runningVerticalOscillation = value
        case .latitude, .longitude, .gradient:
            preconditionFailure("\(channel) is not a single recorded channel")
        }
        return sample
    }

    private static func position(_ second: TimeInterval, _ latitude: Double, _ longitude: Double) -> NativeSample {
        NativeSample(
            timestamp: Synthetic.at(second),
            position: Coordinate(latitude: latitude, longitude: longitude)
        )
    }

    // MARK: Gaps of up to 5 seconds

    @Test(arguments: [Channel.altitude, .distance, .heartRate])
    func gapOfFiveSecondsIsFilledLinearly(_ channel: Channel) throws {
        // Values at seconds 0 and 6, so seconds 1 to 5 are a 5 s gap.
        let samples = [Self.sample(0, channel, 100), Self.sample(6, channel, 160)]
        let stream = try Synthetic.stream(Synthetic.activity(elapsed: 7, samples: samples))
        // Six equal steps from 100 to 160: (160 - 100) / 6 = 10 a second.
        expectValues(stream[channel], [100, 110, 120, 130, 140, 150, 160])
        #expect(stream[channel].quality == [
            measured, interpolated, interpolated, interpolated, interpolated, interpolated, measured,
        ])
    }

    @Test func gapOfFiveSecondsInPositionIsFilledLinearly() throws {
        let samples = [Self.position(0, 10.000, 20.000), Self.position(6, 10.006, 20.012)]
        let stream = try Synthetic.stream(Synthetic.activity(elapsed: 7, samples: samples))
        // Latitude steps (10.006 - 10.000) / 6 = 0.001 a second.
        expectValues(stream.latitude, [10.000, 10.001, 10.002, 10.003, 10.004, 10.005, 10.006])
        // Longitude steps (20.012 - 20.000) / 6 = 0.002 a second.
        expectValues(stream.longitude, [20.000, 20.002, 20.004, 20.006, 20.008, 20.010, 20.012])
        // Latitude and longitude share one quality per second.
        let quality = [measured, interpolated, interpolated, interpolated, interpolated, interpolated, measured]
        #expect(stream.latitude.quality == quality)
        #expect(stream.longitude.quality == quality)
    }

    @Test(arguments: [Channel.power, .cadence])
    func gapOfFiveSecondsHoldsTheLastValue(_ channel: Channel) throws {
        let samples = [Self.sample(0, channel, 200), Self.sample(6, channel, 100)]
        let stream = try Synthetic.stream(Synthetic.activity(elapsed: 7, samples: samples))
        // Seconds 1 to 5 repeat the 200 from second 0. No line towards 100.
        expectValues(stream[channel], [200, 200, 200, 200, 200, 200, 100])
        #expect(stream[channel].quality == [
            measured, interpolated, interpolated, interpolated, interpolated, interpolated, measured,
        ])
    }

    // MARK: Longer gaps

    @Test(arguments: [Channel.altitude, .distance, .heartRate, .power, .cadence])
    func gapOfSixSecondsIsMissingThroughout(_ channel: Channel) throws {
        // Values at seconds 0 and 7, so seconds 1 to 6 are a 6 s gap.
        let samples = [Self.sample(0, channel, 100), Self.sample(7, channel, 160)]
        let stream = try Synthetic.stream(Synthetic.activity(elapsed: 8, samples: samples))
        // No part of a longer gap is filled, not even its first 5 seconds.
        expectValues(stream[channel], [100, nil, nil, nil, nil, nil, nil, 160])
        #expect(stream[channel].quality == [
            measured, missing, missing, missing, missing, missing, missing, measured,
        ])
    }

    @Test func gapOfSixSecondsInPositionIsMissingThroughout() throws {
        let samples = [Self.position(0, 10.000, 20.000), Self.position(7, 10.007, 20.014)]
        let stream = try Synthetic.stream(Synthetic.activity(elapsed: 8, samples: samples))
        #expect(stream.latitude.presentSeconds == [0, 7])
        #expect(stream.longitude.presentSeconds == [0, 7])
        #expect(stream.coordinate(at: 3) == nil)
    }

    /// Reading: a gap has a value on each side. The run before a channel's
    /// first value and the run after its last are not gaps, so they stay
    /// missing however short they are, for hold-last channels too.
    @Test(arguments: [Channel.heartRate, .power])
    func runsBeforeTheFirstValueAndAfterTheLastAreNotFilled(_ channel: Channel) throws {
        let samples = [2, 3, 4].map { Self.sample($0, channel, 100) }
        let stream = try Synthetic.stream(Synthetic.activity(elapsed: 8, samples: samples))
        // Seconds 0 to 1 (2 s) and 5 to 7 (3 s) are each under 5 s but one-sided.
        expectValues(stream[channel], [nil, nil, 100, 100, 100, nil, nil, nil])
    }

    /// Reading: the spec names a fill for six channels and none for
    /// temperature, so temperature is not filled.
    @Test func temperatureIsNotFilled() throws {
        let samples = [Self.sample(0, .temperature, 20), Self.sample(3, .temperature, 23)]
        let stream = try Synthetic.stream(Synthetic.activity(elapsed: 4, samples: samples))
        expectValues(stream.temperature, [20, nil, nil, 23])
        #expect(stream.temperature.quality == [measured, missing, missing, measured])
    }

    /// Reading: recorded speed is not filled from its own neighbours. With no
    /// distance and no position to fall back on, the seconds between stay
    /// missing.
    @Test func recordedSpeedIsNotFilledFromItsNeighbours() throws {
        let samples = [Self.sample(0, .speed, 5), Self.sample(3, .speed, 8)]
        let stream = try Synthetic.stream(Synthetic.activity(elapsed: 4, samples: samples))
        expectValues(stream.speed, [5, nil, nil, 8])
    }

    // MARK: Missing is never zero

    @Test func recordedZeroIsMeasuredAndNoReadingIsMissing() throws {
        // Coasting for 3 s with 0 W and 0 rpm recorded, then 3 s with no
        // power or cadence field at all. Heart rate is on every sample.
        let samples = (0..<6).map { second in
            NativeSample(
                timestamp: Synthetic.at(Double(second)),
                heartRate: 120,
                power: second < 3 ? 0 : nil,
                cadence: second < 3 ? 0 : nil
            )
        }
        let stream = try Synthetic.stream(Synthetic.activity(elapsed: 6, samples: samples))
        expectValues(stream.power, [0, 0, 0, nil, nil, nil])
        #expect(stream.power.quality == [measured, measured, measured, missing, missing, missing])
        expectValues(stream.cadence, [0, 0, 0, nil, nil, nil])
        #expect(stream.cadence.quality == [measured, measured, measured, missing, missing, missing])
    }

    // MARK: Sensor dropouts

    @Test func sensorDropoutAffectsOnlyItsOwnChannel() throws {
        // 30 s at 1 Hz. The power meter drops out for seconds 10 to 19, while
        // heart rate carries on.
        let samples = (0..<30).map { second in
            NativeSample(
                timestamp: Synthetic.at(Double(second)),
                heartRate: 120,
                power: (10..<20).contains(second) ? nil : 200
            )
        }
        let stream = try Synthetic.stream(Synthetic.activity(elapsed: 30, samples: samples))
        // A 10 s dropout is longer than 5 s, so power is missing for all of it.
        #expect(stream.power.presentSeconds == Array(0..<10) + Array(20..<30))
        // Heart rate is untouched.
        #expect(stream.heartRate.quality == Array(repeating: measured, count: 30))
    }

    @Test func sensorDropoutNeverShortensTheActivity() throws {
        // Stated to last 60 s, but every sensor stops after second 19.
        let samples = (0..<20).map {
            NativeSample(timestamp: Synthetic.at(Double($0)), heartRate: 120, power: 200)
        }
        let stream = try Synthetic.stream(Synthetic.activity(elapsed: 60, samples: samples))
        #expect(stream.count == 60)
        #expect(stream.isConsistent)
        #expect(stream.heartRate.presentSeconds == Array(0..<20))
        #expect(stream.power.presentSeconds == Array(0..<20))
    }

    @Test func gapInTheSamplesIsNotAPause() throws {
        // Nothing recorded from second 10 to second 39, and no timer events.
        // Stated timer time equals elapsed time.
        let samples = (Array(0..<10) + Array(40..<50)).map {
            NativeSample(timestamp: Synthetic.at(Double($0)), heartRate: 120)
        }
        let stream = try Synthetic.stream(Synthetic.activity(elapsed: 50, samples: samples))
        #expect(stream.count == 50)
        // Only timer events create pauses.
        #expect(stream.pauses == .known(paused: []))
    }

    // MARK: Pause boundaries

    /// Ten seconds of every fillable channel, a 4 s hole, then six more.
    private static let aroundAHole: [NativeSample] = (Array(0...9) + Array(14...19)).map { second in
        let s = Double(second)
        return NativeSample(
            timestamp: Synthetic.at(s),
            position: Coordinate(latitude: 10 + 0.001 * s, longitude: 20),
            altitude: 50 + s,
            distance: 10 * s,
            heartRate: 100 + s,
            power: second < 10 ? 200 : 260,
            cadence: second < 10 ? 80 : 90
        )
    }

    private static let fillable: [Channel] = [
        .latitude, .longitude, .altitude, .distance, .heartRate, .power, .cadence,
    ]

    /// The control for the next test: the same samples with no pause.
    @Test func fourSecondHoleIsFilledWhenThereIsNoPause() throws {
        let stream = try Synthetic.stream(Synthetic.activity(elapsed: 20, samples: Self.aroundAHole))
        for channel in Self.fillable {
            #expect(stream[channel].quality[10...13].allSatisfy { $0 == interpolated }, "\(channel)")
        }
        // Heart rate 109 at second 9 and 114 at second 14: 1 a second.
        #expect(isClose(stream.heartRate[10], 110))
        #expect(isClose(stream.heartRate[13], 113))
        // Power holds the 200 from second 9.
        #expect(stream.power[10] == 200)
        #expect(stream.power[13] == 200)
    }

    @Test func nothingIsFilledAcrossAPause() throws {
        // The timer stops at 11 s and starts again at 13 s, inside the hole
        // between the reading at second 9 and the reading at second 14.
        let events = [Synthetic.event(.start, 0), Synthetic.event(.stop, 11), Synthetic.event(.start, 13)]
        let stream = try Synthetic.stream(
            Synthetic.activity(elapsed: 20, events: events, samples: Self.aroundAHole)
        )
        #expect(stream.pauses == .known(paused: [11..<13]))
        // The hole is only 4 s, but the values each side of the pause stand alone.
        for channel in Self.fillable {
            #expect(stream[channel].presentSeconds == Array(0...9) + Array(14...19), "\(channel)")
        }
        // The readings either side are still measured, with their own values.
        #expect(stream.heartRate[9] == 109)
        #expect(stream.heartRate[14] == 114)
        #expect(stream.power[9] == 200)
        #expect(stream.power[14] == 260)
    }

    @Test func gapsThatDoNotTouchAPauseAreStillFilled() throws {
        // Paused from 10 s to 15 s. Heart rate has a 2 s gap before the pause
        // (seconds 1 and 2) and a 2 s gap after it (seconds 17 and 18).
        let events = [Synthetic.event(.start, 0), Synthetic.event(.stop, 10), Synthetic.event(.start, 15)]
        let readings: [(Double, Double)] = [
            (0, 100), (3, 106), (4, 108), (5, 110), (6, 112), (7, 114), (8, 116), (9, 118),
            (15, 118), (16, 120), (19, 126),
        ]
        let samples = readings.map { Self.sample($0.0, .heartRate, $0.1) }
        let stream = try Synthetic.stream(Synthetic.activity(elapsed: 20, events: events, samples: samples))
        // 100 to 106 over 3 s is 2 a second: 102, 104.
        #expect(isClose(stream.heartRate[1], 102))
        #expect(isClose(stream.heartRate[2], 104))
        #expect(stream.heartRate.quality[1...2].allSatisfy { $0 == interpolated })
        // 120 to 126 over 3 s is 2 a second: 122, 124.
        #expect(isClose(stream.heartRate[17], 122))
        #expect(isClose(stream.heartRate[18], 124))
        #expect(stream.heartRate.quality[17...18].allSatisfy { $0 == interpolated })
        // Seconds 10 to 14 lie between readings on opposite sides of the pause.
        #expect(stream.heartRate.quality[10...14].allSatisfy { $0 == missing })
    }

    /// "Paused spans stay in elapsed time": the grid keeps its length, and a
    /// sample recorded while paused keeps its place on it.
    @Test func samplesRecordedDuringAPauseStayOnTheGrid() throws {
        // Paused from 5 s to 10 s, with one stray reading at 7 s.
        let events = [Synthetic.event(.start, 0), Synthetic.event(.stop, 5), Synthetic.event(.start, 10)]
        let seconds = Array(0...4) + [7] + Array(10...14)
        let samples = seconds.map { Self.sample(Double($0), .heartRate, $0 == 7 ? 77 : 120) }
        let stream = try Synthetic.stream(Synthetic.activity(elapsed: 15, events: events, samples: samples))
        #expect(stream.count == 15)
        #expect(stream.pauses == .known(paused: [5..<10]))
        #expect(stream.heartRate[7] == 77)
        #expect(stream.heartRate.quality[7] == measured)
        // Seconds 5, 6, 8 and 9 lie between a reading inside the pause and one
        // outside it, so nothing is filled across either boundary.
        #expect(stream.heartRate.presentSeconds == [0, 1, 2, 3, 4, 7, 10, 11, 12, 13, 14])
    }

    // MARK: Irregular recording intervals

    @Test func irregularIntervalsFillShortGapsAndKeepTheGrid() throws {
        // Readings at 0, 1, 3, 4.5, 8 and 14 s, as smart recording writes them.
        let readings: [(time: Double, heartRate: Double, power: Double)] = [
            (0, 100, 200), (1, 102, 210), (3, 106, 190), (4.5, 110, 0), (8, 118, 250), (14, 130, 240),
        ]
        let samples = readings.map {
            NativeSample(timestamp: Synthetic.at($0.time), heartRate: $0.heartRate, power: $0.power)
        }
        let stream = try Synthetic.stream(Synthetic.activity(elapsed: 15, samples: samples))
        #expect(stream.count == 15)

        // Measured seconds: 0, 1, 3, 4 (4.5 s is inside second 4), 8 and 14.
        // Gaps: second 2 (1 s), seconds 5 to 7 (3 s), seconds 9 to 13 (5 s).
        let quality = [
            measured, measured, interpolated, measured, measured,
            interpolated, interpolated, interpolated, measured,
            interpolated, interpolated, interpolated, interpolated, interpolated, measured,
        ]

        // Heart rate, linear in grid seconds:
        //   second 2: halfway from 102 to 106 = 104
        //   seconds 5 to 7: 110 to 118 over 4 s is 2 a second = 112, 114, 116
        //   seconds 9 to 13: 118 to 130 over 6 s is 2 a second = 120 ... 128
        expectValues(
            stream.heartRate,
            [100, 102, 104, 106, 110, 112, 114, 116, 118, 120, 122, 124, 126, 128, 130]
        )
        #expect(stream.heartRate.quality == quality)

        // Power holds the value before each gap. The held 0 W is a value.
        expectValues(
            stream.power,
            [200, 210, 210, 190, 0, 0, 0, 0, 250, 250, 250, 250, 250, 250, 240]
        )
        #expect(stream.power.quality == quality)
    }
}
