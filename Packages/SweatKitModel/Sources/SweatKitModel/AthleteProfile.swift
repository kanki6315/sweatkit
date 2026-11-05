import Foundation

public enum UnitSystem: String, Codable, Sendable, CaseIterable {
    case metric
    case imperial
}

/// The athlete's thresholds and preferences. Threshold power is
/// date-effective, so old activities keep their old zones.
public struct AthleteProfile: Hashable, Codable, Sendable {
    public struct ThresholdPower: Hashable, Codable, Sendable {
        public var effectiveFrom: Date
        public var watts: Double

        public init(effectiveFrom: Date, watts: Double) {
            self.effectiveFrom = effectiveFrom
            self.watts = watts
        }
    }

    public var thresholdPowerHistory: [ThresholdPower]
    /// Beats per minute.
    public var maxHeartRate: Double?
    /// Beats per minute, when the user has set it.
    public var statedThresholdHeartRate: Double?
    /// Kilograms.
    public var weight: Double?
    /// Absolute lower bounds for zones 2 onward. Nil uses threshold-based defaults.
    public var powerZoneBounds: [Double]?
    public var heartRateZoneBounds: [Double]?

    public static func validZoneBounds(_ bounds: [Double], count: Int) -> Bool {
        bounds.count == count && bounds.allSatisfy { $0.isFinite && $0 > 0 }
            && zip(bounds, bounds.dropFirst()).allSatisfy { $0 < $1 }
    }

    public var units: UnitSystem

    public init(
        thresholdPowerHistory: [ThresholdPower] = [],
        maxHeartRate: Double? = nil,
        statedThresholdHeartRate: Double? = nil,
        weight: Double? = nil,
        units: UnitSystem = .metric,
        powerZoneBounds: [Double]? = nil,
        heartRateZoneBounds: [Double]? = nil
    ) {
        self.thresholdPowerHistory = thresholdPowerHistory
        self.maxHeartRate = maxHeartRate
        self.statedThresholdHeartRate = statedThresholdHeartRate
        self.weight = weight
        self.units = units
        self.powerZoneBounds = powerZoneBounds
        self.heartRateZoneBounds = heartRateZoneBounds
    }

    /// The threshold power in effect on `date`, or nil when none was set by then.
    public func thresholdPower(on date: Date) -> Double? {
        thresholdPowerHistory
            .filter { $0.effectiveFrom <= date }
            .max { $0.effectiveFrom < $1.effectiveFrom }?
            .watts
    }

    /// The user's threshold heart rate. Until they set one it is 90% of max
    /// heart rate.
    public var thresholdHeartRate: Double? {
        statedThresholdHeartRate ?? maxHeartRate.map { $0 * 0.9 }
    }
}

extension AthleteProfile {
    /// The profile values a derived result can read. Weight and units are not
    /// among them, because no stored result depends on them.
    public struct Inputs: OptionSet, Hashable, Codable, Sendable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        /// The threshold power in effect on the result's date and custom power zones.
        public static let thresholdPower = Inputs(rawValue: 1 << 0)
        /// Threshold heart rate and custom heart-rate zones.
        public static let thresholdHeartRate = Inputs(rawValue: 1 << 1)
        public static let maxHeartRate = Inputs(rawValue: 1 << 2)
        public static let all: Inputs = [.thresholdPower, .thresholdHeartRate, .maxHeartRate]
    }

    /// The version of the fingerprint's canonical form. Changing the form
    /// changes every fingerprint, which stales every result that read the
    /// profile.
    private static let fingerprintFormatVersion = 1

    /// A hash of the values in `inputs` as they stand on `date`. Two profiles
    /// give the same fingerprint for a date exactly when those values match,
    /// so a threshold corrected for one range of dates changes fingerprints
    /// in that range only. A derived result records it in its provenance.
    public func fingerprint(on date: Date, reading inputs: Inputs = .all) -> ContentHash {
        var lines = ["athlete-profile/\(Self.fingerprintFormatVersion)"]
        func line(_ name: String, _ value: Double?) {
            // The bit pattern is exact and does not depend on the locale.
            lines.append("\(name)=" + (value.map { String($0.bitPattern, radix: 16) } ?? "none"))
        }
        if inputs.contains(.thresholdPower) {
            line("thresholdPower", thresholdPower(on: date))
            if let powerZoneBounds {
                lines.append("powerZones=" + powerZoneBounds.map { String($0.bitPattern, radix: 16) }.joined(separator: ","))
            }
        }
        if inputs.contains(.thresholdHeartRate) {
            line("thresholdHeartRate", thresholdHeartRate)
            if let heartRateZoneBounds {
                lines.append("heartRateZones=" + heartRateZoneBounds.map { String($0.bitPattern, radix: 16) }.joined(separator: ","))
            }
        }
        if inputs.contains(.maxHeartRate) { line("maxHeartRate", maxHeartRate) }
        return ContentHash(of: Data(lines.joined(separator: "\n").utf8))
    }
}
