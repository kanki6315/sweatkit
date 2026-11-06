import Foundation
import SwiftData
import SweatKitModel
@testable import SweatKitStore
import Testing

@Suite struct SportNameMigrationTests {
    @MainActor private func writeV1(root: URL, id: SourceIdentity, bytes: Data) throws {
        let files = LibraryFiles(root: root)
        try files.createDirectories()
        let hash = ContentHash(of: bytes)
        try bytes.write(to: files.originalURL(hash))
        let schema = Schema(versionedSchema: StoreSchemaV1.self)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: files.databaseURL, cloudKitDatabase: .none)])
        let context = ModelContext(container)
        let source = StoreSchemaV1.SourceRecordEntity(key: id.description, sourceRaw: id.source.rawValue,
            externalID: id.externalID, stateRaw: SourceRecordState.active.rawValue, importedAt: referenceDate,
            currentRevisionHash: hash.hex)
        let revision = StoreSchemaV1.RevisionEntity(key: "\(id.description)#\(hash.hex)", contentHash: hash.hex,
            sequence: 0, addedAt: referenceDate, byteCount: bytes.count)
        let activity = StoreSchemaV1.ActivityEntity(id: id.description, primaryKey: id.description,
            sportRaw: Sport.other.rawValue, start: referenceDate, elapsedTime: 3600,
            isIndoor: false, isVirtual: false, title: "My existing title", isHidden: true)
        context.insert(source); context.insert(revision); context.insert(activity)
        source.revisions = [revision]; source.activity = activity; activity.members = [source]
        try context.save()
    }

    @Test func v1MigratesWithoutLosingIdentityOriginalOrUserState() async throws {
        let temporary = TemporaryLibrary()
        let identity = garmin(909)
        let bytes = Data("untouched original".utf8)
        try await writeV1(root: temporary.root, id: identity, bytes: bytes)
        let store = try temporary.open()
        var row = try #require(try await store.activity(identity))
        #expect(row.title == "My existing title")
        #expect(row.members == [identity])
        #expect(row.isHidden)
        #expect(row.sourceSportName == nil)
        #expect(try await store.original(ContentHash(of: bytes)) == bytes)
        row.sourceSportName = "Golf"
        try await store.saveActivity(row)
        let reopened = try temporary.open()
        #expect(try await reopened.activity(identity)?.sourceSportName == "Golf")
        #expect(try await reopened.activity(identity)?.title == row.title)
        #expect(try await reopened.sourceRecords().count == 1)
    }

    @Test func legacyActivityJSONWithoutSportNameDecodes() throws {
        let old = ActivityRecord(members: [garmin(1)], primary: garmin(1), sport: .other,
            start: referenceDate, elapsedTime: 60, title: "Activity")
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        json.removeValue(forKey: "sourceSportName")
        let decoded = try JSONDecoder().decode(ActivityRecord.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.sourceSportName == nil)
        #expect(decoded == old)
    }
}
