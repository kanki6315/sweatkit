import Foundation
import Darwin

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
        // Write inside an excluded staging directory and flag the file before
        // its atomic rename. There is never an eligible Health checkpoint,
        // including during replacement of the previous anchor document.
        var staging = destination.deletingLastPathComponent().appendingPathComponent("HealthCheckpointWrites", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try staging.setResourceValues(values)
        var temporary = staging.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try JSONEncoder().encode(self).write(to: temporary, options: .atomic)
        try temporary.setResourceValues(values)
        guard rename(temporary.path, destination.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}
