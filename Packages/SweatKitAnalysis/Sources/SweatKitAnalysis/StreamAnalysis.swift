import Foundation
import SweatKitModel

/// One activity's stream, laid out for the metric algorithms. Each metric is
/// a method in an extension, in the file named after it.
struct StreamAnalysis {
    let sport: Sport
    let isIndoor: Bool
    let profile: AthleteProfile
    let activityDate: Date

    /// Elapsed seconds: the length of the grid.
    let count: Int
    /// The timer seconds, or nil when pause positions are unknown.
    let timer: TimerGrid?
    /// The timer time the original states, when pause positions are unknown.
    let statedTimerTime: TimeInterval?

    /// One value per grid second, nil where the channel is missing.
    let power: [Double?]
    let heartRate: [Double?]
    let speed: [Double?]
    let altitude: [Double?]
    let distance: [Double?]
    let gradient: [Double?]

    /// A stream whose `count` is negative is read as empty. A channel shorter
    /// than `count` is missing past its end and one longer is cut, so an
    /// inconsistent stream cannot read out of bounds.
    init(input: ActivityInput, stream: AnalysisStream) {
        sport = input.sport
        isIndoor = input.isIndoor
        profile = input.profile
        activityDate = input.activityDate

        let count = max(stream.count, 0)
        self.count = count
        switch stream.pauses {
        case .known(let paused):
            timer = TimerGrid(count: count, paused: paused)
            statedTimerTime = nil
        case .unknown(let stated):
            timer = nil
            statedTimerTime = stated
        }

        power = stream.power.samples(count: count)
        heartRate = stream.heartRate.samples(count: count)
        speed = stream.speed.samples(count: count)
        altitude = stream.altitude.samples(count: count)
        distance = stream.distance.samples(count: count)
        gradient = stream.gradient.samples(count: count)
    }

    /// The threshold power in effect on the activity date, or nil when none was.
    var thresholdPower: Double? {
        profile.thresholdPower(on: activityDate)
    }

    func metrics() -> ActivityMetrics {
        let power = powerMetrics()
        let heartRate = heartRateMetrics()
        let climbing = elevation()
        return ActivityMetrics(
            time: timeMetrics(),
            distance: totalDistance(),
            ascent: climbing.map(\.ascent),
            descent: climbing.map(\.descent),
            power: power,
            heartRate: heartRate,
            load: activityLoad(fromPower: power.load, fromHeartRate: heartRate.load),
            promptsForThresholdPower: power.weighted.value != nil && thresholdPower == nil,
            timeInPowerZones: timeInPowerZones(),
            timeInHeartRateZones: timeInHeartRateZones(),
            timeInGradientBands: timeInGradientBands(),
            cyclingEfficiency: cyclingEfficiency(weightedPower: power.weighted, averageHeartRate: heartRate.average),
            onFootEfficiency: onFootEfficiency(),
            splits: splits(climbs: climbing.value?.climbs),
            bestDistances: bestDistances()
        )
    }

    // MARK: Shared pieces

    /// The share of timer seconds at which `channel` has a value.
    func coverage(of channel: [Double?]) -> Metric<Double> {
        guard let timer else { return .unavailable(.pausePositionsUnknown) }
        guard timer.timerSeconds > 0 else { return .unavailable(.zeroDenominator) }
        let present = timer.seconds.count { channel[$0] != nil }
        return .available(Double(present) / Double(timer.timerSeconds))
    }

    /// The mean of `channel` over every second of the stream that has a
    /// value, paused or not, or `reason` when none has.
    func average(of channel: [Double?], orElse reason: UnavailableReason) -> Metric<Double> {
        var tally = Tally()
        for value in channel {
            tally.add(value)
        }
        return tally.mean.map(Metric.available) ?? .unavailable(reason)
    }
}

/// A sum of present values and how many there were. Missing values are left
/// out of both, and are never counted as zero.
struct Tally {
    private(set) var sum = 0.0
    private(set) var count = 0

    mutating func add(_ value: Double?) {
        guard let value else { return }
        sum += value
        count += 1
    }

    /// The sum divided by the number of present values, or nil when there
    /// were none.
    var mean: Double? {
        count > 0 ? sum / Double(count) : nil
    }
}

extension Series {
    /// The first `count` seconds of the channel, nil where a value is missing
    /// or the channel has ended.
    func samples(count: Int) -> [Double?] {
        let stored = min(values.count, quality.count)
        return (0..<count).map { $0 < stored ? self[$0] : nil }
    }
}

extension [Double?] {
    /// Whether any second has a value.
    var hasValues: Bool {
        contains { $0 != nil }
    }
}

extension Metric {
    /// The same metric with its value transformed. A reason passes through.
    func map<Other>(_ transform: (Value) -> Other) -> Metric<Other> {
        switch self {
        case .available(let value): .available(transform(value))
        case .unavailable(let reason): .unavailable(reason)
        }
    }
}
