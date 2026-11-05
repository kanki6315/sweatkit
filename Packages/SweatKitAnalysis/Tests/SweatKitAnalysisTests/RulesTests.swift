import SweatKitModel
import Testing
@testable import SweatKitAnalysis

/// The spec's starting values, each held in a named constant.
@Suite struct RulesTests {
    @Test func timeConstantsMatchTheSpec() {
        // "seconds below 0.5 m/s on foot or 1.0 m/s on a bike"
        #expect(AnalysisRules.movingSpeedFloorOnFoot == 0.5)
        #expect(AnalysisRules.movingSpeedFloorCycling == 1.0)
    }

    @Test func zoneBoundsMatchTheSpec() {
        // "under 55%, 55 to 75%, 75 to 90%, 90 to 105%, 105 to 120%, 120 to 150%, over 150%"
        #expect(AnalysisRules.powerZoneLowerBounds == [0.55, 0.75, 0.90, 1.05, 1.20, 1.50])
        // "under 81%, 81 to 90%, 90 to 94%, 94 to 100%, 100% and over"
        #expect(AnalysisRules.heartRateZoneLowerBounds == [0.81, 0.90, 0.94, 1.00])
        // "under -2%, flat from -2% to 2%, climbs of 2 to 5%, 5 to 8%, and over 8%"
        #expect(AnalysisRules.gradientBandLowerBounds == [-0.02, 0.02, 0.05, 0.08])
    }

    @Test func schemesHaveSevenFiveAndFiveZones() {
        #expect(ZoneScheme.power.zoneCount == 7)
        #expect(ZoneScheme.heartRate.zoneCount == 5)
        #expect(ZoneScheme.gradient.zoneCount == 5)
    }

    @Test func powerConstantsMatchTheSpec() {
        // "each valid 30-second window", "at least 24 of its seconds have power"
        #expect(AnalysisRules.weightedWindowSeconds == 30)
        #expect(AnalysisRules.weightedWindowMinimumPresentSeconds == 24)
        // "At least 90% of the possible windows are valid and there are at least 5 minutes of power"
        #expect(AnalysisRules.weightedMinimumValidWindowShare == 0.90)
        #expect(AnalysisRules.weightedMinimumPowerSeconds == 300)
        // "coverage is shown beside it when under 90%"
        #expect(AnalysisRules.averagePowerCoverageNoteBelow == 0.90)
        // "labelled recorded work when coverage is under 98%"
        #expect(AnalysisRules.recordedWorkCoverageBelow == 0.98)
        // "at least 95% of its seconds have power. A window shorter than 20 seconds must be complete."
        #expect(AnalysisRules.curveMinimumPresentShare == 0.95)
        #expect(AnalysisRules.curveCompleteBelowSeconds == 20)
        #expect(AnalysisRules.joulesPerKilojoule == 1000)
    }

    @Test func heartRateAndLoadConstantsMatchTheSpec() {
        // "Heart-rate coverage is available and at least 90%"
        #expect(AnalysisRules.heartRateLoadMinimumCoverage == 0.90)
        // "divided by 3,600, times 100"
        #expect(AnalysisRules.secondsPerHour == 3600)
        #expect(AnalysisRules.loadPerHourAtThreshold == 100)
    }

    @Test func otherConstantsMatchTheSpec() {
        // "The threshold is 3 m, 1.5 m for cycling, and none for a virtual
        // activity"
        #expect(AnalysisRules.elevationThreshold == 3)
        #expect(AnalysisRules.cyclingElevationThreshold == 1.5)
        #expect(AnalysisRules.virtualElevationThreshold == 0)
        // "per km"
        #expect(AnalysisRules.splitDistance == 1000)
        // "Fastest 1 km, 5 km and 10 km"
        #expect(AnalysisRules.bestDistances == [1000, 5000, 10_000])
    }

    @Test func everyAlgorithmHasAVersion() {
        let versions = [
            AlgorithmVersion.time, AlgorithmVersion.distance, AlgorithmVersion.elevation,
            AlgorithmVersion.zones, AlgorithmVersion.power, AlgorithmVersion.weightedPower,
            AlgorithmVersion.powerCurve, AlgorithmVersion.heartRate, AlgorithmVersion.load,
            AlgorithmVersion.efficiency, AlgorithmVersion.splits, AlgorithmVersion.bestDistances,
        ]
        #expect(versions.allSatisfy { $0 >= 1 })
    }

    @Test func everyReasonIsDistinct() {
        let reasons: [UnavailableReason] = [
            .noStream, .notStated, .pausePositionsUnknown, .notDefinedForSport,
            .noPower, .noHeartRate, .noSpeed, .noAltitude, .noDistance, .noGradient,
            .tooLittlePower, .tooFewValidWindows, .noValidWindow,
            .noThresholdPower, .noThresholdHeartRate, .lowHeartRateCoverage,
            .zeroDenominator, .distanceNotCovered,
        ]
        #expect(Set(reasons).count == reasons.count)
    }
}
