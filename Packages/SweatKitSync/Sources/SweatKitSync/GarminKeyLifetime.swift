import Foundation

/// User-entered key lifetime; Garmin does not expose an authoritative expiry.
public struct GarminKeyLifetime: Codable, Sendable, Equatable {
    public enum Period: Int, CaseIterable, Codable, Sendable {
        case days30 = 30, days90 = 90, days180 = 180, year = 365
    }
    public let created: Date
    public let period: Period
    public init(created: Date, period: Period) { self.created = created; self.period = period }
    public var estimatedExpiry: Date { created.addingTimeInterval(Double(period.rawValue) * 86400) }
    public enum Warning: Equatable, Sendable { case none, dueSoon, expired }
    public func warning(at now: Date) -> Warning {
        if now >= estimatedExpiry { return .expired }
        return now >= estimatedExpiry.addingTimeInterval(-7 * 86400) ? .dueSoon : .none
    }
}
