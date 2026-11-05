import Foundation
import SweatKitIdentity
import SweatKitModel
import Testing

@Suite("Forming activities from links")
struct FormationTests {
    // MARK: Groups and IDs

    @Test func everyRecordStartsAsItsOwnActivity() {
        let formed = ActivityFormation.form(records: [hk1, ga2, ga1], links: [LinkRecord]())
        // Ordered by ID: garmin:1 < garmin:2 < healthKit:W1.
        #expect(formed == ActivityFormation(
            activities: [group(id: ga1, ga1), group(id: ga2, ga2), group(id: hk1, hk1)],
            skippedLinks: []
        ))
    }

    @Test func noRecordsFormNoActivities() {
        let formed = ActivityFormation.form(records: [], links: [autoLink(ga1, hk1)])
        #expect(formed == ActivityFormation(activities: [], skippedLinks: []))
    }

    @Test func aSameActivityLinkJoinsItsTwoRecords() {
        let formed = ActivityFormation.form(records: [ga1, hk1], links: [autoLink(ga1, hk1)])
        #expect(formed == ActivityFormation(activities: [group(id: ga1, ga1, hk1)], skippedLinks: []))
    }

    @Test func linksChainRecordsIntoOneActivity() {
        // garmin:1 + garmin:2, then garmin:2 + healthKit:W1.
        let formed = ActivityFormation.form(
            records: [ga1, ga2, hk1],
            links: [autoLink(ga2, hk1), autoLink(ga1, ga2)]
        )
        #expect(formed == ActivityFormation(activities: [group(id: ga1, ga1, ga2, hk1)], skippedLinks: []))
    }

    @Test func anActivitysIDIsTheLowestIdentityAmongItsMembers() {
        // "file" < "garmin" < "healthKit", so the file is the lowest.
        let formed = ActivityFormation.form(
            records: [hk1, ga1, fi1],
            links: [autoLink(ga1, hk1), autoLink(fi1, hk1)]
        )
        #expect(formed.activities == [group(id: fi1, fi1, ga1, hk1)])
    }

    @Test func theLowestIdentityIsByStringOrderNotNumber() {
        // "10" < "9" as strings, so garmin:10 is the ID.
        let ten = SourceIdentity(source: .garmin, externalID: "10")
        let nine = SourceIdentity(source: .garmin, externalID: "9")
        let formed = ActivityFormation.form(records: [nine, ten], links: [autoLink(ten, nine)])
        #expect(formed.activities == [group(id: ten, ten, nine)])
    }

    @Test func aKeepSeparateLinkAloneLeavesTheRecordsApart() {
        let formed = ActivityFormation.form(
            records: [ga1, hk1],
            links: [userLink("sep", ga1, hk1, .keepSeparate)]
        )
        #expect(formed == ActivityFormation(
            activities: [group(id: ga1, ga1), group(id: hk1, hk1)],
            skippedLinks: []
        ))
    }

    // MARK: Separation across the whole group

    @Test func twoRecordsKeptSeparateAreNotJoinedThroughAThird() {
        // The spec's case: A = garmin:1 and B = garmin:2 are kept separate,
        // and both match C = healthKit:W1.
        // Automatic links are applied in ascending order of name:
        //   link|sameActivity|garmin:1|healthKit:W1  -> joins A and C
        //   link|sameActivity|garmin:2|healthKit:W1  -> would put A and B
        //     together, so it is skipped.
        let formed = ActivityFormation.form(
            records: [ga1, ga2, hk1],
            links: [
                userLink("sep", ga1, ga2, .keepSeparate, time: 10),
                autoLink(ga1, hk1),
                autoLink(ga2, hk1),
            ]
        )
        #expect(formed == ActivityFormation(
            activities: [group(id: ga1, ga1, hk1), group(id: ga2, ga2)],
            skippedLinks: [autoLink(ga2, hk1)]
        ))
    }

    @Test func separationHoldsAcrossAChainOfFour() {
        // garmin:1 and healthKit:W2 are kept separate. In name order:
        //   ...|garmin:1|garmin:2          -> {garmin:1, garmin:2}
        //   ...|garmin:2|healthKit:W1      -> {garmin:1, garmin:2, healthKit:W1}
        //   ...|healthKit:W1|healthKit:W2  -> would hold garmin:1 and
        //     healthKit:W2 together, so it is skipped.
        let formed = ActivityFormation.form(
            records: [ga1, ga2, hk1, hk2],
            links: [
                userLink("sep", ga1, hk2, .keepSeparate),
                autoLink(ga1, ga2),
                autoLink(ga2, hk1),
                autoLink(hk1, hk2),
            ]
        )
        #expect(formed == ActivityFormation(
            activities: [group(id: ga1, ga1, ga2, hk1), group(id: hk2, hk2)],
            skippedLinks: [autoLink(hk1, hk2)]
        ))
    }

    @Test func aSkippedLinkDoesNotStopTheLinksAfterIt() {
        // garmin:1 and garmin:2 are kept separate. In name order:
        //   ...|garmin:1|healthKit:W1  -> {garmin:1, healthKit:W1}
        //   ...|garmin:2|healthKit:W1  -> skipped
        //   ...|garmin:2|healthKit:W2  -> {garmin:2, healthKit:W2}
        let formed = ActivityFormation.form(
            records: [ga1, ga2, hk1, hk2],
            links: [
                userLink("sep", ga1, ga2, .keepSeparate),
                autoLink(ga1, hk1),
                autoLink(ga2, hk1),
                autoLink(ga2, hk2),
            ]
        )
        #expect(formed == ActivityFormation(
            activities: [group(id: ga1, ga1, hk1), group(id: ga2, ga2, hk2)],
            skippedLinks: [autoLink(ga2, hk1)]
        ))
    }

    @Test func skippedLinksAreListedInTheOrderTheyWereTried() {
        // garmin:1 is kept separate from garmin:2 and from file:f1. All
        // three match healthKit:W1. In name order:
        //   ...|file:f1|healthKit:W1   -> {file:f1, healthKit:W1}
        //   ...|garmin:1|healthKit:W1  -> would join garmin:1 and file:f1: skipped
        //   ...|garmin:2|healthKit:W1  -> {file:f1, garmin:2, healthKit:W1}
        // Then with garmin:1 swapped for file:f1 as the separated record,
        // two links are skipped, in name order.
        let first = ActivityFormation.form(
            records: [fi1, ga1, ga2, hk1],
            links: [
                userLink("s1", ga1, ga2, .keepSeparate),
                userLink("s2", ga1, fi1, .keepSeparate),
                autoLink(fi1, hk1),
                autoLink(ga1, hk1),
                autoLink(ga2, hk1),
            ]
        )
        #expect(first == ActivityFormation(
            activities: [group(id: fi1, fi1, ga2, hk1), group(id: ga1, ga1)],
            skippedLinks: [autoLink(ga1, hk1)]
        ))

        // file:f1 is kept separate from garmin:1 and from garmin:2.
        //   ...|file:f1|healthKit:W1   -> {file:f1, healthKit:W1}
        //   ...|garmin:1|healthKit:W1  -> would join garmin:1 and file:f1: skipped
        //   ...|garmin:2|healthKit:W1  -> would join garmin:2 and file:f1: skipped
        let second = ActivityFormation.form(
            records: [fi1, ga1, ga2, hk1],
            links: [
                userLink("s1", fi1, ga1, .keepSeparate),
                userLink("s2", fi1, ga2, .keepSeparate),
                autoLink(ga2, hk1),
                autoLink(ga1, hk1),
                autoLink(fi1, hk1),
            ]
        )
        #expect(second == ActivityFormation(
            activities: [group(id: fi1, fi1, hk1), group(id: ga1, ga1), group(id: ga2, ga2)],
            skippedLinks: [autoLink(ga1, hk1), autoLink(ga2, hk1)]
        ))
    }

    // MARK: The order links are applied in

    @Test func userMadeLinksAreAppliedInOrderOfName() {
        // garmin:1 and garmin:2 are kept separate. "m1" < "m2", so
        //   m1 (garmin:2 + healthKit:W1) is applied first
        //   m2 (garmin:1 + healthKit:W1) is skipped.
        // With automatic links the garmin:1 link would have come first, so
        // this shows the order is by name, not by pair.
        let m1 = userLink("m1", ga2, hk1, .sameActivity)
        let m2 = userLink("m2", ga1, hk1, .sameActivity)
        let formed = ActivityFormation.form(
            records: [ga1, ga2, hk1],
            links: [userLink("sep", ga1, ga2, .keepSeparate), m2, m1]
        )
        #expect(formed == ActivityFormation(
            activities: [group(id: ga1, ga1), group(id: ga2, ga2, hk1)],
            skippedLinks: [m2]
        ))
    }

    @Test func userMadeLinksAreAppliedBeforeAutomaticOnes() {
        // The user link's name "zz" sorts after "link|...", but user-made
        // links go first whatever their names:
        //   zz (garmin:2 + healthKit:W1)                    -> applied
        //   link|sameActivity|garmin:1|healthKit:W1 (auto)  -> skipped
        let merge = userLink("zz", ga2, hk1, .sameActivity)
        let formed = ActivityFormation.form(
            records: [ga1, ga2, hk1],
            links: [autoLink(ga1, hk1), userLink("sep", ga1, ga2, .keepSeparate), merge]
        )
        #expect(formed == ActivityFormation(
            activities: [group(id: ga1, ga1), group(id: ga2, ga2, hk1)],
            skippedLinks: [autoLink(ga1, hk1)]
        ))
    }

    @Test func onlyTheLinkInEffectForAPairTakesPartInTheOrder() {
        // garmin:1 + healthKit:W1 has two user-made merges: "a1" at time 1
        // and "z9" at time 2. The later one, z9, is in effect.
        // garmin:2 + healthKit:W1 has "m5".
        // Links in effect in name order: m5, then z9. So m5 is applied and
        // z9 is skipped. Had a1 taken part, it would have gone first and the
        // groups would be the other way round.
        let a1 = userLink("a1", ga1, hk1, .sameActivity, time: 1)
        let z9 = userLink("z9", ga1, hk1, .sameActivity, time: 2)
        let m5 = userLink("m5", ga2, hk1, .sameActivity, time: 1)
        let formed = ActivityFormation.form(
            records: [ga1, ga2, hk1],
            links: [a1, z9, m5, userLink("sep", ga1, ga2, .keepSeparate)]
        )
        #expect(formed == ActivityFormation(
            activities: [group(id: ga1, ga1), group(id: ga2, ga2, hk1)],
            skippedLinks: [z9]
        ))
    }

    // MARK: Which links count

    @Test func aUserKeepSeparateBeatsALaterAutomaticMerge() {
        // The user link is in effect for the pair, so the automatic one is
        // not applied. It is not a skipped link either: the user has decided.
        let formed = ActivityFormation.form(
            records: [ga1, hk1],
            links: [userLink("sep", ga1, hk1, .keepSeparate, time: 1), autoLink(ga1, hk1, time: 50)]
        )
        #expect(formed == ActivityFormation(
            activities: [group(id: ga1, ga1), group(id: hk1, hk1)],
            skippedLinks: []
        ))
    }

    @Test func aUserMergeBeatsALaterAutomaticKeepSeparate() {
        let formed = ActivityFormation.form(
            records: [ga1, hk1],
            links: [userLink("m", ga1, hk1, .sameActivity, time: 1), autoLink(ga1, hk1, .keepSeparate, time: 50)]
        )
        #expect(formed == ActivityFormation(activities: [group(id: ga1, ga1, hk1)], skippedLinks: []))
    }

    @Test func aSeparationThatIsNotInEffectDoesNotBlockAGroup() {
        // garmin:1 + garmin:2 were kept separate at time 10 and merged by
        // the user at time 20. The merge is in effect, so the separation is
        // lifted and all three records join.
        //   lift (user)                 -> {garmin:1, garmin:2}
        //   ...|garmin:1|healthKit:W1   -> all three
        //   ...|garmin:2|healthKit:W1   -> already together
        let formed = ActivityFormation.form(
            records: [ga1, ga2, hk1],
            links: [
                userLink("sep", ga1, ga2, .keepSeparate, time: 10),
                userLink("lift", ga1, ga2, .sameActivity, time: 20),
                autoLink(ga1, hk1),
                autoLink(ga2, hk1),
            ]
        )
        #expect(formed == ActivityFormation(activities: [group(id: ga1, ga1, ga2, hk1)], skippedLinks: []))
    }

    @Test func aLinkBetweenRecordsAlreadyTogetherIsNotSkipped() {
        // A triangle. The third link in name order joins nothing new.
        let formed = ActivityFormation.form(
            records: [ga1, ga2, hk1],
            links: [autoLink(ga1, ga2), autoLink(ga1, hk1), autoLink(ga2, hk1)]
        )
        #expect(formed == ActivityFormation(activities: [group(id: ga1, ga1, ga2, hk1)], skippedLinks: []))
    }

    @Test func aLinkNamingARecordThatIsNotThereIsIgnored() {
        // garmin:2 is not among the records, so neither link can be applied
        // and garmin:1 and healthKit:W1 are not joined through it.
        let formed = ActivityFormation.form(
            records: [ga1, hk1],
            links: [autoLink(ga1, ga2), autoLink(ga2, hk1)]
        )
        #expect(formed == ActivityFormation(
            activities: [group(id: ga1, ga1), group(id: hk1, hk1)],
            skippedLinks: []
        ))
    }

    @Test func aSeparationFromARecordThatIsNotThereBlocksNothing() {
        let formed = ActivityFormation.form(
            records: [ga1, hk1],
            links: [userLink("sep", ga1, ga2, .keepSeparate), autoLink(ga1, hk1)]
        )
        #expect(formed == ActivityFormation(activities: [group(id: ga1, ga1, hk1)], skippedLinks: []))
    }

    @Test func aLinkFromARecordToItselfIsIgnored() {
        let formed = ActivityFormation.form(
            records: [ga1, hk1],
            links: [userLink("self", ga1, ga1, .keepSeparate), autoLink(ga1, hk1)]
        )
        #expect(formed == ActivityFormation(activities: [group(id: ga1, ga1, hk1)], skippedLinks: []))
    }

    // MARK: Two devices

    @Test func aMergeAndAKeepSeparateAtTheSameMomentLeaveTheRecordsApart() {
        // Same pair, same time, two devices. "Keep separate" is in effect on
        // equal times, whichever device has the higher ID. The merge is not
        // in effect, so it is not listed as skipped.
        let records: Set<SourceIdentity> = [ga1, hk1]
        let apart = ActivityFormation(
            activities: [group(id: ga1, ga1), group(id: hk1, hk1)],
            skippedLinks: []
        )
        let mergeOnPhone = userLink("m", ga1, hk1, .sameActivity, time: 100, device: "phone")
        let separateOnPad = userLink("s", ga1, hk1, .keepSeparate, time: 100, device: "pad")
        #expect(ActivityFormation.form(records: records, links: [mergeOnPhone, separateOnPad]) == apart)
        #expect(ActivityFormation.form(records: records, links: [separateOnPad, mergeOnPhone]) == apart)

        let mergeOnPad = userLink("m", ga1, hk1, .sameActivity, time: 100, device: "pad")
        let separateOnPhone = userLink("s", ga1, hk1, .keepSeparate, time: 100, device: "phone")
        #expect(ActivityFormation.form(records: records, links: [mergeOnPad, separateOnPhone]) == apart)
        #expect(ActivityFormation.form(records: records, links: [separateOnPhone, mergeOnPad]) == apart)
    }

    @Test func theSameUserMergeMadeOnTwoOfflineDevicesFormsOneActivity() {
        // Each device wrote its own record of the same merge. Together they
        // form exactly what either forms alone.
        let records: Set<SourceIdentity> = [ga1, hk1]
        let together = ActivityFormation(activities: [group(id: ga1, ga1, hk1)], skippedLinks: [])
        let onPhone = userLink("m-phone", ga1, hk1, .sameActivity, time: 100, device: "phone")
        let onPad = userLink("m-pad", hk1, ga1, .sameActivity, time: 130, device: "pad")
        #expect(ActivityFormation.form(records: records, links: [onPhone]) == together)
        #expect(ActivityFormation.form(records: records, links: [onPad]) == together)
        #expect(ActivityFormation.form(records: records, links: [onPhone, onPad]) == together)
        #expect(ActivityFormation.form(records: records, links: [onPad, onPhone]) == together)
    }

    @Test func theSameAutomaticMergeMadeOnTwoOfflineDevicesFormsOneActivity() {
        // Both devices wrote a record of the same name. Before storage
        // settles on one, both copies may be on hand, with their own times
        // and devices.
        let records: Set<SourceIdentity> = [ga1, hk1]
        let together = ActivityFormation(activities: [group(id: ga1, ga1, hk1)], skippedLinks: [])
        let onPhone = autoLink(ga1, hk1, time: 100, device: "phone")
        let onPad = autoLink(ga1, hk1, time: 130, device: "pad")
        #expect(onPhone.name == onPad.name)
        #expect(ActivityFormation.form(records: records, links: [onPhone]) == together)
        #expect(ActivityFormation.form(records: records, links: [onPhone, onPad]) == together)
        #expect(ActivityFormation.form(records: records, links: [onPad, onPhone]) == together)
    }

    // MARK: Order independence

    @Test func theSpecsThreeRecordCaseDoesNotDependOnLinkOrder() {
        let links = [
            userLink("sep", ga1, ga2, .keepSeparate, time: 10),
            autoLink(ga1, hk1),
            autoLink(ga2, hk1),
        ]
        let expected = ActivityFormation(
            activities: [group(id: ga1, ga1, hk1), group(id: ga2, ga2)],
            skippedLinks: [autoLink(ga2, hk1)]
        )
        // 3 links, 6 orderings.
        for ordering in permutations(links) {
            #expect(ActivityFormation.form(records: [ga1, ga2, hk1], links: ordering) == expected)
        }
    }

    @Test func aMixOfUserAndAutomaticLinksDoesNotDependOnLinkOrder() {
        // Five records and five links.
        //   s1: garmin:1 and garmin:2 kept separate (user).
        //   u1: healthKit:W1 + healthKit:W2 (user).
        //   automatic, in name order:
        //     ...|file:f1|garmin:2
        //     ...|garmin:1|healthKit:W1
        //     ...|garmin:2|healthKit:W2
        // Applied: u1 -> {W1, W2}. file:f1|garmin:2 -> {f1, garmin:2}.
        // garmin:1|W1 -> {garmin:1, W1, W2}. garmin:2|W2 would put garmin:1
        // and garmin:2 together: skipped.
        let s1 = userLink("s1", ga1, ga2, .keepSeparate)
        let u1 = userLink("u1", hk1, hk2, .sameActivity)
        let links = [s1, u1, autoLink(fi1, ga2), autoLink(ga1, hk1), autoLink(ga2, hk2)]
        let expected = ActivityFormation(
            activities: [group(id: fi1, fi1, ga2), group(id: ga1, ga1, hk1, hk2)],
            skippedLinks: [autoLink(ga2, hk2)]
        )
        // 5 links, 120 orderings.
        for ordering in permutations(links) {
            #expect(ActivityFormation.form(records: [fi1, ga1, ga2, hk1, hk2], links: ordering) == expected)
        }
    }
}

@Suite("Merges that would break a separation")
struct BlockedMergeTests {
    private let separation = userLink("sep", ga1, ga2, .keepSeparate, time: 10)

    @Test func mergingTheSeparatedPairItselfIsBlockedByItsSeparation() {
        let blocking = ActivityFormation.separationsBlockingMerge(
            of: ga1,
            with: ga2,
            records: [ga1, ga2],
            links: [separation]
        )
        #expect(blocking == [separation])
    }

    @Test func mergingIntoAGroupThatHoldsASeparatedRecordIsBlocked() {
        // garmin:1 and healthKit:W1 are one activity. Merging garmin:2 with
        // healthKit:W1 would put garmin:1 and garmin:2 together.
        let links = [separation, autoLink(ga1, hk1)]
        let records: Set<SourceIdentity> = [ga1, ga2, hk1]
        #expect(ActivityFormation.separationsBlockingMerge(of: ga2, with: hk1, records: records, links: links) == [separation])
        #expect(ActivityFormation.separationsBlockingMerge(of: hk1, with: ga2, records: records, links: links) == [separation])
    }

    @Test func aMergeThatBreaksNoSeparationIsNotBlocked() {
        let records: Set<SourceIdentity> = [ga1, ga2, hk1]
        let blocking = ActivityFormation.separationsBlockingMerge(
            of: ga1,
            with: hk1,
            records: records,
            links: [separation]
        )
        #expect(blocking.isEmpty)
    }

    @Test func recordsAlreadyInOneActivityHaveNothingBlockingThem() {
        let blocking = ActivityFormation.separationsBlockingMerge(
            of: ga1,
            with: hk1,
            records: [ga1, ga2, hk1],
            links: [separation, autoLink(ga1, hk1)]
        )
        #expect(blocking.isEmpty)
    }

    @Test func aLiftedSeparationNoLongerBlocks() {
        // The later user merge is the link in effect for the pair.
        let lift = userLink("lift", ga1, ga2, .sameActivity, time: 20)
        let blocking = ActivityFormation.separationsBlockingMerge(
            of: ga2,
            with: hk1,
            records: [ga1, ga2, hk1],
            links: [separation, lift, autoLink(ga1, hk1)]
        )
        #expect(blocking.isEmpty)
    }

    @Test func everyBlockingSeparationIsListedInOrderOfName() {
        // {garmin:1, healthKit:W1} and {garmin:2, healthKit:W2} are two
        // activities. garmin:1 is kept separate from garmin:2 ("s2") and
        // healthKit:W1 from healthKit:W2 ("s1"). Merging any member of one
        // with any member of the other breaks both. "s1" < "s2".
        let s2 = userLink("s2", ga1, ga2, .keepSeparate)
        let s1 = userLink("s1", hk1, hk2, .keepSeparate)
        let links = [s2, s1, autoLink(ga1, hk1), autoLink(ga2, hk2)]
        let records: Set<SourceIdentity> = [ga1, ga2, hk1, hk2]
        for ordering in permutations(links) {
            let blocking = ActivityFormation.separationsBlockingMerge(
                of: ga1,
                with: hk2,
                records: records,
                links: ordering
            )
            #expect(blocking == [s1, s2])
        }
    }
}
