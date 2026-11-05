import Foundation
import SweatKitGarmin
import SweatKitModel

/// The summary fields of one Garmin activity that sync compares and keeps.
///
/// Built from a listing entry. Two summaries are equal when every field is
/// equal, and an unequal summary is a metadata change. Absent values stay
/// absent: nil is never read as zero, and nil against a value is a change.
public struct GarminSummary: Sendable, Hashable, Codable {
    public var activityID: Int64
    public var name: String?
    /// Garmin's activity type key, such as `road_biking` or `virtual_ride`.
    public var typeKey: String?
    /// Local start, `yyyy-MM-dd HH:mm:ss`, with no offset.
    public var startTimeLocal: String?
    /// UTC start, `yyyy-MM-dd HH:mm:ss`, with no offset.
    public var startTimeGMT: String?
    /// Timer time, seconds.
    public var duration: Double?
    /// Seconds including pauses.
    public var elapsedDuration: Double?
    public var movingDuration: Double?
    /// Metres.
    public var distance: Double?
    public var manufacturer: String?
    /// Watts.
    public var averagePower: Double?
    public var averageHeartRate: Double?

    public init(
        activityID: Int64,
        name: String? = nil,
        typeKey: String? = nil,
        startTimeLocal: String? = nil,
        startTimeGMT: String? = nil,
        duration: Double? = nil,
        elapsedDuration: Double? = nil,
        movingDuration: Double? = nil,
        distance: Double? = nil,
        manufacturer: String? = nil,
        averagePower: Double? = nil,
        averageHeartRate: Double? = nil
    ) {
        self.activityID = activityID
        self.name = name
        self.typeKey = typeKey
        self.startTimeLocal = startTimeLocal
        self.startTimeGMT = startTimeGMT
        self.duration = duration
        self.elapsedDuration = elapsedDuration
        self.movingDuration = movingDuration
        self.distance = distance
        self.manufacturer = manufacturer
        self.averagePower = averagePower
        self.averageHeartRate = averageHeartRate
    }

    /// From one entry of Garmin's activity search.
    public init(_ entry: ActivitySummary) {
        self.init(
            activityID: entry.activityId,
            name: entry.activityName,
            typeKey: entry.activityType?.typeKey,
            startTimeLocal: entry.startTimeLocal,
            startTimeGMT: entry.startTimeGMT,
            duration: entry.duration,
            elapsedDuration: entry.elapsedDuration,
            movingDuration: entry.movingDuration,
            distance: entry.distance,
            manufacturer: entry.manufacturer,
            averagePower: entry.avgPower,
            averageHeartRate: entry.averageHR
        )
    }

    public var identity: SourceIdentity { .garminActivity(activityID) }

    /// The local start date, which is what Garmin's date filter matches.
    public var startDate: CalendarDate? { startTimeLocal.flatMap(CalendarDate.init(prefixOf:)) }

    /// The start instant, from the UTC start time.
    public var startTime: Date? {
        guard let startTimeGMT else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = startTimeGMT.contains("T") ? "yyyy-MM-dd'T'HH:mm:ss" : "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: String(startTimeGMT.prefix(19)))
    }

    /// The fields whose change means the file is downloaded again: the start,
    /// the duration and the distance. "Duration" covers both timer time and
    /// elapsed time, because a trim can change either.
    public var fileTriggers: FileTriggers {
        FileTriggers(
            startTimeLocal: startTimeLocal,
            startTimeGMT: startTimeGMT,
            duration: duration,
            elapsedDuration: elapsedDuration,
            distance: distance
        )
    }

    public struct FileTriggers: Sendable, Hashable {
        public var startTimeLocal: String?
        public var startTimeGMT: String?
        public var duration: Double?
        public var elapsedDuration: Double?
        public var distance: Double?
    }
}

/// One activity's full summary from Garmin's per-activity endpoint. It carries
/// metadata the listing lacks.
public struct GarminActivityDetail: Sendable, Hashable, Codable {
    public var summary: GarminSummary
    /// As Garmin writes it. Whether it moves when an activity is edited is not
    /// yet known (spec, "Identity and revisions").
    public var lastUpdateDate: String?
    public var uploadedDate: String?
    public var isOriginal: Bool?
    public var fileFormat: String?

    public init(summary: GarminSummary, lastUpdateDate: String? = nil, uploadedDate: String? = nil, isOriginal: Bool? = nil, fileFormat: String? = nil) {
        self.summary = summary
        self.lastUpdateDate = lastUpdateDate
        self.uploadedDate = uploadedDate
        self.isOriginal = isOriginal
        self.fileFormat = fileFormat
    }

    public init(_ detail: ActivityDetail) {
        self.init(
            summary: GarminSummary(
                activityID: detail.activityId,
                name: detail.activityName,
                typeKey: detail.activityTypeDTO?.typeKey,
                startTimeLocal: detail.summaryDTO?.startTimeLocal,
                startTimeGMT: detail.summaryDTO?.startTimeGMT,
                duration: detail.summaryDTO?.duration,
                elapsedDuration: detail.summaryDTO?.elapsedDuration,
                movingDuration: detail.summaryDTO?.movingDuration,
                distance: detail.summaryDTO?.distance,
                manufacturer: detail.metadataDTO?.manufacturer
            ),
            lastUpdateDate: detail.metadataDTO?.lastUpdateDate,
            uploadedDate: detail.metadataDTO?.uploadedDate,
            isOriginal: detail.metadataDTO?.isOriginal,
            fileFormat: detail.metadataDTO?.fileFormat?.formatKey
        )
    }
}

extension SourceIdentity {
    /// The identity of the Garmin activity with this ID: Garmin plus the activity ID.
    public static func garminActivity(_ id: Int64) -> SourceIdentity {
        SourceIdentity(source: .garmin, externalID: String(id))
    }

    /// The Garmin activity ID, for a Garmin identity.
    public var garminActivityID: Int64? {
        source == .garmin ? Int64(externalID) : nil
    }
}
