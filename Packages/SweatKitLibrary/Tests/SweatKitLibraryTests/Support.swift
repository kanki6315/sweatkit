import Foundation
import Synchronization
import SweatKitLibrary
import SweatKitModel
import SweatKitStore
import SweatKitTestSupport
import Testing

/// A library in its own temporary directory, removed when the test ends.
///
/// Each suite holds one as a stored property. Swift Testing makes a new
/// suite value for every test, and that value outlives the test's body, so
/// the directory is there for as long as the test uses it. One held only in
/// a local can be released, and the directory removed, while the library is
/// still open.
final class TemporaryLibrary: Sendable {
    let root: URL

    init() {
        root = FileManager.default.temporaryDirectory
            .appending(path: "SweatKitLibraryTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    /// Opens the library from disk. Each call is a fresh store, as after a
    /// relaunch, so the earlier one must be out of use.
    func open(versions: PipelineVersions = .current) throws -> ActivityLibrary {
        try ActivityLibrary(root: root, versions: versions)
    }

    /// Fills the directory with a copy of the library that holds all four
    /// fixtures. Call it before the first `open()`.
    @discardableResult
    func withFixtures() async throws -> TemporaryLibrary {
        try FileManager.default.copyItem(at: try await FixtureLibrary.imported().root, to: root)
        return self
    }

    var originalsDirectory: URL { root.appending(path: "Originals", directoryHint: .isDirectory) }
    var streamsDirectory: URL { root.appending(path: "Streams", directoryHint: .isDirectory) }

    func originalFile(_ revision: ContentHash) -> URL {
        originalsDirectory.appending(path: revision.hex)
    }

    func analysisFile(_ revision: ContentHash) -> URL {
        streamsDirectory.appending(path: "\(revision.hex).analysis")
    }

    func recordedFile(_ revision: ContentHash) -> URL {
        streamsDirectory.appending(path: "\(revision.hex).recorded")
    }

    /// The names of the files the library holds outside its database.
    func storedFiles() throws -> Set<String> {
        var names: Set<String> = []
        for directory in [originalsDirectory, streamsDirectory] {
            for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
                names.insert("\(directory.lastPathComponent)/\(url.lastPathComponent)")
            }
        }
        return names
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }
}

/// When a file was last written.
func modificationDate(_ url: URL) throws -> Date {
    try #require(try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)
}

let secondsPerDay: TimeInterval = 86_400

/// Fixed times, so no test depends on the clock.
let firstImport = Date(timeIntervalSince1970: 1_800_000_000)
let later = firstImport.addingTimeInterval(secondsPerDay)
let laterStill = later.addingTimeInterval(secondsPerDay)

/// The identity of a fixture imported as a plain file: the hash of its bytes.
func fileIdentity(_ fixture: Fixtures.FIT) throws -> SourceIdentity {
    SourceIdentity(fileContents: try fixture.data())
}

/// The content hash of a fixture, which names its stored files.
func revision(_ fixture: Fixtures.FIT) throws -> ContentHash {
    ContentHash(of: try fixture.data())
}

/// A library holding all four fixtures, imported once for the whole test run
/// and copied for each test that wants it. The pit-lane walk takes several
/// seconds to decode in a debug build, so it is decoded here and nowhere else.
enum FixtureLibrary {
    struct Template: Sendable {
        var root: URL
        /// What the batch import reported for each fixture.
        var outcomes: [Fixtures.FIT: ImportFileOutcome]
        /// Every progress report of the batch, in the order it arrived.
        var progress: [ImportProgress]
    }

    private static let template = Task<Template, any Error> {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "SweatKitLibraryTests-template-\(UUID().uuidString)", directoryHint: .isDirectory)
        templateRoot.withLock { $0 = root.path }
        atexit { templateRoot.withLock { path in try? FileManager.default.removeItem(atPath: path) } }

        let fixtures = Fixtures.FIT.allCases
        let reports = Mutex<[ImportProgress]>([])
        let outcomes: [ImportFileOutcome]
        do {
            // A scope of its own, so the store is closed before any copy.
            let library = try ActivityLibrary(root: root)
            outcomes = await library.importFiles(
                fixtures.map { ImportFile(url: $0.url()) },
                at: firstImport,
                progress: { report in reports.withLock { $0.append(report) } }
            )
        }
        return Template(
            root: root,
            outcomes: Dictionary(uniqueKeysWithValues: zip(fixtures, outcomes)),
            progress: reports.withLock { $0 }
        )
    }

    private static let templateRoot = Mutex<String>("")

    /// The template, and what importing the four fixtures into it reported.
    static func imported() async throws -> Template {
        try await template.value
    }
}

/// One row of the table in `Fixtures/README.md`, with the start each file
/// states. None of it comes from running this package: the README gives the
/// figures, and the start and offset were read with Ingest's decoder.
struct FixtureFacts: Sendable, CustomTestStringConvertible {
    var fixture: Fixtures.FIT
    var sport: Sport
    var isIndoor: Bool
    var isVirtual: Bool
    /// The "Elapsed" column, seconds, printed to 0.1 s.
    var elapsed: Double
    /// The "Timer" column, seconds, printed to 0.1 s.
    var timer: Double
    /// The "Distance" column, kilometres, printed to 0.01 km.
    var distanceKilometres: Double
    /// The "Records" column.
    var records: Int
    /// The session's start, in seconds since 1970.
    var start: TimeInterval
    /// Seconds east of UTC, or nil where the file states none.
    var utcOffset: Int?
    /// The title the feed rules give: the part of the day that holds the
    /// start on the activity's own clock, then the sport.
    var title: String
    /// The kind of headline the feed rules give the sport.
    var headlineKind: String

    var testDescription: String { fixture.rawValue }

    /// Four hours west of UTC.
    private static let edt = -14_400

    static let all = [
        // 26 August 2026, 12:30:41 UTC, which is 08:30 on its own clock: morning.
        FixtureFacts(
            fixture: .outdoorRide, sport: .cycling, isIndoor: false, isVirtual: false,
            elapsed: 5755.7, timer: 5335.7, distanceKilometres: 37.53, records: 5347,
            start: 1_787_747_441, utcOffset: edt, title: "Morning ride", headlineKind: "averagePower"
        ),
        // 30 October 2026, 14:43:25 UTC. Zwift states no offset, so the title
        // has no time of day. A virtual ride is ridden indoors, so Ingest
        // marks it as both.
        FixtureFacts(
            fixture: .zwiftRide, sport: .cycling, isIndoor: true, isVirtual: true,
            elapsed: 2408.0, timer: 2409.0, distanceKilometres: 18.74, records: 2409,
            start: 1_793_371_405, utcOffset: nil, title: "Virtual ride", headlineKind: "averagePower"
        ),
        // 24 October 2026, 01:00:50 UTC, which is 21:00 the evening before on
        // its own clock: the first hour of the night.
        FixtureFacts(
            fixture: .walk, sport: .walking, isIndoor: false, isVirtual: false,
            elapsed: 2492.7, timer: 2490.3, distanceKilometres: 3.27, records: 2492,
            start: 1_792_803_650, utcOffset: edt, title: "Night walk", headlineKind: "averagePace"
        ),
        // 3 October 2026, 16:52:14 UTC, which is 12:52 on its own clock: afternoon.
        FixtureFacts(
            fixture: .walkPitlane, sport: .walking, isIndoor: false, isVirtual: false,
            elapsed: 36141.7, timer: 27034.1, distanceKilometres: 17.91, records: 27039,
            start: 1_791_046_334, utcOffset: edt, title: "Afternoon walk", headlineKind: "averagePace"
        ),
    ]

    static func of(_ fixture: Fixtures.FIT) throws -> FixtureFacts {
        try #require(all.first { $0.fixture == fixture })
    }

    /// The fixtures as the feed lists them: newest start first.
    static let newestFirst: [Fixtures.FIT] = [.zwiftRide, .walk, .walkPitlane, .outdoorRide]
}

/// Average power as the spec defines it, worked out here from a stream:
/// "sum of power divided by the number of seconds that have power; zeros
/// included".
func averagePower(of stream: AnalysisStream) -> Double? {
    let present = (0..<stream.count).compactMap { stream.power[$0] }
    return present.isEmpty ? nil : present.reduce(0, +) / Double(present.count)
}

/// Whether two figures agree to within rounding in the last places.
func close(_ a: Double?, _ b: Double?, relative: Double = 1e-9) -> Bool {
    guard let a, let b else { return false }
    return abs(a - b) <= relative * max(abs(a), abs(b), 1)
}

/// A profile with one threshold power in effect long before every fixture.
func profile(thresholdPower watts: Double = 250, maxHeartRate: Double? = 190) -> AthleteProfile {
    AthleteProfile(
        thresholdPowerHistory: [.init(effectiveFrom: Date(timeIntervalSince1970: 0), watts: watts)],
        maxHeartRate: maxHeartRate
    )
}
