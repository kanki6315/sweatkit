import FITSwiftSDK
import Foundation
import SweatKitModel

/// Throwaway: the records of a FIT file that have a position, decoded with
/// Garmin's SDK. The real app gets its route from SweatKitIngest.
struct FitTrack: Sendable {
    struct Point: Sendable {
        /// The record's index in the file, used as the source sample index.
        var sample: Int
        /// Seconds since the first record.
        var time: Double
        var coordinate: Coordinate
        var power: Double?
        var speed: Double?
    }

    var name: String
    var points: [Point]
    var recordCount: Int

    enum LoadError: Error {
        case missingResource(String)
        case noPositions
    }

    static func load(resource name: String) throws -> FitTrack {
        guard let url = Bundle.main.url(forResource: name, withExtension: "fit") else {
            throw LoadError.missingResource(name)
        }
        return try load(url: url)
    }

    static func load(url: URL) throws -> FitTrack {
        let name = url.deletingPathExtension().lastPathComponent
        let data = try Data(contentsOf: url)
        let decoder = FITSwiftSDK.Decoder(stream: FITSwiftSDK.InputStream(data: data))
        let listener = FitListener()
        decoder.addMesgListener(listener)
        try decoder.read()
        let records = listener.fitMessages.recordMesgs

        let semicircle = 180.0 / 2_147_483_648.0
        let start = records.first?.getTimestamp()?.timestamp ?? 0
        var points: [Point] = []
        points.reserveCapacity(records.count)
        for (index, record) in records.enumerated() {
            guard let lat = record.getPositionLat(), let lon = record.getPositionLong(),
                  let timestamp = record.getTimestamp()?.timestamp
            else { continue }
            points.append(Point(
                sample: index,
                time: Double(timestamp) - Double(start),
                coordinate: Coordinate(latitude: Double(lat) * semicircle, longitude: Double(lon) * semicircle),
                power: record.getPower().map(Double.init),
                speed: record.getEnhancedSpeed() ?? record.getSpeed()
            ))
        }
        guard points.count >= 2 else { throw LoadError.noPositions }
        return FitTrack(name: name, points: points, recordCount: records.count)
    }
}
