import SweatKitModel

/// Why an analysis metric is unavailable.
extension UnavailableReason {
    /// The activity has no stream. Only the three times can come from the
    /// stated metadata.
    public static let noStream = UnavailableReason(rawValue: "analysis.noStream")
    /// The original does not state the figure, and nothing else can supply it.
    public static let notStated = UnavailableReason(rawValue: "analysis.notStated")
    /// Pause data is incomplete, and the metric needs to know which seconds
    /// were running.
    public static let pausePositionsUnknown = UnavailableReason(rawValue: "analysis.pausePositionsUnknown")
    /// The metric is not defined for this sport: power off a bike, on-foot
    /// efficiency and splits off foot, best distances outside walking and
    /// running.
    public static let notDefinedForSport = UnavailableReason(rawValue: "analysis.notDefinedForSport")

    /// The power channel has no measured or interpolated value.
    public static let noPower = UnavailableReason(rawValue: "analysis.noPower")
    /// The heart-rate channel has no measured or interpolated value.
    public static let noHeartRate = UnavailableReason(rawValue: "analysis.noHeartRate")
    /// The speed channel has no measured or interpolated value.
    public static let noSpeed = UnavailableReason(rawValue: "analysis.noSpeed")
    /// The altitude channel has no measured or interpolated value.
    public static let noAltitude = UnavailableReason(rawValue: "analysis.noAltitude")
    /// The distance channel has no measured or interpolated value.
    public static let noDistance = UnavailableReason(rawValue: "analysis.noDistance")
    /// The gradient channel has no measured or interpolated value.
    public static let noGradient = UnavailableReason(rawValue: "analysis.noGradient")

    /// Fewer timer seconds have power than weighted power needs.
    public static let tooLittlePower = UnavailableReason(rawValue: "analysis.tooLittlePower")
    /// Too small a share of the possible 30-second windows is valid.
    public static let tooFewValidWindows = UnavailableReason(rawValue: "analysis.tooFewValidWindows")
    /// No valid power-curve window of the duration exists.
    public static let noValidWindow = UnavailableReason(rawValue: "analysis.noValidWindow")
    /// No threshold power was in effect on the activity date.
    public static let noThresholdPower = UnavailableReason(rawValue: "analysis.noThresholdPower")
    /// The profile has neither a threshold heart rate nor a max heart rate.
    public static let noThresholdHeartRate = UnavailableReason(rawValue: "analysis.noThresholdHeartRate")
    /// Heart rate covers too little of timer time for a load.
    public static let lowHeartRateCoverage = UnavailableReason(rawValue: "analysis.lowHeartRateCoverage")
    /// The metric divides by a value that is zero.
    public static let zeroDenominator = UnavailableReason(rawValue: "analysis.zeroDenominator")
    /// The activity does not cover the distance.
    public static let distanceNotCovered = UnavailableReason(rawValue: "analysis.distanceNotCovered")
}
