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

    /// Degrees per semicircle, the unit FIT stores positions in: 180 / 2^31.
    public static let degreesPerSemicircle = 180.0 / 2_147_483_648.0

    /// Seconds from the Unix epoch to the FIT epoch, 31 December 1989 00:00 UTC.
    public static let fitEpochOffset: TimeInterval = 631_065_600

    /// Decodes one FIT activity file.
    ///
    /// The file is checked before anything is read from it, in the order of
    /// `FITDecodeError`'s cases, so a corrupt, truncated or non-FIT file is
    /// rejected whole and never half-decoded.
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
    /// - Distance, heart rate, power, cadence and temperature: as recorded. A
    ///   recorded zero is 0, and a field the record does not hold is nil.
    /// - Cadence is the cadence field alone. Fractional cadence is not added,
    ///   and on-foot cadence is not doubled, although Garmin devices count
    ///   one foot. The spec does not cover either, so the value stays as
    ///   recorded.
    public static func decode(_ data: Data) throws(FITDecodeError) -> RecordedActivity {
        fatalError("unimplemented")
    }
}
