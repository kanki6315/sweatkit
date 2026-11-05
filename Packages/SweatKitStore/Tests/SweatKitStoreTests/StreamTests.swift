import Foundation
import SweatKitModel
import SweatKitStore
import Testing

/// The length of the longest fixture, the pit-lane walk, in seconds.
let longestFixtureSeconds = 36_142
/// The pit-lane walk's record count, for a recorded activity of that size.
let longestFixtureRecords = 27_039
let rulesVersion = 3
let decoderVersion = 2

/// A small stream with every quality, missing runs and paused spans.
func makeShortStream() -> AnalysisStream {
    var stream = AnalysisStream(rulesVersion: rulesVersion, start: referenceDate, count: 8, pauses: .known(paused: [2..<4, 6..<7]))
    stream.latitude = Series(values: [51.44, 51.4401, 0, 0, 51.4403, 51.4404, 51.4405, 51.4406],
                             quality: [.measured, .interpolated, .missing, .missing, .measured, .measured, .measured, .measured])
    stream.longitude = Series(values: [-0.27, -0.2701, 0, 0, -0.2703, -0.2704, -0.2705, -0.2706],
                              quality: [.measured, .interpolated, .missing, .missing, .measured, .measured, .measured, .measured])
    stream.power = Series([0, 250, nil, nil, 310.5, 0, nil, 199])
    stream.heartRate = Series(values: [120, 121, 121, 0, 125, 126, 126, 127],
                              quality: [.measured, .measured, .interpolated, .missing, .measured, .measured, .interpolated, .measured])
    stream.distance = Series([0, 4.1, 8.3, nil, 12, 16, 20, 24.25])
    stream.gradient = Series([nil, 0.05, -0.012, nil, nil, 0, 0.1, nil])
    return stream
}

/// A recorded activity with sparse channels, timer events and laps.
func makeShortRecording() -> RecordedActivity {
    let t = { (offset: Double) in referenceDate.addingTimeInterval(offset) }
    return RecordedActivity(
        sport: .cycling,
        isIndoor: false,
        isVirtual: true,
        stated: StatedSummary(start: t(0), end: nil, timerTime: 5.5, distance: 24.25, ascent: nil, utcOffset: -18_000),
        timerEvents: [TimerEvent(kind: .start, timestamp: t(0)), TimerEvent(kind: .stop, timestamp: t(2)), TimerEvent(kind: .start, timestamp: t(4))],
        laps: [RecordedLap(start: t(0), end: t(4)), RecordedLap(start: t(4), end: t(8))],
        stream: NativeStream(samples: [
            NativeSample(timestamp: t(0), position: Coordinate(latitude: 51.44, longitude: -0.27), altitude: 10, distance: 0, heartRate: 120, power: 0),
            NativeSample(timestamp: t(1.25), heartRate: 121, cadence: 85),
            NativeSample(timestamp: t(4), position: Coordinate(latitude: 51.4403, longitude: -0.2703), speed: 4.2, temperature: 18.5),
            NativeSample(timestamp: t(7.999)),
        ])
    )
}

/// A stream as long as the longest fixture, with realistic values, dropouts
/// and about 2.5 hours paused.
func makeLongStream() -> AnalysisStream {
    let count = longestFixtureSeconds
    let pauses = [3_000..<4_800, 12_000..<15_600, 25_000..<28_600]
    var stream = AnalysisStream(rulesVersion: rulesVersion, start: referenceDate, count: count, pauses: .known(paused: pauses))
    func series(_ value: (Int) -> Double, missing: (Int) -> Bool = { _ in false }) -> Series {
        Series((0..<count).map { missing($0) ? nil : value($0) })
    }
    let dropout = { (i: Int) in i % 997 < 12 }
    stream.latitude = series({ 51.44 + 0.01 * sin(Double($0) / 700) }, missing: dropout)
    stream.longitude = series({ -0.27 + 0.015 * cos(Double($0) / 900) }, missing: dropout)
    stream.altitude = series({ 30 + 12 * sin(Double($0) / 300) })
    stream.distance = series({ Double($0) * 1.4 })
    stream.speed = series({ 1.4 + 0.2 * sin(Double($0) / 37) })
    stream.heartRate = series({ (100 + 20 * sin(Double($0) / 120)).rounded() }, missing: { $0 % 5_000 < 30 })
    stream.power = series({ _ in 0 }, missing: { $0 % 2 == 0 })
    stream.cadence = series({ (100 + 8 * sin(Double($0) / 50)).rounded() })
    stream.temperature = series({ (14 + Double($0) / 6_000).rounded() })
    stream.gradient = series({ 0.04 * cos(Double($0) / 300) }, missing: { $0 % 61 == 0 })
    return stream
}

@Suite struct StreamTests {
    @Test func analysisStreamRoundTrips() async throws {
        let library = TemporaryLibrary()
        let store = try library.open()
        let revision = try await storeGarminRecord(1, in: store)
        let stream = makeShortStream()

        try await store.saveAnalysisStream(stream, for: revision)

        #expect(await store.analysisStream(for: revision, rulesVersion: rulesVersion) == .available(stream))
    }

    @Test func unknownPausesRoundTrip() async throws {
        let library = TemporaryLibrary()
        let store = try library.open()
        let revision = try await storeGarminRecord(1, in: store)
        for pauses in [PauseData.unknown(statedTimerTime: 5_335.7), .unknown(statedTimerTime: nil), .known(paused: [])] {
            var stream = makeShortStream()
            stream.pauses = pauses
            try await store.saveAnalysisStream(stream, for: revision)
            #expect(await store.analysisStream(for: revision, rulesVersion: rulesVersion) == .available(stream))
        }
    }

    @Test func emptyStreamRoundTrips() async throws {
        let library = TemporaryLibrary()
        let store = try library.open()
        let revision = try await storeGarminRecord(1, in: store)
        let stream = AnalysisStream(rulesVersion: rulesVersion, start: referenceDate, count: 0)

        try await store.saveAnalysisStream(stream, for: revision)

        #expect(await store.analysisStream(for: revision, rulesVersion: rulesVersion) == .available(stream))
    }

    @Test func recordedActivityRoundTrips() async throws {
        let library = TemporaryLibrary()
        let store = try library.open()
        let revision = try await storeGarminRecord(1, in: store)
        let recording = makeShortRecording()

        try await store.saveRecordedActivity(recording, decoderVersion: decoderVersion, for: revision)

        #expect(await store.recordedActivity(for: revision, decoderVersion: decoderVersion) == .available(recording))
        #expect(await store.recordedActivity(for: revision, decoderVersion: decoderVersion + 1) == .needsRebuild(.outdated))
    }

    @Test func aDeletedStreamFileNeedsARebuild() async throws {
        let library = TemporaryLibrary()
        let store = try library.open()
        let revision = try await storeGarminRecord(1, in: store)
        try await store.saveAnalysisStream(makeShortStream(), for: revision)
        try await store.saveRecordedActivity(makeShortRecording(), decoderVersion: decoderVersion, for: revision)

        try FileManager.default.removeItem(at: library.analysisFile(revision))
        try FileManager.default.removeItem(at: library.recordedFile(revision))

        #expect(await store.analysisStream(for: revision, rulesVersion: rulesVersion) == .needsRebuild(.missing))
        #expect(await store.recordedActivity(for: revision, decoderVersion: decoderVersion) == .needsRebuild(.missing))
        #expect(try await store.sourceRecord(garmin(1))?.currentRevision == revision)
    }

    @Test func aTruncatedStreamFileNeedsARebuild() async throws {
        let library = TemporaryLibrary()
        let store = try library.open()
        let revision = try await storeGarminRecord(1, in: store)
        try await store.saveAnalysisStream(makeLongStream(), for: revision)
        try await store.saveRecordedActivity(makeShortRecording(), decoderVersion: decoderVersion, for: revision)

        // Cut inside the header, at the end of the header, inside the body and
        // one byte short. The header is 56 bytes.
        func cuts(_ file: URL) throws -> (Data, [Int]) {
            let whole = try Data(contentsOf: file)
            return (whole, [3, 56, whole.count / 2, whole.count - 1])
        }
        let (analysis, analysisCuts) = try cuts(library.analysisFile(revision))
        for length in analysisCuts {
            try analysis.prefix(length).write(to: library.analysisFile(revision))
            #expect(await store.analysisStream(for: revision, rulesVersion: rulesVersion) == .needsRebuild(.unreadable))
        }
        let (recorded, recordedCuts) = try cuts(library.recordedFile(revision))
        for length in recordedCuts {
            try recorded.prefix(length).write(to: library.recordedFile(revision))
            #expect(await store.recordedActivity(for: revision, decoderVersion: decoderVersion) == .needsRebuild(.unreadable))
        }
        #expect(await store.analysisStream(for: revision, rulesVersion: rulesVersion) == .needsRebuild(.unreadable))
        #expect(await store.recordedActivity(for: revision, decoderVersion: decoderVersion) == .needsRebuild(.unreadable))
        #expect(try await store.sourceRecord(garmin(1))?.currentRevision == revision)
    }

    @Test func aCorruptByteInTheBodyNeedsARebuild() async throws {
        let library = TemporaryLibrary()
        let store = try library.open()
        let revision = try await storeGarminRecord(1, in: store)
        try await store.saveAnalysisStream(makeLongStream(), for: revision)
        let file = library.analysisFile(revision)
        var bytes = try Data(contentsOf: file)
        bytes[bytes.count - 100] ^= 0x5A
        try bytes.write(to: file)

        #expect(await store.analysisStream(for: revision, rulesVersion: rulesVersion) == .needsRebuild(.unreadable))
    }

    @Test func otherFilesAreNotStreams() async throws {
        let library = TemporaryLibrary()
        let store = try library.open()
        let revision = try await storeGarminRecord(1, in: store)
        try await store.saveRecordedActivity(makeShortRecording(), decoderVersion: decoderVersion, for: revision)
        // A recorded-activity file under the analysis name.
        try FileManager.default.copyItem(at: library.recordedFile(revision), to: library.analysisFile(revision))

        #expect(await store.analysisStream(for: revision, rulesVersion: rulesVersion) == .needsRebuild(.unreadable))
    }

    @Test func aNewerFormatNeedsARebuild() async throws {
        let library = TemporaryLibrary()
        let store = try library.open()
        let revision = try await storeGarminRecord(1, in: store)
        try await store.saveAnalysisStream(makeShortStream(), for: revision)
        let file = library.analysisFile(revision)
        var bytes = try Data(contentsOf: file)
        // The format version follows the four-byte magic.
        let versionOffset = 4
        bytes[versionOffset] = 0xFF
        try bytes.write(to: file)

        #expect(await store.analysisStream(for: revision, rulesVersion: rulesVersion) == .needsRebuild(.unsupportedFormat))
    }

    @Test func aStreamFromOtherRulesIsOutdated() async throws {
        let library = TemporaryLibrary()
        let store = try library.open()
        let revision = try await storeGarminRecord(1, in: store)
        try await store.saveAnalysisStream(makeShortStream(), for: revision)

        #expect(await store.analysisStream(for: revision, rulesVersion: rulesVersion + 1) == .needsRebuild(.outdated))
    }

    @Test func aStreamNeedsAStoredRevision() async throws {
        let library = TemporaryLibrary()
        let store = try library.open()
        let unknown = ContentHash(of: Data("nothing".utf8))

        await #expect(throws: StoreError.unknownRevision(unknown)) {
            try await store.saveAnalysisStream(makeShortStream(), for: unknown)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: library.streamsDirectory.path).isEmpty)
    }

    /// The spec targets cached data for a 5-hour ride on screen within 1
    /// second on the phone, so a read here should be a small fraction of that.
    /// `swift test` builds without optimisation, which reads about 20 times
    /// slower than a release build, so the budget allows for that.
    static let longStreamReadBudget: TimeInterval = 0.25
    static let readRepeats = 5

    @Test func longStreamSizeAndReadTime() async throws {
        let library = TemporaryLibrary()
        let store = try library.open()
        let revision = try await storeGarminRecord(1, in: store)
        let stream = makeLongStream()
        let clock = ContinuousClock()

        let writeTime = try await clock.measure { try await store.saveAnalysisStream(stream, for: revision) }
        let size = try FileManager.default.attributesOfItem(atPath: library.analysisFile(revision).path)[.size] as? Int ?? 0

        var readTimes: [Double] = []
        var read: StreamRead<AnalysisStream> = .needsRebuild(.missing)
        for _ in 0..<Self.readRepeats {
            readTimes.append(seconds(await clock.measure { read = await store.analysisStream(for: revision, rulesVersion: rulesVersion) }))
        }

        #expect(read == .available(stream))
        #expect(readTimes[0] < Self.longStreamReadBudget)
        recordMeasurement(
            """
            analysis stream, \(longestFixtureSeconds) s
            file bytes: \(size)
            write seconds: \(seconds(writeTime))
            first read seconds: \(readTimes[0])
            best read seconds: \(readTimes.min() ?? 0)
            """,
            named: "long-stream.txt"
        )
    }

    @Test func longRecordingSizeAndReadTime() async throws {
        let library = TemporaryLibrary()
        let store = try library.open()
        let revision = try await storeGarminRecord(1, in: store)
        let samples = (0..<longestFixtureRecords).map { i in
            NativeSample(
                timestamp: referenceDate.addingTimeInterval(Double(i) * 1.3367),
                position: i % 200 == 0 ? nil : Coordinate(latitude: 51.44 + Double(i) * 1e-6, longitude: -0.27 - Double(i) * 1e-6),
                altitude: 30 + Double(i % 400) * 0.2,
                distance: Double(i) * 0.66,
                speed: 1.4,
                heartRate: Double(100 + i % 40),
                cadence: Double(50 + i % 10),
                temperature: 15
            )
        }
        let recording = RecordedActivity(sport: .walking, stream: NativeStream(samples: samples))
        try await store.saveRecordedActivity(recording, decoderVersion: decoderVersion, for: revision)
        let size = try FileManager.default.attributesOfItem(atPath: library.recordedFile(revision).path)[.size] as? Int ?? 0

        var read: StreamRead<RecordedActivity> = .needsRebuild(.missing)
        let readTime = await ContinuousClock().measure {
            read = await store.recordedActivity(for: revision, decoderVersion: decoderVersion)
        }

        #expect(read == .available(recording))
        recordMeasurement(
            """
            recorded activity, \(longestFixtureRecords) samples
            file bytes: \(size)
            read seconds: \(seconds(readTime))
            """,
            named: "long-recording.txt"
        )
    }
}
