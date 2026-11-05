import Foundation
import SweatKitIdentity
import SweatKitModel
import Testing

@Suite("Link records and automatic names")
struct LinkRecordTests {
    @Test func anAutomaticLinkIsNamedFromItsPairAndKind() {
        // link|<kind>|<lower>|<upper>, with garmin:1 < healthKit:W1.
        let name = LinkRecord.automaticName(pair: IdentityPair(ga1, hk1), kind: .sameActivity)
        #expect(name == RecordName("link|sameActivity|garmin:1|healthKit:W1"))
    }

    @Test func theAutomaticNameIsTheSameWhicheverRecordComesFirst() {
        let name = LinkRecord.automaticName(pair: IdentityPair(hk1, ga1), kind: .sameActivity)
        #expect(name == RecordName("link|sameActivity|garmin:1|healthKit:W1"))
    }

    @Test func theAutomaticNameCarriesTheKind() {
        let name = LinkRecord.automaticName(pair: IdentityPair(ga1, hk1), kind: .keepSeparate)
        #expect(name == RecordName("link|keepSeparate|garmin:1|healthKit:W1"))
    }

    @Test func theAutomaticNameCarriesBothIdentities() {
        let name = LinkRecord.automaticName(pair: IdentityPair(hk2, fi1), kind: .sameActivity)
        #expect(name == RecordName("link|sameActivity|file:f1|healthKit:W2"))
    }

    @Test func anAutomaticLinkHoldsItsPairKindMakerTimeAndDevice() {
        let link = LinkRecord.automatic(pair: IdentityPair(hk1, ga1), time: at(50), device: DeviceID("pad"))
        #expect(link == LinkRecord(
            name: RecordName("link|sameActivity|garmin:1|healthKit:W1"),
            pair: IdentityPair(ga1, hk1),
            kind: .sameActivity,
            maker: .automatic,
            time: at(50),
            device: DeviceID("pad")
        ))
    }

    @Test func anAutomaticKeepSeparateLinkIsNamedForItsKind() {
        let link = LinkRecord.automatic(
            pair: IdentityPair(ga1, hk1),
            kind: .keepSeparate,
            time: at(50),
            device: DeviceID("pad")
        )
        #expect(link.name == RecordName("link|keepSeparate|garmin:1|healthKit:W1"))
        #expect(link.kind == .keepSeparate)
        #expect(link.maker == .automatic)
    }

    @Test func twoDevicesMakingTheSameAutomaticMergeWriteTheSameRecordName() {
        let onPhone = LinkRecord.automatic(pair: IdentityPair(ga1, hk1), time: at(10), device: DeviceID("phone"))
        let onPad = LinkRecord.automatic(pair: IdentityPair(hk1, ga1), time: at(99), device: DeviceID("pad"))
        #expect(onPhone.name == onPad.name)
    }
}

@Suite("Which link is in effect for a pair")
struct LinkInEffectTests {
    private let pair = IdentityPair(ga1, hk1)

    /// The winner whichever link is listed first.
    private func inEffect(_ first: LinkRecord, _ second: LinkRecord) -> [LinkRecord?] {
        [
            LinkRecord.inEffect(for: pair, among: [first, second]),
            LinkRecord.inEffect(for: pair, among: [second, first]),
        ]
    }

    @Test func aPairWithNoLinkHasNoneInEffect() {
        #expect(LinkRecord.inEffect(for: pair, among: [LinkRecord]()) == nil)
    }

    @Test func aPairWithOneLinkHasThatLinkInEffect() {
        let link = autoLink(ga1, hk1)
        #expect(LinkRecord.inEffect(for: pair, among: [link]) == link)
    }

    @Test func linksOnOtherPairsAreIgnored() {
        let other = userLink("other", ga2, hk1, .keepSeparate, time: 99)
        let link = autoLink(ga1, hk1)
        #expect(LinkRecord.inEffect(for: pair, among: [other]) == nil)
        #expect(LinkRecord.inEffect(for: pair, among: [other, link]) == link)
    }

    @Test func aLinkIsFoundWhicheverWayRoundThePairIsAsked() {
        let link = autoLink(ga1, hk1)
        #expect(LinkRecord.inEffect(for: IdentityPair(hk1, ga1), among: [link]) == link)
    }

    // The tie-break order, one step at a time. In each test the loser is
    // given every later advantage, so only the step under test can decide.

    @Test func step1AUserMadeLinkBeatsAnAutomaticOne() {
        // The automatic link is later (100 > 1), is "keep separate", has the
        // higher device ("z" > "a") and the higher name ("link..." > "a-user").
        let user = userLink("a-user", ga1, hk1, .sameActivity, time: 1, device: "a")
        let automatic = autoLink(ga1, hk1, .keepSeparate, time: 100, device: "z")
        #expect(inEffect(user, automatic) == [user, user])
    }

    @Test func step2TheLaterTimeWinsBetweenUserMadeLinks() {
        // The earlier link is "keep separate", with the higher device and name.
        let earlier = userLink("z", ga1, hk1, .keepSeparate, time: 1, device: "z")
        let later = userLink("a", ga1, hk1, .sameActivity, time: 2, device: "a")
        #expect(inEffect(earlier, later) == [later, later])
    }

    @Test func step2TheLaterTimeWinsBetweenAutomaticLinks() {
        // The earlier link is "keep separate", with the higher device.
        let earlier = autoLink(ga1, hk1, .keepSeparate, time: 1, device: "z")
        let later = autoLink(ga1, hk1, .sameActivity, time: 2, device: "a")
        #expect(inEffect(earlier, later) == [later, later])
    }

    @Test func step3OnEqualTimesKeepSeparateBeatsSameActivity() {
        // The "same activity" link has the higher device and name.
        let same = userLink("z", ga1, hk1, .sameActivity, time: 5, device: "z")
        let separate = userLink("a", ga1, hk1, .keepSeparate, time: 5, device: "a")
        #expect(inEffect(same, separate) == [separate, separate])
    }

    @Test func step4ThenTheHigherDeviceIDWins() {
        // Equal times and kinds. Device "b" > "a"; the loser has the higher name.
        let lowDevice = userLink("z", ga1, hk1, .sameActivity, time: 5, device: "a")
        let highDevice = userLink("a", ga1, hk1, .sameActivity, time: 5, device: "b")
        #expect(inEffect(lowDevice, highDevice) == [highDevice, highDevice])
    }

    @Test func step5ThenTheHigherRecordNameWins() {
        // Everything equal but the name. "b" > "a".
        let lowName = userLink("a", ga1, hk1, .sameActivity, time: 5, device: "x")
        let highName = userLink("b", ga1, hk1, .sameActivity, time: 5, device: "x")
        #expect(inEffect(lowName, highName) == [highName, highName])
    }

    @Test func aMergeAndAKeepSeparateAtTheSameMomentResolveToSeparate() {
        // Two devices, the same pair, the same time. Whichever device has
        // the higher ID, "keep separate" is in effect, because kind is
        // compared before device.
        let mergeOnPhone = userLink("m", ga1, hk1, .sameActivity, time: 100, device: "phone")
        let separateOnPad = userLink("s", ga1, hk1, .keepSeparate, time: 100, device: "pad")
        #expect(inEffect(mergeOnPhone, separateOnPad) == [separateOnPad, separateOnPad])

        let mergeOnPad = userLink("m", ga1, hk1, .sameActivity, time: 100, device: "pad")
        let separateOnPhone = userLink("s", ga1, hk1, .keepSeparate, time: 100, device: "phone")
        #expect(inEffect(mergeOnPad, separateOnPhone) == [separateOnPhone, separateOnPhone])
    }

    @Test func aLaterMergeLiftsAnEarlierSeparation() {
        let separate = userLink("s", ga1, hk1, .keepSeparate, time: 10)
        let merge = userLink("m", ga1, hk1, .sameActivity, time: 20)
        #expect(inEffect(separate, merge) == [merge, merge])
    }

    @Test func theLinkInEffectDoesNotDependOnTheOrderOfTheLinks() {
        // Five links on one pair. The user-made ones are u1, u2 and u3.
        // Among them the latest time is 20, shared by u2 and u3. u3 is
        // "keep separate", so u3 is in effect. The automatic links never get
        // a say.
        let u1 = userLink("u1", ga1, hk1, .keepSeparate, time: 10, device: "z")
        let u2 = userLink("u2", ga1, hk1, .sameActivity, time: 20, device: "z")
        let u3 = userLink("u3", ga1, hk1, .keepSeparate, time: 20, device: "a")
        let a1 = autoLink(ga1, hk1, .sameActivity, time: 30, device: "z")
        let a2 = autoLink(ga1, hk1, .keepSeparate, time: 40, device: "z")
        // 5 links, 120 orderings.
        for ordering in permutations([u1, u2, u3, a1, a2]) {
            #expect(LinkRecord.inEffect(for: pair, among: ordering) == u3)
        }
    }

    @Test func everyPairGetsItsOwnLinkInEffect() {
        // garmin:1 + healthKit:W1: the user link beats the automatic one.
        // garmin:2 + healthKit:W1: only one link.
        // garmin:1 + garmin:2: the later of two user links.
        let auto1 = autoLink(ga1, hk1, time: 50)
        let user1 = userLink("u1", ga1, hk1, .keepSeparate, time: 1)
        let auto2 = autoLink(ga2, hk1, time: 50)
        let early = userLink("u2", ga1, ga2, .keepSeparate, time: 1)
        let late = userLink("u3", ga2, ga1, .sameActivity, time: 2)
        let expected: [IdentityPair: LinkRecord] = [
            IdentityPair(ga1, hk1): user1,
            IdentityPair(ga2, hk1): auto2,
            IdentityPair(ga1, ga2): late,
        ]
        for ordering in permutations([auto1, user1, auto2, early, late]) {
            #expect(LinkRecord.inEffect(among: ordering) == expected)
        }
    }

    @Test func noLinksMeansNoPairs() {
        #expect(LinkRecord.inEffect(among: [LinkRecord]()).isEmpty)
    }
}
