import Foundation
import SweatKitModel

/// Explicit allowlist. There is no directory upload or generic database export.
public struct CloudRecord: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case original, sourceMetadata, garminMetadata, link, decision, tombstone, profile, featureDecision }
    public let name: String
    public let kind: Kind
    public let payload: Data
    public let subject: SourceIdentity?
    public let assetHash: ContentHash?
    public let permanentlyDeleted: Bool
    public init(key: String, kind: Kind, payload: Data, subject: SourceIdentity? = nil,
                assetHash: ContentHash? = nil, permanentlyDeleted: Bool = false) throws {
        guard (kind != .original && kind != .sourceMetadata && kind != .garminMetadata) || (subject?.source == .garmin || subject?.source == .file),
              (kind == .original) == (assetHash != nil),
              !permanentlyDeleted || (kind == .tombstone && subject != nil), payload.count < 750_000 else {
            throw CloudFailure.invalidRecord
        }
        name = ContentHash(of: Data("\(kind.rawValue):\(key)".utf8)).hex
        self.kind = kind; self.payload = payload; self.subject = subject
        self.assetHash = assetHash; self.permanentlyDeleted = permanentlyDeleted
    }
    public func validate() throws {
        guard name.count == 64, name.allSatisfy({ $0.isHexDigit }),
              (kind != .original && kind != .sourceMetadata && kind != .garminMetadata) || (subject?.source == .garmin || subject?.source == .file),
              (kind == .original) == (assetHash != nil),
              !permanentlyDeleted || (kind == .tombstone && subject != nil), payload.count < 750_000 else {
            throw CloudFailure.invalidRecord
        }
    }
}
public enum CloudFailure: Error, LocalizedError {
    case invalidRecord, missingAsset, checkpoint, accountChanged
    public var errorDescription: String? {
        switch self {
        case .invalidRecord: "The iCloud copy contains an unsupported or invalid record. Update SweatKit and retry."
        case .missingAsset: "An original is missing or damaged. The copy is incomplete; retry sync."
        case .checkpoint: "The iCloud checkpoint could not be saved. Free device storage and retry."
        case .accountChanged: "The iCloud account changed. Sign back in to the original Apple account to resume this copy."
        }
    }
}

/// Transport-independent, durable inbox/outbox. An acknowledged fetch never
/// depends on successful FIT decoding. Tombstones suppress stale uploads forever.
public struct CloudReplica: Codable, Sendable {
    public private(set) var records: [String: CloudRecord] = [:]
    public private(set) var confirmed: Set<String> = []
    public private(set) var pendingDeletes: Set<String> = []
    public init() {}
    public var deletedSubjects: Set<SourceIdentity> {
        Set(records.values.filter(\.permanentlyDeleted).compactMap(\.subject))
    }
    public var liveOriginals: [CloudRecord] {
        let deleted = deletedSubjects
        return records.values.filter { $0.kind == .original && !deleted.contains($0.subject!) }
    }
    public var pendingSaves: [CloudRecord] {
        records.values.filter { !confirmed.contains($0.name) && !pendingDeletes.contains($0.name) }
    }
    public mutating func merge(_ record: CloudRecord, confirmed remotelyConfirmed: Bool = false) throws {
        try record.validate()
        if let existing = records[record.name], existing != record {
            // Immutable record ID collisions are corruption, never silently LWW.
            throw CloudFailure.invalidRecord
        }
        records[record.name] = record
        if remotelyConfirmed { confirmed.insert(record.name) }
        let deleted = deletedSubjects
        for original in records.values where (original.kind == .original || original.kind == .sourceMetadata || original.kind == .garminMetadata) && original.subject.map({ deleted.contains($0) }) == true {
            pendingDeletes.insert(original.name)
            confirmed.remove(original.name)
        }
    }
    public mutating func acknowledgeSave(_ name: String) { confirmed.insert(name) }
    public mutating func acknowledgeDelete(_ name: String) {
        records.removeValue(forKey: name); pendingDeletes.remove(name); confirmed.remove(name)
    }
    public mutating func resetConfirmation() {
        confirmed = []
        // Losing a server zone must never turn a suppressed original back into
        // a save. Rebuild deletions from retained intent before re-seeding it.
        let deleted = deletedSubjects
        pendingDeletes = Set(records.values.filter {
            ($0.kind == .original || $0.kind == .sourceMetadata || $0.kind == .garminMetadata)
                && $0.subject.map { deleted.contains($0) } == true
        }.map(\.name))
    }
    public func validate() throws {
        for (name, record) in records {
            try record.validate()
            guard name == record.name else { throw CloudFailure.invalidRecord }
        }
        for name in confirmed.union(pendingDeletes) {
            guard name.count == 64, name.allSatisfy({ $0.isHexDigit }) else { throw CloudFailure.invalidRecord }
        }
    }
}
