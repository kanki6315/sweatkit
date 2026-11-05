import Foundation
import SweatKitIngest
import SweatKitModel
import Testing

/// Stream rules 1 and 2: the 1 Hz grid over elapsed time, which second a
/// sample belongs to, and averaging within a second. Also elapsed time from
/// the "Time" table: the stated start and end, with the first and last
/// samples as the fallback.
@Suite struct StreamGridTests {
    private func heartRate(_ second: TimeInterval, _ value: Double) -> NativeSample {
        NativeSample(timestamp: Synthetic.at(second), heartRate: value)
    }

    // MARK: Elapsed time

    @Test func gridStartsAtTheStatedStartAndCoversStatedElapsedTime() throws {
        let stream = try Synthetic.stream(Synthetic.activity(elapsed: 100, samples: [heartRate(0, 120)]))
        #expect(stream.start == Synthetic.start)
        // Stated end - stated start = 100 s, so 100 samples.
        #expect(stream.count == 100)
        #expect(stream.isConsistent)
    }

    @Test func streamCarriesTheRulesVersion() throws {
        let stream = try Synthetic.stream(Synthetic.activity(elapsed: 10, samples: [heartRate(0, 120)]))
        #expect(stream.rulesVersion == StreamRules.version)
    }

    /// Reading: the grid covers the whole of elapsed time, so a part second
    /// at the end gets a grid second of its own.
    @Test func partSecondOfElapsedTimeIsRoundedUp() throws {
        let activity = RecordedActivity(
            sport: .cycling,
            stated: StatedSummary(start: Synthetic.start, end: Synthetic.at(100.5), timerTime: 100.5),
            stream: NativeStream(samples: [heartRate(0, 120)])
        )
        // 100.5 s needs 101 whole seconds to cover it.
        #expect(try Synthetic.stream(activity).count == 101)
    }

    @Test func elapsedTimeFallsBackToTheFirstAndLastSamples() throws {
        // Nothing stated. Samples at 0, 1, ... 10 s with heart rate 100, 101, ... 110.
        let activity = RecordedActivity(
            sport: .cycling,
            stream: NativeStream(samples: (0...10).map { heartRate(Double($0), 100 + Double($0)) })
        )
        let stream = try Synthetic.stream(activity)
        #expect(stream.start == Synthetic.start)
        // Last sample - first sample = 10 s, so 10 samples: seconds 0 to 9.
        // The sample at 10 s sits exactly on the end and is off the grid.
        #expect(stream.count == 10)
        expectValues(stream.heartRate, [100, 101, 102, 103, 104, 105, 106, 107, 108, 109])
        #expect(stream.heartRate.quality == Array(repeating: measured, count: 10))
    }

    /// Reading: the start and the end fall back separately.
    @Test func statedStartIsKeptWhenOnlyTheEndIsMissing() throws {
        // Start stated at 0 s. Samples at 5, 6, ... 20 s.
        let activity = RecordedActivity(
            sport: .cycling,
            stated: StatedSummary(start: Synthetic.start),
            stream: NativeStream(samples: (5...20).map { heartRate(Double($0), 120) })
        )
        let stream = try Synthetic.stream(activity)
        #expect(stream.start == Synthetic.start)
        // Last sample (20 s) - stated start (0 s) = 20 samples.
        #expect(stream.count == 20)
        // Seconds 0 to 4 have no sample. The sample at 20 s is on the end.
        #expect(stream.heartRate.presentSeconds == Array(5...19))
    }

    /// Reading: the start and the end fall back separately.
    @Test func statedEndIsKeptWhenOnlyTheStartIsMissing() throws {
        // End stated at 30 s. Samples at 5, 6, ... 20 s.
        let activity = RecordedActivity(
            sport: .cycling,
            stated: StatedSummary(end: Synthetic.at(30)),
            stream: NativeStream(samples: (5...20).map { heartRate(Double($0), 120) })
        )
        let stream = try Synthetic.stream(activity)
        // The first sample is the start.
        #expect(stream.start == Synthetic.at(5))
        // Stated end (30 s) - first sample (5 s) = 25 samples.
        #expect(stream.count == 25)
        // Samples at 5 to 20 s are grid seconds 0 to 15.
        #expect(stream.heartRate.presentSeconds == Array(0...15))
    }

    @Test func noStatedTimesAndNoSamplesGivesNoStream() {
        #expect(StreamNormaliser.analysisStream(from: RecordedActivity(sport: .cycling)) == nil)
    }

    @Test func statedStartAloneWithNoSamplesGivesNoStream() {
        let activity = RecordedActivity(sport: .cycling, stated: StatedSummary(start: Synthetic.start))
        #expect(StreamNormaliser.analysisStream(from: activity) == nil)
    }

    /// "Activity with no stream: all three times come from the stated
    /// metadata." The grid still spans elapsed time, with nothing on it.
    @Test func activityWithNoSamplesGetsAGridWithEveryChannelMissing() throws {
        let stream = try Synthetic.stream(Synthetic.activity(elapsed: 3600, samples: []))
        #expect(stream.count == 3600)
        #expect(stream.isConsistent)
        #expect(Channel.allCases.allSatisfy { stream[$0].presentSeconds.isEmpty })
        // No events, and stated timer time equals elapsed: treated as unpaused.
        #expect(stream.pauses == .known(paused: []))
    }

    // MARK: Which second a sample belongs to

    @Test func sampleBelongsToTheGridSecondThatContainsItsTimestamp() throws {
        // 2.75 s is inside second 2, 5.5 s inside second 5, and 7.0 s starts second 7.
        let samples = [heartRate(2.75, 100), heartRate(5.5, 130), heartRate(7, 150)]
        let stream = try Synthetic.stream(Synthetic.activity(elapsed: 8, samples: samples))
        // Seconds 3 and 4 are a 2 s gap between 100 and 130: 110, 120.
        // Second 6 is a 1 s gap between 130 and 150: 140.
        // Seconds 0 and 1 come before the first reading, so they are not a gap.
        expectValues(stream.heartRate, [nil, nil, 100, 110, 120, 130, 140, 150])
        #expect(stream.heartRate.quality == [
            missing, missing, measured, interpolated, interpolated, measured, interpolated, measured,
        ])
    }

    @Test func gridSecondsAreCountedFromTheStartEvenWhenItIsNotAWholeSecond() throws {
        // Start at 0.5 s. A sample at 1.25 s is 0.75 s in: second 0.
        // A sample at 1.5 s is exactly 1.0 s in: second 1.
        let activity = RecordedActivity(
            sport: .cycling,
            stated: StatedSummary(start: Synthetic.at(0.5), end: Synthetic.at(10.5), timerTime: 10),
            stream: NativeStream(samples: [heartRate(1.25, 100), heartRate(1.5, 110)])
        )
        let stream = try Synthetic.stream(activity)
        #expect(stream.start == Synthetic.at(0.5))
        #expect(stream.count == 10)
        expectValues(stream.heartRate, [100, 110, nil, nil, nil, nil, nil, nil, nil, nil])
    }

    /// Reading: the grid is fixed by the start and the end. A sample outside
    /// it, or stamped exactly on the end, is left off and never extends it.
    @Test func samplesOutsideTheStatedTimesAreLeftOffTheGrid() throws {
        let samples = [
            heartRate(-2, 90),   // before the start
            heartRate(0, 100),   // second 0
            heartRate(9, 109),   // second 9, the last one
            heartRate(10, 200),  // exactly on the end: second 10 does not exist
            heartRate(12, 210),  // after the end
        ]
        let stream = try Synthetic.stream(Synthetic.activity(elapsed: 10, samples: samples))
        #expect(stream.count == 10)
        // Seconds 1 to 8 are an 8 s gap, longer than 5 s, so they stay missing.
        expectValues(stream.heartRate, [100, nil, nil, nil, nil, nil, nil, nil, nil, 109])
    }

    // MARK: Averaging within a second

    @Test func severalSamplesInOneSecondAreAveragedPerChannel() throws {
        // Three samples inside second 3. The middle one has power only.
        let samples = [
            NativeSample(
                timestamp: Synthetic.at(3),
                position: Coordinate(latitude: 10.000, longitude: 20.000),
                heartRate: 120,
                power: 100
            ),
            NativeSample(timestamp: Synthetic.at(3.25), power: 200),
            NativeSample(
                timestamp: Synthetic.at(3.75),
                position: Coordinate(latitude: 10.002, longitude: 20.004),
                heartRate: 130,
                power: 300
            ),
        ]
        let stream = try Synthetic.stream(Synthetic.activity(elapsed: 5, samples: samples))
        // Power: (100 + 200 + 300) / 3 = 200.
        expectValues(stream.power, [nil, nil, nil, 200, nil])
        // Heart rate, over the two samples that have it: (120 + 130) / 2 = 125.
        expectValues(stream.heartRate, [nil, nil, nil, 125, nil])
        // Latitude (10.000 + 10.002) / 2 = 10.001. Longitude (20.000 + 20.004) / 2 = 20.002.
        expectValues(stream.latitude, [nil, nil, nil, 10.001, nil])
        expectValues(stream.longitude, [nil, nil, nil, 20.002, nil])
        // An average of recorded values is measured.
        #expect(stream.power.quality[3] == measured)
        #expect(stream.heartRate.quality[3] == measured)
        #expect(stream.latitude.quality[3] == measured)
        #expect(stream.longitude.quality[3] == measured)
    }

    @Test func recordingFasterThanOneHertzAveragesEachSecond() throws {
        // Two samples a second for 3 s: power 100, 110 | 120, 130 | 140, 150.
        let samples = (0..<6).map {
            NativeSample(timestamp: Synthetic.at(Double($0) / 2), power: 100 + 10 * Double($0))
        }
        let stream = try Synthetic.stream(Synthetic.activity(elapsed: 3, samples: samples))
        // (100 + 110) / 2 = 105, (120 + 130) / 2 = 125, (140 + 150) / 2 = 145.
        expectValues(stream.power, [105, 125, 145])
        #expect(stream.power.quality == [measured, measured, measured])
    }
}
