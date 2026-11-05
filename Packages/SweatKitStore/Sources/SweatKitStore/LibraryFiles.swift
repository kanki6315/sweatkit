import Foundation
import SweatKitModel

/// Where the store keeps its files under the root the caller passes in.
///
/// ```
/// root/
///   LocalMetadata/Library.store   excluded SwiftData metadata
///   library-backup.json    non-Health source/profile recovery manifest
///   HealthOriginals/<hash> excluded Health snapshots
///   Originals/<hash>       originals, byte for byte, named by content hash
///   Streams/<hash>.recorded   the decoded recorded activity of a revision
///   Streams/<hash>.analysis   the analysis stream of a revision
/// ```
///
/// Thumbnails and streams are excluded caches. A future iCloud copy may
/// upload `Originals/` and the recovery inputs; it must never upload local
/// metadata or `HealthOriginals/`. See Documentation/HEALTH-STORAGE.md.
struct LibraryFiles: Sendable {
    static let databaseName = "Library.store"
    static let originalsName = "Originals"
    static let streamsName = "Streams"
    static let recordedExtension = "recorded"
    static let analysisExtension = "analysis"

    let root: URL

    var healthOriginalsDirectory: URL { root.appendingPathComponent("HealthOriginals", isDirectory: true) }
    var thumbnailsDirectory: URL { root.appendingPathComponent("Thumbnails", isDirectory: true) }

    var metadataDirectory: URL { root.appendingPathComponent("LocalMetadata", isDirectory: true) }
    var databaseURL: URL { metadataDirectory.appending(path: Self.databaseName) }
    var backupURL: URL { root.appendingPathComponent("library-backup.json") }
    var backupGenerationURL: URL { metadataDirectory.appendingPathComponent("backup-generation") }
    var originalsDirectory: URL { root.appending(path: Self.originalsName, directoryHint: .isDirectory) }
    var streamsDirectory: URL { root.appending(path: Self.streamsName, directoryHint: .isDirectory) }

    func originalURL(_ hash: ContentHash) -> URL {
        originalsDirectory.appending(path: hash.hex)
    }

    func recordedURL(_ hash: ContentHash) -> URL {
        streamsDirectory.appending(path: "\(hash.hex).\(Self.recordedExtension)")
    }

    func analysisURL(_ hash: ContentHash) -> URL {
        streamsDirectory.appending(path: "\(hash.hex).\(Self.analysisExtension)")
    }

    func createDirectories() throws {
        let manager = FileManager.default
        try manager.createDirectory(at: metadataDirectory, withIntermediateDirectories: true)
        var localMetadata = metadataDirectory
        var excluded = URLResourceValues()
        excluded.isExcludedFromBackup = true
        try localMetadata.setResourceValues(excluded)
        try manager.createDirectory(at: healthOriginalsDirectory, withIntermediateDirectories: true)
        var healthOriginals = healthOriginalsDirectory
        try healthOriginals.setResourceValues(excluded)
        try migrateLegacyMetadata()
        try manager.createDirectory(at: originalsDirectory, withIntermediateDirectories: true)
        try manager.createDirectory(at: streamsDirectory, withIntermediateDirectories: true)
        try manager.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true)
        var thumbnails = thumbnailsDirectory
        var thumbnailValues = URLResourceValues()
        thumbnailValues.isExcludedFromBackup = true
        try thumbnails.setResourceValues(thumbnailValues)
        // Streams are derived and rebuilt from originals, so they stay out of backups.
        var streams = streamsDirectory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try streams.setResourceValues(values)
    }

    private func legacyMetadata() throws -> [URL] {
        try contents(of: root).filter {
            $0.lastPathComponent.hasPrefix(Self.databaseName) || $0.lastPathComponent == ".Library_SUPPORT"
        }
    }

    /// Copy every SQLite component before opening the new path. The marker is
    /// atomic and last; incomplete copies are discarded and retried on reopen.
    private func migrateLegacyMetadata() throws {
        let manager = FileManager.default
        let marker = metadataDirectory.appendingPathComponent("migration-complete")
        guard !manager.fileExists(atPath: marker.path) else { return }
        let legacy = try legacyMetadata()
        if !legacy.isEmpty {
            for item in try contents(of: metadataDirectory) { try manager.removeItem(at: item) }
            for item in legacy where !item.lastPathComponent.hasSuffix("-shm") {
                try manager.copyItem(at: item, to: metadataDirectory.appendingPathComponent(item.lastPathComponent))
            }
        }
        try Data().write(to: marker, options: .atomic)
    }

    func removeLegacyMetadata() throws {
        for item in try legacyMetadata() { try FileManager.default.removeItem(at: item) }
    }

    /// Writes an original unless an intact copy is already there. The write
    /// is atomic, so an interrupted one leaves no partial file under the
    /// final name.
    func writeOriginal(_ bytes: Data, hash: ContentHash, health: Bool) throws {
        let url = health ? healthOriginalsDirectory.appendingPathComponent(hash.hex) : originalURL(hash)
        if let existing = try? Data(contentsOf: url), existing == bytes { return }
        try bytes.write(to: url, options: .atomic)
    }

    /// The original's bytes, checked against their hash. Nil when no file is
    /// stored.
    func readOriginal(_ hash: ContentHash) throws -> Data? {
        var url = originalURL(hash)
        if !FileManager.default.fileExists(atPath: url.path) { url = healthOriginalsDirectory.appendingPathComponent(hash.hex) }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let bytes = try Data(contentsOf: url)
        guard ContentHash(of: bytes) == hash else { throw StoreError.originalCorrupted(hash) }
        return bytes
    }

    func contents(of directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
    }
}
