import SweatKitModel

/// The source records that make up one real-world activity.
public struct ActivityGroup: Hashable, Codable, Sendable {
    /// The activity's ID: the lowest identity among its members.
    public let id: SourceIdentity
    public let members: Set<SourceIdentity>

    /// Stores both values as given. `ActivityFormation.form` is what
    /// guarantees that `id` is the lowest member.
    public init(id: SourceIdentity, members: Set<SourceIdentity>) {
        self.id = id
        self.members = members
    }
}

/// The activities that a set of source records and links form.
public struct ActivityFormation: Hashable, Codable, Sendable {
    /// Every activity, ordered by ID. Each record is in exactly one.
    public let activities: [ActivityGroup]
    /// "Same activity" links in effect that were skipped because applying
    /// them would have broken a separation. They are shown as possible
    /// duplicates for review. In the order they were tried.
    public let skippedLinks: [LinkRecord]

    public init(activities: [ActivityGroup], skippedLinks: [LinkRecord]) {
        self.activities = activities
        self.skippedLinks = skippedLinks
    }

    /// Forms activities from links, with separation enforced across the
    /// whole group.
    ///
    /// 1. Every record in `records` starts as its own group.
    /// 2. The "same activity" links that are in effect for their pair are
    ///    applied one at a time: user-made links first, then automatic ones,
    ///    each set in ascending order of link name.
    /// 3. A link is applied only if the merged group would contain no pair
    ///    whose link in effect is a "keep separate" link. Otherwise it is
    ///    skipped and reported in `skippedLinks`.
    /// 4. Each activity's ID is the lowest identity among its members.
    ///
    /// The result depends only on which records and links are given, not on
    /// the order of `links`.
    ///
    /// Readings taken where the spec is ambiguous or silent:
    /// - "Ordered by link name" is ascending order.
    /// - Only the link in effect for a pair takes part. A "same activity"
    ///   link that lost to another link on its pair is neither applied nor
    ///   reported as skipped, and its name plays no part in the order.
    /// - A link naming an identity that is not in `records` is ignored: it
    ///   is not applied, not reported as skipped, and does not separate.
    /// - A link from an identity to itself is ignored.
    /// - A link whose two records are already in one group changes nothing
    ///   and is not reported as skipped.
    /// - The only way to lift a separation is a later user-made "same
    ///   activity" link on the separated pair, which then is the link in
    ///   effect for it.
    public static func form(
        records: Set<SourceIdentity>,
        links: some Sequence<LinkRecord>
    ) -> ActivityFormation {
        fatalError("unimplemented")
    }

    /// The separations a merge would break.
    ///
    /// On one device the app does not create a conflict in the first place:
    /// a merge that would break a separation asks the user to lift the
    /// separation first. This returns the "keep separate" links in effect
    /// between a member of the activity holding `first` and a member of the
    /// activity holding `second`, as `form(records:links:)` forms them, in
    /// ascending order of link name. Empty means the merge can go ahead.
    ///
    /// It is empty when both records are already in one activity, and when
    /// either is not in `records`.
    public static func separationsBlockingMerge(
        of first: SourceIdentity,
        with second: SourceIdentity,
        records: Set<SourceIdentity>,
        links: some Sequence<LinkRecord>
    ) -> [LinkRecord] {
        fatalError("unimplemented")
    }
}
