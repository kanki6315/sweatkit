import Foundation

/// A position in degrees.
public struct Coordinate: Hashable, Codable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// One sample at its original timestamp, exactly as recorded. A channel the
/// recorder did not write at this timestamp is nil.
public struct NativeSample: Hashable, Codable, Sendable {
    public var timestamp: Date
    public var position: Coordinate?
    /// Metres.
    public var altitude: Double?
    /// Cumulative metres, as recorded.
    public var distance: Double?
    /// Metres per second.
    public var speed: Double?
    /// Beats per minute.
    public var heartRate: Double?
    /// Watts.
    public var power: Double?
    /// Revolutions per minute on a bike, steps per minute on foot.
    public var cadence: Double?
    /// Degrees Celsius.
    public var temperature: Double?
    /// Metres per running step.
    public var runningStrideLength: Double?
    /// Seconds of contact per step.
    public var runningGroundContactTime: Double?
    /// Metres of vertical displacement per stride.
    public var runningVerticalOscillation: Double?

    public init(
        timestamp: Date,
        position: Coordinate? = nil,
        altitude: Double? = nil,
        distance: Double? = nil,
        speed: Double? = nil,
        heartRate: Double? = nil,
        power: Double? = nil,
        cadence: Double? = nil,
        temperature: Double? = nil,
        runningStrideLength: Double? = nil,
        runningGroundContactTime: Double? = nil,
        runningVerticalOscillation: Double? = nil
    ) {
        self.timestamp = timestamp
        self.position = position
        self.altitude = altitude
        self.distance = distance
        self.speed = speed
        self.heartRate = heartRate
        self.power = power
        self.cadence = cadence
        self.temperature = temperature
        self.runningStrideLength = runningStrideLength
        self.runningGroundContactTime = runningGroundContactTime
        self.runningVerticalOscillation = runningVerticalOscillation

    }
}

/// Every sample of one original, in recorded order. Never altered.
public struct NativeStream: Hashable, Codable, Sendable {
    public var samples: [NativeSample]

    public init(samples: [NativeSample] = []) {
        self.samples = samples
    }
}

/// A timer start or stop, from the file or from a workout's pause events.
public struct TimerEvent: Hashable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case start
        case stop
    }

    public var kind: Kind
    public var timestamp: Date

    public init(kind: Kind, timestamp: Date) {
        self.kind = kind
        self.timestamp = timestamp
    }
}

/// A lap as the device recorded it.
public struct RecordedLap: Hashable, Codable, Sendable {
    public var start: Date
    public var end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }
}

/// What the original states about itself, in a file's session record or a
/// Health workout. Any of it can be absent.
public struct StatedSummary: Hashable, Codable, Sendable {
    public var start: Date?
    public var end: Date?
    /// Seconds.
    public var timerTime: TimeInterval?
    /// Metres.
    public var distance: Double?
    /// Metres.
    public var ascent: Double?
    /// Seconds east of UTC at the start, when the original says.
    public var utcOffset: Int?

    public init(
        start: Date? = nil,
        end: Date? = nil,
        timerTime: TimeInterval? = nil,
        distance: Double? = nil,
        ascent: Double? = nil,
        utcOffset: Int? = nil
    ) {
        self.start = start
        self.end = end
        self.timerTime = timerTime
        self.distance = distance
        self.ascent = ascent
        self.utcOffset = utcOffset
    }
}

/// One original decoded into a common shape. Every source produces this, and
/// the analysis stream is derived from it.
public struct RecordedActivity: Hashable, Codable, Sendable {
    public var sport: Sport
    public var isIndoor: Bool
    /// Virtual rides carry made-up GPS coordinates and open on charts.
    public var isVirtual: Bool
    public var stated: StatedSummary
    /// Empty when the original has no pause events.
    public var timerEvents: [TimerEvent]
    public var laps: [RecordedLap]
    public var stream: NativeStream

    public init(
        sport: Sport,
        isIndoor: Bool = false,
        isVirtual: Bool = false,
        stated: StatedSummary = StatedSummary(),
        timerEvents: [TimerEvent] = [],
        laps: [RecordedLap] = [],
        stream: NativeStream = NativeStream()
    ) {
        self.sport = sport
        self.isIndoor = isIndoor
        self.isVirtual = isVirtual
        self.stated = stated
        self.timerEvents = timerEvents
        self.laps = laps
        self.stream = stream
    }
}
