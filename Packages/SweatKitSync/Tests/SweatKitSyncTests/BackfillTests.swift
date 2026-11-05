import Foundation
import SweatKitGarmin
import SweatKitModel
@testable import SweatKitSync
import Testing

/// The first-sync backfill and the two-listing check. "Today" is 5 November
/// 2026 in UTC, and requests are 3 seconds apart, so request k is sent at
/// t0 + 3k within one run.
@Suite struct BackfillTests {
    let october = ("2026-10-01", "2026-10-31")

    /// `count` rides from 1 to 5 October, newest last by ID, all before the
    /// quick-sync window (which starts on 6 October).
    func earlyOctober(_ count: Int, firstID: Int64) -> [GarminSummary] {
        (0..<count).map { i in
            ride(firstID + Int64(i), String(format: "2026-10-%02d %02d:%02d:00", 1 + i / 30, 6 + (i % 30) / 6, (i % 6) * 10))
        }
    }

    @Test func anInterruptedBackfillResumesAtTheFirstIncompleteMonth() async throws {
        let n1 = ride(11, "2026-11-02 08:00:00")
        let o1 = ride(21, "2026-10-20 08:00:00")
        let o2 = ride(22, "2026-10-01 08:00:00")
        let a1 = ride(31, "2026-08-10 08:00:00")
        let j1 = ride(41, "2026-07-03 08:00:00")
        var world = World()
        for summary in [n1, o1, o2, a1, j1] { world.add(summary) }
        // Garmin rate-limits the twelfth request, the first listing of August,
        // and asks for 600 seconds.
        let garmin = ScriptedGarmin(world) { index, _, _ in index == 11 ? .rateLimited(retryAfter: 600) : nil }
        let library = InMemoryGarminLibrary()
        let clock = TestClock()
        let sync = makeSync(garmin, library, clock: clock)

        // Run 1. Quick listing from 6 October finds N1 and O1, both new.
        // The ascending request finds J1, so the backfill covers November back
        // to July. November and October settle at the second listing (O2 is
        // downloaded in October), September is empty and settles, and the first
        // August listing is refused.
        let first = await sync.run(.routine)
        let run1: [Request] = [
            .range("2026-10-06", nil), .download(11), .download(21),
            .earliest,
            .range("2026-11-01", nil), .range("2026-11-01", nil),
            .range(october.0, october.1), .range(october.0, october.1), .download(22),
            .range("2026-09-01", "2026-09-30"), .range("2026-09-01", "2026-09-30"),
            .range("2026-08-01", "2026-08-31"),
        ]
        #expect(await garmin.log == run1)
        // Request 11 went at t0 + 33 s, so the wait ends at t0 + 633 s.
        let until = t0.addingTimeInterval(633)
        #expect(first.outcome == .rateLimited(until: until))
        #expect(first.added == ids(11, 21, 22))
        #expect(first.pass == .inProgress(.backfill, completedMonths: 3))
        let checkpoint = try #require(await library.state)
        #expect(checkpoint.pass?.completed == Set([CalendarMonth(year: 2026, month: 11)!, CalendarMonth(year: 2026, month: 10)!, CalendarMonth(year: 2026, month: 9)!]))
        #expect(checkpoint.backfillFinished == nil)

        // Run 2, before the wait ends: nothing is sent.
        let waiting = await sync.run(.routine)
        #expect(waiting.outcome == .rateLimited(until: until))
        #expect(waiting.requests == 0)
        #expect(await garmin.log.count == run1.count)

        // Run 3, once the wait is over: the quick listing changes nothing, the
        // backfill skips the three checkpointed months and resumes at August.
        clock.advance(600)
        let third = await sync.run(.routine)
        #expect(third.outcome == .completed)
        #expect(Array(await garmin.log.dropFirst(run1.count)) == [
            .range("2026-10-06", nil),
            .earliest,
            .range("2026-08-01", "2026-08-31"), .range("2026-08-01", "2026-08-31"), .download(31),
            .range("2026-07-01", "2026-07-31"), .range("2026-07-01", "2026-07-31"), .download(41),
        ])
        #expect(third.pass == .finished(.backfill))

        // No gaps and no duplicates: every activity ingested exactly once.
        #expect(await library.ingestedIDs == [11, 21, 22, 31, 41])
        #expect(await library.state?.backfillFinished != nil)
    }

    @Test func aMonthOfMoreThan99ActivitiesIsPagedWithTheOverlap() async throws {
        // 150 rides in early October. Each listing of October is two pages: the
        // first at offset 0 returns 99; the next starts 10 entries back, at
        // 99 - 10 = 89, and returns the remaining 150 - 89 = 61, a short page
        // that ends the listing. The two listings agree, so October settles
        // after four requests, then all 150 are downloaded once each.
        let rides = earlyOctober(150, firstID: 1000)
        var world = World()
        for summary in rides { world.add(summary) }
        let garmin = ScriptedGarmin(world)
        let library = InMemoryGarminLibrary()

        let report = await makeSync(garmin, library, clock: TestClock()).run(.routine)

        let log = await garmin.log
        #expect(Array(log.prefix(8)) == [
            .range("2026-10-06", nil),
            .earliest,
            .range("2026-11-01", nil), .range("2026-11-01", nil),
            .range(october.0, october.1, offset: 0), .range(october.0, october.1, offset: 89),
            .range(october.0, october.1, offset: 0), .range(october.0, october.1, offset: 89),
        ])
        #expect(log.count == 8 + 150)
        #expect(report.added.count == 150)
        let ingested = await library.ingestedIDs
        #expect(ingested.count == 150)
        #expect(Set(ingested) == Set(rides.map(\.activityID)))
    }

    @Test func insertsAndDeletesDuringPagingMissNothingAndDuplicateNothing() async throws {
        // The spec's own test. 120 rides in early October. While the first
        // October listing is between its pages, 5 rides newer than all of them
        // are uploaded and 2 rides that page one already returned are deleted.
        //
        // Listing 1: page one (offset 0) returns the 99 newest originals. The
        // order has then shifted by +5 - 2 = 3, so page two at offset 89 starts
        // at original 86 and returns the 34 entries left (123 - 89). The overlap
        // covers the shift. Listing 1 holds all 120 originals, including the 2
        // now deleted, and none of the 5 new.
        // Listing 2: 123 entries in two pages, 99 and 34. Differs from 1.
        // Listing 3: the same 123. Matches 2, so October settles.
        // Then the 123 that exist are downloaded once each, newest first.
        let rides = earlyOctober(120, firstID: 2000)
        let newest = (0..<5).map { ride(2200 + Int64($0), "2026-10-05 23:0\($0):00") }
        let byNewest = rides.sorted { $0.startTimeLocal! > $1.startTimeLocal! }
        let deleted = [byNewest[10].activityID, byNewest[11].activityID]
        var world = World()
        for summary in rides { world.add(summary) }
        let garmin = ScriptedGarmin(world) { index, _, world in
            if index == 5 {
                for summary in newest { world.add(summary) }
                for id in deleted { world.remove(id) }
            }
            return nil
        }
        let library = InMemoryGarminLibrary()

        let report = await makeSync(garmin, library, clock: TestClock()).run(.routine)

        let log = await garmin.log
        let octoberPages: [Request] = [0, 89, 0, 89, 0, 89].map { .range(october.0, october.1, offset: $0) }
        #expect(Array(log.prefix(10)) == [.range("2026-10-06", nil), .earliest, .range("2026-11-01", nil), .range("2026-11-01", nil)] + octoberPages)
        #expect(log.count == 10 + 123)
        #expect(report.outcome == .completed)

        let exists = Set(await garmin.world.activities.keys)
        #expect(exists.count == 123)
        let ingested = await library.ingestedIDs
        #expect(ingested.count == 123)
        #expect(Set(ingested) == exists)
        #expect(deleted.allSatisfy { !ingested.contains($0) })
    }

    @Test func aDeletionLargerThanTheOverlapStillSettlesWithNothingMissed() async throws {
        // 120 rides. Between the pages of the first October listing, the 15
        // newest are deleted. Page two at offset 89 now starts at original
        // 89 + 15 = 104, so originals 99 to 103 slip between the pages and none
        // of page one's last 10 appear in page two: listing 1 is not joined and
        // cannot count.
        // Listing 2: 105 entries, pages of 99 and 16, joined. Listing 3: the
        // same. October settles, and all 105 that exist are ingested, including
        // the 5 that listing 1 missed.
        let rides = earlyOctober(120, firstID: 3000)
        let byNewest = rides.sorted { $0.startTimeLocal! > $1.startTimeLocal! }
        let deleted = byNewest.prefix(15).map(\.activityID)
        let slipped = byNewest[99...103].map(\.activityID)
        var world = World()
        for summary in rides { world.add(summary) }
        let garmin = ScriptedGarmin(world) { index, _, world in
            if index == 5 { for id in deleted { world.remove(id) } }
            return nil
        }
        let library = InMemoryGarminLibrary()

        _ = await makeSync(garmin, library, clock: TestClock()).run(.routine)

        let log = await garmin.log
        #expect(Array(log[4..<10]) == [0, 89, 0, 89, 0, 89].map { .range(october.0, october.1, offset: $0) })
        let ingested = Set(await library.ingestedIDs)
        #expect(ingested == Set(byNewest.dropFirst(15).map(\.activityID)))
        #expect(slipped.allSatisfy(ingested.contains))
        #expect(await library.ingestedIDs.count == 105)
    }

    @Test func aRangeThatNeverSettlesIsLeftForTheDeepScan() async throws {
        // One ride in September. Before every September listing in the first
        // run, a new September ride appears, so no two listings agree. September
        // is listed twice, then again three times, five in all, and left
        // unsettled with nothing ingested from it.
        let s0 = ride(51, "2026-09-10 08:00:00")
        var world = World()
        world.add(s0)
        let garmin = ScriptedGarmin(world) { index, request, world in
            if case .list(let query) = request, query.startDate == date("2026-09-01") {
                world.add(ride(600 + Int64(index), "2026-09-20 08:00:00"))
            }
            return nil
        }
        let library = InMemoryGarminLibrary()
        let clock = TestClock()
        let sync = makeSync(garmin, library, clock: clock)

        let first = await sync.run(.routine)
        let september = Request.range("2026-09-01", "2026-09-30")
        #expect(await garmin.log == [
            .range("2026-10-06", nil),
            .earliest,
            .range("2026-11-01", nil), .range("2026-11-01", nil),
            .range(october.0, october.1), .range(october.0, october.1),
            september, september, september, september, september,
        ])
        let sept = CalendarMonth(year: 2026, month: 9)!
        #expect(first.unsettledMonths == [sept])
        #expect(first.pass == .finished(.backfill))
        #expect(await library.state?.unsettledMonths == [sept])
        #expect(await library.ingestedIDs.isEmpty)

        // The uploads stop. A day later the deep scan is not due, so September
        // waits. Six days after that it is, and September settles.
        await garmin.setHook(nil)
        clock.advance(1 * day)
        _ = await sync.run(.routine)
        #expect(await garmin.log.count == 12)
        clock.advance(6 * day)
        let deep = await sync.run(.routine)
        // Quick from 13 October, earliest, November and October twice each,
        // September twice, then six downloads: the five inserted rides share a
        // start time, so newest-first breaks the tie by ID, highest first.
        #expect(Array(await garmin.log.dropFirst(12)) == [
            .range("2026-10-13", nil),
            .earliest,
            .range("2026-11-01", nil), .range("2026-11-01", nil),
            .range(october.0, october.1), .range(october.0, october.1),
            september, september,
            .download(610), .download(609), .download(608), .download(607), .download(606), .download(51),
        ])
        #expect(deep.pass == .finished(.deepScan))
        #expect(await library.state?.unsettledMonths == [])
    }
}
