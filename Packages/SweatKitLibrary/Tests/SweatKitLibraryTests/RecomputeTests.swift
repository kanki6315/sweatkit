import Foundation
import Synchronization
import SweatKitAnalysis
import SweatKitLibrary
import SweatKitModel
import SweatKitStore
import SweatKitTestSupport
import Testing

private func metricsResult(_ fixture: Fixtures.FIT, in library: ActivityLibrary) async throws -> DerivedResult {
    try #require(try await library.store.derivedResult(owner: .activity(try fileIdentity(fixture)), kind: ActivityLibrary.metricsKind))
}

private func ids(_ fixtures: [Fixtures.FIT]) throws -> [SourceIdentity] {
    try fixtures.map(fileIdentity).sorted()
}

/// The profile, and what a change to it makes stale.
@Suite struct ProfileStalenessTests {
    let temporary = TemporaryLibrary()

    @Test func theProfileIsEmptyUntilSavedAndSurvivesReopening() async throws {
        do {
            let library = try temporary.open()
            #expect(try await library.profile() == AthleteProfile())
            #expect(try await library.saveProfile(profile()).isEmpty)
        }
        #expect(try await temporary.open().profile() == profile())
    }

    /// The first thresholds stale every activity: every sport reads the
    /// threshold heart rate. Each is rebuilt from its stored stream.
    @Test func settingThresholdsStalesEveryActivityAndRecomputeClearsIt() async throws {
        let library = try await temporary.withFixtures().open()
        let stale = try await library.saveProfile(profile())
        #expect(stale.map(\.id) == (try ids(Fixtures.FIT.allCases)))
        #expect(stale.allSatisfy { $0.reasons == [.profile] })
        #expect(try await library.staleActivities() == stale)

        let reports = Mutex<[RecomputeProgress]>([])
        let report = try await library.recompute(at: later) { progress in
            reports.withLock { $0.append(progress) }
        }
        #expect(report.failures.isEmpty)
        #expect(report.rebuilt.map(\.id) == stale.map(\.id))
        #expect(report.rebuilt.allSatisfy { $0.source == .analysisStream && $0.reasons == [.profile] })
        // Nothing the feed shows depends on a threshold.
        #expect(report.rebuilt.allSatisfy { !$0.feedRowChanged })
        #expect(reports.withLock { $0 } == (1...4).map { RecomputeProgress(completed: $0, total: 4) })
        #expect(try await library.staleActivities().isEmpty)

        // The ride now has what the threshold was missing for: intensity is
        // weighted power over the 250 W threshold.
        let metrics = try #require(try await library.metrics(for: try fileIdentity(.outdoorRide)))
        let weighted = try #require(metrics.power.weighted.value)
        #expect(close(metrics.power.intensity.value, weighted / 250))
        #expect(metrics.load.value?.source == .power)
        #expect(!metrics.promptsForThresholdPower)
        // The walk's load comes from heart rate: 90% of a max of 190.
        let walk = try #require(try await library.metrics(for: try fileIdentity(.walk)))
        #expect(walk.load.value?.source == .heartRate)

        // A second recompute finds nothing to do.
        #expect(try await library.recompute(at: laterStill) == RecomputeReport())
    }

    /// "A historical threshold is corrected: zones, intensity and load for
    /// activities in the affected dates." The outdoor ride is in the
    /// corrected range. The Zwift ride, two months later, is not, and the
    /// walks never read threshold power.
    @Test func aThresholdCorrectedForADateRangeRecomputesOnlyTheRideInIt() async throws {
        let library = try await temporary.withFixtures().open()
        try await library.saveProfile(profile())
        try await library.recompute(at: later)

        let ride = Date(timeIntervalSince1970: try FixtureFacts.of(.outdoorRide).start)
        let zwift = Date(timeIntervalSince1970: try FixtureFacts.of(.zwiftRide).start)
        var corrected = profile()
        // 265 W from the day before the ride to the day after, then 250 W again.
        corrected.thresholdPowerHistory += [
            .init(effectiveFrom: ride.addingTimeInterval(-secondsPerDay), watts: 265),
            .init(effectiveFrom: ride.addingTimeInterval(secondsPerDay), watts: 250),
        ]
        #expect(ride.addingTimeInterval(secondsPerDay) < zwift)

        let stale = try await library.saveProfile(corrected)
        #expect(stale == [StaleActivity(id: try fileIdentity(.outdoorRide), reasons: [.profile])])

        let report = try await library.recompute(at: laterStill)
        #expect(report.failures.isEmpty)
        #expect(report.rebuilt == [
            .init(id: try fileIdentity(.outdoorRide), reasons: [.profile], source: .analysisStream, feedRowChanged: false),
        ])
        #expect(try await library.staleActivities().isEmpty)

        // Only the ride was computed again, under the corrected threshold.
        #expect(try await metricsResult(.outdoorRide, in: library).computedAt == laterStill)
        for untouched in [Fixtures.FIT.zwiftRide, .walk, .walkPitlane] {
            #expect(try await metricsResult(untouched, in: library).computedAt == later)
        }
        let metrics = try #require(try await library.metrics(for: try fileIdentity(.outdoorRide)))
        let weighted = try #require(metrics.power.weighted.value)
        #expect(close(metrics.power.intensity.value, weighted / 265))
        let zwiftMetrics = try #require(try await library.metrics(for: try fileIdentity(.zwiftRide)))
        #expect(close(zwiftMetrics.power.intensity.value, try #require(zwiftMetrics.power.weighted.value) / 250))
    }

    /// A threshold that takes effect after every activity changes none.
    @Test func aThresholdForLaterDatesStalesNothing() async throws {
        let library = try await temporary.withFixtures().open()
        try await library.saveProfile(profile())
        try await library.recompute(at: later)

        var raised = profile()
        let afterEverything = Date(timeIntervalSince1970: try FixtureFacts.of(.zwiftRide).start + secondsPerDay)
        raised.thresholdPowerHistory.append(.init(effectiveFrom: afterEverything, watts: 280))
        #expect(try await library.saveProfile(raised).isEmpty)
    }

    /// Threshold power is read by rides only. Weight and units are read by
    /// no stored result.
    @Test func onlyTheValuesAResultReadCanStaleIt() async throws {
        let library = try await temporary.withFixtures().open()
        try await library.saveProfile(profile())
        try await library.recompute(at: later)

        var changed = profile()
        changed.weight = 70
        changed.units = .imperial
        #expect(try await library.saveProfile(changed).isEmpty)

        let stale = try await library.saveProfile(profile(thresholdPower: 240))
        #expect(stale.map(\.id) == (try ids([.outdoorRide, .zwiftRide])))

        // The stated threshold heart rate replaces 90% of max for everyone.
        var heartRate = profile(thresholdPower: 240)
        heartRate.statedThresholdHeartRate = 165
        try await library.recompute(at: laterStill)
        #expect(try await library.saveProfile(heartRate).map(\.id) == (try ids(Fixtures.FIT.allCases)))
    }
}

/// A later build's versions, and what they make stale.
@Suite struct VersionStalenessTests {
    let temporary = TemporaryLibrary()

    /// "An algorithm version changes: everything that algorithm produces."
    /// Only the metrics are computed again, from the stored streams.
    @Test func aChangedAlgorithmVersionRecomputesFromTheStoredStreams() async throws {
        try await temporary.withFixtures()
        var newer = PipelineVersions.current
        newer.algorithms[PipelineVersions.AlgorithmName.elevation] = AlgorithmVersion.elevation + 1
        let library = try temporary.open(versions: newer)
        let streamFiles = try Fixtures.FIT.allCases.flatMap { fixture in
            [temporary.recordedFile(try revision(fixture)), temporary.analysisFile(try revision(fixture))]
        }
        let written = try streamFiles.map(modificationDate)

        let stale = try await library.staleActivities()
        #expect(stale.map(\.id) == (try ids(Fixtures.FIT.allCases)))
        #expect(stale.allSatisfy { $0.reasons == [.algorithm] })

        let report = try await library.recompute(at: later)
        #expect(report.failures.isEmpty)
        #expect(report.rebuilt.map(\.id) == stale.map(\.id))
        #expect(report.rebuilt.allSatisfy { $0.source == .analysisStream })
        #expect(try streamFiles.map(modificationDate) == written)

        for fixture in Fixtures.FIT.allCases {
            let result = try await metricsResult(fixture, in: library)
            #expect(result.provenance.algorithmVersion == newer.combinedAlgorithmVersion)
            #expect(result.computedAt == later)
        }
        #expect(try await library.staleActivities().isEmpty)
        // The build before it would call these results stale in turn.
        do {
            let older = ActivityLibrary(store: library.store)
            #expect(try await older.staleActivities().count == 4)
        }
    }

    /// "The analysis stream is rebuilt from the native stream whenever a
    /// rule changes": from the stored decoded activity, with no decoding.
    @Test func aChangedStreamRulesVersionRebuildsFromTheDecodedActivity() async throws {
        try await temporary.withFixtures()
        var newer = PipelineVersions.current
        newer.streamRules += 1
        let library = try temporary.open(versions: newer)
        let recordedFiles = try Fixtures.FIT.allCases.map { temporary.recordedFile(try revision($0)) }
        let written = try recordedFiles.map(modificationDate)

        let stale = try await library.staleActivities()
        #expect(stale.map(\.id) == (try ids(Fixtures.FIT.allCases)))
        #expect(stale.allSatisfy { $0.reasons == [.input] })

        let report = try await library.recompute(at: later)
        #expect(report.failures.isEmpty)
        #expect(report.rebuilt.map(\.id) == stale.map(\.id))
        #expect(report.rebuilt.allSatisfy { $0.source == .recordedActivity })
        // The decoded activities were read, not written again.
        #expect(try recordedFiles.map(modificationDate) == written)

        for fixture in Fixtures.FIT.allCases {
            let stream = try await library.analysisStream(for: try fileIdentity(fixture))
            #expect(stream.rulesVersion == newer.streamRules)
            let result = try await metricsResult(fixture, in: library)
            #expect(result.provenance.inputRevision == newer.inputRevision(original: try revision(fixture)))
        }
        #expect(try await library.staleActivities().isEmpty)
    }

    /// A changed decoder goes back to the original. One small file, because
    /// this decodes it again.
    @Test func aChangedDecoderVersionDecodesTheOriginalAgain() async throws {
        let bytes = try Fixtures.FIT.walk.data()
        let id = SourceIdentity(fileContents: bytes)
        do {
            let library = try temporary.open()
            try await library.importFile(bytes, at: firstImport)
        }
        var newer = PipelineVersions.current
        newer.decoder += 1
        let library = try temporary.open(versions: newer)

        #expect(try await library.staleActivities() == [StaleActivity(id: id, reasons: [.input])])
        let report = try await library.recompute(at: later)
        #expect(report.failures.isEmpty)
        #expect(report.rebuilt == [.init(id: id, reasons: [.input], source: .original, feedRowChanged: false)])
        #expect(try await library.staleActivities().isEmpty)

        // The stored decoded activity now carries the new decoder's version.
        let hash = ContentHash(of: bytes)
        #expect(await library.store.recordedActivity(for: hash, decoderVersion: newer.decoder).value != nil)
        #expect(await library.store.recordedActivity(for: hash, decoderVersion: PipelineVersions.decoderVersion).value == nil)
    }
}

/// Stream files that have gone missing, and writes that never finished.
@Suite struct RepairTests {
    let temporary = TemporaryLibrary()

    private func remove(_ url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// The metrics are still valid, so only a pass that checks the files
    /// finds it. The stream is rebuilt from the decoded activity.
    @Test func aDeletedAnalysisStreamIsRebuiltFromTheDecodedActivity() async throws {
        let library = try await temporary.withFixtures().open()
        let id = try fileIdentity(.zwiftRide)
        let hash = try revision(.zwiftRide)
        let stream = try await library.analysisStream(for: id)
        try remove(temporary.analysisFile(hash))

        #expect(try await library.staleActivities().isEmpty)
        #expect(try await library.staleActivities(checkingStreamFiles: true) == [StaleActivity(id: id, reasons: [.streamFile])])

        let report = try await library.recompute(checkingStreamFiles: true, at: later)
        #expect(report.failures.isEmpty)
        #expect(report.rebuilt == [.init(id: id, reasons: [.streamFile], source: .recordedActivity, feedRowChanged: false)])
        #expect(exists(temporary.analysisFile(hash)))
        #expect(try await library.analysisStream(for: id) == stream)
        #expect(try await library.staleActivities(checkingStreamFiles: true).isEmpty)
    }

    /// With the decoded activity gone too, the original is decoded again
    /// and both files come back.
    @Test func bothStreamFilesDeletedAreRebuiltFromTheOriginal() async throws {
        let library = try await temporary.withFixtures().open()
        let id = try fileIdentity(.zwiftRide)
        let hash = try revision(.zwiftRide)
        let stream = try await library.analysisStream(for: id)
        let recorded = try await library.recordedActivity(for: id)
        try remove(temporary.analysisFile(hash))
        try remove(temporary.recordedFile(hash))

        let report = try await library.recompute(checkingStreamFiles: true, at: later)
        #expect(report.failures.isEmpty)
        #expect(report.rebuilt == [.init(id: id, reasons: [.streamFile], source: .original, feedRowChanged: false)])
        #expect(exists(temporary.analysisFile(hash)) && exists(temporary.recordedFile(hash)))
        #expect(try await library.analysisStream(for: id) == stream)
        #expect(try await library.recordedActivity(for: id) == recorded)
    }

    /// The decoded activity can only come from the original, so that is
    /// what is read, though the analysis stream was still good.
    @Test func aDeletedDecodedActivityAloneIsDecodedAgainFromTheOriginal() async throws {
        let library = try await temporary.withFixtures().open()
        let id = try fileIdentity(.zwiftRide)
        let hash = try revision(.zwiftRide)
        try remove(temporary.recordedFile(hash))

        #expect(try await library.staleActivities(checkingStreamFiles: true) == [StaleActivity(id: id, reasons: [.streamFile])])
        let report = try await library.recompute(checkingStreamFiles: true, at: later)
        #expect(report.rebuilt.map(\.source) == [.original])
        #expect(exists(temporary.recordedFile(hash)))
        #expect(try await library.staleActivities(checkingStreamFiles: true).isEmpty)
    }

    /// Reading a stream whose file is gone rebuilds it on the way.
    @Test func readingADeletedStreamRebuildsIt() async throws {
        let library = try await temporary.withFixtures().open()
        let id = try fileIdentity(.walk)
        let hash = try revision(.walk)
        let stream = try await library.analysisStream(for: id)
        let computedAt = try await metricsResult(.walk, in: library).computedAt
        try remove(temporary.analysisFile(hash))
        try remove(temporary.recordedFile(hash))

        #expect(try await library.analysisStream(for: id) == stream)
        #expect(exists(temporary.analysisFile(hash)) && exists(temporary.recordedFile(hash)))
        // The metrics were valid and are left alone.
        #expect(try await metricsResult(.walk, in: library).computedAt == computedAt)
    }

    /// A recompute that needs a stream the file no longer holds falls back
    /// without being asked to check files.
    @Test func aStaleActivityWithNoStreamFileFallsBackToTheDecodedActivity() async throws {
        let library = try await temporary.withFixtures().open()
        let id = try fileIdentity(.zwiftRide)
        try remove(temporary.analysisFile(try revision(.zwiftRide)))
        try await library.saveProfile(profile())

        let report = try await library.recompute(at: later)
        #expect(report.failures.isEmpty)
        let sources = Dictionary(uniqueKeysWithValues: report.rebuilt.map { ($0.id, $0.source) })
        #expect(sources[id] == .recordedActivity)
        #expect(sources.filter { $0.key != id }.values.allSatisfy { $0 == .analysisStream })
        #expect(exists(temporary.analysisFile(try revision(.zwiftRide))))
    }

    /// With the original gone as well there is nothing to rebuild from. The
    /// activity is reported, left as it was, and the rest are still done.
    @Test func aMissingOriginalIsReportedAndTheOthersAreStillRebuilt() async throws {
        let library = try await temporary.withFixtures().open()
        let id = try fileIdentity(.zwiftRide)
        let hash = try revision(.zwiftRide)
        let row = try await library.activity(id)
        try remove(temporary.analysisFile(hash))
        try remove(temporary.recordedFile(hash))
        try remove(temporary.originalFile(hash))
        try await library.saveProfile(profile())

        let report = try await library.recompute(at: later)
        #expect(report.failures == [.init(id: id, error: .originalMissing(hash))])
        #expect(report.rebuilt.map(\.id) == (try ids([.outdoorRide, .walk, .walkPitlane])))
        #expect(try await library.activity(id) == row)
        // Still stale, so the next recompute tries again.
        #expect(try await library.staleActivities().map(\.id) == [id])
        await #expect(throws: LibraryError.originalMissing(hash)) {
            try await library.analysisStream(for: id)
        }
    }

    /// An import that stored the original and the row and then stopped has
    /// no metrics. A recompute finds it and builds everything.
    @Test func anActivityWithNoMetricsIsFoundAndBuilt() async throws {
        let library = try temporary.open()
        let bytes = try Fixtures.FIT.walk.data()
        let id = SourceIdentity(fileContents: bytes)
        _ = try await library.store.importFile(bytes, at: firstImport)
        try await library.store.saveActivity(ActivityRecord(
            members: [id], primary: id, sport: .other, start: firstImport, elapsedTime: 1,
            title: FeedRules.title(sport: .other, start: firstImport, utcOffset: nil)
        ))

        #expect(try await library.staleActivities() == [StaleActivity(id: id, reasons: [.notComputed])])
        let report = try await library.recompute(at: later)
        #expect(report.failures.isEmpty)
        #expect(report.rebuilt == [.init(id: id, reasons: [.notComputed], source: .original, feedRowChanged: true)])

        let facts = try FixtureFacts.of(.walk)
        let row = try #require(try await library.activity(id))
        #expect(row.sport == .walking)
        #expect(row.start == Date(timeIntervalSince1970: facts.start))
        #expect(row.title == facts.title)
        #expect(try await library.metrics(for: id) != nil)
        #expect(try await library.staleActivities().isEmpty)
    }

    /// An import that stopped earlier still, with only the original and its
    /// source record stored. The record becomes its own activity.
    @Test func aSourceRecordWithNoActivityIsFoundAndBuilt() async throws {
        let library = try temporary.open()
        let bytes = try Fixtures.FIT.zwiftRide.data()
        let garmin = SourceIdentity(source: .garmin, externalID: "24906063494")
        _ = try await library.store.importOriginal(bytes, as: garmin, at: firstImport)
        #expect(try await library.feed(limit: 10).activities.isEmpty)

        #expect(try await library.staleActivities() == [StaleActivity(id: garmin, reasons: [.notComputed])])
        let report = try await library.recompute(at: later)
        #expect(report.failures.isEmpty)
        #expect(report.rebuilt == [.init(id: garmin, reasons: [.notComputed], source: .original, feedRowChanged: true)])

        let row = try #require(try await library.activity(garmin))
        #expect(row.members == [garmin])
        #expect(row.sport == .cycling && row.isVirtual)
        #expect(row.title == "Virtual ride")
        #expect(try await library.feed(limit: 10).activities == [row])
        #expect(try await library.metrics(for: garmin) != nil)
        #expect(try await library.staleActivities().isEmpty)
    }

    /// A title someone wrote and a hidden state belong to the activity, and
    /// a recompute keeps both.
    @Test func aRecomputeKeepsAWrittenTitleAndTheHiddenState() async throws {
        try await temporary.withFixtures()
        let renamed = try fileIdentity(.zwiftRide)
        let hidden = try fileIdentity(.walk)
        do {
            let library = try temporary.open()
            var row = try #require(try await library.activity(renamed))
            row.title = "Race day"
            try await library.store.saveActivity(row)
            row = try #require(try await library.activity(hidden))
            row.isHidden = true
            try await library.store.saveActivity(row)
        }
        var newer = PipelineVersions.current
        newer.algorithms[PipelineVersions.AlgorithmName.feedRow] = PipelineVersions.feedRowVersion + 1
        let library = try temporary.open(versions: newer)

        let report = try await library.recompute(at: later)
        #expect(report.rebuilt.count == 4)
        #expect(report.rebuilt.allSatisfy { !$0.feedRowChanged })
        #expect(try await library.activity(renamed)?.title == "Race day")
        #expect(try await library.activity(hidden)?.isHidden == true)
        #expect(try await library.feed(limit: 10).activities.map(\.title) == ["Race day", "Afternoon walk", "Morning ride"])
    }

    @Test func anUnknownActivityIsAnError() async throws {
        let library = try temporary.open()
        let nobody = SourceIdentity(source: .garmin, externalID: "0")
        #expect(try await library.activity(nobody) == nil)
        #expect(try await library.metrics(for: nobody) == nil)
        await #expect(throws: LibraryError.unknownActivity(nobody)) {
            try await library.analysisStream(for: nobody)
        }
    }
}
