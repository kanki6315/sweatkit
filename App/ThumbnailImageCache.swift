import Foundation

/// Reads and bounds rendered previews off the main actor. Writes still go through
/// LibraryStore.saveThumbnail, which serializes with permanent activity deletion.
actor ThumbnailImageCache {
    static let shared = ThumbnailImageCache()
    private let budget: Int

    init(budget: Int = 100 * 1024 * 1024) { self.budget = budget }

    func read(_ url: URL) -> Data? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return data
    }

    func trim(directory: URL) throws {
        let files = try FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])
            .filter { $0.pathExtension == "png" }
            .compactMap { url -> (URL, Int, Date)? in
                guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { return nil }
                return (url, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
            }.sorted { $0.2 < $1.2 }
        var total = files.reduce(0) { $0 + $1.1 }
        for (url, size, _) in files where total > budget {
            // Permanent deletion may concurrently remove the same preview.
            try? FileManager.default.removeItem(at: url)
            total -= size
        }
    }
}
