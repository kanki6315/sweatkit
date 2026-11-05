import Foundation
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

}
