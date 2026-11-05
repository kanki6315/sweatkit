import SweatKitIngest
import SweatKitModel
import Testing

/// The spec's starting values, pinned so that changing one is a deliberate
/// act that also raises the rules version and revisits the tests built on it.
@Suite struct StreamRulesTests {
    @Test func startingValuesAreTheSpecs() {
        // "The analysis stream is a 1 Hz grid."
        #expect(StreamRules.gridInterval == 1)
        // "Gaps of up to 5 seconds are filled."
        #expect(StreamRules.longestFilledGap == 5)
        // "...the stated timer time is within 1% of elapsed time."
        #expect(StreamRules.unpausedTolerance == 0.01)
        // "...over a 30 m window centred on the sample."
        #expect(StreamRules.gradientWindow == 30)
        // "...when the window covers less than 5 m of travel."
        #expect(StreamRules.gradientMinimumTravel == 5)
    }

    @Test func runningFormChannelsRequireVersionTwo() {
        #expect(StreamRules.version == 2)
    }

    /// "Position, altitude, distance and heart rate are filled linearly.
    /// Power and cadence hold the last value."
    @Test func eachNamedChannelHasItsFill() {
        for channel in [Channel.latitude, .longitude, .altitude, .distance, .heartRate] {
            #expect(StreamRules.gapFill(for: channel) == .linear, "\(channel)")
        }
        for channel in [Channel.power, .cadence] {
            #expect(StreamRules.gapFill(for: channel) == .holdLast, "\(channel)")
        }
    }

    /// Reading: the spec names no fill for these, so they have none.
    @Test func channelsTheSpecDoesNotNameAreNotFilled() {
        for channel in [Channel.speed, .temperature, .gradient, .runningStrideLength, .runningGroundContactTime, .runningVerticalOscillation] {
            #expect(StreamRules.gapFill(for: channel) == StreamRules.GapFill.none, "\(channel)")
        }
    }
}
