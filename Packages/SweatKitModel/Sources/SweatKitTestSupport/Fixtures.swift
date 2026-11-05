import Foundation

/// The shared fixture files in `Fixtures/` at the repository root.
public enum Fixtures {
    /// The real FIT files every package tests against.
    public enum FIT: String, CaseIterable, Sendable {
        /// An outdoor ride from a Garmin bike computer.
        case outdoorRide = "outdoor-ride"
        /// A Zwift ride, with made-up GPS coordinates.
        case zwiftRide = "zwift-ride"
        /// An outdoor walk in the open.
        case walk = "walk"
        /// A walk along a pit lane, with the GPS drift of walking beside buildings.
        case walkPitlane = "walk-pitlane"

        public func url(from filePath: String = #filePath) -> URL {
            Fixtures.root(from: filePath).appending(path: "fit/\(rawValue).fit")
        }

        public func data(from filePath: String = #filePath) throws -> Data {
            try Data(contentsOf: url(from: filePath))
        }
    }

    /// The `Fixtures/` directory, found by walking up from the calling file.
    public static func root(from filePath: String = #filePath) -> URL {
        var directory = URL(filePath: filePath).deletingLastPathComponent()
        while directory.path != "/" {
            let candidate = directory.appending(path: "Fixtures", directoryHint: .isDirectory)
            if FileManager.default.fileExists(atPath: candidate.appending(path: "fit").path) {
                return candidate
            }
            directory = directory.deletingLastPathComponent()
        }
        preconditionFailure("No Fixtures directory above \(filePath)")
    }
}
