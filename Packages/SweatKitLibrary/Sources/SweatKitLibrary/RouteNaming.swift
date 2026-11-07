import Foundation
import SweatKitRouteMatching

extension ActivityLibrary {
    nonisolated static func routeRegion(_ input: RouteInput) -> String {
        if input.row.isVirtual { return "Virtual routes" }
        if let locality = input.locality, !locality.isEmpty { return locality }
        guard let point = input.track.points.first?.coordinate else { return "Unknown region" }
        // Fixed geographic buckets remain stable across imports, without network access.
        let latitude = floor(point.latitude * 4) / 4 + 0.125
        let longitude = floor(point.longitude * 4) / 4 + 0.125
        return String(format: "Area %.2f, %.2f", latitude, longitude)
    }

    nonisolated static func routeDescription(_ input: RouteInput) -> String {
        let place = input.row.isVirtual ? "Virtual" : input.locality ?? "Local"
        return "\(place) \(routeShapeDescription(input))"
    }

    nonisolated static func routeShapeDescription(_ input: RouteInput) -> String {
        let points = RouteDetection.resample(input.track)
        let length = input.track.length
        var shape = "Point-to-Point"
        if let first = points.first, let last = points.last,
           Geodesy.distance(from: first, to: last) <= min(200, length * 0.1) {
            let pairs = points.count / 2
            let retraced = (0..<pairs).filter {
                Geodesy.distance(from: points[$0], to: points[points.count - 1 - $0]) < 50
            }.count
            shape = pairs > 0 && Double(retraced) / Double(pairs) >= 0.75 ? "Out-and-Back" : "Loop"
        }
        return "\(String(format: "%.1f", length / 1000)) km \(shape)"
    }
}
