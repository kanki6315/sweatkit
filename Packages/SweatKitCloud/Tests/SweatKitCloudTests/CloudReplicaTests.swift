import Foundation
import Testing
import SweatKitModel
@testable import SweatKitCloud

struct CloudReplicaTests {
    let id = SourceIdentity(source: .garmin, externalID: "123")
    func original() throws -> CloudRecord {
        try CloudRecord(key: "original", kind: .original, payload: Data(), subject: id, assetHash: ContentHash(of: Data([1])))
    }
    func deletion() throws -> CloudRecord {
        try CloudRecord(key: "delete", kind: .tombstone, payload: Data(), subject: id, permanentlyDeleted: true)
    }
    @Test func offlineDeletionWinsInEitherOrderAndAfterCheckpoint() throws {
        var a = CloudReplica(); var b = CloudReplica()
        let original = try original(); let deletion = try deletion()
        try a.merge(original, confirmed: true); try a.merge(deletion)
        try b.merge(deletion); try b.merge(original)
        #expect(a.liveOriginals.isEmpty && b.liveOriginals.isEmpty)
        #expect(a.pendingDeletes == b.pendingDeletes)
        let restored = try JSONDecoder().decode(CloudReplica.self, from: JSONEncoder().encode(a))
        #expect(restored.deletedSubjects == [id])
        #expect(restored.pendingDeletes == [original.name])
        b.resetConfirmation()
        #expect(!b.pendingSaves.contains(original))
        #expect(b.pendingDeletes == [original.name])
        b.acknowledgeDelete(original.name)
        try b.merge(original) // A third stale device must not resurrect its original.
        #expect(b.pendingDeletes == [original.name])
    }
    @Test func confirmationRequiresAcknowledgementAndRetriesAreIdempotent() throws {
        var replica = CloudReplica(); let record = try original()
        try replica.merge(record); try replica.merge(record)
        #expect(replica.pendingSaves.count == 1)
        #expect(replica.confirmed.isEmpty)
        replica.acknowledgeSave(record.name)
        try replica.merge(record)
        #expect(replica.pendingSaves.isEmpty)
        replica.resetConfirmation()
        #expect(replica.pendingSaves.count == 1)
    }
    @Test func healthAssetsAndImmutableCollisionsAreRejected() throws {
        #expect(throws: (any Error).self) {
            try CloudRecord(key: "health", kind: .original, payload: Data(),
                subject: SourceIdentity(source: .healthKit, externalID: UUID().uuidString), assetHash: ContentHash(of: Data()))
        }
        var replica = CloudReplica()
        try replica.merge(CloudRecord(key: "same", kind: .decision, payload: Data([1])))
        #expect(throws: (any Error).self) { try replica.merge(CloudRecord(key: "same", kind: .decision, payload: Data([2]))) }
    }
    @Test func unknownFeatureDecisionSurvivesTransport() throws {
        let envelope = CloudDecisionEnvelope(namespace: "routes.manual", version: 99, time: .now, device: "test", payload: Data("opaque user intent".utf8))
        let record = try CloudRecord(key: envelope.id.uuidString, kind: .featureDecision, payload: JSONEncoder().encode(envelope))
        var replica = CloudReplica(); try replica.merge(record)
        let restored = try JSONDecoder().decode(CloudReplica.self, from: JSONEncoder().encode(replica))
        #expect(restored.records[record.name] == record)
    }
}

struct CloudDiskTests {
    @Test func checkpointSurvivesRestartAndDeletionPurgesStagedAsset() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let identity = SourceIdentity(source: .garmin, externalID: "disk-test")
        let bytes = Data("original".utf8)
        let original = try CloudRecord(key: "disk", kind: .original, payload: Data(), subject: identity, assetHash: ContentHash(of: bytes))
        let first = try PrivateCloudCopy(root: root)
        try await first.stage(original, original: bytes)
        let reopened = try PrivateCloudCopy(root: root)
        #expect(try await reopened.asset(original) == bytes)
        #expect(await reopened.status().copied == 0)
        #expect(await reopened.status().pending == 1)
        let tombstone = try CloudRecord(key: "delete", kind: .tombstone, payload: Data(), subject: identity, permanentlyDeleted: true)
        try await reopened.stage(tombstone)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("CloudTransport/\(original.name).asset").path))
        let final = try PrivateCloudCopy(root: root)
        try await final.stage(original, original: bytes)
        #expect(await final.status().total == 0)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("CloudTransport/\(original.name).asset").path))
        #expect(try root.appendingPathComponent("CloudTransport").resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }
    @Test func corruptCheckpointFailsClosed() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("CloudTransport")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("invalid".utf8).write(to: directory.appendingPathComponent("checkpoint.json"))
        #expect(throws: (any Error).self) { try PrivateCloudCopy(root: root) }
    }
}

extension CloudReplicaTests {
    @Test func deletingOneSourceKeepsAnotherSourcesSharedOriginal() throws {
        var replica = CloudReplica()
        let first = try original()
        let second = try CloudRecord(key: "other-source", kind: .original, payload: Data(),
            subject: SourceIdentity(source: .garmin, externalID: "456"), assetHash: first.assetHash)
        try replica.merge(first); try replica.merge(second); try replica.merge(deletion())
        #expect(replica.liveOriginals == [second])
        #expect(replica.pendingDeletes == [first.name])
    }
}
