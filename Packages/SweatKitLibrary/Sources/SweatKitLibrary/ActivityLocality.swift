import Foundation
import SweatKitModel
import SweatKitStore

/// A request is tied to the source revision that supplied its location. A late
/// network response cannot label a newer revision with an older location.
public struct ActivityLocalityRequest: Sendable, Hashable {
    public let source: SourceIdentity
    public let revision: ContentHash
    public let coordinate: Coordinate
}

/// A rebuildable place-name cache, never a user title or an original. Exclude
/// it from backup before writing because a name can be derived from Health GPS.
/// Missing/corrupt cache entries are retried; they cannot block the feed.
enum ActivityLocalityCache {
    struct Entry: Codable {
        var version = 1
        var name: String?
    }

    static func entry(root: URL, revision: ContentHash) -> Entry? {
        guard let data = try? Data(contentsOf: url(root: root, revision: revision)),
              let entry = try? JSONDecoder().decode(Entry.self, from: data), entry.version == 1 else { return nil }
        return entry
    }

    static func save(_ name: String?, root: URL, revision: ContentHash) throws {
        var directory = root.appendingPathComponent("Localities", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        let cleaned = name?.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let entry = Entry(name: cleaned?.isEmpty == false ? cleaned : nil)
        try JSONEncoder().encode(entry).write(to: url(root: root, revision: revision), options: .atomic)
    }

    private static func url(root: URL, revision: ContentHash) -> URL {
        root.appendingPathComponent("Localities", isDirectory: true).appendingPathComponent("\(revision.hex).json")
    }
}

extension ActivityLibrary {
    /// The first valid recorded location is enough for a locality. Virtual and
    /// indoor coordinates never become real place names. A cached no-result is
    /// also complete, avoiding repeated requests where no locality is available.
    public func localityRequest(for id: SourceIdentity) async throws -> ActivityLocalityRequest? {
        guard let row = try await activity(id), !row.isIndoor, !row.isVirtual,
              let source = try await store.sourceRecord(row.primary), source.state != .deleted,
              ActivityLocalityCache.entry(root: store.root, revision: source.currentRevision) == nil else { return nil }
        var cached = await store.analysisStream(for: source.currentRevision, rulesVersion: versions.streamRules)
        if case .needsRebuild = cached {
            _ = try await analysisStream(for: id)
            cached = await store.analysisStream(for: source.currentRevision, rulesVersion: versions.streamRules)
        }
        guard case .available(let stream) = cached else { return nil }
        for second in 0..<stream.count {
            guard let coordinate = stream.coordinate(at: second),
                  coordinate.latitude.isFinite, coordinate.longitude.isFinite,
                  (-90...90).contains(coordinate.latitude), (-180...180).contains(coordinate.longitude) else { continue }
            return ActivityLocalityRequest(source: row.primary, revision: source.currentRevision, coordinate: coordinate)
        }
        return nil
    }
}
