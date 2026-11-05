import Foundation
import SweatKitGarmin

/// The time source and the waiting, injected so tests run instantly.
public protocol SyncClock: Sendable {
    var now: Date { get }
    /// Returns at or after `deadline`. Throws if the task is cancelled.
    func sleep(until deadline: Date) async throws
}

/// The wall clock.
public struct SystemSyncClock: SyncClock {
    public init() {}

    public var now: Date { Date() }

    public func sleep(until deadline: Date) async throws {
        let seconds = deadline.timeIntervalSinceNow
        if seconds > 0 { try await Task.sleep(for: .seconds(seconds)) }
    }
}

/// The numbers sync runs by. The defaults are the spec's, or M0's where the
/// spec gives none.
public struct SyncConfiguration: Sendable, Hashable {
    /// The least time between the starts of two requests. M0 saw no limit at
    /// 11 requests 3 seconds apart, so that is the default.
    public var requestInterval: TimeInterval = 3
    /// Garmin's default and documented page size.
    public var pageSize: Int = ActivityQuery.defaultLimit
    /// Entries each page repeats from the one before.
    public var pageOverlap: Int = 10
    /// A quick sync lists start dates from this many days before today, plus
    /// anything newer.
    public var quickSyncDays: Int = 30
    /// The least time between the end of one pass over history and the start
    /// of the next deep scan.
    public var deepScanInterval: TimeInterval = 7 * 24 * 60 * 60
    /// After the first two listings of a range differ, it is listed again up to
    /// this many times.
    public var maximumRelistings: Int = 3
    /// The wait after a rate-limit response that states none. The spec is
    /// silent; this is a guess, to be replaced by what Garmin is seen to want.
    public var defaultRateLimitWait: TimeInterval = 15 * 60
    /// A listing is abandoned as broken after this many pages.
    public var maximumPagesPerListing: Int = 200

    public init() {}
}
