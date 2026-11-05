import Foundation
import Synchronization
import SweatKitAnalysis
import SweatKitIngest
import SweatKitLibrary
import SweatKitModel
import SweatKitStore
import SweatKitTestSupport
import Testing

/// The four real fixtures through the whole pipeline. Expected values come
/// from `Fixtures/README.md` and from the spec's rules, never from this
/// package's output.
@Suite struct FixtureImportTests {
    let temporary = TemporaryLibrary()

    /// Elapsed time is the length of a whole-second grid, so it is the
    /// README's figure rounded up: within 1 s, plus half the README's last
    /// printed digit.
    private static let elapsedSlack = 1.05
    /// Timer time is elapsed time minus the paused spans, and every pause
    /// starts and ends on a whole grid second, so the slack grows with the
    /// pauses. Ingest's fixture tests allow 2 s for the same sum.
    private static let timerSlack = 2.0
    /// Half of the README's last printed digit, 0.01 km, plus one metre.
    private static let distanceSlack = 6.0

    @Test(arguments: FixtureFacts.all)
    func fixtureIsReportedAsAdded(_ facts: FixtureFacts) async throws {
        let imported = try await FixtureLibrary.imported()
        let outcome = try #require(imported.outcomes[facts.fixture])
        let result = try outcome.result.get()
        #expect(outcome.name == "\(facts.fixture.rawValue).fit")
        #expect(result.change == .added)
        #expect(result.source == (try fileIdentity(facts.fixture)))
        #expect(result.activity.id == (try fileIdentity(facts.fixture)))
    }

    @Test(arguments: FixtureFacts.all)
    func fixtureBecomesAFeedRowWithTheReadmesFigures(_ facts: FixtureFacts) async throws {
        let library = try await temporary.withFixtures().open()
        let id = try fileIdentity(facts.fixture)
        let row = try #require(try await library.activity(id))

        #expect(row.members == [id])
        #expect(row.primary == id)
        #expect(row.sport == facts.sport)
        #expect(row.isIndoor == facts.isIndoor)
        #expect(row.isVirtual == facts.isVirtual)
        #expect(row.start == Date(timeIntervalSince1970: facts.start))
        #expect(row.utcOffset == facts.utcOffset)
        #expect(!row.isHidden)

        #expect(abs(row.elapsedTime - facts.elapsed) <= Self.elapsedSlack)
        // A whole number of seconds: a duration is a count of samples.
        #expect(row.elapsedTime == row.elapsedTime.rounded())
        let timer = try #require(row.timerTime)
        #expect(abs(timer - facts.timer) <= Self.timerSlack)
        let distance = try #require(row.distance)
        #expect(abs(distance - facts.distanceKilometres * 1000) <= Self.distanceSlack)

        // Moving time is timer time minus the seconds below the speed floor,
        // so it is known, and no longer than timer time.
        let moving = try #require(row.movingTime)
        #expect(moving > 0 && moving <= timer)
        // Every fixture has altitude on every record, and climbs.
        #expect(try #require(row.ascent) > 0)

        #expect(row.title == facts.title)
        #expect(row.headline?.kind == facts.headlineKind)
    }

    @Test(arguments: FixtureFacts.all)
    func fixtureKeepsItsOriginalAndBothStreams(_ facts: FixtureFacts) async throws {
        let library = try await temporary.withFixtures().open()
        let bytes = try facts.fixture.data()
        let id = SourceIdentity(fileContents: bytes)
        let hash = ContentHash(of: bytes)

        // The original, byte for byte, under one active record.
        let record = try #require(try await library.store.sourceRecord(id))
        #expect(record.state == .active)
        #expect(record.importedAt == firstImport)
        #expect(record.revisions.map(\.contentHash) == [hash])
        #expect(record.currentRevision == hash)
        #expect(record.activityID == id)
        #expect(try await library.store.original(hash) == bytes)

        // The decoded activity, with every record.
        let recorded = try await library.recordedActivity(for: id)
        #expect(recorded.stream.samples.count == facts.records)
        #expect(recorded.sport == facts.sport)

        // The analysis stream: one second for each second of elapsed time.
        let stream = try await library.analysisStream(for: id)
        #expect(stream.count == Int(facts.elapsed.rounded(.up)))
        #expect(stream.rulesVersion == StreamRules.version)
        #expect(stream.start == Date(timeIntervalSince1970: facts.start))
        #expect(stream.isConsistent)

        #expect(FileManager.default.fileExists(atPath: temporary.originalFile(hash).path))
        #expect(FileManager.default.fileExists(atPath: temporary.recordedFile(hash).path))
        #expect(FileManager.default.fileExists(atPath: temporary.analysisFile(hash).path))
    }

    @Test(arguments: FixtureFacts.all)
    func fixtureMetricsRecordWhatTheyWereComputedFrom(_ facts: FixtureFacts) async throws {
        let library = try await temporary.withFixtures().open()
        let id = try fileIdentity(facts.fixture)
        let start = Date(timeIntervalSince1970: facts.start)
        let result = try #require(try await library.store.derivedResult(owner: .activity(id), kind: ActivityLibrary.metricsKind))

        #expect(result.provenance.inputRevision == PipelineVersions.current.inputRevision(original: try revision(facts.fixture)))
        #expect(result.provenance.algorithmVersion == PipelineVersions.current.combinedAlgorithmVersion)
        // Only a ride reads threshold power. Nothing was saved to the
        // profile, so the fingerprint is the empty profile's.
        let inputs: AthleteProfile.Inputs = facts.sport == .cycling ? [.thresholdPower, .thresholdHeartRate] : [.thresholdHeartRate]
        #expect(result.profileReading == ProfileReading(date: start, inputs: inputs))
        #expect(result.provenance.profileFingerprint == AthleteProfile().fingerprint(on: start, reading: inputs))
        #expect(result.computedAt == firstImport)

        // The stored metrics read back, and agree with the row.
        let metrics = try #require(try await library.metrics(for: id))
        let row = try #require(try await library.activity(id))
        #expect(metrics.time.elapsed == .available(row.elapsedTime))
        #expect(metrics.time.timer.value == row.timerTime)
        #expect(metrics.distance.value == row.distance)
        #expect(try await library.staleActivities().isEmpty)
    }

    @Test func theBatchReportsProgressForEveryFile() async throws {
        let imported = try await FixtureLibrary.imported()
        let total = Fixtures.FIT.allCases.count
        #expect(imported.progress.map(\.completed) == Array(1...total))
        #expect(imported.progress.allSatisfy { $0.total == total })
        // Files finish out of order, but each is reported once.
        #expect(Set(imported.progress.map(\.latest.index)) == Set(0..<total))
    }
}

/// Files that must be turned away, and what the library looks like after.
@Suite struct RejectionTests {
    let temporary = TemporaryLibrary()

    static func truncated() throws -> Data {
        let bytes = try Fixtures.FIT.walk.data()
        return bytes.prefix(bytes.count / 2)
    }

    /// The same length as the original with one byte of the recording
    /// changed, so the file's checksum no longer holds.
    static func corrupted() throws -> Data {
        var bytes = try Fixtures.FIT.walk.data()
        bytes[bytes.count / 2] ^= 0xFF
        return bytes
    }

    /// The first bytes of a zip archive.
    static let zip = Data([0x50, 0x4B, 0x03, 0x04, 0x14, 0x00, 0x00, 0x00, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00])

    private func expectEmpty(_ library: ActivityLibrary) async throws {
        #expect(try await library.store.sourceRecords().isEmpty)
        #expect(try await library.feed(limit: 10).activities.isEmpty)
        #expect(try temporary.storedFiles().isEmpty)
        #expect(try await library.staleActivities().isEmpty)
    }

    @Test func aTruncatedFileIsRejectedAndLeavesNothing() async throws {
        let library = try temporary.open()
        await #expect(throws: LibraryError.rejected(.truncated)) {
            try await library.importFile(try Self.truncated(), at: firstImport)
        }
        try await expectEmpty(library)
    }

    @Test func aCorruptedFileIsRejectedAndLeavesNothing() async throws {
        let library = try temporary.open()
        await #expect(throws: LibraryError.rejected(.corrupt)) {
            try await library.importFile(try Self.corrupted(), at: firstImport)
        }
        try await expectEmpty(library)
    }

    @Test func aZipIsRejectedAsNotFIT() async throws {
        let library = try temporary.open()
        await #expect(throws: LibraryError.rejected(.notFIT)) {
            try await library.importFile(Self.zip, at: firstImport)
        }
        try await expectEmpty(library)
    }

    @Test func aRejectedFileIsNotImportedUnderAGarminIdentityEither() async throws {
        let library = try temporary.open()
        await #expect(throws: LibraryError.rejected(.truncated)) {
            try await library.importFile(try Self.truncated(), as: SourceIdentity(source: .garmin, externalID: "1"), at: firstImport)
        }
        try await expectEmpty(library)
    }

    @Test func aRejectedFileLeavesAFilledLibraryAsItWas() async throws {
        let library = try temporary.open()
        try await library.importFile(try Fixtures.FIT.zwiftRide.data(), at: firstImport)
        let records = try await library.store.sourceRecords()
        let feed = try await library.feed(limit: 10)
        let files = try temporary.storedFiles()

        await #expect(throws: LibraryError.rejected(.corrupt)) {
            try await library.importFile(try Self.corrupted(), at: later)
        }
        #expect(try await library.store.sourceRecords() == records)
        #expect(try await library.feed(limit: 10) == feed)
        #expect(try temporary.storedFiles() == files)
    }

    @Test func theMessageIsIngestsOwn() {
        #expect(LibraryError.rejected(.truncated).errorDescription == FITDecodeError.truncated.errorDescription)
        #expect(LibraryError.rejected(.corrupt).errorDescription == FITDecodeError.corrupt.errorDescription)
    }
}

/// Importing what is already there, and importing under a source identity.
@Suite struct RepeatedImportTests {
    let temporary = TemporaryLibrary()

    @Test func importingTheSameBytesTwiceChangesAndComputesNothing() async throws {
        let library = try temporary.open()
        let bytes = try Fixtures.FIT.walk.data()
        let id = SourceIdentity(fileContents: bytes)
        let hash = ContentHash(of: bytes)

        let first = try await library.importFile(bytes, at: firstImport)
        #expect(first.change == .added)
        let records = try await library.store.sourceRecords()
        let result = try await library.store.derivedResult(owner: .activity(id), kind: ActivityLibrary.metricsKind)
        let files = try temporary.storedFiles()
        let written = try [temporary.originalFile(hash), temporary.recordedFile(hash), temporary.analysisFile(hash)].map(modificationDate)

        let second = try await library.importFile(bytes, at: later)
        #expect(second.change == .alreadyInLibrary)
        #expect(second.source == id)
        #expect(second.activity == first.activity)

        // One record with one revision, still dated by the first import.
        #expect(try await library.store.sourceRecords() == records)
        #expect(records.map(\.revisions.count) == [1])
        #expect(records.map(\.importedAt) == [firstImport])
        // The same result, computed once, and no file written again.
        #expect(try await library.store.derivedResult(owner: .activity(id), kind: ActivityLibrary.metricsKind) == result)
        #expect(result?.computedAt == firstImport)
        #expect(try temporary.storedFiles() == files)
        #expect(try [temporary.originalFile(hash), temporary.recordedFile(hash), temporary.analysisFile(hash)].map(modificationDate) == written)
        #expect(try await library.feed(limit: 10).activities == [first.activity])
    }

    @Test func aGarminDownloadIsImportedUnderItsGarminIdentity() async throws {
        let library = try temporary.open()
        let bytes = try Fixtures.FIT.zwiftRide.data()
        let garmin = SourceIdentity(source: .garmin, externalID: "24906063494")

        let result = try await library.importFile(bytes, as: garmin, at: firstImport)
        #expect(result.change == .added)
        #expect(result.source == garmin)
        #expect(result.activity.id == garmin)
        #expect(result.activity.sport == .cycling)
        #expect(try await library.metrics(for: garmin) != nil)

        // The same bytes as a plain file are recognised as that record.
        let again = try await library.importFile(bytes, at: later)
        #expect(again.change == .alreadyInLibrary)
        #expect(again.source == garmin)
        #expect(again.activity == result.activity)
        #expect(try await library.store.sourceRecords().map(\.identity) == [garmin])
        #expect(try await library.feed(limit: 10).activities.count == 1)
    }

    /// A source record whose own import stopped after its original was
    /// stored. A file with the same bytes is that record, and finishes it.
    @Test func aFileRecognisedAsAnUnfinishedRecordFinishesIt() async throws {
        let library = try temporary.open()
        let bytes = try Fixtures.FIT.zwiftRide.data()
        let garmin = SourceIdentity(source: .garmin, externalID: "24906063494")
        _ = try await library.store.importOriginal(bytes, as: garmin, at: firstImport)

        let result = try await library.importFile(bytes, at: later)
        #expect(result.change == .added)
        #expect(result.source == garmin)
        #expect(result.activity.id == garmin)
        #expect(try await library.store.sourceRecords().map(\.identity) == [garmin])
        #expect(try await library.metrics(for: garmin) != nil)
    }

    /// An imported file has no identity but the hash of its bytes.
    @Test func aFileIdentityThatIsNotTheHashIsRefusedAndStoresNothing() async throws {
        let library = try temporary.open()
        let wrong = SourceIdentity(source: .file, externalID: "not-the-hash")
        await #expect(throws: LibraryError.identityMismatch(wrong)) {
            try await library.importFile(try Fixtures.FIT.zwiftRide.data(), as: wrong, at: firstImport)
        }
        #expect(try await library.store.sourceRecords().isEmpty)
        #expect(try temporary.storedFiles().isEmpty)
    }

    /// Zwift states no offset. A sync that knows the local start time can
    /// supply one, and the title then has its time of day: 14:43 UTC is
    /// 10:43 four hours west.
    @Test func aFallbackOffsetGivesAZwiftRideItsTimeOfDay() async throws {
        let library = try temporary.open()
        let result = try await library.importFile(try Fixtures.FIT.zwiftRide.data(), fallbackUTCOffset: -14_400, at: firstImport)
        #expect(result.activity.utcOffset == -14_400)
        #expect(result.activity.title == "Morning virtual ride")
    }

    /// A file that states its own offset keeps it: 12:30 UTC is 08:30 four
    /// hours west, whatever the caller suggests.
    @Test func aFallbackOffsetDoesNotOverrideTheFilesOwn() async throws {
        let library = try temporary.open()
        let result = try await library.importFile(try Fixtures.FIT.outdoorRide.data(), fallbackUTCOffset: 36_000, at: firstImport)
        #expect(result.activity.utcOffset == -14_400)
        #expect(result.activity.title == "Morning ride")
    }

    /// "A change becomes a new revision of the same record, never an
    /// additional record", and the activity is rebuilt from it.
    @Test func changedBytesUnderOneIdentityRebuildTheSameActivity() async throws {
        let library = try temporary.open()
        let garmin = SourceIdentity(source: .garmin, externalID: "1")
        let zwift = try Fixtures.FIT.zwiftRide.data()
        let walk = try Fixtures.FIT.walk.data()

        try await library.importFile(zwift, as: garmin, at: firstImport)
        let updated = try await library.importFile(walk, as: garmin, at: later)
        #expect(updated.change == .updated)
        #expect(updated.activity.id == garmin)
        #expect(updated.activity.sport == .walking)
        // The title was generated, so it is generated again for the walk.
        #expect(updated.activity.title == "Night walk")

        let record = try #require(try await library.store.sourceRecord(garmin))
        #expect(record.revisions.map(\.contentHash) == [ContentHash(of: zwift), ContentHash(of: walk)])
        #expect(record.currentRevision == ContentHash(of: walk))
        #expect(try await library.feed(limit: 10).activities == [updated.activity])
        #expect(try await library.analysisStream(for: garmin).count == 2493)
        #expect(try await library.staleActivities().isEmpty)
    }

    /// An import that stopped after the original and the row were stored,
    /// with no streams and no metrics, is finished by importing again.
    @Test func importingAgainFinishesAnInterruptedImport() async throws {
        let library = try temporary.open()
        let bytes = try Fixtures.FIT.walk.data()
        let id = SourceIdentity(fileContents: bytes)
        _ = try await library.store.importFile(bytes, at: firstImport)
        try await library.store.saveActivity(ActivityRecord(
            members: [id], primary: id, sport: .other, start: firstImport, elapsedTime: 1,
            title: FeedRules.title(sport: .other, start: firstImport, utcOffset: nil)
        ))

        let result = try await library.importFile(bytes, at: later)
        #expect(result.change == .updated)
        #expect(result.activity.sport == .walking)
        #expect(result.activity.title == "Night walk")
        #expect(try await library.metrics(for: id) != nil)
        #expect(try await library.staleActivities().isEmpty)
    }
}

/// Several files at once.
@Suite struct BatchImportTests {
    let temporary = TemporaryLibrary()

    @Test func eachFileSucceedsOrFailsOnItsOwn() async throws {
        let library = try temporary.open()
        let walk = try Fixtures.FIT.walk.data()
        let missing = FileManager.default.temporaryDirectory.appending(path: "no-such-file-\(UUID().uuidString).fit")
        let files = [
            ImportFile(name: "walk.fit", contents: .bytes(walk)),
            ImportFile(name: "cut-short.fit", contents: .bytes(try RejectionTests.truncated())),
            ImportFile(url: Fixtures.FIT.zwiftRide.url()),
            ImportFile(name: "walk again.fit", contents: .bytes(walk)),
            ImportFile(url: missing),
            ImportFile(name: "archive.zip", contents: .bytes(RejectionTests.zip)),
        ]
        let reports = Mutex<[ImportProgress]>([])

        let outcomes = await library.importFiles(files, at: firstImport) { report in
            reports.withLock { $0.append(report) }
        }

        // One outcome per file, in the order given.
        #expect(outcomes.map(\.index) == Array(files.indices))
        #expect(outcomes.map(\.name) == ["walk.fit", "cut-short.fit", "zwift-ride.fit", "walk again.fit", missing.lastPathComponent, "archive.zip"])

        #expect(outcomes[1].failure == .rejected(.truncated))
        #expect(try outcomes[2].result.get().change == .added)
        #expect(try outcomes[2].result.get().activity.sport == .cycling)
        if case .unreadableFile = outcomes[4].failure {} else {
            Issue.record("A file that cannot be opened should be unreadable, got \(outcomes[4].result)")
        }
        #expect(outcomes[5].failure == .rejected(.notFIT))

        // The same walk twice: added once and found already there once,
        // whichever of the two got there first.
        let walks = try [outcomes[0], outcomes[3]].map { try $0.result.get() }
        #expect(Set(walks.map(\.change)) == [.added, .alreadyInLibrary])
        #expect(walks[0].activity == walks[1].activity)

        // Two activities, and nothing from the files that failed.
        #expect(try await library.feed(limit: 10).activities.count == 2)
        #expect(try await library.store.sourceRecords().count == 2)

        let progress = reports.withLock { $0 }
        #expect(progress.map(\.completed) == Array(1...files.count))
        #expect(progress.allSatisfy { $0.total == files.count })
        #expect(Set(progress.map(\.latest)) == Set(outcomes))
    }

    @Test func anEmptyBatchReportsNothing() async throws {
        let library = try temporary.open()
        let outcomes = await library.importFiles([]) { _ in
            Issue.record("No file, so no progress")
        }
        #expect(outcomes.isEmpty)
    }
}
