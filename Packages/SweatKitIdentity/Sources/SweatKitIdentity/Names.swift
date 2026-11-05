import SweatKitModel

/// The name of a stored record. The last tie between two links or two
/// decisions is broken by the higher name.
///
/// Names are ordered as Swift orders their raw strings. That order does not
/// depend on locale, so it is the same on every device. It is not numeric:
/// `"link-9"` is higher than `"link-10"`.
public struct RecordName: RawRepresentable, Hashable, Codable, Sendable, Comparable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public static func < (lhs: RecordName, rhs: RecordName) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// The device that wrote a record. It is always passed in, never looked up.
///
/// Device IDs are ordered as Swift orders their raw strings, like
/// `RecordName`. "The higher device ID" in the spec is the greater one in
/// this order.
public struct DeviceID: RawRepresentable, Hashable, Codable, Sendable, Comparable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public static func < (lhs: DeviceID, rhs: DeviceID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Two source identities with no order between them. `IdentityPair(a, b)`
/// equals `IdentityPair(b, a)`.
///
/// A pair of one identity with itself can be built. A link on it joins and
/// separates nothing.
public struct IdentityPair: Hashable, Codable, Sendable, Comparable {
    /// The lower of the two identities, in `SourceIdentity`'s order.
    public let lower: SourceIdentity
    /// The higher of the two identities.
    public let upper: SourceIdentity

    /// The pair of `first` and `second`, in either order.
    public init(_ first: SourceIdentity, _ second: SourceIdentity) {
        if second < first {
            lower = second
            upper = first
        } else {
            lower = first
            upper = second
        }
    }

    /// Decodes a pair through the same normalising step as `init(_:_:)`, so
    /// a stored pair whose two identities are the wrong way round still
    /// equals the pair built in code.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let lower = try container.decode(SourceIdentity.self, forKey: .lower)
        let upper = try container.decode(SourceIdentity.self, forKey: .upper)
        self.init(lower, upper)
    }

    /// Whether `identity` is one of the two.
    public func contains(_ identity: SourceIdentity) -> Bool {
        identity == lower || identity == upper
    }

    /// Ordered by `lower`, then by `upper`.
    public static func < (lhs: IdentityPair, rhs: IdentityPair) -> Bool {
        if lhs.lower != rhs.lower {
            return lhs.lower < rhs.lower
        }
        return lhs.upper < rhs.upper
    }
}
