import Foundation
import Testing
import SweatKitLibrary
import SweatKitModel
import SweatKitIngest

@Suite struct HealthQuantityConversionTests {
    @Test func runningMetricsReachAnalysisWithoutFillingGaps() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let samples = [0.0, 2.0].map { offset in
            NativeSample(timestamp: start.addingTimeInterval(offset), runningStrideLength: 1.1,
                         runningGroundContactTime: 0.24, runningVerticalOscillation: 0.08)
        }
        let activity = RecordedActivity(sport: .running,
            stated: .init(start: start, end: start.addingTimeInterval(3)), stream: NativeStream(samples: samples))
        let stream = try #require(StreamNormaliser.analysisStream(from: activity))
        #expect(stream.runningStrideLength[0] == 1.1)
        #expect(stream.runningGroundContactTime[2] == 0.24)
        #expect(stream.runningVerticalOscillation[2] == 0.08)
        #expect(stream.runningStrideLength[1] == nil)
        #expect(stream.runningGroundContactTime[1] == nil)
        #expect(stream.runningVerticalOscillation[1] == nil)
    }

    let start = Date(timeIntervalSince1970: 1_700_000_000)
    func interval(_ a: Double, _ b: Double, _ value: Double) -> HealthQuantityInterval {
        .init(start: start.addingTimeInterval(a), end: start.addingTimeInterval(b), value: value)
    }

    @Test func distanceRestoresGradientThroughTheRealNormaliser() throws {
        let intervals = (0..<60).map { interval(Double($0), Double($0 + 1), 2) }
        let distance = HealthQuantityConversion.distance(intervals.reversed())
        let altitude = (0...60).map {
            NativeSample(timestamp: start.addingTimeInterval(Double($0)), altitude: 200 + Double($0) * 0.1)
        }
        let activity = RecordedActivity(sport: .running,
            stated: .init(start: start, end: start.addingTimeInterval(60)),
            stream: NativeStream(samples: (distance + altitude).sorted { $0.timestamp < $1.timestamp }))
        let stream = try #require(StreamNormaliser.analysisStream(from: activity))
        #expect(stream.distance[30] == 60)
        #expect(abs(try #require(stream.gradient[30]) - 0.05) < 0.00001)
        #expect(distance.last?.distance == 120)
    }

    @Test func missingDistanceIsNotInferredFromSummaryOrLongGaps() throws {
        #expect(HealthQuantityConversion.distance([]).isEmpty)
        let points = HealthQuantityConversion.distance([interval(0, 1, 2), interval(30, 31, 3)])
        let activity = RecordedActivity(sport: .walking,
            stated: .init(start: start, end: start.addingTimeInterval(32), distance: 100),
            stream: NativeStream(samples: points))
        let stream = try #require(StreamNormaliser.analysisStream(from: activity))
        #expect(stream.distance[15] == nil)
        #expect(stream.distance[31] == 5)
    }

    @Test func overlappingAndInvalidIntervalsCannotDoubleCountDistance() {
        #expect(HealthQuantityConversion.distance([interval(0, 3, 5), interval(2, 4, 4)]).isEmpty)
        #expect(HealthQuantityConversion.distance([interval(0, 1, -.infinity)]).isEmpty)
        #expect(HealthQuantityConversion.distance([interval(1, 1, 4)]).isEmpty)
    }


    @Test func sharedSubsecondBoundariesHaveOneVoteInGridAverage() throws {
        let points = HealthQuantityConversion.distance([interval(0, 0.25, 1), interval(0.25, 1, 3)])
        #expect(points.count == 3)
        let activity = RecordedActivity(sport: .running,
            stated: .init(start: start, end: start.addingTimeInterval(2)),
            stream: NativeStream(samples: points))
        let stream = try #require(StreamNormaliser.analysisStream(from: activity))
        // Unique observations in second 0 are 0 m and 1 m, hence 0.5 m.
        // The shared 1 m boundary must not be counted twice (giving 2/3 m).
        #expect(stream.distance[0] == 0.5)
        #expect(stream.distance[1] == 4)
    }

    @Test func sparseHeartRateFillsOnlyFiveMissingSeconds() throws {
        let points = [0.0, 6, 13].map {
            NativeSample(timestamp: start.addingTimeInterval($0), heartRate: 120 + $0)
        }
        let activity = RecordedActivity(sport: .running,
            stated: .init(start: start, end: start.addingTimeInterval(15), timerTime: 15),
            stream: NativeStream(samples: points))
        let stream = try #require(StreamNormaliser.analysisStream(from: activity))
        #expect(stream.heartRate[3] == 123)
        #expect(stream.heartRate.quality[3] == .interpolated)
        #expect((7..<13).allSatisfy { stream.heartRate[$0] == nil })
        #expect(stream.heartRate[14] == nil)
        #expect(stream.pauses == .known(paused: []))
    }

    @Test func cadenceUsesIntervalDurationAndRejectsLongAggregates() {
        let points = HealthQuantityConversion.cadence([interval(0, 2, 4), interval(5, 65, 100)])
        #expect(points.count == 2)
        #expect(points.allSatisfy { $0.cadence == 120 })
        #expect(points.last?.timestamp == start.addingTimeInterval(1))
    }
}
