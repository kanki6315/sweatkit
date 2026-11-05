import Foundation
import SweatKitGarmin
import SweatKitModel

/// What one sync run asks for.
public enum SyncRun: Sendable, Hashable {
    /// Start dates in the last 30 days plus anything newer, and outstanding
    /// retries. For background refresh.
    case quick
    /// A quick sync, then the pass over history when one is owed: the first-sync
    /// backfill until it finishes, an interrupted pass, or a deep scan once a
    /// week has passed since the last pass finished. For launch and
    /// pull-to-refresh, in the foreground.
    case routine
    /// A new pass over all history, now, with a fresh download of the chosen files.
    case fullReconciliation(Redownload)
}

/// What a sync run did, for the status a screen shows.
public struct SyncReport: Sendable, Equatable {
    public enum Outcome: Sendable, Equatable {
        /// Everything this run set out to list was listed.
        case completed
        /// Garmin answered 429. Nothing is sent before `until`; the next run
        /// after it resumes from the checkpoints.
        case rateLimited(until: Date)
        /// Garmin refused the Personal API key: wrong, expired or deleted. The
        /// user needs to enter a new key. Not retried.
        case keyRefused
        /// Garmin refused a token it had just issued, and renewing did not help.
        case tokenRefused
        /// A listing failed, so this run stopped and inferred nothing from it.
        case listingFailed(GarminError)
        /// The task was cancelled. Checkpoints keep what finished.
        case interrupted
        /// The library could not be read or the checkpoints could not be saved.
        case libraryFailed
        /// Another run on this engine had not finished.
        case alreadyRunning
    }

    public var outcome: Outcome
    /// New records.
    public var added: [SourceIdentity] = []
    /// New revisions of known records: a downloaded original with a new hash.
    public var revised: [SourceIdentity] = []
    /// Summaries replaced with no new file.
    public var summariesUpdated: [SourceIdentity] = []
    /// Downloads whose original matched the hash already held.
    public var unchangedDownloads: [SourceIdentity] = []
    public var removedAtSource: [SourceIdentity] = []
    /// Identities marked removed earlier that Garmin lists again.
    public var presentAgain: [SourceIdentity] = []
    /// Activities that failed in this run.
    public var failures: [SourceIdentity: SyncFailure] = [:]
    /// Activities waiting for a retry after this run.
    public var outstanding: Int = 0
    /// Months left unsettled by this run.
    public var unsettledMonths: [CalendarMonth] = []
    /// The pass over history after this run.
    public var pass: PassStatus = .none
    /// Requests sent to Garmin.
    public var requests: Int = 0

    public enum PassStatus: Sendable, Equatable {
        /// No pass is in progress and this run finished none.
        case none
        case inProgress(HistoryPass.Kind, completedMonths: Int)
        case finished(HistoryPass.Kind)
    }

    public init(outcome: Outcome) {
        self.outcome = outcome
    }
}
