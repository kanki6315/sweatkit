import Foundation
import SweatKitModel

/// A value ready to show: its numerals, its unit, and how VoiceOver says it.
struct FormattedStat: Hashable, Sendable {
    /// The numerals, or the dash when there is no value.
    var value: String
    /// The unit beside the numerals. Empty for a time.
    var unit: String
    /// The value and unit in words, or "No data".
    var spoken: String
}

/// Formats each stat in both unit systems.
///
/// A value that is nil or not finite is missing and shows as a dash, never as
/// zero. Rounding is to the nearest, with halves away from zero, except for
/// times, which show the seconds completed. A value that rounds to zero has
/// no minus sign.
enum StatFormatter {
    /// What a missing value shows as.
    static let missing = "–"
    static let missingSpoken = "No data"

    static let metresPerKilometre = 1000.0
    static let metresPerMile = 1609.344
    static let metresPerFoot = 0.3048
    static let secondsPerHour = 3600.0
    /// A pace slower than this many seconds per kilometre or mile shows as a
    /// dash: the athlete is as good as stopped and the number means nothing.
    static let slowestPace = 5999.0

    // MARK: Stats

    /// Kilometres or miles, to two decimal places.
    static func distance(_ metres: Double?, units: UnitSystem, locale: Locale = .current) -> FormattedStat {
        let unit = units == .metric ? "km" : "mi"
        guard let metres, metres.isFinite else { return missing(unit: unit) }
        let value = metres / (units == .metric ? metresPerKilometre : metresPerMile)
        let text = decimal(value, places: 2, locale: locale)
        return FormattedStat(value: text, unit: unit, spoken: "\(text) \(units == .metric ? "kilometres" : "miles")")
    }

    /// Hours, minutes and seconds as `h:mm:ss`, or `m:ss` under an hour.
    static func elapsedTime(_ seconds: TimeInterval?) -> FormattedStat {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return missing(unit: "") }
        let whole = Int(seconds.rounded(.down))
        return FormattedStat(value: clock(whole), unit: "", spoken: spokenDuration(whole))
    }

    /// Kilometres or miles per hour, to one decimal place.
    static func speed(_ metresPerSecond: Double?, units: UnitSystem, locale: Locale = .current) -> FormattedStat {
        let unit = units == .metric ? "km/h" : "mph"
        guard let metresPerSecond, metresPerSecond.isFinite else { return missing(unit: unit) }
        let perHour = metresPerSecond * secondsPerHour / (units == .metric ? metresPerKilometre : metresPerMile)
        let text = decimal(perHour, places: 1, locale: locale)
        return FormattedStat(value: text, unit: unit, spoken: "\(text) \(units == .metric ? "kilometres per hour" : "miles per hour")")
    }

    /// Minutes and seconds per kilometre or mile, from a speed. A speed of
    /// zero, or one slower than `slowestPace`, has no pace and shows as a
    /// dash.
    static func pace(_ metresPerSecond: Double?, units: UnitSystem) -> FormattedStat {
        let unit = units == .metric ? "/km" : "/mi"
        guard let metresPerSecond, metresPerSecond.isFinite, metresPerSecond > 0 else { return missing(unit: unit) }
        let seconds = ((units == .metric ? metresPerKilometre : metresPerMile) / metresPerSecond)
            .rounded(.toNearestOrAwayFromZero)
        guard seconds <= slowestPace else { return missing(unit: unit) }
        let whole = Int(seconds)
        let rest = whole % 60
        return FormattedStat(
            // Minutes run past 59 rather than turning into hours.
            value: "\(whole / 60):\(rest < 10 ? "0" : "")\(rest)",
            unit: unit,
            spoken: "\(spokenDuration(whole)) per \(units == .metric ? "kilometre" : "mile")"
        )
    }

    /// Whole watts.
    static func power(_ watts: Double?, locale: Locale = .current) -> FormattedStat {
        whole(watts, unit: "W", spokenUnit: "watts", locale: locale)
    }

    /// Whole beats per minute.
    static func heartRate(_ beatsPerMinute: Double?, locale: Locale = .current) -> FormattedStat {
        whole(beatsPerMinute, unit: "bpm", spokenUnit: "beats per minute", locale: locale)
    }

    /// Whole revolutions per minute on a bike, and steps per minute otherwise.
    static func cadence(_ perMinute: Double?, sport: Sport, locale: Locale = .current) -> FormattedStat {
        sport.family == .cycling
            ? whole(perMinute, unit: "rpm", spokenUnit: "revolutions per minute", locale: locale)
            : whole(perMinute, unit: "spm", spokenUnit: "steps per minute", locale: locale)
    }

    /// Whole metres or feet. Also used for ascent.
    static func elevation(_ metres: Double?, units: UnitSystem, locale: Locale = .current) -> FormattedStat {
        let scaled = metres.map { units == .metric ? $0 : $0 / metresPerFoot }
        return units == .metric
            ? whole(scaled, unit: "m", spokenUnit: "metres", locale: locale)
            : whole(scaled, unit: "ft", spokenUnit: "feet", locale: locale)
    }

    /// Percent to one decimal place, from rise over run.
    static func gradient(_ riseOverRun: Double?, locale: Locale = .current) -> FormattedStat {
        guard let riseOverRun, riseOverRun.isFinite else { return missing(unit: "%") }
        let text = decimal(riseOverRun * 100, places: 1, locale: locale)
        return FormattedStat(value: text, unit: "%", spoken: "\(text) percent")
    }

    // MARK: Parts

    static func missing(unit: String) -> FormattedStat {
        FormattedStat(value: missing, unit: unit, spoken: missingSpoken)
    }

    private static func whole(_ value: Double?, unit: String, spokenUnit: String, locale: Locale) -> FormattedStat {
        guard let value, value.isFinite else { return missing(unit: unit) }
        let text = decimal(value, places: 0, locale: locale)
        return FormattedStat(value: text, unit: unit, spoken: "\(text) \(spokenUnit)")
    }

    /// A number with a fixed count of decimal places, no grouping, the
    /// locale's digits and decimal separator, and a true minus sign.
    static func decimal(_ value: Double, places: Int, locale: Locale) -> String {
        let scale = pow(10, Double(places))
        let rounded = (abs(value) * scale).rounded(.toNearestOrAwayFromZero) / scale
        let digits = rounded.formatted(
            .number.precision(.fractionLength(places)).grouping(.never).locale(locale)
        )
        return value < 0 && rounded != 0 ? "−" + digits : digits
    }

    /// `h:mm:ss` from an hour up, and `m:ss` below.
    static func clock(_ seconds: Int) -> String {
        let hours = seconds / 3600, minutes = seconds % 3600 / 60, rest = seconds % 60
        let two = { (value: Int) in value < 10 ? "0\(value)" : "\(value)" }
        return hours > 0 ? "\(hours):\(two(minutes)):\(two(rest))" : "\(minutes):\(two(rest))"
    }

    /// A duration in words, leaving out the parts that are zero.
    static func spokenDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600, minutes = seconds % 3600 / 60, rest = seconds % 60
        var parts: [String] = []
        if hours > 0 { parts.append("\(hours) \(hours == 1 ? "hour" : "hours")") }
        if minutes > 0 { parts.append("\(minutes) \(minutes == 1 ? "minute" : "minutes")") }
        if rest > 0 || parts.isEmpty { parts.append("\(rest) \(rest == 1 ? "second" : "seconds")") }
        return parts.joined(separator: " ")
    }
}
