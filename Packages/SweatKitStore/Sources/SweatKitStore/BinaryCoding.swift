import Foundation

#if !_endian(little)
#error("Stream files are little-endian and arrays are copied in native order.")
#endif

/// A stream file's contents are malformed.
struct MalformedStreamFile: Error {}

/// Appends little-endian scalars and arrays to a buffer.
struct BinaryWriter {
    private(set) var data = Data()

    init(capacity: Int = 0) {
        data.reserveCapacity(capacity)
    }

    mutating func write<T: FixedWidthInteger>(_ value: T) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    mutating func write(_ value: Double) {
        write(value.bitPattern)
    }

    mutating func write(_ value: Bool) {
        write(UInt8(value ? 1 : 0))
    }

    mutating func write(_ value: Date) {
        write(value.timeIntervalSinceReferenceDate)
    }

    mutating func write(_ value: String) {
        let bytes = Data(value.utf8)
        write(UInt32(bytes.count))
        data.append(bytes)
    }

    mutating func write(_ value: Double?) {
        write(value != nil)
        if let value { write(value) }
    }

    mutating func write(_ value: Date?) {
        write(value?.timeIntervalSinceReferenceDate)
    }

    /// Writes the elements without a count.
    mutating func writeElements(_ values: [Double]) {
        values.withUnsafeBufferPointer { data.append($0) }
    }

    /// Writes the elements without a count.
    mutating func writeByteElements(_ values: [UInt8]) {
        data.append(contentsOf: values)
    }

    mutating func writeBytes(_ bytes: Data) {
        data.append(bytes)
    }
}

/// Reads what `BinaryWriter` wrote, throwing on any read past the end.
struct BinaryReader {
    private let data: Data
    private var offset: Int

    init(_ data: Data) {
        self.data = data
        self.offset = data.startIndex
    }

    var isAtEnd: Bool { offset == data.endIndex }

    private mutating func take(_ count: Int) throws -> Data {
        guard count >= 0, data.endIndex - offset >= count else { throw MalformedStreamFile() }
        let slice = data[offset..<(offset + count)]
        offset += count
        return slice
    }

    mutating func read<T: FixedWidthInteger>(_: T.Type = T.self) throws -> T {
        let bytes = try take(MemoryLayout<T>.size)
        var value = T.zero
        withUnsafeMutableBytes(of: &value) { $0.copyBytes(from: bytes) }
        return T(littleEndian: value)
    }

    mutating func readDouble() throws -> Double {
        Double(bitPattern: try read(UInt64.self))
    }

    mutating func readBool() throws -> Bool {
        switch try read(UInt8.self) {
        case 0: false
        case 1: true
        default: throw MalformedStreamFile()
        }
    }

    mutating func readDate() throws -> Date {
        Date(timeIntervalSinceReferenceDate: try readDouble())
    }

    mutating func readString() throws -> String {
        let count = Int(try read(UInt32.self))
        guard let string = String(data: try take(count), encoding: .utf8) else { throw MalformedStreamFile() }
        return string
    }

    mutating func readOptionalDouble() throws -> Double? {
        try readBool() ? try readDouble() : nil
    }

    mutating func readOptionalDate() throws -> Date? {
        try readOptionalDouble().map(Date.init(timeIntervalSinceReferenceDate:))
    }

    /// A count, checked against what is left so a corrupt count cannot ask
    /// for more memory than the file holds.
    mutating func readCount(elementSize: Int) throws -> Int {
        let count = try read(UInt64.self)
        guard elementSize > 0, count <= UInt64(data.endIndex - offset) / UInt64(elementSize) else {
            throw MalformedStreamFile()
        }
        return Int(count)
    }

    mutating func readDoubles(_ count: Int) throws -> [Double] {
        let bytes = try take(count * MemoryLayout<Double>.size)
        return [Double](unsafeUninitializedCapacity: count) { buffer, initialized in
            bytes.withUnsafeBytes { source in
                UnsafeMutableRawBufferPointer(buffer).copyMemory(from: source)
            }
            initialized = count
        }
    }

    mutating func readBytes(_ count: Int) throws -> [UInt8] {
        [UInt8](try take(count))
    }

    mutating func readRemaining() -> Data {
        let rest = data[offset...]
        offset = data.endIndex
        return rest
    }
}
