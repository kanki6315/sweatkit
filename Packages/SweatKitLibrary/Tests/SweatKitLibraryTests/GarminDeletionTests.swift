import Foundation
import SweatKitLibrary
import SweatKitModel
import SweatKitSync
import SweatKitTestSupport
import Testing

@Suite struct GarminDeletionTests {
    let temporary = TemporaryLibrary()
    var metadataURL: URL { temporary.root.appendingPathComponent("garmin-sync.json") }

    @Test func coordinatedDeletionPrunesSummariesAndRetriesWithoutLosingOtherProgress() async throws {
        let library = try temporary.open()
        let bridge = PersistentGarminLibrary(library: library, metadataURL: metadataURL)
        let deleted = GarminSummary(activityID: 100)
        let kept = GarminSummary(activityID: 200)
        let walk = try Fixtures.FIT.walk.data()
        let ride = try Fixtures.FIT.outdoorRide.data()
        try await bridge.ingestOriginal(walk, contentHash: ContentHash(of: walk), as: deleted.identity, summary: deleted)
        try await bridge.ingestOriginal(ride, contentHash: ContentHash(of: ride), as: kept.identity, summary: kept)
        var stale = GarminSyncState()
        stale.lastQuickSync = Date(timeIntervalSince1970: 12345)
        stale.pass = HistoryPass(kind: .deepScan, started: Date(timeIntervalSince1970: 12000))
        stale.pending[100] = PendingActivity(summary: deleted, forceDownload: true, attempts: 2, lastFailure: .network)
        stale.pending[200] = PendingActivity(summary: kept, forceDownload: false, attempts: 1, lastFailure: .network)
        try await bridge.saveSyncState(stale)

        try await bridge.permanentlyDelete(deleted.identity)
        var expected = stale
        expected.pending.removeValue(forKey: 100)
        #expect(try await bridge.loadSyncState() == expected)
        #expect(try await storedSummaryKeys() == [kept.identity.description])
        #expect(try await library.activity(deleted.identity) == nil)
        #expect(try await library.activity(kept.identity) != nil)
        // The engine may still hold a pre-deletion checkpoint or listing.
        // Saving either later must not republish deleted summary data.
        try await bridge.saveSyncState(stale)
        try await bridge.updateSummary(deleted, for: deleted.identity)
        try await bridge.ingestOriginal(walk, contentHash: ContentHash(of: walk), as: deleted.identity, summary: deleted)
        #expect(try await bridge.loadSyncState() == expected)
        #expect(try await storedSummaryKeys() == [kept.identity.description])
        #expect(try await library.store.sourceRecord(deleted.identity) == nil)
    }

    @Test func concurrentSyncWritesCannotRepublishDeletedSummary() async throws {
        let library = try temporary.open()
        let bridge = PersistentGarminLibrary(library: library, metadataURL: metadataURL)
        let summary = GarminSummary(activityID: 250)
        let bytes = try Fixtures.FIT.walk.data()
        let hash = ContentHash(of: bytes)
        try await bridge.ingestOriginal(bytes, contentHash: hash, as: summary.identity, summary: summary)
        let state = GarminSyncState(pending: [250: PendingActivity(summary: summary,
            forceDownload: true, attempts: 1, lastFailure: .network)])
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await bridge.permanentlyDelete(summary.identity) }
            for _ in 0..<8 {
                group.addTask { try await bridge.saveSyncState(state) }
                group.addTask { try await bridge.updateSummary(summary, for: summary.identity) }
                group.addTask { try await bridge.ingestOriginal(bytes, contentHash: hash, as: summary.identity, summary: summary) }
            }
            try await group.waitForAll()
        }
        #expect(try await storedSummaryKeys().isEmpty)
        #expect(try await bridge.loadSyncState()?.pending.isEmpty == true)
        #expect(try await library.store.sourceRecord(summary.identity) == nil)
    }

    @Test func restartPrunesAfterDeletionCommittedBeforeBridgeCleanup() async throws {
        let library = try temporary.open()
        let bridge = PersistentGarminLibrary(library: library, metadataURL: metadataURL)
        let summary = GarminSummary(activityID: 300)
        let bytes = try Fixtures.FIT.walk.data()
        try await bridge.ingestOriginal(bytes, contentHash: ContentHash(of: bytes), as: summary.identity, summary: summary)
        var state = GarminSyncState()
        state.pending[300] = PendingActivity(summary: summary, forceDownload: true, attempts: 1, lastFailure: .network)
        try await bridge.saveSyncState(state)
        // Exact crash boundary: deletion completed but no bridge cleanup yet.
        try await library.permanentlyDelete(summary.identity)
        #expect(try await storedSummaryKeys() == [summary.identity.description])
        let reopened = try temporary.open()
        let restarted = PersistentGarminLibrary(library: reopened, metadataURL: metadataURL)
        #expect(try await restarted.loadSyncState()?.pending.isEmpty == true)
        #expect(try await storedSummaryKeys().isEmpty)
        #expect(try await restarted.garminTombstones() == [summary.identity])
    }

    @Test func cleanupFailureCanBeRetriedAfterLibraryDeletion() async throws {
        let library = try temporary.open()
        let bridge = PersistentGarminLibrary(library: library, metadataURL: metadataURL)
        let summary = GarminSummary(activityID: 400)
        let bytes = try Fixtures.FIT.walk.data()
        try await bridge.ingestOriginal(bytes, contentHash: ContentHash(of: bytes), as: summary.identity, summary: summary)
        let previous = try Data(contentsOf: metadataURL)
        try FileManager.default.removeItem(at: metadataURL)
        try FileManager.default.createDirectory(at: metadataURL, withIntermediateDirectories: false)
        await #expect(throws: (any Error).self) { try await bridge.permanentlyDelete(summary.identity) }
        #expect(try await library.deletedIdentities().contains(summary.identity))
        #expect(try await library.store.sourceRecord(summary.identity) == nil)
        try FileManager.default.removeItem(at: metadataURL)
        try previous.write(to: metadataURL, options: .atomic)
        try await bridge.permanentlyDelete(summary.identity)
        #expect(try await storedSummaryKeys().isEmpty)
    }

    private func storedSummaryKeys() async throws -> Set<String> {
        let json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: metadataURL)) as? [String: Any])
        let summaries = try #require(json["summaries"] as? [String: Any])
        return Set(summaries.keys)
    }
}
