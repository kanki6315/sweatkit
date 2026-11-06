import Foundation
import SweatKitModel

/// Display data from one Health original. Never uses the normalized stream,
/// merges another provider, or substitutes a computed total for a source total.
public struct GolfHealthRecording: Sendable {
    public let sourceName: String
    public let stated: StatedSummary
    public let channels: [Channel]
    public let positions: [Position]
    public let laps: [RecordedLap]
    public let segments: [RecordedLap]

    public struct Reading: Sendable {
        public let timestamp: Date
        public let value: Double
    }
    public struct Channel: Sendable {
        public let name: String
        public let unit: String
        public let readings: [Reading]
    }
    public struct Position: Sendable {
        public let timestamp: Date
        public let coordinate: Coordinate
    }

    public init?(_ snapshot: HealthSnapshot) {
        guard snapshot.sourceSportName == "Golf" else { return nil }
        sourceName = snapshot.sourceName
        stated = snapshot.activity.stated
        laps = snapshot.activity.laps
        segments = snapshot.activity.segments ?? []
        let samples = snapshot.activity.stream.samples.sorted { $0.timestamp < $1.timestamp }
        // These are native values, not interpolated or derived analysis channels.
        let fields: [(String, String, KeyPath<NativeSample, Double?>, Bool)] = [
            ("Heart rate", "bpm", \.heartRate, true),
            ("Altitude", "m", \.altitude, false),
            ("Speed", "m/s", \.speed, true),
            ("Distance", "m", \.distance, true),
            ("Power", "W", \.power, true),
            ("Cadence", "per minute", \.cadence, true),
            ("Temperature", "°C", \.temperature, false)
        ]
        channels = fields.compactMap { name, unit, key, nonnegative in
            let readings = samples.compactMap { sample -> Reading? in
                guard let value = sample[keyPath: key], value.isFinite,
                      !nonnegative || value >= 0 else { return nil }
                return Reading(timestamp: sample.timestamp, value: value)
            }
            return readings.isEmpty ? nil : Channel(name: name, unit: unit, readings: readings)
        }
        positions = samples.compactMap { sample in
            guard let coordinate = sample.position,
                  coordinate.latitude.isFinite, coordinate.longitude.isFinite,
                  (-90...90).contains(coordinate.latitude),
                  (-180...180).contains(coordinate.longitude) else { return nil }
            return Position(timestamp: sample.timestamp, coordinate: coordinate)
        }
    }
}

extension ActivityLibrary {
    public func golfHealthRecording(for source: SourceIdentity) async throws -> GolfHealthRecording? {
        guard source.source == .healthKit,
              let record = try await store.sourceRecord(source),
              let bytes = try await store.original(record.currentRevision),
              let snapshot = try HealthSnapshot.decode(bytes) else { return nil }
        return GolfHealthRecording(snapshot)
    }
}
