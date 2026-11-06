import Foundation
import Testing

@Suite struct ThumbnailMigrationTests {
    @Test func removesLegacyMapImagesOnlyOnce() throws {
        let library = TemporaryLibrary()
        let directory = library.root.appendingPathComponent("Thumbnails")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let legacy = directory.appendingPathComponent("old-map.png")
        try Data([1]).write(to: legacy)
        _ = try library.open()
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
        let localRoute = directory.appendingPathComponent("local-route.png")
        try Data([2]).write(to: localRoute)
        _ = try library.open()
        #expect(try Data(contentsOf: localRoute) == Data([2]))
    }
}
