import SweatKitIdentity

/// Add-only user intent, separate from derived rows and source originals.
/// Unioning these records is order-independent; Identity resolves conflicts.
/// No HealthKit samples or routes are present in this value.
public struct IdentityChanges: Codable, Sendable {
    public var links: [LinkRecord]
    public var decisions: [DecisionRecord]
    public var tombstones: [Tombstone]

    public init(links: [LinkRecord] = [], decisions: [DecisionRecord] = [], tombstones: [Tombstone] = []) {
        self.links = links
        self.decisions = decisions
        self.tombstones = tombstones
    }
}
