import Foundation
import SweatKitIdentity
import SweatKitModel
import Testing

/// Decision rules that the first set of tests left open. Each expected
/// value is worked out from the spec's wording in the comment.
@Suite("Decisions: edges")
struct DecisionEdgeTests {
    @Test func aDecisionAppliesToTheMembersAtTheTimeItWasMade() {
        // "A decision made on an activity applies to all of that activity's
        // members at the time."
        // The title was made at time 100 on {garmin:1, healthKit:W1}.
        // garmin:2 was merged in afterwards. The merged activity has the
        // title, through the two members it applies to. garmin:2 on its own
        // has none: the decision was never made on it.
        let title = decision("t1", .title("Morning loop"), time: 100, on: [ga1, hk1])
        #expect(DecisionRecord.title(of: [ga1, ga2, hk1], among: [title]) == "Morning loop")
        #expect(DecisionRecord.winner(of: .title, for: ga1, among: [title]) == title)
        #expect(DecisionRecord.winner(of: .title, for: hk1, among: [title]) == title)
        #expect(DecisionRecord.winner(of: .title, for: ga2, among: [title]) == nil)
        #expect(DecisionRecord.title(of: [ga2], among: [title]) == nil)
    }

    @Test func aMergeWritesNoDecisionAndStillResolves() {
        // "A merge writes no decision. The rule above gives the merged
        // activity the most recent title and keeps it hidden if either side
        // was hidden."
        // Before the merge: {garmin:1} titled at 10 and hidden at 20;
        // {healthKit:W1} titled at 30 and visible. The same three records,
        // with nothing added, resolve the merged activity:
        //   title: garmin:1's winner is at 10, healthKit:W1's at 30 -> the
        //     later, "Evening spin".
        //   hidden: garmin:1's winning hidden decision is "hide" -> hidden.
        let records = [
            decision("t1", .title("Morning loop"), time: 10, on: [ga1]),
            decision("h1", .hidden(true), time: 20, on: [ga1]),
            decision("t2", .title("Evening spin"), time: 30, on: [hk1]),
        ]
        for ordering in permutations(records) {
            #expect(DecisionRecord.title(of: [ga1, hk1], among: ordering) == "Evening spin")
            #expect(DecisionRecord.isHidden([ga1, hk1], among: ordering))
            // The sides on their own are as they were.
            #expect(DecisionRecord.title(of: [ga1], among: ordering) == "Morning loop")
            #expect(DecisionRecord.isHidden([ga1], among: ordering))
            #expect(DecisionRecord.title(of: [hk1], among: ordering) == "Evening spin")
            #expect(!DecisionRecord.isHidden([hk1], among: ordering))
        }
    }

    @Test func recordsThatTieOnEveryStepStillResolveTheSameInAnyOrder() {
        // The spec's order ends at the record name. These three share time,
        // origin, device and name and differ only in value, which unique
        // names should never allow. The spec does not say which wins. It
        // does say the result depends only on which records exist, so all
        // six orderings must agree.
        let records = [
            decision("t", .title("One"), time: 5, device: "x", on: [ga1]),
            decision("t", .title("Two"), time: 5, device: "x", on: [ga1]),
            decision("t", .title("Three"), time: 5, device: "x", on: [ga1]),
        ]
        let titles = Set(permutations(records).map { DecisionRecord.title(of: [ga1], among: $0) })
        #expect(titles.count == 1)
        let winners = Set(permutations(records).map { DecisionRecord.winner(among: $0) })
        #expect(winners.count == 1)
    }

    @Test func aLargerSetOfDecisionsResolvesTheSameInAnyOrder() {
        // One activity of four: {file:f1, garmin:1, healthKit:W1,
        // healthKit:W2}, and eleven decisions.
        let members: Set<SourceIdentity> = [fi1, ga1, hk1, hk2]

        // Titles.
        //   t1 "A" at 10 on {file:f1}
        //   t2 "B" at 30 on {garmin:1, healthKit:W1}, direct
        //   t3 "C" at 30 on {healthKit:W2}, an inherited copy
        //   t4 "D" at 20 on all four
        // Winners by member:
        //   file:f1       t1 (10) against t4 (20) -> t4
        //   garmin:1      t2 (30) against t4 (20) -> t2
        //   healthKit:W1  the same                -> t2
        //   healthKit:W2  t3 (30) against t4 (20) -> t3
        // Among t4, t2 and t3 the latest time is 30, shared by t2 and t3.
        // t2 is direct and t3 is a copy, so t2 wins: "B". The copy's higher
        // device "z" does not come into it.
        let t1 = decision("t1", .title("A"), time: 10, device: "phone", on: [fi1])
        let t2 = decision("t2", .title("B"), time: 30, device: "pad", on: [ga1, hk1])
        let t3 = decision("t3", .title("C"), time: 30, device: "z", on: [hk2], origin: .inheritedCopy)
        let t4 = decision("t4", .title("D"), time: 20, device: "z", on: members)

        // Hidden state.
        //   h1 hide at 40 on {file:f1}
        //   h2 restore at 50 on {file:f1, garmin:1}, device "phone"
        //   h3 hide at 50 on {garmin:1}, device "pad"
        //   h4 hide at 45 on {healthKit:W2}
        //   h5 restore at 44 on {healthKit:W2}
        // Winners by member:
        //   file:f1       h1 (40) against h2 (50) -> h2, a restore
        //   garmin:1      h2 and h3 tie at 50, both direct; "phone" > "pad"
        //                 -> h2, a restore
        //   healthKit:W1  none
        //   healthKit:W2  h5 (44) against h4 (45) -> h4, a hide
        // One member's winner is "hide", so the activity is hidden, and h4
        // is the decision that makes it so.
        let h1 = decision("h1", .hidden(true), time: 40, device: "phone", on: [fi1])
        let h2 = decision("h2", .hidden(false), time: 50, device: "phone", on: [fi1, ga1])
        let h3 = decision("h3", .hidden(true), time: 50, device: "pad", on: [ga1])
        let h4 = decision("h4", .hidden(true), time: 45, device: "phone", on: [hk2])
        let h5 = decision("h5", .hidden(false), time: 44, device: "z", on: [hk2])

        // Primary.
        //   p1 chooses healthKit:W1 at 60 on all four
        //   p2 chooses garmin:2 at 70 on {garmin:1}
        // garmin:1's winner is p2 (70); the others' is p1 (60). The winner
        // among them is p2. garmin:2 is not a member, so the default order
        // applies again: an original file first. file:f1 and garmin:1 are
        // both original files, and file:f1 is the lower identity.
        let p1 = decision("p1", .primary(hk1), time: 60, device: "phone", on: members)
        let p2 = decision("p2", .primary(ga2), time: 70, device: "phone", on: [ga1])

        let records = [t1, t2, t3, t4, h1, h2, h3, h4, h5, p1, p2]
        // 11 records have about 40 million orderings. 300 seeded shuffles.
        var generator = SeededGenerator(seed: 8_675_309)
        for round in 0..<301 {
            let ordering = round == 0 ? records : records.shuffled(using: &generator)
            #expect(DecisionRecord.title(of: members, among: ordering) == "B")
            #expect(DecisionRecord.inEffect(.title, members: members, among: ordering) == t2)
            #expect(DecisionRecord.isHidden(members, among: ordering))
            #expect(DecisionRecord.inEffect(.hidden, members: members, among: ordering) == h4)
            #expect(DecisionRecord.inEffect(.primary, members: members, among: ordering) == p2)
            #expect(PrimaryChoice.primary(of: members, among: ordering) == fi1)
            // The part without healthKit:W2 is visible: file:f1's and
            // garmin:1's winners are the restore h2, and healthKit:W1 has
            // no hidden decision.
            #expect(!DecisionRecord.isHidden([fi1, ga1, hk1], among: ordering))
        }
    }
}

@Suite("The default primary order")
struct DefaultPrimaryOrderTests {
    // With today's source kinds "an original file, then HealthKit" picks
    // the same record as "the lowest identity", because "file" < "garmin" <
    // "healthKit". Passing another order shows that the order is what is
    // read.

    @Test func theOrderPassedInIsTheOneUsed() {
        // HealthKit first, then original files. healthKit:W1 is the only
        // member of the first rank.
        let healthKitFirst: [Set<SourceKind>] = [[.healthKit], [.garmin, .file]]
        #expect(PrimaryChoice.defaultPrimary(among: [fi1, ga1, hk1], order: healthKitFirst) == hk1)
        // And with no HealthKit member, the next rank: the lowest of
        // file:f1 and garmin:1.
        #expect(PrimaryChoice.defaultPrimary(among: [fi1, ga1], order: healthKitFirst) == fi1)
    }

    @Test func anEarlierRankBeatsALowerIdentity() {
        // Garmin alone first. garmin:2 is the only Garmin record, and it
        // wins although file:f1 is the lower identity.
        let garminFirst: [Set<SourceKind>] = [[.garmin], [.file], [.healthKit]]
        #expect(PrimaryChoice.defaultPrimary(among: [fi1, ga2, hk1], order: garminFirst) == ga2)
    }

    @Test func theStandardOrderIsTheDefaultArgument() {
        #expect(
            PrimaryChoice.defaultPrimary(among: [fi1, ga1, hk1])
                == PrimaryChoice.defaultPrimary(among: [fi1, ga1, hk1], order: PrimaryChoice.defaultOrder)
        )
    }

    @Test func aKindTheOrderDoesNotListRanksLast() {
        // Only HealthKit is listed. With a HealthKit member it wins. With
        // none, there is still a primary: the lowest identity.
        let healthKitOnly: [Set<SourceKind>] = [[.healthKit]]
        #expect(PrimaryChoice.defaultPrimary(among: [fi1, ga1, hk2], order: healthKitOnly) == hk2)
        #expect(PrimaryChoice.defaultPrimary(among: [ga1, fi1], order: healthKitOnly) == fi1)
    }
}

@Suite("Inherited copies: edges")
struct InheritedCopyEdgeTests {
    private let both: Set<SourceIdentity> = [ga1, hk1]

    @Test func anEmptyPartGetsNoCopy() {
        // A copy "applies to that part's members". A part with no members
        // has nothing for a copy to apply to.
        let title = decision("t1", .title("Morning loop"), time: 100, on: both)
        let copies = Split.inheritedCopies(
            splitting: both,
            into: [[ga1], [], [hk1]],
            decisions: [title],
            device: DeviceID("pad")
        )
        #expect(copies.map(\.name) == [RecordName("t1|copy|garmin:1"), RecordName("t1|copy|healthKit:W1")])
        #expect(copies.map(\.members) == [[ga1], [hk1]])
    }

    @Test func aPartGivenTwiceGetsOneCopy() {
        // "Once for each resulting part."
        let title = decision("t1", .title("Morning loop"), time: 100, on: both)
        let copies = Split.inheritedCopies(
            splitting: both,
            into: [[ga1], [hk1], [ga1]],
            decisions: [title],
            device: DeviceID("pad")
        )
        #expect(copies.map(\.name) == [RecordName("t1|copy|garmin:1"), RecordName("t1|copy|healthKit:W1")])
    }

    @Test func aCopyOfACopyKeepsTheOriginalDecisionsTime() {
        // {garmin:1, garmin:2, healthKit:W1} was titled at time 100, then
        // split into {garmin:1, healthKit:W1} and {garmin:2} at time 300.
        // Now {garmin:1, healthKit:W1} is split again, at time 500. The
        // decision in effect for it: garmin:1's and healthKit:W1's winners
        // are the original and the first copy, both at time 100. The
        // original is direct, so it wins and is what is copied, at time 100.
        let all: Set<SourceIdentity> = [ga1, ga2, hk1]
        let title = decision("t1", .title("Morning loop"), time: 100, device: "phone", on: all)
        let firstCopies = Split.inheritedCopies(
            splitting: all,
            into: [[ga1, hk1], [ga2]],
            decisions: [title],
            device: DeviceID("phone")
        )
        let secondCopies = Split.inheritedCopies(
            splitting: [ga1, hk1],
            into: [[ga1], [hk1]],
            decisions: [title] + firstCopies,
            device: DeviceID("pad")
        )
        #expect(secondCopies == [
            decision("t1|copy|garmin:1", .title("Morning loop"), time: 100, device: "pad", on: [ga1], origin: .inheritedCopy),
            decision("t1|copy|healthKit:W1", .title("Morning loop"), time: 100, device: "pad", on: [hk1], origin: .inheritedCopy),
        ])
    }

    @Test func whenOnlyACopyAppliesTheCopyIsCopiedWithItsTime() {
        // The title was made at time 100 on garmin:1 alone. A split copied
        // it to healthKit:W1 as "t1|copy|healthKit:W1", keeping time 100.
        // healthKit:W1 was then merged with healthKit:W2 and that activity
        // is split. The only title that applies to either member is the
        // copy, so it is in effect and is copied: same value, same time
        // 100, named from the copy's own name.
        let firstCopy = decision(
            "t1|copy|healthKit:W1",
            .title("Morning loop"),
            time: 100,
            device: "phone",
            on: [hk1],
            origin: .inheritedCopy
        )
        let copies = Split.inheritedCopies(
            splitting: [hk1, hk2],
            into: [[hk1], [hk2]],
            decisions: [firstCopy],
            device: DeviceID("pad")
        )
        #expect(copies == [
            decision(
                "t1|copy|healthKit:W1|copy|healthKit:W1",
                .title("Morning loop"),
                time: 100,
                device: "pad",
                on: [hk1],
                origin: .inheritedCopy
            ),
            decision(
                "t1|copy|healthKit:W1|copy|healthKit:W2",
                .title("Morning loop"),
                time: 100,
                device: "pad",
                on: [hk2],
                origin: .inheritedCopy
            ),
        ])
    }
}

/// A split from start to finish, with the copies written by
/// `Split.inheritedCopies` instead of by hand.
@Suite("A split, end to end")
struct SplitEndToEndTests {
    @Test func aSplitOnOneDeviceWhileAnotherOfflineRenamesAndHides() {
        // garmin:1 and healthKit:W1 are one activity by an automatic link.
        // The phone titled it "Morning loop" at time 100.
        let records: Set<SourceIdentity> = [ga1, hk1]
        let merged = [autoLink(ga1, hk1, time: 10)]
        let title = decision("t1", .title("Morning loop"), time: 100, device: "phone", on: records)

        // The phone splits it at time 300: a user "keep separate", and a
        // copy of the one decision in effect for each part.
        let split = userLink("split", ga1, hk1, .keepSeparate, time: 300, device: "phone")
        let copies = Split.inheritedCopies(
            splitting: records,
            into: [[ga1], [hk1]],
            decisions: [title],
            device: DeviceID("phone")
        )
        #expect(copies.count == 2)

        // The pad, offline and without the split, renames the activity at
        // time 200 and hides it at time 250. Both apply to both members.
        let rename = decision("t2", .title("Commute"), time: 200, device: "pad", on: records)
        let hide = decision("h1", .hidden(true), time: 250, device: "pad", on: records)
        let tombstones = Tombstone.written(.hidden, for: records, at: at(250))

        // Once both devices hold everything:
        //   groups: the user's separation beats the automatic link, so two
        //     activities and nothing to review.
        //   title: on each part the rename (200) beats the original and the
        //     copy (both 100) -> "Commute".
        //   hidden: each member's only hidden decision is the hide.
        //   primary: each record is its own.
        let expected = ResolvedLibrary(
            activities: [
                ResolvedActivity(id: ga1, members: [ga1], title: "Commute", isHidden: true, primary: ga1),
                ResolvedActivity(id: hk1, members: [hk1], title: "Commute", isHidden: true, primary: hk1),
            ],
            possibleDuplicates: []
        )
        var generator = SeededGenerator(seed: 31_337)
        for _ in 0..<100 {
            let library = ResolvedLibrary.resolve(
                records: records,
                links: (merged + [split]).shuffled(using: &generator),
                decisions: ([title, rename, hide] + copies).shuffled(using: &generator),
                tombstones: tombstones.shuffled(using: &generator)
            )
            #expect(library == expected)
        }

        // The phone before it hears from the pad: two visible parts with
        // the original title.
        let phoneAlone = ResolvedLibrary.resolve(
            records: records,
            links: merged + [split],
            decisions: [title] + copies,
            tombstones: [Tombstone]()
        )
        #expect(phoneAlone == ResolvedLibrary(
            activities: [
                ResolvedActivity(id: ga1, members: [ga1], title: "Morning loop", isHidden: false, primary: ga1),
                ResolvedActivity(id: hk1, members: [hk1], title: "Morning loop", isHidden: false, primary: hk1),
            ],
            possibleDuplicates: []
        ))
    }
}

/// "Deletion wins over stale updates. A tombstone outlasts any later write
/// from a device that had not seen it."
@Suite("Tombstones against later writes")
struct TombstoneOutlastTests {
    @Test func aHiddenTombstoneOutlastsLaterWritesThatAreNotARestore() {
        // garmin:1 was hidden at time 10. A device that had not seen that
        // then, at time 20, renamed it, chose a primary and merged
        // healthKit:W1 into it. None of those is a restore, so the identity
        // is still held hidden, and the merged activity with it.
        let tombstones = Tombstone.written(.hidden, for: [ga1], at: at(10))
        let stale = [
            decision("t", .title("Renamed"), time: 20, device: "pad", on: [ga1]),
            decision("p", .primary(hk1), time: 20, device: "pad", on: [ga1, hk1]),
        ]
        let library = ResolvedLibrary.resolve(
            records: [ga1, hk1],
            links: [userLink("stale-merge", ga1, hk1, .sameActivity, time: 20, device: "pad")],
            decisions: stale,
            tombstones: tombstones
        )
        #expect(library.activities == [
            ResolvedActivity(id: ga1, members: [ga1, hk1], title: "Renamed", isHidden: true, primary: hk1),
        ])
    }

    @Test func aDeletedIdentityOfferedAgainBySyncFormsNoActivityHoweverLateTheWrite() {
        // garmin:1 was deleted at time 10. Sync offers it again, and a
        // stale device has since hidden and restored it at times 20 and 30,
        // with a hidden tombstone at 20. The delete is final.
        let tombstones = [
            Tombstone(identity: ga1, kind: .deleted, time: at(10)),
            Tombstone(identity: ga1, kind: .hidden, time: at(20)),
        ]
        let decisions = [
            decision("h", .hidden(true), time: 20, device: "pad", on: [ga1]),
            decision("r", .hidden(false), time: 30, device: "pad", on: [ga1]),
        ]
        for tombstoneOrder in permutations(tombstones) {
            for decisionOrder in permutations(decisions) {
                let library = ResolvedLibrary.resolve(
                    records: [ga1],
                    links: [LinkRecord](),
                    decisions: decisionOrder,
                    tombstones: tombstoneOrder
                )
                #expect(library == ResolvedLibrary(activities: [], possibleDuplicates: []))
                #expect(Tombstone.standing(of: ga1, tombstones: tombstoneOrder, decisions: decisionOrder) == .deleted)
            }
        }
    }

    @Test func deletingAMergedActivityRemovesEveryMember() {
        // "Permanently deleting an activity writes a tombstone for every
        // member's identity." With both written, neither record is left to
        // form an activity on its own.
        let members: Set<SourceIdentity> = [ga1, hk1]
        let tombstones = Tombstone.written(.deleted, for: members, at: at(10))
        #expect(Tombstone.surviving(members, tombstones: tombstones).isEmpty)
        // Had only one been written, the other would have come back alone.
        #expect(Tombstone.surviving(members, tombstones: [tombstones[0]]) == [hk1])
    }
}
