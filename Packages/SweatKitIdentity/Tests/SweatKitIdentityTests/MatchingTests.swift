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
    indoor: Bool = false,
    linked: Set<SourceIdentity> = []
) -> MatchCandidate {
    MatchCandidate(
        identity: identity,
        sport: sport,
        start: at(start),
        elapsed: elapsed,
        distance: distance,
        isIndoor: indoor,
        linkedIdentities: linked
    )
}

/// The outcome both ways round, which must agree.
private func outcomes(_ first: MatchCandidate, _ second: MatchCandidate) -> [MatchOutcome] {
    [MatchOutcome.between(first, second), MatchOutcome.between(second, first)]
}

private let matched: [MatchOutcome] = [.sameActivity(.tolerances), .sameActivity(.tolerances)]
private let flagged: [MatchOutcome] = [.possibleDuplicate, .possibleDuplicate]
private let unrelated: [MatchOutcome] = [.unrelated, .unrelated]

@Suite("Automatic match rule")
struct MatchRuleTests {
    @Test func standardTolerancesAreTheSpecsStartingValues() {
        // 2 minutes = 2 x 60 = 120 s. 5% = 0.05.
        #expect(MatchTolerances.standard.startDifference == 120)
        #expect(MatchTolerances.standard.durationFraction == 0.05)
        #expect(MatchTolerances.standard.distanceFraction == 0.05)
    }

    @Test func recordsThatAgreeOnEverythingMatch() {
        #expect(outcomes(candidate(ga1), candidate(hk1)) == matched)
    }

    // MARK: Sport family

    @Test func differentSportFamiliesDoNotMatch() {
        // Cycling against the on-foot family. Same hour, so they overlap and
        // are flagged.
        #expect(outcomes(candidate(ga1), candidate(hk1, sport: .walking)) == flagged)
    }

    @Test func aWalkAndAHikeAreTheSameFamily() {
        // Walking, running and hiking are all on foot.
        let walk = candidate(ga1, sport: .walking)
        #expect(outcomes(walk, candidate(hk1, sport: .hiking)) == matched)
        #expect(outcomes(walk, candidate(hk1, sport: .running)) == matched)
    }

    // MARK: Start time

    @Test func startsExactlyTwoMinutesApartMatch() {
        // 120 - 0 = 120 s, which is within 2 minutes.
        #expect(outcomes(candidate(ga1), candidate(hk1, start: 120)) == matched)
    }

    @Test func startsMoreThanTwoMinutesApartDoNotMatch() {
        // 121 s > 120 s. The hours still overlap, so the pair is flagged.
        #expect(outcomes(candidate(ga1), candidate(hk1, start: 121)) == flagged)
    }

    @Test func theStartDifferenceIsTakenInEitherDirection() {
        // 1000 - 880 = 120 s with the second record the earlier one.
        #expect(outcomes(candidate(ga1, start: 1000), candidate(hk1, start: 880)) == matched)
        // 1000 - 879 = 121 s.
        #expect(outcomes(candidate(ga1, start: 1000), candidate(hk1, start: 879)) == flagged)
    }

    // MARK: Elapsed duration

    @Test func durationsExactlyFivePercentApartMatch() {
        // 2000 - 1900 = 100 s, and 5% of the longer, 2000 s, is 100 s.
        // This also pins "of the longer": 5% of the shorter is 95 s.
        #expect(outcomes(candidate(ga1, elapsed: 2000), candidate(hk1, elapsed: 1900)) == matched)
    }

    @Test func durationsMoreThanFivePercentApartDoNotMatch() {
        // 2000 - 1899 = 101 s > 100 s. Both start at 0, so they overlap.
        #expect(outcomes(candidate(ga1, elapsed: 2000), candidate(hk1, elapsed: 1899)) == flagged)
    }

    // MARK: Distance

    @Test func outdoorDistancesExactlyFivePercentApartMatch() {
        // 40 000 - 38 000 = 2000 m, and 5% of the longer, 40 000 m, is 2000 m.
        #expect(outcomes(candidate(ga1, distance: 40_000), candidate(hk1, distance: 38_000)) == matched)
    }

    @Test func outdoorDistancesMoreThanFivePercentApartDoNotMatch() {
        // 40 000 - 37 999 = 2001 m > 2000 m.
        #expect(outcomes(candidate(ga1, distance: 40_000), candidate(hk1, distance: 37_999)) == flagged)
    }

    @Test func indoorDistancesAreNotCompared() {
        // 40 km against 20 km is 50% apart, but both records are indoor.
        let trainer = candidate(ga1, distance: 40_000, indoor: true)
        let watch = candidate(hk1, distance: 20_000, indoor: true)
        #expect(outcomes(trainer, watch) == matched)
    }

    @Test func distanceIsNotComparedWhenEitherRecordIsIndoor() {
        // The distance test is for outdoor activities only, read as both
        // records outdoor. One indoor record is enough to skip it.
        let trainer = candidate(ga1, distance: 40_000, indoor: true)
        let watch = candidate(hk1, distance: 20_000, indoor: false)
        #expect(outcomes(trainer, watch) == matched)
    }

    @Test func aMissingOutdoorDistanceFailsTheRule() {
        // Missing is never zero, so a missing distance cannot be within 5%.
        #expect(outcomes(candidate(ga1), candidate(hk1, distance: nil)) == flagged)
    }

    @Test func twoMissingOutdoorDistancesFailTheRule() {
        #expect(outcomes(candidate(ga1, distance: nil), candidate(hk1, distance: nil)) == flagged)
    }

    @Test func aMissingIndoorDistanceDoesNotMatter() {
        let trainer = candidate(ga1, distance: nil, indoor: true)
        let watch = candidate(hk1, distance: 20_000, indoor: true)
        #expect(outcomes(trainer, watch) == matched)
    }

    // MARK: Source identifier

    @Test func aSourceIdentifierSettlesTheMatchOnItsOwn() {
        // Different family, an hour apart, a third of the length and no
        // distance: every tolerance fails. The Health workout names the
        // Garmin activity, which is enough.
        let ride = candidate(ga1)
        let workout = candidate(hk1, sport: .walking, start: 7200, elapsed: 1200, distance: nil, linked: [ga1])
        #expect(MatchOutcome.between(ride, workout) == .sameActivity(.sourceIdentifier))
        #expect(MatchOutcome.between(workout, ride) == .sameActivity(.sourceIdentifier))
    }

    @Test func aSourceIdentifierOnEitherRecordCounts() {
        let ride = candidate(ga1, linked: [hk1])
        let workout = candidate(hk1, start: 7200)
        #expect(MatchOutcome.between(ride, workout) == .sameActivity(.sourceIdentifier))
        #expect(MatchOutcome.between(workout, ride) == .sameActivity(.sourceIdentifier))
    }

    @Test func aSourceIdentifierIsTheBasisEvenWhenTheTolerancesAgree() {
        let ride = candidate(ga1)
        let workout = candidate(hk1, linked: [ga1])
        #expect(MatchOutcome.between(ride, workout) == .sameActivity(.sourceIdentifier))
    }

    @Test func aSourceIdentifierNamingAThirdRecordSettlesNothing() {
        // The workout names garmin:2, not garmin:1. The pair is judged on
        // the tolerances and fails on the start: 121 s.
        let ride = candidate(ga1)
        let workout = candidate(hk1, start: 121, linked: [ga2])
        #expect(outcomes(ride, workout) == flagged)
    }

    // MARK: Overlap

    @Test func aPartialRecordingInsideALongerRideIsFlaggedNotMerged() {
        // A two-hour ride from 0 to 7200, and a 20-minute recording from
        // 1800 to 3000 inside it. Starts are 1800 s apart, so the rule fails.
        let ride = candidate(ga1, elapsed: 7200, distance: 60_000)
        let part = candidate(hk1, start: 1800, elapsed: 1200, distance: 10_000)
        #expect(outcomes(ride, part) == flagged)
    }

    @Test func recordsThatOverlapByOneSecondAreFlagged() {
        // 0 to 3600 and 3599 to 7199 share the second from 3599 to 3600.
        #expect(outcomes(candidate(ga1), candidate(hk1, start: 3599)) == flagged)
    }

    @Test func recordsThatOnlyTouchDoNotOverlap() {
        // 0 to 3600 and 3600 to 7200. The spans are half-open.
        #expect(outcomes(candidate(ga1), candidate(hk1, start: 3600)) == unrelated)
    }

    @Test func recordsFarApartAreUnrelated() {
        // 0 to 3600 and 7200 to 10 800.
        #expect(outcomes(candidate(ga1), candidate(hk1, start: 7200)) == unrelated)
    }

    @Test func overlappingRecordsOfDifferentFamiliesAreStillFlagged() {
        // A walk from 600 to 1800 during a ride from 0 to 3600.
        let ride = candidate(ga1)
        let walk = candidate(hk1, sport: .walking, start: 600, elapsed: 1200, distance: 1500)
        #expect(outcomes(ride, walk) == flagged)
    }

    // MARK: Tolerances are parameters

    @Test func theTolerancesPassedInAreTheOnesUsed() {
        // Starts 60 s apart pass the standard 120 s and fail a 30 s limit.
        let ride = candidate(ga1)
        let workout = candidate(hk1, start: 60)
        let strict = MatchTolerances(startDifference: 30, durationFraction: 0.05, distanceFraction: 0.05)
        #expect(MatchOutcome.between(ride, workout) == .sameActivity(.tolerances))
        #expect(MatchOutcome.between(ride, workout, tolerances: strict) == .possibleDuplicate)
    }

    @Test func aLooserDurationToleranceLetsALargerDifferenceThrough() {
        // 2000 - 1700 = 300 s. 5% of 2000 is 100 s; 20% of 2000 is 400 s.
        let ride = candidate(ga1, elapsed: 2000)
        let workout = candidate(hk1, elapsed: 1700)
        let loose = MatchTolerances(startDifference: 120, durationFraction: 0.2, distanceFraction: 0.05)
        #expect(MatchOutcome.between(ride, workout) == .possibleDuplicate)
        #expect(MatchOutcome.between(ride, workout, tolerances: loose) == .sameActivity(.tolerances))
    }

    @Test func aLooserDistanceToleranceLetsALargerDifferenceThrough() {
        // 40 000 - 36 000 = 4000 m. 5% of 40 000 is 2000 m; 20% is 8000 m.
        let ride = candidate(ga1, distance: 40_000)
        let workout = candidate(hk1, distance: 36_000)
        let loose = MatchTolerances(startDifference: 120, durationFraction: 0.05, distanceFraction: 0.2)
        #expect(MatchOutcome.between(ride, workout) == .possibleDuplicate)
        #expect(MatchOutcome.between(ride, workout, tolerances: loose) == .sameActivity(.tolerances))
    }
}

@Suite("Scanning records for matches")
struct MatchScanTests {
    // garmin:1 and healthKit:W1 are one ride:
    //   starts 30 s apart (within 120), durations 3600 and 3590 (10 s apart,
    //   within 5% of 3600 = 180), distances 30 000 and 30 100 (100 m apart,
    //   within 5% of 30 100 = 1505).
    // file:f1 is a 10-minute recording from 1800 to 2400, inside both. Its
    //   start is 1800 s and 1770 s from theirs, so it fails and is flagged
    //   against each.
    // garmin:2 starts at 100 000, long after the others end. Unrelated.
    private let ride = candidate(ga1, start: 0, elapsed: 3600, distance: 30_000)
    private let workout = candidate(hk1, start: 30, elapsed: 3590, distance: 30_100)
    private let part = candidate(fi1, start: 1800, elapsed: 600, distance: 5000)
    private let later = candidate(ga2, start: 100_000)

    private var expected: MatchScan {
        MatchScan(
            links: [autoLink(ga1, hk1, time: 400, device: "phone")],
            // Both pairs have file:f1 as the lower identity, so they are
            // ordered by the upper: garmin:1 < healthKit:W1.
            possibleDuplicates: [IdentityPair(fi1, ga1), IdentityPair(fi1, hk1)]
        )
    }

    @Test func aScanWritesAnAutomaticLinkForEveryMatchAndFlagsTheRest() {
        let scan = MatchScan.scan([ride, workout, part, later], at: at(400), device: DeviceID("phone"))
        #expect(scan == expected)
    }

    @Test func theLinkAScanWritesIsAnAutomaticSameActivityLink() {
        let scan = MatchScan.scan([ride, workout], at: at(400), device: DeviceID("phone"))
        #expect(scan.links.count == 1)
        let link = scan.links.first
        #expect(link?.name == RecordName("link|sameActivity|garmin:1|healthKit:W1"))
        #expect(link?.pair == IdentityPair(ga1, hk1))
        #expect(link?.kind == .sameActivity)
        #expect(link?.maker == .automatic)
        #expect(link?.time == at(400))
        #expect(link?.device == DeviceID("phone"))
        #expect(scan.possibleDuplicates.isEmpty)
    }

    @Test func aScanDoesNotDependOnTheOrderOfTheRecords() {
        // 4 records, 24 orderings.
        for ordering in permutations([ride, workout, part, later]) {
            #expect(MatchScan.scan(ordering, at: at(400), device: DeviceID("phone")) == expected)
        }
    }

    @Test func linksInAScanAreOrderedByName() {
        // Three recordings of one ride. All three pairs match, and the link
        // names in ascending order are
        //   link|sameActivity|file:f1|garmin:1
        //   link|sameActivity|file:f1|healthKit:W1
        //   link|sameActivity|garmin:1|healthKit:W1
        let records = [candidate(hk1), candidate(ga1), candidate(fi1)]
        let scan = MatchScan.scan(records, at: at(7), device: DeviceID("pad"))
        #expect(scan == MatchScan(
            links: [
                autoLink(fi1, ga1, time: 7, device: "pad"),
                autoLink(fi1, hk1, time: 7, device: "pad"),
                autoLink(ga1, hk1, time: 7, device: "pad"),
            ],
            possibleDuplicates: []
        ))
    }

    @Test func twoDevicesScanningTheSameRecordsWriteTheSameRecordNames() {
        let onPhone = MatchScan.scan([ride, workout], at: at(400), device: DeviceID("phone"))
        let onPad = MatchScan.scan([workout, ride], at: at(900), device: DeviceID("pad"))
        #expect(onPhone.links.map(\.name) == [RecordName("link|sameActivity|garmin:1|healthKit:W1")])
        #expect(onPad.links.map(\.name) == [RecordName("link|sameActivity|garmin:1|healthKit:W1")])
    }

    @Test func aScanUsesTheTolerancesPassedIn() {
        // Starts are 30 s apart. With a 10 s limit the pair fails and, since
        // the hours overlap, is flagged instead.
        let strict = MatchTolerances(startDifference: 10, durationFraction: 0.05, distanceFraction: 0.05)
        let scan = MatchScan.scan([ride, workout], at: at(400), device: DeviceID("phone"), tolerances: strict)
        #expect(scan == MatchScan(links: [], possibleDuplicates: [IdentityPair(ga1, hk1)]))
    }

    @Test func aScanOfNothingOrOfOneRecordFindsNothing() {
        let empty = MatchScan(links: [], possibleDuplicates: [])
        #expect(MatchScan.scan([], at: at(0), device: DeviceID("phone")) == empty)
        #expect(MatchScan.scan([ride], at: at(0), device: DeviceID("phone")) == empty)
    }
}
