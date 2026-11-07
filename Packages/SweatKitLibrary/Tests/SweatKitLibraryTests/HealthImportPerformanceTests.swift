import Foundation
@testable import SweatKitLibrary
import SweatKitModel
import Testing

@Suite struct HealthImportPerformanceTests {
    let temporary = TemporaryLibrary()

    @Test func intervalIndexMatchesInclusiveScanWithNestedAndOverlappingWorkouts() {
        let origin = Date(timeIntervalSince1970: 1_700_000_000)
        var workouts: [UUID: DateInterval] = [:]
        for index in 0..<1000 {
            let start = origin.addingTimeInterval(Double(index * 100))
            workouts[UUID()] = DateInterval(start: start, duration: index.isMultiple(of: 17) ? 20_000 : 150)
        }
        let index = HealthWorkoutIndex(workouts)
        for offset in stride(from: -200, through: 120_000, by: 100) {
            let start = origin.addingTimeInterval(Double(offset))
            let end = start.addingTimeInterval(100)
            let expected = Set(workouts.filter { $0.value.start <= end && $0.value.end >= start }.keys)
            #expect(index.overlapping(start: start, end: end) == expected)
        }
        #expect(HealthWorkoutIndex([:]).overlapping(start: origin, end: origin).isEmpty)
    }

    func snapshot(_ offset: Double, id: UUID = UUID()) -> HealthSnapshot {
        let start = Date(timeIntervalSince1970: 1_700_000_000 + offset)
        return HealthSnapshot(workoutID: id, activity: RecordedActivity(sport: .walking,
            stated: StatedSummary(start: start, end: start.addingTimeInterval(600), timerTime: 600, distance: 1000)),
            sourceName: "Watch", sourceBundleIdentifier: "test.health")
    }

    @Test func batchMatchesSequentialImportAndRetryDoesNotCreateRevisions() async throws {
        let batchLibrary = try temporary.open()
        let other = TemporaryLibrary()
        let sequential = try other.open()
        let snapshots = (0..<8).map { snapshot(Double($0 * 86_400)) } + [snapshot(0)]
        let expected = Set(snapshots.map(\.workoutID))
        #expect(try await batchLibrary.importHealthSnapshots(snapshots) == expected)
        for snapshot in snapshots { try await sequential.importHealthSnapshot(snapshot) }
        let batchRows = try await batchLibrary.feed(limit: 20).activities
        let sequentialRows = try await sequential.feed(limit: 20).activities
        #expect(batchRows.map(\.members) == sequentialRows.map(\.members))
        #expect(batchRows.map(\.distance) == sequentialRows.map(\.distance))
        let reopened = try temporary.open()
        #expect(try await reopened.importHealthSnapshots(snapshots) == expected)
        for snapshot in snapshots {
            #expect(try await reopened.store.sourceRecord(snapshot.identity)?.revisions.count == 1)
        }
    }

    @Test func failedWorkoutDoesNotPreventOthersAndCanBeRetried() async throws {
        let library = try temporary.open()
        let good = snapshot(0)
        var broken = snapshot(86_400)
        let repaired = broken
        broken.activity.stated.start = nil
        broken.activity.stated.end = nil
        #expect(try await library.importHealthSnapshots([broken, good]) == [good.workoutID])
        #expect(try await library.importHealthSnapshots([repaired]) == [repaired.workoutID])
        #expect(try await temporary.open().feed(limit: 20).activities.count == 2)
    }
    @Test func interruptedBatchRecoversFromDurableInputsAfterRestart() async throws {
        let library = try temporary.open()
        let first = snapshot(0)
        let second = snapshot(86_400)
        // Model interruption after storing a workout but before batch matching.
        _ = try await library.importBytes(first.encoded(), as: first.identity,
            fallbackUTCOffset: nil, at: Date(), deferIdentity: true)
        let reopened = try temporary.open()
        #expect(try await reopened.importHealthSnapshots([first, second]) == [first.workoutID, second.workoutID])
        #expect(try await reopened.feed(limit: 20).activities.count == 2)
        #expect(try await reopened.store.sourceRecord(first.identity)?.revisions.count == 1)
    }

}
