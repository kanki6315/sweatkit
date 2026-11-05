import CryptoKit
import Foundation

/// Where a source record came from.
public enum SourceKind: String, Codable, Sendable, CaseIterable {
    case garmin
    case healthKit
    case file
}

/// The stable identity of one source record.
///
/// - Garmin: the activity ID.
/// - HealthKit: the workout's UUID.
/// - Imported file: the hash of the file's bytes, because there is no external ID.
public struct SourceIdentity: Hashable, Codable, Sendable, CustomStringConvertible {
    public let source: SourceKind
    public let externalID: String

    public init(source: SourceKind, externalID: String) {
        self.source = source
        self.externalID = externalID
    }

    /// The identity of an imported file with these bytes.
    public init(fileContents: Data) {
        self.init(source: .file, externalID: ContentHash(of: fileContents).hex)
    }

    /// Canonical form, such as `garmin:24172582403`. Record names derive from it.
    public var description: String { "\(source.rawValue):\(externalID)" }
}

extension SourceIdentity: Comparable {
    /// A total order that is the same on every device. An activity's ID is the
    /// lowest identity among its members.
    public static func < (lhs: SourceIdentity, rhs: SourceIdentity) -> Bool {
        (lhs.source.rawValue, lhs.externalID) < (rhs.source.rawValue, rhs.externalID)
    }
}

/// A SHA-256 content hash. Identifies revisions of a source record and the
/// inputs of derived results.
public struct ContentHash: Hashable, Codable, Sendable, CustomStringConvertible {
    public let hex: String

    public init(hex: String) {
        self.hex = hex
    }

    public init(of data: Data) {
        self.hex = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public var description: String { hex }
}
