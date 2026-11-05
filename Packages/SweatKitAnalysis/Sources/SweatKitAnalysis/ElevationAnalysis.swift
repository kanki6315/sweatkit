import SweatKitModel

/// Ascent and descent, and where each climb was counted.
struct Elevation {
    /// Metres climbed.
    var ascent = 0.0
    /// Metres descended, as a positive number.
    var descent = 0.0
    /// Each counted climb: the second at which it was counted and its
    /// metres. They add up to `ascent`.
    var climbs: [(second: Int, gain: Double)] = []
}

extension StreamAnalysis {
    /// Summed altitude change with hysteresis, over every second that has
    /// altitude.
    ///
    /// The reference is the first altitude. A later altitude that differs
    /// from the reference by `AnalysisRules.elevationHysteresis` or more adds
    /// the whole difference to ascent or descent and becomes the reference.
    func elevation() -> Metric<Elevation> {
        var reference: Double?
        var result = Elevation()
        for (second, value) in altitude.enumerated() {
            guard let value else { continue }
            guard let from = reference else {
                reference = value
                continue
            }
            let change = value - from
            if change >= AnalysisRules.elevationHysteresis {
                result.ascent += change
                result.climbs.append((second: second, gain: change))
                reference = value
            } else if -change >= AnalysisRules.elevationHysteresis {
                result.descent -= change
                reference = value
            }
        }
        guard reference != nil else { return .unavailable(.noAltitude) }
        return .available(result)
    }

    /// The last value the cumulative distance channel has.
    func totalDistance() -> Metric<Double> {
        guard let last = distance.last(where: { $0 != nil }), let metres = last else {
            return .unavailable(.noDistance)
        }
        return .available(metres)
    }
}
