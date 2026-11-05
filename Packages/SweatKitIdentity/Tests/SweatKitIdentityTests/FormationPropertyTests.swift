import Foundation
import SweatKitIdentity
import SweatKitModel
import Testing

/// The steps of "Forming activities from links", checked as properties of
/// the result over many generated sets of links. Nothing here repeats the
/// forming algorithm: each property is read off the spec's wording and
/// checked pair by pair with `LinkRecord.inEffect(for:among:)`.
@Suite("Forming activities from links: properties")
struct FormationPropertyTests {
    /// Eight records: file:f1, garmin:1 to garmin:4, healthKit:W1 to W3.
    private let identities: [SourceIdentity] = [
        fi1,
        ga1,
        ga2,
        SourceIdentity(source: .garmin, externalID: "3"),
        SourceIdentity(source: .garmin, externalID: "4"),
        hk1,
        hk2,
        SourceIdentity(source: .healthKit, externalID: "W3"),
    ]

    /// A generated set of links. Times and devices come from small pools,
    /// so pairs often carry several links that tie on time.
    private func links(count: Int, using generator: inout SeededGenerator) -> [LinkRecord] {
        var result: [LinkRecord] = []
        for index in 0..<count {
            let first = identities[Int.random(in: 0..<identities.count, using: &generator)]
            let second = identities[Int.random(in: 0..<identities.count, using: &generator)]
            guard first != second else { continue }
            // Three links in ten are separations.
            let kind: LinkKind = Int.random(in: 0..<10, using: &generator) < 3 ? .keepSeparate : .sameActivity
            let time = Double(Int.random(in: 0..<4, using: &generator))
            let device = ["pad", "phone", "watch"][Int.random(in: 0..<3, using: &generator)]
            if Bool.random(using: &generator) {
                result.append(userLink("u\(index)", first, second, kind, time: time, device: device))
            } else {
                let pair = IdentityPair(first, second)
                result.append(autoLink(pair.lower, pair.upper, kind, time: time, device: device))
            }
        }
        return result
    }

    private func isKeptSeparate(_ first: SourceIdentity, _ second: SourceIdentity, links: [LinkRecord]) -> Bool {
        LinkRecord.inEffect(for: IdentityPair(first, second), among: links)?.kind == .keepSeparate
    }

    /// Whether any record of one set is kept separate from any of the other.
    private func anyKeptSeparate(
        _ first: Set<SourceIdentity>,
        _ second: Set<SourceIdentity>,
        links: [LinkRecord]
    ) -> Bool {
        first.contains { one in second.contains { other in isKeptSeparate(one, other, links: links) } }
    }

    @Test func generatedLinkSetsFormGroupsThatObeyEveryStep() {
        var generator = SeededGenerator(seed: 1_597_463)
        let records = Set(identities)
        var casesWithASkippedLink = 0
        var casesWithAMerge = 0

        for _ in 0..<300 {
            let count = Int.random(in: 0...16, using: &generator)
            let links = links(count: count, using: &generator)
            let formed = ActivityFormation.form(records: records, links: links)

            // Step 1 and the wording of the result: every record is in
            // exactly one group.
            #expect(formed.activities.reduce(0) { $0 + $1.members.count } == records.count)
            #expect(formed.activities.reduce(into: Set<SourceIdentity>()) { $0.formUnion($1.members) } == records)

            // Step 5: an activity's ID is the lowest identity among its
            // members. Activities are listed by ID.
            for activity in formed.activities {
                #expect(activity.id == activity.members.min())
            }
            #expect(formed.activities.map(\.id) == formed.activities.map(\.id).sorted())

            // Step 3: no group contains a pair whose link in effect is a
            // "keep separate" link.
            for activity in formed.activities {
                let members = activity.members.sorted()
                for (index, first) in members.enumerated() {
                    for second in members[(index + 1)...] {
                        #expect(!isKeptSeparate(first, second, links: links))
                    }
                }
            }

            var groupOf: [SourceIdentity: Set<SourceIdentity>] = [:]
            for activity in formed.activities {
                for member in activity.members {
                    groupOf[member] = activity.members
                }
            }

            // Step 3 again: a skipped link is a "same activity" link in
            // effect whose merge would have brought a separated pair
            // together. Groups only ever grow, so the two final groups
            // still hold that pair apart.
            for skipped in formed.skippedLinks {
                #expect(skipped.kind == .sameActivity)
                #expect(LinkRecord.inEffect(for: skipped.pair, among: links) == skipped)
                let lower = groupOf[skipped.pair.lower] ?? []
                let upper = groupOf[skipped.pair.upper] ?? []
                #expect(lower != upper)
                #expect(anyKeptSeparate(lower, upper, links: links))
            }

            // Step 2: every "same activity" link in effect is applied. One
            // whose two records ended up apart must have been skipped.
            let inEffect = LinkRecord.inEffect(among: links).values
            let leftApart = inEffect.filter { link in
                link.kind == .sameActivity && groupOf[link.pair.lower] != groupOf[link.pair.upper]
            }
            #expect(Set(leftApart) == Set(formed.skippedLinks))
            #expect(formed.skippedLinks.count == Set(formed.skippedLinks).count)

            // Step 2's order: skipped links are listed as tried, user-made
            // first, then automatic, each by name.
            let user = formed.skippedLinks.filter { $0.maker == .user }
            let automatic = formed.skippedLinks.filter { $0.maker == .automatic }
            #expect(formed.skippedLinks == user + automatic)
            #expect(user.map(\.name) == user.map(\.name).sorted())
            #expect(automatic.map(\.name) == automatic.map(\.name).sorted())

            // Step 4: the same links in any order form the same groups.
            for _ in 0..<5 {
                let shuffled = links.shuffled(using: &generator)
                #expect(ActivityFormation.form(records: records, links: shuffled) == formed)
            }

            if !formed.skippedLinks.isEmpty { casesWithASkippedLink += 1 }
            if formed.activities.count < records.count { casesWithAMerge += 1 }
        }

        // The generator must actually reach the interesting cases.
        #expect(casesWithASkippedLink >= 20)
        #expect(casesWithAMerge >= 200)
    }
}

/// Cases of forming and of blocked merges that the first set of tests left
/// open.
@Suite("Forming activities from links: edges")
struct FormationEdgeTests {
    // garmin:1, garmin:2 and healthKit:W1 are one activity by three
    // automatic links. The user splits garmin:2 away at time 300.
    private let triangle = [autoLink(ga1, ga2, time: 10), autoLink(ga1, hk1, time: 10), autoLink(ga2, hk1, time: 10)]

    @Test func aSplitOfThreeHeldBySeparatingEveryLinkedPairLeavesNothingToReview() {
        // A user "keep separate" on each pair that crosses the split:
        // garmin:1 + garmin:2 and garmin:2 + healthKit:W1. A user-made link
        // beats an automatic one, so on both pairs the separation is in
        // effect and the automatic link is not. Links applied:
        //   link|sameActivity|garmin:1|healthKit:W1 -> {garmin:1, healthKit:W1}
        // Nothing else is in effect as "same activity", so nothing is
        // skipped.
        let formed = ActivityFormation.form(
            records: [ga1, ga2, hk1],
            links: triangle + [
                userLink("split-1", ga1, ga2, .keepSeparate, time: 300),
                userLink("split-2", ga2, hk1, .keepSeparate, time: 300),
            ]
        )
        #expect(formed == ActivityFormation(
            activities: [group(id: ga1, ga1, hk1), group(id: ga2, ga2)],
            skippedLinks: []
        ))
    }

    @Test func aSplitOfThreeHeldByOneSeparationLeavesTheOtherLinkForReview() {
        // Only garmin:1 + garmin:2 is separated. In name order:
        //   ...|garmin:1|garmin:2      -> not in effect, the user link is
        //   ...|garmin:1|healthKit:W1  -> {garmin:1, healthKit:W1}
        //   ...|garmin:2|healthKit:W1  -> would put garmin:2 with garmin:1:
        //     skipped.
        // The parts are still held apart, because separation is enforced
        // across the whole group, but the skipped link is shown for review.
        let formed = ActivityFormation.form(
            records: [ga1, ga2, hk1],
            links: triangle + [userLink("split-1", ga1, ga2, .keepSeparate, time: 300)]
        )
        #expect(formed == ActivityFormation(
            activities: [group(id: ga1, ga1, hk1), group(id: ga2, ga2)],
            skippedLinks: [autoLink(ga2, hk1, time: 10)]
        ))
    }

    @Test func aMergeWithARecordThatIsNotThereHasNothingBlockingIt() {
        // garmin:2 is not among the records, so it is in no activity and
        // the separation from it holds nothing apart.
        let separation = userLink("sep", ga1, ga2, .keepSeparate, time: 10)
        #expect(ActivityFormation.separationsBlockingMerge(
            of: ga1,
            with: ga2,
            records: [ga1, hk1],
            links: [separation]
        ).isEmpty)
        #expect(ActivityFormation.separationsBlockingMerge(
            of: ga2,
            with: ga1,
            records: [ga1, hk1],
            links: [separation]
        ).isEmpty)
    }

    @Test func aRecordMergedWithItselfHasNothingBlockingIt() {
        // One record is already in one activity.
        let separation = userLink("sep", ga1, ga2, .keepSeparate, time: 10)
        #expect(ActivityFormation.separationsBlockingMerge(
            of: ga1,
            with: ga1,
            records: [ga1, ga2],
            links: [separation]
        ).isEmpty)
    }

    @Test func liftingTheSeparationLetsTheBlockedMergeGoAhead() {
        // "A merge that would break a separation asks the user to lift the
        // separation first."
        // Before: garmin:1 and garmin:2 are kept separate, garmin:1 and
        // healthKit:W1 are one activity. Merging garmin:2 with healthKit:W1
        // is blocked by the separation.
        let separation = userLink("sep", ga1, ga2, .keepSeparate, time: 10)
        let records: Set<SourceIdentity> = [ga1, ga2, hk1]
        let before = [separation, autoLink(ga1, hk1)]
        #expect(ActivityFormation.separationsBlockingMerge(of: ga2, with: hk1, records: records, links: before) == [separation])

        // The user lifts it at time 20 with a merge of the separated pair,
        // which is later and so in effect. Nothing blocks any more, and the
        // lift itself joins all three:
        //   lift (user)                -> {garmin:1, garmin:2}
        //   ...|garmin:1|healthKit:W1  -> all three
        let lift = userLink("lift", ga1, ga2, .sameActivity, time: 20)
        let after = before + [lift]
        #expect(ActivityFormation.separationsBlockingMerge(of: ga2, with: hk1, records: records, links: after).isEmpty)
        #expect(ActivityFormation.form(records: records, links: after) == ActivityFormation(
            activities: [group(id: ga1, ga1, ga2, hk1)],
            skippedLinks: []
        ))
    }
}
