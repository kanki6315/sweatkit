import Foundation
import SweatKitGarmin
import SweatKitModel
@testable import SweatKitSync
import Testing

/// Identity and revisions. The library holds ride 1 with the original of
/// version 1; each test changes what Garmin lists or serves, then runs a quick
/// sync (one page, from 6 October).
@Suite struct RevisionTests {
    let held = ride(1, "2026-10-20 08:00:00", duration: 3600, distance: 30_000, name: "Ride")
    let hashV1 = ContentHash(of: fitBytes(1, version: 1))
    let hashV2 = ContentHash(of: fitBytes(1, version: 2))

    func run(listing: GarminSummary, original version: Int, _ kind: SyncRun = .quick) async -> (SyncReport, [Request], [InMemoryGarminLibrary.Action]) {
        var world = World()
        world.add(listing, original: fitBytes(1, version: version))
        let garmin = ScriptedGarmin(world)
        let library = InMemoryGarminLibrary(records: [known(held)], state: settledState())
        let report = await makeSync(garmin, library, clock: TestClock()).run(kind)
        return (report, await garmin.log, await library.actions)
    }

    @Test func anUnchangedSummaryChangesNothing() async {
        let (report, log, actions) = await run(listing: held, original: 1)
        #expect(log == [.range("2026-10-06", nil)])
        #expect(actions.isEmpty)
        #expect(report.summariesUpdated.isEmpty)
    }

    @Test func aChangedNameUpdatesTheMetadataWithoutADownload() async {
        var renamed = held
        renamed.name = "Morning ride"
        let (report, log, actions) = await run(listing: renamed, original: 1)
        #expect(log == [.range("2026-10-06", nil)])
        #expect(actions == [.updateSummary(1)])
        #expect(report.summariesUpdated == ids(1))
    }

    @Test func aChangedDurationDownloadsAgainAndTheSameHashChangesOnlyTheSummary() async {
        // Duration is a file trigger, so the file is downloaded. Its original is
        // still version 1: same hash, so no revision, only the new summary.
        var trimmed = held
        trimmed.duration = 3500
        trimmed.elapsedDuration = 3500
        let (report, log, actions) = await run(listing: trimmed, original: 1)
        #expect(log == [.range("2026-10-06", nil), .download(1)])
        #expect(actions == [.updateSummary(1)])
        #expect(report.unchangedDownloads == ids(1))
        #expect(report.revised.isEmpty)
    }

    @Test func aChangedDistanceWithANewFileIsANewRevision() async {
        var corrected = held
        corrected.distance = 31_250
        let (report, log, actions) = await run(listing: corrected, original: 2)
        #expect(log == [.range("2026-10-06", nil), .download(1)])
        #expect(actions == [.ingest(1, hashV2)])
        #expect(report.revised == ids(1))
        #expect(report.added.isEmpty)
    }

    @Test func aChangedStartDownloadsAgain() async {
        var moved = held
        moved.startTimeLocal = "2026-10-20 09:00:00"
        moved.startTimeGMT = "2026-10-20 09:00:00"
        let (_, log, actions) = await run(listing: moved, original: 2)
        #expect(log == [.range("2026-10-06", nil), .download(1)])
        #expect(actions == [.ingest(1, hashV2)])
    }

    @Test func aRequestedDownloadWithTheSameHashChangesNothing() async {
        // Full reconciliation: earliest, November twice, October twice, then the
        // chosen file.
        let (report, log, actions) = await run(listing: held, original: 1, .fullReconciliation(.only(Set(ids(1)))))
        #expect(log.last == .download(1))
        #expect(log.count == 6)
        #expect(actions.isEmpty)
        #expect(report.unchangedDownloads == ids(1))
    }

    @Test func aRequestedDownloadWithADifferentHashIsANewRevision() async {
        // The file changed at Garmin while its summary stayed the same: the
        // spec's known limit, caught only because the user asked.
        let (report, _, actions) = await run(listing: held, original: 2, .fullReconciliation(.all))
        #expect(actions == [.ingest(1, hashV2)])
        #expect(report.revised == ids(1))
    }

    @Test func summaryComparisonKeepsMissingApartFromZero() {
        var missing = held
        missing.distance = nil
        var zero = held
        zero.distance = 0
        #expect(missing != zero)
        #expect(missing.fileTriggers != zero.fileTriggers)
    }
}
