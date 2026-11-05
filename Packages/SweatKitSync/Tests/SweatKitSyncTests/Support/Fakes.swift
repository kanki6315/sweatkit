import Compression
import Foundation
import Synchronization
import SweatKitGarmin
import SweatKitModel
@testable import SweatKitSync

// MARK: Scripted Garmin

/// One request the fake answered.
enum Request: Equatable, CustomStringConvertible {
    case list(ActivityQuery)
    case detail(Int64)
    case download(Int64)

    var description: String {
        switch self {
        case .list(let q):
            "list(\(q.order.rawValue) \(q.startDate?.description ?? "-")...\(q.endDate?.description ?? "-") @\(q.start)+\(q.limit))"
        case .detail(let id): "detail(\(id))"
        case .download(let id): "download(\(id))"
        }
    }

    /// A descending month or open range listing, as sync sends it.
    static func range(_ start: String, _ end: String?, offset: Int = 0, limit: Int = 99) -> Request {
        .list(ActivityQuery(start: offset, limit: limit, order: .descending, startDate: date(start), endDate: end.map(date)))
    }

    /// The single earliest activity.
    static let earliest = Request.list(ActivityQuery(start: 0, limit: 1, order: .ascending))
}

/// What the fake Garmin holds: each activity's listing entry and original.
struct World {
    var activities: [Int64: (summary: GarminSummary, original: Data)] = [:]
    /// Downloads of these come back as bytes that are not a zip.
    var damaged: Set<Int64> = []

    mutating func add(_ summary: GarminSummary, original: Data? = nil) {
        activities[summary.activityID] = (summary, original ?? fitBytes(summary.activityID, version: 1))
    }

    mutating func remove(_ id: Int64) { activities[id] = nil }
}

/// A Garmin that answers from `world` and keeps every request. A hook runs
/// before each answer with the request's index; it may change the world, and
/// may return an error to answer with instead.
actor ScriptedGarmin: GarminRemoteSource {
    typealias Hook = @Sendable (_ index: Int, _ request: Request, _ world: inout World) -> GarminError?

    var world: World
    private(set) var log: [Request] = []
    private var hook: Hook?

    init(_ world: World = World(), hook: Hook? = nil) {
        self.world = world
        self.hook = hook
    }

    func setHook(_ hook: Hook?) { self.hook = hook }
    func change(_ edit: @Sendable (inout World) -> Void) { edit(&world) }

    private func record(_ request: Request) throws(GarminError) {
        let index = log.count
        log.append(request)
        if let error = hook?(index, request, &world) { throw error }
    }

    func listActivities(_ query: ActivityQuery) async throws(GarminError) -> [GarminSummary] {
        try record(.list(query))
        let matching = world.activities.values.map(\.summary).filter { summary in
            guard let date = summary.startDate else { return false }
            if let start = query.startDate, date < start { return false }
            if let end = query.endDate, date > end { return false }
            return true
        }
        let ascending = matching.sorted { ($0.startTimeLocal ?? "", $0.activityID) < ($1.startTimeLocal ?? "", $1.activityID) }
        let ordered = query.order == .ascending ? ascending : ascending.reversed()
        return Array(ordered.dropFirst(query.start).prefix(query.limit))
    }

    func activityDetail(id: Int64) async throws(GarminError) -> GarminActivityDetail {
        try record(.detail(id))
        guard let activity = world.activities[id] else { throw .unexpectedResponse(UnexpectedResponse(status: 404, reason: .status)) }
        return GarminActivityDetail(summary: activity.summary)
    }

    func downloadOriginal(id: Int64) async throws(GarminError) -> Data {
        try record(.download(id))
        guard let activity = world.activities[id] else { throw .unexpectedResponse(UnexpectedResponse(status: 404, reason: .status)) }
        if world.damaged.contains(id) { return Data("<html>Service unavailable</html>".utf8) }
        return makeZip([ZipItem(name: "\(id)_ACTIVITY.fit", data: activity.original, method: .stored)])
    }
}

// MARK: In-memory library

/// The library, in memory, for tests only. Keeps every action asked of it.
actor InMemoryGarminLibrary: GarminLibrary {
    enum Action: Equatable {
        case ingest(Int64, ContentHash)
        case updateSummary(Int64)
        case markRemoved(Int64)
        case markPresent(Int64)
    }

    private(set) var records: [SourceIdentity: KnownGarminActivity]
    private(set) var originals: [SourceIdentity: [Data]] = [:]
    private(set) var tombstones: Set<SourceIdentity>
    private(set) var state: GarminSyncState?
    private(set) var actions: [Action] = []
    /// Ingests of these IDs throw.
    var refuseIngest: Set<Int64> = []

    init(records: [KnownGarminActivity] = [], tombstones: Set<Int64> = [], state: GarminSyncState? = nil) {
        self.records = Dictionary(uniqueKeysWithValues: records.map { ($0.summary.identity, $0) })
        self.tombstones = Set(tombstones.map(SourceIdentity.garminActivity))
        self.state = state
    }

    func knownGarminActivities() async throws -> [SourceIdentity: KnownGarminActivity] { records }
    func garminTombstones() async throws -> Set<SourceIdentity> { tombstones }
    func loadSyncState() async throws -> GarminSyncState? { state }
    func saveSyncState(_ state: GarminSyncState) async throws { self.state = state }

    func ingestOriginal(_ original: Data, contentHash: ContentHash, as identity: SourceIdentity, summary: GarminSummary) async throws {
        if refuseIngest.contains(summary.activityID) { throw CocoaError(.fileWriteUnknown) }
        precondition(ContentHash(of: original) == contentHash)
        precondition(!tombstones.contains(identity), "a tombstoned identity was brought back")
        actions.append(.ingest(summary.activityID, contentHash))
        originals[identity, default: []].append(original)
        records[identity] = KnownGarminActivity(summary: summary, contentHash: contentHash, removedAtSource: false)
    }

    func updateSummary(_ summary: GarminSummary, for identity: SourceIdentity) async throws {
        actions.append(.updateSummary(summary.activityID))
        records[identity]?.summary = summary
    }

    func markRemovedAtSource(_ identity: SourceIdentity) async throws {
        actions.append(.markRemoved(identity.garminActivityID!))
        records[identity]?.removedAtSource = true
    }

    func markPresentAtSource(_ identity: SourceIdentity) async throws {
        actions.append(.markPresent(identity.garminActivityID!))
        records[identity]?.removedAtSource = false
    }

    func setRefuseIngest(_ ids: Set<Int64>) { refuseIngest = ids }

    var ingestedIDs: [Int64] {
        actions.compactMap { if case .ingest(let id, _) = $0 { id } else { nil } }
    }
    var recordIDs: Set<Int64> { Set(records.keys.compactMap(\.garminActivityID)) }
}

// MARK: Clock

/// Virtual time: sleeping moves it forward at once.
final class TestClock: SyncClock {
    private let current: Mutex<Date>

    init(_ start: Date = t0) { current = Mutex(start) }

    var now: Date { current.withLock { $0 } }
    func sleep(until deadline: Date) async throws { current.withLock { $0 = max($0, deadline) } }
    func advance(_ seconds: TimeInterval) { current.withLock { $0.addTimeInterval(seconds) } }
}

/// 2026-11-05 12:00:00 UTC, a Thursday.
let t0 = Date(timeIntervalSince1970: 1_793_880_000)
let day: TimeInterval = 24 * 60 * 60

var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}

func makeSync(_ garmin: ScriptedGarmin, _ library: InMemoryGarminLibrary, clock: TestClock, calendar: Calendar = utc) -> GarminSync {
    GarminSync(remote: garmin, library: library, clock: clock, calendar: calendar)
}

/// A library state for a backfill that finished at `t0`.
func settledState(at date: Date = t0) -> GarminSyncState {
    GarminSyncState(backfillFinished: date, lastPassFinished: date)
}

// MARK: Activities

func date(_ text: String) -> CalendarDate { CalendarDate(prefixOf: text)! }

/// A ride starting at `start`, local and UTC alike.
func ride(_ id: Int64, _ start: String, duration: Double = 3600, distance: Double = 30_000, name: String = "Ride") -> GarminSummary {
    GarminSummary(activityID: id, name: name, typeKey: "road_biking", startTimeLocal: start, startTimeGMT: start, duration: duration, elapsedDuration: duration, distance: distance)
}

/// Stand-in bytes for an original FIT file. Sync never decodes them.
func fitBytes(_ id: Int64, version: Int) -> Data { Data("FIT activity \(id) version \(version)".utf8) }

func known(_ summary: GarminSummary, version: Int = 1) -> KnownGarminActivity {
    KnownGarminActivity(summary: summary, contentHash: ContentHash(of: fitBytes(summary.activityID, version: version)))
}

// MARK: Zip building

struct ZipItem {
    enum Method { case stored, deflated }
    var name: String
    var data: Data
    var method: Method
}

/// Writes a zip: local headers and data, then the central directory, then the
/// end record. Deflated data is raw DEFLATE from the Compression framework.
func makeZip(_ items: [ZipItem]) -> Data {
    var out = [UInt8]()
    var central = [UInt8]()
    func u16(_ v: Int, _ into: inout [UInt8]) { into += [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)] }
    func u32(_ v: UInt32, _ into: inout [UInt8]) { into += (0..<4).map { UInt8((v >> (8 * $0)) & 0xFF) } }

    for item in items {
        let raw = [UInt8](item.data)
        let stored: [UInt8] = item.method == .stored ? raw : deflate(raw)
        let method = item.method == .stored ? 0 : 8
        let crc = CRC32.checksum(raw)
        let name = [UInt8](item.name.utf8)
        let offset = out.count

        u32(0x0403_4B50, &out); u16(20, &out); u16(0, &out); u16(method, &out); u16(0, &out); u16(0, &out)
        u32(crc, &out); u32(UInt32(stored.count), &out); u32(UInt32(raw.count), &out)
        u16(name.count, &out); u16(0, &out); out += name; out += stored

        u32(0x0201_4B50, &central); u16(20, &central); u16(20, &central); u16(0, &central); u16(method, &central)
        u16(0, &central); u16(0, &central); u32(crc, &central); u32(UInt32(stored.count), &central); u32(UInt32(raw.count), &central)
        u16(name.count, &central); u16(0, &central); u16(0, &central); u16(0, &central); u16(0, &central)
        u32(0, &central); u32(UInt32(offset), &central); central += name
    }
    let directoryOffset = out.count
    out += central
    u32(0x0605_4B50, &out); u16(0, &out); u16(0, &out); u16(items.count, &out); u16(items.count, &out)
    u32(UInt32(central.count), &out); u32(UInt32(directoryOffset), &out); u16(0, &out)
    return Data(out)
}

func deflate(_ input: [UInt8]) -> [UInt8] {
    var output = [UInt8](repeating: 0, count: input.count + 1024)
    let written = output.withUnsafeMutableBufferPointer { destination in
        input.withUnsafeBufferPointer { source in
            compression_encode_buffer(destination.baseAddress!, destination.count, source.baseAddress!, source.count, nil, COMPRESSION_ZLIB)
        }
    }
    precondition(written > 0)
    return Array(output.prefix(written))
}
