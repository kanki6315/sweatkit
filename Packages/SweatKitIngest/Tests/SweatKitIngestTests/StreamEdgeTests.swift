import Foundation
import SweatKitIngest
import SweatKitModel
import Testing

/// Rules of the normaliser that the first round of stream tests left open.
///
/// Each expected value is worked out in the comment beside it, before the
/// implementation was run: from the spec's "Stream rules" where they decide
/// the case, and otherwise from the reading written in `StreamNormaliser`'s
/// doc comment, which the test then names as a reading.
@Suite struct StreamEdgeTests {
    private func heartRate(_ second: TimeInterval, _ value: Double) -> NativeSample {
        NativeSample(timestamp: Synthetic.at(second), heartRate: value)
    }

    // MARK: Elapsed time

    /// The start and the end are the same instant, so elapsed time is 0 s and
    /// the grid has no seconds. That is still a start and an end, so it is a
    /// stream and not nil.
    @Test func activityOfNoLengthIsAnEmptyStream() throws {
        let stream = try Synthetic.stream(Synthetic.activity(elapsed: 0, samples: [heartRate(0, 120)]))
        #expect(stream.start == Synthetic.start)
        // 0 s of elapsed time is 0 samples. The one sample sits on the end.
        #expect(stream.count == 0)
        #expect(stream.isConsistent)
    }

    @Test func singleSampleWithNothingStatedIsAnEmptyStream() throws {
        // The first sample and the last sample are the same one, at 7 s:
        // last - first = 0 s.
        let activity = RecordedActivity(sport: .cycling, stream: NativeStream(samples: [heartRate(7, 120)]))
        let stream = try Synthetic.stream(activity)
        #expect(stream.start == Synthetic.at(7))
        #expect(stream.count == 0)
        #expect(stream.isConsistent)
    }

    @Test func statedEndBeforeTheStatedStartGivesNoStream() {
        // End 10 s before the start: there is no elapsed time to put a grid on.
        let activity = RecordedActivity(
            sport: .cycling,
            stated: StatedSummary(start: Synthetic.at(10), end: Synthetic.start, timerTime: 10),
            stream: NativeStream(samples: [heartRate(0, 120), heartRate(5, 120)])
        )
        #expect(StreamNormaliser.analysisStream(from: activity) == nil)
    }

    // MARK: Order of the samples

    /// "A native sample belongs to the grid second that contains its
    /// timestamp." Nothing in that depends on where the sample sits in the
    /// stream, so the same samples in reverse give the same grid.
    @Test func samplesOutOfTimeOrderLandOnTheSameSeconds() throws {
        // The readings of `irregularIntervalsFillShortGapsAndKeepTheGrid`,
        // last one first.
        let readings: [(time: Double, heartRate: Double, power: Double)] = [
            (14, 130, 240), (8, 118, 250), (4.5, 110, 0), (3, 106, 190), (1, 102, 210), (0, 100, 200),
        ]
        let samples = readings.map {
            NativeSample(timestamp: Synthetic.at($0.time), heartRate: $0.heartRate, power: $0.power)
        }
        let stream = try Synthetic.stream(Synthetic.activity(elapsed: 15, samples: samples))
        // Measured seconds: 0, 1, 3, 4 (4.5 s), 8 and 14, as in time order.
        //   second 2: halfway from 102 to 106 = 104
        //   seconds 5 to 7: 110 to 118 over 4 s is 2 a second = 112, 114, 116
        //   seconds 9 to 13: 118 to 130 over 6 s is 2 a second = 120 ... 128
        expectValues(
            stream.heartRate,
            [100, 102, 104, 106, 110, 112, 114, 116, 118, 120, 122, 124, 126, 128, 130]
        )
        // Power holds the value of the second before each gap, which is the
        // earlier second on the grid, not the earlier sample in the stream.
        expectValues(
            stream.power,
            [200, 210, 210, 190, 0, 0, 0, 0, 250, 250, 250, 250, 250, 250, 240]
        )
    }

    /// Reading: the first and last samples of the fallback are the earliest
    /// and the latest by timestamp.
    @Test func fallbackUsesTheEarliestAndLatestSamples() throws {
        // Nothing stated. Samples at 10, 9, ... 0 s with heart rate 110 ... 100.
        let activity = RecordedActivity(
            sport: .cycling,
            stream: NativeStream(samples: (0...10).reversed().map { heartRate(Double($0), 100 + Double($0)) })
        )
        let stream = try Synthetic.stream(activity)
        // Earliest 0 s, latest 10 s: 10 samples from the earliest.
        #expect(stream.start == Synthetic.start)
        #expect(stream.count == 10)
        expectValues(stream.heartRate, [100, 101, 102, 103, 104, 105, 106, 107, 108, 109])
    }

    // MARK: Gaps and pauses

    /// "Nothing is interpolated across a pause boundary." A gap between two
    /// readings that were both taken during one pause crosses no boundary, so
    /// "gaps of up to 5 seconds are filled" still holds for it.
    @Test func gapWhollyInsideAPausedSpanIsFilled() throws {
        // Paused from 5 s to 15 s. Readings at 7 s and 11 s fall inside it.
        let events = [Synthetic.event(.start, 0), Synthetic.event(.stop, 5), Synthetic.event(.start, 15)]
        let readings: [(Double, Double)] =
            (0...4).map { (Double($0), 120) } + [(7, 77), (11, 85)] + (15...19).map { (Double($0), 120) }
        let samples = readings.map { heartRate($0.0, $0.1) }
        let stream = try Synthetic.stream(Synthetic.activity(elapsed: 20, events: events, samples: samples))
        #expect(stream.pauses == .known(paused: [5..<15]))
        // Seconds 8 to 10 are a 3 s gap between 77 and 85, with no span
        // starting or ending between second 7 and second 11:
        // (85 - 77) / 4 = 2 a second, so 79, 81, 83.
        #expect(isClose(stream.heartRate[8], 79))
        #expect(isClose(stream.heartRate[9], 81))
        #expect(isClose(stream.heartRate[10], 83))
        #expect(stream.heartRate.quality[8...10].allSatisfy { $0 == interpolated })
        // Seconds 5 and 6 lie across the pause's start at 5, and seconds 12
        // to 14 across its end at 15, so they stay missing.
        #expect(stream.heartRate.presentSeconds == Array(0...4) + Array(7...11) + Array(15...19))
    }

    /// Reading: with incomplete pause data no pause boundary is known, so
    /// gaps are filled as they are with no pauses.
    @Test func gapsAreFilledWhenPausePositionsAreUnknown() throws {
        // A stop at 3 s with no matching start, while samples carry on:
        // incomplete pause data. Heart rate has a hole at seconds 5 and 6.
        let events = [Synthetic.event(.start, 0), Synthetic.event(.stop, 3)]
        let readings: [(Double, Double)] = [
            (0, 100), (1, 102), (2, 104), (3, 106), (4, 108), (7, 114), (8, 116), (9, 118),
        ]
        let samples = readings.map { heartRate($0.0, $0.1) }
        let stream = try Synthetic.stream(Synthetic.activity(elapsed: 10, events: events, samples: samples))
        // `Synthetic.activity` states a timer time equal to elapsed time.
        #expect(stream.pauses == .unknown(statedTimerTime: 10))
        // 108 to 114 over 3 s is 2 a second: 110, 112.
        expectValues(stream.heartRate, [100, 102, 104, 106, 108, 110, 112, 114, 116, 118])
        #expect(stream.heartRate.quality[5...6].allSatisfy { $0 == interpolated })
    }

    // MARK: Speed

    /// "Several native samples in one second are averaged", for recorded
    /// speed as for any channel.
    @Test func recordedSpeedsInOneSecondAreAveraged() throws {
        let samples = [
            NativeSample(timestamp: Synthetic.at(2), speed: 4),
            NativeSample(timestamp: Synthetic.at(2.5), speed: 6),
        ]
        let stream = try Synthetic.stream(Synthetic.activity(elapsed: 4, samples: samples))
        // (4 + 6) / 2 = 5.
        expectValues(stream.speed, [nil, nil, 5, nil])
        #expect(stream.speed.quality[2] == measured)
    }

    /// Reading: a fall in distance is not a speed, so that second goes on to
    /// position. The spec does not say what a falling distance means.
    @Test func fallInDistanceGoesOnToPosition() throws {
        // Distance 0, 10, 20, 15, 25, 35 m: it falls 5 m from second 2 to 3.
        // Position moves 0.0001 degrees of latitude a second, which is
        // 0.0001 x pi / 180 x 6,371,009 m = 11.12 m.
        let distances: [Double] = [0, 10, 20, 15, 25, 35]
        let samples = distances.enumerated().map { second, distance in
            NativeSample(
                timestamp: Synthetic.at(Double(second)),
                position: Coordinate(latitude: 10 + 0.0001 * Double(second), longitude: 20),
                distance: distance
            )
        }
        let stream = try Synthetic.stream(Synthetic.activity(elapsed: 6, samples: samples))
        // Seconds 0, 1, 3 and 4 gain 10 m each. Second 2 would be -5 m/s.
        for second in [0, 1, 3, 4] {
            #expect(isClose(stream.speed[second], 10), "second \(second)")
        }
        #expect(isClose(stream.speed[2], 11.12, tolerance: 0.11))
        // Second 5 has nothing ahead of it in either channel.
        #expect(stream.speed[5] == nil)
    }

    /// Reading: with no position to go on to, the second of a fall in
    /// distance has no speed. It is never negative and never zero.
    @Test func fallInDistanceWithNoPositionIsMissing() throws {
        let distances: [Double] = [0, 10, 20, 15, 25, 35]
        let samples = distances.enumerated().map {
            NativeSample(timestamp: Synthetic.at(Double($0.offset)), distance: $0.element)
        }
        let stream = try Synthetic.stream(Synthetic.activity(elapsed: 6, samples: samples))
        expectValues(stream.speed, [10, 10, nil, 10, 10, nil])
    }

    /// Reading: a speed that leans on a filled position is interpolated, as
    /// for distance.
    @Test func speedFromFilledPositionIsInterpolated() throws {
        // Positions at seconds 0, 1, 4, 5 and 6, each 0.0001 degrees of
        // latitude a second further north. Seconds 2 and 3 are a 2 s gap,
        // filled linearly, so the steps stay 0.0001 degrees: 11.12 m.
        let samples = [0, 1, 4, 5, 6].map { second in
            NativeSample(
                timestamp: Synthetic.at(Double(second)),
                position: Coordinate(latitude: 10 + 0.0001 * Double(second), longitude: 20)
            )
        }
        let stream = try Synthetic.stream(Synthetic.activity(elapsed: 7, samples: samples))
        for second in 0...5 {
            #expect(isClose(stream.speed[second], 11.12, tolerance: 0.11), "second \(second)")
        }
        // Second 0 uses seconds 0 and 1, both measured. Seconds 1, 2 and 3
        // each use at least one of the filled seconds 2 and 3. Seconds 4 and
        // 5 are measured, and second 6 has nothing ahead of it.
        #expect(stream.speed.quality == [
            measured, interpolated, interpolated, interpolated, measured, measured, missing,
        ])
    }

    // MARK: Gradient

    private func normalised(
        count: Int,
        events: [TimerEvent] = [],
        distance: (Double) -> Double?,
        altitude: (Double) -> Double?
    ) throws -> AnalysisStream {
        let samples = (0..<count).map { second in
            let s = Double(second)
            return NativeSample(timestamp: Synthetic.at(s), altitude: altitude(s), distance: distance(s))
        }
        return try Synthetic.stream(Synthetic.activity(elapsed: Double(count), events: events, samples: samples))
    }

    /// Reading: the window stops at missing data. It does not reach across a
    /// dropout to the altitude on the far side.
    ///
    /// 5 m/s throughout. Altitude is flat at 0 up to second 7 (35 m), missing
    /// for seconds 8 to 15 (an 8 s gap, too long to fill), and from second 16
    /// (80 m) a 10% ramp starting at 10 m: 10 + 0.5 a second.
    @Test func gradientWindowStopsAtMissingAltitude() throws {
        let stream = try normalised(
            count: 20,
            distance: { 5 * $0 },
            altitude: { $0 <= 7 ? 0 : ($0 <= 15 ? nil : 10 + 0.5 * ($0 - 16)) }
        )
        // Second 5, at 25 m: window 10 to 40 m, cut to 10 to 35 m. Flat: 0 / 25.
        #expect(isClose(stream.gradient[5], 0))
        // Second 7, at 35 m: window 20 to 50 m, cut to 20 to 35 m. Flat: 0 / 15.
        // Reaching on to second 16 would read 10 m of climb.
        #expect(isClose(stream.gradient[7], 0))
        #expect(stream.gradient.quality[7] == measured)
        #expect(stream.gradient.quality[8...15].allSatisfy { $0 == missing })
        // Second 16, at 80 m: window 65 to 95 m, cut to 80 to 95 m.
        // Altitude 10 to 11.5: 1.5 / 15 = 0.1.
        #expect(isClose(stream.gradient[16], 0.1))
        #expect(stream.gradient.quality[16] == measured)
        // Second 19, at 95 m: window 80 to 110 m, cut to the same 80 to 95 m.
        #expect(isClose(stream.gradient[19], 0.1))
    }

    /// "Missing ... when the window covers less than 5 m of travel." Reading:
    /// the window stops at missing data, so a lone second of altitude between
    /// two dropouts has a window of 0 m.
    @Test func loneSecondOfAltitudeBetweenDropoutsHasNoGradient() throws {
        // 5 m/s on a steady 5% climb: 0.25 m a second. Altitude is recorded
        // on seconds 0 to 3, on second 10 alone, and on seconds 17 to 19. The
        // holes at 4 to 9 and 11 to 16 are 6 s each, too long to fill.
        let stream = try normalised(
            count: 20,
            distance: { 5 * $0 },
            altitude: { second in
                let s = Int(second)
                return (0...3).contains(s) || s == 10 || (17...19).contains(s) ? 100 + 0.25 * second : nil
            }
        )
        // Seconds 0 to 3 share 15 m of road and seconds 17 to 19 share 10 m,
        // both over 5 m, and on a constant slope any window gives 0.05.
        // Second 10 has altitude but no road on either side.
        let slope: [Double?] = Array(repeating: 0.05, count: 4)
            + Array(repeating: nil, count: 13)
            + Array(repeating: 0.05, count: 3)
        expectValues(stream.gradient, slope)
        #expect(stream.altitude[10] != nil)
    }

    /// Reading: paused spans do not cut the window. Only missing data does.
    ///
    /// 5 m/s for 10 s to 50 m, 5 s standing at 50 m with the timer stopped
    /// and the device still recording, then 5 m/s again. The road is flat up
    /// to 50 m and a 10% ramp after it.
    @Test func pauseDoesNotCutTheGradientWindow() throws {
        let events = [Synthetic.event(.start, 0), Synthetic.event(.stop, 10), Synthetic.event(.start, 15)]
        let distance: (Double) -> Double = { $0 <= 10 ? 5 * $0 : ($0 <= 15 ? 50 : 50 + 5 * ($0 - 15)) }
        let stream = try normalised(
            count: 21,
            events: events,
            distance: distance,
            altitude: { max(0, 0.1 * (distance($0) - 50)) }
        )
        #expect(stream.pauses == .known(paused: [10..<15]))
        // Second 9, at 45 m: window 30 to 60 m.
        //   30 m is second 6, on the flat: 0.
        //   60 m is second 17, after the pause: 0.1 x (60 - 50) = 1.
        //   1 / 30. Cut at the pause, the window would be all flat: 0.
        #expect(isClose(stream.gradient[9], 1.0 / 30))
        // Second 16, at 55 m: window 40 to 70 m.
        //   40 m is second 8, before the pause: 0.
        //   70 m is second 19: 0.1 x (70 - 50) = 2.
        //   2 / 30. Cut at the pause, it would be all ramp: 0.1.
        #expect(isClose(stream.gradient[16], 2.0 / 30))
    }

    /// Reading: where several seconds share one distance, a window end at
    /// that distance reads the altitude of the second nearest in time to the
    /// sample. The spec does not say which.
    ///
    /// 5 m/s to 50 m at second 10, standing there until second 14 while the
    /// altimeter drifts up 1 m a second from 0 to 4 m, then 5 m/s again with
    /// altitude steady at 4 m.
    @Test func windowEndAtAStandstillReadsTheNearestSecond() throws {
        let stream = try normalised(
            count: 21,
            distance: { $0 <= 10 ? 5 * $0 : ($0 <= 14 ? 50 : 50 + 5 * ($0 - 14)) },
            altitude: { min(4, max(0, $0 - 10)) }
        )
        // Second 7, at 35 m: window 20 to 50 m. Going forward, 50 m is first
        // reached at second 10, altitude 0. 20 m is second 4, altitude 0.
        // 0 / 30 = 0: the drift to come is not in it.
        #expect(isClose(stream.gradient[7], 0))
        // Second 17, at 65 m: window 50 to 80 m. Going back, 50 m is first
        // reached at second 14, altitude 4. 80 m is second 20, altitude 4.
        // 0 / 30 = 0: the drift behind is not in it.
        #expect(isClose(stream.gradient[17], 0))
        // Second 12, standing at 50 m: window 35 to 65 m.
        //   35 m is second 7, altitude 0. 65 m is second 17, altitude 4.
        //   4 / 30: the whole drift, spread over the 30 m around it.
        #expect(isClose(stream.gradient[12], 4.0 / 30))
    }

    /// Reading: a gradient's quality follows the altitude at its own second,
    /// whatever its window leans on.
    @Test func measuredSecondBesideFilledAltitudeIsStillMeasured() throws {
        // The steady 5% climb at 5 m/s, with no samples for seconds 8 and 9.
        // Second 7, at 35 m, has a window of 20 to 50 m, which is seconds 4
        // to 10 and so includes both filled seconds.
        let samples = (0..<20).filter { $0 != 8 && $0 != 9 }.map { second in
            let s = Double(second)
            return NativeSample(timestamp: Synthetic.at(s), altitude: 100 + 0.25 * s, distance: 5 * s)
        }
        let stream = try Synthetic.stream(Synthetic.activity(elapsed: 20, samples: samples))
        #expect(stream.altitude.quality[8] == interpolated)
        #expect(stream.gradient.quality[7] == measured)
        #expect(stream.gradient.quality[10] == measured)
    }
}
