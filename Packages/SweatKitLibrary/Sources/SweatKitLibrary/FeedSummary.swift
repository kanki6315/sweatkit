import Foundation
import SweatKitStore

public struct FeedWeekSummary: Sendable, Hashable, Identifiable {
    public let start: Date
    public var count = 0
    public var distance: Double = 0
    public var movingTime: Double = 0
    public var ascent: Double = 0
    public var missingDistance = 0
    public var missingMovingTime = 0
    public var missingAscent = 0
    public var id: Date { start }

    init(start: Date) { self.start = start }

    mutating func include(_ row: ActivityRecord) {
        count += 1
        if let value = row.distance { distance += value } else { missingDistance += 1 }
        if let value = row.movingTime { movingTime += value } else { missingMovingTime += 1 }
        if let value = row.ascent { ascent += value } else { missingAscent += 1 }
    }
}

extension ActivityLibrary {
    /// Complete totals for each matching week, independent of the feed page.
    /// Missing figures are counted separately, never silently treated as zero.
    public func weeklySummaries(_ filter: FeedFilter = FeedFilter(), calendar: Calendar = .current) async throws -> [FeedWeekSummary] {
        var weeks: [Date: FeedWeekSummary] = [:]
        var cursor: FeedCursor?
        repeat {
            let page = try await feed(filter, limit: 256, after: cursor)
            for row in page.activities {
                guard let start = calendar.dateInterval(of: .weekOfYear, for: row.start)?.start else { continue }
                var summary = weeks[start] ?? FeedWeekSummary(start: start)
                summary.include(row)
                weeks[start] = summary
            }
            cursor = page.next
        } while cursor != nil
        return weeks.values.sorted { $0.start > $1.start }
    }
}
