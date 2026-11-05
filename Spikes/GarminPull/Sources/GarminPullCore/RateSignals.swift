import Foundation

/// What one response said about rate limiting. Garmin documents no limits for
/// the Personal tier, so this looks for every common convention.
public struct RateSignals: Sendable, Equatable {
    /// Headers whose names suggest a limit, quota or retry, lower-cased.
    public var headers: [String: String]
    public var status: Int

    public init(status: Int, headers: [String: String]) {
        self.status = status
        self.headers = headers.reduce(into: [:]) { result, pair in
            let name = pair.key.lowercased()
            if Self.isRateHeader(name) { result[name] = pair.value }
        }
    }

    public var isRateLimited: Bool { status == 429 }

    /// `Retry-After` in seconds, when it is given as a number.
    public var retryAfterSeconds: Double? { headers["retry-after"].flatMap { Double($0.trimmingCharacters(in: .whitespaces)) } }

    static func isRateHeader(_ name: String) -> Bool {
        name == "retry-after"
            || name.contains("ratelimit")
            || name.contains("rate-limit")
            || name.contains("quota")
            || name.contains("throttl")
            || name.hasPrefix("x-ratelimit")
    }
}

/// Every response header, with cookie values hidden. Used for the request log.
public func loggableHeaders(_ headers: [String: String]) -> [String: String] {
    headers.reduce(into: [:]) { result, pair in
        let name = pair.key.lowercased()
        result[name] = (name == "set-cookie" || name == "authorization") ? "<redacted>" : pair.value
    }
}
