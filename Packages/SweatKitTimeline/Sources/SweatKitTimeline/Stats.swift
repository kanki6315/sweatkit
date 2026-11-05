import Foundation
import SweatKitModel

/// The values at the cursor, supplied by the caller. Each is nil when the
/// activity has no value there, which shows as a dash, never as zero.
public struct CursorStats: Hashable, Sendable {
    /// Metres from the start.
    public var distance: Double?
    /// Seconds from the start.
    public var elapsedTime: TimeInterval?
    /// Metres per second. Shown as speed for cycling and as pace on foot.
    public var speed: Double?
    /// Watts, averaged over 3 seconds. Shown for cycling only.
    public var power: Double?
    /// Beats per minute.
    public var heartRate: Double?
    /// Revolutions per minute on a bike, steps per minute on foot.
    public var cadence: Double?
    /// Metres.
    public var elevation: Double?
    /// Rise over run, so 0.05 is a 5% climb.
    public var gradient: Double?

    public init(
        distance: Double? = nil,
        elapsedTime: TimeInterval? = nil,
        speed: Double? = nil,
        power: Double? = nil,
        heartRate: Double? = nil,
        cadence: Double? = nil,
        elevation: Double? = nil,
        gradient: Double? = nil
    ) {
        self.distance = distance
        self.elapsedTime = elapsedTime
        self.speed = speed
        self.power = power
        self.heartRate = heartRate
        self.cadence = cadence
        self.elevation = elevation
        self.gradient = gradient
    }
}

/// The stats of a selected range, supplied by the caller. Each is nil when it
/// is unavailable, which shows as a dash.
public struct RangeStats: Hashable, Sendable {
    /// Seconds.
    public var time: TimeInterval?
    /// Metres.
    public var distance: Double?
    /// Metres.
    public var ascent: Double?
    /// Watts. Shown for cycling only.
    public var averagePower: Double?
    /// Beats per minute.
    public var averageHeartRate: Double?

    public init(
        time: TimeInterval? = nil,
        distance: Double? = nil,
        ascent: Double? = nil,
        averagePower: Double? = nil,
        averageHeartRate: Double? = nil
    ) {
        self.time = time
        self.distance = distance
        self.ascent = ascent
        self.averagePower = averagePower
        self.averageHeartRate = averageHeartRate
    }
}

/// One stat in its slot.
struct StatSlot: Hashable, Sendable, Identifiable {
    /// The label above the numerals.
    var label: String
    /// The label VoiceOver reads, where the short one is not enough.
    var spokenLabel: String
    var stat: FormattedStat
    /// The widest numerals the slot will hold. The slot is sized to this, so
    /// its width does not change as the value does.
    var template: String

    var id: String { label }
}

enum StatSlots {
    /// The slots of the stats panel, in the spec's order. Cycling shows
    /// speed and 3-second power. Walking, running and hiking show pace in
    /// place of speed and have no power. Any other sport shows speed and has
    /// neither power nor cadence.
    static func cursor(_ stats: CursorStats, sport: Sport, units: UnitSystem, locale: Locale = .current) -> [StatSlot] {
        let distance = StatSlot(
            label: "Distance", spokenLabel: "Distance",
            stat: StatFormatter.distance(stats.distance, units: units, locale: locale),
            template: "888.88"
        )
        let time = StatSlot(
            label: "Time", spokenLabel: "Elapsed time",
            stat: StatFormatter.elapsedTime(stats.elapsedTime),
            template: "88:88:88"
        )
        let speed = StatSlot(
            label: "Speed", spokenLabel: "Speed",
            stat: StatFormatter.speed(stats.speed, units: units, locale: locale),
            template: "88.8"
        )
        let pace = StatSlot(
            label: "Pace", spokenLabel: "Pace",
            stat: StatFormatter.pace(stats.speed, units: units),
            template: "888:88"
        )
        let power = StatSlot(
            label: "3 s power", spokenLabel: "3-second power",
            stat: StatFormatter.power(stats.power, locale: locale),
            template: "8888"
        )
        let heartRate = StatSlot(
            label: "Heart rate", spokenLabel: "Heart rate",
            stat: StatFormatter.heartRate(stats.heartRate, locale: locale),
            template: "888"
        )
        let cadence = StatSlot(
            label: "Cadence", spokenLabel: "Cadence",
            stat: StatFormatter.cadence(stats.cadence, sport: sport, locale: locale),
            template: "888"
        )
        let elevation = StatSlot(
            label: "Elevation", spokenLabel: "Elevation",
            stat: StatFormatter.elevation(stats.elevation, units: units, locale: locale),
            template: units == .metric ? "8888" : "88888"
        )
        let gradient = StatSlot(
            label: "Gradient", spokenLabel: "Gradient",
            stat: StatFormatter.gradient(stats.gradient, locale: locale),
            template: "−88.8"
        )
        switch sport.family {
        case .cycling: return [distance, time, speed, power, heartRate, cadence, elevation, gradient]
        case .onFoot: return [distance, time, pace, heartRate, cadence, elevation, gradient]
        case .other: return [distance, time, speed, heartRate, elevation, gradient]
        }
    }

    /// The slots for a selected range: time, distance, ascent, average power
    /// and average heart rate. Power is shown for cycling only.
    static func range(_ stats: RangeStats?, sport: Sport, units: UnitSystem, locale: Locale = .current) -> [StatSlot] {
        var slots = [
            StatSlot(
                label: "Time", spokenLabel: "Time",
                stat: StatFormatter.elapsedTime(stats?.time),
                template: "88:88:88"
            ),
            StatSlot(
                label: "Distance", spokenLabel: "Distance",
                stat: StatFormatter.distance(stats?.distance, units: units, locale: locale),
                template: "888.88"
            ),
            StatSlot(
                label: "Ascent", spokenLabel: "Ascent",
                stat: StatFormatter.elevation(stats?.ascent, units: units, locale: locale),
                template: units == .metric ? "8888" : "88888"
            ),
        ]
        if sport.family == .cycling {
            slots.append(StatSlot(
                label: "Avg power", spokenLabel: "Average power",
                stat: StatFormatter.power(stats?.averagePower, locale: locale),
                template: "8888"
            ))
        }
        slots.append(StatSlot(
            label: "Avg HR", spokenLabel: "Average heart rate",
            stat: StatFormatter.heartRate(stats?.averageHeartRate, locale: locale),
            template: "888"
        ))
        return slots
    }
}

enum StatGrid {
    /// The width of each column when the slots are laid out row by row in
    /// `columns` columns: a column is as wide as its widest slot.
    static func columnWidths(slotWidths: [Double], columns: Int) -> [Double] {
        var widths = [Double](repeating: 0, count: min(max(columns, 1), max(slotWidths.count, 1)))
        for (index, width) in slotWidths.enumerated() {
            widths[index % widths.count] = max(widths[index % widths.count], width)
        }
        return widths
    }

    /// Where each column starts, from the left edge of the width.
    ///
    /// Columns start at equal steps across the width when every column fits
    /// its step with the spacing to spare. Otherwise they are packed with
    /// whatever room is left shared equally between them, which is never
    /// less than the spacing when the columns fit at all.
    static func columnOrigins(columnWidths: [Double], available: Double, spacing: Double) -> [Double] {
        let count = columnWidths.count
        guard count > 1 else { return count == 1 ? [0] : [] }
        let step = available / Double(count)
        let last = columnWidths[count - 1]
        if columnWidths.dropLast().allSatisfy({ $0 + spacing <= step }), last <= step {
            return (0..<count).map { Double($0) * step }
        }
        let gap = max(spacing, (available - columnWidths.reduce(0, +)) / Double(count - 1))
        var origins: [Double] = []
        var x = 0.0
        for width in columnWidths {
            origins.append(x)
            x += width + gap
        }
        return origins
    }

    /// How many columns of slots fit: the most, up to `maximum`, whose
    /// columns and the spacing between them fit the width. There is always
    /// at least one. At large text sizes the slots are wider, so they reflow
    /// to fewer columns instead of being cut short.
    static func columns(available: Double, slotWidths: [Double], spacing: Double, maximum: Int) -> Int {
        let most = min(max(maximum, 1), max(slotWidths.count, 1))
        guard available.isFinite else { return most }
        for columns in stride(from: most, to: 1, by: -1) {
            let widths = columnWidths(slotWidths: slotWidths, columns: columns)
            if widths.reduce(0, +) + spacing * Double(columns - 1) <= available { return columns }
        }
        return 1
    }
}
