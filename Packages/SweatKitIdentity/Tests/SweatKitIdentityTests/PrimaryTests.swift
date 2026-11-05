import Foundation
import SweatKitIdentity
import SweatKitModel
import Testing

@Suite("The primary record")
struct PrimaryTests {
    // MARK: Default order

    @Test func theDefaultOrderIsAnOriginalFileThenHealthKit() {
        // Garmin records and imported files are both original files.
        #expect(PrimaryChoice.defaultOrder == [[.garmin, .file], [.healthKit]])
    }

    @Test func aGarminOriginalIsTheDefaultOverHealthKit() {
        #expect(PrimaryChoice.defaultPrimary(among: [hk1, ga1]) == ga1)
    }

    @Test func anImportedFileIsTheDefaultOverHealthKit() {
        #expect(PrimaryChoice.defaultPrimary(among: [hk1, fi1]) == fi1)
    }

    @Test func healthKitIsTheDefaultWhenThereIsNoOriginalFile() {
        #expect(PrimaryChoice.defaultPrimary(among: [hk1]) == hk1)
    }

    @Test func amongSeveralOriginalFilesTheLowestIdentityIsTheDefault() {
        // file:f1 < garmin:1 < garmin:2.
        #expect(PrimaryChoice.defaultPrimary(among: [ga2, ga1, hk1]) == ga1)
        #expect(PrimaryChoice.defaultPrimary(among: [ga1, fi1, hk1]) == fi1)
    }

    @Test func amongSeveralHealthKitRecordsTheLowestIdentityIsTheDefault() {
        // healthKit:W1 < healthKit:W2.
        #expect(PrimaryChoice.defaultPrimary(among: [hk2, hk1]) == hk1)
    }

    @Test func noMembersHaveNoDefault() {
        #expect(PrimaryChoice.defaultPrimary(among: []) == nil)
    }

    // MARK: The choice is a decision

    @Test func withNoChoiceTheDefaultOrderApplies() {
        #expect(PrimaryChoice.primary(of: [ga1, hk1], among: [DecisionRecord]()) == ga1)
    }

    @Test func theUserCanSwitchThePrimary() {
        let choice = decision("p", .primary(hk1), time: 1, on: [ga1, hk1])
        #expect(PrimaryChoice.primary(of: [ga1, hk1], among: [choice]) == hk1)
    }

    @Test func theLatestChoiceWins() {
        let first = decision("p1", .primary(hk1), time: 1, on: [ga1, hk1])
        let second = decision("p2", .primary(ga1), time: 2, on: [ga1, hk1])
        #expect(PrimaryChoice.primary(of: [ga1, hk1], among: [first, second]) == ga1)
        #expect(PrimaryChoice.primary(of: [ga1, hk1], among: [second, first]) == ga1)
    }

    @Test func twoChoicesAtTheSameTimeGoToTheHigherDevice() {
        // "phone" > "pad".
        let onPad = decision("p-z", .primary(ga1), time: 100, device: "pad", on: [ga1, hk1, fi1])
        let onPhone = decision("p-a", .primary(hk1), time: 100, device: "phone", on: [ga1, hk1, fi1])
        #expect(PrimaryChoice.primary(of: [ga1, hk1, fi1], among: [onPad, onPhone]) == hk1)
        #expect(PrimaryChoice.primary(of: [ga1, hk1, fi1], among: [onPhone, onPad]) == hk1)
    }

    @Test func ifTheChosenPrimaryIsNoLongerAMemberTheDefaultOrderAppliesAgain() {
        // healthKit:W1 was chosen while a member, then split away. What is
        // left is {garmin:1, garmin:2}, whose default is garmin:1.
        let choice = decision("p", .primary(hk1), time: 1, on: [ga1, ga2, hk1])
        #expect(PrimaryChoice.primary(of: [ga1, ga2], among: [choice]) == ga1)
    }

    @Test func anEarlierChoiceIsNotRevivedWhenTheWinningChoiceHasLeft() {
        // First healthKit:W1 was chosen, then garmin:2. garmin:2 has since
        // left. The winning choice is still garmin:2, which is not a member,
        // so the default applies: garmin:1, not the earlier healthKit:W1.
        let first = decision("p1", .primary(hk1), time: 1, on: [ga1, hk1])
        let second = decision("p2", .primary(ga2), time: 2, on: [ga1, ga2, hk1])
        #expect(PrimaryChoice.primary(of: [ga1, hk1], among: [first, second]) == ga1)
        #expect(PrimaryChoice.primary(of: [ga1, hk1], among: [second, first]) == ga1)
    }

    @Test func aChoiceMadeOnOneMemberBeforeAMergeHoldsForTheMergedActivity() {
        // The choice applies to healthKit:W1, which is a member.
        let choice = decision("p", .primary(hk1), time: 1, on: [hk1, hk2])
        #expect(PrimaryChoice.primary(of: [ga1, hk1, hk2], among: [choice]) == hk1)
    }

    @Test func noMembersHaveNoPrimary() {
        #expect(PrimaryChoice.primary(of: [], among: [DecisionRecord]()) == nil)
    }

    // MARK: Decisions belong to the activity

    @Test func switchingThePrimaryChangesNothingElse() {
        // "A renamed activity whose primary source is switched."
        let rename = decision("t", .title("Morning loop"), time: 1, on: [ga1, hk1])
        let hide = decision("h", .hidden(true), time: 2, on: [ga1, hk1])
        let members: Set<SourceIdentity> = [ga1, hk1]

        // Before the switch.
        #expect(PrimaryChoice.primary(of: members, among: [rename, hide]) == ga1)
        #expect(DecisionRecord.title(of: members, among: [rename, hide]) == "Morning loop")
        #expect(DecisionRecord.isHidden(members, among: [rename, hide]))

        // After it: a new primary, the same title and hidden state.
        let switched = decision("p", .primary(hk1), time: 3, on: [ga1, hk1])
        #expect(PrimaryChoice.primary(of: members, among: [rename, hide, switched]) == hk1)
        #expect(DecisionRecord.title(of: members, among: [rename, hide, switched]) == "Morning loop")
        #expect(DecisionRecord.isHidden(members, among: [rename, hide, switched]))
    }

    // MARK: Alternatives

    @Test func anAlternativeHoldingAChannelThePrimaryLacksIsOffered() {
        // The Garmin file has no heart rate. The Health workout does.
        let offers = PrimaryChoice.alternativesOfferingMore(
            than: ga1,
            channelsByMember: [
                ga1: [.latitude, .longitude, .power, .cadence],
                hk1: [.heartRate, .power],
            ]
        )
        #expect(offers == [AlternativeOffer(identity: hk1, channels: [.heartRate])])
    }

    @Test func anAlternativeWithNothingToAddIsNotOffered() {
        let offers = PrimaryChoice.alternativesOfferingMore(
            than: ga1,
            channelsByMember: [
                ga1: [.power, .heartRate],
                hk1: [.heartRate],
            ]
        )
        #expect(offers.isEmpty)
    }

    @Test func offersAreOrderedByIdentityAndListEveryMissingChannel() {
        // file:f1 < healthKit:W1.
        let offers = PrimaryChoice.alternativesOfferingMore(
            than: ga1,
            channelsByMember: [
                hk1: [.heartRate, .cadence, .power],
                ga1: [.power],
                fi1: [.temperature, .power],
            ]
        )
        #expect(offers == [
            AlternativeOffer(identity: fi1, channels: [.temperature]),
            AlternativeOffer(identity: hk1, channels: [.heartRate, .cadence]),
        ])
    }

    @Test func aPrimaryWithNoListedChannelsHoldsNone() {
        let offers = PrimaryChoice.alternativesOfferingMore(
            than: ga1,
            channelsByMember: [hk1: [.heartRate]]
        )
        #expect(offers == [AlternativeOffer(identity: hk1, channels: [.heartRate])])
    }
}
