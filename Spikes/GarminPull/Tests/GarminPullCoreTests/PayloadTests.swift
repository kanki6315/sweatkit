import Foundation
@testable import GarminPullCore
import Testing

/// The repository's shared fixtures, found from this file's location.
func fixture(_ name: String) throws -> Data {
    let root = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    return try Data(contentsOf: root.appending(path: "Fixtures/fit/\(name)"))
}

@Suite struct PayloadTests {
    @Test func sniffsZipFitAndOther() throws {
        #expect(PayloadKind(sniffing: try fixture("zwift-ride.fit")) == .fit)
        #expect(PayloadKind(sniffing: Data([0x50, 0x4B, 0x03, 0x04, 0x14, 0x00])) == .zip)
        #expect(PayloadKind(sniffing: Data(#"{"error":"x"}"#.utf8)) == .other)
        #expect(PayloadKind(sniffing: Data()) == .other)
    }

    /// Counts from Fixtures/README.md: 10 of the outdoor ride's records lack power.
    @Test func reportsTheOutdoorRideChannels() throws {
        let report = try FITChannelReport(fit: fixture("outdoor-ride.fit"))
        #expect(report.integrityOK)
        #expect(report.records == 5347)
        #expect(report.withPower == 5337)
        #expect(report.withHeartRate == 5347)
        #expect(report.withPosition == 5347)
        #expect(report.sport == "cycling")
        #expect(report.subSport == "road")
        #expect(report.differences(from: report).isEmpty)
    }

    @Test func namesEveryChannelThatDiffers() throws {
        let reference = try FITChannelReport(fit: fixture("outdoor-ride.fit"))
        var stripped = reference
        stripped.withPower = 0
        stripped.withPosition = 0
        #expect(stripped.differences(from: reference) == [
            "power: download 0, reference 5337",
            "position: download 0, reference 5347",
        ])
    }

    /// The download is documented as a zip. This zips a fixture the way Garmin's
    /// downloads are expected to look and checks the FIT comes back byte for byte.
    @Test func unzipsAFITByteForByte() throws {
        let original = try fixture("zwift-ride.fit")
        let work = FileManager.default.temporaryDirectory.appending(path: "garminpull-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        try original.write(to: work.appending(path: "24906063494_ACTIVITY.fit"))

        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", work.appending(path: "24906063494_ACTIVITY.fit").path(), work.appending(path: "a.zip").path()]
        try process.run()
        process.waitUntilExit()

        let zip = try Data(contentsOf: work.appending(path: "a.zip"))
        #expect(PayloadKind(sniffing: zip) == .zip)
        let entries = try unzipEntries(zip)
        #expect(entries.map(\.name) == ["24906063494_ACTIVITY.fit"])
        #expect(sha256Hex(entries[0].data) == sha256Hex(original))
    }
}
