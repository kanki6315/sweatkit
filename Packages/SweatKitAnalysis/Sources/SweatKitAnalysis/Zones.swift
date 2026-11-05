import Foundation
import SweatKitModel

/// A set of zones laid end to end. Zone 0 is everything under the first
/// bound, and each bound opens the next zone.
public struct ZoneScheme: Hashable, Sendable {
    /// The lower bound of every zone but the lowest, ascending.
    public let lowerBounds: [Double]

    public init(lowerBounds: [Double]) {
        self.lowerBounds = lowerBounds
    }

    public var zoneCount: Int { lowerBounds.count + 1 }

    /// The zone holding `value`, counted from 0 for the lowest. A value
    /// exactly on a boundary belongs to the higher zone.
    ///
    /// For power and heart rate `value` is the share of threshold: the
    /// reading divided by the threshold. The share is formed by that one
    /// division and compared with the bound as it is, so 110 W at a 200 W
    /// threshold is exactly 55% and lands in the second zone.
    public func index(of value: Double) -> Int {
        lowerBounds.firstIndex { value < $0 } ?? lowerBounds.count
    }

    /// Seven zones by share of threshold power.
    public static let power = ZoneScheme(lowerBounds: AnalysisRules.powerZoneLowerBounds)
    /// Five zones by share of threshold heart rate.
    public static let heartRate = ZoneScheme(lowerBounds: AnalysisRules.heartRateZoneLowerBounds)
    /// Five bands by gradient as rise over run: descent, flat, and three
    /// steepening climbs.
    public static let gradient = ZoneScheme(lowerBounds: AnalysisRules.gradientBandLowerBounds)
}

/// Seconds spent in each zone of a scheme.
///
/// Every second of the stream is counted once, paused or not, so the zones
/// and the missing bucket add up to elapsed time. The spec does not say
/// whether paused seconds are left out; counting all of them is the literal
/// reading, and it keeps the figure the same whether or not pause positions
/// are known.
public struct TimeInZones: Hashable, Codable, Sendable {
    /// Seconds per zone from measured and interpolated values, lowest zone first.
    public var seconds: [Int]
    /// Seconds with no value. Never folded into a zone.
    public var missing: Int

    public init(seconds: [Int], missing: Int) {
        self.seconds = seconds
        self.missing = missing
    }
}

/// Shared resolution for time totals and route/timeline colours. Starter thresholds
/// are display assumptions only; intensity and training load still need a profile.
public struct ResolvedZones: Sendable {
    public let scheme: ZoneScheme
    public let threshold: Double
    public let isStarter: Bool
    public var absoluteBounds: [Double] { scheme.lowerBounds.map { $0 * threshold } }

    public static func power(profile: AthleteProfile, on date: Date) -> Self {
        if let bounds = profile.powerZoneBounds,
           AthleteProfile.validZoneBounds(bounds, count: 6) {
            return Self(scheme: ZoneScheme(lowerBounds: bounds), threshold: 1, isStarter: false)
        }
        let threshold = profile.thresholdPower(on: date)
        return Self(scheme: .power, threshold: threshold ?? 200, isStarter: threshold == nil)
    }

    public static func heartRate(profile: AthleteProfile) -> Self {
        if let bounds = profile.heartRateZoneBounds,
           AthleteProfile.validZoneBounds(bounds, count: 4) {
            return Self(scheme: ZoneScheme(lowerBounds: bounds), threshold: 1, isStarter: false)
        }
        let threshold = profile.thresholdHeartRate
        return Self(scheme: .heartRate, threshold: threshold ?? 170, isStarter: threshold == nil)
    }
}
