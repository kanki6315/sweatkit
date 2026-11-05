import Foundation
import SweatKitModel
import SweatKitStore

// MARK: Import

/// What importing one file did.
public struct ImportResult: Hashable, Sendable {
    public enum Change: String, Hashable, Sendable, CaseIterable {
        /// A new activity is in the library.
        case added
        /// The activity was already there and has been rebuilt: its source
        /// has a new revision, or an earlier import of it was interrupted.
        case updated
        /// These bytes were already imported. Nothing was stored and nothing
        /// was computed.
        case alreadyInLibrary
    }

    public var change: Change
    /// The source record the bytes belong to. For a file whose bytes are
    /// already stored under another source, such as a Garmin original, it is
    /// that source's record.
    public var source: SourceIdentity
    /// The activity as the feed lists it.
    public var activity: ActivityRecord

    public init(change: Change, source: SourceIdentity, activity: ActivityRecord) {
        self.change = change
        self.source = source
        self.activity = activity
    }
}

/// One file of a batch import.
public struct ImportFile: Hashable, Sendable {
    /// Where the file's bytes are.
    public enum Contents: Hashable, Sendable {
        case bytes(Data)
        /// A file on disk, read when its turn comes so that a large batch is
        /// never all in memory. A URL from the Files picker must already be
        /// accessible: starting and stopping security-scoped access is the
        /// caller's work.
        case url(URL)
    }

    /// The name shown beside the file's outcome, such as its file name.
    public var name: String
    public var contents: Contents
    /// The identity to import under. Nil for a plain file, whose identity is
    /// the hash of its bytes.
    public var identity: SourceIdentity?
    /// Seconds east of UTC to use when the file does not state its own
    /// offset. See `ActivityLibrary.importFile`.
    public var fallbackUTCOffset: Int?

    public init(name: String, contents: Contents, identity: SourceIdentity? = nil, fallbackUTCOffset: Int? = nil) {
        self.name = name
        self.contents = contents
        self.identity = identity
        self.fallbackUTCOffset = fallbackUTCOffset
    }

    /// A file on disk, named by its last path component.
    public init(url: URL) {
        self.init(name: url.lastPathComponent, contents: .url(url))
    }
}

/// How one file of a batch import ended.
public struct ImportFileOutcome: Hashable, Sendable {
    /// The file's position in the batch.
    public var index: Int
    public var name: String
    public var result: Result<ImportResult, LibraryError>

    public init(index: Int, name: String, result: Result<ImportResult, LibraryError>) {
        self.index = index
        self.name = name
        self.result = result
    }

    /// The reason the file was not imported, or nil when it was.
    public var failure: LibraryError? {
        if case .failure(let error) = result { error } else { nil }
    }
}

/// Where a batch import has got to. One is reported as each file finishes.
public struct ImportProgress: Hashable, Sendable {
    /// Files finished so far, including this one.
    public var completed: Int
    public var total: Int
    /// The file that just finished. Files finish out of order.
    public var latest: ImportFileOutcome

    public init(completed: Int, total: Int, latest: ImportFileOutcome) {
        self.completed = completed
        self.total = total
        self.latest = latest
    }
}

// MARK: Recompute

/// An activity whose stored metrics no longer match what they would be
/// computed from now.
public struct StaleActivity: Hashable, Sendable {
    public enum Reason: String, Hashable, Sendable, CaseIterable {
        /// A profile value the metrics read has changed for the activity's date.
        case profile
        /// An analysis algorithm, or a feed-row rule, has a new version.
        case algorithm
        /// The original has a new revision, or the decoder or the stream
        /// rules have a new version.
        case input
        /// The activity has no stored metrics, or its source record has no
        /// activity yet: an import was interrupted before it finished.
        case notComputed
        /// A stream file is missing, unreadable or outdated. Found only when
        /// stream files are checked.
        case streamFile
    }

    /// The activity's ID. For a source record with no activity yet, the
    /// record's identity, which is the ID its activity will have.
    public var id: SourceIdentity
    public var reasons: Set<Reason>

    public init(id: SourceIdentity, reasons: Set<Reason>) {
        self.id = id
        self.reasons = reasons
    }
}

/// What a rebuild started from: the cheapest stored form that was still good.
public enum RebuildSource: String, Hashable, Sendable, CaseIterable {
    /// The stored analysis stream. Only the metrics were computed again.
    case analysisStream
    /// The stored decoded activity. The analysis stream was built again.
    case recordedActivity
    /// The preserved original. It was decoded again.
    case original
}

/// What a recompute did.
public struct RecomputeReport: Hashable, Sendable {
    /// One activity that was rebuilt.
    public struct Rebuilt: Hashable, Sendable {
        public var id: SourceIdentity
        public var reasons: Set<StaleActivity.Reason>
        public var source: RebuildSource
        /// Whether the feed row's values changed and the row was saved again.
        public var feedRowChanged: Bool

        public init(id: SourceIdentity, reasons: Set<StaleActivity.Reason>, source: RebuildSource, feedRowChanged: Bool) {
            self.id = id
            self.reasons = reasons
            self.source = source
            self.feedRowChanged = feedRowChanged
        }
    }

    /// One activity that could not be rebuilt. Its stored results are left
    /// as they were, still stale, so the next recompute tries again.
    public struct Failure: Hashable, Sendable {
        public var id: SourceIdentity
        public var error: LibraryError

        public init(id: SourceIdentity, error: LibraryError) {
            self.id = id
            self.error = error
        }
    }

    /// Ordered by activity ID.
    public var rebuilt: [Rebuilt]
    /// Ordered by activity ID.
    public var failures: [Failure]

    public init(rebuilt: [Rebuilt] = [], failures: [Failure] = []) {
        self.rebuilt = rebuilt
        self.failures = failures
    }
}

/// Where a recompute has got to. One is reported as each activity finishes.
public struct RecomputeProgress: Hashable, Sendable {
    public var completed: Int
    public var total: Int

    public init(completed: Int, total: Int) {
        self.completed = completed
        self.total = total
    }
}
