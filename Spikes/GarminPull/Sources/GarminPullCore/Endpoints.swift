import Foundation

/// Builds every request the spike makes, from Garmin's Personal API pages and
/// the OpenAPI document behind its Swagger page (opened 4 November 2026).
public struct Endpoints: Sendable {
    public static let production = URL(string: "https://personal.connectapi.garmin.com")!

    public var base: URL

    public init(base: URL = Endpoints.production) {
        self.base = base
    }

    /// `POST /personalapitoken-service/personal-api/personal-api-key/token` with
    /// `Authorization: ApiKey <key>`. From the Personal API page and its FAQ; this
    /// endpoint is not in the OpenAPI document, and neither is its response body.
    public func token(apiKey: String) -> URLRequest {
        var request = URLRequest(url: base.appending(path: "personalapitoken-service/personal-api/personal-api-key/token"))
        request.httpMethod = "POST"
        request.setValue("ApiKey \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    /// `GET /activitylist-service/activities/search/activities`.
    /// The documented defaults are `start=0`, `limit=99`, `sortOrder=desc`,
    /// `sortBy=startLocal` and `excludeChildren=true`. `startDate` and `endDate`
    /// are inclusive local calendar dates.
    public func search(_ query: ActivitySearch, accessToken: String) -> URLRequest {
        var components = URLComponents(url: base.appending(path: "activitylist-service/activities/search/activities"), resolvingAgainstBaseURL: false)!
        components.queryItems = query.queryItems
        return authorized(URLRequest(url: components.url!), accessToken: accessToken, accept: "application/json")
    }

    /// `GET /activity-service/activity/{activityId}`, the full summary with `metadataDTO`.
    public func activity(id: Int64, accessToken: String) -> URLRequest {
        authorized(URLRequest(url: base.appending(path: "activity-service/activity/\(id)")), accessToken: accessToken, accept: "application/json")
    }

    /// `GET /download-service/files/activity/{activityId}`. Documented as "an
    /// activity file in its original format" with content type
    /// `application/x-zip-compressed`, so the FIT file is expected inside a zip.
    public func download(id: Int64, accessToken: String) -> URLRequest {
        authorized(URLRequest(url: base.appending(path: "download-service/files/activity/\(id)")), accessToken: accessToken, accept: "*/*")
    }

    /// The FAQ says Connect APIs take "OAuth2 access tokens" but neither page names
    /// the scheme; `Bearer` is the OAuth2 default and is assumed until a live run.
    private func authorized(_ request: URLRequest, accessToken: String, accept: String) -> URLRequest {
        var request = request
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        return request
    }
}

public struct ActivitySearch: Sendable, Equatable {
    public enum Order: String, Sendable { case ascending = "asc", descending = "desc" }

    public var start = 0
    public var limit = 99
    public var order: Order = .descending
    public var startDate: CalendarDate?
    public var endDate: CalendarDate?

    public init(start: Int = 0, limit: Int = 99, order: Order = .descending, startDate: CalendarDate? = nil, endDate: CalendarDate? = nil) {
        self.start = start
        self.limit = limit
        self.order = order
        self.startDate = startDate
        self.endDate = endDate
    }

    /// The newest page, as a quick sync would start.
    public static let newest = ActivitySearch()
    /// One entry in ascending order: the earliest activity, which starts the backfill.
    public static let earliest = ActivitySearch(limit: 1, order: .ascending)

    /// Every activity whose local start date is in `month`, newest first.
    public static func month(_ month: CalendarMonth, start: Int = 0) -> ActivitySearch {
        ActivitySearch(start: start, startDate: month.firstDay, endDate: month.lastDay)
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

/// A request with its `Authorization` value hidden, safe to print or log.
public func redacted(_ request: URLRequest) -> String {
    let method = request.httpMethod ?? "GET"
    let target = request.url.map { url in
        url.query.map { "\(url.path())?\($0)" } ?? url.path()
    } ?? "?"
    return "\(method) \(target)"
}
