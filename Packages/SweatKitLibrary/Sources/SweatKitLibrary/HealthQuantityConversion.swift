import Foundation
import SweatKitModel

/// Individual Health quantity intervals, expanded from quantity series by the
/// adapter. Values are interval totals for distance and steps, not rates.
public struct HealthQuantityInterval: Sendable {
    public var start: Date
    public var end: Date
    public var value: Double

    public init(start: Date, end: Date, value: Double) {
        self.start = start
        self.end = end
        self.value = value
    }
}

public enum HealthQuantityConversion {
    /// Accumulate recorded distance increments at their boundaries. Do not
    /// spread a workout summary over GPS points or invent samples in long gaps.
    /// The normaliser interpolates only its usual short gaps (up to 5 seconds).
    /// Overlapping intervals are ambiguous: omit the channel rather than count
    /// two sources twice. Callers scope queries to the workout's source.
    public static func distance(_ intervals: [HealthQuantityInterval]) -> [NativeSample] {
        guard let ordered = validated(intervals) else { return [] }
        var total = 0.0
        var output: [NativeSample] = []
        for interval in ordered {
            // Adjacent intervals share one boundary. Emitting it twice would
            // overweight it when the normaliser averages subsecond samples.
            if output.last?.timestamp != interval.start {
                output.append(NativeSample(timestamp: interval.start, distance: total))
            }
            total += interval.value
            output.append(NativeSample(timestamp: interval.end, distance: total))
        }
        return output
    }

    /// Steps divided by the observed interval, in steps/minute. Only short
    /// intervals describe cursor cadence; a long aggregate is not instantaneous
    /// cadence. Emit inside the interval, never beyond its end.
    public static func cadence(_ intervals: [HealthQuantityInterval]) -> [NativeSample] {
        guard let ordered = validated(intervals) else { return [] }
        return ordered.flatMap { interval -> [NativeSample] in
            let duration = interval.end.timeIntervalSince(interval.start)
            guard duration > 0, duration <= 5 else { return [] }
            return stride(from: 0.0, to: duration, by: 1).map {
                NativeSample(timestamp: interval.start.addingTimeInterval($0), cadence: interval.value * 60 / duration)
            }
        }
    }

    private static func validated(_ intervals: [HealthQuantityInterval]) -> [HealthQuantityInterval]? {
        let ordered = intervals.sorted {
            $0.start == $1.start ? $0.end < $1.end : $0.start < $1.start
        }
        var previousEnd: Date?
        for interval in ordered {
            guard interval.value.isFinite, interval.value >= 0, interval.end > interval.start,
                  previousEnd.map({ interval.start >= $0 }) ?? true else { return nil }
            previousEnd = interval.end
        }
        return ordered
    }
}
