import Foundation
import SweatKitModel
import SweatKitStore
import SweatKitIdentity
import SweatKitCloud
import SweatKitSync

private struct CloudSourceEvent: Codable {
    var time: Date
    var source: SourceRecord
}
/// Only original source descriptors, not Garmin summary measurements.
private struct CloudGarminMetadata: Codable {
    var identity: SourceIdentity
    var name: String?
    var typeKey: String?
    var manufacturer: String?
    var utcOffset: Int?
    init(_ summary: GarminSummary) {
        identity = summary.identity; name = summary.name; typeKey = summary.typeKey
        manufacturer = summary.manufacturer; utcOffset = PersistentGarminLibrary.utcOffset(summary)
    }
}
private struct CloudGarminEvent: Codable {
    var time: Date
    var metadata: CloudGarminMetadata
}
private struct CloudProfileEvent: Codable {
    var time: Date
    var profile: AthleteProfile
}
private struct CloudLibraryJournal: Codable {
    var records: [String: CloudRecord] = [:]
    var observed: [String: ContentHash] = [:]
    var recovering: Set<String>? = []
}

extension ActivityLibrary {
    /// Local permanent erasure includes the transport's duplicate asset files,
    /// even when the user has paused networking. Tombstones remain for retry.
    func cloudPurgeDeletedAssets(_ identities: Set<SourceIdentity>) async throws {
        for source in try await store.sourceRecords() where identities.contains(source.identity) && source.source != .healthKit {
            for revision in source.revisions {
                let item = try CloudRecord(key: "\(source.identity)#\(revision.contentHash)", kind: .original,
                    payload: Data(), subject: source.identity, assetHash: revision.contentHash)
                let url = store.root.appendingPathComponent("CloudTransport/\(item.name).asset")
                if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            }
        }
    }

    func recordCloudGarminMetadata(_ summary: GarminSummary) async throws {
        let token = summary.identity
        await begin(token); defer { end(token) }
        guard !(try deletedIdentities()).contains(token) else { return }
        var journal = try cloudJournal()
        try addGarminMetadata(summary, to: &journal)
        try saveCloudJournal(journal)
    }
    private func addGarminMetadata(_ summary: GarminSummary, to journal: inout CloudLibraryJournal) throws {
        let metadata = CloudGarminMetadata(summary)
        let key = "garmin-metadata:\(summary.identity)"
        let hash = ContentHash(of: try Self.cloudEncode(metadata))
        guard journal.observed[key] != hash else { return }
        let item = try CloudRecord(key: UUID().uuidString, kind: .garminMetadata,
            payload: Self.cloudEncode(CloudGarminEvent(time: .now, metadata: metadata)), subject: summary.identity)
        journal.records[item.name] = item; journal.observed[key] = hash
    }

    private var cloudJournalURL: URL { store.root.appendingPathComponent("cloud-decisions.json") }
    private func cloudJournal() throws -> CloudLibraryJournal {
        guard FileManager.default.fileExists(atPath: cloudJournalURL.path) else { return .init() }
        return try JSONDecoder().decode(CloudLibraryJournal.self, from: Data(contentsOf: cloudJournalURL))
    }
    private func saveCloudJournal(_ journal: CloudLibraryJournal) throws {
        try Self.cloudEncode(journal).write(to: cloudJournalURL, options: .atomic)
    }
    private static func cloudEncode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(value)
        // DecisionRecord.members is a Set; canonicalize its JSON array so the
        // same immutable action has identical bytes on every process/device.
        if var object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
           let members = object["members"] as? [[String: Any]] {
            object["members"] = try members.sorted {
                let left = try JSONSerialization.data(withJSONObject: $0, options: .sortedKeys)
                let right = try JSONSerialization.data(withJSONObject: $1, options: .sortedKeys)
                return left.lexicographicallyPrecedes(right)
            }
            return try JSONSerialization.data(withJSONObject: object, options: .sortedKeys)
        }
        return bytes
    }

    /// Feature owners call this only for explicit user intent, with an audited
    /// payload schema. Route geometry, including derived Health geometry, is forbidden.
    public func appendCloudDecision(_ envelope: CloudDecisionEnvelope) async throws {
        let token = SourceIdentity(source: .file, externalID: "cloud-decision")
        await begin(token); defer { end(token) }
        var journal = try cloudJournal()
        let item = try CloudRecord(key: envelope.id.uuidString, kind: .featureDecision, payload: Self.cloudEncode(envelope))
        if let old = journal.records[item.name], old != item { throw CloudFailure.invalidRecord }
        journal.records[item.name] = item
        try saveCloudJournal(journal)
    }
    public func cloudDecisions(namespace: String) throws -> [CloudDecisionEnvelope] {
        try cloudJournal().records.values.filter { $0.kind == .featureDecision }.map {
            try JSONDecoder().decode(CloudDecisionEnvelope.self, from: $0.payload)
        }.filter { $0.namespace == namespace }.sorted { ($0.time, $0.id.uuidString) < ($1.time, $1.id.uuidString) }
    }

    /// Deliberately projects safe fields instead of uploading the recovery files.
    /// In particular, identity matching candidates and activityID are never copied.
    public func cloudExport() async throws -> [CloudRecord] {
        let token = SourceIdentity(source: .file, externalID: "cloud-export")
        await begin(token); defer { end(token) }
        var output: [CloudRecord] = []
        let identity = try readIdentityJournal()
        for link in identity.links {
            output.append(try CloudRecord(key: link.name.rawValue, kind: .link, payload: Self.cloudEncode(link)))
        }
        for decision in identity.decisions {
            output.append(try CloudRecord(key: decision.name.rawValue, kind: .decision, payload: Self.cloudEncode(decision)))
        }
        for tombstone in identity.tombstones {
            let payload = try Self.cloudEncode(tombstone)
            output.append(try CloudRecord(key: ContentHash(of: payload).hex, kind: .tombstone, payload: payload,
                subject: tombstone.identity, permanentlyDeleted: tombstone.kind == .deleted))
        }
        var journal = try cloudJournal()
        let deleted = Set(identity.tombstones.filter { $0.kind == .deleted }.map(\.identity))
        // Upgrade the existing app's Garmin cache through a typed, narrow
        // projection. Never copy the sync checkpoint or summary measurements.
        struct GarminCache: Decodable { var version: Int; var summaries: [String: GarminSummary] }
        let cacheURL = store.root.appendingPathComponent("garmin-sync.json")
        if FileManager.default.fileExists(atPath: cacheURL.path) {
            let cache = try JSONDecoder().decode(GarminCache.self, from: Data(contentsOf: cacheURL))
            guard cache.version == 1 else { throw CloudFailure.invalidRecord }
            for summary in cache.summaries.values where !deleted.contains(summary.identity) {
                let key = "garmin-metadata:\(summary.identity)"
                // Bootstrap only; the owning bridge records subsequent changes.
                if journal.observed[key] == nil { try addGarminMetadata(summary, to: &journal) }
            }
        }
        for var source in try await store.sourceRecords() where source.source != .healthKit && !deleted.contains(source.identity) {
            source.activityID = nil
            for revision in source.revisions {
                output.append(try CloudRecord(key: "\(source.identity)#\(revision.contentHash)", kind: .original,
                    payload: Data(), subject: source.identity, assetHash: revision.contentHash))
            }
            let hash = ContentHash(of: try Self.cloudEncode(source))
            let key = source.identity.description
            if journal.observed[key] != hash && !(journal.recovering ?? []).contains(key) {
                let item = try CloudRecord(key: UUID().uuidString, kind: .sourceMetadata,
                    payload: Self.cloudEncode(CloudSourceEvent(time: .now, source: source)), subject: source.identity)
                journal.records[item.name] = item; journal.observed[key] = hash
            }
        }
        if let profile = try await store.profile() {
            let hash = ContentHash(of: try Self.cloudEncode(profile))
            if journal.observed["profile"] != hash {
                let item = try CloudRecord(key: UUID().uuidString, kind: .profile,
                    payload: Self.cloudEncode(CloudProfileEvent(time: .now, profile: profile)))
                journal.records[item.name] = item; journal.observed["profile"] = hash
            }
        }
        try saveCloudJournal(journal)
        return output + journal.records.values.filter { $0.subject.map { !deleted.contains($0) } ?? true }
    }

    /// Assets are read only through a non-Health source's revision reference.
    public func cloudOriginal(_ record: CloudRecord) async throws -> Data {
        guard record.kind == .original, let subject = record.subject, subject.source != .healthKit,
              let hash = record.assetHash,
              let source = try await store.sourceRecord(subject), source.revisions.contains(where: { $0.contentHash == hash }),
              let bytes = try await store.original(hash), ContentHash(of: bytes) == hash else { throw CloudFailure.missingAsset }
        return bytes
    }

    /// Replay is restartable. Decisions/tombstones commit before any originals;
    /// a wiped device can never briefly re-create a permanently deleted activity.
    public func cloudRestore(_ records: [CloudRecord], asset: @Sendable (CloudRecord) async throws -> Data) async throws {
        // Capture local edits before resolving downloaded events.
        _ = try await cloudExport()
        let token = SourceIdentity(source: .file, externalID: "cloud-restore")
        await begin(token)
        var locked = true
        defer { if locked { end(token) } }
        do {
            var identity = try readIdentityJournal()
            var journal = try cloudJournal()
            for item in records {
                try item.validate()
                switch item.kind {
                case .link:
                    let value = try JSONDecoder().decode(LinkRecord.self, from: item.payload)
                    if !identity.links.contains(value) { identity.links.append(value) }
                case .decision:
                    let value = try JSONDecoder().decode(DecisionRecord.self, from: item.payload)
                    if !identity.decisions.contains(value) { identity.decisions.append(value) }
                case .tombstone:
                    let value = try JSONDecoder().decode(Tombstone.self, from: item.payload)
                    guard value.identity == item.subject, (value.kind == .deleted) == item.permanentlyDeleted else { throw CloudFailure.invalidRecord }
                    if !identity.tombstones.contains(value) { identity.tombstones.append(value) }
                case .sourceMetadata, .garminMetadata, .profile, .featureDecision: journal.records[item.name] = item
                case .original: break
                }
            }
            try writeIdentityJournal(identity)
            try saveCloudJournal(journal)
            try await reconcileIdentity()
        } catch { throw error }
        let journal = try cloudJournal()
        let deleted = Set(try readIdentityJournal().tombstones.filter { $0.kind == .deleted }.map(\.identity))
        let originals = records.filter { $0.kind == .original && !deleted.contains($0.subject!) }
        // Metadata winner is deterministic; all immutable revisions remain available.
        var sources: [SourceIdentity: (String, CloudSourceEvent)] = [:]
        var allRevisions: [SourceIdentity: [ContentHash: SourceRevision]] = [:]
        for item in journal.records.values where item.kind == .sourceMetadata {
            let value = try JSONDecoder().decode(CloudSourceEvent.self, from: item.payload)
            guard value.source.source != .healthKit, value.source.identity == item.subject, value.source.activityID == nil else { throw CloudFailure.invalidRecord }
            for revision in value.source.revisions {
                if let old = allRevisions[value.source.identity]?[revision.contentHash], old.addedAt <= revision.addedAt { continue }
                allRevisions[value.source.identity, default: [:]][revision.contentHash] = revision
            }
            if let old = sources[value.source.identity], (old.1.time, old.0) >= (value.time, item.name) { continue }
            sources[value.source.identity] = (item.name, value)
        }
        var garmin: [SourceIdentity: (String, CloudGarminEvent)] = [:]
        for item in journal.records.values where item.kind == .garminMetadata {
            let value = try JSONDecoder().decode(CloudGarminEvent.self, from: item.payload)
            guard value.metadata.identity == item.subject, value.metadata.identity.source == .garmin else { throw CloudFailure.invalidRecord }
            if let old = garmin[value.metadata.identity], (old.1.time, old.0) >= (value.time, item.name) { continue }
            garmin[value.metadata.identity] = (item.name, value)
        }
        var replay = try cloudJournal()
        replay.recovering = Set(sources.keys.filter { !deleted.contains($0) }.map(\.description))
        try saveCloudJournal(replay)
        for (id, entry) in sources where !deleted.contains(id) {
            let source = entry.1.source
            let revisions = Array(allRevisions[id, default: [:]].values).sorted { ($0.contentHash == source.currentRevision ? 1 : 0, $0.addedAt, $0.contentHash.hex) < ($1.contentHash == source.currentRevision ? 1 : 0, $1.addedAt, $1.contentHash.hex) }
            for revision in revisions {
                let bytes: Data
                if let item = originals.first(where: { $0.subject == id && $0.assetHash == revision.contentHash }) {
                    bytes = try await asset(item)
                } else if let local = try await store.sourceRecord(id),
                          local.source != .healthKit, local.revisions.contains(where: { $0.contentHash == revision.contentHash }),
                          let original = try await store.original(revision.contentHash) {
                    // A local import made during the network fetch is not in
                    // that fetch's batch. Keep it; the next copy will send it.
                    bytes = original
                } else { throw CloudFailure.missingAsset }
                guard ContentHash(of: bytes) == revision.contentHash else { throw CloudFailure.missingAsset }
                _ = try await importBytes(bytes, as: id, fallbackUTCOffset: garmin[id]?.1.metadata.utcOffset, at: revision.addedAt, alreadyLocked: true)
            }
            if (source.state == .active || source.state == .removedAtSource), try await store.sourceRecord(id) != nil {
                try await store.setState(source.state, for: id)
            }
        }
        let profiles = try journal.records.values.filter { $0.kind == .profile }.map {
            ($0.name, try JSONDecoder().decode(CloudProfileEvent.self, from: $0.payload))
        }
        if let winner = profiles.max(by: { ($0.1.time, $0.0) < ($1.1.time, $1.0) }) { try await store.saveProfile(winner.1.profile) }
        // Record projections after replay, so receiving a winner never creates a new local edit.
        var updated = try cloudJournal()
        for var source in try await store.sourceRecords() where source.source != .healthKit {
            source.activityID = nil
            updated.observed[source.identity.description] = ContentHash(of: try Self.cloudEncode(source))
        }
        for (id, value) in garmin { updated.observed["garmin-metadata:\(id)"] = ContentHash(of: try Self.cloudEncode(value.1.metadata)) }
        if let profile = try await store.profile() { updated.observed["profile"] = ContentHash(of: try Self.cloudEncode(profile)) }
        try await reconcileIdentity()
        updated.recovering = []
        try saveCloudJournal(updated)
        end(token); locked = false
        _ = try await recompute()
    }
}
