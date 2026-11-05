import Foundation
import SweatKitGarmin

/// One calendar month of local start dates, the unit of the backfill and the
/// deep scan.
public struct CalendarMonth: Sendable, Hashable, Comparable, Codable, CustomStringConvertible {
    public var year: Int
    public var month: Int

    public init?(year: Int, month: Int) {
        guard (1...9999).contains(year), (1...12).contains(month) else { return nil }
        self.year = year
        self.month = month
    }

    public init(containing date: CalendarDate) {
        year = date.year
        month = date.month
    }

    public var firstDay: CalendarDate {
        // Day 1 of a valid month always exists.
        CalendarDate(year: year, month: month, day: 1)!
    }

    public var lastDay: CalendarDate {
        (28...31).reversed().lazy.compactMap { CalendarDate(year: self.year, month: self.month, day: $0) }.first!
    }

    public var previous: CalendarMonth? {
        month == 1 ? CalendarMonth(year: year - 1, month: 12) : CalendarMonth(year: year, month: month - 1)
    }

    public static func < (lhs: CalendarMonth, rhs: CalendarMonth) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }

    public var description: String { String(format: "%04d-%02d", year, month) }
}

/// A range of local start dates, both ends included. A nil end is open: it
/// takes in anything newer, including start dates after today.
public struct DateRange: Sendable, Hashable, CustomStringConvertible {
    public var start: CalendarDate
    public var end: CalendarDate?

    public init(start: CalendarDate, end: CalendarDate?) {
        self.start = start
        self.end = end
    }

    public init(_ month: CalendarMonth, openEnded: Bool = false) {
        self.init(start: month.firstDay, end: openEnded ? nil : month.lastDay)
    }

    public func contains(_ date: CalendarDate) -> Bool {
        date >= start && (end.map { date <= $0 } ?? true)
    }

    public var description: String { "\(start)...\(end?.description ?? "")" }
}

extension CalendarDate {
    /// The local date of `date` in `calendar`'s time zone.
    init(_ date: Date, in calendar: Calendar) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        // A Gregorian calendar always yields a valid date.
        self.init(year: parts.year!, month: parts.month!, day: parts.day!)!
    }

    /// This date moved by a number of days.
    func adding(days: Int) -> CalendarDate {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let noon = utc.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
        return CalendarDate(utc.date(byAdding: .day, value: days, to: noon)!, in: utc)
    }
}
