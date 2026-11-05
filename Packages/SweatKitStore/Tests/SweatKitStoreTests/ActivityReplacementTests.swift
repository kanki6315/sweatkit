import Foundation
import SweatKitModel
import SweatKitStore
import Testing

@Suite struct ActivityReplacementTests {
    let temporary = TemporaryLibrary()

    func row(_ members: [SourceIdentity]) -> ActivityRecord {
        ActivityRecord(members: members, primary: members[0], sport: .cycling,
            start: referenceDate, elapsedTime: 3600, title: "Ride")
    }

    @Test func mergeAndSplitRetainSourcesAndRevisions() async throws {
        let store = try temporary.open()
        try await storeGarminRecord(1, in: store)
        try await storeGarminRecord(2, in: store)
        try await store.saveActivity(row([garmin(1)]))
        try await store.saveActivity(row([garmin(2)]))
        try await store.replaceActivities(removing: [garmin(1), garmin(2)], with: [row([garmin(1), garmin(2)])])
        #expect(try await store.feed(limit: 10).activities.count == 1)
        #expect(try await store.sourceRecord(garmin(2))?.activityID == garmin(1))
        try await store.replaceActivities(removing: [garmin(1)], with: [row([garmin(1)]), row([garmin(2)])])
        #expect(try await store.feed(limit: 10).activities.count == 2)
        #expect(try await store.sourceRecord(garmin(2))?.activityID == garmin(2))
        #expect(try await store.sourceRecords().allSatisfy { $0.revisions.count == 1 })
    }

    @Test func invalidReplacementLeavesTheOldFeedUntouched() async throws {
        let store = try temporary.open()
        try await storeGarminRecord(1, in: store)
        try await storeGarminRecord(2, in: store)
        try await store.saveActivity(row([garmin(1)]))
        try await store.saveActivity(row([garmin(2)]))
        let before = try await store.feed(limit: 10)
        await #expect(throws: (any Error).self) {
            try await store.replaceActivities(removing: [garmin(1)], with: [row([garmin(1), garmin(2)])])
        }
        #expect(try await store.feed(limit: 10) == before)
        await #expect(throws: (any Error).self) {
            try await store.replaceActivities(removing: [garmin(1), garmin(2)],
                with: [row([garmin(1)]), row([garmin(1), garmin(2)])])
        }
        #expect(try await store.feed(limit: 10) == before)
    }
}
