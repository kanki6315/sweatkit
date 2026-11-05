import Foundation

/// How a value on the analysis grid came to be. Missing is never zero: a
/// recorded 0 W while coasting is measured, and no reading is missing.
public enum SampleQuality: UInt8, Codable, Sendable {
    case measured
    case interpolated
    case missing
}

/// One channel on the 1 Hz grid: a value and a quality for every second.
public struct Series: Hashable, Codable, Sendable {
    public private(set) var values: [Double]
    public private(set) var quality: [SampleQuality]

    /// Values at missing seconds are ignored and stored as 0.
    public init(values: [Double], quality: [SampleQuality]) {
        precondition(values.count == quality.count, "A series needs one quality per value")
        self.values = zip(values, quality).map { $1 == .missing ? 0 : $0 }
        self.quality = quality
    }

    /// Every non-nil value is measured and every nil is missing.
    public init(_ samples: [Double?]) {
        self.values = samples.map { $0 ?? 0 }
        self.quality = samples.map { $0 == nil ? .missing : .measured }
    }

    public init(missingCount count: Int) {
        self.values = Array(repeating: 0, count: count)
        self.quality = Array(repeating: .missing, count: count)
    }

    public var count: Int { values.count }

    /// The value at second `index`, or nil when it is missing.
    public subscript(index: Int) -> Double? {
        quality[index] == .missing ? nil : values[index]
    }
}

/// The channels of the analysis stream.
public enum Channel: String, Codable, Sendable, CaseIterable {
    case latitude
    case longitude
    case altitude
    case distance
    case speed
    case heartRate
    case power
    case cadence
    case temperature
    case gradient
}

/// Where the timer was paused, when the original says.
public enum PauseData: Hashable, Codable, Sendable {
    /// Pause data is complete, or the activity is treated as unpaused. The
    /// spans are half-open ranges of grid seconds, sorted and non-overlapping.
    case known(paused: [Range<Int>])
    /// Pause data is incomplete, so pause positions are unknown. Only the
    /// stated timer time, if any, is left.
    case unknown(statedTimerTime: TimeInterval?)
}

/// The per-second stream every screen and metric reads.
///
/// A 1 Hz grid over elapsed time, starting at the activity start. The sample
/// at second t describes the interval from t to t + 1, so a duration is a
/// count of samples. Paused spans stay on the grid. It is derived from a
/// `RecordedActivity` under the versioned stream rules and can always be
/// rebuilt.
public struct AnalysisStream: Hashable, Codable, Sendable {
    /// The version of the stream rules that built this stream.
    public var rulesVersion: Int
    public var start: Date
    /// Elapsed seconds, which is the length of every channel.
    public var count: Int
    public var pauses: PauseData

    /// Latitude and longitude share one quality per second.
    public var latitude: Series
    public var longitude: Series
    /// Metres.
    public var altitude: Series
    /// Cumulative metres.
    public var distance: Series
    /// Metres per second.
    public var speed: Series
    /// Beats per minute.
    public var heartRate: Series
    /// Watts.
    public var power: Series
    public var cadence: Series
    /// Degrees Celsius.
    public var temperature: Series
    /// Rise over run, so 0.05 is a 5% climb.
    public var gradient: Series

    /// A stream of `count` seconds with every channel missing.
    public init(rulesVersion: Int, start: Date, count: Int, pauses: PauseData = .known(paused: [])) {
        self.rulesVersion = rulesVersion
        self.start = start
        self.count = count
        self.pauses = pauses
        let empty = Series(missingCount: count)
        self.latitude = empty
        self.longitude = empty
        self.altitude = empty
        self.distance = empty
        self.speed = empty
        self.heartRate = empty
        self.power = empty
        self.cadence = empty
        self.temperature = empty
        self.gradient = empty
    }

    public subscript(channel: Channel) -> Series {
        get {
            switch channel {
            case .latitude: latitude
            case .longitude: longitude
            case .altitude: altitude
            case .distance: distance
            case .speed: speed
            case .heartRate: heartRate
            case .power: power
            case .cadence: cadence
            case .temperature: temperature
            case .gradient: gradient
            }
        }
        set {
            switch channel {
            case .latitude: latitude = newValue
            case .longitude: longitude = newValue
            case .altitude: altitude = newValue
            case .distance: distance = newValue
            case .speed: speed = newValue
            case .heartRate: heartRate = newValue
            case .power: power = newValue
            case .cadence: cadence = newValue
            case .temperature: temperature = newValue
            case .gradient: gradient = newValue
            }
        }
    }

    /// The position at second `index`, or nil when it is missing.
    public func coordinate(at index: Int) -> Coordinate? {
        guard let latitude = latitude[index], let longitude = longitude[index] else { return nil }
        return Coordinate(latitude: latitude, longitude: longitude)
    }

    /// Whether every channel has exactly `count` seconds.
    public var isConsistent: Bool {
        Channel.allCases.allSatisfy { self[$0].count == count }
    }
}
