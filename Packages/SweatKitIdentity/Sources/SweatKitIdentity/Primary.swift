import SweatKitModel

/// An alternative record that holds channels the primary lacks. The detail
/// screen says so and offers the switch.
public struct AlternativeOffer: Hashable, Codable, Sendable {
    public let identity: SourceIdentity
    /// The channels this record holds and the primary does not.
    public let channels: Set<Channel>

    public init(identity: SourceIdentity, channels: Set<Channel>) {
        self.identity = identity
        self.channels = channels
    }
}

/// Which member of a merged activity supplies every stream. The other
/// members are kept as alternatives, and nothing is merged field by field.
public enum PrimaryChoice {
    /// The default primary order: an original file, then HealthKit. Garmin
    /// records and imported files are both original files.
    public static let defaultOrder: [Set<SourceKind>] = [[.garmin, .file], [.healthKit]]

    /// The default primary among `members`, or nil when there are none.
    ///
    /// It is a member of the earliest source kind in `defaultOrder` that any
    /// member has. The spec does not say which of several such members to
    /// take, so this takes the lowest identity among them, which is the same
    /// on every device.
    public static func defaultPrimary(among members: Set<SourceIdentity>) -> SourceIdentity? {
        fatalError("unimplemented")
    }

    /// The primary record of an activity of `members`, or nil when there are
    /// no members.
    ///
    /// The primary choice is a decision like any other, so the choice in
    /// effect is the winner among the members' winning primary decisions. If
    /// that choice is a member, it is the primary. If it is no longer a
    /// member, or no choice was made, the default order applies.
    ///
    /// The spec's "the default order applies again" is read literally: an
    /// earlier choice that the winning one replaced is not revived, even
    /// when the record it chose is still a member.
    public static func primary(
        of members: Set<SourceIdentity>,
        among decisions: some Sequence<DecisionRecord>
    ) -> SourceIdentity? {
        fatalError("unimplemented")
    }

    /// The alternatives that hold a channel the primary lacks, ordered by
    /// identity.
    ///
    /// `channelsByMember` says which channels each member holds. A member it
    /// leaves out holds none. An alternative with nothing to add is left out
    /// of the result. What counts as holding a channel is the caller's call.
    public static func alternativesOfferingMore(
        than primary: SourceIdentity,
        channelsByMember: [SourceIdentity: Set<Channel>]
    ) -> [AlternativeOffer] {
        fatalError("unimplemented")
    }
}
