import Foundation
import SwiftData
import SweatKitModel

/// The backup-eligible recovery input for Garmin/imported data. Activity rows,
/// metrics and Health records are deliberately absent: they can contain Health
/// summaries after a primary-source switch. Originals and user decisions live
/// separately and remain eligible for backup.
struct MetadataBackup: Codable, Equatable {
    struct Revision: Codable, Equatable {
        var key: String
        var hash: String
        var sequence: Int
        var date: Date
        var byteCount: Int
    }
    struct Source: Codable, Equatable {
        var key: String
        var source: String
        var externalID: String
        var state: String
        var importedAt: Date
        var current: String
        var revisions: [Revision]
    }
    var version = 1
    var generation: UUID
    var sources: [Source]
    var profile: Data?

    static func snapshot(_ context: ModelContext) throws -> Self {
        let deleted = Set(context.deletedModelsArray.map(\.persistentModelID))
        let records = try context.fetch(FetchDescriptor<SourceRecordEntity>(predicate: #Predicate { $0.sourceRaw != "healthKit" }))
            .filter { !deleted.contains($0.persistentModelID) }
        let sources = records.map { record in
            Source(key: record.key, source: record.sourceRaw, externalID: record.externalID,
                state: record.stateRaw, importedAt: record.importedAt, current: record.currentRevisionHash,
                revisions: record.revisions.filter { !deleted.contains($0.persistentModelID) }.map {
                    Revision(key: $0.key, hash: $0.contentHash, sequence: $0.sequence, date: $0.addedAt, byteCount: $0.byteCount)
                }.sorted { $0.sequence < $1.sequence })
        }.sorted { $0.key < $1.key }
        let profile = try context.fetch(FetchDescriptor<ProfileEntity>()).first { !deleted.contains($0.persistentModelID) }?.encoded
        return Self(generation: UUID(), sources: sources, profile: profile)
    }

    static func read(_ files: LibraryFiles) throws -> Self? {
        guard FileManager.default.fileExists(atPath: files.backupURL.path) else { return nil }
        let value = try JSONDecoder().decode(Self.self, from: Data(contentsOf: files.backupURL))
        guard value.version == 1, Set(value.sources.map(\.key)).count == value.sources.count,
              value.sources.allSatisfy({ source in
                  (source.source == SourceKind.garmin.rawValue || source.source == SourceKind.file.rawValue)
                      && source.key == "\(source.source):\(source.externalID)"
                      && SourceRecordState(rawValue: source.state) != nil
                      && source.revisions.contains { $0.hash == source.current }
                      && Set(source.revisions.map(\.hash)).count == source.revisions.count
                      && source.revisions.allSatisfy { $0.hash.count == 64 && $0.byteCount >= 0 && $0.key == "\(source.key)#\($0.hash)" }
              }) else {
            throw StoreError.unreadableMetadata("backup manifest")
        }
        if let profile = value.profile {
            _ = try PropertyListDecoder().decode(AthleteProfile.self, from: profile)
        }
        return value
    }

    /// Durable recovery input is committed before the excluded database. If
    /// the database save fails, replaying the manifest on reopen is safe: an
    /// original is always stored before its metadata and deletion intent is
    /// already durable in the identity journal.
    static func save(_ context: ModelContext, files: LibraryFiles) throws {
        var next = try snapshot(context)
        if let previous = try read(files), previous.sources == next.sources, previous.profile == next.profile {
            next.generation = previous.generation
        } else {
            try JSONEncoder().encode(next).write(to: files.backupURL, options: .atomic)
        }
        try context.save()
        try Data(next.generation.uuidString.utf8).write(to: files.backupGenerationURL, options: .atomic)
    }

    static func prepare(_ context: ModelContext, files: LibraryFiles) throws {
        if let backup = try read(files) {
            let committed = try? String(contentsOf: files.backupGenerationURL, encoding: .utf8)
            if committed != backup.generation.uuidString {
                try backup.replay(in: context)
                try context.save()
                try Data(backup.generation.uuidString.utf8).write(to: files.backupGenerationURL, options: .atomic)
            }
        } else {
            try save(context, files: files)
        }
        let records = try context.fetch(FetchDescriptor<SourceRecordEntity>())
        let nonHealth = Set(records.filter { $0.sourceRaw != "healthKit" }.flatMap { $0.revisions.map(\.contentHash) })
        let health = Set(records.filter { $0.sourceRaw == "healthKit" }.flatMap { $0.revisions.map(\.contentHash) })
        for hash in health.subtracting(nonHealth) {
            let old = files.originalsDirectory.appendingPathComponent(hash)
            let local = files.healthOriginalsDirectory.appendingPathComponent(hash)
            if FileManager.default.fileExists(atPath: old.path) {
                // Atomic copy into an excluded parent precedes removing the
                // old individual backup-excluded snapshot.
                try Data(contentsOf: old).write(to: local, options: .atomic)
                try FileManager.default.removeItem(at: old)
            }
        }
        // Only after the non-Health recovery input is durable can the legacy
        // mixed database be removed. Migration copies, never moves, its files.
        try files.removeLegacyMetadata()
    }

    private func replay(in context: ModelContext) throws {
        let existing = try context.fetch(FetchDescriptor<SourceRecordEntity>())
        let expected = Dictionary(uniqueKeysWithValues: sources.map { ($0.key, $0) })
        var affected: Set<String> = []
        for record in existing where record.sourceRaw != "healthKit" {
            if let id = record.activity?.id { affected.insert(id) }
            context.delete(record)
        }
        for row in try context.fetch(FetchDescriptor<ActivityEntity>()) where affected.contains(row.id) {
            row.members = []
            context.delete(row)
        }
        for result in try context.fetch(FetchDescriptor<DerivedResultEntity>())
            where affected.contains(where: { result.owner == "activity/\($0)" }) {
            context.delete(result)
        }
        // Commit removal before reinserting unique identities. A crash is
        // recoverable because the generation marker still differs.
        try context.save()
        for source in expected.values {
            let record = SourceRecordEntity(key: source.key, sourceRaw: source.source,
                externalID: source.externalID, stateRaw: source.state, importedAt: source.importedAt,
                currentRevisionHash: source.current)
            context.insert(record)
            for revision in source.revisions {
                let entity = RevisionEntity(key: revision.key, contentHash: revision.hash,
                    sequence: revision.sequence, addedAt: revision.date, byteCount: revision.byteCount)
                context.insert(entity)
                entity.record = record
            }
        }
        let profiles = try context.fetch(FetchDescriptor<ProfileEntity>())
        if let profile {
            if let existing = profiles.first { existing.encoded = profile }
            else { context.insert(ProfileEntity(key: "athlete", encoded: profile)) }
            for extra in profiles.dropFirst() { context.delete(extra) }
        } else {
            for entity in profiles { context.delete(entity) }
        }
    }
}
