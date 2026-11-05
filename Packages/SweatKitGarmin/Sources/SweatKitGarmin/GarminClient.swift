import Foundation

/// A client for Garmin's Personal API: token exchange, activity search, activity
/// summaries and original-file downloads.
///
/// It holds the Personal API key it is given and the access token it obtains,
/// and never writes either anywhere. Where the key comes from is the caller's job.
///
/// Tokens are requested on first use and renewed shortly before their stated
/// expiry. A data call refused with 401 gets one fresh token and one retry, which
/// covers a token that Garmin ended early, such as when the key was deleted.
public actor GarminClient {
    public typealias Observer = @Sendable (GarminExchange) -> Void

    /// A token is renewed this long before its stated expiry, so it does not
    /// lapse between being checked and being used.
    public static let renewalMargin: TimeInterval = 5 * 60

    private let apiKey: String
    private let endpoints: GarminEndpoints
    private let transport: any GarminTransport
    private let now: @Sendable () -> Date
    private let observer: Observer?
    private var token: AccessToken?
    private var pendingToken: Task<Result<AccessToken, GarminError>, Never>?

    /// - Parameter observer: Called after every response, including errors, with
    ///   its status and headers. Holds nothing secret. Useful for rate-limit
    ///   diagnostics.
    public init(
        apiKey: String,
        endpoints: GarminEndpoints = GarminEndpoints(),
        transport: any GarminTransport = URLSessionTransport(),
        now: @escaping @Sendable () -> Date = { Date() },
        observer: Observer? = nil
    ) {
        self.apiKey = apiKey
        self.endpoints = endpoints
        self.transport = transport
        self.now = now
        self.observer = observer
    }

    /// When the current token is treated as expired, or nil before the first one.
    public var tokenExpiry: Date? { token?.expiresAt }

    /// The token response's top-level key names, for diagnosing its undocumented
    /// shape. Never holds values.
    public var tokenResponseKeys: [String]? { token?.keys }

    /// Exchanges the key for a fresh token now. Use it to check a newly entered key.
    public func validateKey() async throws(GarminError) {
        token = nil
        _ = try await currentToken()
    }

    /// One page of the activity search.
    public func activities(_ query: ActivityQuery) async throws(GarminError) -> [ActivitySummary] {
        let (data, response) = try await authorized { token throws(GarminError) in
            try self.endpoints.activities(query, accessToken: token)
        }
        return try decode([ActivitySummary].self, data, status: response.statusCode)
    }

    /// One activity's full summary and metadata.
    public func activity(id: Int64) async throws(GarminError) -> ActivityDetail {
        let (data, response) = try await authorized { token throws(GarminError) in
            try self.endpoints.activity(id: id, accessToken: token)
        }
        return try decode(ActivityDetail.self, data, status: response.statusCode)
    }

    /// The activity's file as Garmin served it, unopened.
    public func originalFile(activityID: Int64) async throws(GarminError) -> ActivityFile {
        let (data, response) = try await authorized { token throws(GarminError) in
            try self.endpoints.originalFile(activityID: activityID, accessToken: token)
        }
        guard !data.isEmpty else {
            throw .unexpectedResponse(UnexpectedResponse(status: response.statusCode, reason: .emptyBody))
        }
        return ActivityFile(
            activityID: activityID,
            data: data,
            contentType: response.value(forHTTPHeaderField: "Content-Type"),
            suggestedFilename: response.value(forHTTPHeaderField: "Content-Disposition").flatMap(filename(fromContentDisposition:))
        )
    }

    // MARK: Tokens

    private func currentToken() async throws(GarminError) -> AccessToken {
        if let token, now() < token.expiresAt.addingTimeInterval(-Self.renewalMargin) {
            return token
        }
        // Concurrent callers share one exchange.
        if let pendingToken {
            return try await pendingToken.value.get()
        }
        let task = Task { await self.exchangeKey() }
        pendingToken = task
        let result = await task.value
        pendingToken = nil
        if case .success(let fresh) = result { token = fresh }
        return try result.get()
    }

    private func exchangeKey() async -> Result<AccessToken, GarminError> {
        do throws(GarminError) {
            let (data, response) = try await perform(endpoints.token(apiKey: apiKey))
            switch response.statusCode {
            case 200..<300:
                return .success(try AccessToken.parse(data, status: response.statusCode, now: now()))
            case 400, 401, 403:
                return .failure(.keyRejected(status: response.statusCode))
            case 429:
                return .failure(.rateLimited(retryAfter: retryAfter(response)))
            default:
                return .failure(.unexpectedResponse(UnexpectedResponse(status: response.statusCode, reason: .status)))
            }
        } catch {
            return .failure(error)
        }
    }

    // MARK: Requests

    private func authorized(_ build: (String) throws(GarminError) -> URLRequest) async throws(GarminError) -> (Data, HTTPURLResponse) {
        let first = try await currentToken()
        var (data, response) = try await perform(build(first.value))
        if response.statusCode == 401 {
            // Garmin ended the token early. Renew once, unless another call already has.
            if token?.value == first.value { token = nil }
            let renewed = try await currentToken()
            (data, response) = try await perform(build(renewed.value))
            if response.statusCode == 401 { throw .tokenExpired }
        }
        switch response.statusCode {
        case 200..<300:
            return (data, response)
        case 429:
            throw .rateLimited(retryAfter: retryAfter(response))
        default:
            throw .unexpectedResponse(UnexpectedResponse(status: response.statusCode, reason: .status))
        }
    }

    private func perform(_ request: URLRequest) async throws(GarminError) -> (Data, HTTPURLResponse) {
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch let error as URLError {
            throw .network(error.code)
        } catch is CancellationError {
            throw .network(.cancelled)
        } catch {
            throw .network(.unknown)
        }
        observer?(GarminExchange(request: request, response: response, bytes: data.count))
        return (data, response)
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data, status: Int) throws(GarminError) -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw .unexpectedResponse(UnexpectedResponse(status: status, reason: .undecodableBody))
        }
    }

    /// `Retry-After` as seconds from now, from either of its two forms.
    private func retryAfter(_ response: HTTPURLResponse) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After")?.trimmingCharacters(in: .whitespaces) else { return nil }
        if let seconds = TimeInterval(value), seconds >= 0 { return seconds }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: value).map { max(0, $0.timeIntervalSince(now())) }
    }
}

/// The `filename` parameter of a `Content-Disposition` header.
func filename(fromContentDisposition header: String) -> String? {
    for part in header.split(separator: ";") {
        let pair = part.trimmingCharacters(in: .whitespaces).split(separator: "=", maxSplits: 1)
        guard pair.count == 2, pair[0].lowercased() == "filename" else { continue }
        let name = pair[1].trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
        return name.isEmpty ? nil : name
    }
    return nil
}
