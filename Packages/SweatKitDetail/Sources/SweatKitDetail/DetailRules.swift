/// Every number the detail preparation uses that is not already a rule of
/// another package. None of them is written inline anywhere else.
public enum DetailRules {
    /// Seconds of the trailing window that power is smoothed over before it
    /// is coloured: the spec's "10-second smoothed power".
    public static let bandSmoothingSeconds = 10

    /// Seconds of the trailing window behind the cursor's power: the spec's
    /// "3-second power".
    public static let cursorPowerSeconds = 3

    /// The number of pace or speed bands. The spec says only "relative to the
    /// activity's own range". Five matches the heart-rate zones and the
    /// gradient bands, so every zoned overlay but power has the same number
    /// of colours.
    public static let paceBandCount = 5

    /// The share of the activity's moving seconds that the slowest band's top
    /// and the fastest band's bottom are taken at. Taking the activity's
    /// range between its 10th and 90th percentiles keeps one GPS spike or a
    /// minute of shuffling from squeezing every other second into one band.
    public static let paceRangeLowerPercentile = 0.10
    public static let paceRangeUpperPercentile = 0.90
}
