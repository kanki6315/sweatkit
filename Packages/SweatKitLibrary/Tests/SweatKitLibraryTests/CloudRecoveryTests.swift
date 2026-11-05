import Foundation
import Testing
import SweatKitCloud
import SweatKitSync
import SweatKitLibrary
import SweatKitModel
import SweatKitIdentity
import SweatKitIngest
import SweatKitTestSupport

struct CloudRecoveryTests {
    let first = TemporaryLibrary()
    let second = TemporaryLibrary()

    @Test func wipedDeviceRestoresOriginalsProfileHiddenAndHealthDecisionsWithoutHealthFacts() async throws {
        let a = try first.open(); let b = try second.open()
        let bytes = try Fixtures.FIT.walk.data()
        let source = SourceIdentity(source: .garmin, externalID: "cloud-ride")
        try await a.importFile(bytes, as: source)
        let health = HealthSnapshot(workoutID: UUID(), activity: try FITActivityDecoder.decode(bytes), sourceName: "SECRET-WATCH", sourceBundleIdentifier: "private.watch")
        try await a.importHealthSnapshot(health)
        try await a.decide(.title("My walk"), for: source)
        try await a.decide(.hidden(true), for: source)
        let profile = profile(thresholdPower: 271)
        try await a.saveProfile(profile)
        let records = try await a.cloudExport()
        #expect(records.filter { $0.kind == .original }.count == 1)
        let encoded = String(decoding: try JSONEncoder().encode(records), as: UTF8.self)
        #expect(!encoded.contains("SECRET-WATCH"))
        for record in records {
            let payload = String(decoding: record.payload, as: UTF8.self)
            #expect(!payload.contains("SECRET-WATCH"))
            #expect(!payload.contains("candidates"))
        }
        try await b.cloudRestore(records) { record in try await a.cloudOriginal(record) }
        #expect(try await b.profile() == profile)
        #expect(try await b.feed(limit: 10).activities.isEmpty)
        #expect(try await b.hiddenActivities().first?.title == "My walk")
        #expect(try await b.store.sourceRecord(health.identity) == nil)
        try await b.importHealthSnapshot(health)
        #expect(try await b.hiddenActivities().first?.members.count == 2)
        // A repeated recovery is safe and the same user action keeps identical bytes.
        try await b.cloudRestore(records) { record in try await a.cloudOriginal(record) }
        let exported = try await b.cloudExport()
        for decision in records where decision.kind == .decision {
            #expect(exported.first { $0.name == decision.name } == decision)
        }
    }

    @Test func deletionWinsOverStaleOriginalsDuringRecovery() async throws {
        let a = try first.open(); let b = try second.open()
        let id = SourceIdentity(source: .garmin, externalID: "cloud-delete")
        try await a.importFile(Fixtures.FIT.walk.data(), as: id)
        let stale = try await a.cloudExport()
        try await a.permanentlyDelete(id)
        let deleted = try await a.cloudExport()
        try await b.cloudRestore(stale + deleted) { _ in
            Issue.record("Deleted assets must never be requested")
            return Data()
        }
        #expect(try await b.deletedIdentities().contains(id))
        #expect(try await b.store.sourceRecords().isEmpty)
    }

    @Test func twoDevicesImportSameActivityAndConvergeOnConcurrentDecisions() async throws {
        let a = try first.open(); let b = try second.open()
        let id = SourceIdentity(source: .garmin, externalID: "same-ride")
        let bytes = try Fixtures.FIT.walk.data()
        try await a.importFile(bytes, as: id, at: Date(timeIntervalSince1970: 10))
        try await b.importFile(bytes, as: id, at: Date(timeIntervalSince1970: 20))
        try await a.decide(.title("Chosen title"), for: id)
        try await b.decide(.hidden(true), for: id)
        let records = try await a.cloudExport() + b.cloudExport()
        try await a.cloudRestore(records) { _ in bytes }
        try await b.cloudRestore(records) { _ in bytes }
        #expect(try await a.hiddenActivities().first?.title == b.hiddenActivities().first?.title)
        #expect(try await a.hiddenActivities().count == 1)
        #expect(try await b.hiddenActivities().count == 1)
    }
}

extension CloudRecoveryTests {
    @Test func pausedCloudDeletionAlsoErasesTransportCopies() async throws {
        let library = try first.open()
        let id = SourceIdentity(source: .garmin, externalID: "staging-delete")
        let bytes = try Fixtures.FIT.walk.data()
        try await library.importFile(bytes, as: id)
        let item = try #require(try await library.cloudExport().first { $0.kind == .original })
        let copy = try PrivateCloudCopy(root: first.root)
        try await copy.stage(item, original: bytes)
        try await library.permanentlyDelete(id)
        #expect(!FileManager.default.fileExists(atPath: first.root.appendingPathComponent("CloudTransport/\(item.name).asset").path))
    }

    @Test func concurrentRevisionsAreRetainedAndCurrentRevisionConverges() async throws {
        let a = try first.open(); let b = try second.open()
        let id = SourceIdentity(source: .garmin, externalID: "revisions")
        let walk = try Fixtures.FIT.walk.data(); let ride = try Fixtures.FIT.outdoorRide.data()
        try await a.importFile(walk, as: id)
        try await b.importFile(ride, as: id)
        let records = try await a.cloudExport() + b.cloudExport()
        let assets = [ContentHash(of: walk): walk, ContentHash(of: ride): ride]
        try await a.cloudRestore(records) { item in try #require(assets[item.assetHash!]) }
        try await b.cloudRestore(records) { item in try #require(assets[item.assetHash!]) }
        let left = try #require(try await a.store.sourceRecord(id))
        let right = try #require(try await b.store.sourceRecord(id))
        #expect(Set(left.revisions.map(\.contentHash)) == Set(assets.keys))
        #expect(Set(right.revisions.map(\.contentHash)) == Set(assets.keys))
        #expect(left.currentRevision == right.currentRevision)
    }
}

extension CloudRecoveryTests {
    @Test func localImportDuringFetchIsPreservedForNextCopy() async throws {
        let a = try first.open(); let b = try second.open()
        let walk = try Fixtures.FIT.walk.data()
        try await a.importFile(walk)
        let downloaded = try await a.cloudExport()
        let ride = try Fixtures.FIT.outdoorRide.data()
        try await b.importFile(ride)
        try await b.cloudRestore(downloaded) { _ in walk }
        #expect(try await b.store.sourceRecords().count == 2)
        #expect(try await b.cloudExport().filter { $0.kind == .original }.count == 2)
    }
}

extension CloudRecoveryTests {
    @Test func interruptedRecoveryDoesNotPromotePartialRevisionsToNewEdits() async throws {
        let a = try first.open(); let b = try second.open()
        let id = SourceIdentity(source: .garmin, externalID: "interrupted")
        let walk = try Fixtures.FIT.walk.data(); let ride = try Fixtures.FIT.outdoorRide.data()
        try await a.importFile(walk, as: id)
        try await a.importFile(ride, as: id)
        let records = try await a.cloudExport()
        await #expect(throws: (any Error).self) {
            try await b.cloudRestore(records) { item in
                if item.assetHash == ContentHash(of: ride) { throw CloudFailure.missingAsset }
                return walk
            }
        }
        // Simulate the next process staging local work before retrying download.
        let reopened = try second.open()
        let staged = try await reopened.cloudExport()
        #expect(Set(staged.filter { $0.kind == .sourceMetadata }.map(\.name)) == Set(records.filter { $0.kind == .sourceMetadata }.map(\.name)))
        try await reopened.cloudRestore(records) { item in item.assetHash == ContentHash(of: ride) ? ride : walk }
        #expect(try await reopened.store.sourceRecord(id)?.currentRevision == ContentHash(of: ride))
    }
}

extension CloudRecoveryTests {
    @Test func garminSourceMetadataKeepsOffsetWithoutSummaryMeasurements() async throws {
        let a = try first.open(); let b = try second.open()
        let bytes = try Fixtures.FIT.zwiftRide.data()
        let summary = GarminSummary(activityID: 123, name: "Source title", typeKey: "virtual_ride",
            startTimeLocal: "2026-11-05 07:00:00", startTimeGMT: "2026-11-05 12:00:00",
            duration: 9876, distance: 54321, averagePower: 321, averageHeartRate: 145)
        let bridge = PersistentGarminLibrary(library: a, metadataURL: first.root.appendingPathComponent("garmin-sync.json"))
        try await bridge.ingestOriginal(bytes, contentHash: ContentHash(of: bytes), as: summary.identity, summary: summary)
        let records = try await a.cloudExport()
        let metadata = try #require(records.first { $0.kind == .garminMetadata })
        let payload = String(decoding: metadata.payload, as: UTF8.self)
        #expect(payload.contains("Source title"))
        #expect(payload.contains("-18000"))
        #expect(!payload.contains("averageHeartRate"))
        #expect(!payload.contains("averagePower"))
        #expect(!payload.contains("distance"))
        try await b.cloudRestore(records) { _ in bytes }
        #expect(try await b.store.activity(summary.identity)?.utcOffset == -18000)
    }
}
