import Foundation
import SweatKitModel

/// Why an identity has a tombstone.
public enum TombstoneKind: String, Codable, Sendable, CaseIterable {
    /// The activity was hidden in the app. Its data is kept.
    case hidden
    /// The activity was permanently deleted.
    case deleted
}

/// A record that keeps a hidden or deleted source identity, so the next
/// sync does not bring the activity back.
public struct Tombstone: Hashable, Codable, Sendable {
    public let identity: SourceIdentity
    public let kind: TombstoneKind
    /// When the hide or the delete was made.
    public let time: Date

    public init(identity: SourceIdentity, kind: TombstoneKind, time: Date) {
        self.identity = identity
        self.kind = kind
        self.time = time
    }

    /// The tombstones that hiding or permanently deleting an activity
    /// writes: one for every member's identity, ordered by identity.
    public static func written(
        _ kind: TombstoneKind,
        for members: Set<SourceIdentity>,
        at time: Date
    ) -> [Tombstone] {
        fatalError("unimplemented")
    }

    /// Where `identity` stands once its tombstones are taken into account.
    ///
    /// - A `.deleted` tombstone makes it `.deleted` whatever else exists.
    ///   Deletion wins over stale updates: no decision, link or re-import
    ///   reverses it, whatever its time.
    /// - Otherwise a `.hidden` tombstone makes it `.hidden` unless a restore
    ///   was made after it. A restore is a `.hidden(false)` decision that
    ///   applies to the identity. "After" is strictly later than the
    ///   identity's latest `.hidden` tombstone, so a restore at the same
    ///   time does not reverse it.
    /// - Otherwise it is `.live`.
    ///
    /// Only tombstones can make an identity anything but live here. A
    /// "hide" decision without a tombstone is the business of
    /// `DecisionRecord.isHidden`.
    public static func standing(
        of identity: SourceIdentity,
        tombstones: some Sequence<Tombstone>,
        decisions: some Sequence<DecisionRecord>
    ) -> IdentityStanding {
        fatalError("unimplemented")
    }

    /// The records that may exist: `records` without every identity that
    /// has a `.deleted` tombstone. Sync never reverses a permanent delete,
    /// so an import of a deleted identity is dropped. A hidden identity
    /// survives, because its data is kept and it can be restored.
    public static func surviving(
        _ records: Set<SourceIdentity>,
        tombstones: some Sequence<Tombstone>
    ) -> Set<SourceIdentity> {
        fatalError("unimplemented")
    }
}

/// Where a source identity stands after its tombstones.
public enum IdentityStanding: String, Codable, Sendable, CaseIterable {
    /// No tombstone holds it.
    case live
    /// A tombstone holds it hidden.
    case hidden
    /// It was permanently deleted and can never come back.
    case deleted
}
