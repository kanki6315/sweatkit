import Foundation
import SweatKitModel

/// A local, versioned snapshot of a Health workout. It contains only the
/// data returned by HealthKit; missing samples are never synthesized here.
public struct HealthSnapshot: Codable, Hashable, Sendable {
    public var workoutID: UUID
    public var activity: RecordedActivity
    public var linkedIdentities: Set<SourceIdentity>
    public var sourceName: String
    public var sourceBundleIdentifier: String

    public init(workoutID: UUID, activity: RecordedActivity, linkedIdentities: Set<SourceIdentity> = [],
                sourceName: String, sourceBundleIdentifier: String) {
        self.workoutID = workoutID
        self.activity = activity
        self.linkedIdentities = linkedIdentities
        self.sourceName = sourceName
        self.sourceBundleIdentifier = sourceBundleIdentifier
    }

    private enum CodingKeys: String, CodingKey {
        case workoutID, activity, linkedIdentities, sourceName, sourceBundleIdentifier
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(workoutID, forKey: .workoutID)
        try container.encode(activity, forKey: .activity)
        try container.encode(linkedIdentities.sorted(), forKey: .linkedIdentities)
        try container.encode(sourceName, forKey: .sourceName)
        try container.encode(sourceBundleIdentifier, forKey: .sourceBundleIdentifier)
    }

    public var identity: SourceIdentity { SourceIdentity(source: .healthKit, externalID: workoutID.uuidString) }

    private static let magic = Data("SKHEALTH1".utf8)
    private struct Envelope: Codable {
        var version = 1
        var snapshot: HealthSnapshot
    }

    func encoded() throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return Self.magic + (try encoder.encode(Envelope(snapshot: self)))
    }

    static func decode(_ data: Data) throws -> HealthSnapshot? {
        guard data.starts(with: magic) else { return nil }
        let envelope = try PropertyListDecoder().decode(Envelope.self, from: data.dropFirst(magic.count))
        guard envelope.version == 1 else { throw LibraryError.storage("Unsupported Health snapshot version") }
        return envelope.snapshot
    }
}
