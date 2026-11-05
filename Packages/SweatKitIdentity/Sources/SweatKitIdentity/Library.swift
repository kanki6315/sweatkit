import SweatKitModel

/// One activity with its decisions resolved.
public struct ResolvedActivity: Hashable, Codable, Sendable {
    /// The lowest identity among the members.
    public let id: SourceIdentity
    public let members: Set<SourceIdentity>
    /// Nil when the user has not titled it.
    public let title: String?
    public let isHidden: Bool
    /// The member that supplies every stream.
    public let primary: SourceIdentity

    public init(
        id: SourceIdentity,
        members: Set<SourceIdentity>,
        title: String?,
        isHidden: Bool,
        primary: SourceIdentity
    ) {
        self.id = id
        self.members = members
        self.title = title
        self.isHidden = isHidden
        self.primary = primary
    }
}

/// Every activity that a set of records resolves to.
public struct ResolvedLibrary: Hashable, Codable, Sendable {
    /// Ordered by ID. Hidden activities are included, marked hidden.
    public let activities: [ResolvedActivity]
    /// "Same activity" links that were skipped to keep a separation, for
    /// review as possible duplicates. In the order they were tried.
    public let possibleDuplicates: [LinkRecord]

    public init(activities: [ResolvedActivity], possibleDuplicates: [LinkRecord]) {
        self.activities = activities
        self.possibleDuplicates = possibleDuplicates
    }

    /// Resolves source records, links, decisions and tombstones into
    /// activities.
    ///
    /// 1. Identities with a `.deleted` tombstone are dropped, as
    ///    `Tombstone.surviving` does. They form no activity.
    /// 2. The rest are grouped by `ActivityFormation.form`.
    /// 3. Each activity's title is `DecisionRecord.title`, and its primary
    ///    is `PrimaryChoice.primary`.
    /// 4. An activity is hidden when `DecisionRecord.isHidden` says so, or
    ///    when `Tombstone.standing` is `.hidden` for any member. The second
    ///    half is this package's reading of "a tombstone keeps the source
    ///    identity, so the next sync does not bring the activity back".
    ///
    /// The result depends only on which records exist, not on the order
    /// they are given in. Every device therefore reaches the same answer
    /// once it has the same records.
    public static func resolve(
        records: Set<SourceIdentity>,
        links: some Sequence<LinkRecord>,
        decisions: some Sequence<DecisionRecord>,
        tombstones: some Sequence<Tombstone>
    ) -> ResolvedLibrary {
        let tombstoneIndex = TombstoneIndex(tombstones)
        let decisionIndex = DecisionIndex(decisions)
        let formation = ActivityFormation.form(
            records: tombstoneIndex.surviving(records),
            links: links
        )
        let activities = formation.activities.map { group in
            let heldHidden = group.members.contains {
                tombstoneIndex.standing(of: $0, decisions: decisionIndex) == .hidden
            }
            return ResolvedActivity(
                id: group.id,
                members: group.members,
                title: decisionIndex.title(of: group.members),
                isHidden: heldHidden || decisionIndex.isHidden(group.members),
                // A formed group always has a member, so there is always a
                // primary. The ID stands in only to avoid unwrapping.
                primary: PrimaryChoice.primary(of: group.members, index: decisionIndex) ?? group.id
            )
        }
        return ResolvedLibrary(activities: activities, possibleDuplicates: formation.skippedLinks)
    }
}
