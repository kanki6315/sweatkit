import Foundation
import SweatKitGarmin
import SweatKitModel
@testable import SweatKitSync
import Testing

func ids(_ values: Int64...) -> [SourceIdentity] { values.map(SourceIdentity.garminActivity) }

/// The quick sync and the deep scan, and which late uploads each catches.
/// "Today" is 5 November 2026 in UTC unless a test says otherwise.
@Suite struct DepthTests {
    @Test func aRideUploadedAWeekLateIsCaughtByAQuickSync() async throws {
        // A was synced before. B started on 29 October and reached Garmin a
        // week late. A quick sync lists from 5 November minus 30 days, open-ended:
        // 2026-10-06 onwards. One page holds both, B is unknown, so B alone is
        // downloaded.
        let a = ride(1, "2026-10-28 08:00:00")
        let b = ride(2, "2026-10-29 09:00:00")
        var world = World()
        world.add(a); world.add(b)
        let garmin = ScriptedGarmin(world)
        let library = InMemoryGarminLibrary(records: [known(a)], state: settledState())
        let clock = TestClock()

        let report = await makeSync(garmin, library, clock: clock).run(.quick)

        #expect(report.outcome == .completed)
        #expect(await garmin.log == [.range("2026-10-06", nil), .download(2)])
        #expect(report.added == ids(2))
        #expect(await library.actions == [.ingest(2, ContentHash(of: fitBytes(2, version: 1)))])
        // Two requests, paced 3 seconds apart.
        #expect(clock.now == t0.addingTimeInterval(3))
    }

    @Test func aRideUploadedMonthsLateIsCaughtByTheNextDeepScanAndNotByAQuickSync() async throws {
        // C started on 15 June and reached Garmin in November, after the last
        // pass over history finished at t0.
        let a = ride(1, "2026-10-28 08:00:00")
        let c = ride(3, "2026-06-15 07:00:00")
        var world = World()
        world.add(a); world.add(c)
        let garmin = ScriptedGarmin(world)
        let library = InMemoryGarminLibrary(records: [known(a)], state: settledState())
        let clock = TestClock()
        let sync = makeSync(garmin, library, clock: clock)

        // Day 0, quick: lists 2026-10-06 onwards. June is outside it.
        _ = await sync.run(.quick)
        // Day 6, routine: the deep scan is not yet due (the last pass finished
        // six days ago), so only the quick listing runs, from 2026-10-12.
        clock.advance(6 * day)
        let early = await sync.run(.routine)
        #expect(early.added.isEmpty)
        #expect(await garmin.log == [.range("2026-10-06", nil), .range("2026-10-12", nil)])

        // Day 7: a week since the last pass, so routine runs the deep scan after
        // its quick listing (from 2026-10-13). The ascending request finds C in
        // June, so months run November (open-ended) back to June, each listed
        // twice and settling at once. June holds the unknown C: one download.
        clock.advance(1 * day)
        let deep = await sync.run(.routine)
        #expect(deep.outcome == .completed)
        #expect(deep.added == ids(3))
        #expect(deep.pass == .finished(.deepScan))
        let expected: [Request] = [
            .range("2026-10-13", nil),
            .earliest,
            .range("2026-11-01", nil), .range("2026-11-01", nil),
            .range("2026-10-01", "2026-10-31"), .range("2026-10-01", "2026-10-31"),
            .range("2026-09-01", "2026-09-30"), .range("2026-09-01", "2026-09-30"),
            .range("2026-08-01", "2026-08-31"), .range("2026-08-01", "2026-08-31"),
            .range("2026-07-01", "2026-07-31"), .range("2026-07-01", "2026-07-31"),
            .range("2026-06-01", "2026-06-30"), .range("2026-06-01", "2026-06-30"),
            .download(3),
        ]
        #expect(Array(await garmin.log.dropFirst(2)) == expected)

        // The next routine run, a day later, owes no deep scan.
        clock.advance(1 * day)
        _ = await sync.run(.routine)
        #expect(await garmin.log.count == 2 + expected.count + 1)
    }

    @Test func monthsAndTodayAreLocalTime() async throws {
        // 03:00 UTC on 1 November is 20:00 on 31 October in Los Angeles, so
        // "today" is 31 October: the quick sync lists from 1 October, and the
        // newest month of the backfill is October, open-ended.
        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let clock = TestClock(Date(timeIntervalSince1970: 1_793_502_000))
        var world = World()
        world.add(ride(1, "2026-10-31 19:00:00"))
        let garmin = ScriptedGarmin(world)
        let library = InMemoryGarminLibrary()

        let report = await makeSync(garmin, library, clock: clock, calendar: losAngeles).run(.routine)

        #expect(report.outcome == .completed)
        #expect(await garmin.log == [
            .range("2026-10-01", nil), .download(1),
            .earliest,
            .range("2026-10-01", nil), .range("2026-10-01", nil),
        ])
        #expect(report.pass == .finished(.backfill))
    }

    @Test func aFullReconciliationListsEverythingAndDownloadsTheChosenFilesAgain() async throws {
        // Both rides are known. The user asks for ride 2's file again. The pass
        // runs at once, whatever the weekly schedule: earliest, November twice,
        // October twice, then download 2 only. Its original is unchanged, so
        // nothing is ingested.
        let one = ride(1, "2026-10-10 08:00:00")
        let two = ride(2, "2026-10-12 08:00:00")
        var world = World()
        world.add(one); world.add(two)
        let garmin = ScriptedGarmin(world)
        let library = InMemoryGarminLibrary(records: [known(one), known(two)], state: settledState())
        let clock = TestClock()

        let report = await makeSync(garmin, library, clock: clock).run(.fullReconciliation(.only(Set(ids(2)))))

        #expect(await garmin.log == [
            .earliest,
            .range("2026-11-01", nil), .range("2026-11-01", nil),
            .range("2026-10-01", "2026-10-31"), .range("2026-10-01", "2026-10-31"),
            .download(2),
        ])
        #expect(report.unchangedDownloads == ids(2))
        #expect(report.pass == .finished(.fullReconciliation))
        #expect(await library.actions.isEmpty)
    }
}
