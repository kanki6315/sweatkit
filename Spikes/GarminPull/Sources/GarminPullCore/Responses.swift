import Foundation

/// The token endpoint's body is not documented. This accepts the common OAuth2
/// spellings and keeps the key names it saw, so a live run can report the real
/// shape without printing the token.
public struct TokenResponse: Sendable {
    public var accessToken: String
    /// Seconds until expiry, when the body states it.
    public var expiresIn: Double?
    public var tokenType: String?
    /// Every top-level key in the body, sorted. Values are never kept here.
    public var keys: [String]

    public enum ParseError: Error, CustomStringConvertible {
        case notJSONObject
        case noTokenField(keys: [String])

        public var description: String {
            switch self {
            case .notJSONObject: "Token response is not a JSON object."
            case .noTokenField(let keys): "Token response has no recognised token field. Keys: \(keys.joined(separator: ", "))"
            }
        }
    }

    public static func parse(_ data: Data) throws -> TokenResponse {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ParseError.notJSONObject
        }
        let keys = object.keys.sorted()
        let token = ["access_token", "accessToken", "token"].lazy.compactMap { object[$0] as? String }.first
        guard let token, !token.isEmpty else { throw ParseError.noTokenField(keys: keys) }
        let expiresIn = ["expires_in", "expiresIn"].lazy.compactMap { (object[$0] as? NSNumber)?.doubleValue }.first
        let tokenType = ["token_type", "tokenType"].lazy.compactMap { object[$0] as? String }.first
        return TokenResponse(accessToken: token, expiresIn: expiresIn, tokenType: tokenType, keys: keys)
    }
}

/// The fields of `SummarizedActivityDTO` the spike reports. Every field is
/// optional because the OpenAPI document marks none as required.
public struct ActivityListEntry: Sendable, Decodable, Equatable {
    public struct ActivityType: Sendable, Decodable, Equatable {
        public var typeId: Int64?
        public var typeKey: String?
        public var parentTypeId: Int64?
    }

    public var activityId: Int64
    public var activityName: String?
    public var startTimeLocal: String?
    public var startTimeGMT: String?
    public var activityType: ActivityType?
    public var distance: Double?
    public var duration: Double?
    public var elapsedDuration: Double?
    public var manufacturer: String?
    public var avgPower: Double?
    public var averageHR: Double?
    public var hasPolyline: Bool?
    public var parentId: Int64?

    public var startDate: CalendarDate? { startTimeLocal.flatMap(CalendarDate.init(prefixOf:)) }

    public static func decodeList(_ data: Data) throws -> [ActivityListEntry] {
        try JSONDecoder().decode([ActivityListEntry].self, from: data)
    }
}

/// The fields of `ActivitySummaryDTO` the spike reports. `metadataDTO` holds
/// `isOriginal`, the file format and `lastUpdateDate`, none of which the list has.
public struct ActivityDetail: Sendable, Decodable, Equatable {
    public struct ActivityType: Sendable, Decodable, Equatable {
        public var typeKey: String?
        public var parentTypeId: Int64?
    }

    public struct Summary: Sendable, Decodable, Equatable {
        public var startTimeLocal: String?
        public var startTimeGMT: String?
        public var distance: Double?
        public var duration: Double?
        public var elapsedDuration: Double?
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

    public static func decode(_ data: Data) throws -> ActivityDetail {
        try JSONDecoder().decode(ActivityDetail.self, from: data)
    }
}
