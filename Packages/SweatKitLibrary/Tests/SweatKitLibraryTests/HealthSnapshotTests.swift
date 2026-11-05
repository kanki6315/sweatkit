import Foundation
import SweatKitAnalysis
import SweatKitIdentity
import SweatKitIngest
import SweatKitLibrary
import SweatKitModel
import SweatKitTestSupport
import Testing

@Suite struct HealthSnapshotTests {
    let temporary = TemporaryLibrary()

    func snapshot(_ activity: RecordedActivity, id: UUID = UUID()) -> HealthSnapshot {
        HealthSnapshot(workoutID: id, activity: activity, sourceName: "Apple Watch", sourceBundleIdentifier: "test.health")
    }

    @Test func workoutMergesWithGarminAndKeepsItsAlternative() async throws {
        let library = try temporary.open()
        let bytes = try Fixtures.FIT.outdoorRide.data()
        let health = snapshot(try FITActivityDecoder.decode(bytes))
        try await library.importHealthSnapshot(health)
        let garmin = SourceIdentity(source: .garmin, externalID: "health-overlap")
        let imported = try await library.importFile(bytes, as: garmin)
        #expect(Set(imported.activity.members) == [garmin, health.identity])
        #expect(imported.activity.primary == garmin)
        #expect(try await library.feed(limit: 10).activities.count == 1)
        try await library.decide(.primary(health.identity), for: imported.activity.id!)
        #expect(try await library.recordedActivity(for: imported.activity.id!) == health.activity)
    }

    @Test func partialHealthRecordingIsReviewedWithoutMergingAndSurvivesRestart() async throws {
        let library = try temporary.open()
        let bytes = try Fixtures.FIT.outdoorRide.data()
        let full = try FITActivityDecoder.decode(bytes)
        let samples = full.stream.samples
        let lower = samples.count / 3
        let upper = samples.count * 2 / 3
        let selected = Array(samples[lower..<upper])
        let start = try #require(selected.first?.timestamp)
        let end = try #require(selected.last?.timestamp)
        let partial = snapshot(RecordedActivity(sport: full.sport,
            stated: StatedSummary(start: start, end: end, timerTime: end.timeIntervalSince(start)),
            stream: NativeStream(samples: selected)))
        let garmin = SourceIdentity(source: .garmin, externalID: "full-with-partial-health")
        try await library.importFile(bytes, as: garmin)
        try await library.importHealthSnapshot(partial)
        let pair = IdentityPair(garmin, partial.identity)
        #expect(try await library.feed(limit: 10).activities.count == 2)
        #expect(try await library.possibleDuplicates().contains(pair))
        #expect(try await library.recordedActivity(for: partial.identity) == partial.activity)
        try await library.link(pair, kind: .keepSeparate)

        let restarted = try temporary.open()
        try await restarted.importHealthSnapshot(partial)
        try await restarted.importFile(bytes, as: garmin)
        #expect(try await restarted.feed(limit: 10).activities.count == 2)
        #expect(try await restarted.possibleDuplicates().isEmpty)
        #expect(try await restarted.store.sourceRecord(partial.identity)?.revisions.count == 1)
        #expect(try await restarted.recordedActivity(for: garmin) == full)
    }

    @Test func revisedWorkoutRetainsOriginalAndRebuildsAfterCacheLoss() async throws {
        let library = try temporary.open()
        var health = snapshot(try FITActivityDecoder.decode(Fixtures.FIT.walk.data()))
        try await library.importHealthSnapshot(health)
        let original = try #require(try await library.store.sourceRecord(health.identity)?.currentRevision)
        health.activity.stream.samples[0].heartRate = 101
        try await library.importHealthSnapshot(health)
        let record = try #require(try await library.store.sourceRecord(health.identity))
        #expect(record.revisions.count == 2)
        #expect(record.currentRevision != original)
        #expect(try await library.store.original(original) != nil)
        for path in [temporary.analysisFile(record.currentRevision), temporary.root.appendingPathComponent("Streams/\(record.currentRevision.hex).recorded")] {
            if FileManager.default.fileExists(atPath: path.path) { try FileManager.default.removeItem(at: path) }
        }
        #expect(try await library.recordedActivity(for: health.identity) == health.activity)
        try await library.markHealthWorkoutRemoved(health.workoutID)
        #expect(try await library.store.sourceRecord(health.identity)?.state == .removedAtSource)
        #expect(try await library.feed(limit: 10).activities.count == 1)
    }

    @Test func summaryOnlyWorkoutKeepsStatedTotalsWithoutInventingSamples() async throws {
        let library = try temporary.open()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let health = snapshot(RecordedActivity(sport: .walking,
            stated: StatedSummary(start: start, end: start.addingTimeInterval(600), timerTime: 580, distance: 1000)))
        let first = try await library.importHealthSnapshot(health)
        #expect(first.activity.distance == 1000)
        #expect(first.activity.timerTime == 580)
        // Spec: with no stream, moving time equals stated timer time.
        #expect(first.activity.movingTime == 580)
        #expect(try await library.recordedActivity(for: health.identity).stream.samples.isEmpty)
        let second = try await library.importHealthSnapshot(health)
        #expect(second.change == .alreadyInLibrary)
        #expect(try await library.store.sourceRecord(health.identity)?.revisions.count == 1)
        var versions = PipelineVersions.current
        versions.algorithms[PipelineVersions.AlgorithmName.feedRow] = PipelineVersions.feedRowVersion + 1
        let reopened = try temporary.open(versions: versions)
        try await reopened.recompute()
        #expect(try await reopened.activity(health.identity)?.distance == 1000)
    }
    @Test func distanceRefreshUpdatesExistingWorkoutWithoutDuplicatingIt() async throws {
        let library = try temporary.open()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var health = snapshot(RecordedActivity(sport: .running,
            stated: .init(start: start, end: start.addingTimeInterval(61), distance: 120),
            stream: NativeStream(samples: (0...60).map {
                NativeSample(timestamp: start.addingTimeInterval(Double($0)), altitude: 200 + Double($0) * 0.1)
            })))
        try await library.importHealthSnapshot(health)
        let distance = HealthQuantityConversion.distance((0..<60).map {
            HealthQuantityInterval(start: start.addingTimeInterval(Double($0)),
                end: start.addingTimeInterval(Double($0 + 1)), value: 2)
        })
        health.activity.stream.samples += distance
        health.activity.stream.samples.sort { $0.timestamp < $1.timestamp }
        try await library.importHealthSnapshot(health)
        #expect(try await library.feed(limit: 10).activities.count == 1)
        #expect(try await library.activity(health.identity)?.distance == 120)
        #expect(try await library.store.sourceRecord(health.identity)?.revisions.count == 2)
        try await library.importHealthSnapshot(health)
        #expect(try await library.store.sourceRecord(health.identity)?.revisions.count == 2)
    }

    @Test func thinnerRefreshKeepsOriginalAndRestoringAccessDoesNotDuplicate() async throws {
        let library = try temporary.open()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let rich = snapshot(RecordedActivity(sport: .running,
            stated: .init(start: start, end: start.addingTimeInterval(60), timerTime: 60),
            laps: [RecordedLap(start: start, end: start.addingTimeInterval(30))],
            segments: [RecordedLap(start: start.addingTimeInterval(10), end: start.addingTimeInterval(20))],
            stream: .init(samples: [NativeSample(timestamp: start, heartRate: 119)])))
        try await library.importHealthSnapshot(rich)
        let original = try #require(try await library.store.sourceRecord(rich.identity)?.currentRevision)
        var thin = rich
        thin.activity.stream.samples = []
        try await library.importHealthSnapshot(thin)
        #expect(try await library.store.original(original) != nil)
        try await library.importHealthSnapshot(rich)
        #expect(try await library.feed(limit: 10).activities.count == 1)
        #expect(try await library.recordedActivity(for: rich.identity) == rich.activity)
        #expect(try await library.store.sourceRecord(rich.identity)?.revisions.count == 2)
    }

    @Test func healthPauseIntervalsAndSplitsUseTimerRatherThanMovingSeconds() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        // 1,201 elapsed seconds, a 30-second pause, and 2 m per active second.
        // Cumulative distance at t=1200 is 2*(1200-30) = 2,340 m.
        let intervals = (0..<1200).map { second in
            HealthQuantityInterval(start: start.addingTimeInterval(Double(second)),
                end: start.addingTimeInterval(Double(second + 1)),
                value: (300..<330).contains(second) ? 0 : 2)
        }
        var points = HealthQuantityConversion.distance(intervals)
        points += (0..<1201).map { second in
            // A recorded stationary speed wins over distance-derived speed.
            NativeSample(timestamp: start.addingTimeInterval(Double(second)),
                speed: (600..<610).contains(second) ? 0 : 2,
                heartRate: (300..<330).contains(second) ? 80 : 119)
        }
        let activity = RecordedActivity(sport: .walking,
            stated: .init(start: start, end: start.addingTimeInterval(1201), timerTime: 1171),
            timerEvents: [.init(kind: .stop, timestamp: start.addingTimeInterval(300)),
                          .init(kind: .start, timestamp: start.addingTimeInterval(330))],
            stream: .init(samples: points))
        let stream = try #require(StreamNormaliser.analysisStream(from: activity))
        let metrics = ActivityAnalysis.metrics(for: ActivityInput(sport: .walking,
            recording: .stream(stream), activityDate: start))
        #expect(metrics.time.elapsed.value == 1201)
        #expect(metrics.time.timer.value == 1171)
        #expect(metrics.time.moving.value == 1161)
        let expectedHR = (1171.0 * 119.0 + 30.0 * 80.0) / 1201.0
        let actualHR = try #require(metrics.heartRate.average.value)
        #expect(abs(actualHR - expectedHR) < 0.000001)
        #expect(metrics.distance.value == 2340)
        let splits = try #require(metrics.splits.value)
        // The kilometre boundaries are t=530 and t=1030; pause is in split 1.
        #expect(splits.map(\.duration) == [500, 500, 171])
        #expect(splits.allSatisfy { $0.averageHeartRate.value == 119 })
        #expect(splits.map(\.distance) == [1000, 1000, 340])
        #expect(splits[0].pace.value == 500)
        #expect(splits[1].pace.value == 500)
        #expect(abs(try #require(splits[2].pace.value) - 171 / 0.34) < 0.000001)
        #expect(abs(try #require(FeedRules.averagePace(metrics).value) - 1161 / 2.34) < 0.000001)
    }

    @Test func checkpointKeepsPendingSnapshotsAcrossRestartAndRetry() throws {
        let url = temporary.root.appendingPathComponent("health-sync.json")
        let workout = UUID()
        var checkpoint = HealthSyncState()
        checkpoint.anchors["workouts"] = Data([1, 2, 3])
        checkpoint.workouts[workout] = DateInterval(start: Date(timeIntervalSince1970: 10), duration: 600)
        checkpoint.pending.insert(workout)
        try checkpoint.save(to: url)
        // Simulates termination after an anchor was checkpointed but before
        // its queued snapshot could be imported.
        var restarted = try HealthSyncState.load(from: url)
        #expect(restarted == checkpoint)
        restarted.pending.remove(workout)
        try restarted.save(to: url)
        #expect(try HealthSyncState.load(from: url).pending.isEmpty)
        #expect(try HealthSyncState.load(from: url).anchors == checkpoint.anchors)
        try Data("corrupt".utf8).write(to: url)
        #expect(throws: (any Error).self) { try HealthSyncState.load(from: url) }
    }

    @Test func workoutDistanceDoesNotBecomeAnInventedDistanceStream() async throws {
        let library = try temporary.open()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let health = snapshot(RecordedActivity(sport: .walking,
            stated: StatedSummary(start: start, end: start.addingTimeInterval(60), timerTime: 60, distance: 100),
            stream: NativeStream(samples: [NativeSample(timestamp: start, heartRate: 100)])))
        let result = try await library.importHealthSnapshot(health)
        #expect(result.activity.distance == 100)
        let stream = try await library.analysisStream(for: health.identity)
        #expect((0..<stream.count).allSatisfy { stream.distance[$0] == nil })
    }

    @Test func alternativeOffersOnlyChannelsMissingFromThePrimary() async throws {
        let library = try temporary.open()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let summary = StatedSummary(start: start, end: start.addingTimeInterval(60), timerTime: 60, distance: 100)
        let first = snapshot(RecordedActivity(sport: .cycling, stated: summary,
            stream: NativeStream(samples: [NativeSample(timestamp: start, speed: 3)])))
        let second = snapshot(RecordedActivity(sport: .cycling, stated: summary,
            stream: NativeStream(samples: [NativeSample(timestamp: start, speed: 3, heartRate: 120)])))
        try await library.importHealthSnapshot(first)
        let result = try await library.importHealthSnapshot(second)
        let id = try #require(result.activity.id)
        try await library.decide(.primary(first.identity), for: id)
        let offers = try await library.alternativeSources(for: id)
        #expect(offers.count == 1)
        #expect(offers.first?.identity == second.identity)
        #expect(offers.first?.channels == [.heartRate])
        try await library.decide(.primary(second.identity), for: id)
        #expect(try await library.alternativeSources(for: id).isEmpty)
    }

}
