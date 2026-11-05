import Foundation
import SweatKitModel

/// Where the store keeps its files under the root the caller passes in.
///
/// ```
/// root/
///   Library.store          SwiftData metadata
///   Originals/<hash>       originals, byte for byte, named by content hash
///   Streams/<hash>.recorded   the decoded recorded activity of a revision
///   Streams/<hash>.analysis   the analysis stream of a revision
/// ```
///
/// Later: HealthKit snapshots are originals like any other. Thumbnails would
/// sit in a `Thumbnails/` directory beside `Streams/`, named by activity and
/// excluded from backup the same way. The iCloud copy uploads files from
/// `Originals/` as assets and never touches `Streams/`.
struct LibraryFiles: Sendable {
    static let databaseName = "Library.store"
    static let originalsName = "Originals"
    static let streamsName = "Streams"
    static let recordedExtension = "recorded"
    static let analysisExtension = "analysis"

    let root: URL

    var databaseURL: URL { root.appending(path: Self.databaseName) }
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
        try manager.createDirectory(at: originalsDirectory, withIntermediateDirectories: true)
        try manager.createDirectory(at: streamsDirectory, withIntermediateDirectories: true)
        // Streams are derived and rebuilt from originals, so they stay out of backups.
        var streams = streamsDirectory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try streams.setResourceValues(values)
    }

    /// Writes an original unless an intact copy is already there. The write
    /// is atomic, so an interrupted one leaves no partial file under the
    /// final name.
    func writeOriginal(_ bytes: Data, hash: ContentHash) throws {
        let url = originalURL(hash)
        if let existing = try? Data(contentsOf: url), existing == bytes { return }
        try bytes.write(to: url, options: .atomic)
    }

    /// The original's bytes, checked against their hash. Nil when no file is
    /// stored.
    func readOriginal(_ hash: ContentHash) throws -> Data? {
        let url = originalURL(hash)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let bytes = try Data(contentsOf: url)
        guard ContentHash(of: bytes) == hash else { throw StoreError.originalCorrupted(hash) }
        return bytes
    }

    func contents(of directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
    }
}
