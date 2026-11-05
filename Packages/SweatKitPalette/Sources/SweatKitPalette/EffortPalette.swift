import SwiftUI

/// The colours of the data. They mean one thing everywhere: the map, the
/// timeline, charts and legends all read these, and nothing else in the
/// interface uses them.
///
/// Each ramp is in band order, so `ramp[band]` is the colour of that band.
/// The values are recorded in `DESIGN.md`, with the measurements behind them.
public enum EffortPalette {
    /// The seven power zones, from under 55% of threshold power to over 150%.
    ///
    /// Blue below threshold, yellow at it, warm above it, so a route shows
    /// which side of threshold it was ridden on without a legend.
    public static let power: [RampColor] = [
        RampColor(hex: 0x184998),
        RampColor(hex: 0x0E89D6),
        RampColor(hex: 0x65CBE3),
        RampColor(hex: 0xF8E94C),
        RampColor(hex: 0xFE9823),
        RampColor(hex: 0xEA5202),
        RampColor(hex: 0xBA0329),
    ]

    /// The five heart-rate zones, from under 81% of threshold heart rate to
    /// 100% and over.
    ///
    /// Five of the power colours, so the meaning carries over: the fourth
    /// zone, just under threshold, is the yellow, and the fifth, at or above
    /// threshold, is warm.
    public static let heartRate: [RampColor] = [power[0], power[1], power[2], power[3], power[5]]

    /// Five bands of pace or speed within one activity's own range, from
    /// slowest to fastest. The same colours as heart rate: warmer is harder.
    public static let pace: [RampColor] = heartRate

    /// The five gradient bands: descent, flat, and climbs of 2 to 5%, 5 to
    /// 8% and over 8%.
    ///
    /// Terrain, not effort, so it has its own colours. The bands differ in
    /// lightness as well as hue, which is what keeps them apart for
    /// colour-blind eyes.
    public static let gradient: [RampColor] = [
        RampColor(hex: 0x1B8FA5),
        RampColor(hex: 0xE0DED7),
        RampColor(hex: 0xE6B14E),
        RampColor(hex: 0xC3610D),
        RampColor(hex: 0x6D2A1A),
    ]

    /// The outline drawn under a coloured line on the map. No ramp holds
    /// its contrast on both dark and bright ground without one.
    public static let lineCasing = RampColor(hex: 0x0B0B0B)
    /// The opacity of `lineCasing`.
    public static let lineCasingOpacity = 0.55
}
