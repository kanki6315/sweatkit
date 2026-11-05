import SweatKitModel

/// The numbers in the spec's "Analysis metrics" section. Every one is a
/// starting value, kept here by name so it is tuned in one place.
public enum AnalysisRules {
    // MARK: Time

    /// Metres per second. An outdoor second on foot below this is stopped.
    public static let movingSpeedFloorOnFoot = 0.5
    /// Metres per second. An outdoor second on a bike below this is stopped.
    public static let movingSpeedFloorCycling = 1.0

    // MARK: Zones

    /// The lower bound of power zones 2 to 7, as a share of threshold power.
    public static let powerZoneLowerBounds = [0.55, 0.75, 0.90, 1.05, 1.20, 1.50]
    /// The lower bound of heart-rate zones 2 to 5, as a share of threshold
    /// heart rate.
    public static let heartRateZoneLowerBounds = [0.81, 0.90, 0.94, 1.00]
    /// The lower bound of the flat band and of the three climbing bands, as
    /// rise over run.
    public static let gradientBandLowerBounds = [-0.02, 0.02, 0.05, 0.08]

    // MARK: Power

    /// The length of a weighted-power window, in seconds.
    public static let weightedWindowSeconds = 30
    /// A weighted-power window is valid with at least this many seconds of power.
    public static let weightedWindowMinimumPresentSeconds = 24
    /// Weighted power needs at least this share of the possible windows to be valid.
    public static let weightedMinimumValidWindowShare = 0.90
    /// Weighted power needs at least this many seconds of power: 5 minutes.
    public static let weightedMinimumPowerSeconds = 300
    /// Coverage is shown beside average power when it is under this share.
    public static let averagePowerCoverageNoteBelow = 0.90
    /// Work is labelled "recorded work" when coverage is under this share.
    public static let recordedWorkCoverageBelow = 0.98
    /// A power-curve window is valid with at least this share of its seconds present.
    public static let curveMinimumPresentShare = 0.95
    /// A power-curve window shorter than this many seconds must be complete.
    public static let curveCompleteBelowSeconds = 20
    public static let joulesPerKilojoule = 1000.0

    // MARK: Heart rate and load

    /// Load from heart rate needs at least this heart-rate coverage.
    public static let heartRateLoadMinimumCoverage = 0.90
    /// The load of one hour at threshold.
    public static let loadPerHourAtThreshold = 100.0
    public static let secondsPerHour = 3600.0

    // MARK: Other

    /// Metres. A climb or descent ends once the altitude has turned back by
    /// this much, and a turn smaller than this is not counted.
    public static let elevationThreshold = 3.0
    /// Metres. The same for cycling, where real climbing dwarfs the wobble
    /// of the sensor.
    public static let cyclingElevationThreshold = 1.5
    /// Metres. The same for a virtual activity, whose altitude is computed
    /// and has no wobble, so every rise and fall counts.
    public static let virtualElevationThreshold = 0.0

    /// The elevation threshold for a recording. Virtual comes first, then
    /// cycling, and every other sport takes `elevationThreshold`.
    ///
    /// These are fitted to four recordings, one or two of each kind, so they
    /// are provisional until more history confirms them.
    public static func elevationThreshold(sport: Sport, isVirtual: Bool) -> Double {
        if isVirtual { return virtualElevationThreshold }
        return sport == .cycling ? cyclingElevationThreshold : elevationThreshold
    }
    /// Metres. The length of one split.
    public static let splitDistance = 1000.0
    /// Metres. The distances a best time is found for.
    public static let bestDistances = [1000.0, 5000.0, 10_000.0]
}

/// The version of each algorithm. A version goes up whenever its rule or one
/// of its numbers changes, which makes stored results stale.
public enum AlgorithmVersion {
    public static let time = 1
    public static let distance = 1
    public static let elevation = 2
    public static let zones = 1
    /// Coverage, average power and work.
    public static let power = 1
    /// Weighted power, intensity and variability.
    public static let weightedPower = 1
    public static let powerCurve = 1
    /// Heart-rate coverage and average heart rate.
    public static let heartRate = 1
    /// Load from power, load from heart rate and the choice between them.
    public static let load = 1
    public static let efficiency = 1
    /// Splits carry ascent, so this follows `elevation`.
    public static let splits = 2
    public static let bestDistances = 1
}
