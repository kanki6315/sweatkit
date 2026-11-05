import Foundation
import Testing
@testable import SweatKitSync

@Suite struct ProgressTests {
    actor Recorder {
        var values: [SyncProgress] = []
        func append(_ value: SyncProgress) { values.append(value) }
    }

    @Test func progressCountsSavedActivitiesAndResetsForEachRun() async {
        var world = World()
        world.add(ride(1, "2026-11-02 08:00:00"))
        world.add(ride(2, "2026-10-20 08:00:00"))
        world.add(ride(3, "2026-10-19 08:00:00"))
        let library = InMemoryGarminLibrary()
        await library.setRefuseIngest([3])
        let sync = makeSync(ScriptedGarmin(world), library, clock: TestClock())
        let recorder = Recorder()
        let report = await sync.run(.routine) { progress in
            // Counts are published only after persistence has succeeded.
            #expect(await library.ingestedIDs.count == progress.added)
            await recorder.append(progress)
        }
        #expect(report.added.count == 2)
        #expect(report.failures.count == 1)
        // The quick pass and history pass encounter the same records without
        // double-counting; the failed import does not increment progress.
        #expect(await recorder.values == [
            SyncProgress(added: 0, updated: 0),
            SyncProgress(added: 1, updated: 0),
            SyncProgress(added: 2, updated: 0),
        ])
        let second = Recorder()
        _ = await sync.run(.quick) { await second.append($0) }
        #expect(await second.values == [SyncProgress(added: 0, updated: 0)])
    }

    @Test func revisionsPublishUpdatedCount() async {
        let original = ride(1, "2026-10-20 08:00:00")
        var changed = original
        changed.distance = 42_000
        var world = World()
        world.add(changed, original: fitBytes(1, version: 2))
        let library = InMemoryGarminLibrary(records: [known(original)])
        let recorder = Recorder()
        let report = await makeSync(ScriptedGarmin(world), library, clock: TestClock()).run(.quick) {
            await recorder.append($0)
        }
        #expect(report.revised.count == 1)
        #expect(await recorder.values == [SyncProgress(added: 0, updated: 0), SyncProgress(added: 0, updated: 1)])
    }
}
