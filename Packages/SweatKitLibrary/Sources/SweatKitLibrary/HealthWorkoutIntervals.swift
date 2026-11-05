import Foundation
import SweatKitModel

/// Health event intervals, kept separate from computed kilometre splits.
public enum HealthWorkoutIntervals {
    /// Legacy zero-duration lap events mark an end, with the previous lap's
    /// end (or workout start) as their start. Modern laps carry both bounds;
    /// preserve their gaps rather than extending them to fill the workout.
    public static func laps(_ intervals: [DateInterval], within workout: DateInterval) -> [RecordedLap] {
        var previousEnd = workout.start
        var result: [RecordedLap] = []
        for interval in ordered(intervals) {
            let start = interval.duration == 0 ? previousEnd : interval.start
            let end = interval.end
            guard start >= workout.start, end <= workout.end,
                  start >= previousEnd, end > start else { continue }
            result.append(RecordedLap(start: start, end: end))
            previousEnd = end
        }
        return result
    }

    /// Segments may overlap; never silently turn them into a lap partition.
    public static func segments(_ intervals: [DateInterval], within workout: DateInterval) -> [RecordedLap] {
        ordered(intervals).compactMap {
            guard $0.duration > 0, $0.start >= workout.start, $0.end <= workout.end else { return nil }
            return RecordedLap(start: $0.start, end: $0.end)
        }
    }

    private static func ordered(_ intervals: [DateInterval]) -> [DateInterval] {
        Array(Set(intervals)).sorted { ($0.start, $0.end) < ($1.start, $1.end) }
    }
}
