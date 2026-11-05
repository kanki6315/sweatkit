import CryptoKit
import Foundation
import SweatKitModel

/// The stream file format: a small uncompressed header, then a columnar
/// binary body compressed with LZFSE.
///
/// Header, little-endian:
///
/// | Bytes | Field |
/// | --- | --- |
/// | 4 | Magic, `SKST` |
/// | 2 | Format version |
/// | 1 | Content: 1 recorded activity, 2 analysis stream |
/// | 1 | Compression: 1 LZFSE |
/// | 8 | Producer version: the decoder version or the stream rules version |
/// | 8 | Body length before compression |
/// | 32 | SHA-256 of the body before compression |
///
/// The body is columnar: each channel is written as one run of values and
/// one run of quality or presence bytes, which LZFSE compresses well because
/// neighbouring values are close and missing runs are zeros. Values are
/// 64-bit floats, so a stream reads back exactly equal. The digest catches
/// truncation and corruption that decompression lets through.
enum StreamFileFormat {
    static let magic = Data("SKST".utf8)
    static let currentVersion: UInt16 = 2
    static let lzfse: UInt8 = 1
    static let digestLength = 32

    enum Content: UInt8 {
        case recordedActivity = 1
        case analysisStream = 2
    }

    enum ReadFailure: Error {
        case unreadable
        case unsupportedFormat
    }

    /// The order channels are written in. Fixed by the format, not by the
    /// order of `Channel.allCases`.
    static let channelOrder: [Channel] = [
        .latitude, .longitude, .altitude, .distance, .speed,
        .heartRate, .power, .cadence, .temperature, .gradient,
        .runningStrideLength, .runningGroundContactTime, .runningVerticalOscillation,
    ]

    // MARK: Envelope

    static func wrap(_ body: Data, content: Content, producerVersion: Int) throws -> Data {
        let compressed = try (body as NSData).compressed(using: .lzfse) as Data
        var writer = BinaryWriter(capacity: compressed.count + magic.count + digestLength + 24)
        writer.writeBytes(magic)
        writer.write(currentVersion)
        writer.write(content.rawValue)
        writer.write(lzfse)
        writer.write(Int64(producerVersion))
        writer.write(UInt64(body.count))
        writer.writeBytes(Data(SHA256.hash(data: body)))
        writer.writeBytes(compressed)
        return writer.data
    }

    static func unwrap(_ file: Data, content: Content) throws(ReadFailure) -> (producerVersion: Int, body: Data, formatVersion: UInt16) {
        do {
            var reader = BinaryReader(file)
            guard Data(try reader.readBytes(magic.count)) == magic else { throw ReadFailure.unreadable }
            let version = try reader.read(UInt16.self)
            guard version >= 1, version <= currentVersion else { throw ReadFailure.unsupportedFormat }
            guard try reader.read(UInt8.self) == content.rawValue else { throw ReadFailure.unreadable }
            guard try reader.read(UInt8.self) == lzfse else { throw ReadFailure.unsupportedFormat }
            let producerVersion = Int(try reader.read(Int64.self))
            let length = try reader.read(UInt64.self)
            let digest = Data(try reader.readBytes(digestLength))
            let compressed = reader.readRemaining()
            let body = try (compressed as NSData).decompressed(using: .lzfse) as Data
            guard UInt64(body.count) == length, Data(SHA256.hash(data: body)) == digest else {
                throw ReadFailure.unreadable
            }
            return (producerVersion, body, version)
        } catch let failure as ReadFailure {
            throw failure
        } catch {
            throw .unreadable
        }
    }

    // MARK: Analysis stream

    static func encode(_ stream: AnalysisStream) throws -> Data {
        let bytesPerSecond = channelOrder.count * (MemoryLayout<Double>.size + 1)
        var writer = BinaryWriter(capacity: stream.count * bytesPerSecond + 256)
        writer.write(Int64(stream.rulesVersion))
        writer.write(stream.start)
        writer.write(Int64(stream.count))
        switch stream.pauses {
        case .known(let paused):
            writer.write(UInt8(0))
            writer.write(UInt64(paused.count))
            for span in paused {
                writer.write(Int64(span.lowerBound))
                writer.write(Int64(span.upperBound))
            }
        case .unknown(let statedTimerTime):
            writer.write(UInt8(1))
            writer.write(statedTimerTime)
        }
        for channel in channelOrder {
            let series = stream[channel]
            writer.write(UInt64(series.count))
            writer.writeElements(series.values)
            writer.writeByteElements(series.quality.map(\.rawValue))
        }
        return try wrap(writer.data, content: .analysisStream, producerVersion: stream.rulesVersion)
    }

    static func decodeAnalysisStream(_ file: Data) throws(ReadFailure) -> AnalysisStream {
        let envelope = try unwrap(file, content: .analysisStream)
        let body = envelope.body
        do {
            var reader = BinaryReader(body)
            let rulesVersion = Int(try reader.read(Int64.self))
            let start = try reader.readDate()
            let count = Int(try reader.read(Int64.self))
            let pauses: PauseData
            switch try reader.read(UInt8.self) {
            case 0:
                let spanCount = try reader.readCount(elementSize: 2 * MemoryLayout<Int64>.size)
                var spans: [Range<Int>] = []
                spans.reserveCapacity(spanCount)
                for _ in 0..<spanCount {
                    let lower = Int(try reader.read(Int64.self))
                    let upper = Int(try reader.read(Int64.self))
                    guard lower <= upper else { throw MalformedStreamFile() }
                    spans.append(lower..<upper)
                }
                pauses = .known(paused: spans)
            case 1:
                pauses = .unknown(statedTimerTime: try reader.readOptionalDouble())
            default:
                throw MalformedStreamFile()
            }
            var stream = AnalysisStream(rulesVersion: rulesVersion, start: start, count: count, pauses: pauses)
            for channel in (envelope.formatVersion == 1 ? Array(channelOrder.prefix(10)) : channelOrder) {
                let length = try reader.readCount(elementSize: MemoryLayout<Double>.size + 1)
                let values = try reader.readDoubles(length)
                let qualityBytes = try reader.readBytes(length)
                var quality: [SampleQuality] = []
                quality.reserveCapacity(length)
                for byte in qualityBytes {
                    guard let value = SampleQuality(rawValue: byte) else { throw MalformedStreamFile() }
                    quality.append(value)
                }
                stream[channel] = Series(values: values, quality: quality)
            }
            guard reader.isAtEnd else { throw MalformedStreamFile() }
            return stream
        } catch {
            throw .unreadable
        }
    }

    // MARK: Recorded activity

    private static func timerKindCode(_ kind: TimerEvent.Kind) -> UInt8 {
        switch kind {
        case .start: 0
        case .stop: 1
        }
    }

    private static func timerKind(code: UInt8) throws -> TimerEvent.Kind {
        switch code {
        case 0: .start
        case 1: .stop
        default: throw MalformedStreamFile()
        }
    }

    /// The optional channels of a native sample, in the order they are written.
    private static var sampleChannels: [WritableKeyPath<NativeSample, Double?>] {
        [\.altitude, \.distance, \.speed, \.heartRate, \.power, \.cadence, \.temperature, \.runningStrideLength, \.runningGroundContactTime, \.runningVerticalOscillation]
    }

    static func encode(_ activity: RecordedActivity, decoderVersion: Int) throws -> Data {
        let samples = activity.stream.samples
        let bytesPerSample = (sampleChannels.count + 3) * (MemoryLayout<Double>.size + 1)
        var writer = BinaryWriter(capacity: samples.count * bytesPerSample + 1024)
        writer.write(activity.sport.rawValue)
        writer.write(activity.isIndoor)
        writer.write(activity.isVirtual)

        let stated = activity.stated
        writer.write(stated.start)
        writer.write(stated.end)
        writer.write(stated.timerTime)
        writer.write(stated.distance)
        writer.write(stated.ascent)
        writer.write(stated.utcOffset != nil)
        if let offset = stated.utcOffset { writer.write(Int64(offset)) }

        writer.write(UInt64(activity.timerEvents.count))
        for event in activity.timerEvents {
            writer.write(timerKindCode(event.kind))
            writer.write(event.timestamp)
        }
        writer.write(UInt64(activity.laps.count))
        for lap in activity.laps {
            writer.write(lap.start)
            writer.write(lap.end)
        }

        writer.write(UInt64(samples.count))
        writer.writeElements(samples.map(\.timestamp.timeIntervalSinceReferenceDate))
        writer.writeByteElements(samples.map { $0.position == nil ? 0 : 1 })
        let positions = samples.compactMap(\.position)
        writer.writeElements(positions.map(\.latitude))
        writer.writeElements(positions.map(\.longitude))
        for channel in sampleChannels {
            writer.writeByteElements(samples.map { $0[keyPath: channel] == nil ? 0 : 1 })
            writer.writeElements(samples.compactMap { $0[keyPath: channel] })
        }
        return try wrap(writer.data, content: .recordedActivity, producerVersion: decoderVersion)
    }

    static func decodeRecordedActivity(_ file: Data) throws(ReadFailure) -> (decoderVersion: Int, activity: RecordedActivity) {
        let (decoderVersion, body, formatVersion) = try unwrap(file, content: .recordedActivity)
        do {
            var reader = BinaryReader(body)
            guard let sport = Sport(rawValue: try reader.readString()) else { throw MalformedStreamFile() }
            let isIndoor = try reader.readBool()
            let isVirtual = try reader.readBool()

            var stated = StatedSummary()
            stated.start = try reader.readOptionalDate()
            stated.end = try reader.readOptionalDate()
            stated.timerTime = try reader.readOptionalDouble()
            stated.distance = try reader.readOptionalDouble()
            stated.ascent = try reader.readOptionalDouble()
            stated.utcOffset = try reader.readBool() ? Int(try reader.read(Int64.self)) : nil

            let eventCount = try reader.readCount(elementSize: 1 + MemoryLayout<Double>.size)
            var events: [TimerEvent] = []
            events.reserveCapacity(eventCount)
            for _ in 0..<eventCount {
                let kind = try timerKind(code: try reader.read(UInt8.self))
                events.append(TimerEvent(kind: kind, timestamp: try reader.readDate()))
            }
            let lapCount = try reader.readCount(elementSize: 2 * MemoryLayout<Double>.size)
            var laps: [RecordedLap] = []
            laps.reserveCapacity(lapCount)
            for _ in 0..<lapCount {
                laps.append(RecordedLap(start: try reader.readDate(), end: try reader.readDate()))
            }

            let sampleCount = try reader.readCount(elementSize: MemoryLayout<Double>.size + 1)
            let timestamps = try reader.readDoubles(sampleCount)
            var samples = timestamps.map { NativeSample(timestamp: Date(timeIntervalSinceReferenceDate: $0)) }

            let hasPosition = try presence(try reader.readBytes(sampleCount))
            let positionCount = hasPosition.count { $0 }
            let latitudes = try reader.readDoubles(positionCount)
            let longitudes = try reader.readDoubles(positionCount)
            var next = 0
            for index in samples.indices where hasPosition[index] {
                samples[index].position = Coordinate(latitude: latitudes[next], longitude: longitudes[next])
                next += 1
            }

            for channel in (formatVersion == 1 ? Array(sampleChannels.prefix(7)) : sampleChannels) {
                let present = try presence(try reader.readBytes(sampleCount))
                let values = try reader.readDoubles(present.count { $0 })
                var next = 0
                for index in samples.indices where present[index] {
                    samples[index][keyPath: channel] = values[next]
                    next += 1
                }
            }
            guard reader.isAtEnd else { throw MalformedStreamFile() }

            let activity = RecordedActivity(
                sport: sport,
                isIndoor: isIndoor,
                isVirtual: isVirtual,
                stated: stated,
                timerEvents: events,
                laps: laps,
                stream: NativeStream(samples: samples)
            )
            return (decoderVersion, activity)
        } catch {
            throw .unreadable
        }
    }

    private static func presence(_ bytes: [UInt8]) throws -> [Bool] {
        try bytes.map {
            switch $0 {
            case 0: false
            case 1: true
            default: throw MalformedStreamFile()
            }
        }
    }
}
