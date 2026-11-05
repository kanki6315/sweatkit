import Foundation
import SweatKitModel

extension StreamAnalysis {
    /// One entry per kilometre, for walking, running and hiking.
    ///
    /// The activity's distance, the last value of the cumulative channel,
    /// sets the number of splits: it falls in the last one. A second belongs
    /// to the split its own distance falls in, so one exactly on a kilometre
    /// mark opens the next split, and an activity that ends exactly on a mark
    /// ends with a split of zero distance. A second with missing distance
    /// takes the last distance before it, and one before any distance belongs
    /// to split 0.
    ///
    /// A cumulative distance never goes down. If the channel does, a second
    /// whose distance falls outside the splits is put in the nearest one.
    ///
    /// - Parameter climbs: the activity's counted climbs, or nil when the
    ///   stream has no altitude.
    func splits(climbs: [(second: Int, gain: Double)]?) -> Metric<[Split]> {
        guard sport.family == .onFoot else { return .unavailable(.notDefinedForSport) }
        guard let timer else { return .unavailable(.pausePositionsUnknown) }
        guard let total = totalDistance().value else { return .unavailable(.noDistance) }

        let length = AnalysisRules.splitDistance
        let last = Self.splitIndex(of: total, length: length)

        // The split of every second, carrying the last distance forward.
        var splitOfSecond: [Int] = []
        splitOfSecond.reserveCapacity(count)
        var current = 0
        for value in distance {
            if let value {
                current = min(Self.splitIndex(of: value, length: length), last)
            }
            splitOfSecond.append(current)
        }

        var durations = Array(repeating: 0, count: last + 1)
        var beats = Array(repeating: Tally(), count: last + 1)
        for second in timer.seconds {
            let split = splitOfSecond[second]
            durations[split] += 1
            beats[split].add(heartRate[second])
        }

        var gains = Array(repeating: 0.0, count: last + 1)
        for climb in climbs ?? [] {
            gains[splitOfSecond[climb.second]] += climb.gain
        }

        return .available((0...last).map { index in
            let metres = index < last ? length : max(total - Double(index) * length, 0)
            let duration = TimeInterval(durations[index])
            return Split(
                index: index,
                distance: metres,
                duration: duration,
                pace: metres > 0 ? .available(duration / (metres / length)) : .unavailable(.zeroDenominator),
                averageHeartRate: beats[index].mean.map(Metric.available) ?? .unavailable(.noHeartRate),
                ascent: climbs == nil ? .unavailable(.noAltitude) : .available(gains[index])
            )
        })
    }

    /// The split a cumulative distance falls in, counted from 0. A distance
    /// exactly on a mark belongs to the split the mark opens.
    private static func splitIndex(of metres: Double, length: Double) -> Int {
        guard metres.isFinite, metres > 0, length > 0 else { return 0 }
        return Int((metres / length).rounded(.down))
    }
}
