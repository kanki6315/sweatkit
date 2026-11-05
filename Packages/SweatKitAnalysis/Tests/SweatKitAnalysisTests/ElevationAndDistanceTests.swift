import Foundation
import SweatKitModel
import Testing
@testable import SweatKitAnalysis

/// "Ascent and descent: summed altitude change with a 3 m hysteresis."
///
/// The rule under test: the reference is the first altitude; a later altitude
/// that differs from the reference by 3 m or more adds the whole difference
/// to ascent or descent and becomes the reference; a smaller difference
/// changes nothing.
@Suite struct ElevationTests {
    private func elevation(_ altitude: [Double?], pauses: PauseData = .known(paused: [])) -> ActivityMetrics {
        analyse(makeStream(count: altitude.count, pauses: pauses, altitude: altitude))
    }

    @Test func aClimbIsCountedOnceItReachesThreeMetres() {
        // Reference 100. 101 and 102 differ by under 3. 103 differs by 3:
        // ascent 3, reference 103. 104 differs by 1: nothing.
        let metrics = elevation([100, 101, 102, 103, 104])
        #expect(metrics.ascent == .available(3))
        #expect(metrics.descent == .available(0))
    }

    @Test func aChangeOfExactlyThreeMetresCounts() {
        #expect(elevation([100, 103]).ascent == .available(3))
        #expect(elevation([100, 97]).descent == .available(3))
    }

    @Test func aChangeUnderThreeMetresDoesNotCount() {
        // 2.9 m up, then back: both under the hysteresis.
        let metrics = elevation([100, 102.9, 100])
        #expect(metrics.ascent == .available(0))
        #expect(metrics.descent == .available(0))
    }

    @Test func noiseWithinThreeMetresOfTheReferenceAddsNothing() {
        // Every value is within 2 m of the reference of 100, so nothing is
        // counted, though the raw changes add up to 6 m up and 6 m down.
        let metrics = elevation([100, 102, 100, 102, 100, 98, 100])
        #expect(metrics.ascent == .available(0))
        #expect(metrics.descent == .available(0))
    }

    @Test func theReferenceMovesOnlyWhenAChangeIsCounted() {
        // Reference 100. 102: +2, nothing. 104: +4 from 100, ascent 4,
        // reference 104. 106: +2 from 104, nothing. Total 4, not 6.
        #expect(elevation([100, 102, 104, 106]).ascent == .available(4))
    }

    @Test func ascentAndDescentAreSummedSeparately() {
        // Reference 100.
        //   110: +10 -> ascent 10, reference 110
        //   104:  -6 -> descent 6, reference 104
        //   107:  +3 -> ascent 13, reference 107
        //    95: -12 -> descent 18, reference 95
        let metrics = elevation([100, 110, 104, 107, 95])
        #expect(metrics.ascent == .available(13))
        #expect(metrics.descent == .available(18))
    }

    @Test func secondsWithMissingAltitudeAreSkipped() {
        // Present values 100, 105, 99: +5 then -6. A gap is not a drop to zero.
        let metrics = elevation([100, nil, nil, 105, nil, 99])
        #expect(metrics.ascent == .available(5))
        #expect(metrics.descent == .available(6))
    }

    @Test func altitudeInsideAPausedSpanIsStillRead() {
        // The spec does not leave paused seconds out of ascent, which is why
        // it survives unknown pause positions. Paused 1..<3:
        // 100 -> 105 (+5) -> 110 (+5): ascent 10.
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
