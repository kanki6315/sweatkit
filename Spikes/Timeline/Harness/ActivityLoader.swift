import Foundation
import SweatKitAnalysis
import SweatKitFlyover
import SweatKitIngest
import SweatKitModel
import SweatKitTimeline
import SwiftUI

/// Throwaway: one fixture decoded and turned into what the timeline, the
/// stats panel and the map take. In the app this comes from storage, track
/// cleanup and the analysis cache.
struct LoadedActivity: Sendable {
    var name: String
    var sport: Sport
    var isVirtual: Bool
    var stream: AnalysisStream
    /// Cumulative metres, filled forward so it never decreases. Nil when the
    /// stream has no distance at all.
    var distance: [Double]?
    var timeline: TimelineData
    var lapCount: Int
}

enum OverlayChoice: String, CaseIterable, Identifiable, Sendable {
    case none, power, heartRate, speed, cadence

    var id: String { rawValue }

    func label(for sport: Sport) -> String {
        switch self {
        case .none: "None"
        case .power: "Power"
        case .heartRate: "Heart rate"
        case .speed: sport.family == .onFoot ? "Pace" : "Speed"
        case .cadence: "Cadence"
        }
    }
}

/// PLACEHOLDER COLOURS. The real effort palette is not chosen yet (DESIGN.md
/// leaves it "to be resolved during implementation"). These are only here so
/// the harness has bands to draw.
enum PlaceholderPalette {
    static let grey = Color(hex: 0x9A9A9A)
    /// Seven power zones, then the band for seconds with no power.
    static let power: [Color] = [
        Color(hex: 0x8DA0CB), Color(hex: 0x0072B2), Color(hex: 0x009E73), Color(hex: 0xF0E442),
        Color(hex: 0xE69F00), Color(hex: 0xD55E00), Color(hex: 0xCC79A7), grey,
    ]
    /// Five heart-rate zones, then the band for seconds with no heart rate.
    static let heartRate: [Color] = [
        Color(hex: 0x56B4E9), Color(hex: 0x009E73), Color(hex: 0xF0E442), Color(hex: 0xE69F00),
        Color(hex: 0xD55E00), grey,
    ]
    /// Five relative speed bands, then the band for seconds with no speed.
    static let speed: [Color] = [
        Color(hex: 0x0072B2), Color(hex: 0x56B4E9), Color(hex: 0xF0E442), Color(hex: 0xE69F00),
        Color(hex: 0xD55E00), grey,
    ]
}

enum ActivityLoader {
    /// Assumed thresholds, for zone bands only.
    static let assumedThresholdPower = 250.0
    static let assumedThresholdHeartRate = 165.0
    /// A stretch below the moving-speed floor, or paused, for at least this
    /// many seconds counts as a stop. A crude stand-in for stop detection.
    static let shortestStop = 10

    enum LoadError: Error {
        case missingResource(String)
        case noStream
    }

    static func load(resource name: String) throws -> LoadedActivity {
        guard let url = Bundle.main.url(forResource: name, withExtension: "fit") else {
            throw LoadError.missingResource(name)
        }
        let activity = try FITActivityDecoder.decode(Data(contentsOf: url))
        guard let stream = StreamNormaliser.analysisStream(from: activity), stream.count >= 2 else {
            throw LoadError.noStream
        }
        let distance = filledDistance(stream)
        let laps = lapBoundaries(activity, stream: stream)
        let timeline = try TimelineData(
            elevation: (0..<stream.count).map { stream.altitude[$0] },
            distance: distance,
            stops: stops(stream, sport: activity.sport),
            lapBoundaries: laps
        )
        return LoadedActivity(
            name: name, sport: activity.sport, isVirtual: activity.isVirtual,
            stream: stream, distance: distance, timeline: timeline, lapCount: laps.count + 1
        )
    }

    /// The fixtures hold no 5-hour ride, which is what the spec's frame-rate
    /// target names. This repeats an activity end to end until it is `count`
    /// seconds long. It has no route, so it is shown over a drawn backdrop.
    static func repeated(_ activity: LoadedActivity, to count: Int, name: String) throws -> LoadedActivity {
        let source = activity.stream
        let length = source.count
        var stream = AnalysisStream(rulesVersion: source.rulesVersion, start: source.start, count: count)
        for channel in Channel.allCases where channel != .latitude && channel != .longitude && channel != .distance {
            let series = source[channel]
            stream[channel] = Series(
                values: (0..<count).map { series.values[$0 % length] },
                quality: (0..<count).map { series.quality[$0 % length] }
            )
        }
        let lap = activity.distance.map { $0[length - 1] - $0[0] } ?? 0
        let distance = activity.distance.map { distance in
            (0..<count).map { distance[$0 % length] - distance[0] + Double($0 / length) * lap }
        }
        if let distance { stream.distance = Series(distance.map { $0 }) }
        var stops: [Range<Int>] = []
        var laps: [Int] = []
        for copy in 0...(count / length) {
            let offset = copy * length
            for stop in activity.timeline.stops where stop.lowerBound + offset < count {
                let moved = (stop.lowerBound + offset)..<min(stop.upperBound + offset, count)
                if moved.lowerBound >= (stops.last?.upperBound ?? 0) { stops.append(moved) }
            }
            for boundary in ([0] + activity.timeline.lapBoundaries).map({ $0 + offset })
            where boundary > (laps.last ?? 0) && boundary < count {
                laps.append(boundary)
            }
        }
        let timeline = try TimelineData(
            elevation: (0..<count).map { stream.altitude[$0] },
            distance: distance, stops: stops, lapBoundaries: laps
        )
        return LoadedActivity(
            name: name, sport: activity.sport, isVirtual: true,
            stream: stream, distance: distance, timeline: timeline, lapCount: laps.count + 1
        )
    }

    private static func filledDistance(_ stream: AnalysisStream) -> [Double]? {
        guard let first = (0..<stream.count).lazy.compactMap({ stream.distance[$0] }).first else { return nil }
        var last = max(first, 0)
        return (0..<stream.count).map { index in
            if let value = stream.distance[index] { last = max(last, value) }
            return last
        }
    }

    private static func lapBoundaries(_ activity: RecordedActivity, stream: AnalysisStream) -> [Int] {
        var boundaries: [Int] = []
        for lap in activity.laps.dropFirst() {
            let sample = Int(lap.start.timeIntervalSince(stream.start).rounded())
            if sample > (boundaries.last ?? 0), sample < stream.count { boundaries.append(sample) }
        }
        return boundaries
    }

    private static func stops(_ stream: AnalysisStream, sport: Sport) -> [Range<Int>] {
        let floor = sport.family == .cycling
            ? AnalysisRules.movingSpeedFloorCycling
            : AnalysisRules.movingSpeedFloorOnFoot
        var stopped = (0..<stream.count).map { index in
            stream.speed[index].map { $0 < floor } ?? false
        }
        if case .known(let paused) = stream.pauses {
            for span in paused {
                for index in span.clamped(to: 0..<stream.count) { stopped[index] = true }
            }
        }
        var spans: [Range<Int>] = []
        var start: Int?
        for index in 0...stream.count {
            let isStopped = index < stream.count && stopped[index]
            if isStopped, start == nil { start = index }
            if !isStopped, let from = start {
                if index - from >= shortestStop { spans.append(from..<index) }
                start = nil
            }
        }
        return spans
    }

    // MARK: Overlays

    static func overlay(_ choice: OverlayChoice, for activity: LoadedActivity) -> TimelineOverlay? {
        let stream = activity.stream
        let values = { (series: Series) in (0..<stream.count).map { series[$0] } }
        switch choice {
        case .none:
            return nil
        case .power:
            let bands = trailingMean(stream.power, seconds: 10).map { power in
                power.map { ZoneScheme.power.index(of: $0 / assumedThresholdPower) } ?? 7
            }
            return TimelineOverlay(kind: .power, values: values(stream.power), bands: bands, bandColors: PlaceholderPalette.power)
        case .heartRate:
            let bands = (0..<stream.count).map { index in
                stream.heartRate[index].map { ZoneScheme.heartRate.index(of: $0 / assumedThresholdHeartRate) } ?? 5
            }
            return TimelineOverlay(kind: .heartRate, values: values(stream.heartRate), bands: bands, bandColors: PlaceholderPalette.heartRate)
        case .speed:
            let smoothed = trailingMean(stream.speed, seconds: 10)
            let moving = smoothed.compactMap { $0 }.filter { $0 > 0.3 }.sorted()
            let limits = moving.count > 10
                ? [0.1, 0.3, 0.7, 0.9].map { moving[Int(Double(moving.count - 1) * $0)] }
                : []
            let bands = smoothed.map { speed in
                speed.map { value in limits.firstIndex { value <= $0 } ?? 4 } ?? 5
            }
            return TimelineOverlay(
                kind: activity.sport.family == .onFoot ? .pace : .speed,
                values: values(stream.speed), bands: bands, bandColors: PlaceholderPalette.speed
            )
        case .cadence:
            return TimelineOverlay(kind: .cadence, values: values(stream.cadence))
        }
    }

    /// The mean of the values in the seconds ending at each second, or nil
    /// when none of them has a value.
    private static func trailingMean(_ series: Series, seconds: Int) -> [Double?] {
        var result: [Double?] = []
        result.reserveCapacity(series.count)
        var sum = 0.0, count = 0
        for index in 0..<series.count {
            if let value = series[index] { sum += value; count += 1 }
            if index >= seconds, let value = series[index - seconds] { sum -= value; count -= 1 }
            result.append(count > 0 ? sum / Double(count) : nil)
        }
        return result
    }

    // MARK: Stats

    static func cursorStats(at scrub: Double, in activity: LoadedActivity) -> CursorStats {
        let stream = activity.stream
        let index = min(max(Int(scrub.rounded()), 0), stream.count - 1)
        let recent = (max(0, index - 2)...index).compactMap { stream.power[$0] }
        return CursorStats(
            distance: activity.distance.map { $0[index] - $0[0] },
            elapsedTime: scrub,
            speed: stream.speed[index],
            power: recent.isEmpty ? nil : recent.reduce(0, +) / Double(recent.count),
            heartRate: stream.heartRate[index],
            cadence: stream.cadence[index],
            elevation: stream.altitude[index],
            gradient: stream.gradient[index]
        )
    }

    /// A range's stats from SweatKitAnalysis, run on the slice of the stream
    /// the range covers.
    static func rangeStats(_ range: ClosedRange<Int>, in activity: LoadedActivity) -> RangeStats {
        let stream = activity.stream
        let lower = max(range.lowerBound, 0), upper = min(range.upperBound, stream.count - 1)
        guard upper > lower else { return RangeStats(time: 0) }
        let pauses: PauseData
        switch stream.pauses {
        case .known(let paused):
            pauses = .known(paused: paused.compactMap { span in
                let clipped = span.clamped(to: lower..<upper)
                return clipped.isEmpty ? nil : (clipped.lowerBound - lower)..<(clipped.upperBound - lower)
            })
        case .unknown:
            pauses = .unknown(statedTimerTime: nil)
        }
        var slice = AnalysisStream(
            rulesVersion: stream.rulesVersion,
            start: stream.start.addingTimeInterval(Double(lower)),
            count: upper - lower,
            pauses: pauses
        )
        for channel in Channel.allCases {
            let series = stream[channel]
            slice[channel] = Series(
                values: Array(series.values[lower..<upper]),
                quality: Array(series.quality[lower..<upper])
            )
        }
        let metrics = ActivityAnalysis.metrics(for: ActivityInput(
            sport: activity.sport, isVirtual: activity.isVirtual,
            recording: .stream(slice), activityDate: stream.start
        ))
        return RangeStats(
            time: Double(upper - lower),
            distance: activity.distance.map { $0[upper] - $0[lower] },
            ascent: metrics.ascent.value,
            averagePower: metrics.power.average.value,
            averageHeartRate: metrics.heartRate.average.value
        )
    }

    // MARK: Route

    /// The route for the map, coloured by the overlay's bands so the map and
    /// the timeline agree. No cleanup: the tangles where the recorder sat
    /// still are drawn as recorded.
    static func route(for activity: LoadedActivity, overlay: TimelineOverlay?) -> (route: FlyoverRoute, colors: [Color])? {
        guard !activity.isVirtual else { return nil }
        let stream = activity.stream
        var samples: [Int] = []
        var coordinates: [Coordinate] = []
        for index in 0..<stream.count {
            guard let coordinate = stream.coordinate(at: index) else { continue }
            samples.append(index)
            coordinates.append(coordinate)
        }
        guard coordinates.count >= 2 else { return nil }
        let bands = samples.map { overlay?.bands?[$0] ?? 0 }
        let kept = simplify(coordinates, bands: bands, tolerance: 2)
        guard let route = try? FlyoverRoute(
            vertices: kept.map { coordinates[$0] },
            bands: kept.map { bands[$0] },
            sampleIndices: kept.map { samples[$0] }
        ) else { return nil }
        let colors = overlay?.bands == nil ? [Color.white] : (overlay?.bandColors ?? [])
        return (route, colors)
    }

    /// Douglas–Peucker in local metres, keeping the ends and the first point
    /// of each band. Copied from the flyover harness.
    private static func simplify(_ coordinates: [Coordinate], bands: [Int], tolerance: Double) -> [Int] {
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

        let anchors = (0..<count).filter { keep[$0] }
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
