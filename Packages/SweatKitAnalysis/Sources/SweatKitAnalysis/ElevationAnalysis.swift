import SweatKitModel

/// Ascent and descent, and where each rise was counted.
struct Elevation {
    /// Metres climbed.
    var ascent = 0.0
    /// Metres descended, as a positive number.
    var descent = 0.0
    /// Each counted rise: the second at which it was counted and its metres.
    /// They add up to `ascent`.
    var climbs: [(second: Int, gain: Double)] = []
}

/// Which way the altitude is heading.
private enum Leg {
    /// No climb or descent has started. Holds the lowest and highest
    /// altitudes so far.
    case undecided(low: Double, high: Double)
    /// Climbing. Holds the highest altitude of the climb.
    case up(peak: Double)
    /// Descending. Holds the lowest altitude of the descent.
    case down(valley: Double)
}

extension StreamAnalysis {
    /// Ascent and descent by peak and valley, over every second that has
    /// altitude.
    ///
    /// A climb runs from a low point to the next high point. It starts to
    /// count once the altitude is the threshold or more above the low point,
    /// and from then on every new high adds to it. It ends once the altitude
    /// has fallen the threshold or more below the high point, which starts a
    /// descent measured from that high point. A turn smaller than the
    /// threshold neither ends the climb nor counts. Descents mirror this.
    ///
    /// Before the first climb or descent, the low and high points are the
    /// lowest and highest altitudes so far. The threshold comes from
    /// `AnalysisRules.elevationThreshold(sport:isVirtual:)`, and a turn of
    /// exactly the threshold counts.
    func elevation() -> Metric<Elevation> {
        let threshold = AnalysisRules.elevationThreshold(sport: sport, isVirtual: isVirtual)
        var leg: Leg?
        var result = Elevation()

        func rise(_ gain: Double, at second: Int) {
            result.ascent += gain
            result.climbs.append((second: second, gain: gain))
        }

        for (second, value) in altitude.enumerated() {
            guard let value else { continue }
            switch leg {
            case nil:
                leg = .undecided(low: value, high: value)
            case .undecided(let low, let high):
                if value > low, value - low >= threshold {
                    rise(value - low, at: second)
                    leg = .up(peak: value)
                } else if value < high, high - value >= threshold {
                    result.descent += high - value
                    leg = .down(valley: value)
                } else {
                    leg = .undecided(low: min(low, value), high: max(high, value))
                }
            case .up(let peak):
                if value > peak {
                    rise(value - peak, at: second)
                    leg = .up(peak: value)
                } else if value < peak, peak - value >= threshold {
                    result.descent += peak - value
                    leg = .down(valley: value)
                }
            case .down(let valley):
                if value < valley {
                    result.descent += valley - value
                    leg = .down(valley: value)
                } else if value > valley, value - valley >= threshold {
                    rise(value - valley, at: second)
                    leg = .up(peak: value)
                }
            }
        }
        guard leg != nil else { return .unavailable(.noAltitude) }
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
