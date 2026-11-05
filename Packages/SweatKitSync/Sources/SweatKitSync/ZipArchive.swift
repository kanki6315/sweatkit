import Compression
import Foundation

/// Reads a zip archive held in memory, with nothing beyond the system's
/// Compression framework.
///
/// Handles what Garmin serves: single-disk archives with stored or deflated
/// entries. The central directory is authoritative for names and sizes, so
/// entries written with a trailing data descriptor read correctly. Zip64,
/// encryption, spanning and other compression methods are refused with a
/// typed error rather than guessed at. Every entry's CRC-32 and size are
/// checked when it is read.
public struct ZipArchive: Sendable {
    public struct Entry: Sendable, Hashable {
        public var name: String
        /// 0 is stored, 8 is deflated.
        public var method: UInt16
        public var flags: UInt16
        public var crc32: UInt32
        public var compressedSize: Int
        public var uncompressedSize: Int
        var localHeaderOffset: Int

        /// A directory entry, which holds no data.
        public var isDirectory: Bool { name.hasSuffix("/") }
    }

    /// Entries in central-directory order.
    public let entries: [Entry]
    private let bytes: [UInt8]

    /// The largest entry read, to refuse a zip bomb. A FIT file of a very long
    /// ride is tens of megabytes.
    public static let maximumEntrySize = 512 * 1024 * 1024

    public init(_ data: Data) throws(ZipError) {
        let bytes = [UInt8](data)
        self.bytes = bytes
        guard bytes.count >= 4, bytes.u32(at: 0) == Signature.localHeader || bytes.u32(at: 0) == Signature.endOfCentralDirectory else {
            throw .notAZip
        }

        // The end-of-central-directory record is the last 22 bytes plus a
        // comment of up to 65,535 bytes.
        let lowest = max(0, bytes.count - 22 - 0xFFFF)
        var end: Int?
        var position = bytes.count - 22
        while position >= lowest {
            if bytes.u32(at: position) == Signature.endOfCentralDirectory { end = position; break }
            position -= 1
        }
        guard let end else { throw .truncated }

        let disk = bytes.u16(at: end + 4)
        let directoryDisk = bytes.u16(at: end + 6)
        let count = Int(bytes.u16(at: end + 10))
        let directorySize = Int(bytes.u32(at: end + 12))
        let directoryOffset = Int(bytes.u32(at: end + 16))
        if count == 0xFFFF || directorySize == 0xFFFF_FFFF || directoryOffset == 0xFFFF_FFFF { throw .unsupported(.zip64) }
        guard disk == 0, directoryDisk == 0 else { throw .unsupported(.multipleDisks) }
        guard directoryOffset + directorySize <= end else { throw .truncated }

        var entries: [Entry] = []
        var cursor = directoryOffset
        for _ in 0..<count {
            guard cursor + 46 <= end, bytes.u32(at: cursor) == Signature.centralHeader else { throw .corrupt }
            let nameLength = Int(bytes.u16(at: cursor + 28))
            let extraLength = Int(bytes.u16(at: cursor + 30))
            let commentLength = Int(bytes.u16(at: cursor + 32))
            let next = cursor + 46 + nameLength + extraLength + commentLength
            guard next <= end else { throw .corrupt }
            let nameBytes = bytes[(cursor + 46)..<(cursor + 46 + nameLength)]
            let entry = Entry(
                name: String(decoding: nameBytes, as: UTF8.self),
                method: bytes.u16(at: cursor + 10),
                flags: bytes.u16(at: cursor + 8),
                crc32: bytes.u32(at: cursor + 16),
                compressedSize: Int(bytes.u32(at: cursor + 20)),
                uncompressedSize: Int(bytes.u32(at: cursor + 24)),
                localHeaderOffset: Int(bytes.u32(at: cursor + 42))
            )
            if entry.compressedSize == 0xFFFF_FFFF || entry.uncompressedSize == 0xFFFF_FFFF || entry.localHeaderOffset == 0xFFFF_FFFF {
                throw .unsupported(.zip64)
            }
            entries.append(entry)
            cursor = next
        }
        self.entries = entries
    }

    /// The entries that hold data.
    public var files: [Entry] { entries.filter { !$0.isDirectory } }

    /// One entry's contents, decompressed and checked.
    public func contents(of entry: Entry) throws(ZipError) -> Data {
        if entry.flags & 0x0001 != 0 { throw .unsupported(.encrypted) }
        guard entry.uncompressedSize <= Self.maximumEntrySize else { throw .unsupported(.tooLarge) }

        let header = entry.localHeaderOffset
        guard header + 30 <= bytes.count, bytes.u32(at: header) == Signature.localHeader else { throw .corrupt }
        let start = header + 30 + Int(bytes.u16(at: header + 26)) + Int(bytes.u16(at: header + 28))
        guard start + entry.compressedSize <= bytes.count else { throw .truncated }
        let stored = bytes[start..<(start + entry.compressedSize)]

        let output: [UInt8]
        switch entry.method {
        case 0:
            guard entry.compressedSize == entry.uncompressedSize else { throw .corrupt }
            output = Array(stored)
        case 8:
            output = try Self.inflate(Array(stored), size: entry.uncompressedSize)
        default:
            throw .unsupported(.method(entry.method))
        }
        guard CRC32.checksum(output) == entry.crc32 else { throw .checksumMismatch(entry.name) }
        return Data(output)
    }

    /// Raw DEFLATE (RFC 1951), which is what Compression calls `COMPRESSION_ZLIB`.
    private static func inflate(_ input: [UInt8], size: Int) throws(ZipError) -> [UInt8] {
        guard size > 0 else { return [] }
        guard !input.isEmpty else { throw .corrupt }
        // One spare byte shows whether the stream holds more than it claims.
        var output = [UInt8](repeating: 0, count: size + 1)
        let written = output.withUnsafeMutableBufferPointer { destination in
            input.withUnsafeBufferPointer { source in
                compression_decode_buffer(destination.baseAddress!, destination.count, source.baseAddress!, source.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written == size else { throw .corrupt }
        output.removeLast()
        return output
    }

    enum Signature {
        static let localHeader: UInt32 = 0x0403_4B50
        static let centralHeader: UInt32 = 0x0201_4B50
        static let endOfCentralDirectory: UInt32 = 0x0605_4B50
    }
}

public enum ZipError: Error, Sendable, Equatable {
    public enum Unsupported: Sendable, Equatable {
        case zip64
        case multipleDisks
        case encrypted
        case method(UInt16)
        case tooLarge
    }

    /// The bytes do not start like a zip.
    case notAZip
    /// The archive ends before its directory or an entry's data.
    case truncated
    /// A header or compressed stream is malformed.
    case corrupt
    /// An entry's contents do not match its CRC-32.
    case checksumMismatch(String)
    case unsupported(Unsupported)
    /// A Garmin download holding no file, or several and not exactly one FIT file.
    case noSingleOriginal(files: Int)
}

/// CRC-32 as zip uses it: the reflected IEEE polynomial.
enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 { value = value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1 }
        return value
    }

    static func checksum<C: Collection>(_ bytes: C) -> UInt32 where C.Element == UInt8 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFF_FFFF
    }
}

private extension [UInt8] {
    func u16(at offset: Int) -> UInt16 {
        guard offset >= 0, offset + 2 <= count else { return 0 }
        return UInt16(self[offset]) | UInt16(self[offset + 1]) << 8
    }

    func u32(at offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= count else { return 0 }
        return UInt32(self[offset]) | UInt32(self[offset + 1]) << 8 | UInt32(self[offset + 2]) << 16 | UInt32(self[offset + 3]) << 24
    }
}
