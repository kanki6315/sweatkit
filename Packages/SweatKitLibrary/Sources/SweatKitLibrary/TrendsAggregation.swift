import Foundation
import SweatKitAnalysis
import SweatKitModel
import SweatKitStore

public enum TrendMeasure: String, CaseIterable, Sendable { case distance = "Distance", time = "Time", ascent = "Ascent", load = "Load" }
public enum TrendPeriod: String, CaseIterable, Sendable {
    case week = "Weekly", month = "Monthly", year = "Yearly"
    public var component: Calendar.Component { switch self { case .week: .weekOfYear; case .month: .month; case .year: .year } }
}
public struct TrendTotal: Sendable {
    public var known: Double = 0
    public var missing: Int = 0
    public var count: Int = 0
    public init() {}
    public var complete: Double? { missing == 0 ? known : nil }
}
public struct TrendBucket: Identifiable, Sendable {
    public var start: Date
    public var end: Date
    public var total: TrendTotal
    public var previous: TrendTotal
    public var lastYear: TrendTotal
    public var id: Date { start }
    public init(start: Date, end: Date, total: TrendTotal, previous: TrendTotal, lastYear: TrendTotal) {
        self.start = start; self.end = end; self.total = total; self.previous = previous; self.lastYear = lastYear
    }
}
public struct TrendRecord: Identifiable, Sendable {
    public var key: String
    public var title: String
    public var value: Double
    public var unit: String
    public var activity: ActivityRecord
    public var id: String { key }
}
public struct TrendPoint: Identifiable, Sendable {
    public var date: Date
    public var value: Double
    public var activity: ActivityRecord?
    public var id: String { "\(date.timeIntervalSinceReferenceDate):\(activity?.primary.description ?? "")" }
    public init(date: Date, value: Double, activity: ActivityRecord? = nil) {
        self.date = date; self.value = value; self.activity = activity
    }
}

public enum TrendsAggregation {
    public static func total(_ rows: [TrendActivity], measure: TrendMeasure) -> TrendTotal {
        var result = TrendTotal()
        for row in rows {
            result.count += 1
            let value: Double?
            switch measure {
            case .distance: value = row.isStale ? nil : row.activity.distance
            case .time: value = row.isStale ? nil : row.activity.movingTime
            case .ascent: value = row.isStale ? nil : row.activity.ascent
            case .load: value = row.isStale ? nil : row.metrics?.load.value?.value
            }
            if let value { result.known += value } else { result.missing += 1 }
        }
        return result
    }
    /// Calendar periods use the caller's calendar/timezone, half-open throughout.
    /// Empty bins mean no imported activities, never proof of no exercise.
    public static func volume(_ rows: [TrendActivity], range: Range<Date>, period: TrendPeriod,
                              measure: TrendMeasure, calendar: Calendar = .current) -> [TrendBucket] {
        guard var start = calendar.dateInterval(of: period.component, for: range.lowerBound)?.start else { return [] }
        func sum(_ start: Date, _ end: Date) -> TrendTotal {
            total(rows.filter { $0.activity.start >= start && $0.activity.start < end }, measure: measure)
        }
        var result: [TrendBucket] = []
        while start < range.upperBound {
            guard let end = calendar.date(byAdding: period.component, value: 1, to: start), end > start,
                  let previous = calendar.date(byAdding: period.component, value: -1, to: start) else { break }
            var lastYear = TrendTotal()
            if let year = previousYear(start, period: period, calendar: calendar),
               let yearEnd = calendar.date(byAdding: period.component, value: 1, to: year) {
                lastYear = sum(year, yearEnd)
            }
            result.append(TrendBucket(start: start, end: end, total: sum(max(start, range.lowerBound), min(end, range.upperBound)),
                previous: sum(previous, start), lastYear: lastYear))
            start = end
        }
        return result
    }
    private static func previousYear(_ date: Date, period: TrendPeriod, calendar: Calendar) -> Date? {
        if period == .week {
            var parts = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
            parts.yearForWeekOfYear = (parts.yearForWeekOfYear ?? 1) - 1
            parts.weekday = calendar.firstWeekday
            guard let result = calendar.date(from: parts),
                  calendar.component(.weekOfYear, from: result) == parts.weekOfYear,
                  calendar.component(.yearForWeekOfYear, from: result) == parts.yearForWeekOfYear else { return nil }
            return result
        }
        return calendar.date(byAdding: .year, value: -1, to: date)
    }
    public static func dailyLoad(_ rows: [TrendActivity], range: Range<Date>, calendar: Calendar = .current) -> [TrendBucket] {
        let groups = Dictionary(grouping: rows.filter { range.contains($0.activity.start) }) {
            calendar.startOfDay(for: $0.activity.start)
        }
        var day = calendar.dateInterval(of: .weekOfYear, for: range.lowerBound)?.start ?? calendar.startOfDay(for: range.lowerBound)
        var result: [TrendBucket] = []
        while day < range.upperBound {
            guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { break }
            result.append(TrendBucket(start: day, end: next, total: total(groups[day] ?? [], measure: .load), previous: TrendTotal(), lastYear: TrendTotal()))
            day = next
        }
        return result
    }
    public static func curve(_ rows: [TrendActivity]) -> [PowerCurvePoint] {
        TrendsHistory.durations.map { duration in
            let best = rows.filter { !$0.isStale }.flatMap(\.curve).filter { $0.duration == duration }.compactMap { $0.power.value }.max()
            return PowerCurvePoint(duration: duration, power: best.map(Metric.available) ?? .unavailable(.noValidWindow))
        }
    }
    public static func estimate(_ rows: [TrendActivity], on date: Date, calendar: Calendar = .current) -> Double? {
        guard let start = calendar.date(byAdding: .day, value: -90, to: date) else { return nil }
        return rows.filter { !$0.isStale && $0.activity.start >= start && $0.activity.start <= date }
            .flatMap(\.curve).filter { $0.duration == 1200 }.compactMap { $0.power.value }.max().map { $0 * 0.95 }
    }
    public static func thresholds(_ rows: [TrendActivity], range: Range<Date>, calendar: Calendar = .current) -> [TrendPoint] {
        var date = range.lowerBound
        var result: [TrendPoint] = []
        while date < range.upperBound {
            if let value = estimate(rows, on: date, calendar: calendar) { result.append(TrendPoint(date: date, value: value)) }
            guard let next = calendar.date(byAdding: .day, value: 1, to: date), next > date else { break }
            date = next
        }
        return result
    }
    public static func efficiency(_ rows: [TrendActivity]) -> [TrendPoint] {
        rows.compactMap { row in
            guard !row.isStale, row.activity.sport == .cycling, let metrics = row.metrics,
                  let duration = metrics.time.timer.value, duration >= 1200,
                  let variability = metrics.power.variability.value, variability < 1.10,
                  let value = metrics.cyclingEfficiency.value else { return nil }
            return TrendPoint(date: row.activity.start, value: value, activity: row.activity)
        }.sorted { $0.date < $1.date }
    }
    public static func regression(_ points: [TrendPoint]) -> [TrendPoint] {
        guard points.count > 1, let first = points.first, let last = points.last, first.date < last.date else { return [] }
        let xs = points.map { $0.date.timeIntervalSince(first.date) / 86400 }
        let meanX = xs.reduce(0, +) / Double(xs.count)
        let meanY = points.map(\.value).reduce(0, +) / Double(points.count)
        let denominator = xs.reduce(0) { $0 + pow($1 - meanX, 2) }
        guard denominator > 0 else { return [] }
        let slope = zip(xs, points).reduce(0) { $0 + ($1.0 - meanX) * ($1.1.value - meanY) } / denominator
        return [first, last].map { TrendPoint(date: $0.date, value: meanY + slope * ($0.date.timeIntervalSince(first.date) / 86400 - meanX)) }
    }
    public static func records(_ rows: [TrendActivity]) -> [TrendRecord] {
        var best: [String: TrendRecord] = [:]
        func include(_ key: String, _ title: String, _ value: Double?, _ unit: String, _ row: ActivityRecord, lower: Bool = false) {
            guard let value else { return }
            if let old = best[key], lower ? value >= old.value : value <= old.value { return }
            best[key] = TrendRecord(key: key, title: title, value: value, unit: unit, activity: row)
        }
        // First attainment wins ties, independent of ingestion order.
        for item in rows.filter({ !$0.isStale && !$0.activity.isHidden }).sorted(by: {
            $0.activity.start == $1.activity.start ? $0.activity.primary < $1.activity.primary : $0.activity.start < $1.activity.start
        }) {
            let row = item.activity
            for point in item.curve { include("power.\(point.duration)", "Best \(point.duration < 60 ? "\(point.duration) s" : "\(point.duration / 60) min") power", point.power.value, "W", row) }
            for distance in item.metrics?.bestDistances ?? [] {
                include("distance.\(row.sport).\(distance.distance)", "Fastest \(Int(distance.distance / 1000)) km · \(row.sport)", distance.time.value, "s", row, lower: true)
            }
            if row.sport == .cycling { include("longestRide", "Longest ride", row.distance, "m", row) }
            include("ascent.\(row.sport)", "Most ascent · \(row.sport)", row.ascent, "m", row)
        }
        return best.values.sorted {
            let left = $0.key.hasPrefix("power.")
            let right = $1.key.hasPrefix("power.")
            if left && right {
                return (Int($0.key.dropFirst(6)) ?? 0) < (Int($1.key.dropFirst(6)) ?? 0)
            }
            if left != right { return left }
            return $0.key < $1.key
        }
    }
    /// Read-only feed hook: records newly attained at this activity, relative to earlier
    /// visible history of the same sport/setting. Ties are not new records.
    public static func recordBadges(for id: SourceIdentity, in rows: [TrendActivity]) -> [TrendRecord] {
        guard let target = rows.first(where: { $0.activity.id == id }) else { return [] }
        return records(rows.filter { $0.activity.start <= target.activity.start && $0.activity.sport == target.activity.sport
            && ($0.activity.isIndoor || $0.activity.isVirtual) == (target.activity.isIndoor || target.activity.isVirtual) })
            .filter { $0.activity.id == id }
    }
}
