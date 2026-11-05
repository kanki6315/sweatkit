import Foundation
import SweatKitModel

/// The timeline in words, for VoiceOver.
enum TimelineDescription {
    /// What the chart shows: the elevation range, the overlay and its range,
    /// and how many laps and stops there are.
    static func summary(
        elevation: ClosedRange<Double>?,
        overlay: (kind: TimelineOverlay.Kind, range: ClosedRange<Double>?)?,
        lapBoundaries: Int,
        stops: Int,
        sport: Sport,
        units: UnitSystem,
        locale: Locale = .current
    ) -> String {
        var sentences: [String] = []
        if let elevation {
            let low = StatFormatter.elevation(elevation.lowerBound, units: units, locale: locale)
            let high = StatFormatter.elevation(elevation.upperBound, units: units, locale: locale)
            sentences.append("Elevation from \(low.value) to \(high.spoken).")
        } else {
            sentences.append("No elevation data.")
        }
        if let overlay {
            let name = name(of: overlay.kind)
            if let range = overlay.range {
                let low = stat(range.lowerBound, kind: overlay.kind, sport: sport, units: units, locale: locale)
                let high = stat(range.upperBound, kind: overlay.kind, sport: sport, units: units, locale: locale)
                // Pace runs the other way from speed: the lowest speed is the
                // slowest pace.
                sentences.append(overlay.kind == .pace
                    ? "\(name) from \(low.spoken) to \(high.spoken)."
                    : "\(name) from \(low.value) to \(high.spoken).")
            } else {
                sentences.append("No \(name.lowercased()) data.")
            }
        }
        // A boundary starts each lap after the first.
        if lapBoundaries > 0 { sentences.append("\(lapBoundaries + 1) laps.") }
        if stops > 0 { sentences.append(stops == 1 ? "1 stop." : "\(stops) stops.") }
        return sentences.joined(separator: " ")
    }

    /// Where the cursor is: its distance when there is one, and its elapsed
    /// time.
    static func position(sample: Double, distance: [Double]?, units: UnitSystem, locale: Locale = .current) -> String {
        let time = StatFormatter.elapsedTime(sample).spoken
        guard let distance else { return time }
        let metres = TimelineTicks.value(distance, at: sample) - distance[0]
        return "\(StatFormatter.distance(metres, units: units, locale: locale).spoken), \(time)"
    }

    static func name(of kind: TimelineOverlay.Kind) -> String {
        switch kind {
        case .power: "Power"
        case .heartRate: "Heart rate"
        case .speed: "Speed"
        case .pace: "Pace"
        case .cadence: "Cadence"
        }
    }

    /// An overlay value as its stat.
    static func stat(
        _ value: Double,
        kind: TimelineOverlay.Kind,
        sport: Sport,
        units: UnitSystem,
        locale: Locale = .current
    ) -> FormattedStat {
        switch kind {
        case .power: StatFormatter.power(value, locale: locale)
        case .heartRate: StatFormatter.heartRate(value, locale: locale)
        case .speed: StatFormatter.speed(value, units: units, locale: locale)
        case .pace: StatFormatter.pace(value, units: units)
        case .cadence: StatFormatter.cadence(value, sport: sport, locale: locale)
        }
    }
}
