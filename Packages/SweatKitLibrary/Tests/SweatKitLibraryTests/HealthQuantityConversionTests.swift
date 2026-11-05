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


    @Test func cadenceUsesIntervalDurationAndRejectsLongAggregates() {
        let points = HealthQuantityConversion.cadence([interval(0, 2, 4), interval(5, 65, 100)])
        #expect(points.count == 2)
        #expect(points.allSatisfy { $0.cadence == 120 })
        #expect(points.last?.timestamp == start.addingTimeInterval(1))
    }
}
