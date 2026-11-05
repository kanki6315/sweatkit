import CryptoKit
import FITSwiftSDK
import Foundation

public enum PayloadKind: String, Sendable {
    case zip, fit, other

    /// A zip starts `PK\u{3}\u{4}`; a FIT file has `.FIT` at bytes 8 to 11.
    public init(sniffing data: Data) {
        let bytes = [UInt8](data.prefix(12))
        if bytes.starts(with: [0x50, 0x4B, 0x03, 0x04]) {
            self = .zip
        } else if bytes.count >= 12, bytes[8...11].elementsEqual(Array(".FIT".utf8)) {
            self = .fit
        } else {
            self = .other
        }
    }
}

public func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

/// Extracts a zip with the system `ditto` and returns each file's name and bytes.
/// The download is documented as a zip; this avoids adding a zip dependency.
public func unzipEntries(_ zip: Data) throws -> [(name: String, data: Data)] {
    let fileManager = FileManager.default
    let work = fileManager.temporaryDirectory.appending(path: "garminpull-\(UUID().uuidString)")
    let source = work.appending(path: "download.zip")
    let target = work.appending(path: "contents")
    try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: work) }
    try zip.write(to: source)

    let process = Process()
    process.executableURL = URL(filePath: "/usr/bin/ditto")
    process.arguments = ["-x", "-k", source.path(), target.path()]
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw UnzipError(status: process.terminationStatus) }

    let root = target.resolvingSymlinksInPath().path()
    let enumerator = fileManager.enumerator(at: target, includingPropertiesForKeys: [.isRegularFileKey])
    var entries: [(String, Data)] = []
    while let url = enumerator?.nextObject() as? URL {
        guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
        let name = String(url.resolvingSymlinksInPath().path().dropFirst(root.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        entries.append((name, try Data(contentsOf: url)))
    }
    return entries.sorted { $0.0 < $1.0 }
}

public struct UnzipError: Error, CustomStringConvertible {
    public var status: Int32
    public var description: String { "ditto could not extract the zip (exit \(status))." }
}

/// The channel counts the first M0 gate compares.
public struct FITChannelReport: Sendable, Equatable, CustomStringConvertible {
    public var sha256: String
    public var bytes: Int
    public var integrityOK: Bool
    public var sport: String
    public var subSport: String
    public var manufacturer: String
    public var records: Int
    public var withPower: Int
    public var withHeartRate: Int
    public var withPosition: Int
    /// Consecutive records exactly one second apart, the "per-second" check.
    public var oneSecondSteps: Int

    public init(fit data: Data) throws {
        sha256 = sha256Hex(data)
        bytes = data.count
        integrityOK = (try? Decoder(stream: FITSwiftSDK.InputStream(data: data)).checkIntegrity()) ?? false

        let decoder = Decoder(stream: FITSwiftSDK.InputStream(data: data))
        let listener = FitListener()
        decoder.addMesgListener(listener)
        try decoder.read()
        let messages = listener.fitMessages

        let session = messages.sessionMesgs.first
        sport = session?.getSport().map { "\($0)" } ?? "unknown"
        subSport = session?.getSubSport().map { "\($0)" } ?? "unknown"
        manufacturer = messages.fileIdMesgs.first?.getManufacturer().map { "\($0)" } ?? "unknown"

        let recordMesgs = messages.recordMesgs
        records = recordMesgs.count
        withPower = recordMesgs.count { $0.getPower() != nil }
        withHeartRate = recordMesgs.count { $0.getHeartRate() != nil }
        withPosition = recordMesgs.count { $0.getPositionLat() != nil && $0.getPositionLong() != nil }
        let seconds = recordMesgs.compactMap { $0.getTimestamp()?.timestamp }
        oneSecondSteps = zip(seconds, seconds.dropFirst()).count { $1 &- $0 == 1 }
    }

    public var description: String {
        """
        sha256 \(sha256)  bytes \(bytes)  integrity \(integrityOK ? "ok" : "FAILED")
        sport \(sport)/\(subSport)  manufacturer \(manufacturer)
        records \(records)  power \(withPower)  heart rate \(withHeartRate)  position \(withPosition)  1-s steps \(oneSecondSteps)
        """
    }

    /// Lines naming each channel whose count differs from `reference`.
    public func differences(from reference: FITChannelReport) -> [String] {
        let pairs: [(String, Int, Int)] = [
            ("records", records, reference.records),
            ("power", withPower, reference.withPower),
            ("heart rate", withHeartRate, reference.withHeartRate),
            ("position", withPosition, reference.withPosition),
            ("1-s steps", oneSecondSteps, reference.oneSecondSteps),
        ]
        return pairs.filter { $0.1 != $0.2 }.map { "\($0.0): download \($0.1), reference \($0.2)" }
    }
}
