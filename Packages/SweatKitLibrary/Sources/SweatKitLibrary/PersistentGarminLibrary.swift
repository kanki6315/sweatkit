import Foundation
import SweatKitModel
import SweatKitStore
import SweatKitSync

/// Bridges reconciliation to the real import pipeline. Checkpoints and remote
/// summaries are atomically replaced on disk; originals remain in LibraryStore.
/// Keep one instance per library and let GarminSync serialize its operations.
public actor PersistentGarminLibrary: GarminLibrary {
    private let library: ActivityLibrary
    private let metadataURL: URL

    private struct Metadata: Codable {
        var version = 1
        var state: GarminSyncState?
        var summaries: [String: GarminSummary] = [:]
    }

    public enum Failure: Error {
        case unsupportedMetadataVersion(Int)
        case identityMismatch
        case contentHashMismatch
        case unknownActivity
    }

    public init(library: ActivityLibrary, metadataURL: URL) {
        self.library = library
        self.metadataURL = metadataURL
    }

    public func knownGarminActivities() async throws -> [SourceIdentity: KnownGarminActivity] {
        let records = try await library.store.sourceRecords()
        let metadata = try read()
        var known: [SourceIdentity: KnownGarminActivity] = [:]
        for record in records where record.source == .garmin && record.state != .deleted {
            guard let summary = metadata.summaries[record.identity.description] else { continue }
            known[record.identity] = KnownGarminActivity(summary: summary,
                contentHash: record.currentRevision, removedAtSource: record.state == .removedAtSource)
        }
        return known
    }

    public func garminTombstones() async throws -> Set<SourceIdentity> {
        let deleted = try await library.deletedIdentities().filter { $0.source == .garmin }
        return Set(try await library.store.sourceRecords().filter {
            $0.source == .garmin && ($0.state == .hidden || $0.state == .deleted)
        }.map(\.identity)).union(deleted)
    }

    public func loadSyncState() async throws -> GarminSyncState? { try read().state }

    public func saveSyncState(_ state: GarminSyncState) async throws {
        var metadata = try read()
        metadata.state = state
        try write(metadata)
    }

    public func ingestOriginal(_ original: Data, contentHash: ContentHash,
                               as identity: SourceIdentity, summary: GarminSummary) async throws {
        guard summary.identity == identity else { throw Failure.identityMismatch }
        guard ContentHash(of: original) == contentHash else { throw Failure.contentHashMismatch }
        guard !(try await garminTombstones()).contains(identity) else { return }
        // Publish the summary only after the complete import. A crash before
        // this write causes an idempotent retry, never a false "already synced".
        try await library.importFile(original, as: identity, fallbackUTCOffset: Self.utcOffset(summary))
        try await updateSummary(summary, for: identity)
    }

    public func updateSummary(_ summary: GarminSummary, for identity: SourceIdentity) async throws {
        guard summary.identity == identity else { throw Failure.identityMismatch }
        guard try await library.store.sourceRecord(identity) != nil else { throw Failure.unknownActivity }
        var metadata = try read()
        metadata.summaries[identity.description] = summary
        try write(metadata)
    }

    public func markRemovedAtSource(_ identity: SourceIdentity) async throws {
        guard let record = try await library.store.sourceRecord(identity), record.state == .active else { return }
        try await library.store.setState(.removedAtSource, for: identity)
    }

    public func markPresentAtSource(_ identity: SourceIdentity) async throws {
        guard let record = try await library.store.sourceRecord(identity), record.state == .removedAtSource else { return }
        try await library.store.setState(.active, for: identity)
    }

    private func read() throws -> Metadata {
        guard FileManager.default.fileExists(atPath: metadataURL.path) else { return Metadata() }
        let metadata = try JSONDecoder().decode(Metadata.self, from: Data(contentsOf: metadataURL))
        guard metadata.version == 1 else { throw Failure.unsupportedMetadataVersion(metadata.version) }
        return metadata
    }

    private func write(_ metadata: Metadata) throws {
        try FileManager.default.createDirectory(at: metadataURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(metadata).write(to: metadataURL, options: .atomic)
    }

    private static func utcOffset(_ summary: GarminSummary) -> Int? {
        guard let local = summary.startTimeLocal, let utc = summary.startTime else { return nil }
        var localSummary = summary
        localSummary.startTimeGMT = local
        guard let localAsUTC = localSummary.startTime else { return nil }
        let offset = localAsUTC.timeIntervalSince(utc)
        guard abs(offset) <= 14 * 3600 else { return nil }
        return Int(offset)
    }
}
