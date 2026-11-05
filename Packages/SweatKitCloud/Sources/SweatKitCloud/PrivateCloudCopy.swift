import CloudKit
import Foundation
import SweatKitModel

public struct CloudCopyStatus: Sendable {
    public var copied: Int
    public var total: Int
    public var pending: Int
    public var lastConfirmed: Date?
    public var message: String?
}

/// CKSyncEngine owns transport scheduling/checkpoints; a durable local replica
/// owns replay. No SwiftData mirroring, account-wide file enumeration or credentials.
public actor PrivateCloudCopy: CKSyncEngineDelegate {
    public static let containerIdentifier = "iCloud.com.arjunakankipati.sweatkit"
    private let directory: URL
    private let containerIdentifier: String
    private var container: CKContainer?
    private let zone = CKRecordZone(zoneName: "SweatKitRecoveryV1")
    private var engine: CKSyncEngine?
    private struct Disk: Codable {
        var replica = CloudReplica()
        var serialization: CKSyncEngine.State.Serialization?
        var account: String?
        var lastConfirmed: Date?
    }
    private var disk: Disk
    private var failure: String?
    private var checkpointFailed = false
    private var running = false
    private var accountBlocked = false

    public init(root: URL, containerIdentifier: String = PrivateCloudCopy.containerIdentifier) throws {
        directory = root.appendingPathComponent("CloudTransport", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var excluded = directory
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try excluded.setResourceValues(values)
        let url = directory.appendingPathComponent("checkpoint.json")
        disk = FileManager.default.fileExists(atPath: url.path)
            ? try JSONDecoder().decode(Disk.self, from: Data(contentsOf: url)) : Disk()
        try disk.replica.validate()
        self.containerIdentifier = containerIdentifier
    }
    private func persist() throws {
        try JSONEncoder().encode(disk).write(to: directory.appendingPathComponent("checkpoint.json"), options: .atomic)
    }
    private func assetURL(_ record: CloudRecord) -> URL { directory.appendingPathComponent(record.name + ".asset") }
    public func asset(_ record: CloudRecord) throws -> Data {
        let bytes = try Data(contentsOf: assetURL(record))
        guard ContentHash(of: bytes) == record.assetHash else { throw CloudFailure.missingAsset }
        return bytes
    }
    public func records() -> [CloudRecord] {
        disk.replica.records.values.filter { !disk.replica.pendingDeletes.contains($0.name) }
    }
    public func status() -> CloudCopyStatus {
        let originals = disk.replica.liveOriginals
        return CloudCopyStatus(copied: originals.filter { disk.replica.confirmed.contains($0.name) }.count,
            total: originals.count, pending: disk.replica.pendingSaves.count + disk.replica.pendingDeletes.count,
            lastConfirmed: disk.lastConfirmed, message: failure)
    }
    /// Check before reading and hashing a potentially large original file.
    public func needsOriginal(_ record: CloudRecord) -> Bool {
        guard record.kind == .original, let subject = record.subject,
              !FileManager.default.fileExists(atPath: assetURL(record).path) else { return false }
        return !disk.replica.deletedSubjects.contains(subject)
    }

    public func stage(_ record: CloudRecord, original: Data? = nil) throws {
        try stage([record], originals: original.map { [record.name: $0] } ?? [:])
    }

    /// A bounded batch shares one durable checkpoint. Unchanged retries do no writes.
    public func stage(_ records: [CloudRecord], originals: [String: Data]) throws {
        var next = disk.replica
        var changed = false
        for record in records {
            try record.validate()
            if next.records[record.name] != record {
                try next.merge(record)
                changed = true
            }
        }
        let deleted = next.deletedSubjects
        for record in records where record.kind == .original && !deleted.contains(record.subject!) {
            if !FileManager.default.fileExists(atPath: assetURL(record).path) {
                guard let bytes = originals[record.name], ContentHash(of: bytes) == record.assetHash else { throw CloudFailure.missingAsset }
                try bytes.write(to: assetURL(record), options: .atomic)
            }
        }
        if changed {
            let previous = disk.replica
            disk.replica = next
            do { try persist() }
            catch { disk.replica = previous; throw error }
        }
        try purgeDeletedAssets()
    }
    private func purgeDeletedAssets() throws {
        for name in disk.replica.pendingDeletes {
            let url = directory.appendingPathComponent(name + ".asset")
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
    }
    private func start() async throws -> CKSyncEngine {
        let container = self.container ?? CKContainer(identifier: containerIdentifier)
        self.container = container
        guard try await container.accountStatus() == .available else {
            throw CKError(.notAuthenticated)
        }
        let account = try await container.userRecordID().recordName
        guard disk.account == nil || disk.account == account else {
            accountBlocked = true; throw CloudFailure.accountChanged
        }
        accountBlocked = false
        disk.account = account; try persist()
        if let engine { return engine }
        var configuration = CKSyncEngine.Configuration(database: container.privateCloudDatabase,
            stateSerialization: disk.serialization, delegate: self)
        // App lifecycle and explicit controls initiate work. This keeps disabled
        // copies and account changes from sending data in the background.
        configuration.automaticallySync = false
        let next = CKSyncEngine(configuration)
        engine = next
        return next
    }
    public func sync() async throws {
        guard !running else { return }
        running = true; failure = nil; checkpointFailed = false
        defer { running = false }
        do {
            let engine = try await start()
            // Always fetch tombstones before proposing uploads from an offline device.
            do { try await engine.fetchChanges() }
            catch let error as CKError where error.code == .zoneNotFound { /* First copy creates the private zone below. */ }
            guard !checkpointFailed, !accountBlocked else { throw CloudFailure.checkpoint }
            engine.state.add(pendingDatabaseChanges: [.saveZone(zone)])
            schedule(engine)
            try await engine.sendChanges()
            guard !checkpointFailed else { throw CloudFailure.checkpoint }
            if let failure { throw NSError(domain: "SweatKitCloud", code: 1, userInfo: [NSLocalizedDescriptionKey: failure]) }
            if disk.replica.pendingSaves.isEmpty && disk.replica.pendingDeletes.isEmpty {
                disk.lastConfirmed = .now; try persist()
            }
        } catch {
            failure = Self.message(error)
            // Reload the durable checkpoint on the next attempt after I/O failure;
            // never advance past records that failed to reach disk.
            if checkpointFailed {
                engine = nil
                disk = try JSONDecoder().decode(Disk.self, from: Data(contentsOf: directory.appendingPathComponent("checkpoint.json")))
                try disk.replica.validate()
            }
            throw error
        }
    }
    private func schedule(_ engine: CKSyncEngine) {
        let saves = disk.replica.pendingSaves.map { CKSyncEngine.PendingRecordZoneChange.saveRecord(.init(recordName: $0.name, zoneID: zone.zoneID)) }
        let deletes = disk.replica.pendingDeletes.map { CKSyncEngine.PendingRecordZoneChange.deleteRecord(.init(recordName: $0, zoneID: zone.zoneID)) }
        // A tombstone can replace an already queued save.
        engine.state.remove(pendingRecordZoneChanges: disk.replica.pendingDeletes.map { .saveRecord(.init(recordName: $0, zoneID: zone.zoneID)) })
        engine.state.add(pendingRecordZoneChanges: saves + deletes)
    }
    public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        guard !checkpointFailed else { return }
        do {
            switch event {
            case .stateUpdate(let update):
                disk.serialization = update.stateSerialization
            case .accountChange(let change):
                switch change.changeType {
                case .signIn(let user):
                    if let account = disk.account, account != user.recordName { accountBlocked = true }
                case .signOut, .switchAccounts: accountBlocked = true
                @unknown default: accountBlocked = true
                }
                if accountBlocked { failure = CloudFailure.accountChanged.localizedDescription }
            case .fetchedRecordZoneChanges(let changes):
                // Persist assets and records before accepting the next engine token.
                for change in changes.modifications { try receive(change.record) }
                for deletion in changes.deletions {
                    guard deletion.recordID.recordName.count == 64, deletion.recordID.recordName.allSatisfy({ $0.isHexDigit }) else { throw CloudFailure.invalidRecord }
                    disk.replica.acknowledgeDelete(deletion.recordID.recordName)
                    let url = directory.appendingPathComponent(deletion.recordID.recordName + ".asset")
                    if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
                }
                try purgeDeletedAssets()
            case .fetchedDatabaseChanges(let changes):
                if changes.deletions.contains(where: { $0.zoneID == zone.zoneID }) { disk.replica.resetConfirmation() }
            case .sentRecordZoneChanges(let changes):
                for record in changes.savedRecords { disk.replica.acknowledgeSave(record.recordID.recordName) }
                for id in changes.deletedRecordIDs { disk.replica.acknowledgeDelete(id.recordName) }
                for failed in changes.failedRecordSaves {
                    if failed.error.code == .serverRecordChanged, let server = failed.error.serverRecord {
                        try receive(server) // Immutable same-ID records must be identical.
                    } else { failure = Self.message(failed.error) }
                }
                for error in changes.failedRecordDeletes.values where error.code != .unknownItem { failure = Self.message(error) }
                for (id, error) in changes.failedRecordDeletes where error.code == .unknownItem { disk.replica.acknowledgeDelete(id.recordName) }
            case .sentDatabaseChanges(let changes):
                if let error = changes.failedZoneSaves.first?.error { failure = Self.message(error) }
            case .didFetchRecordZoneChanges(let changes):
                if let error = changes.error, error.code != .zoneNotFound { failure = Self.message(error) }
            default: break
            }
            try persist()
        } catch { checkpointFailed = true; failure = Self.message(error) }
    }
    private func receive(_ record: CKRecord) throws {
        guard record.recordType == "RecoveryRecord", let payload = record["envelope"] as? Data else { throw CloudFailure.invalidRecord }
        let value = try JSONDecoder().decode(CloudRecord.self, from: payload)
        try value.validate()
        guard value.name == record.recordID.recordName else { throw CloudFailure.invalidRecord }
        if let existing = disk.replica.records[value.name], existing != value { throw CloudFailure.invalidRecord }
        if value.kind == .original, !disk.replica.deletedSubjects.contains(value.subject!) {
            if let url = (record["original"] as? CKAsset)?.fileURL {
                let bytes = try Data(contentsOf: url)
                guard ContentHash(of: bytes) == value.assetHash else { throw CloudFailure.missingAsset }
                try bytes.write(to: assetURL(value), options: .atomic)
            } else {
                // A create/create conflict may return asset metadata without a
                // downloaded URL. Identical immutable local bytes are sufficient.
                _ = try asset(value)
            }
        }
        try disk.replica.merge(value, confirmed: true)
    }
    public func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard !checkpointFailed, !accountBlocked else { return nil }
        let changes = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { id in await self.record(id) }
    }
    private func record(_ id: CKRecord.ID) -> CKRecord? {
        guard let value = disk.replica.records[id.recordName], !disk.replica.pendingDeletes.contains(value.name) else { return nil }
        do {
            let record = CKRecord(recordType: "RecoveryRecord", recordID: id)
            record["envelope"] = try JSONEncoder().encode(value) as CKRecordValue
            if value.kind == .original {
                _ = try asset(value)
                record["original"] = CKAsset(fileURL: assetURL(value))
            }
            return record
        } catch { failure = Self.message(error); return nil }
    }
    public static func message(_ error: Error) -> String {
        guard let error = error as? CKError else { return error.localizedDescription }
        switch error.code {
        case .notAuthenticated: return "Sign in to iCloud in device Settings, then retry. Your library remains on this device."
        case .quotaExceeded: return "iCloud storage is full. Free iCloud storage, then retry. Uncopied originals remain on this device."
        case .networkFailure, .networkUnavailable: return "iCloud is unreachable. Your library works offline; retry when connected."
        case .permissionFailure, .missingEntitlement, .badContainer: return "iCloud is not configured for this build. Check the container and signing capabilities."
        case .serviceUnavailable, .requestRateLimited: return "iCloud is temporarily busy. Copying will retry on the next refresh."
        default: return "iCloud could not finish copying. Retry sync. (\(error.errorCode))"
        }
    }
}
