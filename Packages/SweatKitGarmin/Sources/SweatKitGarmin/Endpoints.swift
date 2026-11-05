import Foundation

/// Builds the Personal API requests, from Garmin's Personal API page, its FAQ
/// and the OpenAPI document behind its endpoint reference (opened 4 November 2026).
///
/// The `Authorization` value is set on each request and nowhere else. Use
/// `GarminExchange.target` or `loggable(_:)` to describe a request.
public struct GarminEndpoints: Sendable {
    public var host: String

    public init(host: String = "personal.connectapi.garmin.com") {
        self.host = host
    }

    /// `POST /personalapitoken-service/personal-api/personal-api-key/token` with
    /// `Authorization: ApiKey <key>`. This endpoint is on the Personal API page
    /// and FAQ but not in the OpenAPI document. Sent like the documented curl
    /// command, with `Accept: */*`: an `application/json` Accept gets a 406.
    public func token(apiKey: String) throws(GarminError) -> URLRequest {
        var request = URLRequest(url: try url("/personalapitoken-service/personal-api/personal-api-key/token"))
        request.httpMethod = "POST"
        request.setValue("ApiKey \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        return request
    }

    /// `GET /activitylist-service/activities/search/activities`.
    public func activities(_ query: ActivityQuery, accessToken: String) throws(GarminError) -> URLRequest {
        guard query.start >= 0, query.limit > 0 else { throw .invalidRequest }
        if let startDate = query.startDate, let endDate = query.endDate, endDate < startDate { throw .invalidRequest }
        return authorized(URLRequest(url: try url("/activitylist-service/activities/search/activities", query: query.queryItems)), accessToken: accessToken, accept: "application/json")
    }

    /// `GET /activity-service/activity/{activityId}`.
    public func activity(id: Int64, accessToken: String) throws(GarminError) -> URLRequest {
        authorized(URLRequest(url: try url("/activity-service/activity/\(id)")), accessToken: accessToken, accept: "application/json")
    }

    /// `GET /download-service/files/activity/{activityId}`, documented as the
    /// activity file "in its original format" with content type
    /// `application/x-zip-compressed`.
    public func originalFile(activityID: Int64, accessToken: String) throws(GarminError) -> URLRequest {
        authorized(URLRequest(url: try url("/download-service/files/activity/\(activityID)")), accessToken: accessToken, accept: "*/*")
    }

    private func url(_ path: String, query: [URLQueryItem]? = nil) throws(GarminError) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = path
        components.queryItems = query
        guard let url = components.url else { throw .invalidRequest }
        return url
    }

    /// The FAQ says Connect APIs take "OAuth2 access tokens" but does not name
    /// the scheme. M0's live run confirmed `Bearer`.
    private func authorized(_ request: URLRequest, accessToken: String, accept: String) -> URLRequest {
        var request = request
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        return request
    }
}

/// The activity search's filters. Garmin's defaults are `start=0`, `limit=99`,
/// descending order by local start time, and child activities excluded.
public struct ActivityQuery: Sendable, Hashable {
    public enum Order: String, Sendable, Hashable {
        case ascending = "asc"
        case descending = "desc"
    }

    /// Zero-based offset of the first activity.
    public var start: Int
    public var limit: Int
    public var order: Order
    /// Inclusive earliest local start date.
    public var startDate: CalendarDate?
    /// Inclusive latest local start date.
    public var endDate: CalendarDate?

    public static let defaultLimit = 99

    public init(start: Int = 0, limit: Int = ActivityQuery.defaultLimit, order: Order = .descending, startDate: CalendarDate? = nil, endDate: CalendarDate? = nil) {
        self.start = start
        self.limit = limit
        self.order = order
        self.startDate = startDate
        self.endDate = endDate
    }

    /// The newest page.
    public static let newest = ActivityQuery()

    /// The single earliest activity.
    public static let earliest = ActivityQuery(limit: 1, order: .ascending)

    /// The page after this one.
    public var nextPage: ActivityQuery {
        var next = self
        next.start += limit
        return next
    }

    var queryItems: [URLQueryItem] {
        var items = [
            URLQueryItem(name: "start", value: String(start)),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "sortOrder", value: order.rawValue),
        ]
        if let startDate { items.append(URLQueryItem(name: "startDate", value: startDate.description)) }
        if let endDate { items.append(URLQueryItem(name: "endDate", value: endDate.description)) }
        return items
    }
}

/// A local calendar date, written `yyyy-MM-dd` as the search endpoint expects.
public struct CalendarDate: Sendable, Hashable, Comparable, Codable, CustomStringConvertible {
    public var year: Int
    public var month: Int
    public var day: Int

    public init?(year: Int, month: Int, day: Int) {
        guard (1...9999).contains(year), (1...12).contains(month), (1...31).contains(day) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
        let components = DateComponents(year: year, month: month, day: day)
        guard components.isValidDate(in: calendar) else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Reads the date part of `yyyy-MM-dd`, `yyyy-MM-dd HH:mm:ss` or
    /// `yyyy-MM-ddTHH:mm:ss`, as Garmin writes local start times.
    public init?(prefixOf text: String) {
        let parts = text.prefix(10).split(separator: "-", omittingEmptySubsequences: false)
        guard text.count >= 10, parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else { return nil }
        self.init(year: year, month: month, day: day)
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public static func < (lhs: CalendarDate, rhs: CalendarDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}
