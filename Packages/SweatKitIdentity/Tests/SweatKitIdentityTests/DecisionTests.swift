import Foundation
import SweatKitIdentity
import SweatKitModel
import Testing

@Suite("Decision records")
struct DecisionRecordTests {
    @Test func aValueSaysWhichFieldItSets() {
        #expect(DecisionValue.title("Morning loop").field == .title)
        #expect(DecisionValue.hidden(true).field == .hidden)
        #expect(DecisionValue.hidden(false).field == .hidden)
        #expect(DecisionValue.primary(hk1).field == .primary)
    }

    @Test func aRecordsFieldIsItsValuesField() {
        #expect(decision("t", .title("Morning loop"), time: 1, on: [ga1]).field == .title)
        #expect(decision("h", .hidden(true), time: 1, on: [ga1]).field == .hidden)
        #expect(decision("p", .primary(ga1), time: 1, on: [ga1]).field == .primary)
    }

    @Test func aDecisionIsDirectUnlessMarkedAsACopy() {
        let record = DecisionRecord(
            name: RecordName("t"),
            value: .title("Morning loop"),
            time: at(1),
            device: DeviceID("phone"),
            members: [ga1]
        )
        #expect(record.origin == .direct)
    }
}

@Suite("Which decision wins")
struct DecisionWinnerTests {
    /// The winner whichever decision is listed first.
    private func winner(_ first: DecisionRecord, _ second: DecisionRecord) -> [DecisionRecord?] {
        [
            DecisionRecord.winner(among: [first, second]),
            DecisionRecord.winner(among: [second, first]),
        ]
    }

    @Test func noDecisionsHaveNoWinner() {
        #expect(DecisionRecord.winner(among: [DecisionRecord]()) == nil)
    }

    @Test func aLoneDecisionWins() {
        let only = decision("t", .title("Morning loop"), time: 1, on: [ga1])
        #expect(DecisionRecord.winner(among: [only]) == only)
    }

    // The tie-break order, one step at a time. In each test the loser is
    // given every later advantage, so only the step under test can decide.

    @Test func step1TheLaterTimeWins() {
        // The earlier decision is direct, with the higher device and name.
        let earlier = decision("z", .title("Old"), time: 1, device: "z", on: [ga1])
        let later = decision("a", .title("New"), time: 2, device: "a", on: [ga1], origin: .inheritedCopy)
        #expect(winner(earlier, later) == [later, later])
    }

    @Test func step2OnEqualTimesADirectDecisionBeatsAnInheritedCopy() {
        // The copy has the higher device and name.
        let copy = decision("z", .title("Copied"), time: 5, device: "z", on: [ga1], origin: .inheritedCopy)
        let direct = decision("a", .title("Direct"), time: 5, device: "a", on: [ga1])
        #expect(winner(copy, direct) == [direct, direct])
    }

    @Test func step3ThenTheHigherDeviceIDWins() {
        // Equal times, both direct. Device "b" > "a"; the loser has the
        // higher name.
        let lowDevice = decision("z", .title("Low"), time: 5, device: "a", on: [ga1])
        let highDevice = decision("a", .title("High"), time: 5, device: "b", on: [ga1])
        #expect(winner(lowDevice, highDevice) == [highDevice, highDevice])
    }

    @Test func step3TheHigherDeviceIDWinsBetweenTwoCopies() {
        let lowDevice = decision("z", .title("Low"), time: 5, device: "a", on: [ga1], origin: .inheritedCopy)
        let highDevice = decision("a", .title("High"), time: 5, device: "b", on: [ga1], origin: .inheritedCopy)
        #expect(winner(lowDevice, highDevice) == [highDevice, highDevice])
    }

    @Test func step4ThenTheHigherRecordNameWins() {
        // Everything equal but the name. "b" > "a".
        let lowName = decision("a", .title("Low"), time: 5, device: "x", on: [ga1])
        let highName = decision("b", .title("High"), time: 5, device: "x", on: [ga1])
        #expect(winner(lowName, highName) == [highName, highName])
    }

    @Test func theWinnerDoesNotDependOnTheOrderOfTheDecisions() {
        // Five title decisions. The latest time is 20, shared by d2, d3 and
        // d4. d2 is a copy, so it loses to the direct d3 and d4. Between
        // those, device "phone" > "pad", so d4 wins.
        let d1 = decision("d1", .title("One"), time: 10, device: "z", on: [ga1])
        let d2 = decision("d2", .title("Two"), time: 20, device: "z", on: [ga1], origin: .inheritedCopy)
        let d3 = decision("d3", .title("Three"), time: 20, device: "pad", on: [ga1])
        let d4 = decision("d4", .title("Four"), time: 20, device: "phone", on: [ga1])
        let d5 = decision("d5", .title("Five"), time: 15, device: "z", on: [ga1])
        // 5 decisions, 120 orderings.
        for ordering in permutations([d1, d2, d3, d4, d5]) {
            #expect(DecisionRecord.winner(among: ordering) == d4)
        }
    }

    // MARK: Per member

    @Test func aMembersWinnerIsTakenFromTheDecisionsThatApplyToIt() {
        // The later title applies to healthKit:W1 only, so garmin:1's winner
        // is the earlier one.
        let onBoth = decision("t1", .title("Morning loop"), time: 1, on: [ga1, hk1])
        let onOne = decision("t2", .title("Commute"), time: 2, on: [hk1])
        #expect(DecisionRecord.winner(of: .title, for: ga1, among: [onBoth, onOne]) == onBoth)
        #expect(DecisionRecord.winner(of: .title, for: hk1, among: [onBoth, onOne]) == onOne)
    }

    @Test func aMembersWinnerIsTakenFromDecisionsOnTheFieldAsked() {
        // The hide is later than the title, but it is not a title.
        let title = decision("t", .title("Morning loop"), time: 1, on: [ga1])
        let hide = decision("h", .hidden(true), time: 9, on: [ga1])
        #expect(DecisionRecord.winner(of: .title, for: ga1, among: [title, hide]) == title)
        #expect(DecisionRecord.winner(of: .hidden, for: ga1, among: [title, hide]) == hide)
        #expect(DecisionRecord.winner(of: .primary, for: ga1, among: [title, hide]) == nil)
    }

    @Test func aMemberNoDecisionAppliesToHasNoWinner() {
        let title = decision("t", .title("Morning loop"), time: 1, on: [ga1])
        #expect(DecisionRecord.winner(of: .title, for: hk1, among: [title]) == nil)
    }
}

@Suite("An activity's title")
struct TitleTests {
    @Test func anActivityNobodyTitledHasNoTitle() {
        #expect(DecisionRecord.title(of: [ga1, hk1], among: [DecisionRecord]()) == nil)
    }

    @Test func aTitleDecisionGivesTheActivityItsTitle() {
        let title = decision("t", .title("Morning loop"), time: 1, on: [ga1, hk1])
        #expect(DecisionRecord.title(of: [ga1, hk1], among: [title]) == "Morning loop")
    }

    @Test func theLaterTitleWins() {
        let first = decision("t1", .title("Morning loop"), time: 1, on: [ga1, hk1])
        let second = decision("t2", .title("Commute"), time: 2, on: [ga1, hk1])
        #expect(DecisionRecord.title(of: [ga1, hk1], among: [first, second]) == "Commute")
        #expect(DecisionRecord.title(of: [ga1, hk1], among: [second, first]) == "Commute")
    }

    @Test func aMergedActivityTakesTheMostRecentTitleOfItsParts() {
        // Each record was titled on its own before the merge, and the merge
        // wrote no decision. garmin:1's winner is at time 1 and
        // healthKit:W1's at time 2, so the activity uses the later.
        let morning = decision("t1", .title("Morning loop"), time: 1, on: [ga1])
        let evening = decision("t2", .title("Evening spin"), time: 2, on: [hk1])
        #expect(DecisionRecord.title(of: [ga1, hk1], among: [morning, evening]) == "Evening spin")
        #expect(DecisionRecord.title(of: [ga1, hk1], among: [evening, morning]) == "Evening spin")
    }

    @Test func aTitleOnOneMemberTitlesTheWholeActivity() {
        let morning = decision("t1", .title("Morning loop"), time: 1, on: [ga1])
        #expect(DecisionRecord.title(of: [ga1, hk1], among: [morning]) == "Morning loop")
    }

    @Test func aTitleOnARecordOutsideTheActivityDoesNotApply() {
        let other = decision("t1", .title("Someone else"), time: 9, on: [ga2])
        #expect(DecisionRecord.title(of: [ga1, hk1], among: [other]) == nil)
    }

    @Test func aDecisionStillAppliesToAMemberAfterTheOthersHaveLeft() {
        // Made on {garmin:1, healthKit:W1}. After a split it still applies
        // to garmin:1 on its own.
        let title = decision("t", .title("Morning loop"), time: 1, on: [ga1, hk1])
        #expect(DecisionRecord.title(of: [ga1], among: [title]) == "Morning loop")
    }

    @Test func otherFieldsDoNotChangeTheTitle() {
        let title = decision("t", .title("Morning loop"), time: 1, on: [ga1, hk1])
        let hide = decision("h", .hidden(true), time: 5, on: [ga1, hk1])
        let primary = decision("p", .primary(hk1), time: 6, on: [ga1, hk1])
        #expect(DecisionRecord.title(of: [ga1, hk1], among: [hide, title, primary]) == "Morning loop")
    }

    // "Two decisions on the same field with equal times."

    @Test func twoTitlesAtTheSameTimeFromTwoDevicesGoToTheHigherDevice() {
        // "phone" > "pad".
        let onPad = decision("t-z", .title("From the pad"), time: 100, device: "pad", on: [ga1, hk1])
        let onPhone = decision("t-a", .title("From the phone"), time: 100, device: "phone", on: [ga1, hk1])
        #expect(DecisionRecord.title(of: [ga1, hk1], among: [onPad, onPhone]) == "From the phone")
        #expect(DecisionRecord.title(of: [ga1, hk1], among: [onPhone, onPad]) == "From the phone")
    }

    @Test func twoTitlesAtTheSameTimeFromOneDeviceGoToTheHigherName() {
        // "t-b" > "t-a".
        let lowName = decision("t-a", .title("First"), time: 100, on: [ga1, hk1])
        let highName = decision("t-b", .title("Second"), time: 100, on: [ga1, hk1])
        #expect(DecisionRecord.title(of: [ga1, hk1], among: [lowName, highName]) == "Second")
        #expect(DecisionRecord.title(of: [ga1, hk1], among: [highName, lowName]) == "Second")
    }

    @Test func twoTitlesAtTheSameTimeOnDifferentMembersGoToTheHigherDevice() {
        // garmin:1's winner and healthKit:W1's winner tie on time and are
        // both direct. "phone" > "pad".
        let onPhone = decision("t1", .title("Morning loop"), time: 100, device: "phone", on: [ga1])
        let onPad = decision("t2", .title("Hill repeats"), time: 100, device: "pad", on: [hk1])
        #expect(DecisionRecord.title(of: [ga1, hk1], among: [onPad, onPhone]) == "Morning loop")
        #expect(DecisionRecord.title(of: [ga1, hk1], among: [onPhone, onPad]) == "Morning loop")
    }

    @Test func aDirectTitleBeatsACopyMadeAtTheSameTime() {
        // The copy comes from the higher device and has the higher name.
        let copy = decision("z", .title("Copied"), time: 100, device: "z", on: [ga1], origin: .inheritedCopy)
        let direct = decision("a", .title("Direct"), time: 100, device: "a", on: [ga1])
        #expect(DecisionRecord.title(of: [ga1], among: [copy, direct]) == "Direct")
        #expect(DecisionRecord.title(of: [ga1], among: [direct, copy]) == "Direct")
    }
}

@Suite("An activity's hidden state")
struct HiddenTests {
    @Test func anActivityWithNoHiddenDecisionIsNotHidden() {
        let title = decision("t", .title("Morning loop"), time: 1, on: [ga1])
        #expect(!DecisionRecord.isHidden([ga1, hk1], among: [DecisionRecord]()))
        #expect(!DecisionRecord.isHidden([ga1, hk1], among: [title]))
    }

    @Test func aHideHidesTheActivity() {
        let hide = decision("h", .hidden(true), time: 1, on: [ga1, hk1])
        #expect(DecisionRecord.isHidden([ga1, hk1], among: [hide]))
    }

    @Test func aLaterRestoreOnTheWholeActivityShowsItAgain() {
        let hide = decision("h", .hidden(true), time: 1, on: [ga1, hk1])
        let restore = decision("r", .hidden(false), time: 2, on: [ga1, hk1])
        #expect(!DecisionRecord.isHidden([ga1, hk1], among: [hide, restore]))
        #expect(!DecisionRecord.isHidden([ga1, hk1], among: [restore, hide]))
    }

    @Test func aRestoreEarlierThanTheHideDoesNotShowIt() {
        let restore = decision("r", .hidden(false), time: 1, on: [ga1, hk1])
        let hide = decision("h", .hidden(true), time: 2, on: [ga1, hk1])
        #expect(DecisionRecord.isHidden([ga1, hk1], among: [hide, restore]))
        #expect(DecisionRecord.isHidden([ga1, hk1], among: [restore, hide]))
    }

    @Test func aHiddenActivityMergedWithAVisibleOneIsHidden() {
        // garmin:1 was hidden on its own. healthKit:W1 has no decision. The
        // merge writes none, and garmin:1's winning decision is "hide".
        let hide = decision("h", .hidden(true), time: 1, on: [ga1])
        #expect(DecisionRecord.isHidden([ga1, hk1], among: [hide]))
        // Before the merge, the visible side was visible.
        #expect(!DecisionRecord.isHidden([hk1], among: [hide]))
    }

    @Test func anActivityIsHiddenIfAnyMembersWinningDecisionIsHide() {
        // garmin:1's winner is the hide at time 1. healthKit:W1's winner is
        // a restore at time 5 that applies to it alone. The restore is the
        // later decision, but hidden state is not a single-value field: one
        // member hidden is enough.
        let hide = decision("h", .hidden(true), time: 1, on: [ga1])
        let restoreOther = decision("r", .hidden(false), time: 5, on: [hk1])
        #expect(DecisionRecord.isHidden([ga1, hk1], among: [hide, restoreOther]))
        #expect(DecisionRecord.isHidden([ga1, hk1], among: [restoreOther, hide]))
    }

    @Test func aRestoreOnTheMergedActivityReachesEveryMember() {
        // The restore is made on the merged activity, so it applies to both
        // members and beats garmin:1's earlier hide.
        let hide = decision("h", .hidden(true), time: 1, on: [ga1])
        let restore = decision("r", .hidden(false), time: 2, on: [ga1, hk1])
        #expect(!DecisionRecord.isHidden([ga1, hk1], among: [hide, restore]))
    }

    @Test func aHideAndARestoreAtTheSameTimeGoToTheHigherDevice() {
        // "phone" > "pad", whichever of the two made the hide.
        let hideOnPhone = decision("h", .hidden(true), time: 100, device: "phone", on: [ga1])
        let restoreOnPad = decision("r", .hidden(false), time: 100, device: "pad", on: [ga1])
        #expect(DecisionRecord.isHidden([ga1], among: [hideOnPhone, restoreOnPad]))
        #expect(DecisionRecord.isHidden([ga1], among: [restoreOnPad, hideOnPhone]))

        let hideOnPad = decision("h", .hidden(true), time: 100, device: "pad", on: [ga1])
        let restoreOnPhone = decision("r", .hidden(false), time: 100, device: "phone", on: [ga1])
        #expect(!DecisionRecord.isHidden([ga1], among: [hideOnPad, restoreOnPhone]))
        #expect(!DecisionRecord.isHidden([ga1], among: [restoreOnPhone, hideOnPad]))
    }

    @Test func aHideOnARecordOutsideTheActivityDoesNotApply() {
        let hide = decision("h", .hidden(true), time: 1, on: [ga2])
        #expect(!DecisionRecord.isHidden([ga1, hk1], among: [hide]))
    }
}

@Suite("The decision in effect for a field")
struct DecisionInEffectTests {
    @Test func noDecisionOnTheFieldMeansNoneInEffect() {
        let title = decision("t", .title("Morning loop"), time: 1, on: [ga1])
        #expect(DecisionRecord.inEffect(.hidden, members: [ga1, hk1], among: [title]) == nil)
        #expect(DecisionRecord.inEffect(.primary, members: [ga1, hk1], among: [title]) == nil)
        #expect(DecisionRecord.inEffect(.title, members: [ga2], among: [title]) == nil)
    }

    @Test func theTitleInEffectIsTheWinnerAmongTheMembersWinners() {
        // garmin:1's winner is t2 (time 3 beats time 1). healthKit:W1's
        // winner is t3 (time 2). Between t2 and t3 the later is t2.
        let t1 = decision("t1", .title("One"), time: 1, on: [ga1])
        let t2 = decision("t2", .title("Two"), time: 3, on: [ga1])
        let t3 = decision("t3", .title("Three"), time: 2, on: [hk1])
        for ordering in permutations([t1, t2, t3]) {
            #expect(DecisionRecord.inEffect(.title, members: [ga1, hk1], among: ordering) == t2)
        }
    }

    @Test func thePrimaryChoiceInEffectIsTheLatest() {
        let p1 = decision("p1", .primary(hk1), time: 1, on: [ga1, hk1])
        let p2 = decision("p2", .primary(ga1), time: 2, on: [ga1, hk1])
        #expect(DecisionRecord.inEffect(.primary, members: [ga1, hk1], among: [p1, p2]) == p2)
    }

    @Test func forAHiddenActivityTheHideIsInEffectEvenIfARestoreIsLater() {
        // garmin:1's winner is the hide at time 5. healthKit:W1's winner is
        // a restore at time 9. The activity is hidden, and what makes it so
        // is the hide.
        let hide = decision("h1", .hidden(true), time: 5, on: [ga1])
        let restore = decision("h2", .hidden(false), time: 9, on: [hk1])
        #expect(DecisionRecord.inEffect(.hidden, members: [ga1, hk1], among: [hide, restore]) == hide)
        #expect(DecisionRecord.inEffect(.hidden, members: [ga1, hk1], among: [restore, hide]) == hide)
    }

    @Test func forAHiddenActivityTheLatestWinningHideIsInEffect() {
        // Both members' winners are hides. The later is at time 7.
        let early = decision("h1", .hidden(true), time: 5, on: [ga1])
        let late = decision("h2", .hidden(true), time: 7, on: [hk1])
        #expect(DecisionRecord.inEffect(.hidden, members: [ga1, hk1], among: [early, late]) == late)
        #expect(DecisionRecord.inEffect(.hidden, members: [ga1, hk1], among: [late, early]) == late)
    }

    @Test func forAVisibleActivityTheWinningRestoreIsInEffect() {
        let hide = decision("h1", .hidden(true), time: 5, on: [ga1])
        let restore = decision("h2", .hidden(false), time: 7, on: [ga1])
        #expect(DecisionRecord.inEffect(.hidden, members: [ga1], among: [hide, restore]) == restore)
    }
}
