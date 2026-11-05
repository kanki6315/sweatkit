import Foundation
import SweatKitGarmin
import SweatKitModel

/// Sync's checkpoints, stored by the library between runs.
public struct GarminSyncState: Sendable, Hashable, Codable {
    /// When the first pass over history finished, or nil while the backfill is
    /// unfinished.
    public var backfillFinished: Date?
    /// When the last pass over history finished: backfill, deep scan or full
    /// reconciliation. The next deep scan is due a week later.
    public var lastPassFinished: Date?
    /// The pass over history in progress, if one was interrupted.
    public var pass: HistoryPass?
    /// Months the last finished pass left unsettled, for the next deep scan.
    public var unsettledMonths: Set<CalendarMonth>
    /// Activities whose last attempt failed, retried on the next sync.
    public var pending: [Int64: PendingActivity]
    /// No request is sent before this, because Garmin said to wait.
    public var rateLimitedUntil: Date?
    public var lastQuickSync: Date?

    public init(
        backfillFinished: Date? = nil,
        lastPassFinished: Date? = nil,
        pass: HistoryPass? = nil,
        unsettledMonths: Set<CalendarMonth> = [],
        pending: [Int64: PendingActivity] = [:],
        rateLimitedUntil: Date? = nil,
        lastQuickSync: Date? = nil
    ) {
        self.backfillFinished = backfillFinished
        self.lastPassFinished = lastPassFinished
        self.pass = pass
        self.unsettledMonths = unsettledMonths
        self.pending = pending
        self.rateLimitedUntil = rateLimitedUntil
        self.lastQuickSync = lastQuickSync
    }
}

/// One walk over history, month by month, newest first.
public struct HistoryPass: Sendable, Hashable, Codable {
    public enum Kind: String, Sendable, Hashable, Codable {
        case backfill
        case deepScan
        case fullReconciliation
    }

    public var kind: Kind
    /// Which known files to download again. Only a full reconciliation sets it.
    public var redownload: Redownload
    public var started: Date
    /// Months whose listing settled and whose activities were reconciled.
    public var completed: Set<CalendarMonth>
    /// Months that did not settle in this pass and were left for the next one.
    public var unsettled: Set<CalendarMonth>

    public init(kind: Kind, redownload: Redownload = .none, started: Date, completed: Set<CalendarMonth> = [], unsettled: Set<CalendarMonth> = []) {
        self.kind = kind
        self.redownload = redownload
        self.started = started
        self.completed = completed
        self.unsettled = unsettled
    }
}

/// Which files a full reconciliation downloads again.
public enum Redownload: Sendable, Hashable, Codable {
    case none
    case all
    case only(Set<SourceIdentity>)

    func includes(_ identity: SourceIdentity) -> Bool {
        switch self {
        case .none: false
        case .all: true
        case .only(let chosen): chosen.contains(identity)
        }
    }
}

/// An activity whose last attempt failed.
public struct PendingActivity: Sendable, Hashable, Codable {
    /// The listing entry it was found with.
    public var summary: GarminSummary
    /// The file is to be downloaded again even if the hash may match, because
    /// the user asked.
    public var forceDownload: Bool
    public var attempts: Int
    public var lastFailure: SyncFailure

    public init(summary: GarminSummary, forceDownload: Bool, attempts: Int, lastFailure: SyncFailure) {
        self.summary = summary
        self.forceDownload = forceDownload
        self.attempts = attempts
        self.lastFailure = lastFailure
    }
}

/// Why one activity failed. A screen can explain each.
public enum SyncFailure: Sendable, Hashable, Codable {
    /// The request did not complete.
    case network
    /// Garmin answered with something other than the activity. `status` is the
    /// HTTP status, or 0 when the request could not be built.
    case server(status: Int)
    /// The download is not a readable zip holding one original.
    case unreadableDownload
    /// The library refused the action.
    case libraryRejected
}
