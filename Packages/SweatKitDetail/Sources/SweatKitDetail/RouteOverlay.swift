import SweatKitModel

/// What the route and the timeline are coloured by: the spec's "Route
/// colouring" table.
public enum RouteOverlay: String, Hashable, Sendable, CaseIterable {
    /// Seven zones of 10-second smoothed power.
    case power
    /// Five zones of heart rate.
    case heartRate
    /// Five bands of speed relative to the activity's own range. Shown as
    /// pace on foot and as speed otherwise; the bands are the same.
    case paceOrSpeed
    /// Descent, flat and three steepness bands of climb.
    case gradient
    /// One colour.
    case plain

    /// The overlay the spec's table makes the default: power for rides with a
    /// power meter, heart rate for rides without, pace or speed for walks,
    /// runs and hikes.
    ///
    /// The table names no default for any other sport, which the app shows
    /// as summary stats only. Reading: plain.
    public static func tableDefault(sport: Sport, hasPowerMeter: Bool) -> RouteOverlay {
        switch sport.family {
        case .cycling: hasPowerMeter ? .power : .heartRate
        case .onFoot: .paceOrSpeed
        case .other: .plain
        }
    }

    /// The overlays tried in turn when the table's default is unavailable,
    /// such as a ride with a power meter but no threshold power set. Plain
    /// is always available, so the list always ends in it.
    ///
    /// Reading, where the spec is silent: a ride whose power cannot be zoned
    /// falls back to heart rate, as a ride without power does, and anything
    /// else falls back to plain. The overlay is never coloured from a guessed
    /// threshold.
    public static func defaultCandidates(sport: Sport, hasPowerMeter: Bool) -> [RouteOverlay] {
        switch tableDefault(sport: sport, hasPowerMeter: hasPowerMeter) {
        case .power: [.power, .heartRate, .plain]
        case .heartRate: [.heartRate, .plain]
        case .paceOrSpeed: [.paceOrSpeed, .plain]
        case .gradient: [.gradient, .plain]
        case .plain: [.plain]
        }
    }
}
