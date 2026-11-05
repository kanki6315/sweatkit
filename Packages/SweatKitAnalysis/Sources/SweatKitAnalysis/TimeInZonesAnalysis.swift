import SweatKitModel

extension StreamAnalysis {
    /// Seconds in each of the seven power zones, against the threshold power
    /// in effect on the activity date. Cycling only: the zones are shares of
    /// cycling threshold power, which a power reading on foot is not
    /// comparable with.
    func timeInPowerZones() -> Metric<TimeInZones> {
        guard sport == .cycling else { return .unavailable(.notDefinedForSport) }
        guard power.hasValues else { return .unavailable(.noPower) }
        guard let threshold = thresholdPower else { return .unavailable(.noThresholdPower) }
        guard threshold != 0 else { return .unavailable(.zeroDenominator) }
        return .available(timeInZones(power, scheme: .power, threshold: threshold))
    }

    /// Seconds in each of the five heart-rate zones, against the profile's
    /// threshold heart rate.
    func timeInHeartRateZones() -> Metric<TimeInZones> {
        guard heartRate.hasValues else { return .unavailable(.noHeartRate) }
        guard let threshold = profile.thresholdHeartRate else { return .unavailable(.noThresholdHeartRate) }
        guard threshold != 0 else { return .unavailable(.zeroDenominator) }
        return .available(timeInZones(heartRate, scheme: .heartRate, threshold: threshold))
    }

    /// Seconds in each of the five gradient bands.
    func timeInGradientBands() -> Metric<TimeInZones> {
        guard gradient.hasValues else { return .unavailable(.noGradient) }
        return .available(timeInZones(gradient, scheme: .gradient, threshold: nil))
    }

    /// Every second of the stream, counted once: in the zone of its value,
    /// or in the missing bucket. With a threshold, the value zoned is the
    /// reading divided by the threshold, formed by that one division.
    private func timeInZones(_ channel: [Double?], scheme: ZoneScheme, threshold: Double?) -> TimeInZones {
        var seconds = Array(repeating: 0, count: scheme.zoneCount)
        var missing = 0
        for reading in channel {
            guard let reading else {
                missing += 1
                continue
            }
            let value = threshold.map { reading / $0 } ?? reading
            seconds[scheme.index(of: value)] += 1
        }
        return TimeInZones(seconds: seconds, missing: missing)
    }
}
