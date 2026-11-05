import FITSwiftSDK
import Foundation

/// Small FIT files written with the SDK's encoder, so each mapping rule of
/// the decoder can be pinned on a file whose content is known exactly.
///
/// Values are chosen to survive FIT's fixed-point storage unchanged: whole
/// numbers, halves and quarters.
enum SyntheticFIT {
    /// The FIT timestamp of second 0 in these files.
    static let base: UInt32 = 1_100_000_000

    /// Seconds from the Unix epoch to the FIT epoch, 31 December 1989 00:00
    /// UTC. 1970 to 1989 is 20 years with 5 leap days, 7,305 days, less the
    /// one day back from 1 January 1990: 7,304 x 86,400 = 631,065,600.
    static let fitEpoch: TimeInterval = 631_065_600

    /// The FIT timestamp `seconds` after second 0.
    static func time(_ seconds: UInt32) -> DateTime {
        DateTime(timestamp: base + seconds)
    }

    /// The date `seconds` after second 0, worked out without the SDK.
    static func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: fitEpoch + TimeInterval(base) + seconds)
    }

    /// An activity file holding a file ID and then `messages`, in order.
    static func file(_ messages: [Mesg]) throws -> Data {
        let fileID = FileIdMesg()
        try fileID.setType(.activity)
        let encoder = Encoder()
        encoder.write(mesg: fileID)
        encoder.write(mesgs: messages)
        return encoder.close()
    }

    /// A session that starts at second 0. Nil leaves a field out of the message.
    static func session(
        sport: FITSwiftSDK.Sport? = .cycling,
        subSport: SubSport? = .generic,
        hasStartTime: Bool = true,
        elapsed: Double? = 600,
        timer: Double? = 600,
        distance: Double? = nil,
        ascent: UInt16? = nil
    ) throws -> SessionMesg {
        let session = SessionMesg()
        if hasStartTime { try session.setStartTime(time(0)) }
        if let sport { try session.setSport(sport) }
        if let subSport { try session.setSubSport(subSport) }
        if let elapsed { try session.setTotalElapsedTime(elapsed) }
        if let timer { try session.setTotalTimerTime(timer) }
        if let distance { try session.setTotalDistance(distance) }
        if let ascent { try session.setTotalAscent(ascent) }
        return session
    }

    /// A record at `seconds` holding whatever `configure` sets.
    static func record(
        _ seconds: UInt32,
        _ configure: (RecordMesg) throws -> Void = { _ in }
    ) throws -> RecordMesg {
        let record = RecordMesg()
        try record.setTimestamp(time(seconds))
        try configure(record)
        return record
    }

    static func event(_ event: Event, _ type: EventType, at seconds: UInt32) throws -> EventMesg {
        let message = EventMesg()
        try message.setTimestamp(time(seconds))
        try message.setEvent(event)
        try message.setEventType(type)
        return message
    }

    static func lap(start: UInt32, elapsed: Double?) throws -> LapMesg {
        let lap = LapMesg()
        try lap.setStartTime(time(start))
        if let elapsed { try lap.setTotalElapsedTime(elapsed) }
        return lap
    }
}
