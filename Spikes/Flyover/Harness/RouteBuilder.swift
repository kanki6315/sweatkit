import Foundation
import SweatKitFlyover
import SweatKitModel
import SwiftUI

/// Throwaway, crude stand-ins for the zone calculation and track cleanup that
/// belong in SweatKitAnalysis and SweatKitIngest.
enum RouteBuilder {
    enum Colouring: Sendable {
        /// Seven power zones on 10 s smoothed power, from an assumed threshold.
        case power(threshold: Double)
        /// Five bands of 10 s smoothed speed relative to this activity's range.
        case relativePace
    }

    struct Built {
        var route: FlyoverRoute
        var colors: [Color]
        var bandNames: [String]
        var runCount: Int
    }

    static let powerColors: [Color] = [
        Color(hex: 0x8DA0CB), Color(hex: 0x0072B2), Color(hex: 0x009E73), Color(hex: 0xF0E442),
        Color(hex: 0xE69F00), Color(hex: 0xD55E00), Color(hex: 0xCC79A7), Color(hex: 0xBBBBBB),
    ]
    static let powerNames = ["Z1", "Z2", "Z3", "Z4", "Z5", "Z6", "Z7", "no power"]
    static let paceColors: [Color] = [
        Color(hex: 0x0072B2), Color(hex: 0x56B4E9), Color(hex: 0xF0E442), Color(hex: 0xE69F00),
        Color(hex: 0xD55E00), Color(hex: 0xBBBBBB),
    ]
    static let paceNames = ["slowest", "slow", "middle", "fast", "fastest", "no speed"]

    static func build(_ track: FitTrack, colouring: Colouring, tolerance: Double) throws -> Built {
        let bands: [Int]
        let colors: [Color]
        let names: [String]
        switch colouring {
        case .power(let threshold):
            bands = powerBands(track, threshold: threshold)
            colors = powerColors
            names = powerNames
        case .relativePace:
            bands = paceBands(track)
            colors = paceColors
            names = paceNames
        }
        let kept = simplify(track.points.map(\.coordinate), bands: bands, tolerance: tolerance)
        let route = try FlyoverRoute(
            vertices: kept.map { track.points[$0].coordinate },
            bands: kept.map { bands[$0] },
            sampleIndices: kept.map { track.points[$0].sample }
        )
        return Built(route: route, colors: colors, bandNames: names, runCount: BandRuns.split(route.bands).count)
    }

    // MARK: Colouring

    /// The mean of the values in the 10 s ending at each point, or nil when
    /// none of them has a value.
    private static func trailingMean(_ track: FitTrack, _ value: (FitTrack.Point) -> Double?) -> [Double?] {
        var result: [Double?] = []
        result.reserveCapacity(track.points.count)
        var start = 0
        var sum = 0.0, count = 0
        for point in track.points {
            if let v = value(point) { sum += v; count += 1 }
            while track.points[start].time <= point.time - 10 {
                if let v = value(track.points[start]) { sum -= v; count -= 1 }
                start += 1
            }
            result.append(count > 0 ? sum / Double(count) : nil)
        }
        return result
    }

    private static func powerBands(_ track: FitTrack, threshold: Double) -> [Int] {
        let limits = [0.55, 0.75, 0.90, 1.05, 1.20, 1.50].map { $0 * threshold }
        return trailingMean(track, \.power).map { power in
            guard let power else { return 7 }
            return limits.firstIndex { power <= $0 } ?? 6
        }
    }

    private static func paceBands(_ track: FitTrack) -> [Int] {
        let speeds = trailingMean(track, \.speed)
        let moving = speeds.compactMap { $0 }.filter { $0 > 0.3 }.sorted()
        guard moving.count > 10 else { return speeds.map { $0 == nil ? 5 : 2 } }
        let limits = [0.1, 0.3, 0.7, 0.9].map { moving[Int(Double(moving.count - 1) * $0)] }
        return speeds.map { speed in
            guard let speed else { return 5 }
            return limits.firstIndex { speed <= $0 } ?? 4
        }
    }

    // MARK: Simplification

    /// Douglas–Peucker in local metres, always keeping the ends and the first
    /// point of each band so band edges stay where they were. Returns the kept
    /// indices in order.
    static func simplify(_ coordinates: [Coordinate], bands: [Int], tolerance: Double) -> [Int] {
        let count = coordinates.count
        guard count > 2, tolerance > 0 else { return Array(0..<count) }
        let latitude = coordinates[0].latitude * .pi / 180
        let metresPerDegree = 111_195.08
        let xs = coordinates.map { $0.longitude * metresPerDegree * cos(latitude) }
        let ys = coordinates.map { $0.latitude * metresPerDegree }

        var keep = [Bool](repeating: false, count: count)
        keep[0] = true
        keep[count - 1] = true
        for index in 1..<count where bands[index] != bands[index - 1] { keep[index] = true }

        var anchors: [Int] = []
        for index in 0..<count where keep[index] { anchors.append(index) }
        var stack: [(Int, Int)] = zip(anchors, anchors.dropFirst()).map { ($0, $1) }
        while let (first, last) = stack.popLast() {
            guard last - first > 1 else { continue }
            let ax = xs[first], ay = ys[first]
            let dx = xs[last] - ax, dy = ys[last] - ay
            let lengthSquared = dx * dx + dy * dy
            var farthest = first, farthestDistance = 0.0
            for index in (first + 1)..<last {
                let px = xs[index] - ax, py = ys[index] - ay
                let distance: Double
                if lengthSquared == 0 {
                    distance = (px * px + py * py).squareRoot()
                } else {
                    let t = max(0, min(1, (px * dx + py * dy) / lengthSquared))
                    let ex = px - t * dx, ey = py - t * dy
                    distance = (ex * ex + ey * ey).squareRoot()
                }
                if distance > farthestDistance {
                    farthestDistance = distance
                    farthest = index
                }
            }
            if farthestDistance > tolerance {
                keep[farthest] = true
                stack.append((first, farthest))
                stack.append((farthest, last))
            }
        }
        return (0..<count).filter { keep[$0] }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
