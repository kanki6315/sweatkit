import Foundation

/// A local calendar date, written `yyyy-MM-dd` as the search endpoint expects.
public struct CalendarDate: Sendable, Hashable, Comparable, CustomStringConvertible {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Reads the date part of `yyyy-MM-dd` or `yyyy-MM-dd HH:mm:ss`, the format of
    /// `startTimeLocal` in activity summaries.
    public init?(prefixOf text: String) {
        let parts = text.prefix(10).split(separator: "-")
        guard parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day) else { return nil }
        self.init(year: year, month: month, day: day)
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public static func < (lhs: CalendarDate, rhs: CalendarDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

public struct CalendarMonth: Sendable, Hashable, CustomStringConvertible {
    public var year: Int
    public var month: Int

    public init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    /// Reads `yyyy-MM`.
    public init?(_ text: String) {
        let parts = text.split(separator: "-")
        guard parts.count == 2, let year = Int(parts[0]), let month = Int(parts[1]), (1...12).contains(month) else { return nil }
        self.init(year: year, month: month)
    }

    public init(containing date: CalendarDate) {
        self.init(year: date.year, month: date.month)
    }

    public var firstDay: CalendarDate { CalendarDate(year: year, month: month, day: 1) }

    public var lastDay: CalendarDate {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let first = calendar.date(from: DateComponents(year: year, month: month, day: 1))!
        let days = calendar.range(of: .day, in: .month, for: first)!.count
        return CalendarDate(year: year, month: month, day: days)
    }

    public var description: String { String(format: "%04d-%02d", year, month) }
}
