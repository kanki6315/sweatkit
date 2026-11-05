import Foundation
import SweatKitIngest
import SweatKitTestSupport
import Testing

/// Milestone M1: a corrupt or truncated file is rejected with a clear
/// message. Each case damages a real fixture in memory. The walk is used
/// because it is the smallest.
///
/// Every fixture is one FIT file with a 14-byte header, a data section whose
/// size the header states, and a 2-byte checksum, so removing any bytes from
/// the end leaves a file shorter than its header says.
@Suite struct FITRejectionTests {
    private func walk() throws -> Data {
        try Fixtures.FIT.walk.data()
    }

    // MARK: Not FIT

    @Test func emptyDataIsNotFIT() {
        #expect(throws: FITDecodeError.notFIT) { try FITActivityDecoder.decode(Data()) }
    }

    @Test func textIsNotFIT() {
        let data = Data("This is a GPX file, or a note, or anything but FIT.".utf8)
        #expect(throws: FITDecodeError.notFIT) { try FITActivityDecoder.decode(data) }
    }

    /// Garmin delivers each original inside a zip. Unzipping is not this
    /// package's job, so a zip handed over as it came is not FIT.
    @Test func zipIsNotFIT() {
        // "PK\u{3}\u{4}", the zip local-file signature, then padding.
        let data = Data([0x50, 0x4B, 0x03, 0x04] + [UInt8](repeating: 0, count: 60))
        #expect(throws: FITDecodeError.notFIT) { try FITActivityDecoder.decode(data) }
    }

    @Test func fixtureWithItsSignatureOverwrittenIsNotFIT() throws {
        var data = try walk()
        // Bytes 8 to 11 of the header are ".FIT".
        #expect(data[8..<12] == Data(".FIT".utf8))
        data.replaceSubrange(8..<12, with: Data("XXXX".utf8))
        #expect(throws: FITDecodeError.notFIT) { try FITActivityDecoder.decode(data) }
    }

    @Test func fixtureWithAnImpossibleHeaderSizeIsNotFIT() throws {
        var data = try walk()
        // Byte 0 is the header size, which is 12 or 14 in every FIT file.
        #expect(data[0] == 14)
        data[0] = 99
        #expect(throws: FITDecodeError.notFIT) { try FITActivityDecoder.decode(data) }
    }

    // MARK: Truncated

    @Test func fixtureCutShortIsTruncated() throws {
        let data = try walk()
        // Cut to the header alone, to a few records, to half, and by one byte.
        for length in [14, 100, data.count / 2, data.count - 1] {
            #expect(throws: FITDecodeError.truncated, "cut to \(length) bytes") {
                try FITActivityDecoder.decode(data.prefix(length))
            }
        }
    }

    /// `prefix` keeps the original's indices only by accident of starting at
    /// 0. A slice that starts elsewhere must decode the same as a fresh copy.
    @Test func truncatedSliceWithShiftedIndicesIsStillTruncated() throws {
        let data = try walk()
        let padded = Data([0, 0, 0]) + data
        let slice = padded[3..<(3 + data.count / 2)]
        #expect(throws: FITDecodeError.truncated) { try FITActivityDecoder.decode(slice) }
    }

    // MARK: Corrupt

    @Test func fixtureWithADamagedByteIsCorrupt() throws {
        let data = try walk()
        // The first data byte, the middle of the file, the last data byte,
        // and the last byte of the file's checksum. The length is unchanged,
        // so each is caught by the checksum, not by the length.
        for offset in [14, data.count / 2, data.count - 3, data.count - 1] {
            var damaged = data
            damaged[offset] ^= 0xFF
            #expect(throws: FITDecodeError.corrupt, "byte \(offset) inverted") {
                try FITActivityDecoder.decode(damaged)
            }
        }
    }

    @Test func fixtureWithADamagedHeaderChecksumIsCorrupt() throws {
        var data = try walk()
        // Bytes 12 and 13 are the header's own checksum.
        data[12] ^= 0xFF
        data[13] ^= 0xFF
        #expect(throws: FITDecodeError.corrupt) { try FITActivityDecoder.decode(data) }
    }

    @Test func fixtureWithAStretchOfZeroedBytesIsCorrupt() throws {
        var data = try walk()
        // A bad block in storage: 512 bytes of zeros in the middle.
        let range = (data.count / 2)..<(data.count / 2 + 512)
        data.replaceSubrange(range, with: Data(count: 512))
        #expect(throws: FITDecodeError.corrupt) { try FITActivityDecoder.decode(data) }
    }

    // MARK: Messages

    @Test func everyRejectionHasItsOwnClearMessage() {
        let messages = FITDecodeError.allCases.map(\.localizedDescription)
        #expect(messages.allSatisfy { !$0.isEmpty })
        #expect(Set(messages).count == FITDecodeError.allCases.count)
        // The message is the written one, not the system's stand-in.
        for error in FITDecodeError.allCases {
            #expect(error.errorDescription == error.localizedDescription)
            #expect(!error.localizedDescription.contains("FITDecodeError"))
        }
    }

    /// The untouched fixture decodes, so the rejections above are caused by
    /// the damage and nothing else.
    @Test func untouchedFixtureIsAccepted() throws {
        #expect(throws: Never.self) { try FITActivityDecoder.decode(try walk()) }
    }
}
