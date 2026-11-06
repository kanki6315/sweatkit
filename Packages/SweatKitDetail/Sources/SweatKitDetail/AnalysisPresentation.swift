import Foundation
import SweatKitModel
import SweatKitAnalysis
import SweatKitTimeline

/// Display points retain their original grid second and contiguous run. Never
/// connect points across missing data, even when a gap falls inside a bucket.
public struct DetailChartPoint: Sendable, Hashable, Identifiable {
    public let second: Int
    public let value: Double
    public let segment: Int
    public var id: Int { second }
}

public struct DetailChartSeries: Sendable, Identifiable {
    public enum Kind: String, CaseIterable, Sendable {
        case power, heartRate, speed, cadence, elevation
        case runningStrideLength, runningGroundContactTime, runningVerticalOscillation
    }
    public let kind: Kind
    public let points: [DetailChartPoint]
    public var id: Kind { kind }

    /// Keep each bucket's endpoints and extrema, in time order. The budget
    /// bounds normal continuous data, not the number of gaps: gaps take priority.
    public static func points(_ values: [Double?], budget: Int = 1200) -> [DetailChartPoint] {
        let width = max(1, Int(ceil(Double(values.count) * 4 / Double(max(4, budget)))))
        var result: [DetailChartPoint] = []
        var bucket: [(Int, Double)] = []
        var segment = 0
        func flush() {
            guard let first = bucket.first, let last = bucket.last,
                  let low = bucket.min(by: { $0.1 < $1.1 }), let high = bucket.max(by: { $0.1 < $1.1 }) else { return }
            let indices = Set([first.0, last.0, low.0, high.0])
            for (second, value) in bucket where indices.contains(second) {
                result.append(DetailChartPoint(second: second, value: value, segment: segment))
            }
            bucket.removeAll(keepingCapacity: true)
        }
        for (second, optional) in values.enumerated() {
            guard let value = optional, value.isFinite else {
                flush()
                segment += 1
                continue
            }
            bucket.append((second, value))
            if bucket.count >= width { flush() }
        }
        flush()
        return result
    }
}

public struct DetailLap: Sendable, Identifiable {
    public let id: Int
    public let range: ClosedRange<Int>
    public let stats: RangeStats
}

public struct DetailAnalysisPresentation: Sendable {
    public let charts: [DetailChartSeries]
    public let laps: [DetailLap]
    public let powerCurve: [PowerCurvePoint]
    public let cadence: CadenceSummary

    public static func prepare(_ detail: PreparedDetail) -> Self {
        let stream = detail.input.stream
        var sources: [(DetailChartSeries.Kind, Series)] = [
            (.heartRate, stream.heartRate), (.speed, stream.speed),
            (.cadence, stream.cadence), (.elevation, stream.altitude)
        ]
        if detail.input.sport.family == .cycling { sources.insert((.power, stream.power), at: 0) }
        if detail.input.sport == .running {
            sources += [(.runningStrideLength, stream.runningStrideLength),
                        (.runningGroundContactTime, stream.runningGroundContactTime),
                        (.runningVerticalOscillation, stream.runningVerticalOscillation)]
        }
        let charts = sources.compactMap { kind, series -> DetailChartSeries? in
            let points = DetailChartSeries.points((0..<series.count).map { index -> Double? in
                guard let value = series[index] else { return nil }
                // Stationary pace is undefined, not zero or infinity.
                if kind == .speed && detail.input.sport.family == .onFoot && value <= 0 { return nil }
                return value
            })
            return points.isEmpty ? nil : DetailChartSeries(kind: kind, points: points)
        }
        let laps: [DetailLap]
        if let recorded = detail.input.recordedLaps {
            laps = recorded.enumerated().compactMap { index, lap in
                let start = lap.start.timeIntervalSince(stream.start)
                let end = lap.end.timeIntervalSince(stream.start)
                guard start.isFinite, end.isFinite, end > start, end > 0,
                      start < Double(stream.count) else { return nil }
                // Bounds are half-open on the 1 Hz grid. Do not fill gaps
                // between laps or extend the last lap to the activity end.
                let lower = Int(max(0, start.rounded(.down)))
                let upper = Int(min(Double(stream.count), end.rounded(.down)))
                guard upper > lower else { return nil }
                let range = lower...(upper - 1)
                return DetailLap(id: index + 1, range: range, stats: detail.rangeStats(range))
            }
        } else {
            // Compatibility for callers that have only start markers. The
            // app passes recordedLaps, including an explicit empty array.
            let starts = Array(Set([0] + detail.input.lapStarts.filter { $0 > 0 && $0 < stream.count })).sorted()
            laps = stream.count > 0 && !detail.input.lapStarts.isEmpty ? starts.enumerated().map { index, start in
                let end = (index + 1 < starts.count ? starts[index + 1] : stream.count) - 1
                let range = start...end
                return DetailLap(id: index + 1, range: range, stats: detail.rangeStats(range))
            } : []
        }
        let curve = detail.input.sport.family == .cycling ? ActivityAnalysis.powerCurve(for:
            ActivityInput(sport: detail.input.sport, isIndoor: detail.input.isIndoor,
                isVirtual: detail.input.isVirtual, recording: .stream(stream),
                profile: detail.input.profile, activityDate: detail.input.activityDate),
            durations: [5, 15, 30, 60, 300, 1200, 3600]) : []
        return Self(charts: charts, laps: laps, powerCurve: curve,
                    cadence: CadenceSummary.calculate(stream: stream))
    }
}

/// Presentation-only pace scale. A fixed, disclosed ceiling avoids a near-zero
/// speed flattening the moving trace. No source or cursor values are changed.
public enum PaceChartScale {
    public static func minutesPerUnit(speed: Double, units: UnitSystem) -> Double? {
        guard speed.isFinite, speed > 0 else { return nil }
        return (units == .metric ? 1000 : 1609.344) / speed / 60
    }

    /// 30 min/km represents 2 km/h; imperial uses the same physical boundary.
    public static func ceiling(units: UnitSystem) -> Double {
        30 * (units == .metric ? 1 : 1.609344)
    }
}
