import Foundation
import SweatKitModel

extension StreamAnalysis {
    /// The spec's "Power, cycling only" table.
    func powerMetrics() -> PowerMetrics {
        guard sport == .cycling else { return PowerMetrics(unavailable: .notDefinedForSport) }

        let coverage = coverage(of: power)
        let average = average(of: power, orElse: .noPower)
        let weighted = weightedPower()
        let intensity = intensity(weightedPower: weighted)
        return PowerMetrics(
            coverage: coverage,
            average: average,
            averageShowsCoverage: average.value != nil
                && (coverage.value.map { $0 < AnalysisRules.averagePowerCoverageNoteBelow } ?? false),
            weighted: weighted,
            intensity: intensity,
            load: loadFromPower(intensity: intensity),
            variability: variability(weightedPower: weighted, averagePower: average),
            work: work(coverage: coverage)
        )
    }

    /// Weighted power over timer time, with paused spans removed and the
    /// series joined.
    private func weightedPower() -> Metric<Double> {
        guard let timer else { return .unavailable(.pausePositionsUnknown) }
        guard power.hasValues else { return .unavailable(.noPower) }

        let joined = timer.seconds.map { power[$0] }
        let sums = PrefixSums(joined)
        guard sums.present(in: 0..<joined.count) >= AnalysisRules.weightedMinimumPowerSeconds else {
            return .unavailable(.tooLittlePower)
        }

        // A window starts at every timer second that leaves room for a whole
        // window, so T timer seconds have T - 29 possible windows.
        let window = AnalysisRules.weightedWindowSeconds
        let possible = joined.count - window + 1
        guard possible > 0 else { return .unavailable(.tooFewValidWindows) }

        var valid = 0
        var sumOfFourthPowers = 0.0
        for start in 0..<possible {
            let span = start..<(start + window)
            let present = sums.present(in: span)
            guard present >= AnalysisRules.weightedWindowMinimumPresentSeconds, present > 0 else { continue }
            let mean = sums.sum(in: span) / Double(present)
            let square = mean * mean
            sumOfFourthPowers += square * square
            valid += 1
        }
        guard valid > 0, Double(valid) / Double(possible) >= AnalysisRules.weightedMinimumValidWindowShare else {
            return .unavailable(.tooFewValidWindows)
        }
        return .available(pow(sumOfFourthPowers / Double(valid), 0.25))
    }

    /// Weighted power divided by the threshold power in effect on the
    /// activity date.
    ///
    /// Only a threshold of exactly zero is a zero denominator. A negative
    /// threshold is not checked here: the profile is trusted to hold a
    /// positive number.
    private func intensity(weightedPower: Metric<Double>) -> Metric<Double> {
        guard let weighted = weightedPower.value else { return weightedPower }
        guard let threshold = thresholdPower else { return .unavailable(.noThresholdPower) }
        guard threshold != 0 else { return .unavailable(.zeroDenominator) }
        return .available(weighted / threshold)
    }

    /// Timer hours times intensity squared times 100.
    private func loadFromPower(intensity: Metric<Double>) -> Metric<Double> {
        guard let value = intensity.value else { return intensity }
        // Intensity is only available with known pause positions.
        guard let timer else { return .unavailable(.pausePositionsUnknown) }
        let hours = Double(timer.timerSeconds) / AnalysisRules.secondsPerHour
        return .available(hours * value * value * AnalysisRules.loadPerHourAtThreshold)
    }

    /// Weighted power divided by average power.
    private func variability(weightedPower: Metric<Double>, averagePower: Metric<Double>) -> Metric<Double> {
        guard let weighted = weightedPower.value else { return weightedPower }
        guard let average = averagePower.value else { return averagePower }
        guard average != 0 else { return .unavailable(.zeroDenominator) }
        return .available(weighted / average)
    }

    /// The sum of power over every second that has it, in kilojoules.
    ///
    /// It is "recorded work" when pause positions are unknown or coverage is
    /// under `AnalysisRules.recordedWorkCoverageBelow`. When timer time is
    /// zero, coverage has no value to be under that share, so the literal
    /// reading leaves the label off.
    private func work(coverage: Metric<Double>) -> Metric<Work> {
        guard power.hasValues else { return .unavailable(.noPower) }
        let joules = power.reduce(0.0) { $0 + ($1 ?? 0) }
        let lowCoverage = coverage.value.map { $0 < AnalysisRules.recordedWorkCoverageBelow } ?? false
        return .available(Work(
            kilojoules: joules / AnalysisRules.joulesPerKilojoule,
            isRecordedOnly: timer == nil || lowCoverage
        ))
    }

    /// The best mean power for each duration, in the order given.
    func powerCurve(durations: [Int]) -> [PowerCurvePoint] {
        let blocked: UnavailableReason? =
            if sport != .cycling {
                .notDefinedForSport
            } else if timer == nil {
                .pausePositionsUnknown
            } else if !power.hasValues {
                .noPower
            } else {
                nil
            }
        guard blocked == nil, let timer else {
            let reason = blocked ?? .pausePositionsUnknown
            return durations.map { PowerCurvePoint(duration: $0, power: .unavailable(reason)) }
        }

        let sums = PrefixSums(power)
        return durations.map { duration in
            let best = bestMean(duration: duration, spans: timer.spans, sums: sums)
            return PowerCurvePoint(
                duration: duration,
                power: best.map(Metric.available) ?? .unavailable(.noValidWindow)
            )
        }
    }

    /// The best mean over the valid windows of `duration` seconds, or nil
    /// when there is none. A window must sit inside one unbroken timer span.
    private func bestMean(duration: Int, spans: [Range<Int>], sums: PrefixSums) -> Double? {
        guard duration >= 1 else { return nil }
        var best: Double?
        for span in spans where span.count >= duration {
            for start in span.lowerBound...(span.upperBound - duration) {
                let window = start..<(start + duration)
                let present = sums.present(in: window)
                guard Self.isValidCurveWindow(duration: duration, present: present) else { continue }
                let mean = sums.sum(in: window) / Double(present)
                if best.map({ mean > $0 }) ?? true {
                    best = mean
                }
            }
        }
        return best
    }

    /// Whether a power-curve window of `duration` seconds, `present` of which
    /// have power, is valid. The share is formed by one division and compared
    /// with the bound as it is, so 19 of 20 is exactly 95%.
    static func isValidCurveWindow(duration: Int, present: Int) -> Bool {
        guard present > 0 else { return false }
        if duration < AnalysisRules.curveCompleteBelowSeconds {
            return present == duration
        }
        return Double(present) / Double(duration) >= AnalysisRules.curveMinimumPresentShare
    }
}

/// Running totals of a channel, so the sum and the number of present values
/// of any stretch cost two subtractions.
struct PrefixSums {
    private let sums: [Double]
    private let counts: [Int]

    init(_ channel: [Double?]) {
        var sums = [0.0]
        var counts = [0]
        sums.reserveCapacity(channel.count + 1)
        counts.reserveCapacity(channel.count + 1)
        var sum = 0.0
        var count = 0
        for value in channel {
            if let value {
                sum += value
                count += 1
            }
            sums.append(sum)
            counts.append(count)
        }
        self.sums = sums
        self.counts = counts
    }

    /// The sum of the present values in `range`.
    func sum(in range: Range<Int>) -> Double {
        sums[range.upperBound] - sums[range.lowerBound]
    }

    /// The number of present values in `range`.
    func present(in range: Range<Int>) -> Int {
        counts[range.upperBound] - counts[range.lowerBound]
    }
}
