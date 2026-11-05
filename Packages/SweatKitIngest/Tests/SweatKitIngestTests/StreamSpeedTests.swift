import Foundation
import SweatKitIngest
import SweatKitModel
import Testing

/// Stream rule 9: speed is taken from the recorded speed, then from the
/// change in recorded distance, then from position, and is missing when none
/// of these exists.
///
/// The three sources disagree on purpose in these inputs, so the value says
/// which one was used:
/// - recorded speed is 3 m/s,
/// - distance grows 10 m a second,
/// - position moves 0.0001 degrees of latitude a second, which is
///   0.0001 x pi / 180 x 6,371,009 m = 11.12 m.
@Suite struct StreamSpeedTests {
    /// 11.12 m/s from the positions, within 1%. The margin covers the choice
    /// of Earth radius: a meridian degree is 110.6 to 111.7 km.
    private static let positionSpeed = 11.12
    private static let positionTolerance = 0.11

    private func sample(
        _ second: Int,
        speed: Double? = nil,
        distance: Bool = false,
        position: Bool = false
    ) -> NativeSample {
        let s = Double(second)
        return NativeSample(
            timestamp: Synthetic.at(s),
            position: position ? Coordinate(latitude: 10 + 0.0001 * s, longitude: 20) : nil,
            distance: distance ? 10 * s : nil,
            speed: speed
        )
    }

    @Test func recordedSpeedComesFirst() throws {
        let samples = (0..<6).map { sample($0, speed: 3, distance: true, position: true) }
        let stream = try Synthetic.stream(Synthetic.activity(elapsed: 6, samples: samples))
        expectValues(stream.speed, [3, 3, 3, 3, 3, 3])
        #expect(stream.speed.quality == Array(repeating: measured, count: 6))
    }

    @Test func recordedZeroSpeedIsMeasuredAndNotReplaced() throws {
        // Stopped at a light with 0 m/s recorded, while distance and position
        // in this made-up input keep moving. The recorded zero is a value.
        let samples = (0..<6).map { sample($0, speed: 0, distance: true, position: true) }
        let stream = try Synthetic.stream(Synthetic.activity(elapsed: 6, samples: samples))
        expectValues(stream.speed, [0, 0, 0, 0, 0, 0])
        #expect(stream.speed.quality == Array(repeating: measured, count: 6))
    }

    @Test func changeInDistanceComesSecond() throws {
        let samples = (0..<6).map { sample($0, distance: true, position: true) }
        let stream = try Synthetic.stream(Synthetic.activity(elapsed: 6, samples: samples))
        // Distance grows 10 m every second, so 10 m/s, not the 11.12 m/s the
        // positions would give. Seconds 1 to 4 have a neighbour on both sides,
        // so they hold whichever way the difference is taken.
        for second in 1...4 {
            #expect(isClose(stream.speed[second], 10), "second \(second)")
            #expect(stream.speed.quality[second] == measured, "second \(second)")
        }
    }

    @Test func positionComesThird() throws {
        let samples = (0..<6).map { sample($0, position: true) }
        let stream = try Synthetic.stream(Synthetic.activity(elapsed: 6, samples: samples))
        for second in 1...4 {
            #expect(
                isClose(stream.speed[second], Self.positionSpeed, tolerance: Self.positionTolerance),
                "second \(second)"
            )
            #expect(stream.speed.quality[second] == measured, "second \(second)")
        }
    }

    @Test func speedIsMissingWhenThereIsNoSource() throws {
        // Heart rate only: no speed, no distance, no position.
        let samples = (0..<6).map { NativeSample(timestamp: Synthetic.at(Double($0)), heartRate: 120) }
        let stream = try Synthetic.stream(Synthetic.activity(elapsed: 6, samples: samples))
        #expect(stream.speed.quality == Array(repeating: missing, count: 6))
    }

    /// Reading: the order of sources applies second by second, and a second
    /// without a recorded speed is not filled from the recorded speeds around
    /// it.
    @Test func eachSecondUsesTheFirstSourceItHas() throws {
        // Recorded speed on seconds 0, 1, 5 and 6 only. Distance on all seven.
        let samples = (0..<7).map { second in
            sample(second, speed: (2...4).contains(second) ? nil : 3, distance: true)
        }
        let stream = try Synthetic.stream(Synthetic.activity(elapsed: 7, samples: samples))
        // Seconds 2 to 4 fall to distance: 10 m a second.
        expectValues(stream.speed, [3, 3, 10, 10, 10, 3, 3])
        #expect(stream.speed.quality == Array(repeating: measured, count: 7))
    }

    /// Reading: speed from distance at second t is the change from t to
    /// t + 1, because the sample at t describes the interval t to t + 1. The
    /// last second with distance has nothing ahead of it.
    @Test func speedFromDistanceLooksForwardOneSecond() throws {
        let samples = (0..<6).map { sample($0, distance: true) }
        let stream = try Synthetic.stream(Synthetic.activity(elapsed: 6, samples: samples))
        // Second 0: (10 - 0) / 1 = 10. Second 5: no distance at second 6, and
        // no position either, so missing.
        expectValues(stream.speed, [10, 10, 10, 10, 10, nil])
    }

    /// Reading: speed from position looks forward one second too.
    @Test func speedFromPositionLooksForwardOneSecond() throws {
        let samples = (0..<6).map { sample($0, position: true) }
        let stream = try Synthetic.stream(Synthetic.activity(elapsed: 6, samples: samples))
        #expect(isClose(stream.speed[0], Self.positionSpeed, tolerance: Self.positionTolerance))
        #expect(stream.speed[5] == nil)
    }

    /// Reading: a speed taken from two measured values is measured, and one
    /// that leans on a filled value is interpolated.
    @Test func speedFromFilledDistanceIsInterpolated() throws {
        // Distance at seconds 0, 1, 4, 5 and 6. Seconds 2 and 3 are a 2 s gap,
        // filled linearly: 20 m and 30 m.
        let samples = [0, 1, 4, 5, 6].map { sample($0, distance: true) }
        let stream = try Synthetic.stream(Synthetic.activity(elapsed: 7, samples: samples))
        expectValues(stream.distance, [0, 10, 20, 30, 40, 50, 60])
        // Every forward difference is 10 m. Second 6 has nothing ahead of it.
        expectValues(stream.speed, [10, 10, 10, 10, 10, 10, nil])
        // Second 0 uses 0 and 10, both measured. Seconds 1, 2 and 3 each use
        // at least one of the filled 20 and 30. Seconds 4 and 5 are measured.
        #expect(stream.speed.quality == [
            measured, interpolated, interpolated, interpolated, measured, measured, missing,
        ])
    }
}
