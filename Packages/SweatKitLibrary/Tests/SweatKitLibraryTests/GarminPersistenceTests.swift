import Foundation
import SweatKitLibrary
import SweatKitModel
import SweatKitStore
import SweatKitSync
import SweatKitTestSupport
import Testing

@Suite struct GarminPersistenceTests {
    let temporary = TemporaryLibrary()

    func adapter(_ library: ActivityLibrary) -> PersistentGarminLibrary {
        PersistentGarminLibrary(library: library, metadataURL: temporary.root.appendingPathComponent("garmin.json"))
    }

    @Test func checkpointsSurviveANewAdapter() async throws {
        let library = try temporary.open()
        let first = adapter(library)
        var state = GarminSyncState()
        state.lastQuickSync = Date(timeIntervalSince1970: 1234)
        state.rateLimitedUntil = Date(timeIntervalSince1970: 5678)
        state.pass = HistoryPass(kind: .backfill, started: Date(timeIntervalSince1970: 1000))
        try await first.saveSyncState(state)
        #expect(try await adapter(library).loadSyncState() == state)
    }

    @Test func originalImportIsIdempotentAndRemovalKeepsTheFeed() async throws {
        let library = try temporary.open()
        let bridge = adapter(library)
        let bytes = try Fixtures.FIT.outdoorRide.data()
        let summary = GarminSummary(activityID: 123)
        let hash = ContentHash(of: bytes)
        try await bridge.ingestOriginal(bytes, contentHash: hash, as: summary.identity, summary: summary)
        try await bridge.ingestOriginal(bytes, contentHash: hash, as: summary.identity, summary: summary)
        #expect(try await library.feed(limit: 10).activities.count == 1)
        #expect(try await adapter(library).knownGarminActivities()[summary.identity]?.contentHash == hash)
        try await bridge.markRemovedAtSource(summary.identity)
        #expect(try await adapter(library).knownGarminActivities()[summary.identity]?.removedAtSource == true)
        #expect(try await library.feed(limit: 10).activities.count == 1)
        try await bridge.markPresentAtSource(summary.identity)
        #expect(try await bridge.knownGarminActivities()[summary.identity]?.removedAtSource == false)
    }

    @Test func rejectedImportDoesNotPublishSummary() async throws {
        let library = try temporary.open()
        let bridge = adapter(library)
        let bytes = Data("not a FIT file".utf8)
        let summary = GarminSummary(activityID: 456)
        await #expect(throws: (any Error).self) {
            try await bridge.ingestOriginal(bytes, contentHash: ContentHash(of: bytes), as: summary.identity, summary: summary)
        }
        #expect(try await bridge.knownGarminActivities().isEmpty)
        #expect(try await library.feed(limit: 10).activities.isEmpty)
    }

    @Test func importInterruptedBeforeMetadataCanBeRetried() async throws {
        let library = try temporary.open()
        let bytes = try Fixtures.FIT.outdoorRide.data()
        let summary = GarminSummary(activityID: 789)
        try await library.importFile(bytes, as: summary.identity)
        let bridge = adapter(library)
        #expect(try await bridge.knownGarminActivities().isEmpty)
        try await bridge.ingestOriginal(bytes, contentHash: ContentHash(of: bytes), as: summary.identity, summary: summary)
        #expect(try await bridge.knownGarminActivities().count == 1)
        #expect(try await library.feed(limit: 10).activities.count == 1)
        try await library.store.setState(.hidden, for: summary.identity)
        #expect(try await bridge.garminTombstones() == [summary.identity])
        try await bridge.markRemovedAtSource(summary.identity)
        #expect(try await library.store.sourceRecord(summary.identity)?.state == .hidden)
    }

    @Test func corruptCheckpointFailsExplicitly() async throws {
        let library = try temporary.open()
        let url = temporary.root.appendingPathComponent("garmin.json")
        try Data("broken".utf8).write(to: url)
        await #expect(throws: (any Error).self) { try await adapter(library).loadSyncState() }
    }
}
