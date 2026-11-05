import Foundation

/// An access token and when the client treats it as expired. The token value is
/// kept out of `description` so it cannot reach a log by accident.
struct AccessToken: Sendable, CustomStringConvertible {
    /// Tokens last "24 hours or until the Personal API key expires, whichever
    /// occurs first" (Personal API FAQ). Used when the response states no lifetime.
    static let documentedLifetime: TimeInterval = 24 * 60 * 60

    var value: String
    var expiresAt: Date
    /// The response body's top-level key names, for diagnosing an unknown shape.
    var keys: [String]

    var description: String { "AccessToken(expires \(expiresAt))" }

    /// The key name reported when the body is a bare token rather than an object.
    static let bareTokenKey = "<bare token>"

    /// Garmin does not document the token response body. M0's live run got the
    /// token as `text/plain` with no stated lifetime, so the documented lifetime
    /// applies. A JSON string, or a JSON object with the common OAuth2 spellings,
    /// is also accepted in case the format changes.
    static func parse(_ data: Data, status: Int, now: Date) throws(GarminError) -> AccessToken {
        let parsed = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
        if let bare = (parsed as? String) ?? (parsed == nil ? String(data: data, encoding: .utf8) : nil) {
            let value = bare.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, value.unicodeScalars.allSatisfy({ $0.value > 0x20 && $0.value < 0x7F }) else {
                throw .unexpectedResponse(UnexpectedResponse(status: status, reason: .undecodableBody))
            }
            return AccessToken(value: value, expiresAt: now.addingTimeInterval(documentedLifetime), keys: [bareTokenKey])
        }
        guard let object = parsed as? [String: Any] else {
            throw .unexpectedResponse(UnexpectedResponse(status: status, reason: .undecodableBody))
        }
        let keys = object.keys.sorted()
        guard let value = ["access_token", "accessToken", "token"].lazy.compactMap({ object[$0] as? String }).first(where: { !$0.isEmpty }) else {
            throw .unexpectedResponse(UnexpectedResponse(status: status, reason: .noTokenField(keys: keys)))
        }
        let stated = ["expires_in", "expiresIn"].lazy.compactMap { key -> TimeInterval? in
            if let number = object[key] as? NSNumber { return number.doubleValue }
            if let text = object[key] as? String { return TimeInterval(text) }
            return nil
        }.first
        let lifetime = stated.flatMap { $0 > 0 ? $0 : nil } ?? documentedLifetime
        return AccessToken(value: value, expiresAt: now.addingTimeInterval(lifetime), keys: keys)
    }
}

/// One entry of the activity search, from `SummarizedActivityDTO`. Every field
/// but the ID is optional because the OpenAPI document marks none as required,
/// and absent values stay absent rather than becoming zero.
public struct ActivitySummary: Sendable, Decodable, Equatable {
    public struct ActivityType: Sendable, Decodable, Equatable {
        public var typeId: Int64?
        public var typeKey: String?
        public var parentTypeId: Int64?
    }

    public var activityId: Int64
    public var activityName: String?
    /// Local start, `yyyy-MM-dd HH:mm:ss` with no offset.
    public var startTimeLocal: String?
    /// UTC start, `yyyy-MM-dd HH:mm:ss` with no offset.
    public var startTimeGMT: String?
    /// UTC start in milliseconds since 1970.
    public var beginTimestamp: Int64?
    public var activityType: ActivityType?
    /// Metres.
    public var distance: Double?
    /// Timer time in seconds.
    public var duration: Double?
    /// Seconds, including pauses.
    public var elapsedDuration: Double?
    public var movingDuration: Double?
    public var manufacturer: String?
    /// Watts.
    public var avgPower: Double?
    public var averageHR: Double?
    public var hasPolyline: Bool?
    public var parentId: Int64?

    /// The local start date, which is what the search's date filters match.
    public var startDate: CalendarDate? { startTimeLocal.flatMap(CalendarDate.init(prefixOf:)) }

    /// The start instant, from `beginTimestamp`.
    public var startTime: Date? { beginTimestamp.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) } }
}

/// One activity's full summary, from `ActivitySummaryDTO`. Its `metadataDTO`
/// holds fields the search entries lack, such as `lastUpdateDate`.
public struct ActivityDetail: Sendable, Decodable, Equatable {
    public struct ActivityType: Sendable, Decodable, Equatable {
        public var typeId: Int64?
        public var typeKey: String?
        public var parentTypeId: Int64?
    }

    public struct Summary: Sendable, Decodable, Equatable {
        public var startTimeLocal: String?
        public var startTimeGMT: String?
        public var distance: Double?
        public var duration: Double?
        public var elapsedDuration: Double?
        public var movingDuration: Double?
    }

    public struct Metadata: Sendable, Decodable, Equatable {
        public struct FileFormat: Sendable, Decodable, Equatable {
            public var formatId: Int64?
            public var formatKey: String?
        }

        public var isOriginal: Bool?
        public var fileFormat: FileFormat?
        public var lastUpdateDate: String?
        public var uploadedDate: String?
        public var manufacturer: String?
        public var trimmed: Bool?
    }

    public var activityId: Int64
    public var activityName: String?
    public var activityTypeDTO: ActivityType?
    public var summaryDTO: Summary?
    public var metadataDTO: Metadata?

    public var startDate: CalendarDate? { summaryDTO?.startTimeLocal.flatMap(CalendarDate.init(prefixOf:)) }
}

/// An activity's file exactly as Garmin served it. Documented as a zip holding
/// the original; this client does not open it.
public struct ActivityFile: Sendable, Equatable {
    public var activityID: Int64
    public var data: Data
    public var contentType: String?
    /// The file name from `Content-Disposition`, when given.
    public var suggestedFilename: String?
}
