import Foundation

/// Syncable user intent only. Never carries coordinates, samples, times, or inferred membership.
public struct RouteDecision: Codable, Hashable, Sendable, Identifiable {
    public enum Value: Codable, Hashable, Sendable {
        case name(String)
        case reference(SourceIdentity)
        case membership(activity: SourceIdentity, included: Bool)
        case merge(SourceIdentity)
    }
    public let id: UUID
    /// Stable identity of the original seed effort, independent of the current reference.
    public let route: SourceIdentity
    /// Identity-only scope captured when the user edits a group. It restores the group
    /// after loss of local caches; these are hints, never approvals to bypass alignment.
    public let anchors: [SourceIdentity]?
    public let value: Value
    public let date: Date
    public init(id: UUID = UUID(), route: SourceIdentity, value: Value, date: Date = Date(), anchors: [SourceIdentity]? = nil) {
        self.id = id; self.route = route; self.value = value; self.date = date; self.anchors = anchors
    }
}

/// Versioned opaque payload boundary for Cloud. Merge records by UUID; interpret only in Routes.
public struct RouteDecisionExport: Codable, Sendable {
    public var version: Int = 1
    public var decisions: [RouteDecision]
    public init(decisions: [RouteDecision]) { self.decisions = decisions }
}
