import Foundation

/// HealthKit anchors are opaque secure archives. Pending workout IDs are
/// persisted in the same atomic document before any anchor is advanced.
public struct HealthSyncState: Codable, Sendable, Equatable {
    public var version = 1
    public var anchors: [String: Data] = [:]
    public var workouts: [UUID: DateInterval] = [:]
    public var pending: Set<UUID> = []

    public init() {}

    public static func load(from url: URL) throws -> Self {
        guard FileManager.default.fileExists(atPath: url.path) else { return Self() }
        let state = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard state.version == 1 else { throw LibraryError.storage("Unsupported Health checkpoint version") }
        return state
    }

    public func save(to destination: URL) throws {
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: destination, options: .atomic)
        var url = destination
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
}
