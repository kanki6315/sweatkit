import CryptoKit
import Foundation
import SweatKitModel
import SweatKitStore
import SweatKitTestSupport
import Testing

@Suite struct OriginalTests {
    @Test(arguments: Fixtures.FIT.allCases)
    func fixtureRoundTripsByteForByte(_ fixture: Fixtures.FIT) async throws {
        let library = TemporaryLibrary()
        let store = try library.open()
        let bytes = try fixture.data()
        // Worked out from the bytes directly, not through the model.
        let expectedHex = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()

        let outcome = try await store.importFile(bytes, at: referenceDate)

        guard case .newRecord(let record) = outcome else {
            Issue.record("Expected a new record, got \(outcome)")
            return
        }
        #expect(record.identity == SourceIdentity(source: .file, externalID: expectedHex))
        #expect(record.currentRevision.hex == expectedHex)
        #expect(record.revisions.map(\.byteCount) == [bytes.count])
        #expect(record.state == .active)
        #expect(try await store.original(ContentHash(hex: expectedHex)) == bytes)
        let onDisk = try Data(contentsOf: library.originalsDirectory.appending(path: expectedHex))
        #expect(onDisk == bytes)
    }

    @Test func importingTheSameBytesAgainAddsNothing() async throws {
        let library = TemporaryLibrary()
        let store = try library.open()
        let bytes = try Fixtures.FIT.walk.data()

        let first = try await store.importFile(bytes, at: day(0))
        let second = try await store.importFile(bytes, at: day(1))

        #expect(first.changedLibrary)
        #expect(second == .unchanged(first.record))
        #expect(try await store.sourceRecords().count == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: library.originalsDirectory.path).count == 1)
        // The import date is the first import's.
        #expect(try await store.sourceRecord(first.record.identity)?.importedAt == day(0))
    }

    @Test func repeatingAGarminImportChangesNothing() async throws {
        let library = TemporaryLibrary()
        let store = try library.open()
        let bytes = try Fixtures.FIT.outdoorRide.data()
        let identity = garmin(24_172_582_403)

        let first = try await store.importOriginal(bytes, as: identity, at: day(0))
        let second = try await store.importOriginal(bytes, as: identity, at: day(1))

        #expect(second == .unchanged(first.record))
        #expect(second.record.revisions.count == 1)
    }

    @Test func aChangedGarminOriginalIsANewRevisionOfTheSameRecord() async throws {
        let library = TemporaryLibrary()
        let store = try library.open()
        let identity = garmin(24_172_582_403)
        let original = try Fixtures.FIT.outdoorRide.data()
        var edited = original
        edited[edited.count - 1] ^= 0xFF

        _ = try await store.importOriginal(original, as: identity, at: day(0))
        let outcome = try await store.importOriginal(edited, as: identity, at: day(1))

        guard case .newRevision(let record) = outcome else {
            Issue.record("Expected a new revision, got \(outcome)")
            return
        }
        #expect(record.identity == identity)
        #expect(record.revisions.map(\.contentHash) == [ContentHash(of: original), ContentHash(of: edited)])
        #expect(record.revisions.map(\.addedAt) == [day(0), day(1)])
        #expect(record.currentRevision == ContentHash(of: edited))
        #expect(record.importedAt == day(0))
        #expect(try await store.sourceRecords().count == 1)
        // Both originals are kept.
        #expect(try await store.original(ContentHash(of: original)) == original)
        #expect(try await store.original(ContentHash(of: edited)) == edited)
    }

    @Test func returningToEarlierBytesMakesThatRevisionCurrentAgain() async throws {
        let library = TemporaryLibrary()
        let store = try library.open()
        let identity = garmin(1)
        let a = Data("revision a".utf8)
        let b = Data("revision b".utf8)

        _ = try await store.importOriginal(a, as: identity, at: day(0))
        _ = try await store.importOriginal(b, as: identity, at: day(1))
        let outcome = try await store.importOriginal(a, as: identity, at: day(2))

        guard case .newRevision(let record) = outcome else {
            Issue.record("Expected a new revision, got \(outcome)")
            return
        }
        #expect(record.revisions.map(\.contentHash) == [ContentHash(of: a), ContentHash(of: b)])
        #expect(record.currentRevision == ContentHash(of: a))
    }

    @Test func aChangedImportedFileIsADifferentRecord() async throws {
        let library = TemporaryLibrary()
        let store = try library.open()
        let original = try Fixtures.FIT.zwiftRide.data()
        var edited = original
        edited[edited.count - 1] ^= 0xFF

        let first = try await store.importFile(original, at: day(0))
        let second = try await store.importFile(edited, at: day(1))

        guard case .newRecord(let editedRecord) = second else {
            Issue.record("Expected a new record, got \(second)")
            return
        }
        #expect(editedRecord.identity != first.record.identity)
        #expect(editedRecord.identity == SourceIdentity(fileContents: edited))
        #expect(editedRecord.revisions.count == 1)
        #expect(try await store.sourceRecords().count == 2)
    }

    @Test func aFileIdenticalToAGarminOriginalIsRecognisedAsThatRecord() async throws {
        let library = TemporaryLibrary()
        let store = try library.open()
        let bytes = try Fixtures.FIT.zwiftRide.data()
        let identity = garmin(24_906_063_494)

        let garminImport = try await store.importOriginal(bytes, as: identity, at: day(0))
        let fileImport = try await store.importFile(bytes, at: day(1))

        #expect(fileImport == .recognised(garminImport.record))
        #expect(!fileImport.changedLibrary)
        #expect(try await store.sourceRecords().map(\.identity) == [identity])
    }

    @Test func aFileMustUseTheHashOfItsBytesAsItsIdentity() async throws {
        let library = TemporaryLibrary()
        let store = try library.open()
        let wrong = SourceIdentity(source: .file, externalID: "not-the-hash")

        await #expect(throws: StoreError.fileIdentityMismatch(wrong)) {
            try await store.importOriginal(Data("bytes".utf8), as: wrong, at: referenceDate)
        }
        #expect(try await store.sourceRecords().isEmpty)
    }

    @Test func aCorruptedOriginalIsReportedNotReturned() async throws {
        let library = TemporaryLibrary()
        let store = try library.open()
        let bytes = Data("original bytes".utf8)
        let record = try await store.importFile(bytes, at: referenceDate).record
        try Data("tampered".utf8).write(to: library.originalsDirectory.appending(path: record.currentRevision.hex))

        await #expect(throws: StoreError.originalCorrupted(record.currentRevision)) {
            try await store.original(record.currentRevision)
        }
    }

    @Test func stateIsStored() async throws {
        let library = TemporaryLibrary()
        let store = try library.open()
        try await storeGarminRecord(1, in: store)

        for state in SourceRecordState.allCases {
            try await store.setState(state, for: garmin(1))
            #expect(try await store.sourceRecord(garmin(1))?.state == state)
        }
        await #expect(throws: StoreError.unknownSourceRecord(garmin(2))) {
            try await store.setState(.hidden, for: garmin(2))
        }
    }
}

@Suite struct GarbageTests {
    @Test func filesWithNoMetadataAreCollected() async throws {
        let library = TemporaryLibrary()
        let store = try library.open()
        let revision = try await storeGarminRecord(1, in: store)
        try await store.saveAnalysisStream(AnalysisStream(rulesVersion: 1, start: referenceDate, count: 3), for: revision)

        // What an interrupted import or stream write leaves behind.
        let orphan = ContentHash(of: Data("never recorded".utf8))
        try Data("never recorded".utf8).write(to: library.originalsDirectory.appending(path: orphan.hex))
        try Data("stream".utf8).write(to: library.analysisFile(orphan))
        try Data("partial".utf8).write(to: library.streamsDirectory.appending(path: ".tmp-write"))

        let report = try await store.collectGarbage()

        #expect(report.removedOriginals == [orphan])
        #expect(report.removedStreamFiles == 2)
        #expect(report.revisionsMissingOriginal.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: library.originalsDirectory.path) == [revision.hex])
        #expect(await store.analysisStream(for: revision, rulesVersion: 1).value != nil)
        #expect(try await store.sourceRecords().count == 1)
    }

    @Test func aMissingOriginalIsReportedAndTheRecordKept() async throws {
        let library = TemporaryLibrary()
        let store = try library.open()
        let revision = try await storeGarminRecord(1, in: store)
        try FileManager.default.removeItem(at: library.originalsDirectory.appending(path: revision.hex))

        let report = try await store.collectGarbage()

        #expect(report.revisionsMissingOriginal == [revision])
        #expect(try await store.sourceRecord(garmin(1)) != nil)
        #expect(try await store.original(revision) == nil)
    }
}
