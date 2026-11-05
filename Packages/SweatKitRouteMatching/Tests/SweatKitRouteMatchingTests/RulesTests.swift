import Testing
import SweatKitRouteMatching

/// The starting values, straight from the spec's "Repeated-route comparison"
/// section. Each number here is read off the spec's text, not off the code.
@Suite struct RulesTests {
    let rules = MatchingRules.standard

    @Test func detectionStartingValuesMatchTheSpec() {
        // "Resample each cleaned track to one point every 25 m and record the
        // 50 m grid cells it passes through."
        #expect(rules.resampleSpacing == 25)
        #expect(rules.cellSize == 50)
        // "total distance within 10%, start and finish each within 200 m."
        #expect(rules.distanceTolerance == 0.10)
        #expect(rules.endpointTolerance == 200)
        // "share at least 85% of their grid cells."
        #expect(rules.minimumSharedCells == 0.85)
    }

    @Test func alignmentStartingValuesMatchTheSpec() {
        // Proximity: "within 30 m", "at least 90%"; reject "under 70%".
        #expect(rules.proximityDistance == 30)
        #expect(rules.joinProximity == 0.90)
        #expect(rules.reviewProximity == 0.70)
        // Ends: "within 25 m of the start ... within 25 m of the end".
        #expect(rules.endTolerance == 25)
        // Coverage: "at least 95%, with no unmapped stretch longer than 50 m".
        #expect(rules.minimumCoverage == 0.95)
        #expect(rules.longestUnmappedStretch == 50)
        // Length ratio: "within 3%".
        #expect(rules.lengthRatioTolerance == 0.03)
        // Side offset: "over any 200 m stretch", "more than 10 m to one side".
        #expect(rules.sideOffsetStretch == 200)
        #expect(rules.maximumSideOffset == 10)
    }

    @Test func comparisonStartingValueMatchesTheSpec() {
        // "Each effort is interpolated onto a 10 m grid of route distance."
        #expect(rules.comparisonGridSpacing == 10)
    }

    /// The spec gives no number for the search window. This pins the
    /// package's own starting value, which the lap, out-and-back and
    /// figure-of-eight tests rely on being shorter than a lap or a lobe.
    @Test func searchWindowIsThePackagesOwnStartingValue() {
        #expect(rules.searchWindow == 100)
    }

    @Test func defaultInitialiserGivesTheStandardRules() {
        #expect(MatchingRules() == MatchingRules.standard)
    }
}
