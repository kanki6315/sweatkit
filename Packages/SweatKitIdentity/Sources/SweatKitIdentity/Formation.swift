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
        var grouping = Grouping(records: records, links: links)
        let skipped = grouping.applyLinks()
        return ActivityFormation(activities: grouping.activities(), skippedLinks: skipped)
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
        var grouping = Grouping(records: records, links: links)
        _ = grouping.applyLinks()
        guard let firstGroup = grouping.members(holding: first),
              let secondGroup = grouping.members(holding: second),
              firstGroup != secondGroup
        else {
            return []
        }
        return grouping.separations(between: firstGroup, and: secondGroup)
    }
}

/// The working state of `ActivityFormation.form`: the groups so far and the
/// links in effect that bear on them.
private struct Grouping {
    /// Each record's group, named by an arbitrary member. Only whether two
    /// records share a name matters.
    private var groupOf: [SourceIdentity: SourceIdentity] = [:]
    private var membersOf: [SourceIdentity: Set<SourceIdentity>] = [:]
    /// The "same activity" links in effect, in the order they are applied.
    private let merges: [LinkRecord]
    /// The "keep separate" links in effect, by pair.
    private let separations: [IdentityPair: LinkRecord]
    /// For each record, the records it must stay separate from.
    private var separatedFrom: [SourceIdentity: Set<SourceIdentity>] = [:]

    init(records: Set<SourceIdentity>, links: some Sequence<LinkRecord>) {
        for record in records {
            groupOf[record] = record
            membersOf[record] = [record]
        }
        // A link takes part only when it is in effect for its pair, joins
        // two different records, and both are among the records.
        let inEffect = LinkRecord.inEffect(among: links).values.filter { link in
            link.pair.lower != link.pair.upper
                && records.contains(link.pair.lower)
                && records.contains(link.pair.upper)
        }
        var merges: [LinkRecord] = []
        var separations: [IdentityPair: LinkRecord] = [:]
        for link in inEffect {
            switch link.kind {
            case .sameActivity:
                merges.append(link)
            case .keepSeparate:
                separations[link.pair] = link
                separatedFrom[link.pair.lower, default: []].insert(link.pair.upper)
                separatedFrom[link.pair.upper, default: []].insert(link.pair.lower)
            }
        }
        self.merges = merges.sorted(by: Self.isAppliedBefore)
        self.separations = separations
    }

    /// User-made links first, then automatic ones, each set in ascending
    /// order of name. Two user-made links on different pairs can share a
    /// name only by mistake, and the pair then settles the order so that it
    /// is still the same on every device.
    private static func isAppliedBefore(_ first: LinkRecord, _ second: LinkRecord) -> Bool {
        if first.maker != second.maker {
            return first.maker == .user
        }
        return (first.name, first.pair) < (second.name, second.pair)
    }

    /// Applies every "same activity" link in effect, in order, and returns
    /// the ones skipped to keep a separation.
    mutating func applyLinks() -> [LinkRecord] {
        var skipped: [LinkRecord] = []
        for link in merges {
            guard let first = groupOf[link.pair.lower],
                  let second = groupOf[link.pair.upper],
                  first != second
            else {
                continue
            }
            let firstMembers = membersOf[first] ?? []
            let secondMembers = membersOf[second] ?? []
            if isSeparated(firstMembers, from: secondMembers) {
                skipped.append(link)
                continue
            }
            for member in secondMembers {
                groupOf[member] = first
            }
            membersOf[first] = firstMembers.union(secondMembers)
            membersOf[second] = nil
        }
        return skipped
    }

    /// Whether any record of one group must stay separate from any record
    /// of the other. Each group already holds no separated pair, so these
    /// are the only pairs a merge could bring together.
    private func isSeparated(_ first: Set<SourceIdentity>, from second: Set<SourceIdentity>) -> Bool {
        first.contains { member in
            guard let apart = separatedFrom[member] else { return false }
            return !apart.isDisjoint(with: second)
        }
    }

    /// The members of the group holding `record`, or nil when it is not
    /// among the records.
    func members(holding record: SourceIdentity) -> Set<SourceIdentity>? {
        groupOf[record].flatMap { membersOf[$0] }
    }

    /// The "keep separate" links in effect between the two groups, in
    /// ascending order of name.
    func separations(between first: Set<SourceIdentity>, and second: Set<SourceIdentity>) -> [LinkRecord] {
        var found: [LinkRecord] = []
        for member in first {
            for other in separatedFrom[member] ?? [] where second.contains(other) {
                if let link = separations[IdentityPair(member, other)] {
                    found.append(link)
                }
            }
        }
        return found.sorted { ($0.name, $0.pair) < ($1.name, $1.pair) }
    }

    /// The groups as activities, ordered by ID.
    func activities() -> [ActivityGroup] {
        membersOf.values
            .compactMap { members in
                members.min().map { ActivityGroup(id: $0, members: members) }
            }
            .sorted { $0.id < $1.id }
    }
}
