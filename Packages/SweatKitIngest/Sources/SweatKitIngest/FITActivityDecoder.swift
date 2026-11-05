import FITSwiftSDK
import Foundation
import SweatKitModel

/// Reads a FIT activity file into a `RecordedActivity` with Garmin's FIT SDK.
///
/// Nothing is cleaned or filled here. The result is the file's own content in
/// the common shape, and `StreamNormaliser` derives the analysis stream from it.
public enum FITActivityDecoder {
    /// The size in bytes of the smallest FIT header. Data shorter than this
    /// cannot be recognised as FIT.
    public static let smallestHeaderSize = 12

    /// The size in bytes of a FIT header that ends with its own checksum. A
    /// header is this or `smallestHeaderSize`, and says which in its first byte.
    public static let headerSizeWithChecksum = 14

    /// The size in bytes of the checksum that closes a FIT file.
    public static let fileChecksumSize = 2

    /// Where the header holds the size of the data section, as a
    /// little-endian 32-bit count of bytes.
    static let dataSizeBytes = 4..<8

    /// Where the header holds its signature.
    static let signatureBytes = 8..<12

    /// The signature every FIT header holds.
    static let signature = Array(".FIT".utf8)

    /// The smallest FIT timestamp that is a date. The FIT profile reads
    /// anything below it as a count of seconds since power-up.
    static let smallestAbsoluteTimestamp: UInt32 = 0x1000_0000

    /// Degrees per semicircle, the unit FIT stores positions in: 180 / 2^31.
    public static let degreesPerSemicircle = 180.0 / 2_147_483_648.0

    /// Seconds from the Unix epoch to the FIT epoch, 31 December 1989 00:00 UTC.
    public static let fitEpochOffset: TimeInterval = 631_065_600

    /// The sub-sports the FIT profile names as indoor, and virtual activity,
    /// which is ridden indoors.
    static let indoorSubSports: Set<SubSport> = [
        .treadmill, .spin, .indoorCycling, .indoorRowing, .indoorSkiing, .indoorWalking,
        .indoorRunning, .indoorClimbing, .indoorGrinding, .indoorWheelchairWalk,
        .indoorWheelchairRun, .indoorHandCycling, .virtualActivity,
    ]

    /// Steps in one stride. A FIT file counts on-foot cadence in strides of
    /// one foot.
    static let stepsPerStride = 2.0

    /// The timer event types that stop the timer.
    static let stopEventTypes: Set<EventType> = [.stop, .stopAll, .stopDisable, .stopDisableAll]

    /// Decodes one FIT activity file.
    ///
    /// The file is checked before anything is read from it, in the order of
    /// `FITDecodeError`'s cases, so a corrupt, truncated or non-FIT file is
    /// rejected whole and never half-decoded.
    ///
    /// The spec does not cover bytes that follow a sound FIT file. The SDK
    /// reads on past the first file's checksum, so a second FIT file chained
    /// after the first is read too and its messages follow the first file's,
    /// while anything else there is `.corrupt`.
    ///
    /// **Session.** The first session message describes the activity. The spec
    /// is silent on files with several sessions, so the rest are ignored.
    ///
    /// - Sport: FIT cycling, walking, running and hiking map to the same
    ///   `Sport`. Every other sport, and a session with no sport, is `.other`.
    /// - `isVirtual`: the sub-sport is virtual activity.
    /// - `isIndoor`: the sub-sport is one the FIT profile names as indoor
    ///   (treadmill, spin, indoor cycling, indoor rowing, indoor skiing,
    ///   indoor walking, indoor running, indoor climbing, indoor grinding,
    ///   the indoor wheelchair and hand-cycling sub-sports) or is virtual
    ///   activity. The spec does not say what sets the indoor flag for a
    ///   file, and it lists "virtual and indoor" side by side. A virtual ride
    ///   is ridden indoors, so it is taken as both.
    /// - `stated.start`: the session's start time.
    /// - `stated.end`: the start plus the session's total elapsed time, nil
    ///   when either is absent. The session's own timestamp is not used:
    ///   Garmin devices write the start time there.
    /// - `stated.timerTime`, `stated.distance`, `stated.ascent`: the
    ///   session's total timer time, total distance and total ascent.
    /// - `stated.utcOffset`: the activity message's local timestamp minus its
    ///   timestamp. The session message does not hold a time zone, so this is
    ///   the one field read from elsewhere. It is nil when there is no
    ///   activity message, or when either value is below the FIT profile's
    ///   smallest absolute date-time, as in Zwift files, which write 0.
    ///
    /// **Timer events.** Event messages whose event is timer, in file order.
    /// Event type start is a start. Stop, stop all, stop disable and stop
    /// disable all are a stop. Any other event or event type, and an event
    /// with no timestamp, is left out.
    ///
    /// **Laps.** One `RecordedLap` per lap message that has a start time and a
    /// total elapsed time, in file order. Its end is the start plus the
    /// elapsed time, as for the session.
    ///
    /// **Records.** One `NativeSample` per record message that has a
    /// timestamp, in file order. A record with no timestamp cannot be placed
    /// and is left out.
    ///
    /// - Position: latitude and longitude in degrees, converted from
    ///   semicircles. Nil unless the record has both.
    /// - Altitude and speed: the enhanced field when the record has it,
    ///   otherwise the plain field.
    /// - Distance, heart rate, power and temperature: as recorded. A recorded
    ///   zero is 0, and a field the record does not hold is nil.
    /// - Cadence: the cadence field plus the fractional cadence field when
    ///   the record has one. On a bike that is revolutions per minute. On
    ///   foot a FIT file counts the strides of one foot, so the sum is
    ///   doubled to give steps per minute. Nil when the record has no
    ///   cadence field.
    public static func decode(_ data: Data) throws(FITDecodeError) -> RecordedActivity {
        // The SDK reads by offsets from zero, and a slice of a larger `Data`
        // keeps its parent's indices, so the bytes are copied to start at 0.
        let file = data.startIndex == 0 ? data : Data(data)
        try checkLength(of: file)

        let messages = Messages()
        do {
            guard try Decoder(stream: InputStream(data: file)).checkIntegrity() else {
                throw FITDecodeError.corrupt
            }
            let decoder = Decoder(stream: InputStream(data: file))
            decoder.addMesgListener(messages)
            try decoder.read()
        } catch {
            throw .corrupt
        }

        guard let session = messages.sessions.first else { throw .noActivity }
        let subSport = session.getSubSport()
        let activitySport = sport(session.getSport())
        return RecordedActivity(
            sport: activitySport,
            isIndoor: subSport.map(indoorSubSports.contains) ?? false,
            isVirtual: subSport == .virtualActivity,
            stated: stated(session: session, activity: messages.activities.first),
            timerEvents: messages.events.compactMap(timerEvent),
            laps: messages.laps.compactMap(lap),
            stream: NativeStream(samples: messages.records.compactMap { sample($0, sport: activitySport) })
        )
    }

    // MARK: Checks

    /// Throws `.notFIT` when the data does not open with a FIT header, and
    /// `.truncated` when it is shorter than that header says it should be.
    ///
    /// The header is read here and not by the SDK, whose own check calls a
    /// file cut down to its header "not FIT", where it is a truncated one.
    private static func checkLength(of file: Data) throws(FITDecodeError) {
        guard file.count >= smallestHeaderSize else { throw .notFIT }
        let header = [UInt8](file.prefix(smallestHeaderSize))
        let headerSize = Int(header[0])
        guard headerSize == smallestHeaderSize || headerSize == headerSizeWithChecksum else {
            throw .notFIT
        }
        guard Array(header[signatureBytes]) == signature else { throw .notFIT }

        // Little-endian, so the last byte is the most significant.
        let dataSize = header[dataSizeBytes].reversed().reduce(0) { $0 << 8 | Int($1) }
        guard file.count >= headerSize + dataSize + fileChecksumSize else { throw .truncated }
    }

    // MARK: Mapping

    private static func sport(_ sport: FITSwiftSDK.Sport?) -> SweatKitModel.Sport {
        switch sport {
        case .cycling: .cycling
        case .walking: .walking
        case .running: .running
        case .hiking: .hiking
        default: .other
        }
    }

    private static func stated(session: SessionMesg, activity: ActivityMesg?) -> StatedSummary {
        let start = session.getStartTime().map(date)
        return StatedSummary(
            start: start,
            end: end(start: start, elapsed: session.getTotalElapsedTime()),
            timerTime: session.getTotalTimerTime(),
            distance: session.getTotalDistance(),
            ascent: session.getTotalAscent().map(Double.init),
            utcOffset: activity.flatMap(utcOffset)
        )
    }

    /// The local timestamp minus the timestamp, or nil unless both are dates.
    private static func utcOffset(_ activity: ActivityMesg) -> Int? {
        guard let local = activity.getLocalTimestamp(), local >= smallestAbsoluteTimestamp,
              let utc = activity.getTimestamp()?.timestamp, utc >= smallestAbsoluteTimestamp
        else { return nil }
        return Int(local) - Int(utc)
    }

    private static func timerEvent(_ event: EventMesg) -> TimerEvent? {
        guard event.getEvent() == .timer, let type = event.getEventType(),
              let timestamp = event.getTimestamp()
        else { return nil }
        if type == .start {
            return TimerEvent(kind: .start, timestamp: date(timestamp))
        }
        if stopEventTypes.contains(type) {
            return TimerEvent(kind: .stop, timestamp: date(timestamp))
        }
        return nil
    }

    private static func lap(_ lap: LapMesg) -> RecordedLap? {
        let start = lap.getStartTime().map(date)
        guard let start, let end = end(start: start, elapsed: lap.getTotalElapsedTime()) else {
            return nil
        }
        return RecordedLap(start: start, end: end)
    }

    private static func sample(_ record: RecordMesg, sport: SweatKitModel.Sport) -> NativeSample? {
        guard let timestamp = record.getTimestamp() else { return nil }
        var position: Coordinate?
        if let latitude = record.getPositionLat(), let longitude = record.getPositionLong() {
            position = Coordinate(
                latitude: Double(latitude) * degreesPerSemicircle,
                longitude: Double(longitude) * degreesPerSemicircle
            )
        }
        return NativeSample(
            timestamp: date(timestamp),
            position: position,
            altitude: record.getEnhancedAltitude() ?? record.getAltitude(),
            distance: record.getDistance(),
            speed: record.getEnhancedSpeed() ?? record.getSpeed(),
            heartRate: record.getHeartRate().map(Double.init),
            power: record.getPower().map(Double.init),
            cadence: cadence(of: record, sport: sport),
            temperature: record.getTemperature().map(Double.init)
        )
    }

    /// Revolutions per minute on a bike, steps per minute on foot.
    private static func cadence(of record: RecordMesg, sport: SweatKitModel.Sport) -> Double? {
        guard let whole = record.getCadence() else { return nil }
        let cycles = Double(whole) + (record.getFractionalCadence() ?? 0)
        return sport.family == .onFoot ? cycles * stepsPerStride : cycles
    }

    /// The start plus the elapsed time, or nil when either is absent.
    private static func end(start: Date?, elapsed: Double?) -> Date? {
        guard let start, let elapsed else { return nil }
        return start.addingTimeInterval(elapsed)
    }

    /// A FIT timestamp, seconds since the FIT epoch, as a date. The SDK's own
    /// conversion adds in 32 bits and overflows on timestamps near the top of
    /// the range.
    private static func date(_ time: DateTime) -> Date {
        Date(timeIntervalSince1970: fitEpochOffset + TimeInterval(time.timestamp))
    }
}

/// Keeps the five kinds of message the decoder maps, in file order, and lets
/// the rest of the file go by.
private final class Messages: MesgListener {
    var sessions: [SessionMesg] = []
    var activities: [ActivityMesg] = []
    var events: [EventMesg] = []
    var laps: [LapMesg] = []
    var records: [RecordMesg] = []

    func onMesg(_ mesg: Mesg) {
        switch mesg.mesgNum {
        case Profile.MesgNum.session: sessions.append(SessionMesg(mesg: mesg))
        case Profile.MesgNum.activity: activities.append(ActivityMesg(mesg: mesg))
        case Profile.MesgNum.event: events.append(EventMesg(mesg: mesg))
        case Profile.MesgNum.lap: laps.append(LapMesg(mesg: mesg))
        case Profile.MesgNum.record: records.append(RecordMesg(mesg: mesg))
        default: break
        }
    }
}
