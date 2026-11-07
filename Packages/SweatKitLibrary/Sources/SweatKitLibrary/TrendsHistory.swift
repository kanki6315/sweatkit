import Foundation
import SweatKitAnalysis
import SweatKitModel
import SweatKitStore

/// Compact, local-only input for every historical view. No stream or coordinates escape this boundary.
public struct TrendActivity: Codable, Sendable {
    public var activity: ActivityRecord
    public var metrics: ActivityMetrics?
    public var curve: [PowerCurvePoint]
    public var isStale: Bool
    public init(activity: ActivityRecord, metrics: ActivityMetrics?, curve: [PowerCurvePoint] = [], isStale: Bool = false) {
        self.activity = activity; self.metrics = metrics; self.curve = curve; self.isStale = isStale
    }
}

public struct TrendsHistory: Codable, Sendable {
    public private(set) var id = UUID()
    var diskGeneration: UUID?
    public static let durations = [5, 15, 30, 60, 120, 300, 600, 1200, 1800, 3600]
    public var activities: [TrendActivity] { didSet { id = UUID(); diskGeneration = nil } }
    public var profile: AthleteProfile { didSet { id = UUID(); diskGeneration = nil } }
    public init(activities: [TrendActivity], profile: AthleteProfile) {
        self.activities = activities; self.profile = profile
    }
    public func matching(_ filter: FeedFilter) -> [TrendActivity] {
        activities.filter {
            let row = $0.activity
            return !row.isHidden && (filter.sports?.contains(row.sport) ?? true)
                && (filter.dates?.contains(row.start) ?? true)
                && (filter.setting == nil || (filter.setting == .indoor) == (row.isIndoor || row.isVirtual))
        }
    }
}

extension ActivityLibrary {
    /// Reads cached analysis; only uncached cycling curves read a stream. Cache uses the
    /// metrics provenance plus the curve algorithm version. Store's derived table is local,
    /// excluded from OS backup and never an input to the non-Health recovery manifest.
    public func trendsHistory() async throws -> TrendsHistory {
        let revision = await store.trendsRevision
        if let cachedTrendsHistory, cachedTrendsHistory.revision == revision {
            return cachedTrendsHistory.history
        }
        cachedTrendsHistory = nil
        if let pending = trendsHistoryTask, pending.revision == revision {
            return try await pending.task.value
        }
        let token = UUID()
        let task = Task(priority: .utility) { try await self.loadPersistedTrendsHistory() }
        trendsHistoryTask = (revision, token, task)
        defer { if trendsHistoryTask?.token == token { trendsHistoryTask = nil } }
        let history = try await task.value
        if await store.trendsRevision == revision {
            cachedTrendsHistory = (revision, history)
        }
        return history
    }

    private func loadPersistedTrendsHistory() async throws -> TrendsHistory {
        // Bump the schema when history semantics or its encoded representation changes.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let versionData = try encoder.encode(versions)
        let key = ContentHash(of: Data("trends.history.v1.\(AlgorithmVersion.powerCurve)".utf8) + versionData)
        let generation = try? await store.trendsCacheGeneration()
        if let generation,
           let data = try? await store.readTrendsCache(key: key, generation: generation, kind: .history),
           let history = try? JSONDecoder().decode(TrendsHistory.self, from: data),
           history.diskGeneration == generation {
            return history
        }
        var history = try await buildTrendsHistory()
        if let generation, (try? await store.trendsCacheGeneration()) == generation {
            history.diskGeneration = generation
            if let data = try? encoder.encode(history) {
                try? await store.saveTrendsCache(data, key: key, generation: generation, kind: .history)
            }
        }
        return history
    }

    private func buildTrendsHistory() async throws -> TrendsHistory {
        let profile = try await profile()
        let stale = Set(try await staleActivities().map(\.id))
        var output: [TrendActivity] = []
        var cursor: FeedCursor?
        repeat {
            let page = try await feed(limit: 256, after: cursor)
            for row in page.activities {
                try Task.checkCancellation()
                guard let id = row.id else { continue }
                let result = try await store.derivedResult(owner: .activity(id), kind: Self.metricsKind)
                let metrics = stale.contains(id) ? nil : try await metrics(for: id)
                var curve: [PowerCurvePoint] = []
                if row.sport == .cycling, !stale.contains(id), let result {
                    let kind = "trends.powerCurve.v1.\(AlgorithmVersion.powerCurve)"
                    let cached = try await store.derivedResult(owner: .activity(id), kind: kind)
                    if let cached, cached.provenance == result.provenance,
                       let decoded = try? JSONDecoder().decode([PowerCurvePoint].self, from: cached.payload) {
                        curve = decoded
                    } else {
                        let stream = try await analysisStream(for: id)
                        let input = ActivityInput(sport: row.sport, isIndoor: row.isIndoor, isVirtual: row.isVirtual,
                            recording: .stream(stream), activityDate: row.start)
                        curve = await Task.detached(priority: .utility) {
                            ActivityAnalysis.powerCurve(for: input, durations: TrendsHistory.durations)
                        }.value
                        // Do not attach an old result to a revised or deleted activity.
                        guard try await store.activity(id) == row,
                              try await store.derivedResult(owner: .activity(id), kind: Self.metricsKind) == result else { continue }
                        try await store.saveDerivedResult(DerivedResult(owner: .activity(id), kind: kind,
                            provenance: result.provenance, profileReading: result.profileReading,
                            payload: JSONEncoder().encode(curve), computedAt: Date()))
                    }
                }
                output.append(TrendActivity(activity: row, metrics: metrics, curve: curve, isStale: stale.contains(id)))
            }
            cursor = page.next
        } while cursor != nil
        return TrendsHistory(activities: output, profile: profile)
    }
}
