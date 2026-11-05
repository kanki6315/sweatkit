import Foundation
import SweatKitGarmin
import SweatKitModel

/// Where Garmin activities come from. Sync works only through this, so tests
/// can script a source that changes between requests.
///
/// Errors are `GarminError`, so a refused key, a refused token and a rate
/// limit keep their meaning across any implementation.
public protocol GarminRemoteSource: Sendable {
    /// One page of activities whose local start date is in the query's range,
    /// both ends included, in the query's order, from its zero-based offset.
    func listActivities(_ query: ActivityQuery) async throws(GarminError) -> [GarminSummary]

    /// One activity's full summary.
    func activityDetail(id: Int64) async throws(GarminError) -> GarminActivityDetail

    /// One activity's download exactly as served: a zip holding the original.
    func downloadOriginal(id: Int64) async throws(GarminError) -> Data
}

/// The remote source backed by `SweatKitGarmin`'s client.
public struct GarminClientSource: GarminRemoteSource {
    public let client: GarminClient

    public init(client: GarminClient) {
        self.client = client
    }

    public func listActivities(_ query: ActivityQuery) async throws(GarminError) -> [GarminSummary] {
        try await client.activities(query).map(GarminSummary.init)
    }

    public func activityDetail(id: Int64) async throws(GarminError) -> GarminActivityDetail {
        GarminActivityDetail(try await client.activity(id: id))
    }

    public func downloadOriginal(id: Int64) async throws(GarminError) -> Data {
        try await client.originalFile(activityID: id).data
    }
}

/// What the library holds for one Garmin identity, as sync last left it.
public struct KnownGarminActivity: Sendable, Hashable, Codable {
    /// The summary last seen.
    public var summary: GarminSummary
    /// The hash of the original last ingested, or nil if no file is held.
    public var contentHash: ContentHash?
    /// Marked "removed at source" by an earlier sync.
    public var removedAtSource: Bool

    public init(summary: GarminSummary, contentHash: ContentHash?, removedAtSource: Bool = false) {
        self.summary = summary
        self.contentHash = contentHash
        self.removedAtSource = removedAtSource
    }
}

/// The local library as sync sees it: what it knows, and the actions sync asks
/// of it. The real implementation sits on storage and the import pipeline; this
/// package has an in-memory one in its tests only.
///
/// Sync calls one method at a time and never concurrently.
public protocol GarminLibrary: Sendable {
    /// Every Garmin identity the library holds, keyed by identity. Hidden
    /// activities are included; permanently deleted ones are not.
    func knownGarminActivities() async throws -> [SourceIdentity: KnownGarminActivity]

    /// Garmin identities that carry a tombstone, from hiding or permanent deletion.
    /// Sync never ingests, updates or marks these.
    func garminTombstones() async throws -> Set<SourceIdentity>

    /// The stored checkpoints, or nil before the first sync.
    func loadSyncState() async throws -> GarminSyncState?

    func saveSyncState(_ state: GarminSyncState) async throws

    /// Ingest this original under this identity, with this summary. A new
    /// identity is a new record; a known one gets a new revision. `contentHash`
    /// is the SHA-256 of `original`. Sync calls this only when the hash differs
    /// from the one the library holds.
    func ingestOriginal(_ original: Data, contentHash: ContentHash, as identity: SourceIdentity, summary: GarminSummary) async throws

    /// Replace the summary held for a known identity. The file is unchanged.
    func updateSummary(_ summary: GarminSummary, for identity: SourceIdentity) async throws

    /// Mark a known identity "removed at source". Its data is kept.
    func markRemovedAtSource(_ identity: SourceIdentity) async throws

    /// Clear "removed at source" from an identity that Garmin lists again.
    func markPresentAtSource(_ identity: SourceIdentity) async throws
}
