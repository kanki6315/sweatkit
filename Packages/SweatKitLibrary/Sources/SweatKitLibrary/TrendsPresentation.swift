import Foundation
import SweatKitAnalysis
import SweatKitModel
import SweatKitStore

public struct TrendsOptions: Codable, Hashable, Sendable {
    public var sport: String; public var dateWindow: String; public var setting: String
    public var measure: TrendMeasure; public var period: TrendPeriod; public var comparison: String; public var recordWindow: String
    public init(sport: String, dateWindow: String, setting: String, measure: TrendMeasure,
                period: TrendPeriod, comparison: String, recordWindow: String) {
        self.sport = sport; self.dateWindow = dateWindow; self.setting = setting
        self.measure = measure; self.period = period; self.comparison = comparison; self.recordWindow = recordWindow
    }

}
public struct TrendsPresentation: Codable, Sendable {
    public var rows: [TrendActivity] = []
    public var buckets: [TrendBucket] = []
    public var days: [TrendBucket] = []
    public var curve: [PowerCurvePoint] = []
    public var recentCurve: [PowerCurvePoint] = []
    public var recentPowerActivities: [TrendActivity] = []
    public var powerActivities: [TrendActivity] = []
    public var thresholds: [TrendPoint] = []
    public var setThresholds: [TrendPoint] = []
    public var efficiency: [TrendPoint] = []
    public var regression: [TrendPoint] = []
    public var records: [TrendRecord] = []
    public var estimate: Double?
    public var currentThreshold: Double?
    public var staleCount = 0
    public init() {}
    public static func make(_ history: TrendsHistory, options: TrendsOptions, now: Date = Date(), calendar: Calendar = .current) -> Self {
        let year = calendar.dateInterval(of: .year, for: now)!.start
        let end = now.addingTimeInterval(0.001)
        let sports: [String: Sport] = ["Rides": .cycling, "Walks": .walking, "Runs": .running, "Hikes": .hiking]
        let all = history.matching(FeedFilter(sports: sports[options.sport].map { [$0] },
            setting: options.setting == "All settings" ? nil : options.setting == "Indoor" ? .indoor : .outdoor))
        let first = all.map { $0.activity.start }.min() ?? year
        let start: Date
        switch options.dateWindow {
        case "Last 6 weeks": start = calendar.date(byAdding: .day, value: -42, to: now)!
        case "Last 90 days": start = calendar.date(byAdding: .day, value: -90, to: now)!
        case "This year": start = year
        case "All time": start = min(first, now)
        default: start = calendar.date(byAdding: .year, value: -1, to: now)!
        }
        var result = Self()
        result.rows = all.filter { $0.activity.start >= start && $0.activity.start < end }
        result.staleCount = result.rows.filter(\.isStale).count
        result.buckets = TrendsAggregation.volume(all, range: start..<end, period: options.period, measure: options.measure, calendar: calendar)
        let comparisonStart = options.comparison == "All time" ? first : options.comparison == "This year" ? year : calendar.date(byAdding: .day, value: -90, to: now)!
        result.powerActivities = all.filter { !$0.isStale && $0.activity.start >= comparisonStart && $0.activity.start < end }
        result.curve = TrendsAggregation.curve(result.powerActivities)
        let sixWeeks = calendar.date(byAdding: .day, value: -42, to: now)!
        result.recentPowerActivities = all.filter { !$0.isStale && $0.activity.start >= sixWeeks && $0.activity.start < end }
        result.recentCurve = TrendsAggregation.curve(result.recentPowerActivities)
        result.thresholds = TrendsAggregation.thresholds(all, range: start..<end, calendar: calendar)
        result.currentThreshold = history.profile.thresholdPower(on: now)
        result.estimate = TrendsAggregation.estimate(result.rows, on: now, calendar: calendar)
        result.setThresholds = ([start] + history.profile.thresholdPowerHistory.map(\.effectiveFrom).filter { $0 > start && $0 < end } + [now]).sorted().compactMap { date in
            history.profile.thresholdPower(on: date).map { TrendPoint(date: date, value: $0, activity: nil) }
        }
        result.efficiency = TrendsAggregation.efficiency(result.rows)
        result.regression = TrendsAggregation.regression(result.efficiency)
        result.records = TrendsAggregation.records(result.rows.filter { options.recordWindow == "All time" || $0.activity.start >= year })
        result.days = TrendsAggregation.dailyLoad(result.rows, range: start..<end, calendar: calendar)
        return result
    }
}

/// Shared by tab instances. Bound retained work and coalesce simultaneous requests.
/// A minute boundary refreshes rolling windows even when the library is unchanged.
public actor TrendsPresentationCache {
    public init() {}
    private struct Key: Hashable, Codable {
        var schema = 3
        var history: UUID
        var options: TrendsOptions
        var calendar: Calendar
        var minute: Int
    }
    private var entries: [Key: Task<TrendsPresentation, Never>] = [:]
    private var order: [Key] = []

    public func presentation(_ history: TrendsHistory, options: TrendsOptions,
                      now: Date = Date(), calendar: Calendar = .current, store: LibraryStore? = nil) async -> TrendsPresentation {
        let key = Key(history: history.id, options: options, calendar: calendar,
                      minute: Int(now.timeIntervalSinceReferenceDate / 60))
        if let task = entries[key] { return await task.value }
        // Old snapshots can contain deleted activities. Never retain them here.
        let expired = order.filter { $0.history != key.history || $0.minute != key.minute || $0.calendar != key.calendar }
        for key in expired { entries.removeValue(forKey: key) }
        order.removeAll { expired.contains($0) }
        let task = Task.detached(priority: .utility) {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let diskKey = (try? encoder.encode(key)).map { ContentHash(of: $0) }
            if let store, let generation = history.diskGeneration, let diskKey,
               let data = try? await store.readTrendsCache(key: diskKey, generation: generation),
               let cached = try? JSONDecoder().decode(TrendsPresentation.self, from: data) {
                return cached
            }
            let result = TrendsPresentation.make(history, options: options, now: now, calendar: calendar)
            if let store, let generation = history.diskGeneration, let diskKey,
               let data = try? encoder.encode(result) {
                try? await store.saveTrendsCache(data, key: diskKey, generation: generation)
            }
            return result
        }
        entries[key] = task
        order.append(key)
        if order.count > 12 { entries.removeValue(forKey: order.removeFirst()) }
        return await task.value
    }
}
