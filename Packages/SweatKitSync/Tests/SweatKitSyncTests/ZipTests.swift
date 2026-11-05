import Foundation
@testable import SweatKitSync
import Testing

@Suite struct ZipTests {
    let note = Data("A short note, stored as is.".utf8)
    /// Repetitive, so deflate shrinks it well below its size.
    let fit = Data((0..<6000).map { UInt8(truncatingIfNeeded: $0 % 37) })

    var twoFileZip: Data {
        makeZip([
            ZipItem(name: "notes.txt", data: note, method: .stored),
            ZipItem(name: "123_ACTIVITY.fit", data: fit, method: .deflated),
        ])
    }

    @Test func readsAStoredAndADeflatedEntry() throws {
        let archive = try ZipArchive(twoFileZip)
        #expect(archive.entries.map(\.name) == ["notes.txt", "123_ACTIVITY.fit"])
        #expect(archive.entries.map(\.method) == [0, 8])
        #expect(archive.entries[1].compressedSize < fit.count)
        #expect(try archive.contents(of: archive.entries[0]) == note)
        #expect(try archive.contents(of: archive.entries[1]) == fit)
    }

    @Test func theOriginalIsTheOneFile() throws {
        let single = makeZip([ZipItem(name: "9_ACTIVITY.fit", data: fit, method: .deflated)])
        #expect(try GarminOriginal.extract(from: single) == fit)
    }

    @Test func amongSeveralFilesTheOriginalIsTheFITFile() throws {
        #expect(try GarminOriginal.extract(from: twoFileZip) == fit)
        let twoFITs = makeZip([
            ZipItem(name: "a.fit", data: fit, method: .stored),
            ZipItem(name: "b.fit", data: fit, method: .stored),
        ])
        #expect(throws: ZipError.noSingleOriginal(files: 2)) { try GarminOriginal.extract(from: twoFITs) }
        #expect(throws: ZipError.noSingleOriginal(files: 0)) { try GarminOriginal.extract(from: makeZip([])) }
    }

    @Test func anUnzippedFITFileIsTakenAsTheOriginal() throws {
        var header = [UInt8](repeating: 0, count: 14)
        header[0] = 14
        header.replaceSubrange(8..<12, with: Array(".FIT".utf8))
        let raw = Data(header) + fit
        #expect(try GarminOriginal.extract(from: raw) == raw)
    }

    @Test func aDamagedZipIsRefused() throws {
        let zip = twoFileZip

        // Not a zip at all: an error page.
        #expect(throws: ZipError.notAZip) { try ZipArchive(Data("<html>oops</html>".utf8)) }

        // Cut short: the end record is gone.
        #expect(throws: ZipError.truncated) { try ZipArchive(zip.prefix(zip.count - 40)) }

        // One byte of the stored entry flipped: its CRC-32 no longer matches.
        var flipped = [UInt8](zip)
        let storedDataStart = 30 + "notes.txt".utf8.count
        flipped[storedDataStart] ^= 0xFF
        let archive = try ZipArchive(Data(flipped))
        #expect(throws: ZipError.checksumMismatch("notes.txt")) { try archive.contents(of: archive.entries[0]) }

        // The deflated stream overwritten with junk: it cannot be inflated to
        // its stated size, or inflates to the wrong bytes.
        var junk = [UInt8](zip)
        let deflatedStart = storedDataStart + note.count + 30 + "123_ACTIVITY.fit".utf8.count
        for offset in deflatedStart..<(deflatedStart + 40) { junk[offset] = 0xFF }
        let damaged = try ZipArchive(Data(junk))
        #expect(throws: ZipError.self) { try damaged.contents(of: damaged.entries[1]) }
        #expect(throws: ZipError.self) { try GarminOriginal.extract(from: Data(junk)) }
    }

    @Test func crc32MatchesTheStandardCheckValue() {
        // The CRC-32 of "123456789" is 0xCBF43926 in every reference.
        #expect(CRC32.checksum(Array("123456789".utf8)) == 0xCBF4_3926)
    }
}
