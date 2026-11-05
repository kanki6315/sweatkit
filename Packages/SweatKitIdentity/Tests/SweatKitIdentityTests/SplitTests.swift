import Foundation
import SweatKitIdentity
import SweatKitModel
import Testing

/// An inherited copy, spelled out by hand.
private func copy(
    _ name: String,
    _ value: DecisionValue,
    time: Double,
    device: String,
    on members: Set<SourceIdentity>
) -> DecisionRecord {
    decision(name, value, time: time, device: device, on: members, origin: .inheritedCopy)
}

@Suite("Inherited copies written by a split")
struct InheritedCopyTests {
    private let both: Set<SourceIdentity> = [ga1, hk1]

    @Test func aCopyIsNamedFromTheOriginalAndThePartsMembers() {
        // <original>|copy|<members ascending, joined by commas>.
        #expect(Split.copyName(of: RecordName("t1"), part: [ga1]) == RecordName("t1|copy|garmin:1"))
        // garmin:1 < healthKit:W1.
        #expect(Split.copyName(of: RecordName("t1"), part: [hk1, ga1]) == RecordName("t1|copy|garmin:1,healthKit:W1"))
    }

    @Test func aSplitCopiesTheDecisionInEffectOnceForEachPart() {
        // The title was made on the phone at time 100. The pad splits the
        // activity. Each copy keeps the value and the time 100, applies to
        // its part's members, is marked as a copy and records the pad.
        // Ordered by name: "t1|copy|garmin:1" < "t1|copy|healthKit:W1".
        let title = decision("t1", .title("Morning loop"), time: 100, device: "phone", on: both)
        let copies = Split.inheritedCopies(
            splitting: both,
            into: [[ga1], [hk1]],
            decisions: [title],
            device: DeviceID("pad")
        )
        #expect(copies == [
            copy("t1|copy|garmin:1", .title("Morning loop"), time: 100, device: "pad", on: [ga1]),
            copy("t1|copy|healthKit:W1", .title("Morning loop"), time: 100, device: "pad", on: [hk1]),
        ])
    }

    @Test func aCopyKeepsTheOriginalDecisionsTime() {
        let title = decision("t1", .title("Morning loop"), time: 100, device: "phone", on: both)
        let copies = Split.inheritedCopies(
            splitting: both,
            into: [[ga1], [hk1]],
            decisions: [title],
            device: DeviceID("pad")
        )
        #expect(copies.map(\.time) == [at(100), at(100)])
        #expect(copies.map(\.origin) == [.inheritedCopy, .inheritedCopy])
    }

    @Test func aSplitWithNoDecisionsWritesNoCopies() {
        let copies = Split.inheritedCopies(
            splitting: both,
            into: [[ga1], [hk1]],
            decisions: [DecisionRecord](),
            device: DeviceID("pad")
        )
        #expect(copies.isEmpty)
    }

    @Test func onlyTheDecisionInEffectIsCopied() {
        // The title at time 200 replaced the one at time 100. Only it is in
        // effect, so only it is copied.
        let old = decision("t1", .title("Morning loop"), time: 100, on: both)
        let new = decision("t2", .title("Commute"), time: 200, on: both)
        let expected = [
            copy("t2|copy|garmin:1", .title("Commute"), time: 200, device: "pad", on: [ga1]),
            copy("t2|copy|healthKit:W1", .title("Commute"), time: 200, device: "pad", on: [hk1]),
        ]
        for ordering in permutations([old, new]) {
            let copies = Split.inheritedCopies(
                splitting: both,
                into: [[ga1], [hk1]],
                decisions: ordering,
                device: DeviceID("pad")
            )
            #expect(copies == expected)
        }
    }

    @Test func everyFieldWithADecisionInEffectIsCopied() {
        // A title, a hide and a primary choice: three decisions in effect,
        // two parts, six copies. In name order "h1..." < "p1..." < "t1...",
        // and within each "...garmin:1" < "...healthKit:W1".
        let title = decision("t1", .title("Morning loop"), time: 100, on: both)
        let hide = decision("h1", .hidden(true), time: 150, on: both)
        let primary = decision("p1", .primary(hk1), time: 120, on: both)
        let expected = [
            copy("h1|copy|garmin:1", .hidden(true), time: 150, device: "pad", on: [ga1]),
            copy("h1|copy|healthKit:W1", .hidden(true), time: 150, device: "pad", on: [hk1]),
            copy("p1|copy|garmin:1", .primary(hk1), time: 120, device: "pad", on: [ga1]),
            copy("p1|copy|healthKit:W1", .primary(hk1), time: 120, device: "pad", on: [hk1]),
            copy("t1|copy|garmin:1", .title("Morning loop"), time: 100, device: "pad", on: [ga1]),
            copy("t1|copy|healthKit:W1", .title("Morning loop"), time: 100, device: "pad", on: [hk1]),
        ]
        // 3 decisions, 6 orderings, and the parts either way round.
        for ordering in permutations([title, hide, primary]) {
            for parts in permutations([Set([ga1]), Set([hk1])]) {
                let copies = Split.inheritedCopies(
                    splitting: both,
                    into: parts,
                    decisions: ordering,
                    device: DeviceID("pad")
                )
                #expect(copies == expected)
            }
        }
    }

    @Test func aDecisionMadeOnOneMemberBeforeAMergeIsCopiedToEveryPart() {
        // The title was made on garmin:1 alone. After the merge it is the
        // activity's title, so the split copies it to the healthKit:W1 part
        // too.
        let title = decision("t1", .title("Morning loop"), time: 100, on: [ga1])
        let copies = Split.inheritedCopies(
            splitting: both,
            into: [[ga1], [hk1]],
            decisions: [title],
            device: DeviceID("phone")
        )
        #expect(copies == [
            copy("t1|copy|garmin:1", .title("Morning loop"), time: 100, device: "phone", on: [ga1]),
            copy("t1|copy|healthKit:W1", .title("Morning loop"), time: 100, device: "phone", on: [hk1]),
        ])
    }

    @Test func aPartOfSeveralMembersGetsOneCopyForAllOfThem() {
        // {garmin:1, garmin:2, healthKit:W1} splits into
        // {garmin:1, healthKit:W1} and {garmin:2}.
        // "t1|copy|garmin:1,healthKit:W1" < "t1|copy|garmin:2" because the
        // names first differ at "1" against "2".
        let all: Set<SourceIdentity> = [ga1, ga2, hk1]
        let title = decision("t1", .title("Morning loop"), time: 100, on: all)
        let copies = Split.inheritedCopies(
            splitting: all,
            into: [[ga2], [hk1, ga1]],
            decisions: [title],
            device: DeviceID("pad")
        )
        #expect(copies == [
            copy("t1|copy|garmin:1,healthKit:W1", .title("Morning loop"), time: 100, device: "pad", on: [ga1, hk1]),
            copy("t1|copy|garmin:2", .title("Morning loop"), time: 100, device: "pad", on: [ga2]),
        ])
    }

    @Test func forAHiddenActivityTheHideIsWhatIsCopied() {
        // garmin:1's winner is a hide at time 5, healthKit:W1's a restore at
        // time 9. The activity is hidden, so the hide is in effect and is
        // copied to both parts. The restore is not copied.
        let hide = decision("h1", .hidden(true), time: 5, device: "phone", on: [ga1])
        let restore = decision("h2", .hidden(false), time: 9, device: "pad", on: [hk1])
        let copies = Split.inheritedCopies(
            splitting: both,
            into: [[ga1], [hk1]],
            decisions: [restore, hide],
            device: DeviceID("pad")
        )
        #expect(copies == [
            copy("h1|copy|garmin:1", .hidden(true), time: 5, device: "pad", on: [ga1]),
            copy("h1|copy|healthKit:W1", .hidden(true), time: 5, device: "pad", on: [hk1]),
        ])
    }

    @Test func decisionsAboutOtherActivitiesAreNotCopied() {
        let other = decision("t9", .title("Someone else"), time: 100, on: [ga2])
        let copies = Split.inheritedCopies(
            splitting: both,
            into: [[ga1], [hk1]],
            decisions: [other],
            device: DeviceID("pad")
        )
        #expect(copies.isEmpty)
    }
}

/// How the parts of a split resolve. The copies here are written out by
/// hand, so these tests stand on the resolution rules alone.
@Suite("Decisions after a split")
struct SplitResolutionTests {
    private let both: Set<SourceIdentity> = [ga1, hk1]

    // The phone titled the activity "Morning loop" at time 100 and split it
    // at time 300. The copies keep time 100.
    private let title = decision("t1", .title("Morning loop"), time: 100, device: "phone", on: [ga1, hk1])
    private let titleCopies = [
        copy("t1|copy|garmin:1", .title("Morning loop"), time: 100, device: "phone", on: [ga1]),
        copy("t1|copy|healthKit:W1", .title("Morning loop"), time: 100, device: "phone", on: [hk1]),
    ]

    @Test func eachPartOfASplitKeepsTheTitle() {
        let records = [title] + titleCopies
        #expect(DecisionRecord.title(of: [ga1], among: records) == "Morning loop")
        #expect(DecisionRecord.title(of: [hk1], among: records) == "Morning loop")
    }

    @Test func aPartTheOriginalNeverAppliedToGetsTheTitleFromItsCopy() {
        // The title was made on garmin:1 alone, before the merge. Without
        // the copy, healthKit:W1 would have no title after the split.
        let onOne = decision("t1", .title("Morning loop"), time: 100, on: [ga1])
        #expect(DecisionRecord.title(of: [hk1], among: [onOne]) == nil)
        #expect(DecisionRecord.title(of: [hk1], among: [onOne] + titleCopies) == "Morning loop")
        #expect(DecisionRecord.title(of: [ga1], among: [onOne] + titleCopies) == "Morning loop")
    }

    @Test func anOfflineRenameMadeBeforeTheSplitStillWinsOnEveryPart() {
        // The pad, offline, renamed the activity at time 200: after the
        // original (100) and before the split (300). A copy is not a new
        // decision and keeps time 100, so the rename at 200 wins on both
        // parts. Had the copies taken the split's time, they would have won.
        let rename = decision("t2", .title("Commute"), time: 200, device: "pad", on: both)
        for ordering in permutations([title, rename] + titleCopies) {
            #expect(DecisionRecord.title(of: [ga1], among: ordering) == "Commute")
            #expect(DecisionRecord.title(of: [hk1], among: ordering) == "Commute")
        }
    }

    @Test func anOfflineRenameMadeAfterTheSplitWinsOnEveryPartItAppliesTo() {
        // The pad had not seen the split, so its rename at time 400 applies
        // to both old members.
        let rename = decision("t2", .title("Commute"), time: 400, device: "pad", on: both)
        for ordering in permutations([title, rename] + titleCopies) {
            #expect(DecisionRecord.title(of: [ga1], among: ordering) == "Commute")
            #expect(DecisionRecord.title(of: [hk1], among: ordering) == "Commute")
        }
    }

    @Test func aRenameOlderThanTheOriginalDoesNotWin() {
        // A stale rename from time 50 loses to the title at 100 and to its
        // copies.
        let stale = decision("t0", .title("Old name"), time: 50, device: "pad", on: both)
        for ordering in permutations([title, stale] + titleCopies) {
            #expect(DecisionRecord.title(of: [ga1], among: ordering) == "Morning loop")
            #expect(DecisionRecord.title(of: [hk1], among: ordering) == "Morning loop")
        }
    }

    @Test func anOfflineHideWinsOnEveryPartItAppliesTo() {
        // The same split, with a hide in place of the rename. The activity
        // was visible. The pad, offline, hid it at time 200. The hide
        // applies to both old members, so both parts are hidden.
        let hide = decision("h1", .hidden(true), time: 200, device: "pad", on: both)
        for ordering in permutations([title, hide] + titleCopies) {
            #expect(DecisionRecord.isHidden([ga1], among: ordering))
            #expect(DecisionRecord.isHidden([hk1], among: ordering))
            #expect(DecisionRecord.title(of: [ga1], among: ordering) == "Morning loop")
            #expect(DecisionRecord.title(of: [hk1], among: ordering) == "Morning loop")
        }
    }

    @Test func aHiddenActivityThatIsSplitLeavesEveryPartHidden() {
        // garmin:1 was hidden on its own at time 100, then merged with the
        // visible healthKit:W1, which made the activity hidden. The split
        // copies the hide to each part, so healthKit:W1 stays hidden though
        // the original never applied to it.
        let hide = decision("h1", .hidden(true), time: 100, on: [ga1])
        let copies = [
            copy("h1|copy|garmin:1", .hidden(true), time: 100, device: "phone", on: [ga1]),
            copy("h1|copy|healthKit:W1", .hidden(true), time: 100, device: "phone", on: [hk1]),
        ]
        #expect(!DecisionRecord.isHidden([hk1], among: [hide]))
        for ordering in permutations([hide] + copies) {
            #expect(DecisionRecord.isHidden([ga1], among: ordering))
            #expect(DecisionRecord.isHidden([hk1], among: ordering))
        }
    }

    @Test func anOfflineRestoreLaterThanTheHideShowsEveryPart() {
        // The activity was hidden at time 100 and split at 300. The pad,
        // offline, restored it at time 200. 200 > 100, so the restore beats
        // the hide and both copies.
        let hide = decision("h1", .hidden(true), time: 100, on: both)
        let copies = [
            copy("h1|copy|garmin:1", .hidden(true), time: 100, device: "phone", on: [ga1]),
            copy("h1|copy|healthKit:W1", .hidden(true), time: 100, device: "phone", on: [hk1]),
        ]
        let restore = decision("r1", .hidden(false), time: 200, device: "pad", on: both)
        for ordering in permutations([hide, restore] + copies) {
            #expect(!DecisionRecord.isHidden([ga1], among: ordering))
            #expect(!DecisionRecord.isHidden([hk1], among: ordering))
        }
    }

    @Test func aPartsOwnLaterRestoreBeatsTheCopiedHide() {
        // garmin:1 was hidden at time 5. healthKit:W1 was restored at time 9
        // on its own. Merged, the activity is hidden. After the split,
        // healthKit:W1 has its restore at 9 and the copied hide at 5, so it
        // is visible again. garmin:1 stays hidden.
        let hide = decision("h1", .hidden(true), time: 5, on: [ga1])
        let restore = decision("h2", .hidden(false), time: 9, on: [hk1])
        let copies = [
            copy("h1|copy|garmin:1", .hidden(true), time: 5, device: "phone", on: [ga1]),
            copy("h1|copy|healthKit:W1", .hidden(true), time: 5, device: "phone", on: [hk1]),
        ]
        let records = [hide, restore] + copies
        #expect(DecisionRecord.isHidden([ga1, hk1], among: [hide, restore]))
        #expect(DecisionRecord.isHidden([ga1], among: records))
        #expect(!DecisionRecord.isHidden([hk1], among: records))
    }

    @Test func aCopiedPrimaryChoiceFallsBackToTheDefaultOnThePartThatLostIt() {
        // healthKit:W1 was the chosen primary of {garmin:1, garmin:2,
        // healthKit:W1}. The split leaves {garmin:1, garmin:2} and
        // {healthKit:W1}. On the first part the chosen primary is no longer
        // a member, so the default applies: garmin:1.
        let all: Set<SourceIdentity> = [ga1, ga2, hk1]
        let choice = decision("p1", .primary(hk1), time: 100, on: all)
        let copies = [
            copy("p1|copy|garmin:1,garmin:2", .primary(hk1), time: 100, device: "phone", on: [ga1, ga2]),
            copy("p1|copy|healthKit:W1", .primary(hk1), time: 100, device: "phone", on: [hk1]),
        ]
        let records = [choice] + copies
        #expect(PrimaryChoice.primary(of: [ga1, ga2], among: records) == ga1)
        #expect(PrimaryChoice.primary(of: [hk1], among: records) == hk1)
    }
}
