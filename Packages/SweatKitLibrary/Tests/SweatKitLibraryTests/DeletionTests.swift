import Foundation
import SweatKitIdentity
import SweatKitIngest
import SweatKitLibrary
import SweatKitModel
import SweatKitStore
import SweatKitTestSupport
import Testing

@Suite struct DeletionTests {
    let temporary = TemporaryLibrary()

    @Test func deletionErasesEveryRevisionAndRefusesReimportAfterRestart() async throws {
        let library = try temporary.open()
        let id = SourceIdentity(source: .garmin, externalID: "delete-revisions")
        let first = try Fixtures.FIT.walk.data()
        let second = try Fixtures.FIT.outdoorRide.data()
        try await library.importFile(first, as: id)
        try await library.importFile(second, as: id)
        let hashes = [ContentHash(of: first), ContentHash(of: second)]
        let variant = ContentHash(of: Data("light".utf8))
        try await library.store.saveThumbnail(Data([1]), for: hashes[0], variant: variant)
        try await library.permanentlyDelete(id)
        #expect(try await library.store.sourceRecord(id) == nil)
        #expect(try await library.store.derivedResult(owner: .activity(id), kind: ActivityLibrary.metricsKind) == nil)
        for hash in hashes {
            #expect(!FileManager.default.fileExists(atPath: temporary.originalFile(hash).path))
            #expect(!FileManager.default.fileExists(atPath: temporary.analysisFile(hash).path))
            #expect(!FileManager.default.fileExists(atPath: temporary.recordedFile(hash).path))
        }
        #expect(!FileManager.default.fileExists(atPath: library.store.thumbnailURL(for: hashes[0], variant: variant).path))
        await #expect(throws: (any Error).self) {
            try await library.store.saveThumbnail(Data([2]), for: hashes[0], variant: variant)
        }
        let reopened = try temporary.open()
        #expect(try await reopened.feed(limit: 10).activities.isEmpty)
        await #expect(throws: LibraryError.permanentlyDeleted(id)) {
            try await reopened.importFile(first, as: id)
        }
        let bridge = PersistentGarminLibrary(library: reopened, metadataURL: temporary.root.appendingPathComponent("garmin-sync.json"))
        #expect(try await bridge.garminTombstones() == [id])
        #expect(try await reopened.store.sourceRecords().isEmpty)
    }

    @Test func sharedOriginalSurvivesUntilLastOwningActivityIsDeleted() async throws {
        let library = try temporary.open()
        let first = SourceIdentity(source: .garmin, externalID: "shared-first")
        let second = SourceIdentity(source: .garmin, externalID: "shared-second")
        let bytes = try Fixtures.FIT.walk.data()
        try await library.link(IdentityPair(first, second), kind: .keepSeparate)
        try await library.importFile(bytes, as: first)
        try await library.importFile(bytes, as: second)
        let hash = ContentHash(of: bytes)
        try await library.permanentlyDelete(first)
        #expect(try await library.store.original(hash) == bytes)
        #expect(try await library.recordedActivity(for: second) == FITActivityDecoder.decode(bytes))
        #expect(try await library.feed(limit: 10).activities.map(\.id) == [second])
        try await library.permanentlyDelete(second)
        #expect(try await library.store.original(hash) == nil)
    }

    @Test func deletingMergedActivityTombstonesAllSourcesIncludingHealth() async throws {
        let library = try temporary.open()
        let bytes = try Fixtures.FIT.walk.data()
        let garmin = SourceIdentity(source: .garmin, externalID: "merged-delete")
        let health = HealthSnapshot(workoutID: UUID(), activity: try FITActivityDecoder.decode(bytes),
            sourceName: "Watch", sourceBundleIdentifier: "test.watch")
        try await library.importFile(bytes, as: garmin)
        let merged = try await library.importHealthSnapshot(health)
        try await library.permanentlyDelete(try #require(merged.activity.id))
        #expect(try await library.deletedIdentities() == [garmin, health.identity])
        #expect(try await library.store.sourceRecords().isEmpty)
        #expect(try await library.possibleDuplicates().isEmpty)
        await #expect(throws: LibraryError.permanentlyDeleted(health.identity)) {
            try await library.importHealthSnapshot(health)
        }
    }

    @Test func restartFinishesDeletionAfterDurableIntentBeforeErasure() async throws {
        let library = try temporary.open()
        let bytes = try Fixtures.FIT.walk.data()
        let imported = try await library.importFile(bytes)
        let identity = imported.source
        // Inject the exact crash boundary: the intent file is committed, but
        // the process has not removed metadata or any bytes yet.
        let url = temporary.root.appendingPathComponent("identity.json")
        var journal = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let tombstones = Tombstone.written(.deleted, for: [identity], at: Date())
        journal["tombstones"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(tombstones))
        try JSONSerialization.data(withJSONObject: journal).write(to: url, options: .atomic)
        let restarted = try temporary.open()
        #expect(try await restarted.feed(limit: 10).activities.isEmpty)
        #expect(try await restarted.store.original(ContentHash(of: bytes)) == nil)
        #expect(try await restarted.deletedIdentities() == [identity])
        await #expect(throws: LibraryError.permanentlyDeleted(identity)) { try await restarted.importFile(bytes) }
    }

    @Test func remoteDeleteOfOneMergedMemberRebuildsSurvivor() async throws {
        let library = try temporary.open()
        let first = SourceIdentity(source: .garmin, externalID: "merged-first")
        let second = SourceIdentity(source: .garmin, externalID: "merged-second")
        let bytes = try Fixtures.FIT.walk.data()
        try await library.importFile(bytes, as: first)
        try await library.importFile(bytes, as: second)
        try await library.applyIdentityChanges(IdentityChanges(links: [], decisions: [],
            tombstones: Tombstone.written(.deleted, for: [first], at: Date())))
        let row = try #require(try await library.feed(limit: 10).activities.first)
        #expect(row.members == [second])
        #expect(row.primary == second)
        #expect(try await library.metrics(for: second) != nil)
        #expect(try await library.store.original(ContentHash(of: bytes)) == bytes)
    }
}
