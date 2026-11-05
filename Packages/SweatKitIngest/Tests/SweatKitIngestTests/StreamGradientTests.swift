import Foundation
import SweatKitIngest
import SweatKitModel
import Testing

/// Stream rule 10: gradient is altitude change divided by distance over a
/// 30 m window centred on the sample. It is missing, never zero or infinite,
/// when altitude is missing or when the window covers less than 5 m of travel.
@Suite struct StreamGradientTests {
    /// One sample a second for `count` seconds, with distance and altitude
    /// given by the second. A nil altitude leaves the field off the sample.
    private func recorded(
        count: Int,
        distance: (Double) -> Double?,
        altitude: (Double) -> Double?
    ) -> [NativeSample] {
        (0..<count).map { second in
            let s = Double(second)
            return NativeSample(timestamp: Synthetic.at(s), altitude: altitude(s), distance: distance(s))
        }
    }

    private func normalised(
        count: Int,
        distance: (Double) -> Double?,
        altitude: (Double) -> Double?
    ) throws -> AnalysisStream {
        try Synthetic.stream(
            Synthetic.activity(
                elapsed: Double(count),
                samples: recorded(count: count, distance: distance, altitude: altitude)
            )
        )
    }

    // MARK: Value

    @Test func steadyClimbHasItsSlopeAtEverySecond() throws {
        // 5 m/s along the road, climbing 0.25 m a second: 0.25 / 5 = 0.05.
        // Total travel is 95 m. On a constant slope every window, whole or
        // cut short at an end, gives the same 0.05. The windows at the two
        // ends still cover 15 m, which is more than 5 m.
        let stream = try normalised(count: 20, distance: { 5 * $0 }, altitude: { 100 + 0.25 * $0 })
        expectValues(stream.gradient, Array(repeating: 0.05, count: 20))
        #expect(stream.gradient.quality == Array(repeating: measured, count: 20))
    }

    @Test func steadyDescentIsNegative() throws {
        // 10 m/s, dropping 0.8 m a second: -0.8 / 10 = -0.08.
        let stream = try normalised(count: 20, distance: { 10 * $0 }, altitude: { 500 - 0.8 * $0 })
        expectValues(stream.gradient, Array(repeating: -0.08, count: 20))
    }

    @Test func flatGroundIsAMeasuredZero() throws {
        let stream = try normalised(count: 20, distance: { 5 * $0 }, altitude: { _ in 100 })
        expectValues(stream.gradient, Array(repeating: 0, count: 20))
        #expect(stream.gradient.quality == Array(repeating: measured, count: 20))
    }

    /// Flat for 50 m, then a 10% ramp, with a sample every 5 m, so each
    /// window edge lands exactly on a sample (15 m is three samples).
    ///
    /// Altitude is 0 up to 50 m and 0.1 x (distance - 50) after it.
    @Test func windowIsThirtyMetresCentredOnTheSample() throws {
        let stream = try normalised(
            count: 21,
            distance: { 5 * $0 },
            altitude: { $0 <= 10 ? 0 : 0.1 * (5 * $0 - 50) }
        )
        // Second 7, at 35 m: window 20 to 50 m, all flat. 0 / 30 = 0.
        #expect(isClose(stream.gradient[7], 0))
        // Second 8, at 40 m: window 25 to 55 m. Altitude 0 to 0.5. 0.5 / 30.
        // A 20 m window would give 0, and a 40 m window 1.0 / 40 = 0.025.
        #expect(isClose(stream.gradient[8], 0.5 / 30))
        // Second 10, at 50 m, the foot of the ramp: window 35 to 65 m.
        // Altitude 0 to 1.5. 1.5 / 30 = 0.05.
        #expect(isClose(stream.gradient[10], 0.05))
        // Second 12, at 60 m: window 45 to 75 m. Altitude 0 to 2.5. 2.5 / 30.
        // A 20 m window would already be wholly on the ramp, giving 0.1.
        #expect(isClose(stream.gradient[12], 2.5 / 30))
        // Second 13, at 65 m: window 50 to 80 m, all ramp. 3.0 / 30 = 0.1.
        #expect(isClose(stream.gradient[13], 0.1))
    }

    /// Reading: the window's ends are read off the line between samples, not
    /// snapped to the samples inside it. The same road as above at 10 m/s, so
    /// samples are 10 m apart and a window edge falls halfway between two.
    @Test func windowEndsBetweenSamplesAreInterpolated() throws {
        let stream = try normalised(
            count: 11,
            distance: { 10 * $0 },
            altitude: { $0 <= 5 ? 0 : 0.1 * (10 * $0 - 50) }
        )
        // Second 6, at 60 m: window 45 to 75 m.
        //   Altitude at 45 m: between 40 m (0) and 50 m (0) = 0.
        //   Altitude at 75 m: halfway between 70 m (2.0) and 80 m (3.0) = 2.5.
        //   2.5 / 30. Snapping to the samples at 50 and 70 m would give 0.1.
        #expect(isClose(stream.gradient[6], 2.5 / 30))
    }

    /// At 20 m/s the samples are further apart than half the window. The
    /// gradient is still there, because the window is 30 m of road, not a
    /// count of samples.
    @Test func gradientSurvivesSamplesFurtherApartThanTheWindow() throws {
        // 20 m/s, climbing 1 m a second: 1 / 20 = 0.05.
        let stream = try normalised(count: 10, distance: { 20 * $0 }, altitude: { 100 + $0 })
        expectValues(stream.gradient, Array(repeating: 0.05, count: 10))
    }

    /// Reading: a gradient over filled altitude is interpolated.
    @Test func gradientOverFilledAltitudeIsInterpolated() throws {
        // The steady 5% climb, with no samples at all for seconds 8 and 9.
        // Altitude and distance are both filled linearly across the 2 s gap,
        // so the climb is unbroken.
        let samples = recorded(count: 20, distance: { 5 * $0 }, altitude: { 100 + 0.25 * $0 })
            .enumerated().filter { $0.offset != 8 && $0.offset != 9 }.map(\.element)
        let stream = try Synthetic.stream(Synthetic.activity(elapsed: 20, samples: samples))
        expectValues(stream.gradient, Array(repeating: 0.05, count: 20))
        #expect(stream.gradient.quality[8] == interpolated)
        #expect(stream.gradient.quality[9] == interpolated)
        #expect(stream.gradient.quality[0] == measured)
        #expect(stream.gradient.quality[19] == measured)
    }

    // MARK: Missing

    @Test func gradientIsMissingWhereAltitudeIsMissing() throws {
        // The steady 5% climb, but the altimeter drops out for seconds 8 to
        // 15: an 8 s gap, too long to fill. Distance carries on.
        let stream = try normalised(
            count: 20,
            distance: { 5 * $0 },
            altitude: { (8...15).contains(Int($0)) ? nil : 100 + 0.25 * $0 }
        )
        #expect(stream.gradient.quality[8...15].allSatisfy { $0 == missing })
        // Seconds 0 to 4 have windows that end at or before second 7 (35 m),
        // clear of the dropout, so they keep the slope.
        for second in 0...4 {
            #expect(isClose(stream.gradient[second], 0.05), "second \(second)")
        }
    }

    @Test func gradientIsMissingWhenThereIsNoAltitude() throws {
        let stream = try normalised(count: 20, distance: { 5 * $0 }, altitude: { _ in nil })
        #expect(stream.gradient.quality == Array(repeating: missing, count: 20))
    }

    @Test func gradientIsMissingWhenTheWindowCoversLessThanFiveMetres() throws {
        // 1 m a second for 5 samples: 4 m of travel in the whole activity,
        // so no window can cover 5 m. The 1 m a second of climb must not
        // surface as a gradient of 1.
        let stream = try normalised(count: 5, distance: { $0 }, altitude: { 100 + $0 })
        #expect(stream.gradient.quality == Array(repeating: missing, count: 5))
    }

    @Test func gradientIsMissingNotInfiniteWhenStandingStill() throws {
        // Ten seconds on the spot while the altimeter drifts upward. Zero
        // travel under a non-zero altitude change must not become infinity,
        // NaN or zero.
        let stream = try normalised(count: 10, distance: { _ in 250 }, altitude: { 100 + 0.5 * $0 })
        #expect(stream.gradient.quality == Array(repeating: missing, count: 10))
    }

    @Test func windowOfExactlyFiveMetresIsEnough() throws {
        // 2.5 m a second for 3 samples: exactly 5 m of travel, climbing
        // 0.25 m a second. "Less than 5 m" is missing, so 5 m is not.
        let stream = try normalised(count: 3, distance: { 2.5 * $0 }, altitude: { 0.25 * $0 })
        // Every window is cut to the same 0 to 5 m: 0.5 / 5 = 0.1.
        expectValues(stream.gradient, [0.1, 0.1, 0.1])
    }

    /// Reading: the window is measured along the distance channel, which is
    /// the recorded distance. With no distance there is no window, even where
    /// positions exist.
    @Test func gradientIsMissingWhenThereIsNoDistance() throws {
        let samples = (0..<20).map { second in
            let s = Double(second)
            return NativeSample(
                timestamp: Synthetic.at(s),
                position: Coordinate(latitude: 10 + 0.0001 * s, longitude: 20),
                altitude: 100 + 0.25 * s
            )
        }
        let stream = try Synthetic.stream(Synthetic.activity(elapsed: 20, samples: samples))
        #expect(stream.gradient.quality == Array(repeating: missing, count: 20))
    }
}
