import Foundation
import SweatKitRouteMatching
import Testing

/// What each measure needs to join automatically, exactly at its threshold.
/// The values are set directly, so no arithmetic stands between the test and
/// the rule.
///
/// | Measure | Needed to join automatically |
/// | Proximity | At least 90% |
/// | Ends | First mapped point within 25 m of the start, last within 25 m of the end |
/// | Coverage | At least 95%, with no unmapped stretch longer than 50 m |
/// | Length ratio | Within 3% |
/// | Side offset | No stretch more than 10 m to one side |
@Suite struct MeasureThresholdTests {
    private let clean = AlignmentMeasures.clean

    @Test func cleanMeasuresPassAllFive() {
        #expect(clean.failedMeasures().isEmpty)
        #expect(clean.allPass())
    }

    @Test(arguments: [
        (0.90, true),   // "at least 90%" includes 90%
        (0.95, true),
        (1.0, true),
        (0.8999, false),
        (0.70, false),
        (0.0, false),
    ])
    func proximityNeedsAtLeastNinetyPercent(proximity: Double, passes: Bool) {
        let measures = clean.with { $0.proximity = proximity }
        #expect(measures.failedMeasures() == (passes ? [] : [.proximity]))
        #expect(measures.allPass() == passes)
    }

    @Test(arguments: [
        (25.0, 0.0, true),   // "within 25 m" includes 25 m
        (0.0, 25.0, true),
        (25.0, 25.0, true),
        (25.01, 0.0, false), // start too late
        (0.0, 25.01, false), // finish too early
        (30.0, 30.0, false),
    ])
    func endsNeedBothGapsWithin25Metres(startGap: Double, endGap: Double, passes: Bool) {
        let measures = clean.with {
            $0.startGap = startGap
            $0.endGap = endGap
        }
        #expect(measures.failedMeasures() == (passes ? [] : [.ends]))
    }

    @Test(arguments: [
        (0.95, 0.0, true),    // "at least 95%" includes 95%
        (0.95, 50.0, true),   // "no stretch longer than 50 m" allows 50 m
        (1.0, 50.0, true),
        (0.9499, 0.0, false), // share too low
        (0.99, 50.01, false), // share fine, one stretch too long
        (0.90, 80.0, false),  // both
    ])
    func coverageNeedsNinetyFivePercentAndNoStretchOver50Metres(coverage: Double, stretch: Double, passes: Bool) {
        let measures = clean.with {
            $0.coverage = coverage
            $0.longestUnmappedStretch = stretch
        }
        #expect(measures.failedMeasures() == (passes ? [] : [.coverage]))
    }

    @Test(arguments: [
        (1.03, true),    // "within 3%" includes 3% over
        (0.97, true),    // and 3% under
        (1.0, true),
        (1.0301, false),
        (0.9699, false),
        (1.5, false),
        (0.5, false),
    ])
    func lengthRatioNeedsToBeWithinThreePercent(ratio: Double, passes: Bool) {
        let measures = clean.with { $0.lengthRatio = ratio }
        #expect(measures.failedMeasures() == (passes ? [] : [.lengthRatio]))
    }

    @Test(arguments: [
        (10.0, true),    // "more than 10 m" does not include 10 m
        (-10.0, true),   // on either side
        (0.0, true),
        (10.01, false),  // right
        (-10.01, false), // left
        (-20.0, false),
    ])
    func sideOffsetAllowsTenMetresEitherSide(offset: Double, passes: Bool) {
        let measures = clean.with { $0.worstSideOffset = offset }
        #expect(measures.failedMeasures() == (passes ? [] : [.sideOffset]))
    }

    @Test func everyFailingMeasureIsNamed() {
        let measures = AlignmentMeasures(
            proximity: 0.5,
            startGap: 100,
            endGap: 0,
            coverage: 0.5,
            longestUnmappedStretch: 0,
            lengthRatio: 1.2,
            worstSideOffset: -15
        )
        #expect(measures.failedMeasures() == Set(AlignmentMeasure.allCases))
        #expect(!measures.allPass())
    }

    @Test func theThresholdsComeFromTheRules() {
        var rules = MatchingRules.standard
        rules.joinProximity = 0.80
        rules.maximumSideOffset = 25
        let measures = clean.with {
            $0.proximity = 0.85
            $0.worstSideOffset = 20
        }
        #expect(measures.failedMeasures() == [.proximity, .sideOffset])
        #expect(measures.failedMeasures(rules: rules).isEmpty)
    }
}

/// The outcome table.
///
/// | Join | All five measures pass, and the activity aligns with no other route |
/// | Manual review | The ends and coverage pass, and proximity is between 70% and 90%; or a stretch sits consistently to one side; or the length ratio fails; or the activity also aligns with a second route |
/// | Reject | Proximity is under 70%, or the ends or coverage fail |
@Suite struct OutcomeTests {
    private let clean = AlignmentMeasures.clean

    // MARK: Join

    @Test func allFivePassingAndNoOtherRouteJoins() {
        #expect(clean.outcome() == .join)
        #expect(clean.outcome(alignsWithAnotherRoute: false) == .join)
    }

    @Test func everyMeasureExactlyOnItsThresholdStillJoins() {
        let onTheEdge = AlignmentMeasures(
            proximity: 0.90,
            startGap: 25,
            endGap: 25,
            coverage: 0.95,
            longestUnmappedStretch: 50,
            lengthRatio: 1.03,
            worstSideOffset: -10
        )
        #expect(onTheEdge.outcome() == .join)
    }

    // MARK: Manual review

    @Test(arguments: [0.70, 0.75, 0.80, 0.8999])
    func proximityFromSeventyUpToNinetyPercentGoesToReview(proximity: Double) {
        // The ends and coverage pass, so this is the first review rule. 70%
        // itself is review: reject is "under 70%".
        #expect(clean.with { $0.proximity = proximity }.outcome() == .manualReview)
    }

    @Test(arguments: [10.01, -10.01, 20, -20])
    func aStretchConsistentlyToOneSideGoesToReview(offset: Double) {
        #expect(clean.with { $0.worstSideOffset = offset }.outcome() == .manualReview)
    }

    @Test(arguments: [1.0301, 0.9699, 1.32, 0.80])
    func aFailedLengthRatioGoesToReview(ratio: Double) {
        #expect(clean.with { $0.lengthRatio = ratio }.outcome() == .manualReview)
    }

    @Test func aligningWithASecondRouteGoesToReview() {
        #expect(clean.outcome(alignsWithAnotherRoute: true) == .manualReview)
    }

    @Test func severalReviewReasonsAtOnceAreStillReview() {
        let measures = clean.with {
            $0.proximity = 0.80
            $0.worstSideOffset = 15
            $0.lengthRatio = 1.10
        }
        #expect(measures.outcome() == .manualReview)
        #expect(measures.outcome(alignsWithAnotherRoute: true) == .manualReview)
    }

    // MARK: Reject

    @Test(arguments: [0.6999, 0.5, 0.0])
    func proximityUnderSeventyPercentRejects(proximity: Double) {
        #expect(clean.with { $0.proximity = proximity }.outcome() == .reject)
    }

    @Test func aLateStartRejects() {
        #expect(clean.with { $0.startGap = 25.01 }.outcome() == .reject)
        #expect(clean.with { $0.startGap = 1000 }.outcome() == .reject)
    }

    @Test func anEarlyFinishRejects() {
        #expect(clean.with { $0.endGap = 25.01 }.outcome() == .reject)
    }

    @Test func tooLittleCoverageRejects() {
        #expect(clean.with { $0.coverage = 0.9499 }.outcome() == .reject)
    }

    @Test func anUnmappedStretchOver50MetresRejects() {
        // Coverage of 96% is enough on its own. The 80 m stretch is not.
        let measures = clean.with {
            $0.coverage = 0.96
            $0.longestUnmappedStretch = 80
        }
        #expect(measures.outcome() == .reject)
    }

    // MARK: Which rule wins

    /// The table's rows overlap. Reject comes first: the review row's first
    /// rule already requires the ends and coverage to pass, and "Full efforts
    /// only" says a late start, an early finish or a long detour stays an
    /// ordinary activity.
    @Test func rejectWinsOverEveryReviewReason() {
        // A stretch to one side and a failed length ratio would be review,
        // but the start is late.
        let lateAndOffset = clean.with {
            $0.startGap = 40
            $0.worstSideOffset = 15
            $0.lengthRatio = 1.10
        }
        #expect(lateAndOffset.outcome() == .reject)

        // Proximity in the review band, but coverage fails.
        let thinAndPatchy = clean.with {
            $0.proximity = 0.80
            $0.coverage = 0.90
        }
        #expect(thinAndPatchy.outcome() == .reject)

        // Proximity under 70% with a failed length ratio.
        let farAndLong = clean.with {
            $0.proximity = 0.50
            $0.lengthRatio = 1.5
        }
        #expect(farAndLong.outcome() == .reject)
    }

    @Test func aSecondRouteDoesNotRescueARejection() {
        #expect(clean.with { $0.endGap = 500 }.outcome(alignsWithAnotherRoute: true) == .reject)
        #expect(clean.with { $0.proximity = 0.2 }.outcome(alignsWithAnotherRoute: true) == .reject)
    }

    @Test func theOutcomeThresholdsComeFromTheRules() {
        var rules = MatchingRules.standard
        rules.reviewProximity = 0.50
        let measures = clean.with { $0.proximity = 0.60 }
        #expect(measures.outcome() == .reject)
        #expect(measures.outcome(rules: rules) == .manualReview)
    }

    // MARK: One activity against several routes

    @Test func oneRouteAlignedJoins() {
        #expect(RouteAlignment.outcomes(for: [clean]) == [.join])
    }

    @Test func twoRoutesAlignedBothGoToReview() {
        // "Where GPS accuracy cannot tell two courses apart, the app asks."
        let other = clean.with { $0.worstSideOffset = 4 }
        #expect(RouteAlignment.outcomes(for: [clean, other]) == [.manualReview, .manualReview])
    }

    @Test func aRejectedRouteIsNotASecondRoute() {
        let rejected = clean.with { $0.endGap = 800 }
        #expect(RouteAlignment.outcomes(for: [clean, rejected]) == [.join, .reject])
        #expect(RouteAlignment.outcomes(for: [rejected, clean]) == [.reject, .join])
    }

    @Test func aRouteUnderReviewIsNotASecondRoute() {
        // The activity aligns only with the first route: all five pass there.
        // On the second a stretch sits to one side, so it does not align with
        // it. The first joins and the second is still asked about.
        let offset = clean.with { $0.worstSideOffset = -20 }
        #expect(RouteAlignment.outcomes(for: [clean, offset]) == [.join, .manualReview])
    }

    @Test func threeRoutesKeepTheirOrder() {
        let rejected = clean.with { $0.proximity = 0.1 }
        #expect(RouteAlignment.outcomes(for: [clean, rejected, clean]) == [.manualReview, .reject, .manualReview])
    }

    @Test func noRoutesGiveNoOutcomes() {
        #expect(RouteAlignment.outcomes(for: []).isEmpty)
    }
}
