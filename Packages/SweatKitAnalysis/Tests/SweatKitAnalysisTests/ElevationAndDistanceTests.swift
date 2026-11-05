import Foundation
import SweatKitModel
import Testing
@testable import SweatKitAnalysis

/// "Ascent and descent: summed by peak and valley."
///
/// The rule under test: a climb runs from a low point to the next high point.
/// It starts to count once the altitude is the threshold or more above the
/// low point, every new high then adds to it, and it ends once the altitude
/// has fallen the threshold or more below the high point, which starts a
/// descent measured from that high point. A turn smaller than the threshold
/// neither ends the climb nor counts. Descents mirror this. Before the first
/// climb or descent, the low and high points are the lowest and highest
/// altitudes so far.
///
/// The threshold is 3 m, 1.5 m for cycling and none for a virtual activity.
/// These tests are walks, so 3 m, unless they say otherwise.
@Suite struct ElevationTests {
    private func elevation(
        _ altitude: [Double?],
        sport: Sport = .walking,
        virtual: Bool = false,
        pauses: PauseData = .known(paused: [])
    ) -> ActivityMetrics {
        analyse(makeStream(count: altitude.count, pauses: pauses, altitude: altitude), sport: sport, virtual: virtual)
    }

    @Test func aClimbCountsFromItsLowPointToItsHighPoint() {
        // Low 100. 101 and 102 are under 3 m above it. 103 is 3 m above:
        // the climb starts with 3 m. 104 is a new high: 1 m more. Total 4.
        let metrics = elevation([100, 101, 102, 103, 104])
        #expect(metrics.ascent == .available(4))
        #expect(metrics.descent == .available(0))
    }

    @Test func theTopOfAClimbIsNotLost() {
        // A 4 m hill. Up: 3 m at 103, 1 m more at 104, so 4. Down from the
        // peak of 104: 103 and 102 are under 3 m below it; 101 is 3 m below,
        // so the descent starts with 3 m; 100 is a new low, 1 m more. Total 4.
        let metrics = elevation([100, 101, 102, 103, 104, 103, 102, 101, 100])
        #expect(metrics.ascent == .available(4))
        #expect(metrics.descent == .available(4))
    }

    @Test func aTurnOfExactlyTheThresholdCounts() {
        #expect(elevation([100, 103]).ascent == .available(3))
        #expect(elevation([100, 97]).descent == .available(3))
    }

    @Test func aTurnUnderTheThresholdDoesNotCount() {
        // 2.5 m up, then back: both under 3 m.
        let metrics = elevation([100, 102.5, 100])
        #expect(metrics.ascent == .available(0))
        #expect(metrics.descent == .available(0))
    }

    @Test func wobbleInsideABandNarrowerThanTheThresholdAddsNothing() {
        // Lowest 99.5, highest 102: a band of 2.5 m. No value is ever 3 m
        // above the lowest so far or 3 m below the highest so far, though
        // the raw changes add up to 4.5 m up and 4.5 m down.
        let metrics = elevation([100, 102, 100, 102, 100, 99.5, 100])
        #expect(metrics.ascent == .available(0))
        #expect(metrics.descent == .available(0))
    }

    @Test func aFallIsMeasuredFromTheHighestPointSoFar() {
        // The highest so far is 102. 98 is 4 m below it: a descent of 4.
        // The last value, 100, is 2 m above the low of 98: under 3 m, so
        // no climb.
        let metrics = elevation([100, 102, 100, 102, 100, 98, 100])
        #expect(metrics.ascent == .available(0))
        #expect(metrics.descent == .available(4))
    }

    @Test func aDipSmallerThanTheThresholdDoesNotEndAClimb() {
        // 105: 5 m above the low of 100, the climb starts with 5 m. 103 is
        // 2 m below the peak: under 3 m, so the climb goes on and nothing is
        // counted. 108 is a new high, 3 m above the old peak of 105. Total 8,
        // which is the low of 100 to the high of 108.
        let metrics = elevation([100, 105, 103, 108])
        #expect(metrics.ascent == .available(8))
        #expect(metrics.descent == .available(0))
    }

    @Test func ascentAndDescentAreSummedSeparately() {
        // Low 100.
        //   110: 10 above the low  -> ascent 10, peak 110
        //   104:  6 below the peak -> descent 6, valley 104
        //   107:  3 above the valley -> ascent 13, peak 107
        //    95: 12 below the peak -> descent 18
        let metrics = elevation([100, 110, 104, 107, 95])
        #expect(metrics.ascent == .available(13))
        #expect(metrics.descent == .available(18))
    }

    @Test func secondsWithMissingAltitudeAreSkipped() {
        // Present values 100, 105, 99: 5 up, then 6 below the peak. A gap is
        // not a drop to zero.
        let metrics = elevation([100, nil, nil, 105, nil, 99])
        #expect(metrics.ascent == .available(5))
        #expect(metrics.descent == .available(6))
    }

    @Test func altitudeInsideAPausedSpanIsStillRead() {
        // The spec does not leave paused seconds out of ascent, which is why
        // it survives unknown pause positions. Paused 1..<3:
        // 105 is 5 above the low, 110 is a new high 5 above that: ascent 10.
        let metrics = elevation([100, 105, 110, 110], pauses: .known(paused: [1..<3]))
        #expect(metrics.ascent == .available(10))
    }

    @Test func ascentAndDescentAreUnavailableWithoutAltitude() {
        let metrics = analyse(makeStream(count: 10, power: run(200, 10)))
        #expect(metrics.ascent == .unavailable(.noAltitude))
        #expect(metrics.descent == .unavailable(.noAltitude))
    }

    @Test func aFlatActivityHasATrueZeroAscent() {
        // Altitude exists and never changes: 0 m, which is a value.
        #expect(elevation(run(250, 10)).ascent == .available(0))
    }

    // MARK: The threshold by kind of recording

    @Test func aRideCountsSmallerTurnsThanAWalk() {
        // On a bike the threshold is 1.5 m. 101 is 1 m above the low: under.
        // 102 is 2 m above: the climb starts with 2 m. 101 is 1 m below the
        // peak: under. 100 is 2 m below the peak: a descent of 2.
        let altitude: [Double?] = [100, 101, 102, 101, 100]
        let ride = elevation(altitude, sport: .cycling)
        #expect(ride.ascent == .available(2))
        #expect(ride.descent == .available(2))

        // On foot the threshold is 3 m, and the whole hill is 2 m: nothing.
        let walk = elevation(altitude, sport: .walking)
        #expect(walk.ascent == .available(0))
        #expect(walk.descent == .available(0))
    }

    @Test func aTurnOfExactlyTheCyclingThresholdCounts() {
        #expect(elevation([100, 101.5], sport: .cycling).ascent == .available(1.5))
        // 1.25 m is under it.
        #expect(elevation([100, 101.25], sport: .cycling).ascent == .available(0))
    }

    @Test func aVirtualRideCountsEveryRiseAndFall() {
        // No threshold. Rises: 0.25 + 0.25 + 0.5 = 1. Falls: 0.25.
        let altitude: [Double?] = [10, 10.25, 10.5, 10.25, 10.75]
        let virtual = elevation(altitude, sport: .cycling, virtual: true)
        #expect(virtual.ascent == .available(1))
        #expect(virtual.descent == .available(0.25))

        // The same altitudes on a road, where the threshold is 1.5 m: the
        // band from 10 to 10.75 is 0.75 m, so nothing counts.
        let outdoor = elevation(altitude, sport: .cycling)
        #expect(outdoor.ascent == .available(0))
        #expect(outdoor.descent == .available(0))
    }

    @Test func levelStretchesOfAVirtualRideAddNothing() {
        // 10, 10: no change. 11: 1 m up. 11: no change. 10: 1 m down.
        let metrics = elevation([10, 10, 11, 11, 10], sport: .cycling, virtual: true)
        #expect(metrics.ascent == .available(1))
        #expect(metrics.descent == .available(1))
    }

    @Test func theThresholdFollowsTheKindOfRecording() {
        // "3 m, 1.5 m for cycling, and none for a virtual activity"
        #expect(AnalysisRules.elevationThreshold(sport: .walking, isVirtual: false) == 3)
        #expect(AnalysisRules.elevationThreshold(sport: .running, isVirtual: false) == 3)
        #expect(AnalysisRules.elevationThreshold(sport: .hiking, isVirtual: false) == 3)
        #expect(AnalysisRules.elevationThreshold(sport: .other, isVirtual: false) == 3)
        #expect(AnalysisRules.elevationThreshold(sport: .cycling, isVirtual: false) == 1.5)
        // Virtual comes before the sport.
        #expect(AnalysisRules.elevationThreshold(sport: .cycling, isVirtual: true) == 0)
        #expect(AnalysisRules.elevationThreshold(sport: .running, isVirtual: true) == 0)
    }
}

/// Distance, which the spec lists among the metrics that survive unknown
/// pause positions.
@Suite struct DistanceTests {
    @Test func distanceIsTheLastCumulativeValue() {
        // 5 m/s for 11 samples: second 10 holds 50 m.
        let stream = makeStream(count: 11, distance: ramp(11, perSecond: 5))
        #expect(analyse(stream).distance == .available(50))
    }

    @Test func aMissingTailDoesNotMakeDistanceZero() {
        // The last present value is 40 m; the missing seconds after it are skipped.
        let stream = makeStream(count: 7, distance: [0, 10, 20, 30, 40, nil, nil])
        #expect(analyse(stream).distance == .available(40))
    }

    @Test func distanceIsUnavailableWithoutADistanceChannel() {
        let stream = makeStream(count: 10, power: run(200, 10))
        #expect(analyse(stream).distance == .unavailable(.noDistance))
    }
}
