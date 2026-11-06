import Foundation
import SweatKitModel

/// The starting values of the spec's "Stream rules" and of the pause rules in
/// the "Time" table of "Analysis metrics". `StreamNormaliser` reads every
/// number from here.
public enum StreamRules {
    /// The version of the stream rules. Raise it whenever a rule or a value
    /// below changes, so stored streams are rebuilt.
    /// Version 3 excludes native samples at/after the actual fractional end.
    public static let version = 3

    /// The length of one grid step in seconds. The stream is a 1 Hz grid.
    public static let gridInterval: TimeInterval = 1

    /// The longest gap that is filled, in grid seconds. Longer gaps are missing.
    public static let longestFilledGap = 5

    /// With no pause events, an activity is treated as unpaused when its
    /// stated timer time is within this share of its elapsed time.
    public static let unpausedTolerance = 0.01

    /// The length in metres of the window the gradient is taken over,
    /// centred on the sample.
    public static let gradientWindow = 30.0

    /// The least travel in metres a gradient window must cover. Below it the
    /// gradient is missing.
    public static let gradientMinimumTravel = 5.0

    /// The mean radius of the Earth in metres, for the distance between two
    /// positions when speed is taken from position.
    public static let earthRadius = 6_371_008.8

    /// How a gap in a channel is filled.
    public enum GapFill: Hashable, Sendable {
        /// A straight line between the values on each side of the gap.
        case linear
        /// The value before the gap, repeated.
        case holdLast
        /// Not filled as a channel of its own.
        case none
    }

    /// How gaps of up to `longestFilledGap` seconds are filled in `channel`.
    ///
    /// The spec names six channels: position, altitude, distance and heart
    /// rate are linear, and power and cadence hold the last value. It names
    /// no method for the rest, so the list is read as complete:
    ///
    /// - Temperature is not filled.
    /// - Speed is not filled from its own neighbours. A second without a
    ///   recorded speed falls to the next source in the speed rule.
    /// - Gradient is derived from altitude and distance after they are filled.
    public static func gapFill(for channel: Channel) -> GapFill {
        switch channel {
        case .latitude, .longitude, .altitude, .distance, .heartRate: .linear
        case .power, .cadence: .holdLast
        case .speed, .temperature, .gradient, .runningStrideLength, .runningGroundContactTime, .runningVerticalOscillation: .none
        }
    }
}
