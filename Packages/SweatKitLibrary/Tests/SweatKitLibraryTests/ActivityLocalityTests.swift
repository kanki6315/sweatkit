import Foundation
import SweatKitLibrary
import SweatKitModel
import SweatKitTestSupport
import Testing

@Suite struct ActivityLocalityTests {
    let temporary = TemporaryLibrary()
    let source = SourceIdentity(source: .garmin, externalID: "locality")

    @Test func lateLocalityUpdatesGeneratedTitleAndSurvivesRestart() async throws {
        let library = try temporary.open()
        let initial = try await library.importFile(Fixtures.FIT.outdoorRide.data(), as: source)
        let request = try #require(try await library.localityRequest(for: source))
        let metrics = try await library.store.derivedResult(owner: .activity(source), kind: ActivityLibrary.metricsKind)
        #expect(try await library.setLocality("  Richmond   Park\n", for: request))
        #expect(try await library.store.derivedResult(owner: .activity(source), kind: ActivityLibrary.metricsKind) == metrics)
        #expect(try await library.activity(source)?.title == initial.activity.title + ", Richmond Park")
        #expect(try await library.localityRequest(for: source) == nil)
        let directory = temporary.root.appendingPathComponent("Localities", isDirectory: true)
        #expect(try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        let reopened = try temporary.open()
        #expect(try await reopened.feed(limit: 10).activities.first?.title == initial.activity.title + ", Richmond Park")
        // A refined location remains generated, rather than being mistaken
        // for a user title merely because the old generated title changed.
        try await reopened.setLocality("Richmond", for: request)
        #expect(try await reopened.activity(source)?.title == initial.activity.title + ", Richmond")
    }

    @Test func renameDuringLookupWinsIncludingTitleEqualToGeneratedText() async throws {
        let library = try temporary.open()
        let initial = try await library.importFile(Fixtures.FIT.outdoorRide.data(), as: source)
        let request = try #require(try await library.localityRequest(for: source))
        try await library.decide(.title(initial.activity.title), for: source)
        try await library.setLocality("Richmond Park", for: request)
        #expect(try await library.activity(source)?.title == initial.activity.title)
        try await library.decide(.title("My own ride"), for: source)
        try await library.setLocality("Richmond", for: request)
        var versions = PipelineVersions.current
        versions.algorithms[PipelineVersions.AlgorithmName.feedRow] = PipelineVersions.feedRowVersion + 1
        let reopened = try temporary.open(versions: versions)
        _ = try await reopened.recompute()
        #expect(try await reopened.feed(limit: 10).activities.first?.title == "My own ride")
    }

    @Test func oldRevisionCannotReceiveLateGeocodingResult() async throws {
        let library = try temporary.open()
        try await library.importFile(Fixtures.FIT.outdoorRide.data(), as: source)
        let request = try #require(try await library.localityRequest(for: source))
        let replacement = try await library.importFile(Fixtures.FIT.walk.data(), as: source)
        #expect(try await library.setLocality("Old place", for: request) == false)
        #expect(try await library.activity(source)?.title == replacement.activity.title)
    }

    @Test func virtualAndSummaryOnlyWorkoutsNeverRequestAPlace() async throws {
        let library = try temporary.open()
        let virtual = try await library.importFile(Fixtures.FIT.zwiftRide.data(), as: source)
        #expect(virtual.activity.isVirtual)
        #expect(try await library.localityRequest(for: source) == nil)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let health = HealthSnapshot(workoutID: UUID(), activity: RecordedActivity(sport: .walking,
            stated: StatedSummary(start: start, end: start.addingTimeInterval(60), timerTime: 60)),
            sourceName: "Watch", sourceBundleIdentifier: "test.watch")
        try await library.importHealthSnapshot(health)
        #expect(try await library.localityRequest(for: health.identity) == nil)
    }

    @Test func noResultIsCachedButNetworkFailureCanRetry() async throws {
        let library = try temporary.open()
        try await library.importFile(Fixtures.FIT.outdoorRide.data(), as: source)
        let request = try #require(try await library.localityRequest(for: source))
        // The network failed: no completion is persisted and the request
        // remains available without changing the import or feed.
        #expect(try await library.localityRequest(for: source) == request)
        try await library.setLocality(nil, for: request)
        #expect(try await library.localityRequest(for: source) == nil)
        #expect(try await library.feed(limit: 10).activities.count == 1)
    }
}
