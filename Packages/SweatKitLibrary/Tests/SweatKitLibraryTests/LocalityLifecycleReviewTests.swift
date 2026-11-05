import Foundation
import SweatKitLibrary
import SweatKitModel
import SweatKitTestSupport
import Testing

@Suite struct LocalityLifecycleReviewTests {
    let temporary = TemporaryLibrary()
    let restored = TemporaryLibrary()
    let source = SourceIdentity(source: .garmin, externalID: "locality-review")

    @Test func lateLocalityCannotRecreateDeletedCache() async throws {
        let library = try temporary.open()
        try await library.importFile(Fixtures.FIT.outdoorRide.data(), as: source)
        let request = try #require(try await library.localityRequest(for: source))
        try await library.setLocality("Richmond", for: request)
        let cache = temporary.root.appendingPathComponent("Localities/\(request.revision.hex).json")
        #expect(FileManager.default.fileExists(atPath: cache.path))
        try await library.permanentlyDelete(source)
        #expect(!FileManager.default.fileExists(atPath: cache.path))
        #expect(try await library.setLocality("Late result", for: request) == false)
        #expect(!FileManager.default.fileExists(atPath: cache.path))
        let reopened = try temporary.open()
        #expect(try await reopened.setLocality("Late after restart", for: request) == false)
        #expect(!FileManager.default.fileExists(atPath: cache.path))
        #expect(try await reopened.feed(limit: 10).activities.isEmpty)
    }

    @Test func backupRestoreRegeneratesLocalityWithoutInventingAUserTitle() async throws {
        let library = try temporary.open()
        let imported = try await library.importFile(Fixtures.FIT.outdoorRide.data(), as: source)
        let request = try #require(try await library.localityRequest(for: source))
        try await library.setLocality("Old locality", for: request)
        try FileManager.default.createDirectory(at: restored.root, withIntermediateDirectories: true)
        for name in ["Originals", "library-backup.json", "identity.json"] {
            try FileManager.default.copyItem(at: temporary.root.appendingPathComponent(name), to: restored.root.appendingPathComponent(name))
        }
        let recovered = try restored.open()
        let row = try #require(try await recovered.feed(limit: 10).activities.first)
        #expect(row.title == imported.activity.title)
        let recoveredRequest = try #require(try await recovered.localityRequest(for: source))
        let metrics = try await recovered.store.derivedResult(owner: .activity(source), kind: ActivityLibrary.metricsKind)
        try await recovered.setLocality("New locality", for: recoveredRequest)
        #expect(try await recovered.activity(source)?.title == imported.activity.title + ", New locality")
        #expect(try await recovered.store.derivedResult(owner: .activity(source), kind: ActivityLibrary.metricsKind) == metrics)
    }
}
