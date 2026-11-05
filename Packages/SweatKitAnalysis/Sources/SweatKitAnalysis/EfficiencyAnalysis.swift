import SweatKitModel

extension StreamAnalysis {
    /// Weighted power divided by average heart rate, on a bike.
    func cyclingEfficiency(weightedPower: Metric<Double>, averageHeartRate: Metric<Double>) -> Metric<Double> {
        guard sport == .cycling else { return .unavailable(.notDefinedForSport) }
        guard let weighted = weightedPower.value else { return weightedPower }
        guard let beats = averageHeartRate.value else { return averageHeartRate }
        guard beats != 0 else { return .unavailable(.zeroDenominator) }
        return .available(weighted / beats)
    }

    /// Average speed divided by average heart rate, both over the seconds
    /// that have both, on foot. Every such second of the stream is read,
    /// paused or not: the definition names no timer time.
    func onFootEfficiency() -> Metric<Double> {
        guard sport.family == .onFoot else { return .unavailable(.notDefinedForSport) }
        guard speed.hasValues else { return .unavailable(.noSpeed) }

        var speeds = Tally()
        var beats = Tally()
        for second in 0..<count {
            guard let metresPerSecond = speed[second], let rate = heartRate[second] else { continue }
            speeds.add(metresPerSecond)
            beats.add(rate)
        }
        guard let averageSpeed = speeds.mean, let averageHeartRate = beats.mean else {
            return .unavailable(.noHeartRate)
        }
        guard averageHeartRate != 0 else { return .unavailable(.zeroDenominator) }
        return .available(averageSpeed / averageHeartRate)
    }
}
