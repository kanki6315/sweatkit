import Foundation
import SweatKitModel

/// The state of a source record. Hidden and deleted are recorded here, but
/// what hiding, restoring and deleting do to the rest of the library is not
/// this package's work.
public enum SourceRecordState: String, Codable, Sendable, CaseIterable {
    case active
    case removedAtSource
    case hidden
    case deleted
}

/// One revision of a source record: an original kept byte for byte, named by
/// its content hash.
public struct SourceRevision: Hashable, Codable, Sendable {
    public var contentHash: ContentHash
    /// When this revision was stored.
    public var addedAt: Date
    /// The length of the original in bytes.
    public var byteCount: Int

    public init(contentHash: ContentHash, addedAt: Date, byteCount: Int) {
        self.contentHash = contentHash
        self.addedAt = addedAt
        self.byteCount = byteCount
    }
}

/// A stored source record. Its identity is unique in the store, so two
/// devices that import the same activity name the same record.
public struct SourceRecord: Hashable, Codable, Sendable {
    public var identity: SourceIdentity
    public var state: SourceRecordState
    /// When the record was first imported.
    public var importedAt: Date
    /// Every revision, oldest first.
    public var revisions: [SourceRevision]
    /// The revision the record reads now. Usually the newest, but an
    /// original that returns to an earlier revision's bytes makes that
    /// revision current again.
    public var currentRevision: ContentHash
    /// The activity this record belongs to, once one is saved.
    public var activityID: SourceIdentity?

    public init(
        identity: SourceIdentity,
        state: SourceRecordState,
        importedAt: Date,
        revisions: [SourceRevision],
        currentRevision: ContentHash,
        activityID: SourceIdentity?
    ) {
        self.identity = identity
        self.state = state
        self.importedAt = importedAt
        self.revisions = revisions
        self.currentRevision = currentRevision
        self.activityID = activityID
    }

    public var source: SourceKind { identity.source }
}

/// What importing an original did.
public enum ImportOutcome: Hashable, Sendable {
    /// A new source record, with these bytes as its first revision.
    case newRecord(SourceRecord)
    /// The record existed and these bytes are its new current revision.
    case newRevision(SourceRecord)
    /// The bytes are already this record's current revision. Nothing changed.
    case unchanged(SourceRecord)
    /// The bytes are already stored as a revision of another record, such as
    /// a file import identical to a Garmin original. Nothing changed.
    case recognised(SourceRecord)

    /// The record the import resolved to.
    public var record: SourceRecord {
        switch self {
        case .newRecord(let record), .newRevision(let record), .unchanged(let record), .recognised(let record):
            record
        }
    }

    /// Whether the import added anything.
    public var changedLibrary: Bool {
        switch self {
        case .newRecord, .newRevision: true
        case .unchanged, .recognised: false
        }
    }
}

/// One real-world activity, with the fields the feed lists and filters by.
///
/// Its ID is the lowest identity among its members, so the store works it
/// out rather than taking it. Every activity has one member for now; merges
/// will add more.
public struct ActivityRecord: Hashable, Codable, Sendable {
    /// The value in the feed card's headline, such as average power for a
    /// ride or average pace for a walk.
    public struct Headline: Hashable, Codable, Sendable {
        /// A name the store does not interpret, such as `averagePower`.
        public var kind: String
        public var value: Metric<Double>

        public init(kind: String, value: Metric<Double>) {
            self.kind = kind
            self.value = value
        }
    }

    public var members: [SourceIdentity]
    /// The member that supplies every stream.
    public var primary: SourceIdentity
    public var sport: Sport
    public var start: Date
    /// Seconds east of UTC at the start, when known.
    public var utcOffset: Int?
    /// Seconds.
    public var elapsedTime: TimeInterval
    /// Seconds, when known.
    public var timerTime: TimeInterval?
    /// Seconds, when known.
    public var movingTime: TimeInterval?
    /// Metres, when known.
    public var distance: Double?
    /// Metres, when known.
    public var ascent: Double?
    public var isIndoor: Bool
    public var isVirtual: Bool
    public var title: String
    public var headline: Headline?
    public var isHidden: Bool

    public init(
        members: [SourceIdentity],
        primary: SourceIdentity,
        sport: Sport,
        start: Date,
        utcOffset: Int? = nil,
        elapsedTime: TimeInterval,
        timerTime: TimeInterval? = nil,
        movingTime: TimeInterval? = nil,
        distance: Double? = nil,
        ascent: Double? = nil,
        isIndoor: Bool = false,
        isVirtual: Bool = false,
        title: String,
        headline: Headline? = nil,
        isHidden: Bool = false
    ) {
        self.members = members
        self.primary = primary
        self.sport = sport
        self.start = start
        self.utcOffset = utcOffset
        self.elapsedTime = elapsedTime
        self.timerTime = timerTime
        self.movingTime = movingTime
        self.distance = distance
        self.ascent = ascent
        self.isIndoor = isIndoor
        self.isVirtual = isVirtual
        self.title = title
        self.headline = headline
        self.isHidden = isHidden
    }

    /// The lowest identity among the members, or nil when there are none.
    public var id: SourceIdentity? { members.min() }
}

/// The feed's filters. A nil filter matches everything.
public struct FeedFilter: Hashable, Sendable {
    public enum Setting: Hashable, Sendable {
        case indoor
        case outdoor
    }

    /// Activities of any of these sports.
    public var sports: Set<Sport>?
    /// Activities whose start falls in this range, including its lower end and
    /// excluding its upper end.
    public var dates: Range<Date>?
    public var setting: Setting?
    /// Activities whose title contains this text, ignoring case and
    /// diacritics. Empty text matches everything.
    public var titleContains: String?

    public init(
        sports: Set<Sport>? = nil,
        dates: Range<Date>? = nil,
        setting: Setting? = nil,
        titleContains: String? = nil
    ) {
        self.sports = sports
        self.dates = dates
        self.setting = setting
        self.titleContains = titleContains
    }
}

/// Where a feed page ends: the last activity on it. The next page starts
/// after it, so inserting an activity above it does not repeat or skip rows.
public struct FeedCursor: Hashable, Sendable {
    public var start: Date
    public var id: SourceIdentity

    public init(start: Date, id: SourceIdentity) {
        self.start = start
        self.id = id
    }
}

/// One page of the feed, newest first.
public struct FeedPage: Hashable, Sendable {
    public var activities: [ActivityRecord]
    /// Where the next page starts, or nil when this is the last page.
    public var next: FeedCursor?

    public init(activities: [ActivityRecord], next: FeedCursor?) {
        self.activities = activities
        self.next = next
    }
}

/// What a derived result belongs to, as a name the store does not interpret
/// beyond equality.
public struct ResultOwner: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// An activity, by its ID.
    public static func activity(_ id: SourceIdentity) -> ResultOwner {
        ResultOwner(rawValue: "activity/\(id)")
    }

    public var description: String { rawValue }
}

/// Which profile values a result read, and for which date. The store needs
/// both to work out the profile fingerprint the result would have today.
public struct ProfileReading: Hashable, Codable, Sendable {
    /// The date thresholds were looked up for, usually the activity's start.
    public var date: Date
    public var inputs: AthleteProfile.Inputs

    public init(date: Date, inputs: AthleteProfile.Inputs = .all) {
        self.date = date
        self.inputs = inputs
    }
}

/// A result computed from stored data, kept as bytes the store does not
/// interpret. Owner and kind together are unique.
public struct DerivedResult: Hashable, Codable, Sendable {
    public var owner: ResultOwner
    /// A name the store does not interpret, such as `metrics` or `bestEfforts`.
    public var kind: String
    public var provenance: Provenance
    /// Present exactly when `provenance.profileFingerprint` is.
    public var profileReading: ProfileReading?
    public var payload: Data
    public var computedAt: Date

    public init(
        owner: ResultOwner,
        kind: String,
        provenance: Provenance,
        profileReading: ProfileReading? = nil,
        payload: Data,
        computedAt: Date
    ) {
        self.owner = owner
        self.kind = kind
        self.provenance = provenance
        self.profileReading = profileReading
        self.payload = payload
        self.computedAt = computedAt
    }
}

/// Why a derived result is stale.
public enum StaleReason: String, Hashable, Codable, Sendable, CaseIterable {
    /// Its algorithm version is not the current one.
    case algorithm
    /// Its input revision is not the current one, or its input is gone.
    case input
    /// A profile value it read has changed for its date.
    case profile
}

/// A stored result that no longer matches what the caller says is current.
public struct StaleResult: Hashable, Sendable {
    public var owner: ResultOwner
    public var kind: String
    public var reasons: Set<StaleReason>

    public init(owner: ResultOwner, kind: String, reasons: Set<StaleReason>) {
        self.owner = owner
        self.kind = kind
        self.reasons = reasons
    }
}

/// The result of reading a derived stream file. A missing, unreadable or
/// outdated file is a reason to rebuild, never a failure of the record.
public enum StreamRead<Value: Sendable>: Sendable {
    case available(Value)
    case needsRebuild(RebuildReason)

    public var value: Value? {
        if case .available(let value) = self { value } else { nil }
    }
}

extension StreamRead: Equatable where Value: Equatable {}

public enum RebuildReason: String, Hashable, Codable, Sendable {
    /// No stream file is stored.
    case missing
    /// The file is truncated, corrupt or not a stream file.
    case unreadable
    /// The file was written by a newer format than this build reads.
    case unsupportedFormat
    /// The file was built by an older decoder or older stream rules.
    case outdated
}

/// What a garbage collection removed and found.
public struct GarbageReport: Hashable, Sendable {
    /// Original files that no revision names: an interrupted import.
    public var removedOriginals: [ContentHash]
    /// Stream files and leftover temporary files that no revision names.
    public var removedStreamFiles: Int
    /// Revisions whose original file is gone. Not repaired here: an original
    /// is the source of truth, so the caller must fetch it again.
    public var revisionsMissingOriginal: [ContentHash]

    public init(removedOriginals: [ContentHash], removedStreamFiles: Int, revisionsMissingOriginal: [ContentHash]) {
        self.removedOriginals = removedOriginals
        self.removedStreamFiles = removedStreamFiles
        self.revisionsMissingOriginal = revisionsMissingOriginal
    }
}

public enum StoreError: Error, Hashable, Sendable {
    /// An imported file's identity must be the hash of its bytes.
    case fileIdentityMismatch(SourceIdentity)
    case unknownSourceRecord(SourceIdentity)
    case unknownRevision(ContentHash)
    /// An activity needs at least one member, and its primary among them.
    case invalidMembers
    /// A member already belongs to a different activity. Merges and splits
    /// are not built yet.
    case memberOfAnotherActivity(SourceIdentity)
    /// A stored original no longer matches its content hash.
    case originalCorrupted(ContentHash)
    /// A profile reading without a profile fingerprint, or the reverse.
    case inconsistentProvenance
    /// Stored metadata that the store cannot read back.
    case unreadableMetadata(String)
}
