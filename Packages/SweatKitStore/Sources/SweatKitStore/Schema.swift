import Foundation
import SwiftData

/// The first version of the metadata schema. Every model is internal: the
/// store converts to value types before anything leaves the actor.
///
/// Enumerations are stored as raw strings and identities in their canonical
/// form, so a later CloudKit sync engine can name records from the same keys.
/// Unique keys are deliberate: sync goes through CloudKit's sync engine, not
/// SwiftData's mirroring, which would forbid them.
enum StoreSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [SourceRecordEntity.self, RevisionEntity.self, ActivityEntity.self, DerivedResultEntity.self, ProfileEntity.self]
    }

    /// A source record, keyed by its identity.
    ///
    /// Later: tombstones attach here as a state plus a separate add-only
    /// tombstone model keyed by identity, so a deleted record's identity
    /// outlives its data. HealthKit snapshots are revisions like any other,
    /// with the snapshot's encoded bytes as the original.
    @Model final class SourceRecordEntity {
        @Attribute(.unique) var key: String
        var sourceRaw: String
        var externalID: String
        var stateRaw: String
        var importedAt: Date
        var currentRevisionHash: String
        @Relationship(deleteRule: .cascade, inverse: \RevisionEntity.record)
        var revisions: [RevisionEntity] = []
        var activity: ActivityEntity?

        init(key: String, sourceRaw: String, externalID: String, stateRaw: String, importedAt: Date, currentRevisionHash: String) {
            self.key = key
            self.sourceRaw = sourceRaw
            self.externalID = externalID
            self.stateRaw = stateRaw
            self.importedAt = importedAt
            self.currentRevisionHash = currentRevisionHash
        }
    }

    /// A revision, keyed within its record by the content hash of its
    /// original. The original itself is a file named by the same hash, shared
    /// when two records hold the same bytes.
    @Model final class RevisionEntity {
        #Index<RevisionEntity>([\.contentHash])

        /// The record's identity and the content hash, so it is unique.
        @Attribute(.unique) var key: String
        var contentHash: String
        /// The order of revisions within the record, from 0.
        var sequence: Int
        var addedAt: Date
        var byteCount: Int
        var record: SourceRecordEntity?

        init(key: String, contentHash: String, sequence: Int, addedAt: Date, byteCount: Int) {
            self.key = key
            self.contentHash = contentHash
            self.sequence = sequence
            self.addedAt = addedAt
            self.byteCount = byteCount
        }
    }

    /// An activity, keyed by the lowest identity among its members.
    ///
    /// Later: "same activity" and "keep separate" links, and decision
    /// records, are separate add-only models keyed by their record names; the
    /// pipeline resolves them and saves the resulting activities here. The
    /// title, hidden state and primary stored on this model are then the
    /// resolved values, a cache of the decisions.
    @Model final class ActivityEntity {
        #Index<ActivityEntity>([\.start], [\.isHidden, \.start])

        @Attribute(.unique) var id: String
        var primaryKey: String
        @Relationship(deleteRule: .nullify, inverse: \SourceRecordEntity.activity)
        var members: [SourceRecordEntity] = []
        var sportRaw: String
        var start: Date
        var utcOffset: Int?
        var elapsedTime: Double
        var timerTime: Double?
        var movingTime: Double?
        var distance: Double?
        var ascent: Double?
        var isIndoor: Bool
        var isVirtual: Bool
        var title: String
        var headlineKind: String?
        var headlineValue: Double?
        var headlineUnavailableReason: String?
        var isHidden: Bool

        init(id: String, primaryKey: String, sportRaw: String, start: Date, elapsedTime: Double, isIndoor: Bool, isVirtual: Bool, title: String, isHidden: Bool) {
            self.id = id
            self.primaryKey = primaryKey
            self.sportRaw = sportRaw
            self.start = start
            self.elapsedTime = elapsedTime
            self.isIndoor = isIndoor
            self.isVirtual = isVirtual
            self.title = title
            self.isHidden = isHidden
        }
    }

    /// A derived result, keyed by owner and kind.
    @Model final class DerivedResultEntity {
        #Index<DerivedResultEntity>([\.kind], [\.owner])

        @Attribute(.unique) var key: String
        var owner: String
        var kind: String
        var inputRevision: String
        var profileFingerprint: String?
        var algorithmVersion: Int
        var profileReadingDate: Date?
        var profileReadingInputs: Int?
        @Attribute(.externalStorage) var payload: Data
        var computedAt: Date

        init(key: String, owner: String, kind: String, inputRevision: String, algorithmVersion: Int, payload: Data, computedAt: Date) {
            self.key = key
            self.owner = owner
            self.kind = kind
            self.inputRevision = inputRevision
            self.algorithmVersion = algorithmVersion
            self.payload = payload
            self.computedAt = computedAt
        }
    }

    /// The athlete profile, as one encoded row.
    @Model final class ProfileEntity {
        @Attribute(.unique) var key: String
        var encoded: Data

        init(key: String, encoded: Data) {
            self.key = key
            self.encoded = encoded
        }
    }
}

typealias SourceRecordEntity = StoreSchemaV2.SourceRecordEntity
typealias RevisionEntity = StoreSchemaV2.RevisionEntity
typealias ActivityEntity = StoreSchemaV2.ActivityEntity
typealias DerivedResultEntity = StoreSchemaV2.DerivedResultEntity
typealias ProfileEntity = StoreSchemaV2.ProfileEntity

/// The optional display-only field migrates without rewriting existing values.
enum StoreMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [StoreSchemaV1.self, StoreSchemaV2.self] }
    static var stages: [MigrationStage] { [.lightweight(fromVersion: StoreSchemaV1.self, toVersion: StoreSchemaV2.self)] }
}
