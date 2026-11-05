import Foundation

/// Sends one HTTP request. Injected so tests run without a network and callers
/// can add pacing.
public protocol GarminTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// The default transport: an ephemeral `URLSession` with no cookies or cache.
public struct URLSessionTransport: GarminTransport {
    private let session: URLSession

    public init(timeout: TimeInterval = 60) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = timeout
        session = URLSession(configuration: configuration)
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}

/// One request and its response, with nothing secret in it: no `Authorization`
/// value, no cookies and no body. Delivered to the client's observer.
public struct GarminExchange: Sendable, Equatable {
    public var method: String
    /// Path and query, such as `/activity-service/activity/1`.
    public var target: String
    public var status: Int
    public var bytes: Int
    /// Response headers with lower-cased names. `set-cookie` is redacted.
    public var headers: [String: String]

    init(request: URLRequest, response: HTTPURLResponse, bytes: Int) {
        method = request.httpMethod ?? "GET"
        target = loggable(request)
        status = response.statusCode
        self.bytes = bytes
        headers = response.allHeaderFields.reduce(into: [:]) { result, pair in
            let name = "\(pair.key)".lowercased()
            result[name] = name == "set-cookie" ? "<redacted>" : "\(pair.value)"
        }
    }
}

/// A request's path and query, safe to log. Holds no header values.
public func loggable(_ request: URLRequest) -> String {
    guard let url = request.url else { return "" }
    return url.query.map { "\(url.path())?\($0)" } ?? url.path()
}
