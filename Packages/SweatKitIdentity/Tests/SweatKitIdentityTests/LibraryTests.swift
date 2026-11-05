import Foundation
import SweatKitIdentity
import SweatKitModel
import Testing

/// An expected activity, spelled out by hand.
private func activity(
    id: SourceIdentity,
    _ members: Set<SourceIdentity>,
    title: String? = nil,
    hidden: Bool = false,
    primary: SourceIdentity
) -> ResolvedActivity {
    ResolvedActivity(id: id, members: members, title: title, isHidden: hidden, primary: primary)
}

private func inheritedCopy(
    _ name: String,
    _ value: DecisionValue,
    time: Double,
    device: String = "phone",
    on members: Set<SourceIdentity>
) -> DecisionRecord {
    decision(name, value, time: time, device: device, on: members, origin: .inheritedCopy)
}

@Suite("Resolving a whole library")
struct LibraryTests {
    @Test func recordsWithNothingElseAreOneActivityEach() {
        let library = ResolvedLibrary.resolve(
            records: [hk1, ga1],
            links: [LinkRecord](),
            decisions: [DecisionRecord](),
            tombstones: [Tombstone]()
        )
        // No title, not hidden, and each record is its own primary.
        #expect(library == ResolvedLibrary(
            activities: [activity(id: ga1, [ga1], primary: ga1), activity(id: hk1, [hk1], primary: hk1)],
            possibleDuplicates: []
        ))
    }

    @Test func aMergedActivityHasOnePrimaryByTheDefaultOrder() {
        let library = ResolvedLibrary.resolve(
            records: [hk1, ga1],
            links: [autoLink(ga1, hk1)],
            decisions: [DecisionRecord](),
            tombstones: [Tombstone]()
        )
        // The Garmin original is the default primary over HealthKit.
        #expect(library == ResolvedLibrary(
            activities: [activity(id: ga1, [ga1, hk1], primary: ga1)],
            possibleDuplicates: []
        ))
    }

    // MARK: The spec's cases, end to end

    @Test func threeRecordsWhereAAndBAreKeptSeparateAndBothMatchC() {
        // A = garmin:1 from 0, B = garmin:2 from 200, C = healthKit:W1 from
        // 100. All last an hour and cover 30 km.
        //   A and C: starts 100 s apart -> match.
        //   B and C: starts 100 s apart -> match.
        //   A and B: starts 200 s apart -> fail, and they overlap -> flagged.
        let a = MatchCandidate(identity: ga1, sport: .cycling, start: at(0), elapsed: 3600, distance: 30_000)
        let b = MatchCandidate(identity: ga2, sport: .cycling, start: at(200), elapsed: 3600, distance: 30_000)
        let c = MatchCandidate(identity: hk1, sport: .cycling, start: at(100), elapsed: 3600, distance: 30_000)
        let scan = MatchScan.scan([a, b, c], at: at(400), device: DeviceID("phone"))
        #expect(scan == MatchScan(
            links: [autoLink(ga1, hk1, time: 400), autoLink(ga2, hk1, time: 400)],
            possibleDuplicates: [IdentityPair(ga1, ga2)]
        ))

        // The user reviews the flagged pair and keeps both.
        let keepBoth = userLink("keep", ga1, ga2, .keepSeparate, time: 500)
        let library = ResolvedLibrary.resolve(
            records: [ga1, ga2, hk1],
            links: scan.links + [keepBoth],
            decisions: [DecisionRecord](),
            tombstones: [Tombstone]()
        )
        // In name order the garmin:1 link is applied first. The garmin:2
        // link would join A and B through C, so it is skipped and shown as a
        // possible duplicate.
        #expect(library == ResolvedLibrary(
            activities: [activity(id: ga1, [ga1, hk1], primary: ga1), activity(id: ga2, [ga2], primary: ga2)],
            possibleDuplicates: [autoLink(ga2, hk1, time: 400)]
        ))
    }

    @Test func aRenamedActivityWhosePrimarySourceIsSwitched() {
        let links = [autoLink(ga1, hk1)]
        let rename = decision("t", .title("Morning loop"), time: 100, on: [ga1, hk1])
        let before = ResolvedLibrary.resolve(
            records: [ga1, hk1],
            links: links,
            decisions: [rename],
            tombstones: [Tombstone]()
        )
        #expect(before.activities == [activity(id: ga1, [ga1, hk1], title: "Morning loop", primary: ga1)])

        // The switch changes the primary and nothing else. The ID is still
        // the lowest member, not the primary.
        let switched = decision("p", .primary(hk1), time: 200, on: [ga1, hk1])
        let after = ResolvedLibrary.resolve(
            records: [ga1, hk1],
            links: links,
            decisions: [switched, rename],
            tombstones: [Tombstone]()
        )
        #expect(after.activities == [activity(id: ga1, [ga1, hk1], title: "Morning loop", primary: hk1)])
    }

    @Test func aHiddenActivityMergedWithAVisibleOneIsHidden() {
        // garmin:1 was hidden at time 100, which wrote a decision and a
        // tombstone. Then it was merged with healthKit:W1. A merge writes no
        // decision.
        let hide = decision("h", .hidden(true), time: 100, on: [ga1])
        let tombstones = Tombstone.written(.hidden, for: [ga1], at: at(100))
        let merge = userLink("m", ga1, hk1, .sameActivity, time: 200)
        let library = ResolvedLibrary.resolve(
            records: [ga1, hk1],
            links: [merge],
            decisions: [hide],
            tombstones: tombstones
        )
        #expect(library.activities == [activity(id: ga1, [ga1, hk1], hidden: true, primary: ga1)])
    }

    @Test func aMergedActivityTakesTheMostRecentTitle() {
        let morning = decision("t1", .title("Morning loop"), time: 100, on: [ga1])
        let evening = decision("t2", .title("Evening spin"), time: 150, on: [hk1])
        let library = ResolvedLibrary.resolve(
            records: [ga1, hk1],
            links: [userLink("m", ga1, hk1, .sameActivity, time: 200)],
            decisions: [morning, evening],
            tombstones: [Tombstone]()
        )
        #expect(library.activities == [activity(id: ga1, [ga1, hk1], title: "Evening spin", primary: ga1)])
    }

    @Test func theSameMergeMadeOnTwoOfflineDevicesGivesOneActivity() {
        let onPhone = userLink("m-phone", ga1, hk1, .sameActivity, time: 100, device: "phone")
        let onPad = userLink("m-pad", ga1, hk1, .sameActivity, time: 130, device: "pad")
        let expected = ResolvedLibrary(
            activities: [activity(id: ga1, [ga1, hk1], primary: ga1)],
            possibleDuplicates: []
        )
        for links in [[onPhone], [onPad], [onPhone, onPad], [onPad, onPhone]] {
            let library = ResolvedLibrary.resolve(
                records: [ga1, hk1],
                links: links,
                decisions: [DecisionRecord](),
                tombstones: [Tombstone]()
            )
            #expect(library == expected)
        }
    }

    @Test func aMergeAndAKeepSeparateMadeAtTheSameTimeResolveToSeparate() {
        let merge = userLink("m", ga1, hk1, .sameActivity, time: 100, device: "phone")
        let separate = userLink("s", ga1, hk1, .keepSeparate, time: 100, device: "pad")
        let expected = ResolvedLibrary(
            activities: [activity(id: ga1, [ga1], primary: ga1), activity(id: hk1, [hk1], primary: hk1)],
            possibleDuplicates: []
        )
        for links in [[merge, separate], [separate, merge]] {
            let library = ResolvedLibrary.resolve(
                records: [ga1, hk1],
                links: links,
                decisions: [DecisionRecord](),
                tombstones: [Tombstone]()
            )
            #expect(library == expected)
        }
    }

    // A split on the phone while the pad, offline, makes a decision.
    //
    // Before: garmin:1 and healthKit:W1 are one activity by an automatic
    // link, titled "Morning loop" at time 100.
    // The phone splits it at time 300: a user "keep separate" link, which
    // beats the automatic link, and an inherited copy of the title for each
    // part, keeping time 100.
    private let splitLinks = [
        autoLink(ga1, hk1, time: 10),
        userLink("split", ga1, hk1, .keepSeparate, time: 300),
    ]
    private let splitDecisions = [
        decision("t1", .title("Morning loop"), time: 100, on: [ga1, hk1]),
        inheritedCopy("t1|copy|garmin:1", .title("Morning loop"), time: 100, on: [ga1]),
        inheritedCopy("t1|copy|healthKit:W1", .title("Morning loop"), time: 100, on: [hk1]),
    ]

    @Test func aSplitLeavesBothPartsWithTheTitle() {
        let library = ResolvedLibrary.resolve(
            records: [ga1, hk1],
            links: splitLinks,
            decisions: splitDecisions,
            tombstones: [Tombstone]()
        )
        // The automatic link lost to the user's separation, so it is not in
        // effect and is not a possible duplicate.
        #expect(library == ResolvedLibrary(
            activities: [
                activity(id: ga1, [ga1], title: "Morning loop", primary: ga1),
                activity(id: hk1, [hk1], title: "Morning loop", primary: hk1),
            ],
            possibleDuplicates: []
        ))
    }

    @Test func aSplitOnOneDeviceWhileAnotherOfflineRenamesTheActivity() {
        // The pad's rename is at time 200: later than the title (100), and
        // made without seeing the split, so it applies to both old members.
        // It beats the original and both copies on both parts.
        let rename = decision("t2", .title("Commute"), time: 200, device: "pad", on: [ga1, hk1])
        let expected = ResolvedLibrary(
            activities: [
                activity(id: ga1, [ga1], title: "Commute", primary: ga1),
                activity(id: hk1, [hk1], title: "Commute", primary: hk1),
            ],
            possibleDuplicates: []
        )
        // Both devices end with the same records, in whatever order.
        for decisions in permutations(splitDecisions + [rename]) {
            for links in permutations(splitLinks) {
                let library = ResolvedLibrary.resolve(
                    records: [ga1, hk1],
                    links: links,
                    decisions: decisions,
                    tombstones: [Tombstone]()
                )
                #expect(library == expected)
            }
        }
    }

    @Test func aSplitOnOneDeviceWhileAnotherOfflineHidesTheActivity() {
        // The pad's hide at time 200 wrote a decision on both members and a
        // tombstone for each. Both parts are hidden and keep the title.
        let hide = decision("h1", .hidden(true), time: 200, device: "pad", on: [ga1, hk1])
        let tombstones = Tombstone.written(.hidden, for: [ga1, hk1], at: at(200))
        let expected = ResolvedLibrary(
            activities: [
                activity(id: ga1, [ga1], title: "Morning loop", hidden: true, primary: ga1),
                activity(id: hk1, [hk1], title: "Morning loop", hidden: true, primary: hk1),
            ],
            possibleDuplicates: []
        )
        for decisions in permutations(splitDecisions + [hide]) {
            for links in permutations(splitLinks) {
                let library = ResolvedLibrary.resolve(
                    records: [ga1, hk1],
                    links: links,
                    decisions: decisions,
                    tombstones: tombstones
                )
                #expect(library == expected)
            }
        }
    }

    @Test func aHiddenActivityThatIsSplitLeavesBothPartsHidden() {
        // garmin:1 was hidden alone at time 100, merged with healthKit:W1 at
        // 200, and the merged, hidden activity was split at 300. The split
        // copied the hide to each part.
        let hide = decision("h1", .hidden(true), time: 100, on: [ga1])
        let copies = [
            inheritedCopy("h1|copy|garmin:1", .hidden(true), time: 100, on: [ga1]),
            inheritedCopy("h1|copy|healthKit:W1", .hidden(true), time: 100, on: [hk1]),
        ]
        let links = [
            userLink("merge", ga1, hk1, .sameActivity, time: 200),
            userLink("split", ga1, hk1, .keepSeparate, time: 300),
        ]
        let library = ResolvedLibrary.resolve(
            records: [ga1, hk1],
            links: links,
            decisions: [hide] + copies,
            tombstones: Tombstone.written(.hidden, for: [ga1], at: at(100))
        )
        #expect(library.activities == [
            activity(id: ga1, [ga1], hidden: true, primary: ga1),
            activity(id: hk1, [hk1], hidden: true, primary: hk1),
        ])
    }

    // MARK: Tombstones

    @Test func aDeletedActivityIsGoneAndDoesNotComeBack() {
        // Both members were deleted at time 10. The next sync offers the
        // same identities again, and they form no activity.
        let library = ResolvedLibrary.resolve(
            records: [ga1, hk1, ga2],
            links: [autoLink(ga1, hk1)],
            decisions: [DecisionRecord](),
            tombstones: Tombstone.written(.deleted, for: [ga1, hk1], at: at(10))
        )
        #expect(library == ResolvedLibrary(
            activities: [activity(id: ga2, [ga2], primary: ga2)],
            possibleDuplicates: []
        ))
    }

    @Test func deletionWinsOverStaleUpdates() {
        // {garmin:1, healthKit:W1} was deleted at time 10. A device that had
        // not seen the tombstones then, at time 20, renamed the activity,
        // restored it and merged garmin:2 into it. None of that brings the
        // deleted records back. garmin:2 has no tombstone, so it is left as
        // its own activity; the stale link names a record that is gone and
        // is ignored, and the stale title never applied to garmin:2.
        let library = ResolvedLibrary.resolve(
            records: [ga1, hk1, ga2],
            links: [autoLink(ga1, hk1), userLink("stale-merge", ga1, ga2, .sameActivity, time: 20, device: "pad")],
            decisions: [
                decision("stale-title", .title("Still here"), time: 20, device: "pad", on: [ga1, hk1]),
                decision("stale-restore", .hidden(false), time: 20, device: "pad", on: [ga1, hk1]),
            ],
            tombstones: Tombstone.written(.deleted, for: [ga1, hk1], at: at(10))
        )
        #expect(library == ResolvedLibrary(
            activities: [activity(id: ga2, [ga2], primary: ga2)],
            possibleDuplicates: []
        ))
    }

    @Test func aHiddenTombstoneKeepsTheActivityHiddenWithoutItsDecision() {
        // Only the tombstone is on hand. The record is kept, and hidden.
        let tombstone = Tombstone(identity: ga1, kind: .hidden, time: at(10))
        let library = ResolvedLibrary.resolve(
            records: [ga1],
            links: [LinkRecord](),
            decisions: [DecisionRecord](),
            tombstones: [tombstone]
        )
        #expect(library.activities == [activity(id: ga1, [ga1], hidden: true, primary: ga1)])
    }

    @Test func aHiddenTombstoneOnOneMemberHidesTheWholeActivity() {
        let tombstone = Tombstone(identity: hk1, kind: .hidden, time: at(10))
        let library = ResolvedLibrary.resolve(
            records: [ga1, hk1],
            links: [autoLink(ga1, hk1)],
            decisions: [DecisionRecord](),
            tombstones: [tombstone]
        )
        #expect(library.activities == [activity(id: ga1, [ga1, hk1], hidden: true, primary: ga1)])
    }

    @Test func aRestoreMadeAfterTheTombstoneShowsTheActivityAgain() {
        // Hidden at 10 by decision and tombstone, restored at 20.
        let hide = decision("h", .hidden(true), time: 10, on: [ga1])
        let restore = decision("r", .hidden(false), time: 20, on: [ga1])
        let tombstone = Tombstone(identity: ga1, kind: .hidden, time: at(10))
        let library = ResolvedLibrary.resolve(
            records: [ga1],
            links: [LinkRecord](),
            decisions: [restore, hide],
            tombstones: [tombstone]
        )
        #expect(library.activities == [activity(id: ga1, [ga1], primary: ga1)])
    }

    @Test func aRestoreNotAfterTheTombstoneLeavesTheActivityHidden() {
        // The only decision on hand is a restore at time 10, the same time
        // as the tombstone. By decisions alone the activity would be
        // visible, but the restore was not made after the tombstone.
        let restore = decision("r", .hidden(false), time: 10, on: [ga1])
        let tombstone = Tombstone(identity: ga1, kind: .hidden, time: at(10))
        let library = ResolvedLibrary.resolve(
            records: [ga1],
            links: [LinkRecord](),
            decisions: [restore],
            tombstones: [tombstone]
        )
        #expect(library.activities == [activity(id: ga1, [ga1], hidden: true, primary: ga1)])
    }

    // MARK: Order independence

    @Test func theSameRecordsInAnyOrderGiveTheSameLibrary() {
        // Six source records: file:f1, garmin:1, garmin:2, garmin:3,
        // healthKit:W1, healthKit:W2.
        let ga3 = SourceIdentity(source: .garmin, externalID: "3")
        let records: Set<SourceIdentity> = [fi1, ga1, ga2, ga3, hk1, hk2]

        // Links.
        //   garmin:1 + garmin:2: kept separate by the user.
        //   garmin:1 + healthKit:W1 and garmin:2 + healthKit:W1: automatic.
        //   healthKit:W1 + healthKit:W2: the same user merge made on two
        //     devices at time 20. "phone" > "pad", so u3 is in effect.
        //   healthKit:W2 + file:f1: a merge and a "keep separate" at the
        //     same time 30. "Keep separate" is in effect.
        let u1 = userLink("u1", ga1, ga2, .keepSeparate, time: 10, device: "phone")
        let a1 = autoLink(ga1, hk1, time: 5)
        let a2 = autoLink(ga2, hk1, time: 5)
        let u2 = userLink("u2", hk1, hk2, .sameActivity, time: 20, device: "pad")
        let u3 = userLink("u3", hk1, hk2, .sameActivity, time: 20, device: "phone")
        let u4 = userLink("u4", hk2, fi1, .sameActivity, time: 30, device: "phone")
        let u5 = userLink("u5", hk2, fi1, .keepSeparate, time: 30, device: "pad")
        let links = [u1, a1, a2, u2, u3, u4, u5]
        // Applied in order:
        //   u3 (user)                               -> {W1, W2}
        //   link|sameActivity|garmin:1|healthKit:W1 -> {garmin:1, W1, W2}
        //   link|sameActivity|garmin:2|healthKit:W1 -> would join garmin:1
        //     and garmin:2: skipped.

        // Decisions.
        //   t1 and t2 are titles at the same time 100 on garmin:1 and on
        //     {W1, W2}. Both direct; "phone" > "pad", so t1 wins.
        //   h1 hides garmin:2 at 50 and h2 restores it at 60: visible.
        //   h3 hides healthKit:W2 at 70: its activity is hidden.
        //   p1 chooses healthKit:W1 as primary of {garmin:1, W1, W2}.
        //   t3 is a stale title on the deleted garmin:3.
        let decisions = [
            decision("t1", .title("Morning loop"), time: 100, device: "phone", on: [ga1]),
            decision("t2", .title("Hill repeats"), time: 100, device: "pad", on: [hk1, hk2]),
            decision("h1", .hidden(true), time: 50, device: "phone", on: [ga2]),
            decision("h2", .hidden(false), time: 60, device: "pad", on: [ga2]),
            decision("h3", .hidden(true), time: 70, device: "phone", on: [hk2]),
            decision("p1", .primary(hk1), time: 80, device: "phone", on: [ga1, hk1, hk2]),
            decision("t3", .title("Deleted ride"), time: 90, device: "pad", on: [ga3]),
        ]

        // Tombstones.
        //   garmin:2: hidden at 50, restored at 60, which is after it: live.
        //   healthKit:W2: hidden at 70, never restored.
        //   garmin:3: deleted at 40. It forms no activity.
        let tombstones = [
            Tombstone(identity: ga2, kind: .hidden, time: at(50)),
            Tombstone(identity: hk2, kind: .hidden, time: at(70)),
            Tombstone(identity: ga3, kind: .deleted, time: at(40)),
        ]

        // Ordered by ID: file:f1 < garmin:1 < garmin:2.
        let expected = ResolvedLibrary(
            activities: [
                activity(id: fi1, [fi1], primary: fi1),
                activity(id: ga1, [ga1, hk1, hk2], title: "Morning loop", hidden: true, primary: hk1),
                activity(id: ga2, [ga2], primary: ga2),
            ],
            possibleDuplicates: [a2]
        )

        let asGiven = ResolvedLibrary.resolve(
            records: records,
            links: links,
            decisions: decisions,
            tombstones: tombstones
        )
        #expect(asGiven == expected)

        // 300 seeded shuffles of all three kinds of record.
        var generator = SeededGenerator(seed: 20_261_104)
        for _ in 0..<300 {
            let library = ResolvedLibrary.resolve(
                records: records,
                links: links.shuffled(using: &generator),
                decisions: decisions.shuffled(using: &generator),
                tombstones: tombstones.shuffled(using: &generator)
            )
            #expect(library == expected)
        }
    }

    @Test func twoDevicesThatReceivedTheRecordsInDifferentOrdersAgree() {
        // One device got the split first and the rename later. The other got
        // them the other way round. Each resolves what it holds, and once
        // both hold everything they agree.
        let rename = decision("t2", .title("Commute"), time: 200, device: "pad", on: [ga1, hk1])
        let phone = ResolvedLibrary.resolve(
            records: [ga1, hk1],
            links: splitLinks,
            decisions: splitDecisions + [rename],
            tombstones: [Tombstone]()
        )
        let pad = ResolvedLibrary.resolve(
            records: [hk1, ga1],
            links: Array(splitLinks.reversed()),
            decisions: [rename] + Array(splitDecisions.reversed()),
            tombstones: [Tombstone]()
        )
        #expect(phone == pad)
        #expect(phone.activities.map(\.title) == ["Commute", "Commute"])
    }
}
