/// What a derived result was computed from. The result is valid only while
/// all three still match.
public struct Provenance: Hashable, Codable, Sendable {
    /// The revision of the inputs.
    public var inputRevision: ContentHash
    /// The revision of the athlete profile, or nil when the result does not
    /// read the profile.
    public var profileRevision: Int?
    public var algorithmVersion: Int

    public init(inputRevision: ContentHash, profileRevision: Int? = nil, algorithmVersion: Int) {
        self.inputRevision = inputRevision
        self.profileRevision = profileRevision
        self.algorithmVersion = algorithmVersion
    }
}

/// A metric value, or the reason there isn't one. Unavailable is its own
/// state, shown as a dash with the reason one tap away, never as zero.
public enum Metric<Value> {
    case available(Value)
    case unavailable(UnavailableReason)

    public var value: Value? {
        if case .available(let value) = self { value } else { nil }
    }

    public var reason: UnavailableReason? {
        if case .unavailable(let reason) = self { reason } else { nil }
    }
}

extension Metric: Equatable where Value: Equatable {}
extension Metric: Hashable where Value: Hashable {}
extension Metric: Sendable where Value: Sendable {}
extension Metric: Codable where Value: Codable {}

/// Why a metric is unavailable. Packages add their own reasons as static
/// members in an extension.
public struct UnavailableReason: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}
