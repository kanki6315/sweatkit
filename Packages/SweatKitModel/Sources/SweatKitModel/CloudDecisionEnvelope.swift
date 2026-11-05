import Foundation

/// Add-only user intent. Payload is owned/versioned by its feature, not CloudKit.
/// Only explicit user decisions are permitted: never coordinates, Health facts,
/// computed metrics, cached matches, credentials or serialized feature models.
/// Consumers retain unknown namespaces/versions and replay supported versions.
public struct CloudDecisionEnvelope: Codable, Hashable, Sendable {
    public let id: UUID
    public let namespace: String
    public let version: Int
    public let time: Date
    public let device: String
    public let payload: Data
    public init(id: UUID = UUID(), namespace: String, version: Int, time: Date, device: String, payload: Data) {
        self.id = id; self.namespace = namespace; self.version = version
        self.time = time; self.device = device; self.payload = payload
    }
}
