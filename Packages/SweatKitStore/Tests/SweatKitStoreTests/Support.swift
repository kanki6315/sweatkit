import Foundation
import SweatKitModel
import SweatKitStore
import Testing

/// A library in its own temporary directory, removed when the test ends.
final class TemporaryLibrary {
    let root: URL

    init() {
        root = FileManager.default.temporaryDirectory
            .appending(path: "SweatKitStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    func open() throws -> LibraryStore {
        try LibraryStore(root: root)
    }

    var originalsDirectory: URL { root.appending(path: "Originals", directoryHint: .isDirectory) }
    var streamsDirectory: URL { root.appending(path: "Streams", directoryHint: .isDirectory) }

    func analysisFile(_ revision: ContentHash) -> URL {
        streamsDirectory.appending(path: "\(revision.hex).analysis")
    }

    func recordedFile(_ revision: ContentHash) -> URL {
        streamsDirectory.appending(path: "\(revision.hex).recorded")
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }
}

let secondsPerDay: TimeInterval = 86_400

/// A fixed reference date, so no test depends on the clock.
let referenceDate = Date(timeIntervalSince1970: 1_780_000_000)

func day(_ offset: Double) -> Date {
    referenceDate.addingTimeInterval(offset * secondsPerDay)
}

func garmin(_ id: Int) -> SourceIdentity {
    SourceIdentity(source: .garmin, externalID: String(id))
}

/// Stores a Garmin record whose original is a few distinct bytes, and returns
/// its current revision.
@discardableResult
func storeGarminRecord(_ id: Int, in store: LibraryStore, bytes: String? = nil) async throws -> ContentHash {
    let outcome = try await store.importOriginal(Data((bytes ?? "garmin original \(id)").utf8), as: garmin(id), at: referenceDate)
    return outcome.record.currentRevision
}

/// Records a measurement as a test attachment. Run
/// `swift test --attachments-path <dir>` to keep them.
func recordMeasurement(_ text: String, named name: String) {
    Attachment.record(text, named: name)
}

func seconds(_ duration: Duration) -> Double {
    let components = duration.components
    return Double(components.seconds) + Double(components.attoseconds) / 1e18
}
