import Foundation
import SweatKitGarmin
import SweatKitModel
@testable import SweatKitSync
import Testing

@Suite struct FailureTests {
    @Test func oneFailingDownloadAmongSeveral() async throws {
        // Three new rides in the quick window, downloaded newest first: 3, 2, 1.
        // Garmin answers 500 for ride 2. The other two are ingested, ride 2 is
        // outstanding, and the next sync lists it again and succeeds.
        let rides = [ride(1, "2026-10-30 08:00:00"), ride(2, "2026-10-31 08:00:00"), ride(3, "2026-11-01 08:00:00")]
        var world = World()
        for summary in rides { world.add(summary) }
        let garmin = ScriptedGarmin(world) { _, request, _ in
            request == .download(2) ? .unexpectedResponse(UnexpectedResponse(status: 500, reason: .status)) : nil
        }
        let library = InMemoryGarminLibrary(state: settledState())
        let clock = TestClock()
        let sync = makeSync(garmin, library, clock: clock)

        let first = await sync.run(.quick)
        #expect(await garmin.log == [.range("2026-10-06", nil), .download(3), .download(2), .download(1)])
        #expect(first.outcome == .completed)
        #expect(first.added == ids(3, 1))
        #expect(first.failures == [.garminActivity(2): .server(status: 500)])
        #expect(first.outstanding == 1)
        #expect(await library.state?.pending[2]?.attempts == 1)

        await garmin.setHook(nil)
        let second = await sync.run(.quick)
        #expect(Array(await garmin.log.dropFirst(4)) == [.range("2026-10-06", nil), .download(2)])
        #expect(second.added == ids(2))
        #expect(second.outstanding == 0)
    }

    @Test func aFailureOutsideTheQuickWindowIsRetriedByTheNextQuickSync() async throws {
        // A deep scan finds ride 4 in June but its download is unreadable. A
        // quick sync cannot list June, so the retry comes from the stored
        // pending entry: the quick listing, then download 4.
        let j = ride(4, "2026-06-10 08:00:00")
        var world = World()
        world.add(j)
        world.damaged = [4]
        let garmin = ScriptedGarmin(world)
        let library = InMemoryGarminLibrary(state: settledState(at: t0 - 8 * day))
        let sync = makeSync(garmin, library, clock: TestClock())

        let deep = await sync.run(.routine)
        #expect(deep.failures == [.garminActivity(4): .unreadableDownload])
        #expect(deep.outstanding == 1)
        #expect(deep.pass == .finished(.deepScan))
        let before = await garmin.log.count

        await garmin.change { $0.damaged = [] }
        let quick = await sync.run(.quick)
        #expect(Array(await garmin.log.dropFirst(before)) == [.range("2026-10-06", nil), .download(4)])
        #expect(quick.added == ids(4))
        #expect(quick.outstanding == 0)
    }

    @Test func aLibraryRefusalIsOneActivitysFailure() async throws {
        let rides = [ride(1, "2026-10-30 08:00:00"), ride(2, "2026-10-31 08:00:00")]
        var world = World()
        for summary in rides { world.add(summary) }
        let library = InMemoryGarminLibrary(state: settledState())
        await library.setRefuseIngest([2])

        let report = await makeSync(ScriptedGarmin(world), library, clock: TestClock()).run(.quick)

        #expect(report.added == ids(1))
        #expect(report.failures == [.garminActivity(2): .libraryRejected])
        #expect(report.outstanding == 1)
    }

    @Test func aRateLimitWithNoStatedWaitUsesTheDefault() async throws {
        let garmin = ScriptedGarmin(World()) { _, _, _ in .rateLimited(retryAfter: nil) }
        let library = InMemoryGarminLibrary(state: settledState())
        let report = await makeSync(garmin, library, clock: TestClock()).run(.quick)
        #expect(report.outcome == .rateLimited(until: t0.addingTimeInterval(15 * 60)))
        #expect(await library.state?.rateLimitedUntil == t0.addingTimeInterval(15 * 60))
    }

    @Test func aRateLimitDuringADownloadStopsTheRunAndTheMonthIsListedAgain() async throws {
        // In the backfill, October settles and its first download is refused
        // with 429. The run stops at once; the second ride is not tried, and
        // October is not checkpointed. After the wait, October is listed again
        // and both rides are ingested once.
        let rides = [ride(1, "2026-10-01 08:00:00"), ride(2, "2026-10-02 08:00:00")]
        var world = World()
        for summary in rides { world.add(summary) }
        let garmin = ScriptedGarmin(world) { index, request, _ in
            request == .download(2) && index < 10 ? .rateLimited(retryAfter: 60) : nil
        }
        let library = InMemoryGarminLibrary()
        let clock = TestClock()
        let sync = makeSync(garmin, library, clock: clock)

        let first = await sync.run(.routine)
        #expect(await garmin.log == [
            .range("2026-10-06", nil),
            .earliest,
            .range("2026-11-01", nil), .range("2026-11-01", nil),
            .range("2026-10-01", "2026-10-31"), .range("2026-10-01", "2026-10-31"),
            .download(2),
        ])
        guard case .rateLimited = first.outcome else { Issue.record("expected a rate limit"); return }
        #expect(await library.state?.pass?.completed == [CalendarMonth(year: 2026, month: 11)!])

        clock.advance(60)
        let second = await sync.run(.routine)
        #expect(second.outcome == .completed)
        #expect(Array(await garmin.log.dropFirst(7)) == [
            .range("2026-10-06", nil),
            .earliest,
            .range("2026-10-01", "2026-10-31"), .range("2026-10-01", "2026-10-31"),
            .download(2), .download(1),
        ])
        #expect(await library.ingestedIDs == [2, 1])
    }
}
