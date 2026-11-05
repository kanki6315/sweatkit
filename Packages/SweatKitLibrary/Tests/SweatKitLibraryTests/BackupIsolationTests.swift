import Foundation
import SweatKitIdentity
import SweatKitIngest
import SweatKitLibrary
import SweatKitModel
import SweatKitTestSupport
import Testing

@Suite struct BackupIsolationTests {
    let temporary = TemporaryLibrary()
    let restored = TemporaryLibrary()

    @Test func backupEligibleFilesRestoreNonHealthRevisionsProfileAndDecisionsWithoutHealthFacts() async throws {
        let library = try temporary.open()
        let garmin = SourceIdentity(source: .garmin, externalID: "backup-ride")
        let first = try Fixtures.FIT.walk.data()
        let second = try Fixtures.FIT.outdoorRide.data()
        try await library.importFile(first, as: garmin)
        try await library.importFile(second, as: garmin)
        let userProfile = profile(thresholdPower: 271)
        try await library.saveProfile(userProfile)
        let health = HealthSnapshot(workoutID: UUID(), activity: try FITActivityDecoder.decode(second),
            sourceName: "PRIVATE-SOURCE-NAME", sourceBundleIdentifier: "test.private")
        let imported = try await library.importHealthSnapshot(health)
        let id = try #require(imported.activity.id)
        try await library.decide(.primary(health.identity), for: id)
        try await library.decide(.title("My preserved title"), for: id)
        try await library.decide(.hidden(true), for: id)
        let expectedRecord = try #require(try await library.store.sourceRecord(garmin))
        let snapshotHash = try #require(try await library.store.sourceRecord(health.identity)?.currentRevision)
        #expect(!FileManager.default.fileExists(atPath: temporary.originalFile(snapshotHash).path))
        #expect(FileManager.default.fileExists(atPath: temporary.root.appendingPathComponent("HealthOriginals/\(snapshotHash.hex)").path))
        let journal = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: temporary.root.appendingPathComponent("identity.json"))) as? [String: Any])
        let candidates = try #require(journal["candidates"] as? [String: Any])
        #expect(candidates[health.identity.description] == nil)
        #expect(candidates[garmin.description] != nil)
        let manifest = try String(contentsOf: temporary.root.appendingPathComponent("library-backup.json"), encoding: .utf8)
        #expect(!manifest.contains(health.workoutID.uuidString))
        #expect(!manifest.contains(snapshotHash.hex))
        #expect(!manifest.contains("PRIVATE-SOURCE-NAME"))
        for directory in ["LocalMetadata", "HealthMetadata", "HealthOriginals", "Streams", "Thumbnails"] {
            let values = try temporary.root.appendingPathComponent(directory).resourceValues(forKeys: [.isExcludedFromBackupKey])
            #expect(values.isExcludedFromBackup == true)
        }
        // Model exactly the eligible part of a backup, excluding all local
        // caches and Health payloads; a new installation has no SwiftData DB.
        try FileManager.default.createDirectory(at: restored.root, withIntermediateDirectories: true)
        for name in ["Originals", "library-backup.json", "identity.json"] {
            try FileManager.default.copyItem(at: temporary.root.appendingPathComponent(name), to: restored.root.appendingPathComponent(name))
        }
        let recovered = try restored.open()
        #expect(try await recovered.feed(limit: 10).activities.isEmpty)
        let hidden = try #require(try await recovered.hiddenActivities().first)
        #expect(hidden.title == "My preserved title")
        #expect(hidden.primary == garmin)
        #expect(hidden.members == [garmin])
        #expect(try await recovered.profile() == userProfile)
        let restoredRecord = try #require(try await recovered.store.sourceRecord(garmin))
        #expect(restoredRecord.revisions == expectedRecord.revisions)
        #expect(restoredRecord.currentRevision == expectedRecord.currentRevision)
        #expect(try await recovered.recordedActivity(for: garmin) == FITActivityDecoder.decode(second))
        #expect(try await recovered.store.sourceRecord(health.identity) == nil)
        // Re-reading the Health workout reattaches its decisions, without
        // exporting any Health summary to the recovery manifest.
        try await recovered.importHealthSnapshot(health)
        #expect(try await recovered.hiddenActivities().first?.members.count == 2)
    }

    @Test func upgradesLegacyMixedDatabaseAndCandidateJournalWithoutLosingEitherSource() async throws {
        let library = try temporary.open()
        let bytes = try Fixtures.FIT.walk.data()
        let file = try await library.importFile(bytes)
        let health = HealthSnapshot(workoutID: UUID(), activity: try FITActivityDecoder.decode(bytes),
            sourceName: "Watch", sourceBundleIdentifier: "test.watch")
        try await library.importHealthSnapshot(health)
        let hash = try #require(try await library.store.sourceRecord(health.identity)?.currentRevision)
        let manager = FileManager.default
        let metadata = temporary.root.appendingPathComponent("LocalMetadata")
        // Copy a stable source into a separate legacy-layout root. Never
        // remove or replace files belonging to an open ModelContainer.
        try manager.createDirectory(at: restored.root, withIntermediateDirectories: true)
        for item in try manager.contentsOfDirectory(at: temporary.root, includingPropertiesForKeys: nil)
            where item.lastPathComponent != "LocalMetadata" && item.lastPathComponent != "library-backup.json" {
            try manager.copyItem(at: item, to: restored.root.appendingPathComponent(item.lastPathComponent))
        }
        for item in try manager.contentsOfDirectory(at: metadata, includingPropertiesForKeys: nil)
            where item.lastPathComponent.hasPrefix("Library.store") || item.lastPathComponent == ".Library_SUPPORT" {
            try manager.copyItem(at: item, to: restored.root.appendingPathComponent(item.lastPathComponent))
        }
        let identityURL = restored.root.appendingPathComponent("identity.json")
        var identity = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: identityURL)) as? [String: Any])
        var candidates = try #require(identity["candidates"] as? [String: Any])
        let healthURL = restored.root.appendingPathComponent("HealthMetadata/candidates.json")
        let local = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: healthURL)) as? [String: Any])
        candidates.merge(local) { _, health in health }
        identity["candidates"] = candidates
        try JSONSerialization.data(withJSONObject: identity).write(to: identityURL, options: .atomic)
        try manager.removeItem(at: healthURL)
        try manager.moveItem(at: restored.root.appendingPathComponent("HealthOriginals/\(hash.hex)"), to: restored.originalFile(hash))

        let upgraded = try restored.open()
        #expect(try await upgraded.feed(limit: 10).activities.count == 1)
        #expect(try await upgraded.store.sourceRecords().count == 2)
        #expect(try await upgraded.store.original(hash) != nil)
        #expect(!manager.fileExists(atPath: restored.originalFile(hash).path))
        #expect(!manager.fileExists(atPath: restored.root.appendingPathComponent("Library.store").path))
        #expect(try await upgraded.recordedActivity(for: file.source) == FITActivityDecoder.decode(bytes))
        let safe = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: identityURL)) as? [String: Any])
        #expect((safe["candidates"] as? [String: Any])?[health.identity.description] == nil)
    }

    @Test func staleGenerationReplaysManifestAndCorruptManifestNeverResetsLibrary() async throws {
        let library = try temporary.open()
        let bytes = try Fixtures.FIT.walk.data()
        let imported = try await library.importFile(bytes)
        let savedProfile = profile(thresholdPower: 283)
        try await library.saveProfile(savedProfile)
        let generation = temporary.root.appendingPathComponent("LocalMetadata/backup-generation")
        try Data("interrupted".utf8).write(to: generation, options: .atomic)
        let reopened = try temporary.open()
        #expect(try await reopened.feed(limit: 10).activities.count == 1)
        #expect(try await reopened.profile() == savedProfile)
        #expect(try await reopened.recordedActivity(for: imported.source) == FITActivityDecoder.decode(bytes))
        let manifest = temporary.root.appendingPathComponent("library-backup.json")
        try Data("corrupt".utf8).write(to: manifest, options: .atomic)
        #expect(throws: (any Error).self) { try temporary.open() }
        #expect(FileManager.default.fileExists(atPath: temporary.originalFile(ContentHash(of: bytes)).path))
    }
}
