import Foundation
import SweatKitIdentity
import SweatKitModel
import Testing

@Suite("Tombstones")
struct TombstoneTests {
    private func standing(
        _ tombstones: [Tombstone],
        _ decisions: [DecisionRecord] = [],
        of identity: SourceIdentity = ga1
    ) -> IdentityStanding {
        Tombstone.standing(of: identity, tombstones: tombstones, decisions: decisions)
    }

    // MARK: Writing

    @Test func deletingAnActivityWritesATombstoneForEveryMembersIdentity() {
        // Ordered by identity: garmin:1 < healthKit:W1.
        let written = Tombstone.written(.deleted, for: [hk1, ga1], at: at(10))
        #expect(written == [
            Tombstone(identity: ga1, kind: .deleted, time: at(10)),
            Tombstone(identity: hk1, kind: .deleted, time: at(10)),
        ])
    }

    @Test func hidingAnActivityWritesATombstoneForEveryMembersIdentity() {
        let written = Tombstone.written(.hidden, for: [hk1, ga1, fi1], at: at(20))
        #expect(written == [
            Tombstone(identity: fi1, kind: .hidden, time: at(20)),
            Tombstone(identity: ga1, kind: .hidden, time: at(20)),
            Tombstone(identity: hk1, kind: .hidden, time: at(20)),
        ])
    }

    @Test func noMembersWriteNoTombstones() {
        #expect(Tombstone.written(.deleted, for: [], at: at(10)).isEmpty)
    }

    // MARK: Standing

    @Test func anIdentityWithNoTombstoneIsLive() {
        #expect(standing([]) == .live)
    }

    @Test func aTombstoneForAnotherIdentityDoesNotCount() {
        let other = Tombstone(identity: ga2, kind: .deleted, time: at(10))
        #expect(standing([other]) == .live)
    }

    @Test func aHideDecisionWithoutATombstoneLeavesTheIdentityLive() {
        // Hidden state from decisions is worked out by the decision rule.
        // Standing reads tombstones.
        let hide = decision("h", .hidden(true), time: 10, on: [ga1])
        #expect(standing([], [hide]) == .live)
    }

    @Test func aDeletedTombstoneMakesTheIdentityDeleted() {
        #expect(standing([Tombstone(identity: ga1, kind: .deleted, time: at(10))]) == .deleted)
    }

    @Test func aHiddenTombstoneMakesTheIdentityHidden() {
        #expect(standing([Tombstone(identity: ga1, kind: .hidden, time: at(10))]) == .hidden)
    }

    @Test func aRestoreMadeAfterTheTombstoneReversesAHide() {
        // 11 > 10.
        let tombstone = Tombstone(identity: ga1, kind: .hidden, time: at(10))
        let restore = decision("r", .hidden(false), time: 11, on: [ga1])
        #expect(standing([tombstone], [restore]) == .live)
    }

    @Test func aRestoreMadeBeforeTheTombstoneDoesNotReverseAHide() {
        // A stale restore from time 9, before the hide at 10.
        let tombstone = Tombstone(identity: ga1, kind: .hidden, time: at(10))
        let restore = decision("r", .hidden(false), time: 9, on: [ga1])
        #expect(standing([tombstone], [restore]) == .hidden)
    }

    @Test func aRestoreAtTheSameTimeAsTheTombstoneDoesNotReverseAHide() {
        // "After" is strictly later. 10 is not after 10.
        let tombstone = Tombstone(identity: ga1, kind: .hidden, time: at(10))
        let restore = decision("r", .hidden(false), time: 10, device: "z", on: [ga1])
        #expect(standing([tombstone], [restore]) == .hidden)
    }

    @Test func aRestoreThatDoesNotApplyToTheIdentityDoesNotReverseItsHide() {
        let tombstone = Tombstone(identity: ga1, kind: .hidden, time: at(10))
        let restore = decision("r", .hidden(false), time: 11, on: [hk1])
        #expect(standing([tombstone], [restore]) == .hidden)
    }

    @Test func aRestoreMadeOnTheWholeActivityReversesEveryMembersHide() {
        let tombstones = Tombstone.written(.hidden, for: [ga1, hk1], at: at(10))
        let restore = decision("r", .hidden(false), time: 11, on: [ga1, hk1])
        #expect(standing(tombstones, [restore], of: ga1) == .live)
        #expect(standing(tombstones, [restore], of: hk1) == .live)
    }

    @Test func onlyARestoreReversesAHide() {
        // A later hide, title or primary choice is not a restore.
        let tombstone = Tombstone(identity: ga1, kind: .hidden, time: at(10))
        let later = [
            decision("h", .hidden(true), time: 11, on: [ga1]),
            decision("t", .title("Morning loop"), time: 12, on: [ga1]),
            decision("p", .primary(ga1), time: 13, on: [ga1]),
        ]
        #expect(standing([tombstone], later) == .hidden)
    }

    @Test func aRestoreMustComeAfterTheLatestHide() {
        // Hidden at 10, restored at 15, hidden again at 20. The restore is
        // after the first tombstone but not the second.
        let first = Tombstone(identity: ga1, kind: .hidden, time: at(10))
        let second = Tombstone(identity: ga1, kind: .hidden, time: at(20))
        let between = decision("r1", .hidden(false), time: 15, on: [ga1])
        #expect(standing([first], [between]) == .live)
        #expect(standing([first, second], [between]) == .hidden)
        #expect(standing([second, first], [between]) == .hidden)
        // A second restore at 25 is after both.
        let after = decision("r2", .hidden(false), time: 25, on: [ga1])
        #expect(standing([first, second], [between, after]) == .live)
    }

    // MARK: Deletion wins

    @Test func aPermanentDeleteIsNeverReversed() {
        // Deletion wins over stale updates. A restore, a rename and a hide,
        // all later than the tombstone, change nothing.
        let tombstone = Tombstone(identity: ga1, kind: .deleted, time: at(10))
        let later = [
            decision("r", .hidden(false), time: 99, on: [ga1]),
            decision("t", .title("Still here"), time: 99, on: [ga1]),
            decision("h", .hidden(true), time: 99, on: [ga1]),
        ]
        for ordering in permutations(later) {
            #expect(standing([tombstone], ordering) == .deleted)
        }
    }

    @Test func deletedBeatsHiddenWhicheverCameFirst() {
        let hidden = Tombstone(identity: ga1, kind: .hidden, time: at(20))
        let deleted = Tombstone(identity: ga1, kind: .deleted, time: at(10))
        let restore = decision("r", .hidden(false), time: 30, on: [ga1])
        #expect(standing([hidden, deleted]) == .deleted)
        #expect(standing([deleted, hidden]) == .deleted)
        #expect(standing([deleted, hidden], [restore]) == .deleted)
    }

    @Test func standingDoesNotDependOnTheOrderOfTheRecords() {
        // Hides at 10 and 20, restores at 15 and 18. Neither restore is
        // after 20, so the identity is hidden.
        let tombstones = [
            Tombstone(identity: ga1, kind: .hidden, time: at(10)),
            Tombstone(identity: ga1, kind: .hidden, time: at(20)),
            Tombstone(identity: hk1, kind: .deleted, time: at(5)),
        ]
        let decisions = [
            decision("r1", .hidden(false), time: 15, on: [ga1]),
            decision("r2", .hidden(false), time: 18, on: [ga1, hk1]),
            decision("h1", .hidden(true), time: 20, on: [ga1]),
        ]
        for tombstoneOrder in permutations(tombstones) {
            for decisionOrder in permutations(decisions) {
                #expect(standing(tombstoneOrder, decisionOrder, of: ga1) == .hidden)
                #expect(standing(tombstoneOrder, decisionOrder, of: hk1) == .deleted)
                #expect(standing(tombstoneOrder, decisionOrder, of: ga2) == .live)
            }
        }
    }

    // MARK: Surviving records

    @Test func aDeletedIdentityDoesNotSurvive() {
        // The next sync offers garmin:1 again. Its tombstone drops it.
        let tombstone = Tombstone(identity: ga1, kind: .deleted, time: at(10))
        #expect(Tombstone.surviving([ga1, ga2, hk1], tombstones: [tombstone]) == [ga2, hk1])
    }

    @Test func aHiddenIdentitySurvives() {
        // Hiding keeps all stored data, so the record stays.
        let tombstone = Tombstone(identity: ga1, kind: .hidden, time: at(10))
        #expect(Tombstone.surviving([ga1, hk1], tombstones: [tombstone]) == [ga1, hk1])
    }

    @Test func withNoTombstonesEveryRecordSurvives() {
        #expect(Tombstone.surviving([ga1, hk1], tombstones: [Tombstone]()) == [ga1, hk1])
    }

    @Test func aTombstoneForARecordThatIsNotThereChangesNothing() {
        let tombstone = Tombstone(identity: ga2, kind: .deleted, time: at(10))
        #expect(Tombstone.surviving([ga1, hk1], tombstones: [tombstone]) == [ga1, hk1])
    }
}
