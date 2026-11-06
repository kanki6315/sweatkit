import SweatKitModel

/// Computed from the current stream when preparing detail; never persisted.
public struct CadenceSummary: Sendable {
    public let average: Metric<Double>
    public let coverage: Metric<Double>

    /// Time-weighted mean of available 1 Hz timer samples, including measured
    /// zeroes and interpolated values. Missing/invalid samples are excluded
    /// from the mean, not counted as zero. Units are already steps/min on foot
    /// or rpm on a bike; no further doubling is performed here.
    public static func calculate(stream: AnalysisStream) -> Self {
        guard case .known(let paused) = stream.pauses else {
            return Self(average: .unavailable(.pausePositionsUnknown), coverage: .unavailable(.pausePositionsUnknown))
        }
        let timer = TimerGrid(count: max(0, stream.count), paused: paused)
        guard timer.timerSeconds > 0 else {
            return Self(average: .unavailable(.zeroDenominator), coverage: .unavailable(.zeroDenominator))
        }
        let values = stream.cadence.samples(count: max(0, stream.count))
        var tally = Tally()
        for second in timer.seconds {
            guard let value = values[second], value.isFinite, value >= 0 else { continue }
            tally.add(value)
        }
        return Self(average: tally.mean.map(Metric.available) ?? .unavailable(.noCadence),
                    coverage: .available(Double(tally.count) / Double(timer.timerSeconds)))
    }
}

extension UnavailableReason {
    public static let noCadence = UnavailableReason(rawValue: "analysis.noCadence")
}
