import Foundation
import SweatKitGarmin
import SweatKitModel
@testable import SweatKitSync
import Testing

/// "Removed at source" is inferred only after a complete, successful listing of
/// the range that should hold the activity, and tombstones are final.
@Suite struct DeletionTests {
    let a = ride(1, "2026-10-20 08:00:00")
    let b = ride(2, "2026-10-22 08:00:00")
    let c = ride(3, "2026-10-25 08:00:00")

    @Test func aCompleteListingInfersTheDeletion() async throws {
        // B is in the quick window (from 6 October) and Garmin no longer lists
        // it. The listing is one page, so it is complete: B is removed at source.
        var world = World()
        world.add(a); world.add(c)
        let garmin = ScriptedGarmin(world)
        let library = InMemoryGarminLibrary(records: [known(a), known(b), known(c)], state: settledState())

        let report = await makeSync(garmin, library, clock: TestClock()).run(.quick)

        #expect(await garmin.log == [.range("2026-10-06", nil)])
        #expect(report.removedAtSource == ids(2))
        #expect(await library.actions == [.markRemoved(2)])
        // The record is kept, only marked.
        #expect(await library.records[.garminActivity(2)]?.removedAtSource == true)

        // A second run marks nothing again.
        let again = await makeSync(garmin, library, clock: TestClock(t0 + 60)).run(.quick)
        #expect(again.removedAtSource.isEmpty)
    }

    @Test func aFailedListingInfersNothing() async throws {
        var world = World()
        world.add(a); world.add(c)
        let garmin = ScriptedGarmin(world) { _, _, _ in .network(.notConnectedToInternet) }
        let library = InMemoryGarminLibrary(records: [known(a), known(b), known(c)], state: settledState())

        let report = await makeSync(garmin, library, clock: TestClock()).run(.quick)

        #expect(report.outcome == .listingFailed(.network(.notConnectedToInternet)))
        #expect(report.removedAtSource.isEmpty)
        #expect(await library.actions.isEmpty)
    }

    @Test func anInterruptedListingInfersNothing() async throws {
        // 100 rides in the quick window need two pages. The second page fails,
        // so the listing is incomplete: B is not marked, and nothing from the
        // first page is acted on either.
        var world = World()
        for i in 0..<100 { world.add(ride(100 + Int64(i), String(format: "2026-10-%02d 08:%02d:00", 10 + i / 50, i % 50))) }
        let garmin = ScriptedGarmin(world) { index, _, _ in index == 1 ? .network(.timedOut) : nil }
        let library = InMemoryGarminLibrary(records: [known(b)], state: settledState())

        let report = await makeSync(garmin, library, clock: TestClock()).run(.quick)

        #expect(await garmin.log == [.range("2026-10-06", nil, offset: 0), .range("2026-10-06", nil, offset: 89)])
        #expect(report.outcome == .listingFailed(.network(.timedOut)))
        #expect(await library.actions.isEmpty)
    }

    @Test func aPagedQuickListingLeavesRemovalsToTheDeepScan() async throws {
        // The same 100 rides, and both pages succeed. Pages fetched apart are
        // not one consistent view, so the quick sync ingests the 100 but does
        // not infer B's removal. The next deep scan, whose October listings
        // settle, does.
        var world = World()
        for i in 0..<100 { world.add(ride(100 + Int64(i), String(format: "2026-10-%02d 08:%02d:00", 10 + i / 50, i % 50))) }
        let garmin = ScriptedGarmin(world)
        let library = InMemoryGarminLibrary(records: [known(b)], state: settledState(at: t0 - 8 * day))
        let sync = makeSync(garmin, library, clock: TestClock())

        let quick = await sync.run(.quick)
        #expect(quick.added.count == 100)
        #expect(quick.removedAtSource.isEmpty)

        let deep = await sync.run(.routine)
        #expect(deep.pass == .finished(.deepScan))
        #expect(deep.removedAtSource == ids(2))
    }

    @Test func aDeletionInAnOldMonthIsFoundByTheDeepScanAndAReturnIsNoticed() async throws {
        // J started in June and has gone from Garmin. A quick sync cannot see
        // June; the deep scan, due because the last pass was 8 days ago, lists
        // June twice and marks J removed. When Garmin lists J again, a full
        // reconciliation clears the mark.
        let j = ride(4, "2026-06-10 08:00:00")
        let garmin = ScriptedGarmin(World())
        let library = InMemoryGarminLibrary(records: [known(j)], state: settledState(at: t0 - 8 * day))
        let clock = TestClock()
        let sync = makeSync(garmin, library, clock: clock)

        let quick = await sync.run(.quick)
        #expect(quick.removedAtSource.isEmpty)

        let deep = await sync.run(.routine)
        // Garmin lists nothing, so the earliest month is J's own, from the library.
        #expect(Array(await garmin.log.suffix(2)) == [.range("2026-06-01", "2026-06-30"), .range("2026-06-01", "2026-06-30")])
        #expect(deep.removedAtSource == ids(4))

        await garmin.change { $0.add(j) }
        let full = await sync.run(.fullReconciliation(.none))
        #expect(full.presentAgain == ids(4))
        #expect(full.added.isEmpty)
        #expect(await library.actions == [.markRemoved(4), .markPresent(4)])
    }

    @Test func aTombstonedIdentityStaysGone() async throws {
        // 7 was permanently deleted in the app and only its tombstone remains;
        // Garmin still lists it. 8 was hidden: its record and tombstone remain,
        // and Garmin no longer lists it. Neither a quick sync nor a full
        // reconciliation that downloads every file touches either.
        let seven = ride(7, "2026-10-20 08:00:00")
        let eight = ride(8, "2026-10-21 08:00:00")
        var world = World()
        world.add(seven)
        let garmin = ScriptedGarmin(world)
        let library = InMemoryGarminLibrary(records: [known(eight)], tombstones: [7, 8], state: settledState())
        let sync = makeSync(garmin, library, clock: TestClock())

        let quick = await sync.run(.quick)
        #expect(await garmin.log == [.range("2026-10-06", nil)])
        #expect(quick.added.isEmpty && quick.removedAtSource.isEmpty)

        let full = await sync.run(.fullReconciliation(.all))
        #expect(full.outcome == .completed)
        #expect(!(await garmin.log).contains(.download(7)))
        #expect(await library.actions.isEmpty)
    }
}
