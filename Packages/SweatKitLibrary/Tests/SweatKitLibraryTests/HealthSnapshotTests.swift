import Foundation
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
