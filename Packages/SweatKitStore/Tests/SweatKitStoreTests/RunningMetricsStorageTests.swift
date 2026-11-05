import Foundation
import SweatKitModel
@testable import SweatKitStore
import Testing

@Suite struct RunningMetricsStorageTests {
    let start = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func runningMetricsSurviveBothCacheFormats() throws {
        let sample = NativeSample(timestamp: start, runningStrideLength: 1.1,
                                  runningGroundContactTime: 0.245, runningVerticalOscillation: 0.08)
        let activity = RecordedActivity(sport: .running, stream: NativeStream(samples: [sample]))
        let recorded = try StreamFileFormat.encode(activity, decoderVersion: 1)
        #expect(try StreamFileFormat.decodeRecordedActivity(recorded).activity == activity)
        var stream = AnalysisStream(rulesVersion: 2, start: start, count: 3)
        stream.runningStrideLength = Series([1.1, nil, 1.2])
        stream.runningGroundContactTime = Series([0.245, nil, 0.25])
        stream.runningVerticalOscillation = Series([0.08, nil, 0.09])
        #expect(try StreamFileFormat.decodeAnalysisStream(StreamFileFormat.encode(stream)) == stream)
        #expect(try JSONDecoder().decode(RecordedActivity.self, from: JSONEncoder().encode(activity)) == activity)
    }

    @Test func versionOneFilesStillLoadWithoutInventingRunningMetrics() throws {
        let activity = RecordedActivity(sport: .walking, stream: NativeStream(samples: [NativeSample(timestamp: start, distance: 123)]))
        let encoded = try StreamFileFormat.encode(activity, decoderVersion: 1)
        // Version 1 has seven optional sample columns. Remove the three new
        // absent-column presence bytes and v3 segment flag to recreate the layout.
        let body = try StreamFileFormat.unwrap(encoded, content: .recordedActivity).body.dropLast(4)
        var legacy = try StreamFileFormat.wrap(Data(body), content: .recordedActivity, producerVersion: 1)
        legacy[4] = 1
        #expect(try StreamFileFormat.decodeRecordedActivity(legacy).activity == activity)
        let stream = AnalysisStream(rulesVersion: 1, start: start, count: 2)
        let analysis = try StreamFileFormat.encode(stream)
        let oldBody = try StreamFileFormat.unwrap(analysis, content: .analysisStream).body.dropLast(3 * (8 + 2 * 9))
        var oldAnalysis = try StreamFileFormat.wrap(Data(oldBody), content: .analysisStream, producerVersion: 1)
        oldAnalysis[4] = 1
        #expect(try StreamFileFormat.decodeAnalysisStream(oldAnalysis) == stream)
    }

    @Test func segmentsSurviveBinaryCacheAndVersionTwoRemainsReadable() throws {
        var activity = RecordedActivity(sport: .running,
            stream: NativeStream(samples: [NativeSample(timestamp: start, runningStrideLength: 1.1)]))
        let current = try StreamFileFormat.encode(activity, decoderVersion: 1)
        let body = try StreamFileFormat.unwrap(current, content: .recordedActivity).body.dropLast(1)
        var versionTwo = try StreamFileFormat.wrap(Data(body), content: .recordedActivity, producerVersion: 1)
        versionTwo[4] = 2
        #expect(try StreamFileFormat.decodeRecordedActivity(versionTwo).activity == activity)
        activity.segments = [RecordedLap(start: start, end: start.addingTimeInterval(30))]
        let encoded = try StreamFileFormat.encode(activity, decoderVersion: 1)
        #expect(try StreamFileFormat.decodeRecordedActivity(encoded).activity == activity)
    }

    @Test func legacyJSONDecodesMissingOptionalFields() throws {
        let sample = try JSONDecoder().decode(NativeSample.self, from: Data("{\"timestamp\":0}".utf8))
        #expect(sample.runningStrideLength == nil)
        #expect(sample.runningGroundContactTime == nil)
        #expect(sample.runningVerticalOscillation == nil)
        let stream = AnalysisStream(rulesVersion: 1, start: start, count: 2)
        #expect(try JSONDecoder().decode(AnalysisStream.self, from: JSONEncoder().encode(stream)) == stream)
    }
}
