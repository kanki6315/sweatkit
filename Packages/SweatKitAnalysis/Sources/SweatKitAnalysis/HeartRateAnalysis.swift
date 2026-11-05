import SweatKitModel

extension StreamAnalysis {
    /// The spec's "Heart rate" table, and average heart rate.
    func heartRateMetrics() -> HeartRateMetrics {
        let coverage = coverage(of: heartRate)
        return HeartRateMetrics(
            coverage: coverage,
            average: average(of: heartRate, orElse: .noHeartRate),
            load: loadFromHeartRate(coverage: coverage)
        )
    }

    /// Each timer second with heart rate scores (heart rate / threshold heart
    /// rate) squared. Load is the sum, divided by 3,600, times 100.
    ///
    /// As with threshold power, only a threshold of exactly zero is a zero
    /// denominator.
    private func loadFromHeartRate(coverage: Metric<Double>) -> Metric<Double> {
        guard let timer, let share = coverage.value else {
            return .unavailable(coverage.reason ?? .pausePositionsUnknown)
        }
        guard heartRate.hasValues else { return .unavailable(.noHeartRate) }
        guard share >= AnalysisRules.heartRateLoadMinimumCoverage else {
            return .unavailable(.lowHeartRateCoverage)
        }
        guard let threshold = profile.thresholdHeartRate else { return .unavailable(.noThresholdHeartRate) }
        guard threshold != 0 else { return .unavailable(.zeroDenominator) }

        var score = 0.0
        for second in timer.seconds {
            guard let beats = heartRate[second] else { continue }
            let ratio = beats / threshold
            score += ratio * ratio
        }
        return .available(score / AnalysisRules.secondsPerHour * AnalysisRules.loadPerHourAtThreshold)
    }

    /// The spec's "Which load an activity gets": from power when intensity
    /// is available, otherwise from heart rate, otherwise unavailable with
    /// the reason load from heart rate is unavailable.
    func activityLoad(fromPower: Metric<Double>, fromHeartRate: Metric<Double>) -> Metric<ActivityLoad> {
        if let value = fromPower.value {
            return .available(ActivityLoad(value: value, source: .power))
        }
        return fromHeartRate.map { ActivityLoad(value: $0, source: .heartRate) }
    }
}
