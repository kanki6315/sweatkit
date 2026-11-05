import Foundation
import SweatKitGarmin

/// One calendar month of local start dates, the unit of the spec's backfill.
/// Kept in the probe because the backfill design waits on the gate results.
public struct CalendarMonth: Sendable, Hashable, CustomStringConvertible {
    public var year: Int
    public var month: Int

    public init?(year: Int, month: Int) {
        guard (1...9999).contains(year), (1...12).contains(month) else { return nil }
        self.year = year
        self.month = month
    }

    /// Reads `yyyy-MM`.
    public init?(_ text: String) {
        let parts = text.split(separator: "-")
        guard parts.count == 2, let year = Int(parts[0]), let month = Int(parts[1]) else { return nil }
        self.init(year: year, month: month)
    }

    public init(containing date: CalendarDate) {
        year = date.year
        month = date.month
    }

    public var firstDay: CalendarDate? { CalendarDate(year: year, month: month, day: 1) }

    public var lastDay: CalendarDate? {
        (28...31).reversed().lazy.compactMap { CalendarDate(year: self.year, month: self.month, day: $0) }.first
    }

    public var previous: CalendarMonth? {
        month == 1 ? CalendarMonth(year: year - 1, month: 12) : CalendarMonth(year: year, month: month - 1)
    }

    /// The search for every activity starting in this month, newest first.
    public func query(start: Int = 0) -> ActivityQuery {
        ActivityQuery(start: start, startDate: firstDay, endDate: lastDay)
    }

    public var description: String { String(format: "%04d-%02d", year, month) }
}
