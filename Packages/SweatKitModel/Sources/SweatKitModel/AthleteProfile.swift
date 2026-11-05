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

    /// Changes whenever the profile does. Derived results record it.
    public var revision: Int
    public var thresholdPowerHistory: [ThresholdPower]
    /// Beats per minute.
    public var maxHeartRate: Double?
    /// Beats per minute, when the user has set it.
    public var statedThresholdHeartRate: Double?
    /// Kilograms.
    public var weight: Double?
    public var units: UnitSystem

    public init(
        revision: Int = 0,
        thresholdPowerHistory: [ThresholdPower] = [],
        maxHeartRate: Double? = nil,
        statedThresholdHeartRate: Double? = nil,
        weight: Double? = nil,
        units: UnitSystem = .metric
    ) {
        self.revision = revision
        self.thresholdPowerHistory = thresholdPowerHistory
        self.maxHeartRate = maxHeartRate
        self.statedThresholdHeartRate = statedThresholdHeartRate
        self.weight = weight
        self.units = units
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
