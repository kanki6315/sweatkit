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
    // Monotonic for this actor: a stale in-flight checkpoint cannot resurrect
    // summaries after a coordinated deletion has returned.
    private var deletedGarminIDs: Set<SourceIdentity> = []

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
        try await refreshDeletionKnowledge()
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
        try await refreshDeletionKnowledge()
        _ = try read()
        return Set(try await library.store.sourceRecords().filter {
            $0.source == .garmin && ($0.state == .hidden || $0.state == .deleted)
        }.map(\.identity)).union(deletedGarminIDs)
    }

    public func loadSyncState() async throws -> GarminSyncState? {
        try await refreshDeletionKnowledge()
        return try read().state
    }

    /// App deletion goes through the same bridge actor used by GarminSync.
    /// The library durably erases recordings first; only then are cached
    /// summaries and queued retry summaries removed from the checkpoint file.
    /// Safe to retry if metadata cleanup fails after the library deletion.
    public func permanentlyDelete(_ activity: SourceIdentity) async throws {
        try await library.permanentlyDelete(activity)
        try await pruneDeletedSummaries()
    }

    /// Also used after applying remote tombstones, and at startup. No second
    /// file writer is created; the existing bridge owns this cleanup.
    public func pruneDeletedSummaries() async throws {
        try await refreshDeletionKnowledge()
        _ = try read()
    }

    private func refreshDeletionKnowledge() async throws {
        deletedGarminIDs.formUnion(try await library.deletedIdentities().filter { $0.source == .garmin })
    }

    public func saveSyncState(_ state: GarminSyncState) async throws {
        try await refreshDeletionKnowledge()
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
        do {
            try await library.importFile(original, as: identity, fallbackUTCOffset: Self.utcOffset(summary))
        } catch LibraryError.permanentlyDeleted {
            // A confirmed deletion can arrive while a download is in flight.
            // It is intentional suppression, not a retryable import failure.
            try await pruneDeletedSummaries()
            return
        }
        try await updateSummary(summary, for: identity)
    }

    public func updateSummary(_ summary: GarminSummary, for identity: SourceIdentity) async throws {
        guard summary.identity == identity else { throw Failure.identityMismatch }
        let record = try await library.store.sourceRecord(identity)
        try await refreshDeletionKnowledge()
        if deletedGarminIDs.contains(identity) { _ = try read(); return }
        guard record != nil else { throw Failure.unknownActivity }
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
        var metadata = try JSONDecoder().decode(Metadata.self, from: Data(contentsOf: metadataURL))
        guard metadata.version == 1 else { throw Failure.unsupportedMetadataVersion(metadata.version) }
        if prune(&metadata) { try write(metadata) }
        return metadata
    }

    @discardableResult private func prune(_ metadata: inout Metadata) -> Bool {
        let oldSummaries = metadata.summaries.count
        let oldPending = metadata.state?.pending.count
        metadata.summaries = metadata.summaries.filter { !deletedGarminIDs.contains($0.value.identity) }
        if var state = metadata.state {
            state.pending = state.pending.filter { !deletedGarminIDs.contains($0.value.summary.identity) }
            metadata.state = state
        }
        return oldSummaries != metadata.summaries.count || oldPending != metadata.state?.pending.count
    }

    private func write(_ value: Metadata) throws {
        var metadata = value
        prune(&metadata)
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
