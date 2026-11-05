/// The sport of an activity. Cycling, walking, running and hiking have full
/// support; anything else shows summary stats only.
public enum Sport: String, Codable, Sendable, CaseIterable {
    case cycling
    case walking
    case running
    case hiking
    case other

    public var family: SportFamily {
        switch self {
        case .cycling: .cycling
        case .walking, .running, .hiking: .onFoot
        case .other: .other
        }
    }

    public var hasFullSupport: Bool { self != .other }
}

/// The grouping used by de-duplication and route matching, where a walk
/// recorded as a hike by another device is still the same kind of activity.
public enum SportFamily: String, Codable, Sendable, CaseIterable {
    case cycling
    case onFoot
    case other
}
