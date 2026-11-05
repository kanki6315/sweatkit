import Foundation
import Synchronization
import SweatKitGarmin
import SweatKitLibrary
import SweatKitModel
import SweatKitSync
import SweatKitTestSupport
import Testing

/// Real FIT decoder, disk store and checkpoint adapter behind the real planner.
@Suite struct GarminJourneyTests {
    let temporary = TemporaryLibrary()
    private let clock = JourneyClock()
    func bridge(_ library: ActivityLibrary) -> PersistentGarminLibrary {
        PersistentGarminLibrary(library: library, metadataURL: temporary.root.appendingPathComponent("garmin-journey.json"))
    }
    private func engine(_ remote: JourneyRemote, _ library: ActivityLibrary, smallPages: Bool = false) -> GarminSync {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var config = SyncConfiguration()
        if smallPages { config.pageSize = 2; config.pageOverlap = 1 }
        return GarminSync(remote: remote, library: bridge(library), clock: clock, calendar: calendar, configuration: config)
    }
    @Test func lateUploadsAreCaughtAtTheirDepthAndPersistWithoutDuplicates() async throws {
        let library = try temporary.open()
        let remote = JourneyRemote()
        try await remote.add(1, date: "2026-10-28", fixture: .outdoorRide)
        #expect(await engine(remote, library).run(.routine).outcome == .completed)
        try await remote.add(2, date: "2026-07-20", fixture: .walk)
        try await remote.add(3, date: "2026-10-30", fixture: .zwiftRide)
        #expect(await engine(remote, library).run(.quick).outcome == .completed)
        #expect(Set(try await bridge(library).knownGarminActivities().keys) == [id(1), id(3)])
        clock.advance(days: 8)
        let restarted = try temporary.open()
        #expect(await engine(remote, restarted).run(.routine).outcome == .completed)
        #expect(Set(try await bridge(restarted).knownGarminActivities().keys) == [id(1), id(2), id(3)])
        #expect(try await restarted.feed(limit: 10).activities.count == 3)
        #expect(await engine(remote, restarted).run(.routine).added.isEmpty)
        #expect(try await restarted.store.sourceRecords().allSatisfy { $0.revisions.count == 1 })
    }

    @Test func failedBackfillResumesThenOnlyStableListingInfersRemoval() async throws {
        let library = try temporary.open()
        let remote = JourneyRemote()
        try await remote.add(1, date: "2026-10-01", fixture: .outdoorRide)
        try await remote.add(2, date: "2026-09-01", fixture: .walk)
        try await remote.add(3, date: "2026-08-01", fixture: .zwiftRide)
        await remote.fail(month: "2026-09")
        #expect(await engine(remote, library).run(.routine).outcome == .listingFailed(.network(.notConnectedToInternet)))
        let checkpoint = try #require(try await bridge(library).loadSyncState())
        #expect(checkpoint.pass?.completed.contains(CalendarMonth(year: 2026, month: 10)!) == true)
        #expect(Set(try await bridge(library).knownGarminActivities().keys) == [id(1)])
        let restarted = try temporary.open()
        await remote.fail(month: nil)
        #expect(await engine(remote, restarted).run(.routine).outcome == .completed)
        #expect(try await restarted.feed(limit: 10).activities.count == 3)
        await remote.remove(2)
        await remote.fail(month: "2026-09")
        #expect(await engine(remote, restarted).run(.fullReconciliation(.all)).outcome == .listingFailed(.network(.notConnectedToInternet)))
        #expect(try await bridge(restarted).knownGarminActivities()[id(2)]?.removedAtSource == false)
        await remote.fail(month: nil)
        #expect(await engine(remote, restarted).run(.routine).outcome == .completed)
        #expect(try await bridge(restarted).knownGarminActivities()[id(2)]?.removedAtSource == true)
        #expect(try await restarted.feed(limit: 10).activities.count == 3)
        let removed = try #require(try await restarted.store.sourceRecord(id(2)))
        #expect(try await restarted.store.original(removed.currentRevision) != nil)
    }

    @Test func cancellationKeepsCompletedMonthsAndResumesAfterReopen() async throws {
        let library = try temporary.open()
        let remote = JourneyRemote()
        try await remote.add(1, date: "2026-10-01", fixture: .outdoorRide)
        try await remote.add(2, date: "2026-09-01", fixture: .walk)
        await remote.pause(month: "2026-09")
        let sync = engine(remote, library)
        let task = Task { await sync.run(.routine) }
        await remote.waitForPause()
        task.cancel()
        await remote.releasePause()
        #expect(await task.value.outcome == .interrupted)
        #expect(Set(try await bridge(library).knownGarminActivities().keys) == [id(1)])
        let reopened = try temporary.open()
        #expect(await engine(remote, reopened).run(.routine).outcome == .completed)
        #expect(Set(try await bridge(reopened).knownGarminActivities().keys) == [id(1), id(2)])
        #expect(try await reopened.feed(limit: 10).activities.count == 2)
    }

    @Test func changingPagesSettleWithEverySurvivingIdentity() async throws {
        let library = try temporary.open()
        let remote = JourneyRemote()
        try await remote.add(1, date: "2026-09-01", fixture: .outdoorRide)
        try await remote.add(2, date: "2026-09-02", fixture: .walk)
        try await remote.add(3, date: "2026-09-03", fixture: .zwiftRide)
        try await remote.add(4, date: "2026-09-04", fixture: .walkPitlane)
        await remote.changeOnNextPage()
        #expect(await engine(remote, library, smallPages: true).run(.routine).outcome == .completed)
        let reopened = try temporary.open()
        #expect(await engine(remote, reopened, smallPages: true).run(.fullReconciliation(.none)).outcome == .completed)
        let known = try await bridge(reopened).knownGarminActivities()
        #expect(Set(known.filter { !$0.value.removedAtSource }.keys) == [id(1), id(3), id(4), id(5)])
        #expect(try await reopened.store.sourceRecords().allSatisfy { $0.revisions.count == 1 })
    }
}

private func id(_ value: Int64) -> SourceIdentity { SourceIdentity(source: .garmin, externalID: String(value)) }
private final class JourneyClock: SyncClock {
    private let value = Mutex(Date(timeIntervalSince1970: 1_793_880_000))
    var now: Date { value.withLock { $0 } }
    func sleep(until deadline: Date) async throws { try Task.checkCancellation(); value.withLock { $0 = max($0, deadline) } }
    func advance(days: Int) { value.withLock { $0.addTimeInterval(Double(days) * 86400) } }
}
private actor JourneyRemote: GarminRemoteSource {
    var records: [Int64: (GarminSummary, Data)] = [:]
    var failingMonth: String?
    var changesPage = false
    var pauseMonth: String?
    var pauseWaiter: CheckedContinuation<Void, Never>?
    var releaseWaiter: CheckedContinuation<Void, Never>?
    func pause(month: String) { pauseMonth = month }
    func waitForPause() async {
        if releaseWaiter != nil { return }
        await withCheckedContinuation { pauseWaiter = $0 }
    }
    func releasePause() { releaseWaiter?.resume(); releaseWaiter = nil }

    func add(_ id: Int64, date: String, fixture: Fixtures.FIT) throws {
        records[id] = (GarminSummary(activityID: id, startTimeLocal: date + "T12:00:00"), try fixture.data())
    }
    func remove(_ id: Int64) { records[id] = nil }
    func fail(month: String?) { failingMonth = month }
    func changeOnNextPage() { changesPage = true }
    func listActivities(_ query: ActivityQuery) async throws(GarminError) -> [GarminSummary] {
        if let month = pauseMonth, query.startDate?.description.hasPrefix(month) == true {
            pauseMonth = nil
            await withCheckedContinuation { continuation in
                releaseWaiter = continuation
                pauseWaiter?.resume()
                pauseWaiter = nil
            }
        }
        if let month = failingMonth, query.startDate?.description.hasPrefix(month) == true { throw .network(.notConnectedToInternet) }
        if changesPage && query.start > 0 {
            changesPage = false
            let bytes = records[2]!.1
            records[2] = nil
            records[5] = (GarminSummary(activityID: 5, startTimeLocal: "2026-09-05T12:00:00"), bytes)
        }
        let sorted = records.values.map(\.0).filter {
            guard let date = $0.startDate else { return false }
            return (query.startDate == nil || date >= query.startDate!) && (query.endDate == nil || date <= query.endDate!)
        }.sorted { ($0.startTimeLocal ?? "", $0.activityID) < ($1.startTimeLocal ?? "", $1.activityID) }
        let ordered = query.order == .ascending ? sorted : sorted.reversed()
        return Array(ordered.dropFirst(query.start).prefix(query.limit))
    }
    func activityDetail(id: Int64) async throws(GarminError) -> GarminActivityDetail {
        guard let row = records[id] else { throw .network(.notConnectedToInternet) }
        return GarminActivityDetail(summary: row.0)
    }
    func downloadOriginal(id: Int64) async throws(GarminError) -> Data {
        guard let row = records[id] else { throw .network(.notConnectedToInternet) }
        return storedZip(row.1)
    }
}

/// One stored entry with a genuine CRC, to exercise the production ZIP reader.
private func storedZip(_ bytes: Data) -> Data {
    var crc: UInt32 = 0xffff_ffff
    for byte in bytes { crc ^= UInt32(byte); for _ in 0..<8 { crc = (crc >> 1) ^ (crc & 1 == 1 ? 0xedb8_8320 : 0) } }
    crc ^= 0xffff_ffff
    let name = Data("activity.fit".utf8)
    var output = Data()
    func u16(_ value: UInt16) { output.append(UInt8(value & 255)); output.append(UInt8(value >> 8)) }
    func u32(_ value: UInt32) { u16(UInt16(value & 65535)); u16(UInt16(value >> 16)) }
    u32(0x04034b50); u16(20); u16(0); u16(0); u16(0); u16(0); u32(crc)
    u32(UInt32(bytes.count)); u32(UInt32(bytes.count)); u16(UInt16(name.count)); u16(0)
    output.append(name); output.append(bytes)
    let offset = output.count
    u32(0x02014b50); u16(20); u16(20); u16(0); u16(0); u16(0); u16(0); u32(crc)
    u32(UInt32(bytes.count)); u32(UInt32(bytes.count)); u16(UInt16(name.count)); u16(0); u16(0); u16(0); u16(0); u32(0); u32(0)
    output.append(name)
    let size = output.count - offset
    u32(0x06054b50); u16(0); u16(0); u16(1); u16(1); u32(UInt32(size)); u32(UInt32(offset)); u16(0)
    return output
}
