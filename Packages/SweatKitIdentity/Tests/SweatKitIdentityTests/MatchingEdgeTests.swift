import Foundation
import SweatKitIdentity
import SweatKitModel
import Testing

/// A record for the match rule. The defaults describe a one-hour, 30 km
/// outdoor ride starting at time 0.
private func candidate(
    _ identity: SourceIdentity,
    sport: Sport = .cycling,
    start: Double = 0,
    elapsed: Double = 3600,
    distance: Double? = 30_000,
    indoor: Bool = false
) -> MatchCandidate {
    MatchCandidate(
        identity: identity,
        sport: sport,
        start: at(start),
        elapsed: elapsed,
        distance: distance,
        isIndoor: indoor
    )
}

/// The outcome both ways round, which must agree.
private func outcomes(_ first: MatchCandidate, _ second: MatchCandidate) -> [MatchOutcome] {
    [MatchOutcome.between(first, second), MatchOutcome.between(second, first)]
}

/// Readings of the match rule that the first set of tests left open. Each
/// expected value is worked out from the spec's wording in the comment.
@Suite("Automatic match rule: edges")
struct MatchRuleEdgeTests {
    @Test func recordsThatPassEveryToleranceMatchEvenWithoutOverlapping() {
        // Two one-minute, 300 m recordings: 0 to 60 and 120 to 180.
        //   sport family: cycling and cycling.
        //   starts: 120 - 0 = 120 s, within 2 minutes.
        //   durations: 60 and 60, 0 apart.
        //   distances: 300 and 300, 0 apart.
        // The spec's list has those four conditions and no fifth about
        // overlap, so all of them hold and the records merge, although the
        // first ends 60 s before the second starts.
        let first = candidate(ga1, start: 0, elapsed: 60, distance: 300)
        let second = candidate(hk1, start: 120, elapsed: 60, distance: 300)
        #expect(outcomes(first, second) == [.sameActivity(.tolerances), .sameActivity(.tolerances)])
    }

    @Test func twoRecordsOfSportOtherAreOneFamily() {
        // `Sport.other.family` is `.other` for both, so "the sport family
        // matches" holds by the literal rule. Everything else is equal.
        let first = candidate(ga1, sport: .other)
        let second = candidate(hk1, sport: .other)
        #expect(outcomes(first, second) == [.sameActivity(.tolerances), .sameActivity(.tolerances)])
    }

    @Test func sportOtherIsNotTheFamilyOfAnyNamedSport() {
        // `.other` against cycling and against the on-foot family. The
        // hours are the same, so each pair overlaps and is flagged.
        let other = candidate(ga1, sport: .other)
        #expect(outcomes(other, candidate(hk1, sport: .cycling)) == [.possibleDuplicate, .possibleDuplicate])
        #expect(outcomes(other, candidate(hk1, sport: .hiking)) == [.possibleDuplicate, .possibleDuplicate])
    }

    @Test func aRecordWithNoElapsedTimeOverlapsNothing() {
        // The ride covers 0 to 3600. The other record starts at 1800 and
        // lasts 0 s. Starts are 1800 s apart, so the rule fails. Its
        // half-open span from 1800 to 1800 holds no time at all, so the two
        // share none and are not flagged.
        let ride = candidate(ga1)
        let instant = candidate(hk1, start: 1800, elapsed: 0, distance: 0)
        #expect(outcomes(ride, instant) == [.unrelated, .unrelated])
    }

    @Test func theStartOfOneRecordInsideTheOtherIsEnoughToOverlap() {
        // 0 to 3600 and 3000 to 10 200 share 3000 to 3600. Starts are
        // 3000 s apart, so the rule fails and the pair is flagged.
        let ride = candidate(ga1)
        let longer = candidate(hk1, start: 3000, elapsed: 7200, distance: 60_000)
        #expect(outcomes(ride, longer) == [.possibleDuplicate, .possibleDuplicate])
    }
}

@Suite("Scanning records for matches: edges")
struct MatchScanEdgeTests {
    private let phone = DeviceID("phone")

    @Test func aRecordIsNotComparedWithItself() {
        // A link joins two source records. One identity given twice is one
        // source record, so there is no pair to link or to flag.
        let ride = candidate(ga1)
        let scan = MatchScan.scan([ride, ride], at: at(400), device: phone)
        #expect(scan == MatchScan(links: [], possibleDuplicates: []))
    }

    @Test func anIdentityGivenTwiceStillWritesOneLinkPerPair() {
        // garmin:1 twice and healthKit:W1 once: one pair, one link.
        let ride = candidate(ga1)
        let workout = candidate(hk1, start: 30)
        let scan = MatchScan.scan([ride, workout, ride], at: at(400), device: phone)
        #expect(scan == MatchScan(links: [autoLink(ga1, hk1, time: 400)], possibleDuplicates: []))
    }

    @Test func aLargerScanDoesNotDependOnTheOrderOfTheRecords() {
        // Six records.
        //   garmin:1      0 to 3600, 30 000 m   } one ride: starts 60 s
        //   healthKit:W1  60 to 3660, 30 300 m  } apart, durations equal,
        //                                         300 m apart against 5% of
        //                                         30 300 = 1515 m.
        //   file:f1       900 to 1500, 4000 m: inside both of the above.
        //     Its start is 900 s and 840 s from theirs, so it fails against
        //     each and, overlapping each, is flagged against each.
        //   garmin:2      50 000 to 53 600, 30 000 m } one ride: starts
        //   healthKit:W2  50 100 to 53 520, 29 000 m } 100 s apart;
        //     durations 3600 and 3420, 180 apart = 5% of 3600 exactly;
        //     distances 1000 m apart against 5% of 30 000 = 1500 m.
        //   garmin:3      53 500 to 57 100: overlaps garmin:2 (to 53 600)
        //     and healthKit:W2 (to 53 520). Starts are 3500 s and 3400 s
        //     from theirs, so both pairs fail and are flagged.
        // Nothing in the first three overlaps anything in the last three.
        let ga3 = SourceIdentity(source: .garmin, externalID: "3")
        let records = [
            candidate(ga1, start: 0, elapsed: 3600, distance: 30_000),
            candidate(hk1, start: 60, elapsed: 3600, distance: 30_300),
            candidate(fi1, start: 900, elapsed: 600, distance: 4000),
            candidate(ga2, start: 50_000, elapsed: 3600, distance: 30_000),
            candidate(hk2, start: 50_100, elapsed: 3420, distance: 29_000),
            candidate(ga3, start: 53_500, elapsed: 3600, distance: 30_000),
        ]
        let expected = MatchScan(
            // By name: "...|garmin:1|healthKit:W1" < "...|garmin:2|healthKit:W2".
            links: [autoLink(ga1, hk1, time: 400), autoLink(ga2, hk2, time: 400)],
            // By lower identity, then upper:
            //   file:f1 + garmin:1, file:f1 + healthKit:W1,
            //   garmin:2 + garmin:3, garmin:3 + healthKit:W2.
            possibleDuplicates: [
                IdentityPair(fi1, ga1),
                IdentityPair(fi1, hk1),
                IdentityPair(ga2, ga3),
                IdentityPair(ga3, hk2),
            ]
        )
        #expect(MatchScan.scan(records, at: at(400), device: phone) == expected)

        // 6 records have 720 orderings. 200 seeded shuffles of them.
        var generator = SeededGenerator(seed: 4_112_026)
        for _ in 0..<200 {
            let shuffled = records.shuffled(using: &generator)
            #expect(MatchScan.scan(shuffled, at: at(400), device: phone) == expected)
        }
    }
}

/// "Records that overlap in time but fail the test stay separate and are
/// flagged as possible duplicates. The user merges them or keeps both."
@Suite("Possible duplicates the user has dealt with")
struct AwaitingReviewTests {
    // file:f1 is flagged against garmin:1 and against healthKit:W1.
    private let scan = MatchScan(
        links: [autoLink(ga1, hk1, time: 400)],
        possibleDuplicates: [IdentityPair(fi1, ga1), IdentityPair(fi1, hk1)]
    )

    @Test func withNoUserLinksEveryFlaggedPairAwaitsReview() {
        #expect(scan.awaitingReview(given: [LinkRecord]()) == [IdentityPair(fi1, ga1), IdentityPair(fi1, hk1)])
        // The scan's own automatic link is on another pair.
        #expect(scan.awaitingReview(given: scan.links) == [IdentityPair(fi1, ga1), IdentityPair(fi1, hk1)])
    }

    @Test func keepingBothClearsTheFlagOnThatPair() {
        let keepBoth = userLink("keep", ga1, fi1, .keepSeparate, time: 500)
        #expect(scan.awaitingReview(given: [keepBoth]) == [IdentityPair(fi1, hk1)])
    }

    @Test func mergingClearsTheFlagOnThatPair() {
        let merge = userLink("merge", fi1, hk1, .sameActivity, time: 500)
        #expect(scan.awaitingReview(given: [merge]) == [IdentityPair(fi1, ga1)])
    }

    @Test func dealingWithEveryPairLeavesNothingToReview() {
        let keepBoth = userLink("keep", ga1, fi1, .keepSeparate, time: 500)
        let merge = userLink("merge", fi1, hk1, .sameActivity, time: 600)
        #expect(scan.awaitingReview(given: [merge, keepBoth]).isEmpty)
    }

    @Test func aUserLinkOnAnotherPairClearsNothing() {
        let other = userLink("other", ga2, fi1, .keepSeparate, time: 500)
        #expect(scan.awaitingReview(given: [other]) == [IdentityPair(fi1, ga1), IdentityPair(fi1, hk1)])
    }

    @Test func anAutomaticLinkOnTheFlaggedPairIsNotTheUsersDecision() {
        // It is the user who merges them or keeps both.
        let automatic = autoLink(fi1, ga1, time: 500)
        #expect(scan.awaitingReview(given: [automatic]) == [IdentityPair(fi1, ga1), IdentityPair(fi1, hk1)])
    }
}
