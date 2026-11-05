import Foundation
import SweatKitModel

extension StreamAnalysis {
    /// The fastest time over each distance in `AnalysisRules.bestDistances`,
    /// for walking and running.
    func bestDistances() -> [BestDistance] {
        let blocked: UnavailableReason? =
            if sport != .walking && sport != .running {
                .notDefinedForSport
            } else if timer == nil {
                .pausePositionsUnknown
            } else if !distance.hasValues {
                .noDistance
            } else {
                nil
            }
        guard blocked == nil, let timer else {
            let reason = blocked ?? .pausePositionsUnknown
            return AnalysisRules.bestDistances.map { BestDistance(distance: $0, time: .unavailable(reason)) }
        }

        return AnalysisRules.bestDistances.map { metres in
            let seconds = fewestTimerSeconds(covering: metres, timer: timer)
            return BestDistance(
                distance: metres,
                time: seconds.map { .available(TimeInterval($0)) } ?? .unavailable(.distanceNotCovered)
            )
        }
    }

    /// The fewest timer seconds between two seconds of the stream whose
    /// cumulative distances differ by at least `metres`, or nil when no two
    /// do. From second i to a later second j the time is the number of timer
    /// seconds in `i..<j`.
    ///
    /// For an end second j the best start is the latest earlier second that
    /// is far enough back. A start is worth keeping only while no later
    /// second has a distance as small, so the kept starts rise in distance
    /// and the latest one far enough back is found by bisection. That holds
    /// whether or not the channel ever goes down.
    private func fewestTimerSeconds(covering metres: Double, timer: TimerGrid) -> Int? {
        var starts: [(second: Int, distance: Double)] = []
        var best: Int?
        for (second, value) in distance.enumerated() {
            guard let value else { continue }

            // The kept starts whose distance is at most value - metres are a
            // prefix. Find its length.
            var low = 0
            var high = starts.count
            while low < high {
                let middle = (low + high) / 2
                if value - starts[middle].distance >= metres {
                    low = middle + 1
                } else {
                    high = middle
                }
            }
            if low > 0 {
                let time = timer.secondsBefore[second] - timer.secondsBefore[starts[low - 1].second]
                if best.map({ time < $0 }) ?? true {
                    best = time
                }
            }

            while let latest = starts.last, latest.distance >= value {
                starts.removeLast()
            }
            starts.append((second: second, distance: value))
        }
        return best
    }
}
